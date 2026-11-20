import Foundation
import simd

/// The Sun's motion through the Milky Way.
/// Circular speed of the local standard of rest Θ0 = 230 km/s (rounded IAU-era value) plus the Sun's
/// peculiar motion (U, V, W) = (11.1, 12.24, 7.25) km/s (Schönrich, Binney & Dehnen 2010).
public enum GalacticMotion {
    public static let circularSpeed = 230.0
    public static let peculiar = V3(11.1, 12.24, 7.25)
    /// Distance Sun - galactic centre in kpc (GRAVITY 2019: 8.18).
    public static let r0Kpc = 8.2
    public static let kmPerKpc = 3.0856775814913673e16
    /// Sun height above the mid-plane (pc).
    public static let zSunPc = 20.8

    /// Velocity relative to the galactic centre, galactic Cartesian (x to centre, y rotation, z north), km/s.
    public static var velocityGalactic: V3 { V3(peculiar.x, circularSpeed + peculiar.y, peculiar.z) }
    /// The same in ecliptic J2000, km/s.
    public static var velocityEcliptic: V3 { Frames.galToEcl * velocityGalactic }
    public static var speed: Double { length(velocityGalactic) }
    /// One trip around the galactic centre at Θ0 (years). About 220 million years.
    public static var galacticYearYears: Double {
        2 * .pi * r0Kpc * kmPerKpc / circularSpeed / (365.25 * 86_400)
    }
    /// Solar apex relative to nearby stars (direction of the peculiar motion), galactic l, b in degrees.
    public static var apex: (l: Double, b: Double) {
        let v = peculiar
        return (deg(atan2(v.y, v.x)), deg(asin(v.z / length(v))))
    }

    /// Heliocentric position at `jd`, shifted into the frame that moves with the galaxy, expressed relative
    /// to the Sun at `referenceJD` (km). This is the helix: orbit + steady drift.
    public static func galacticOffset(jd: Double, referenceJD: Double) -> V3 {
        velocityEcliptic * ((jd - referenceJD) * 86_400)
    }

    /// Trail for a body: positions over [endJD - duration, endJD] in the galactic frame, relative to the Sun at endJD (km).
    public static func trail(_ id: BodyID, endJD: Double, durationDays: Double, samples: Int) -> [V3] {
        guard samples > 1 else { return [] }
        let v = velocityEcliptic * 86_400
        return (0..<samples).map { k in
            let t = endJD - durationDays * Double(samples - 1 - k) / Double(samples - 1)
            return Ephemeris.position(id, jd: t) + v * (t - endJD)
        }
    }
}
