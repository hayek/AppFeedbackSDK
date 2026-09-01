/// Decides whether submitted feedback is unqualified praise for the app.
///
/// Deliberately non-throwing: this sits on a purely optional path that runs
/// *after* a report has already been delivered, so there is no failure a caller
/// could usefully handle. Implementations swallow every error and answer
/// `false` — the effect of a hiccup is that no rating prompt appears, which is
/// exactly the behavior on a device without Apple Intelligence.
///
/// The seam exists so ``ReviewPromptCoordinator`` can be tested with a stub on
/// platforms and toolchains where Foundation Models does not exist.
protocol PraiseClassifying: Sendable {

    /// - Returns: `true` only when the text is exclusively positive, with no
    ///   bug, complaint, question, or request mixed in.
    func isPurePraise(title: String, description: String) async -> Bool
}
