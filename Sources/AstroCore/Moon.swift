import Foundation
import simd

/// Geocentric Moon from the main periodic terms of ELP-2000/82 as tabulated by Meeus
/// (Astronomical Algorithms, ch. 47), truncated. Accuracy about 0.1 deg, enough for a viewer.
public enum LunarTheory {
    // (D, M, M', F, coefficient)  longitude in 1e-6 deg, distance in metres
    private static let lr: [(Double, Double, Double, Double, Double, Double)] = [
        (0, 0, 1, 0, 6288774, -20905355), (2, 0, -1, 0, 1274027, -3699111), (2, 0, 0, 0, 658314, -2955968),
        (0, 0, 2, 0, 213618, -569925), (0, 1, 0, 0, -185116, 48888), (0, 0, 0, 2, -114332, -3149),
        (2, 0, -2, 0, 58793, 246158), (2, -1, -1, 0, 57066, -152138), (2, 0, 1, 0, 53322, -170733),
        (2, -1, 0, 0, 45758, -204586), (0, 1, -1, 0, -40923, -129620), (1, 0, 0, 0, -34720, 108743),
        (0, 1, 1, 0, -30383, 104755), (2, 0, 0, -2, 15327, 10321), (0, 0, 1, 2, -12528, 0),
        (0, 0, 1, -2, 10980, 79661), (4, 0, -1, 0, 10675, -34782), (0, 0, 3, 0, 10034, -23210),
        (4, 0, -2, 0, 8548, -21636), (2, 1, -1, 0, -7888, 24208), (2, 1, 0, 0, -6766, 30824),
        (1, 0, -1, 0, -5163, -8379), (1, 1, 0, 0, 4987, -16675), (2, -1, 1, 0, 4036, -12831),
        (2, 0, 2, 0, 3994, -10445), (4, 0, 0, 0, 3861, -11650), (2, 0, -3, 0, 3665, 14403),
        (0, 1, -2, 0, -2689, -7003), (2, 0, -1, 2, -2602, 0), (2, -1, -2, 0, 2390, 10056),
    ]
    private static let b: [(Double, Double, Double, Double, Double)] = [
        (0, 0, 0, 1, 5128122), (0, 0, 1, 1, 280602), (0, 0, 1, -1, 277693), (2, 0, 0, -1, 173237),
        (2, 0, -1, 1, 55413), (2, 0, -1, -1, 46271), (2, 0, 0, 1, 32573), (0, 0, 2, 1, 17198),
        (2, 0, 1, -1, 9266), (0, 0, 2, -1, 8822), (2, -1, 0, -1, 8216), (2, 0, -2, -1, 4324),
        (2, 0, 1, 1, 4200), (2, 1, 0, -1, -3359), (2, -1, -1, 1, 2463), (2, -1, 0, 1, 2211),
        (2, -1, -1, -1, 2065), (0, 1, -1, -1, -1870), (4, 0, -1, -1, 1828), (0, 1, 0, 1, -1794),
    ]

    /// Geocentric position, ecliptic J2000, km.
    public static func geocentric(jd: Double) -> V3 {
        let T = (jd - AstroTime.j2000) / 36_525
        let Lp = 218.3164477 + 481267.88123421 * T
        let D = rad(297.8501921 + 445267.1114034 * T)
        let M = rad(357.5291092 + 35999.0502909 * T)
        let Mp = rad(134.9633964 + 477198.8675055 * T)
        let F = rad(93.2720950 + 483202.0175233 * T)
        let E = 1 - 0.002516 * T
        var sl = 0.0, sr = 0.0, sb = 0.0
        for (d, m, mp, f, cl, cr) in lr {
            let arg = d * D + m * M + mp * Mp + f * F
            let e = abs(m) == 1 ? E : (abs(m) == 2 ? E * E : 1)
            sl += cl * e * sin(arg)
            sr += cr * e * cos(arg)
        }
        for (d, m, mp, f, cb) in b {
            let e = abs(m) == 1 ? E : 1
            sb += cb * e * sin(d * D + m * M + mp * Mp + f * F)
        }
        // Mean equinox of date -> J2000: remove general precession in longitude.
        let lon = rad(Lp + sl / 1e6 - 1.3969713 * T)
        let lat = rad(sb / 1e6)
        let dist = 385000.56 + sr / 1000
        return V3(dist * cos(lat) * cos(lon), dist * cos(lat) * sin(lon), dist * sin(lat))
    }

    /// Earth/Moon mass ratio, used to place Earth around the barycentre.
    public static let earthMoonMassRatio = 81.30056
}
