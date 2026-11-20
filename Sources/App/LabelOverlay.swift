import simd
import SwiftUI
import UIKit
import AstroCore

/// One marker for the overlay: computed on the render thread, drawn by SwiftUI.
struct LabelItem {
    var id: BodyID
    var point: CGPoint          // UIKit points, origin top-left
    var ring: Bool              // body is smaller than a few pixels: draw a glowing ring
    var labelOffset: CGFloat    // distance below the point for the name
    var major: Bool
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
        var placed: [CGPoint] = []
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
            if body.id != focus, placed.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 16 }) { continue }
            placed.append(pt)
            items.append(LabelItem(id: body.id, point: pt, ring: pixR < 6,
                                   labelOffset: max(11, min(pixR, viewSize.height * 0.4) + 5),
                                   major: body.kind == .planet || body.kind == .star))
        }
        return items
    }
}

/// Draws the rings and names every display frame from the latest render-thread layout.
struct LabelsCanvas: View {
    let viewer: ViewerState
    let showNames: Bool

    private static let names: [String] = Catalog.all.map { $0.id.localizedName }
    private static let colors: [Color] = Catalog.all.map { Color(red: $0.color.0, green: $0.color.1, blue: $0.color.2) }

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, _ in
                for item in viewer.labels {
                    let c = Self.colors[item.id.rawValue]
                    if item.ring {
                        let r: CGFloat = item.major ? 7 : 5
                        let rect = CGRect(x: item.point.x - r, y: item.point.y - r, width: 2 * r, height: 2 * r)
                        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(c.opacity(0.12)))
                        ctx.fill(Path(ellipseIn: rect), with: .color(c.opacity(0.22)))
                        ctx.stroke(Path(ellipseIn: rect), with: .color(c.opacity(0.95)), lineWidth: 1.5)
                    }
                    if showNames {
                        let text = Text(Self.names[item.id.rawValue])
                            .font(.system(size: item.major ? 13 : 11, weight: item.major ? .semibold : .medium))
                            .foregroundColor(.white.opacity(item.major ? 0.95 : 0.75))
                        ctx.draw(text, at: CGPoint(x: item.point.x, y: item.point.y + item.labelOffset), anchor: .top)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
