import Foundation
import simd

public enum BodyKind: Int, Sendable { case star, planet, dwarf, moon, comet }

public enum BodyID: Int, CaseIterable, Sendable, Identifiable {
    case sun, mercury, venus, earth, moon, mars, phobos, deimos
    case jupiter, io, europa, ganymede, callisto
    case saturn, mimas, enceladus, tethys, dione, rhea, titan, iapetus
    case uranus, miranda, ariel, umbriel, titania, oberon
    case neptune, triton
    case pluto, charon, ceres, vesta, eris, haumea, makemake
    case halley, encke, churyumov, swiftTuttle, haleBopp

    public var id: Int { rawValue }
    /// Stable key, also the localization key ("body.<key>").
    public var key: String { String(describing: self) }
}

/// IAU WGCCRE style rotation: pole RA/Dec (deg, with rates per Julian century) and prime meridian W (deg, deg/day).
public struct RotationModel: Sendable {
    public var ra: Double, raRate: Double, dec: Double, decRate: Double, w0: Double, wDot: Double
    public init(ra: Double, raRate: Double = 0, dec: Double, decRate: Double = 0, w0: Double, wDot: Double) {
        self.ra = ra; self.raRate = raRate; self.dec = dec; self.decRate = decRate; self.w0 = w0; self.wDot = wDot
    }
    /// Pole near the ecliptic north pole with a rotation period in hours (bodies without an IAU model).
    public static func simple(periodHours: Double, w0: Double = 0) -> RotationModel {
        RotationModel(ra: 270, dec: 66.5607, w0: w0, wDot: 360 / (periodHours / 24))
    }

    /// Body-fixed (x = prime meridian, z = north pole) to ecliptic J2000.
    public func bodyToEcliptic(jd: Double) -> Mat3 {
        let d = jd - AstroTime.j2000, T = d / 36_525
        let a = ra + raRate * T, de = dec + decRate * T
        let w = fmod(w0 + wDot * d, 360)
        return Frames.eqToEcl * Mat3.rz(rad(a + 90)) * Mat3.rx(rad(90 - de)) * Mat3.rz(rad(w))
    }
    public var poleEquatorial: V3 { Frames.equatorial(raDeg: ra, decDeg: dec) }
}

public enum OrbitSource: Sendable {
    case none
    case planet(PlanetTheory.Planet)
    case earth
    case moon
    case satellite(SatelliteElements)
    case heliocentric(OrbitElements)
}

public struct Body: Sendable, Identifiable {
    public let id: BodyID
    public let kind: BodyKind
    public let parent: BodyID?
    /// Mean radius in km, and body-frame scale factors for oblate / elongated shapes.
    public let radiusKm: Double
    public let shape: V3
    public let texture: String?
    /// Linear sRGB-ish tint 0...1 for markers, trails and untextured bodies.
    public let color: (Double, Double, Double)
    public let rotation: RotationModel
    /// Moons that keep one face to their planet (rotation is then derived from the orbit).
    public let tidallyLocked: Bool
    public let orbit: OrbitSource

    public var key: String { id.key }
}

public enum Catalog {

    private static func sat(_ a: Double, _ P: Double, _ pole: V3, _ x0: V3) -> OrbitSource {
        .satellite(SatelliteElements(aKm: a, periodDays: P, pole: pole, x0: x0))
    }
    private static func small(_ a: Double, _ e: Double, _ i: Double, _ node: Double, _ w: Double, _ tp: Double) -> OrbitSource {
        .heliocentric(OrbitElements(a: a, e: e, i: i, node: node, argPeri: w, tp: tp))
    }
    private static func b(_ id: BodyID, _ kind: BodyKind, _ parent: BodyID?, _ r: Double, _ tex: String?,
                          _ color: (Double, Double, Double), _ rot: RotationModel, _ orbit: OrbitSource,
                          shape: V3 = V3(1, 1, 1), locked: Bool = false) -> Body {
        Body(id: id, kind: kind, parent: parent, radiusKm: r, shape: shape, texture: tex, color: color,
             rotation: rot, tidallyLocked: locked, orbit: orbit)
    }

