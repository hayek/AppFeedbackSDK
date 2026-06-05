/// Locale-invariant, deterministic human-readable byte-count formatter.
///
/// A drop-in replacement for `ByteCountFormatter` (wired into the issue-body
/// formatter in a later step), whose output varies by locale and OS version
/// (`kB` vs `KB`, non-breaking spaces, decimal grouping) and therefore cannot
/// be reproduced byte-for-byte by the Android (Kotlin) and Web (TypeScript)
/// ports. The attachment size string is part of the wire contract (see the
/// `appfeedback-spec` wire-format document), so it must be pinned to a single
/// algorithm every platform can replicate exactly.
///
/// Decimal (1000-based) units, matching `IssueBodyParser.parseHumanByteCount`:
/// - `< 1000` bytes → integer bytes, e.g. `"512 B"`.
/// - `KB`/`MB`/`GB` → at most one decimal place, half-up rounded, a trailing
///   `.0` dropped, a single ASCII space before the unit, e.g. `"1.2 KB"`,
///   `"2 MB"`.
///
/// Negative inputs clamp to `0`. Attachment sizes are validated to a small cap
/// upstream, so the integer arithmetic below cannot overflow in practice.
enum DeterministicByteCount {
    static func string(_ bytes: Int) -> String {
        let b = min(max(0, bytes), 100_000_000_000_000)
        let units: [(name: String, factor: Int)] = [
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
        ]
        for unit in units where b >= unit.factor {
            // Tenths of `unit`, rounded half-up using integer arithmetic so the
            // result never depends on floating-point or locale behaviour.
            let tenths = (b * 10 + unit.factor / 2) / unit.factor
            let whole = tenths / 10
            let frac = tenths % 10
            return frac == 0 ? "\(whole) \(unit.name)" : "\(whole).\(frac) \(unit.name)"
        }
        return "\(b) B"
    }
}
