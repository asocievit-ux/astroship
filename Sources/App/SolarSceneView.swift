import simd
import SceneKit
import SwiftUI
import UIKit
import AstroCore

/// SCNView subclass that reports its size to the shared state (the render thread needs it for labels).
final class SolarSCNView: SCNView {
    var viewerState: ViewerState?
    override func layoutSubviews() {
        super.layoutSubviews()
        viewerState?.viewSize = bounds.size
    }
}

struct SolarSceneView: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SolarSCNView {
        let v = SolarSCNView(frame: .zero, options: nil)
        v.viewerState = model.viewer
        let r = model.renderer
        v.scene = r.scene
        v.pointOfView = r.cameraNode
        v.delegate = r
        v.isPlaying = true
        v.loops = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .black
        v.rendersContinuously = true
        v.showsStatistics = model.debugStats
        r.view = v
        let c = context.coordinator
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let dbl = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        [pan, pinch, tap, dbl].forEach { v.addGestureRecognizer($0) }
        return v
    }

    func updateUIView(_ uiView: SolarSCNView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        let model: AppModel
        private var startDistance = 0.0
        init(model: AppModel) { self.model = model }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            model.noteInteraction()
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            let s = model.viewer
            s.yaw -= Double(t.x) * 0.006
            s.pitch += Double(t.y) * 0.006
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            model.noteInteraction()
            let s = model.viewer
            if g.state == .began { startDistance = s.distanceKm }
            guard g.scale > 0 else { return }
            let target = startDistance / Double(g.scale)
            let focus = s.focus
            s.distanceKm = min(max(target, ViewerState.minDistance(focus)), ViewerState.maxDistanceKm)
            s.fly = nil
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            model.noteInteraction()
            if SleepTimer.shared.asleep { SleepTimer.shared.wake(); return }   // sleeping: a tap only wakes up
            if model.viewing { model.viewing = false; return }   // viewing mode: a tap only restores the controls
            guard let v = g.view as? SCNView else { return }
            let p = g.location(in: v)
            if model.handleTap(at: p) { return }
            let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            if let name = hits.first?.node.name, let id = BodyID.allCases.first(where: { $0.key == name }) {
                model.select(id)
            }
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            model.noteInteraction()
            if model.viewing { model.viewing = false; return }
            model.select(model.viewer.focus)
        }
    }
}