    public static let all: [Body] = [
        b(.sun, .star, nil, 695_700, "sun", (1.0, 0.85, 0.45), RotationModel(ra: 286.13, dec: 63.87, w0: 84.176, wDot: 14.1844), .none),
        b(.mercury, .planet, .sun, 2_439.7, "mercury", (0.72, 0.68, 0.64),
          RotationModel(ra: 281.0103, raRate: -0.0328, dec: 61.4155, decRate: -0.0049, w0: 329.5988, wDot: 6.1385108), .planet(.mercury)),
        b(.venus, .planet, .sun, 6_051.8, "venus", (0.95, 0.85, 0.6),
          RotationModel(ra: 272.76, dec: 67.16, w0: 160.20, wDot: -1.4813688), .planet(.venus)),
        b(.earth, .planet, .sun, 6_371.0, "earth", (0.35, 0.6, 1.0),
          RotationModel(ra: 0, raRate: -0.641, dec: 90, decRate: -0.557, w0: 190.147, wDot: 360.9856235), .earth),
        b(.moon, .moon, .earth, 1_737.4, "moon", (0.8, 0.8, 0.78),
          RotationModel(ra: 269.9949, raRate: 0.0031, dec: 66.5392, decRate: 0.0130, w0: 38.3213, wDot: 13.17635815), .moon),
        b(.mars, .planet, .sun, 3_389.5, "mars", (0.95, 0.45, 0.3),
          RotationModel(ra: 317.269202, raRate: -0.10927547, dec: 54.432516, decRate: -0.05827105, w0: 176.049863, wDot: 350.891982443297), .planet(.mars)),
        b(.phobos, .moon, .mars, 11.3, "moon", (0.55, 0.5, 0.45), .simple(periodHours: 7.65),
          sat(9_375, 0.3187, V3(0.429960, -0.050422, 0.901439), V3(-0.892001, -0.178026, 0.415501)), shape: V3(1.2, 1.0, 0.85), locked: true),
        b(.deimos, .moon, .mars, 6.2, "moon", (0.6, 0.55, 0.5), .simple(periodHours: 30.3),
          sat(23_457, 1.2625, V3(0.404114, -0.059569, 0.912767), V3(0.908147, 0.145437, -0.392577)), shape: V3(1.2, 1.0, 0.85), locked: true),
        b(.jupiter, .planet, .sun, 69_911, "jupiter", (0.9, 0.78, 0.62),
          RotationModel(ra: 268.056595, raRate: -0.006499, dec: 64.495303, decRate: 0.002413, w0: 284.95, wDot: 870.536),
          .planet(.jupiter), shape: V3(1.0226, 1.0226, 0.9563)),
        b(.io, .moon, .jupiter, 1_821.6, "moon", (1.0, 0.9, 0.45), .simple(periodHours: 42.46),
          sat(421_800, 1.762732, V3(-0.014345, -0.036183, 0.999242), V3(-0.999238, 0.036796, -0.013012)), locked: true),
        b(.europa, .moon, .jupiter, 1_560.8, "moon", (0.95, 0.88, 0.78), .simple(periodHours: 85.2),
          sat(671_100, 3.525463, V3(-0.020042, -0.029979, 0.999350), V3(-0.123948, -0.991765, -0.032237)), locked: true),
        b(.ganymede, .moon, .jupiter, 2_634.1, "moon", (0.75, 0.7, 0.65), .simple(periodHours: 171.7),
          sat(1_070_400, 7.155588, V3(-0.014625, -0.038196, 0.999163), V3(0.828909, 0.558381, 0.033479)), locked: true),
        b(.callisto, .moon, .jupiter, 2_410.3, "moon", (0.5, 0.45, 0.4), .simple(periodHours: 400.5),
          sat(1_882_700, 16.690440, V3(-0.013444, -0.031304, 0.999419), V3(-0.809197, -0.586809, -0.029266)), locked: true),
        b(.saturn, .planet, .sun, 58_232, "saturn", (0.95, 0.85, 0.6),
          RotationModel(ra: 40.589, raRate: -0.036, dec: 83.537, decRate: -0.004, w0: 38.90, wDot: 810.7939024),
          .planet(.saturn), shape: V3(1.0350, 1.0350, 0.9301)),
        b(.mimas, .moon, .saturn, 198.2, "moon", (0.85, 0.85, 0.85), .simple(periodHours: 22.6),
          sat(186_000, 0.942422, V3(0.071968, 0.484029, 0.872087), V3(0.709182, 0.589984, -0.385980)), locked: true),
        b(.enceladus, .moon, .saturn, 252.1, "moon", (1.0, 1.0, 1.0), .simple(periodHours: 32.9),
          sat(238_400, 1.370218, V3(0.085392, 0.462333, 0.882585), V3(0.016906, 0.885021, -0.465245)), locked: true),
        b(.tethys, .moon, .saturn, 531.1, "moon", (0.92, 0.92, 0.9), .simple(periodHours: 45.3),
          sat(295_000, 1.887802, V3(0.067916, 0.469396, 0.880372), V3(-0.933628, 0.341005, -0.109792)), locked: true),
        b(.dione, .moon, .saturn, 561.4, "moon", (0.88, 0.88, 0.86), .simple(periodHours: 65.7),
          sat(377_700, 2.736916, V3(0.085201, 0.462084, 0.882734), V3(-0.570087, -0.703996, 0.423545)), locked: true),
        b(.rhea, .moon, .saturn, 763.8, "moon", (0.85, 0.84, 0.82), .simple(periodHours: 108.4),
          sat(527_200, 4.517503, V3(0.082608, 0.466495, 0.880658), V3(0.506049, 0.741639, -0.440324)), locked: true),
        b(.titan, .moon, .saturn, 2_574.7, nil, (0.95, 0.72, 0.38), .simple(periodHours: 382.7),
          sat(1_221_900, 15.945448, V3(0.088065, 0.456502, 0.885353), V3(0.237536, 0.853542, -0.463727)), locked: true),
        b(.iapetus, .moon, .saturn, 734.5, "moon", (0.7, 0.62, 0.5), .simple(periodHours: 1903.9),
          sat(3_561_700, 79.331002, V3(0.192015, 0.219821, 0.956456), V3(-0.769465, 0.638642, 0.007697)), locked: true),
        b(.uranus, .planet, .sun, 25_362, "uranus", (0.6, 0.88, 0.92),
          RotationModel(ra: 257.311, dec: -15.175, w0: 203.81, wDot: -501.1600928), .planet(.uranus), shape: V3(1.0089, 1.0089, 0.9819)),
        b(.miranda, .moon, .uranus, 235.8, "moon", (0.8, 0.8, 0.8), .simple(periodHours: 33.9),
          sat(129_846, 1.413479, V3(0.286654, 0.948296, -0.136247), V3(-0.902933, 0.219886, -0.369273)), locked: true),
        b(.ariel, .moon, .uranus, 578.9, "moon", (0.82, 0.82, 0.82), .simple(periodHours: 60.5),
          sat(190_929, 2.520379, V3(0.211675, 0.968068, -0.134305), V3(0.806675, -0.250638, -0.535215)), locked: true),
        b(.umbriel, .moon, .uranus, 584.7, "moon", (0.55, 0.55, 0.55), .simple(periodHours: 99.5),
          sat(265_986, 4.144177, V3(0.210672, 0.968295, -0.134243), V3(-0.536720, 0.229348, 0.811992)), locked: true),
        b(.titania, .moon, .uranus, 788.9, "moon", (0.75, 0.72, 0.7), .simple(periodHours: 208.9),
          sat(436_298, 8.705869, V3(0.212025, 0.967887, -0.135058), V3(0.358796, -0.205646, -0.910481)), locked: true),
        b(.oberon, .moon, .uranus, 761.4, "moon", (0.68, 0.64, 0.62), .simple(periodHours: 323.1),
          sat(583_511, 13.463237, V3(0.210871, 0.967789, -0.137544), V3(0.451189, 0.028460, 0.891975)), locked: true),
        b(.neptune, .planet, .sun, 24_622, "neptune", (0.35, 0.5, 1.0),
          RotationModel(ra: 299.36, dec: 43.46, w0: 249.978, wDot: 541.1397757), .planet(.neptune), shape: V3(1.0085, 1.0085, 0.983)),
        b(.triton, .moon, .neptune, 1_353.4, "moon", (0.9, 0.82, 0.8), .simple(periodHours: 141.0),
          sat(354_800, 5.8792, V3(-0.528044, 0.568344, -0.630994), V3(-0.845263, -0.280138, 0.455030)), locked: true),
        b(.pluto, .dwarf, .sun, 1_188.3, nil, (0.85, 0.75, 0.62),
          RotationModel(ra: 132.993, dec: -6.163, w0: 302.695, wDot: 56.3625225),
          small(39.58862938517124, 0.2518378778576892, 17.14771140999114, 110.2923840543057, 113.7090015158565, 2447812.094159956)),
        b(.charon, .moon, .pluto, 606.0, "moon", (0.7, 0.68, 0.66), .simple(periodHours: 153.29),
          sat(19_596, 6.387222, V3(-0.678068, 0.623666, -0.388927), V3(-0.249205, 0.302732, 0.919919)), locked: true),
        b(.ceres, .dwarf, .sun, 469.7, "ceres", (0.7, 0.7, 0.68),
          RotationModel(ra: 291.418, dec: 66.764, w0: 170.650, wDot: 952.1532),
          small(2.765552595034094, 0.07969229514816586, 10.58802780183462, 80.24862682043221, 73.29421453021587, 2461599.841466614)),
        b(.vesta, .dwarf, .sun, 262.7, "ceres", (0.75, 0.72, 0.68), .simple(periodHours: 5.342),
          small(2.361365965127599, 0.09020374382834395, 7.143925545058711, 103.701293265032, 151.4686478221564, 2460901.587379843),
          shape: V3(1.09, 1.0, 0.86)),
        b(.eris, .dwarf, .sun, 1_163, "eris", (0.92, 0.92, 0.95), .simple(periodHours: 25.9 * 24),
          small(67.93394687853566, 0.4382385347971672, 43.9258279471791, 36.00477044417249, 150.7949235840312, 2545407.716847013)),
        b(.haumea, .dwarf, .sun, 798, "haumea", (0.92, 0.9, 0.88), .simple(periodHours: 3.9154),
          small(43.06029023650952, 0.1944430148898797, 28.20847393040364, 121.7860561329425, 240.6905472508661, 2500416.599615283),
          shape: V3(1.40, 1.12, 0.72)),
        b(.makemake, .dwarf, .sun, 715, "makemake", (0.9, 0.7, 0.55), .simple(periodHours: 22.8266),
          small(45.57093317300052, 0.1588889953992523, 29.02785603743067, 79.2948338209406, 297.0922733397207, 2408158.694098616)),
        b(.halley, .comet, .sun, 5.5, "moon", (0.75, 0.9, 1.0), .simple(periodHours: 52.8),
          small(17.92863504856923, 0.9679359956953211, 162.1905300439129, 59.09894720612437, 112.2414314637764, 2446469.973616147),
          shape: V3(1.5, 0.8, 0.75)),
        b(.encke, .comet, .sun, 2.4, "moon", (0.75, 0.9, 1.0), .simple(periodHours: 11.083),
          small(2.21828304597785, 0.8470243270635326, 11.34076650592971, 334.0134789002986, 187.2820526745018, 2460240.039778987)),
        b(.churyumov, .comet, .sun, 2.0, "moon", (0.75, 0.9, 1.0), .simple(periodHours: 12.76),
          small(3.462249490129549, 0.6409081308996354, 7.040294937543767, 50.13557377155012, 12.79824970228189, 2457247.588657812),
          shape: V3(1.3, 0.9, 0.8)),
        b(.swiftTuttle, .comet, .sun, 13, "moon", (0.75, 0.9, 1.0), .simple(periodHours: 69.4),
          small(26.0920694978266, 0.963225755046038, 113.453816997171, 139.3811920815948, 152.9821676305871, 2448968.499784556)),
        b(.haleBopp, .comet, .sun, 30, "moon", (0.75, 0.9, 1.0), .simple(periodHours: 11.35),
          small(177.4333839117583, 0.9949810027633206, 89.28759424740302, 282.7334213961641, 130.4146670659176, 2450537.134907144)),
    ]

    public static func body(_ id: BodyID) -> Body { all[id.rawValue] }

    public static func moons(of id: BodyID) -> [Body] { all.filter { $0.parent == id && $0.kind == .moon } }

    /// Orbital period in days, for info panels and trail lengths.
    public static func periodDays(_ id: BodyID, jd: Double = AstroTime.j2000) -> Double? {
        switch body(id).orbit {
        case .none: return nil
        case .planet(let p):
            let a = PlanetTheory.elements(p, jd: jd).a
            return 365.256898326 * pow(a, 1.5)
        case .earth: return 365.256363
        case .moon: return 27.321661
        case .satellite(let s): return s.periodDays
        case .heliocentric(let o): return o.periodDays
        }
    }
}
