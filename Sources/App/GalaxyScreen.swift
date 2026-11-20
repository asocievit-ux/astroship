import simd
import SceneKit
import SwiftUI
import UIKit
import AstroCore

/// Milky Way seen from outside: where the Sun is and which way it is going.
/// Scene units: 1 unit = 1 kpc. Galactic centre at the origin, north galactic pole = +Y.
/// Galactic heliocentric axes map to scene as x(to centre) = -Z, y(rotation) = -X, z(north) = +Y,
/// so seen from the north pole the disc turns clockwise, as the real Milky Way does.
final class GalaxyRenderer: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let pulse = SCNNode()
    var labels: [(String, SIMD3<Float>)] = []
    private let lock = NSLock()
    private var _projected: [(String, CGPoint)] = []
    var projected: [(String, CGPoint)] { lock.lock(); defer { lock.unlock() }; return _projected }
    var viewSize = CGSize(width: 390, height: 844)
    static let sunScene = SIMD3<Float>(0, Float(GalacticMotion.zSunPc / 1000), Float(GalacticMotion.r0Kpc))

    override init() {
        super.init()
        build()
    }

    private func build() {
        scene.background.contents = UIColor.black
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zNear = 0.01
        cam.zFar = 500
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 22, 30)
        cameraNode.look(at: SCNVector3(0, 0, 2))
        scene.rootNode.addChildNode(cameraNode)

        // Disc
        let disc = SCNPlane(width: 32, height: 32)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Geo.texture("galaxy_top.jpg")
        m.isDoubleSided = true
        m.blendMode = .add
        m.writesToDepthBuffer = false
        disc.firstMaterial = m
        let discNode = SCNNode(geometry: disc)
        discNode.eulerAngles.x = -.pi / 2      // plane lies in XZ; image top = -Z
        scene.rootNode.addChildNode(discNode)

        // Bulge glow: a soft billboard sprite (solid spheres read as a flat disc).
        let glow = SCNPlane(width: 7.5, height: 7.5)
        let gm = SCNMaterial()
        gm.lightingModel = .constant
        gm.diffuse.contents = Geo.texture("galaxy_glow.png")
        gm.blendMode = .add
        gm.writesToDepthBuffer = false
        gm.readsFromDepthBuffer = false
        glow.firstMaterial = gm
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, 0.05, 0)
        glowNode.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(glowNode)

        // Sun's galactic orbit (circle of radius R0)
        let r0 = Float(GalacticMotion.r0Kpc)
        let circle = (0...240).map { k -> SIMD3<Float> in
            let a = Float(k) / 240 * 2 * .pi
            return SIMD3<Float>(cos(a) * r0, 0.01, sin(a) * r0)
        }
        let orbit = Geo.lineStrip(circle, colors: Array(repeating: SIMD3<Float>(0.9, 0.7, 0.3) * 0.6, count: circle.count), closed: true)
        scene.rootNode.addChildNode(SCNNode(geometry: orbit))

        // Sun marker
        let sun = SCNSphere(radius: 0.12)
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        sun.firstMaterial = sm
        sunNode.geometry = sun
        sunNode.simdPosition = Self.sunScene
        scene.rootNode.addChildNode(sunNode)
        let ring = SCNTorus(ringRadius: 0.35, pipeRadius: 0.02)
        let rm = SCNMaterial()
        rm.lightingModel = .constant
        rm.diffuse.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        rm.blendMode = .add
        ring.firstMaterial = rm
        pulse.geometry = ring
        pulse.simdPosition = Self.sunScene
        scene.rootNode.addChildNode(pulse)
        let grow = SCNAction.sequence([
            .group([.scale(to: 2.2, duration: 1.6), .fadeOut(duration: 1.6)]),
            .group([.scale(to: 1, duration: 0), .fadeIn(duration: 0)]),
        ])
        pulse.runAction(.repeatForever(grow))

        // Direction of travel: galactic +y = scene -X
        let arrowLen: Float = 2.6
        let shaft = SCNCylinder(radius: 0.035, height: CGFloat(arrowLen))
        let head = SCNCone(topRadius: 0, bottomRadius: 0.12, height: 0.35)
        shaft.firstMaterial = rm; head.firstMaterial = rm
        let arrow = SCNNode()
        let s = SCNNode(geometry: shaft); s.position = SCNVector3(0, arrowLen / 2, 0)
        let h = SCNNode(geometry: head); h.position = SCNVector3(0, arrowLen + 0.17, 0)
        arrow.addChildNode(s); arrow.addChildNode(h)
        let v = GalacticMotion.velocityGalactic
        let dir = simd_normalize(SIMD3<Float>(Float(-v.y), Float(v.z), Float(-v.x)))
        arrow.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
        arrow.simdPosition = Self.sunScene
        _ = arrow   // direction arrow removed by request (v3); kept out of the scene

        labels = [
            (L("galaxy.sun"), Self.sunScene),
            (L("galaxy.center"), SIMD3<Float>(0, 0.4, 0)),
            (L("galaxy.perseus"), armPoint(r: 10.5, offsetAngle: 0.0)),
            (L("galaxy.sagittarius"), armPoint(r: 6.6, offsetAngle: 0.0)),
            (L("galaxy.scutum"), armPoint(r: 10.5, offsetAngle: .pi)),
        ]
    }

    /// Point on a modelled arm (same log-spiral model and 16 degree pitch as the texture) that crosses the
    /// Sun's direction at radius r, followed 0.6 rad counter-clockwise (as seen from the north pole).
    private func armPoint(r: Float, offsetAngle: Float) -> SIMD3<Float> {
        let k: Float = 1 / tan(16 * .pi / 180)
        let delta: Float = 0.6
        let rr = r * exp(delta / k)
        let theta = -Float.pi / 2 + delta + offsetAngle      // visual angle: x right, y = -Z up
        return SIMD3<Float>(cos(theta) * rr, 0.2, -sin(theta) * rr)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pov = renderer.pointOfView else { return }
        let inv = pov.simdWorldTransform.inverse
        let fov = Float((pov.camera?.fieldOfView ?? 55) * .pi / 180)
        let size = viewSize
        let f = Float(size.height) / 2 / tan(fov / 2)
        var out: [(String, CGPoint)] = []
        for (name, p) in labels {
            let c = inv * SIMD4<Float>(p.x, p.y, p.z, 1)
            guard c.z < 0 else { continue }
            out.append((name, CGPoint(x: CGFloat(Float(size.width) / 2 + c.x * f / -c.z),
                                      y: CGFloat(Float(size.height) / 2 - c.y * f / -c.z))))
        }
        lock.lock(); _projected = out; lock.unlock()
    }
}

