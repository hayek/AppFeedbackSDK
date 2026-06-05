import XCTest
@testable import AppFeedbackCore

final class DeterministicByteCountTests: XCTestCase {

    func test_bytes_below_one_thousand_render_as_integer_bytes() {
        XCTAssertEqual(DeterministicByteCount.string(0), "0 B")
        XCTAssertEqual(DeterministicByteCount.string(512), "512 B")
        XCTAssertEqual(DeterministicByteCount.string(999), "999 B")
    }

    func test_negative_clamps_to_zero() {
        XCTAssertEqual(DeterministicByteCount.string(-5), "0 B")
    }

    func test_kilobytes_round_half_up_to_one_decimal() {
        XCTAssertEqual(DeterministicByteCount.string(1000), "1 KB")
        XCTAssertEqual(DeterministicByteCount.string(1234), "1.2 KB")
        XCTAssertEqual(DeterministicByteCount.string(1500), "1.5 KB")
        XCTAssertEqual(DeterministicByteCount.string(4096), "4.1 KB")
        XCTAssertEqual(DeterministicByteCount.string(319_488), "319.5 KB")
        XCTAssertEqual(DeterministicByteCount.string(1050), "1.1 KB")
    }

    func test_unit_selected_by_magnitude_before_rounding_no_carry() {
        // 999_950 is below the 1_000_000 (MB) threshold, so the KB unit is
        // chosen first; rounding within KB yields 1000.0, rendered "1000 KB".
        // It deliberately does NOT carry up to "1 MB".
        XCTAssertEqual(DeterministicByteCount.string(999_950), "1000 KB")
    }

    func test_megabytes_and_gigabytes() {
        XCTAssertEqual(DeterministicByteCount.string(1_000_000), "1 MB")
        XCTAssertEqual(DeterministicByteCount.string(1_500_000), "1.5 MB")
        XCTAssertEqual(DeterministicByteCount.string(2_500_000), "2.5 MB")
        XCTAssertEqual(DeterministicByteCount.string(1_000_000_000), "1 GB")
    }

    func test_trailing_zero_decimal_is_dropped() {
        XCTAssertEqual(DeterministicByteCount.string(2_000_000), "2 MB")
    }
}
