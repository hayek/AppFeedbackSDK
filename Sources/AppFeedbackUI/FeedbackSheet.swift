import SwiftUI
import AppFeedbackCore
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
#if os(iOS)
import PhotosUI
#endif

/// A drop-in feedback form, presentable from any SwiftUI view via `.sheet(...)`.
///
/// The sheet handles the full flow: type selection, validated fields, async
/// submission, success animation, and dismissal. Submission state is managed
/// internally — your code receives a callback only after the network
/// round-trip completes or fails.
///
/// ```swift
/// .sheet(isPresented: $showFeedback) {
///     FeedbackSheet(
///         client: feedbackClient,
///         theme: .default,
///         onSubmit: { issueNumber in /* track success */ },
///         onError:  { error in /* track failure */ }
///     )
/// }
/// ```
///
/// All visible copy comes from ``FeedbackTheme/copy`` and accent colors come
/// from ``FeedbackTheme/bugAccent`` / ``FeedbackTheme/featureAccent``. See
/// <doc:Theming> for the customization surface, and <doc:Localization> for
/// the recommended way to wire localized strings.
///
/// ## Sizing
///
/// On macOS and visionOS the sheet uses a fixed `480 × 660` frame. On iOS
/// and iPadOS it fills the system sheet presentation naturally. watchOS and
/// tvOS adapt to platform conventions.
///
/// ## Callbacks
///
/// `onSubmit` and `onError` are `@MainActor` closures so you can touch UI
/// state inside them. They fire once per submission attempt — after the
/// transport returns or throws.
public struct FeedbackSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let client: FeedbackClient
    private let theme: FeedbackTheme
    private let descriptionLimit: Int
    private let extraFields: [String: String]
    private let onSubmit: @MainActor (Int) -> Void
    private let onError: @MainActor (any Error) -> Void
    private let onSubmitReport: (@MainActor (FeedbackReport, Int) -> Void)?

    @State private var title = ""
    @State private var description = ""
    @State private var contactEmail = ""
    @State private var pendingAttachments: [PendingAttachmentUI] = []
    @State private var attachmentError: String?
    @State private var isDragTargeted: Bool = false
    @State private var showFileImporter = false
    #if os(iOS)
    @State private var showPhotoPicker = false
    @State private var photoPicks: [PhotosPickerItem] = []
    #endif
    @State private var selectedType: FeedbackType = .bug

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var submittedIssueNumber: Int?
    @State private var showError = false
    @State private var showValidationError = false
    @State private var checkmarkScale: CGFloat = 0.4
    @State private var checkmarkOpacity: Double = 0
    @State private var successContentVisible = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, description, email }

    /// Builds a feedback sheet.
    ///
    /// - Parameters:
    ///   - client: The configured ``FeedbackClient`` used to submit the
    ///     report. Build it once at app start and share across sheets.
    ///   - theme: Visual + copy customization. Defaults to ``FeedbackTheme/default``.
    ///   - descriptionLimit: Character limit shown next to the description
    ///     label. The counter turns red over the limit but does **not**
    ///     block submission — enforce hard limits in your transport if
    ///     needed. Defaults to `1000`.
    ///   - onSubmit: Called on the main actor after a successful submission,
    ///     with the backend-assigned identifier (GitHub issue number for
    ///     ``GitHubDirectTransport``).
    ///   - onError: Called on the main actor when the transport throws. The
    ///     sheet also displays an alert with `error.localizedDescription`,
    ///     so this callback is mainly for analytics / logging.
    ///   - onSubmitReport: Optional. Called on the main actor after a
    ///     successful submission with the full ``FeedbackReport`` (including
    ///     its ``FeedbackType``) and the backend identifier. Use this when
    ///     `onSubmit`'s issue number alone is not enough — e.g. to log which
    ///     feedback type was submitted. Fires alongside `onSubmit`.
    public init(
        client: FeedbackClient,
        theme: FeedbackTheme = .default,
        descriptionLimit: Int = 1000,
        extraFields: [String: String] = [:],
        onSubmit: @escaping @MainActor (Int) -> Void = { _ in },
        onError: @escaping @MainActor (any Error) -> Void = { _ in },
        onSubmitReport: (@MainActor (FeedbackReport, Int) -> Void)? = nil
    ) {
        self.client = client
        self.theme = theme
        self.descriptionLimit = descriptionLimit
        self.extraFields = extraFields
        self.onSubmit = onSubmit
        self.onError = onError
        self.onSubmitReport = onSubmitReport
    }

    public var body: some View {
        ZStack {
            if submittedIssueNumber == nil {
                formContent
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            } else {
                successView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.04)),
                        removal: .opacity
                    ))
            }
        }
        #if os(macOS) || os(visionOS)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 660, maxHeight: 660)
        #endif
        .background(PlatformColor.windowBackground)
        .background(
            heroGradient
                .opacity(submittedIssueNumber == nil ? 0.06 : 0.10)
                .blur(radius: 60)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: submittedIssueNumber)
        )
        .alert(theme.copy.errorAlertTitle, isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Per-type styling

    /// All per-type visuals + copy in one place: hero, type selector, and the
    /// success ring all read from this so adding a new ``FeedbackType`` only
    /// requires updating one switch.
    private struct TypeStyle {
        let icon: String
        let accent: Color
        let gradient: [Color]
        let label: String
        let tagline: String
        let subtitle: String
    }

    private func style(for type: FeedbackType) -> TypeStyle {
        switch type {
        case .bug:
            return TypeStyle(
                icon: "ant.fill",
                accent: theme.bugAccent,
                gradient: theme.bugGradient ?? [theme.bugAccent, theme.bugAccent.opacity(0.55)],
                label: theme.copy.bugLabel,
                tagline: theme.copy.bugTagline,
                subtitle: theme.copy.bugSubtitle
            )
        case .featureRequest:
            return TypeStyle(
                icon: "sparkles",
                accent: theme.featureAccent,
                gradient: theme.featureGradient ?? [theme.featureAccent, theme.featureAccent.opacity(0.55)],
                label: theme.copy.featureLabel,
                tagline: theme.copy.featureTagline,
                subtitle: theme.copy.featureSubtitle
            )
        }
    }

    private var selectedStyle: TypeStyle { style(for: selectedType) }

    private var heroGradient: LinearGradient {
        LinearGradient(
            colors: selectedStyle.gradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    typeSelector
                    titleCard
                    descriptionCard
                    emailCard
                    attachmentsCard
                    privacyNotice
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            #if os(macOS)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            #endif
            .background(PasteHandler { pasteImage() })
            footer
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(heroGradient)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)

                Image(systemName: selectedStyle.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: selectedType)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.copy.headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(selectedStyle.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: selectedType)
            }
            Spacer()
        }
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        HStack(spacing: 10) {
            typeCard(for: .bug)
            typeCard(for: .featureRequest)
        }
        // Sizes the row to the taller card; each card then fills that height, so copy
        // long enough to wrap in one card no longer leaves the other short.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func typeCard(for type: FeedbackType) -> some View {
        let s = style(for: type)
        return FeedbackTypeCard(
            icon: s.icon,
            accent: s.accent,
            label: s.label,
            tagline: s.tagline,
            isSelected: selectedType == type,
            action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    selectedType = type
                }
            }
        )
    }

    // MARK: - Field cards

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }

    private func fieldSurface<V: View>(focused: Bool, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PlatformColor.textBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        focused ? Color.accentColor.opacity(0.65) : PlatformColor.separator.opacity(0.7),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: focused)
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(theme.copy.titleLabel, icon: "textformat")
            fieldSurface(focused: focusedField == .title) {
                TextField(theme.copy.titlePlaceholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focusedField, equals: .title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel(theme.copy.descriptionLabel, icon: "text.alignleft")
                Spacer()
                Text("\(description.count)/\(descriptionLimit)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(description.count > descriptionLimit ? .red : .secondary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: description.count)
            }

            fieldSurface(focused: focusedField == .description) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $description)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .focused($focusedField, equals: .description)
                        .frame(minHeight: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)

                    if description.isEmpty {
                        Text(theme.copy.descriptionPlaceholder)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionLabel(theme.copy.emailLabel, icon: "envelope")
                Text(theme.copy.emailOptionalBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                Spacer()
            }

            fieldSurface(focused: focusedField == .email) {
                TextField(theme.copy.emailPlaceholder, text: $contactEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focusedField, equals: .email)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    #endif
            }

            Text(theme.copy.emailHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel(theme.copy.attachmentsLabel, icon: "paperclip")
                Spacer()
                addAttachmentControl
            }
            if !pendingAttachments.isEmpty {
                attachmentStrip
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.png, .jpeg, .heic, .gif, .plainText, .json, .pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                ingest(urls: urls)
            }
        }
        #if os(iOS)
        // `.current` keeps each pick in its own format, so the MIME derived from
        // `supportedContentTypes` matches the bytes. HEIC→JPEG then happens in one
        // predictable place — `ImagePreprocessor`, on the submit path — which also
        // strips the GPS tags a camera-roll photo carries.
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPicks,
            maxSelectionCount: freeAttachmentSlots,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: photoPicks) { _, picks in
            guard !picks.isEmpty else { return }
            Task { await ingest(picks: picks) }
        }
        #endif
    }

    /// Both pickers cap their own selection at what the sheet can still hold, so a pick
    /// can't silently overshoot the 3-attachment limit.
    private var freeAttachmentSlots: Int {
        max(0, FeedbackAttachmentValidator.maxCount - pendingAttachments.count)
    }

    /// On iOS the Add button opens a source menu — the file importer can't reach the
    /// camera roll, which is where a screenshot lives, and the photo picker can't reach
    /// iCloud Drive. Every other platform has one source, so it opens the importer
    /// directly rather than growing a one-item menu.
    @ViewBuilder
    private var addAttachmentControl: some View {
        #if os(iOS)
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label(theme.copy.attachPhotoLibraryLabel, systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label(theme.copy.attachFilesLabel, systemImage: "folder")
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(freeAttachmentSlots == 0)
        #else
        Button {
            showFileImporter = true
        } label: {
            Label("Add", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(freeAttachmentSlots == 0)
        #endif
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { att in
                    PendingAttachmentTile(attachment: att, onRemove: {
                        pendingAttachments.removeAll { $0.id == att.id }
                        revalidate()
                    })
                }
            }
        }
        .frame(height: 64)
    }

    private var privacyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "desktopcomputer.and.macbook")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(theme.copy.privacyNotice)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)

            HStack(spacing: 12) {
                if showValidationError, let message = missingFieldsMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Color(red: 0.92, green: 0.30, blue: 0.36))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer()

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button(action: submit) {
                    HStack(spacing: 6) {
                        Text(theme.copy.submitButton)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(minWidth: 96)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSubmitting || attachmentError != nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .animation(.easeInOut(duration: 0.2), value: showValidationError)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(heroGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Circle()
                    .stroke(heroGradient, lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(checkmarkScale * 1.1)
                    .opacity(checkmarkOpacity * 0.4)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

            VStack(spacing: 8) {
                Text(theme.copy.successTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(theme.copy.successMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                if let issue = submittedIssueNumber {
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Issue #\(issue)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .padding(.top, 4)
                }
            }
            .opacity(successContentVisible ? 1 : 0)
            .offset(y: successContentVisible ? 0 : 8)

            Spacer()

            Button(action: { dismiss() }) {
                Text(theme.copy.doneButton)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 120)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .opacity(successContentVisible ? 1 : 0)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                successContentVisible = true
            }
        }
    }

    // MARK: - Validation + submit

    private var missingFieldsMessage: String? {
        var missing: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(theme.copy.titleFieldName) }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(theme.copy.descriptionFieldName) }
        guard !missing.isEmpty else { return nil }
        return theme.copy.validationPrompt(forMissing: missing)
    }

    /// Builds the ``FeedbackReport`` submitted by ``submit()``. Pulled out as a
    /// `static` helper so the email-trimming/nil-coalescing and `extraFields`
    /// forwarding can be unit-tested without standing up the SwiftUI view.
    static func makeReport(
        type: FeedbackType, title: String, description: String,
        contactEmail: String, attachments: [FeedbackAttachment], extraFields: [String: String]
    ) -> FeedbackReport {
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedbackReport(
            type: type, title: title, description: description,
            contactEmail: trimmedEmail.isEmpty ? nil : trimmedEmail,
            extraFields: extraFields, attachments: attachments
        )
    }

    private func submit() {
        // Trim so a whitespace-only title/description can't pass validation and
        // a whitespace-only email doesn't emit a bogus "Contact Email" block;
        // also keeps the submitted issue free of leading/trailing whitespace.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty || trimmedDescription.isEmpty {
            withAnimation { showValidationError = true }
            return
        }
        showValidationError = false

        let modeled = pendingAttachments.map {
            FeedbackAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        let report = Self.makeReport(
            type: selectedType,
            title: trimmedTitle,
            description: trimmedDescription,
            contactEmail: trimmedEmail,
            attachments: modeled,
            extraFields: extraFields
        )

        Task { @MainActor in
            isSubmitting = true
            do {
                let issueNumber = try await client.submit(report)
                // Drop the spinner before flipping to the success view, otherwise
                // the footer's ProgressView briefly overlaps the success transition.
                isSubmitting = false
                focusedField = nil
                withAnimation(.easeInOut(duration: 0.45)) {
                    submittedIssueNumber = issueNumber
                }
                onSubmit(issueNumber)
                onSubmitReport?(report, issueNumber)
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
                showError = true
                onError(error)
            }
        }
    }
    // MARK: - Paste (macOS)

    private func pasteImage() {
        #if os(macOS)
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], let img = images.first {
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let idx = pendingAttachments.count + 1
                pendingAttachments.append(PendingAttachmentUI(
                    filename: "pasted-image-\(idx).png",
                    mimeType: "image/png",
                    data: png,
                    thumbnail: img
                ))
                revalidate()
            }
        }
        #endif
    }

    // MARK: - Drag-and-drop (macOS)

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) {
        let collector = URLCollector()
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [collector] in
            ingest(urls: collector.urls)
        }
    }
    #endif

    // MARK: - Attachment helpers

    private func ingest(urls: [URL]) {
        for url in urls {
            guard pendingAttachments.count < FeedbackAttachmentValidator.maxCount else { break }
            // File-importer URLs are bookmark-based security-scoped URLs, so
            // `startAccessingSecurityScopedResource()` returns true and must be
            // balanced. Drag-and-dropped URLs instead carry a transient sandbox
            // drag exception and are NOT security-scoped, so the same call
            // returns false even though the file is readable — guarding on it
            // silently dropped every drag. Attempt access, read regardless, and
            // only stop accessing when we actually started.
            let didStartScope = url.startAccessingSecurityScopedResource()
            defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = mimeType(for: url)
            let thumb: PlatformImage? = mime.hasPrefix("image/") ? PlatformImage(data: data) : nil
            pendingAttachments.append(PendingAttachmentUI(
                filename: url.lastPathComponent,
                mimeType: mime,
                data: data,
                thumbnail: thumb
            ))
        }
        revalidate()
    }

    #if os(iOS)
    /// Loads each pick's bytes in order, naming as it goes so names stay unique across
    /// the batch. Unlike `ingest(urls:)` these bytes aren't preprocessed here — the
    /// submit path runs `ImagePreprocessor` for every attachment, so EXIF/GPS stripping
    /// and HEIC→JPEG happen once, in one place.
    private func ingest(picks: [PhotosPickerItem]) async {
        var used = Set(pendingAttachments.map(\.filename))
        var dropped = 0
        for pick in picks {
            guard pendingAttachments.count < FeedbackAttachmentValidator.maxCount else { break }
            guard let data = try? await pick.loadTransferable(type: Data.self) else {
                // Named, not skipped: to someone who just tapped a photo, a silent drop
                // reads as a broken button.
                dropped += 1
                continue
            }
            let descriptor = PhotoAttachmentNaming.descriptor(
                for: pick.supportedContentTypes.first,
                avoiding: used
            )
            used.insert(descriptor.filename)
            pendingAttachments.append(PendingAttachmentUI(
                filename: descriptor.filename,
                mimeType: descriptor.mimeType,
                data: data,
                thumbnail: PlatformImage(data: data)
            ))
        }
        revalidate()
        // Set after revalidate, which would clear it. A validator complaint about what
        // did land is the more actionable message, so it wins.
        if dropped > 0, attachmentError == nil {
            attachmentError = dropped == 1
                ? "Couldn\u{2019}t load that photo."
                : "Couldn\u{2019}t load \(dropped) photos."
        }
        photoPicks = []
    }
    #endif

    private func revalidate() {
        let modeled = pendingAttachments.map {
            FeedbackAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        do {
            try FeedbackAttachmentValidator.validate(modeled)
            attachmentError = nil
        } catch let err as FeedbackAttachmentError {
            attachmentError = humanMessage(for: err)
        } catch {
            attachmentError = "Attachment error: \(error.localizedDescription)"
        }
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func humanMessage(for error: FeedbackAttachmentError) -> String {
        switch error {
        case .tooManyAttachments(let limit, _): return "At most \(limit) attachments."
        case .fileTooLarge(let name, _, let limit):
            return "\(name) exceeds \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
        case .totalSizeTooLarge(_, let limit):
            return "Total exceeds \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
        case .unsupportedMimeType(let name, _): return "\(name): unsupported type."
        case .imageProcessingFailed(let name): return "\(name) could not be processed."
        }
    }
}

struct PendingAttachmentUI: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let thumbnail: PlatformImage?

    static func == (lhs: PendingAttachmentUI, rhs: PendingAttachmentUI) -> Bool { lhs.id == rhs.id }
}

private struct PendingAttachmentTile: View {
    let attachment: PendingAttachmentUI
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = attachment.thumbnail {
                    Image(platformImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(attachment.filename)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var icon: String {
        switch attachment.mimeType {
        case "application/pdf": return "doc.fill"
        case "application/json": return "curlybraces"
        default: return "doc.text"
        }
    }
}

#if os(macOS)
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []
    var urls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _urls
    }
    func append(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        _urls.append(url)
    }
}

private struct PasteHandler: NSViewRepresentable {
    let onPaste: () -> Void
    func makeNSView(context: Context) -> NSView { PasteCatcherView(onPaste: onPaste) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class PasteCatcherView: NSView {
    let onPaste: () -> Void
    init(onPaste: @escaping () -> Void) {
        self.onPaste = onPaste
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            onPaste()
        } else {
            super.keyDown(with: event)
        }
    }
}
#else
private struct PasteHandler: View {
    let onPaste: () -> Void
    var body: some View { Color.clear }
}
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
