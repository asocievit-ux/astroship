import Foundation
import simd

/// Heliocentric ecliptic J2000 positions (km) for every catalogue body at one instant.
public struct EphemerisState: Sendable {
    public let jd: Double
    public let positions: [V3]
    public subscript(_ id: BodyID) -> V3 { positions[id.rawValue] }
}

public enum Ephemeris {
    public static func state(jd: Double) -> EphemerisState {
        var p = [V3](repeating: .zero, count: BodyID.allCases.count)
        let emb = PlanetTheory.position(.emb, jd: jd)
        let moonGeo = LunarTheory.geocentric(jd: jd)
        let earth = emb - moonGeo / (1 + LunarTheory.earthMoonMassRatio)
        for body in Catalog.all {
            switch body.orbit {
            case .none: p[body.id.rawValue] = .zero
            case .planet(let pl): p[body.id.rawValue] = PlanetTheory.position(pl, jd: jd)
            case .earth: p[body.id.rawValue] = earth
            case .moon: p[body.id.rawValue] = earth + moonGeo
            case .heliocentric(let o): p[body.id.rawValue] = o.position(jd: jd)
            case .satellite: break
            }
        }
        // Satellites after their parents are known.
        for body in Catalog.all {
            if case .satellite(let s) = body.orbit, let parent = body.parent {
                p[body.id.rawValue] = p[parent.rawValue] + s.position(jd: jd)
            }
        }
        return EphemerisState(jd: jd, positions: p)
    }

    /// Single body, heliocentric km.
    public static func position(_ id: BodyID, jd: Double) -> V3 {
        let body = Catalog.body(id)
        switch body.orbit {
        case .none: return .zero
        case .planet(let pl): return PlanetTheory.position(pl, jd: jd)
        case .earth, .moon:
            let emb = PlanetTheory.position(.emb, jd: jd)
            let m = LunarTheory.geocentric(jd: jd)
            let e = emb - m / (1 + LunarTheory.earthMoonMassRatio)
            return id == .earth ? e : e + m
        case .heliocentric(let o): return o.position(jd: jd)
        case .satellite(let s): return position(body.parent ?? .sun, jd: jd) + s.position(jd: jd)
        }
    }

    /// Position relative to the parent (planetocentric for moons, heliocentric otherwise).
    public static func relativeToParent(_ id: BodyID, jd: Double) -> V3 {
        let body = Catalog.body(id)
        switch body.orbit {
        case .moon: return LunarTheory.geocentric(jd: jd)
        case .satellite(let s): return s.position(jd: jd)
        default: return position(id, jd: jd)
        }
    }

    /// Body-fixed frame (x prime meridian, z north) to ecliptic. Tidally locked moons face their planet.
    public static func orientation(_ id: BodyID, state: EphemerisState) -> Mat3 {
        let body = Catalog.body(id)
        if body.tidallyLocked, let parent = body.parent {
            let toParent = normalize(state[parent] - state[id])
            var pole = V3(0, 0, 1)
            if case .satellite(let s) = body.orbit { pole = s.pole }
            let x = normalize(toParent - pole * dot(toParent, pole))
            let y = cross(pole, x)
            // columns x, y, z  -> rows of the transpose
            return Mat3(x, y, pole).transposed
        }
        return body.rotation.bodyToEcliptic(jd: state.jd)
    }

    /// Orbit polyline for display: heliocentric for Sun-orbiting bodies, planetocentric for moons (km).
    public static func orbitPolyline(_ id: BodyID, jd: Double, count: Int = 360) -> [V3] {
        switch Catalog.body(id).orbit {
        case .none: return []
        case .planet(let p): return PlanetTheory.orbit(p, jd: jd, count: count)
        case .earth:
            let el = PlanetTheory.elements(.emb, jd: jd)
            return OrbitElements(a: el.a, e: el.e, i: el.i, node: el.node, argPeri: el.w, tp: 0).polyline(count: count)
        case .moon:
            // One sidereal month of the lunar theory, centred on jd.
            let month = 27.321661
            return (0..<count).map { k in
                LunarTheory.geocentric(jd: jd - month / 2 + month * Double(k) / Double(count))
            }
        case .satellite(let s): return s.polyline(jd: jd, count: count)
        case .heliocentric(let o): return o.polyline(count: count)
        }
    }
}
