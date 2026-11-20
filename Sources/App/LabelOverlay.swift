import simd
import SwiftUI
import UIKit
import AstroCore

/// One marker for the overlay: computed on the render thread, drawn by SwiftUI.
struct LabelItem {
    var id: BodyID
    var point: CGPoint          // UIKit points, origin top-left
    var radius: CGFloat         // on-screen disc radius in points
}

/// Decides which bodies get a ring and a name, so planets far smaller than a pixel at true scale
/// can still be found and tapped. Plain data only, no UI objects (runs on the render thread).
enum LabelLayout {
    private static func priority(_ b: Body, focus: BodyID) -> Int {
        if b.id == focus { return 0 }
        switch b.kind {
        case .star: return 1
        case .planet: return 2
        case .moon: return 3
        case .dwarf: return 4
        case .comet: return 5
        }
    }

    private static let orderCache: [BodyID: [Body]] = {
        var d: [BodyID: [Body]] = [:]
        for f in BodyID.allCases {
            d[f] = Catalog.all.sorted { priority($0, focus: f) < priority($1, focus: f) }
        }
        return d
    }()

    static func compute(renderer: SolarRenderer, state: EphemerisState, cameraPos: SIMD3<Float>,
                        options: DisplayOptions, focus: BodyID) -> [LabelItem] {
        let viewSize = renderer.state.viewSize
        var items: [LabelItem] = []
        let fovHalfTan = tan(renderer.cameraFovRadians / 2)
        for body in orderCache[focus] ?? Catalog.all {
            switch body.kind {
            case .moon: if !options.moons { continue }
            case .dwarf: if !options.dwarfs { continue }
            case .comet: if !options.comets { continue }
            default: break
            }
            let p = renderer.containerPosition(body.id)
            if body.kind == .moon, let parent = body.parent, body.id != focus {
                let a = Float(length(state[body.id] - state[parent]) / SolarRenderer.unitKm)
                if simd_length(renderer.containerPosition(parent) - cameraPos) > a * 120 { continue }
            }
            guard let (pt, depth) = renderer.project(p, viewSize: viewSize) else { continue }
            guard pt.x > -40, pt.x < viewSize.width + 40, pt.y > -40, pt.y < viewSize.height + 40 else { continue }
            let pixR = CGFloat(Float(body.radiusKm / SolarRenderer.unitKm) / (depth * fovHalfTan)) * viewSize.height / 2
            items.append(LabelItem(id: body.id, point: pt, radius: min(pixR, viewSize.height)))
        }
        return items
    }
}

/// Picks the body for a tap. Bodies are usually far smaller than a pixel at true scale and have no
/// on-screen marker, so every visible body gets a generous invisible hit area around its disc.
enum TapPicker {
    static let slop: CGFloat = 44

    static func pick(at p: CGPoint, markers: [ScreenMarker], focus: BodyID) -> BodyID? {
        var best: (BodyID, CGFloat)?
        for m in markers {
            let d = hypot(m.point.x - p.x, m.point.y - p.y)
            let edge = max(0, d - m.radius)
            guard edge < slop else { continue }
            // Prefer the big, important bodies when several hit areas overlap.
            let b = Catalog.body(m.id)
            var penalty: CGFloat
            switch b.kind {
            case .star, .planet: penalty = 0
            case .dwarf: penalty = 4
            case .comet: penalty = 6
            case .moon: penalty = 8
            }
            if m.id == focus { penalty += 2 }   // tapping near the focused body usually means "something else"
            if d <= m.radius { penalty = -1 }   // directly on a visible disc always wins
            let score = edge + penalty
            if score < (best?.1 ?? .infinity) { best = (m.id, score) }
        }
        return best?.0
    }
}
