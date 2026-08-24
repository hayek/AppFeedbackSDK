// Sources/AppFeedbackUI/FeedbackTypeCard.swift
import SwiftUI

/// One of the two feedback-type tiles in the sheet's selector.
///
/// Its copy is themable, so the card can't assume the defaults' length: an adopter's
/// "Bug / Issue" is wider than "Bug", and a localized string wider still. Label and
/// tagline therefore wrap instead of truncating, and the card expands to whatever height
/// the row hands it — the row sizes to its tallest card, so both come out the same.
struct FeedbackTypeCard: View {
    let icon: String
    let accent: Color
    let label: String
    let tagline: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : accent)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? accent : accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // Fill the row's width and height so the two cards match: equal share of the
            // row across, and the tallest card's height down.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PlatformColor.controlBackground.opacity(isSelected ? 1.0 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.55) : PlatformColor.separator.opacity(0.6),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
