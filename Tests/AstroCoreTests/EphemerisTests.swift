import XCTest
import simd
@testable import AstroCore

/// Reference vectors: JPL Horizons, 2026-11-20 00:00 TDB, ecliptic J2000, km.
final class EphemerisTests: XCTestCase {
    let jd = 2_461_364.5

    func angle(_ a: V3, _ b: V3) -> Double { deg(acos(max(-1, min(1, dot(a, b) / (length(a) * length(b)))))) }

    func check(_ id: BodyID, _ ref: V3, deg tol: Double, rel: Double, file: StaticString = #filePath, line: UInt = #line) {
        let p = Ephemeris.position(id, jd: jd)
        XCTAssertLessThan(angle(p, ref), tol, "\(id) direction", file: file, line: line)
        XCTAssertLessThan(abs(length(p) - length(ref)) / length(ref), rel, "\(id) distance", file: file, line: line)
    }

    func testPlanets() {
        check(.earth, V3(7.987092595069732e7, 1.244009820683518e8, -8.411944543525577e3), deg: 0.05, rel: 0.001)
        check(.mars, V3(-8.001868543354674e7, 2.276555468113629e8, 6.732868756880328e6), deg: 0.1, rel: 0.002)
        check(.jupiter, V3(-5.640469060033547e8, 5.619855983866776e8, 1.028532471226734e7), deg: 0.2, rel: 0.003)
        check(.neptune, V3(4.462295013868309e9, 2.300393745809387e8, -1.075699600069034e8), deg: 0.2, rel: 0.003)
    }

    func testSmallBodies() {
        check(.pluto, V3(3.006628259631199e9, -4.385726024572298e9, -4.002902682355077e8), deg: 1.0, rel: 0.01)
        check(.ceres, V3(-3.684639781073622e7, 3.922073240984526e8, 1.920360594276419e7), deg: 1.0, rel: 0.01)
        check(.halley, V3(-2.891466937373227e9, 4.110072262103614e9, -1.473138263074067e9), deg: 5.0, rel: 0.05)
    }

    func testMoon() {
        let m = LunarTheory.geocentric(jd: jd)
        let ref = V3(3.827709728652904e5, -2.416044295628577e4, 1.772907575853804e4)
        XCTAssertLessThan(angle(m, ref), 0.3)
        XCTAssertLessThan(abs(length(m) - length(ref)), 1500)
    }

    func testSatellitesAtFitEpoch() {
        let io = Ephemeris.relativeToParent(.io, jd: jd)
        XCTAssertLessThan(angle(io, V3(-4.231644016859349e5, 1.558261840395834e4, -5.510462449771112e3)), 1.0)
        let titan = Ephemeris.relativeToParent(.titan, jd: jd)
        XCTAssertLessThan(angle(titan, V3(2.896251590706939e5, 1.040713554710573e6, -5.654169999412115e5)), 1.0)
    }

    func testCatalogueOrder() {
        for (k, b) in Catalog.all.enumerated() { XCTAssertEqual(b.id.rawValue, k) }
        XCTAssertEqual(Catalog.all.count, BodyID.allCases.count)
    }

    func testGalacticMotion() {
        XCTAssertEqual(GalacticMotion.speed, 242.6, accuracy: 0.5)
        XCTAssertEqual(GalacticMotion.galacticYearYears / 1e6, 219, accuracy: 5)
        // Direction of galactic rotation (l = 90, b = 0) is in Cygnus, about RA 318, Dec +48.
        let dirEq = Frames.eqToGal.transposed * V3(0, 1, 0)
        let ra = deg(atan2(dirEq.y, dirEq.x)) + 360, dec = deg(asin(dirEq.z))
        XCTAssertEqual(ra.truncatingRemainder(dividingBy: 360), 318, accuracy: 1)
        XCTAssertEqual(dec, 48.3, accuracy: 1)
    }

    func testClock() {
        var now = 1_000_000.0
        let clock = SimClock(wall: { now })
        let start = clock.jd
        clock.rate = 86_400
        now += 2
        XCTAssertEqual(clock.jd - start, 2, accuracy: 1e-6)
        clock.rate = 0
        now += 5
        XCTAssertEqual(clock.jd - start, 2, accuracy: 1e-6)
    }

    func testOrientationIsRotation() {
        let st = Ephemeris.state(jd: jd)
        for b in Catalog.all {
            let m = Ephemeris.orientation(b.id, state: st)
            let i = m * m.transposed
            XCTAssertEqual(i.r0.x, 1, accuracy: 1e-9); XCTAssertEqual(i.r1.y, 1, accuracy: 1e-9); XCTAssertEqual(i.r0.y, 0, accuracy: 1e-9)
        }
    }
}
