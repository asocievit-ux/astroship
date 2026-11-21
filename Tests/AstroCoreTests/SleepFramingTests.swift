import XCTest
import simd
@testable import AstroCore

final class SleepFramingTests: XCTestCase {
    /// 2026-11-20 00:00 TDB — a typical current-era Saturn.
    let jd = 2_461_364.5

    func testComposition() {
        let sun = Ephemeris.position(.sun, jd: jd)
        let saturn = Ephemeris.position(.saturn, jd: jd)
        XCTAssertLessThan(length(sun), 1)   // heliocentric origin
        let pose = SleepFraming.pose(sun: sun, saturn: saturn)

        // Camera is outside Saturn's orbit, looking inward.
        XCTAssertGreaterThan(length(pose.position), length(saturn))
        XCTAssertLessThan(length(pose.lookAt), length(saturn))

        // Saturn large in the lower half; the Sun in the upper half.
        let satEl = SleepFraming.elevationDegrees(of: saturn, camera: pose)
        let sunEl = SleepFraming.elevationDegrees(of: sun, camera: pose)
        XCTAssertLessThan(satEl, -8)
        XCTAssertGreaterThan(satEl, -22)
        XCTAssertGreaterThan(sunEl, 10)
        XCTAssertLessThan(sunEl, 25)

        // Saturn + rings fill a generous part of the frame (not a distant dot).
        let dist = length(saturn - pose.position)
        let ringDeg = deg(atan(140_220 / dist)) * 2
        XCTAssertGreaterThan(ringDeg, 30)
        XCTAssertLessThan(dist, 600_000)
    }
}