final class GalaxySCNView: SCNView {
    var galaxy: GalaxyRenderer?
    override func layoutSubviews() {
        super.layoutSubviews()
        galaxy?.viewSize = bounds.size
    }
}

struct GalaxySceneView: UIViewRepresentable {
    let renderer: GalaxyRenderer
    func makeUIView(context: Context) -> GalaxySCNView {
        let v = GalaxySCNView(frame: .zero, options: nil)
        v.galaxy = renderer
        v.scene = renderer.scene
        v.pointOfView = renderer.cameraNode
        v.delegate = renderer
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.target = SCNVector3(0, 0, 2)
        v.defaultCameraController.maximumVerticalAngle = 89
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: GalaxySCNView, context: Context) {}
}

struct GalaxyScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var renderer = GalaxyRenderer()

    var body: some View {
        ZStack(alignment: .top) {
            GalaxySceneView(renderer: renderer).ignoresSafeArea()
            TimelineView(.animation) { _ in
                Canvas { ctx, _ in
                    for (name, p) in renderer.projected {
                        ctx.draw(Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9)),
                                 at: CGPoint(x: p.x, y: p.y + 10), anchor: .top)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(spacing: 10) {
                HStack {
                    Text(L("galaxy.title")).font(.headline)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 40)
                    }
                    .glass()
                    .accessibilityLabel(L("common.close"))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("galaxy.speed", Fmt.number(GalacticMotion.speed, digits: 0)))
                        .font(.subheadline.weight(.semibold))
                    Text(L("galaxy.facts",
                           Fmt.number(GalacticMotion.r0Kpc * 3261.56, digits: 0),
                           Fmt.number(GalacticMotion.galacticYearYears / 1e6, digits: 0)))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("galaxy.travelled", Fmt.number(model.travelledKm, digits: 0)))
                        .font(.footnote.monospacedDigit())
                    Text(L("galaxy.illustration")).font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .glass()
            }
            .padding(12)
        }
        .preferredColorScheme(.dark)
    }
}
