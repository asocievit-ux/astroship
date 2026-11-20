import Foundation
import simd

/// Regular moon as a circular orbit fitted to JPL Horizons at epoch 2026-11-20 0h TDB:
/// orbit pole and the moon's direction at the epoch come from the Horizons state vector
/// (planetocentric, ecliptic J2000); mean distance and sidereal period from the JPL mean-element
/// tables (ssd.jpl.nasa.gov/sats/elem). Accurate to a few degrees for decades around the epoch,
/// which is what a viewer needs; eccentricity and precession are ignored.
public struct SatelliteElements: Sendable {
    public static let fitEpoch = 2_461_364.5
    public var aKm: Double
    public var periodDays: Double
    /// Ecliptic unit vectors: orbit normal (direction of motion by the right-hand rule) and position at the epoch.
    public var pole: V3
    public var x0: V3

    public init(aKm: Double, periodDays: Double, pole: V3, x0: V3) {
        self.aKm = aKm; self.periodDays = periodDays
        self.pole = normalize(pole)
        let p = self.pole
        self.x0 = normalize(x0 - p * dot(x0, p))
    }

    var y0: V3 { cross(pole, x0) }

    /// Planetocentric position, ecliptic J2000, km.
    public func position(jd: Double) -> V3 {
        let th = 2 * .pi * (jd - Self.fitEpoch) / periodDays
        return (x0 * cos(th) + y0 * sin(th)) * aKm
    }

    public func polyline(jd: Double, count: Int) -> [V3] {
        let y = y0
        return (0..<count).map { k in
            let th = Double(k) / Double(count) * 2 * .pi
            return (x0 * cos(th) + y * sin(th)) * aKm
        }
    }
}
