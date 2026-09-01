/// Builds the instructions and per-call input for praise classification.
///
/// Kept free of any framework import so it compiles — and stays under test — on
/// watchOS, tvOS, and toolchains with no Foundation Models SDK, where
/// ``FoundationModelsPraiseClassifier`` does not exist at all.
enum PraisePromptBuilder {

    /// Ceiling on the characters handed to the model.
    ///
    /// `FeedbackSheet`'s `descriptionLimit` only colors the character counter —
    /// it never blocks submission — so the submitted text is unbounded in
    /// practice. Capping here keeps a pasted essay from throwing
    /// `GenerationError.exceededContextWindowSize`, and comfortably clears the
    /// default 1,000-character limit.
    static let inputCharacterLimit = 1200

    /// Marks the removed middle so the model reads a gap rather than a non
    /// sequitur where the two halves meet.
    static let elision = "\n[…]\n"

    /// Session instructions. Phrased as an exclusion list because the failure
    /// that matters is a false positive: prompting someone for a five-star
    /// rating right after they reported a crash.
    static let instructions = """
        You classify feedback a person submitted from inside an app.

        Decide whether the text is exclusively positive praise for the app — \
        expressing only satisfaction, appreciation, or a compliment.

        It is NOT pure praise if the text contains any bug report, crash, \
        problem, complaint, criticism, question, or request for a change or a \
        new feature, or if it mixes positive and negative sentiment. Praise \
        followed by "but", "however", or any qualifier is not pure praise.

        The text may have had its middle removed and replaced with [\u{2026}]. \
        Judge the whole of what remains, including the part after the gap.

        When you are unsure, answer that it is not pure praise.
        """

    /// Labels the two fields so the model can tell a terse title from the body,
    /// then caps the result — keeping both ends and dropping the middle.
    ///
    /// Keeping only the head would be actively wrong here. Feedback front-loads
    /// the compliment and appends the qualifier — "I love this app … but it
    /// crashes every time I export" — so a head-only cap deletes exactly the
    /// clause that disqualifies the text and turns a crash report into praise.
    /// The tail keeps its share of the budget for that reason.
    static func input(title: String, description: String) -> String {
        let combined = """
            Title: \(title)
            Feedback: \(description)
            """
        guard combined.count > inputCharacterLimit else { return combined }

        let budget = inputCharacterLimit - elision.count
        let tailBudget = budget / 3
        let headBudget = budget - tailBudget
        // `prefix`/`suffix` count Characters, so neither cut can split a
        // grapheme cluster (a family emoji, a flag, a combining accent).
        return String(combined.prefix(headBudget)) + elision + String(combined.suffix(tailBudget))
    }
}
