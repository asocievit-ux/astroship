import Foundation
import simd

public typealias V3 = SIMD3<Double>

@inline(__always) public func rad(_ d: Double) -> Double { d * .pi / 180 }
@inline(__always) public func deg(_ r: Double) -> Double { r * 180 / .pi }

// dot / cross / length / normalize for V3 come from the simd module (all Apple platforms).

/// Row-major 3x3 matrix in Double. Kept independent of simd matrix types so the core stays portable.
public struct Mat3: Equatable, Sendable {
    public var r0: V3, r1: V3, r2: V3
    public init(_ r0: V3, _ r1: V3, _ r2: V3) { self.r0 = r0; self.r1 = r1; self.r2 = r2 }
    public static let identity = Mat3(V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1))

    public static func * (m: Mat3, v: V3) -> V3 { V3(dot(m.r0, v), dot(m.r1, v), dot(m.r2, v)) }
    public static func * (a: Mat3, b: Mat3) -> Mat3 {
        let t = b.transposed
        return Mat3(V3(dot(a.r0, t.r0), dot(a.r0, t.r1), dot(a.r0, t.r2)),
                    V3(dot(a.r1, t.r0), dot(a.r1, t.r1), dot(a.r1, t.r2)),
                    V3(dot(a.r2, t.r0), dot(a.r2, t.r1), dot(a.r2, t.r2)))
    }
    public var transposed: Mat3 {
        Mat3(V3(r0.x, r1.x, r2.x), V3(r0.y, r1.y, r2.y), V3(r0.z, r1.z, r2.z))
    }
    /// Active rotations (right-handed).
    public static func rx(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(V3(1, 0, 0), V3(0, c, -s), V3(0, s, c))
    }
    public static func ry(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(V3(c, 0, s), V3(0, 1, 0), V3(-s, 0, c))
    }
    public static func rz(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(V3(c, -s, 0), V3(s, c, 0), V3(0, 0, 1))
    }
    /// Columns are the images of the basis vectors.
    public var columns: (V3, V3, V3) { let t = transposed; return (t.r0, t.r1, t.r2) }
}

/// Fixed reference frames. All ephemeris output is heliocentric ecliptic J2000 in kilometres.
public enum Frames {
    public static let au = 149_597_870.7
    public static let obliquityJ2000 = rad(23.4392911)
    /// ecliptic = eqToEcl * equatorial (ICRF)
    public static let eqToEcl = Mat3.rx(-obliquityJ2000)
    public static let eclToEq = Mat3.rx(obliquityJ2000)
    /// galactic = eqToGal * equatorial (ICRS)
    public static let eqToGal = Mat3(
        V3(-0.0548755604162154, -0.8734370902348850, -0.4838350155487132),
        V3(0.4941094278755837, -0.4448296299600112, 0.7469822444972189),
        V3(-0.8676661490190047, -0.1980763734312015, 0.4559837761750669))
    public static let galToEcl = eqToEcl * eqToGal.transposed
    public static let eclToGal = galToEcl.transposed
    /// Renderer axes: y up = ecliptic north. scene = (x, z, -y). A proper rotation.
    public static let eclToScene = Mat3(V3(1, 0, 0), V3(0, 0, 1), V3(0, -1, 0))

    /// Unit vector in equatorial J2000 for right ascension / declination in degrees.
    public static func equatorial(raDeg: Double, decDeg: Double) -> V3 {
        let a = rad(raDeg), d = rad(decDeg)
        return V3(cos(d) * cos(a), cos(d) * sin(a), sin(d))
    }
}
