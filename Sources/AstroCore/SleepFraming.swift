import Foundation
import simd

/// Camera pose for Sleep mode: just outside Saturn, looking inward so Saturn sits large in the
/// lower-middle of the frame, the Sun is small in the upper part, and the asteroid belt crosses
/// behind the Sun. Positions are heliocentric ecliptic J2000, kilometres.
public enum SleepFraming {
    /// Behind Saturn, away from the Sun.
    public static let backKm = 320_000.0
    /// North of the Saturn–Sun line, so Saturn falls below centre and the rings tilt.
    public static let heightKm = 200_000.0
    /// A slight side offset so the rings are not seen dead-on.
    public static let sideKm = 90_000.0
    /// Look-at, just ahead of Saturn toward the Sun — keeps Saturn in the lower-middle and the
    /// Sun in the upper part of a 50° field of view.
    public static let lookAheadKm = 280_000.0

    public struct Pose: Equatable, Sendable {
        public var position: V3
        public var lookAt: V3
    }

    public static func pose(sun: V3, saturn: V3) -> Pose {
        let toSun = normalize(sun - saturn)
        let eclUp = V3(0, 0, 1)
        var right = cross(toSun, eclUp)
        if length(right) < 1e-9 { right = V3(1, 0, 0) }
        right = normalize(right)
        // ecliptic-north component perpendicular to the Saturn–Sun line
        let above = normalize(cross(right, toSun))
        let position = saturn - toSun * backKm + above * heightKm + right * sideKm
        let lookAt = saturn + toSun * lookAheadKm
        return Pose(position: position, lookAt: lookAt)
    }

    /// Vertical angle of a point from the camera's look axis, in degrees. Positive is toward
    /// ecliptic north (up on the screen once the scene mapping is applied).
    public static func elevationDegrees(of point: V3, camera: Pose) -> Double {
        let forward = normalize(camera.lookAt - camera.position)
        let worldUp = V3(0, 0, 1)
        var up = worldUp - forward * dot(worldUp, forward)
        if length(up) < 1e-9 { up = V3(0, 1, 0) }
        up = normalize(up)
        let rel = point - camera.position
        return deg(atan2(dot(rel, up), dot(rel, forward)))
    }
}
