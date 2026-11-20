import Foundation
import simd

public enum Kepler {
    /// Gaussian gravitational constant (rad/day) for heliocentric orbits with a in au.
    public static let gaussK = 0.01720209895

    /// Eccentric anomaly for mean anomaly M (rad), e < 1.
    public static func eccentricAnomaly(M: Double, e: Double) -> Double {
        var m = fmod(M, 2 * .pi)
        if m > .pi { m -= 2 * .pi } else if m < -.pi { m += 2 * .pi }
        var E = e < 0.8 ? m : (m >= 0 ? .pi : -.pi)
        for _ in 0..<50 {
            let f = E - e * sin(E) - m
            let d = f / (1 - e * cos(E))
            E -= d
            if abs(d) < 1e-12 { break }
        }
        return E
    }

    /// Position in the orbital plane (x toward perihelion) for semi-major axis a.
    public static func planePosition(a: Double, e: Double, M: Double) -> (Double, Double) {
        let E = eccentricAnomaly(M: M, e: e)
        return (a * (cos(E) - e), a * (1 - e * e).squareRoot() * sin(E))
    }

    /// Rotation from the orbital plane into the reference plane (angles in radians).
    public static func toReference(x: Double, y: Double, argPeri w: Double, node: Double, incl i: Double) -> V3 {
        let cw = cos(w), sw = sin(w), cn = cos(node), sn = sin(node), ci = cos(i), si = sin(i)
        return V3((cw * cn - sw * sn * ci) * x + (-sw * cn - cw * sn * ci) * y,
                  (cw * sn + sw * cn * ci) * x + (-sw * sn + cw * cn * ci) * y,
                  (sw * si) * x + (cw * si) * y)
    }
}

/// Classical elements, heliocentric ecliptic J2000. Angles in degrees, a in au.
public struct OrbitElements: Sendable {
    public var a: Double, e: Double, i: Double, node: Double, argPeri: Double
    /// Time of perihelion passage (JD TDB).
    public var tp: Double

    public init(a: Double, e: Double, i: Double, node: Double, argPeri: Double, tp: Double) {
        self.a = a; self.e = e; self.i = i; self.node = node; self.argPeri = argPeri; self.tp = tp
    }

    public var periodDays: Double { 2 * .pi / (Kepler.gaussK / pow(a, 1.5)) }

    /// Heliocentric position in km.
    public func position(jd: Double) -> V3 {
        let n = Kepler.gaussK / pow(a, 1.5)
        let M = n * (jd - tp)
        let (x, y) = Kepler.planePosition(a: a, e: e, M: M)
        return Kepler.toReference(x: x, y: y, argPeri: rad(argPeri), node: rad(node), incl: rad(i)) * Frames.au
    }

    /// Closed orbit polyline, `count` points uniform in eccentric anomaly (dense near perihelion in angle).
    public func polyline(count: Int) -> [V3] {
        (0..<count).map { k in
            let E = Double(k) / Double(count) * 2 * .pi
            let x = a * (cos(E) - e), y = a * (1 - e * e).squareRoot() * sin(E)
            return Kepler.toReference(x: x, y: y, argPeri: rad(argPeri), node: rad(node), incl: rad(i)) * Frames.au
        }
    }
}
