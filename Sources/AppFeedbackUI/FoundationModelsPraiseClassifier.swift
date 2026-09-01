#if canImport(FoundationModels)
import FoundationModels

/// Classifies feedback text with Apple Intelligence's on-device model.
///
/// The whole file is behind `canImport` because `FoundationModels` is absent
/// from the watchOS and tvOS SDKs entirely — and from any Xcode older than 26 —
/// so an `@available` annotation alone would not compile there.
///
/// Nothing leaves the device: `SystemLanguageModel.default` is the local
/// on-device model, and the text is never sent anywhere for this check. (The
/// report itself still goes to the configured transport, exactly as before.)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelsPraiseClassifier: PraiseClassifying {

    /// The verdict the model must choose from.
    ///
    /// Guided generation constrains decoding to these three cases, so an
    /// unparsable answer is not merely unlikely — it is unrepresentable. Three
    /// cases rather than a yes/no because naming the disqualifying category
    /// gives the model somewhere to put mixed feedback other than "yes".
    ///
    /// Only the type-level `description` below and the case *names* reach the
    /// model; the schema carries no per-case prose. Anything the model needs to
    /// know about how to weigh a case belongs in
    /// ``PraisePromptBuilder/instructions``, not in a comment here.
    @Generable(description: "Whether app feedback is exclusively positive praise")
    enum Verdict {
        case purePraise
        case mentionsProblemComplaintOrRequest
        case neutralOrUnclear
    }

    func isPurePraise(title: String, description: String) async -> Bool {
        // Every unavailable reason — ineligible hardware, Apple Intelligence
        // switched off, model still downloading — is treated the same: skip, do
        // not wait, do not retry. That is what makes the no-Apple-Intelligence
        // path identical to the pre-feature behavior.
        guard case .available = SystemLanguageModel.default.availability else { return false }

        do {
            let session = LanguageModelSession(instructions: PraisePromptBuilder.instructions)
            let response = try await session.respond(
                to: PraisePromptBuilder.input(title: title, description: description),
                generating: Verdict.self,
                // Greedy sampling: for a given model version the same
                // feedback gets the same verdict. A rating prompt that appeared
                // at random for identical text would be untriageable. Apple
                // makes no cross-version guarantee, so this pins reproducibility
                // on a device, not across OS updates.
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content == .purePraise
        } catch {
            // Guardrail trips, refusals, rate limiting, context overflow, and
            // `unsupportedLanguageOrLocale` for text the on-device model does
            // not handle all land here. Staying quiet is always the safe answer.
            return false
        }
    }
}
#endif
