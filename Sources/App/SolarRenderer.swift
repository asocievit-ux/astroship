import simd
import SceneKit
import SpriteKit
import UIKit
import AstroCore

/// Builds the solar-system scene and updates it every frame on SceneKit's render thread.
///
/// Scale is true: real radii and distances. Precision is kept with a floating origin: every
/// frame, positions are computed in Double (km) and the focused body is placed at the scene origin.
/// 1 scene unit = 1000 km.
final class SolarRenderer: NSObject, SCNSceneRendererDelegate {
    static let unitKm = 1000.0

    let state: ViewerState
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let skyRoot = SCNNode()
    private let sunLight = SCNNode()
    private var containers: [SCNNode] = []      // per body, positioned
    private var orientNodes: [SCNNode] = []     // per body, rotated
    private var meshNodes: [SCNNode] = []       // per body, scaled mesh
    private var orbitNodes: [BodyID: SCNNode] = [:]
    private var trailNodes: [BodyID: SCNNode] = [:]
    private var trailBuiltJD: [BodyID: Double] = [:]
    private var trailRoundRobin = 0
    private let sunTrailNode = SCNNode()
    private let motionArrow = SCNNode()
    private let beltNode = SCNNode()
    private var belt: [(a: Float, n: Float, m0: Float, rot: simd_float3x3)] = []
    private var beltBuiltJD = -1.0
    private var cometTails: [BodyID: SCNNode] = [:]
    private var sunGlow = SCNNode()
    private var orbitBuiltJD = -1e9
    private var lastMode: FrameMode?
    weak var view: SCNView?
    /// Called on the main queue ~4x per second with the latest ephemeris (for the info panel).
    var onSnapshot: (@MainActor (EphemerisState) -> Void)?
    private var lastSnapshot: CFTimeInterval = 0

    init(state: ViewerState) {
        self.state = state
        super.init()
        build()
    }

    // MARK: Build

    private func build() {
        scene.background.contents = UIColor.black
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.projectionDirection = .vertical
        cam.automaticallyAdjustsZRange = false
        cam.zNear = 0.01
        cam.zFar = 1e9
        cam.wantsHDR = false
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        // Sky: Milky Way glow sphere and the bright-star catalogue, both at "infinity" around the camera.
        let skyMesh = Geo.sphere(segments: 72, rings: 36, inward: true)
        let skyMat = SCNMaterial()
        skyMat.lightingModel = .constant
        skyMat.diffuse.contents = Geo.texture("sky_milkyway.jpg")
        skyMat.diffuse.mipFilter = .linear
        skyMat.isDoubleSided = true
        skyMat.writesToDepthBuffer = false
        skyMat.readsFromDepthBuffer = false
        skyMesh.firstMaterial = skyMat
        let skyNode = SCNNode(geometry: skyMesh)
        skyNode.renderingOrder = -100
        skyRoot.addChildNode(skyNode)
        if let stars = Geo.starField() {
            let starNode = SCNNode(geometry: stars)
            starNode.renderingOrder = -99
            skyRoot.addChildNode(starNode)
        }
        skyRoot.simdOrientation = Mat3.identity.sceneQuaternion   // ecliptic axes
        scene.rootNode.addChildNode(skyRoot)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 35
        scene.rootNode.addChildNode(ambient)
        sunLight.light = SCNLight()
        sunLight.light!.type = .omni
        sunLight.light!.intensity = 1150
        sunLight.light!.attenuationStartDistance = 0
        sunLight.light!.attenuationEndDistance = 0
        scene.rootNode.addChildNode(sunLight)

        for body in Catalog.all { addBody(body) }

        let glow = SCNPlane(width: 1, height: 1)
        let gm = SCNMaterial()
        gm.lightingModel = .constant
        gm.diffuse.contents = Geo.texture("sun_glow.png")
        gm.blendMode = .add
        gm.writesToDepthBuffer = false
        gm.isDoubleSided = true
        glow.firstMaterial = gm
        sunGlow = SCNNode(geometry: glow)
        sunGlow.constraints = [SCNBillboardConstraint()]
        sunGlow.renderingOrder = 50
        containers[BodyID.sun.rawValue].addChildNode(sunGlow)

        buildBelt()
        scene.rootNode.addChildNode(beltNode)
        scene.rootNode.addChildNode(sunTrailNode)
        buildMotionArrow()
        scene.rootNode.addChildNode(motionArrow)
    }

    private func addBody(_ body: Body) {
        let container = SCNNode()
        container.name = body.key
        let orient = SCNNode()
        let mesh = SCNNode(geometry: Geo.sphere(segments: body.kind == .planet || body.kind == .star ? 96 : 48,
                                                rings: body.kind == .planet || body.kind == .star ? 48 : 24))
        mesh.name = body.key
        let r = Float(body.radiusKm / Self.unitKm)
        mesh.simdScale = SIMD3<Float>(Float(body.shape.x), Float(body.shape.y), Float(body.shape.z)) * r
        let m = SCNMaterial()
        if body.kind == .star {
            m.lightingModel = .constant
            m.diffuse.contents = Geo.texture("sun.jpg")
            m.multiply.contents = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        } else {
            m.lightingModel = .lambert
            if let t = body.texture, let img = Geo.texture("\(t).jpg") {
                m.diffuse.contents = img
                if t == "moon" && body.id != .moon {
                    m.multiply.contents = UIColor(red: body.color.0, green: body.color.1, blue: body.color.2, alpha: 1)
                }
            } else {
                m.diffuse.contents = UIColor(red: body.color.0, green: body.color.1, blue: body.color.2, alpha: 1)
            }
        }
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        mesh.geometry?.firstMaterial = m
        orient.addChildNode(mesh)

        if body.id == .earth, let clouds = Geo.texture("earth_clouds.jpg") {
            let c = SCNNode(geometry: Geo.sphere())
            let cm = SCNMaterial()
            cm.lightingModel = .lambert
            cm.diffuse.contents = UIColor.white
            cm.transparent.contents = clouds
            cm.transparencyMode = .rgbZero
            cm.writesToDepthBuffer = false
            c.geometry?.firstMaterial = cm
            c.simdScale = SIMD3<Float>(repeating: r * 1.006)
            c.renderingOrder = 10
            orient.addChildNode(c)
        }
        if body.id == .saturn, let ring = Geo.texture("saturn_ring.png") {
            let g = Geo.ring(inner: Float(74_500 / Self.unitKm), outer: Float(140_220 / Self.unitKm))
            let rm = SCNMaterial()
            rm.lightingModel = .lambert
            rm.diffuse.contents = ring
            rm.isDoubleSided = true
            rm.transparencyMode = .aOne
            rm.writesToDepthBuffer = false
            g.firstMaterial = rm
            let n = SCNNode(geometry: g)
            n.renderingOrder = 20
            orient.addChildNode(n)
        }
        if body.kind == .comet {
            let tail = SCNNode(geometry: cometTailGeometry())
            tail.renderingOrder = 30
            tail.isHidden = true
            container.addChildNode(tail)
            cometTails[body.id] = tail
        }
        container.addChildNode(orient)
        scene.rootNode.addChildNode(container)
        containers.append(container)
        orientNodes.append(orient)
        meshNodes.append(mesh)
    }

    private func cometTailGeometry() -> SCNGeometry {
        // Unit cone along +Y with its tip at the origin (the nucleus).
        let cone = SCNCone(topRadius: 0.12, bottomRadius: 0.0, height: 1)
        cone.radialSegmentCount = 24
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
        m.transparency = 0.28
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        cone.firstMaterial = m
        return cone
    }

    private func buildMotionArrow() {
        let shaft = SCNCylinder(radius: 0.02, height: 1)
        let head = SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.18)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        m.blendMode = .add
        shaft.firstMaterial = m; head.firstMaterial = m
        let s = SCNNode(geometry: shaft); s.position = SCNVector3(0, 0.5, 0)
        let h = SCNNode(geometry: head); h.position = SCNVector3(0, 1.09, 0)
        motionArrow.addChildNode(s); motionArrow.addChildNode(h)
        motionArrow.isHidden = true
    }

    private func buildBelt() {
        var rng = SystemRandomNumberGenerator()
        belt.removeAll()
        for _ in 0..<2600 {
            // main belt 2.1 - 3.3 au, avoiding the Kirkwood gaps roughly
            var a = Float.random(in: 2.1...3.3, using: &rng)
            if abs(a - 2.5) < 0.03 || abs(a - 2.82) < 0.03 || abs(a - 2.95) < 0.02 { a += 0.06 }
            let inc = Float.random(in: -1...1, using: &rng) * Float.random(in: 0...1, using: &rng) * 0.3
            let node = Float.random(in: 0...(2 * .pi), using: &rng)
            let m0 = Float.random(in: 0...(2 * .pi), using: &rng)
            let n = Float(Kepler.gaussK) / powf(a, 1.5)          // rad/day
            let rz = simd_float3x3(simd_quatf(angle: node, axis: SIMD3(0, 0, 1)))
            let rx = simd_float3x3(simd_quatf(angle: inc, axis: SIMD3(1, 0, 0)))
            belt.append((a, n, m0, rz * rx))
        }
        beltNode.simdOrientation = Mat3.identity.sceneQuaternion
    }

    private func updateBelt(jd: Double) {
        guard abs(jd - beltBuiltJD) > 0.05 || beltNode.geometry == nil else { return }
        beltBuiltJD = jd
        let d = Float((jd - AstroTime.j2000).truncatingRemainder(dividingBy: 1_000_000))
        let au = Float(Frames.au / Self.unitKm)
        let pts: [SIMD3<Float>] = belt.map { b in
            let m = b.m0 + b.n * d
            return b.rot * SIMD3<Float>(cos(m) * b.a * au, sin(m) * b.a * au, 0)
        }
        beltNode.geometry = Geo.points(pts, size: 2, color: UIColor(white: 0.55, alpha: 1))
    }

    // MARK: Orbits and trails

    private func visible(_ body: Body, _ o: DisplayOptions) -> Bool {
        switch body.kind {
        case .moon: return o.moons
        case .dwarf: return o.dwarfs
        case .comet: return o.comets
        default: return true
        }
    }

    private func rebuildOrbits(jd: Double) {
        orbitBuiltJD = jd
        for body in Catalog.all where body.kind != .star {
            let pts = Ephemeris.orbitPolyline(body.id, jd: jd, count: body.kind == .comet ? 720 : 360)
            let f = pts.map { $0.sceneUnits }
            let c = SIMD3<Float>(Float(body.color.0), Float(body.color.1), Float(body.color.2)) * (body.kind == .moon ? 0.35 : 0.45)
            let g = Geo.lineStrip(f, colors: Array(repeating: c, count: f.count), closed: body.id != .moon)
            let node = lineNode(&orbitNodes, body.id, order: 5)
            node.geometry = g
        }
    }

    private func lineNode(_ dict: inout [BodyID: SCNNode], _ id: BodyID, order: Int) -> SCNNode {
        if let n = dict[id] { return n }
        let n = SCNNode()
        n.renderingOrder = order
        scene.rootNode.addChildNode(n)
        dict[id] = n
        return n
    }

    private func trailDuration(_ id: BodyID) -> Double {
        let p = Catalog.periodDays(id) ?? 365
        switch Catalog.body(id).kind {
        case .moon: return p * 2
        case .comet: return min(p, 365.25 * 80)
        default: return min(p * 1.5, 365.25 * 60)
        }
    }

    private static let trailBodies: [BodyID] = [.mercury, .venus, .earth, .moon, .mars, .jupiter, .saturn, .uranus, .neptune,
                                                .pluto, .ceres, .eris, .haumea, .makemake, .halley, .encke, .swiftTuttle]

    private func updateTrails(jd: Double, sunRel: SIMD3<Float>, options: DisplayOptions, show: Bool) {
        let v = GalacticMotion.velocityEcliptic
        var rebuilt = 0
        for k in 0..<Self.trailBodies.count {
            let id = Self.trailBodies[(k + trailRoundRobin) % Self.trailBodies.count]
            let body = Catalog.body(id)
            let node = lineNode(&trailNodes, id, order: 6)
            let on = show && visible(body, options)
            node.isHidden = !on
            guard on else { continue }
            let dur = trailDuration(id)
            let built = trailBuiltJD[id]
            let samples = body.kind == .comet ? 900 : (id == .moon ? 240 : 480)
            if built == nil || abs(jd - built!) > dur / Double(samples) * 1.5, rebuilt < 3 {
                rebuilt += 1
                trailBuiltJD[id] = jd
                let pts = GalacticMotion.trail(id, endJD: jd, durationDays: dur, samples: samples)
                let base = SIMD3<Float>(Float(body.color.0), Float(body.color.1), Float(body.color.2))
                let n = pts.count
                let colors = (0..<n).map { i -> SIMD3<Float> in
                    let t = Float(i) / Float(max(n - 1, 1))
                    return base * (0.08 + 0.92 * t * t)
                }
                node.geometry = Geo.lineStrip(pts.map { $0.sceneUnits }, colors: colors, closed: false)
            }
            // Positions are relative to the Sun at the build time; the Sun has moved since.
            let shift = (v * ((jd - (trailBuiltJD[id] ?? jd)) * -86_400)).sceneUnits
            node.simdPosition = sunRel + shift
        }
        trailRoundRobin = (trailRoundRobin + 1) % Self.trailBodies.count

        // The Sun's own straight path and its direction of travel.
        sunTrailNode.isHidden = !show
        motionArrow.isHidden = !show
        if show {
            if sunTrailNode.geometry == nil {
                let len = 365.25 * 60 * 86_400
                let p0 = (v * -len).sceneUnits
                sunTrailNode.geometry = Geo.lineStrip([p0, .zero],
                                                      colors: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1.0, 0.75, 0.3)], closed: false)
            }
            sunTrailNode.simdPosition = sunRel
        }
    }

    // MARK: Per frame

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let jd = state.clock.jd
        let st = Ephemeris.state(jd: jd)
        let options = state.options
        let mode = state.mode
        let now = CACurrentMediaTime()

        // Focus (floating origin), including a fly-to transition.
        var focusKm = st[state.focus]
        var dist = state.distanceKm
        if let fly = state.fly {
            let s = min(1, (now - fly.start) / fly.duration)
            let e = s * s * (3 - 2 * s)
            let pa = st[fly.from], pb = st[fly.to]
            focusKm = pa + (pb - pa) * e
            let gap = length(pb - pa)
            let bump = log(max(1, gap / max(fly.d0, fly.d1))) * 0.55
            dist = exp(log(fly.d0) + (log(fly.d1) - log(fly.d0)) * e + bump * sin(.pi * s))
            if s >= 1 {
                state.fly = nil
                state.distanceKm = fly.d1
                dist = fly.d1
            }
        }

        // Bodies
        for body in Catalog.all {
            let i = body.id.rawValue
            let rel = (st.positions[i] - focusKm).sceneUnits
            containers[i].simdPosition = rel
            containers[i].isHidden = !visible(body, options)
            orientNodes[i].simdOrientation = Ephemeris.orientation(body.id, state: st).sceneQuaternion
        }
        let sunRel = containers[BodyID.sun.rawValue].simdPosition
        sunLight.simdPosition = sunRel

        // Camera orbiting the focus (at the origin).
        let yaw = state.yaw, pitch = state.pitch
        let dUnits = dist / Self.unitKm
        let dir = SIMD3<Double>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        let camPos = SIMD3<Float>(Float(dir.x * dUnits), Float(dir.y * dUnits), Float(dir.z * dUnits))
        cameraNode.simdPosition = camPos
        cameraNode.simdLook(at: .zero, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
        let focusBody = Catalog.body(state.fly?.to ?? state.focus)
        let surface = max(dUnits - focusBody.radiusKm / Self.unitKm, focusBody.radiusKm / Self.unitKm * 0.05)
        let zNear = max(surface * 0.05, 1e-5)
        cameraNode.camera?.zNear = zNear
        cameraNode.camera?.zFar = zNear * 1e10
        skyRoot.simdPosition = camPos
        skyRoot.simdScale = SIMD3<Float>(repeating: Float(zNear * 1e8))

        // Sun glow: at least a few percent of the screen so the Sun is findable from far away.
        let sunDist = Double(simd_length(sunRel - camPos))
        let glowSize = max(BodyID.sun.radiusUnits * 9, sunDist * 0.07)
        sunGlow.simdScale = SIMD3<Float>(repeating: Float(glowSize))

        // Orbits / trails / belt
        if mode != lastMode { lastMode = mode; trailBuiltJD.removeAll() }
        if abs(jd - orbitBuiltJD) > 20 { rebuildOrbits(jd: jd) }
        let showOrbits = options.orbits && mode == .heliocentric
        for (id, node) in orbitNodes {
            let body = Catalog.body(id)
            node.isHidden = !(showOrbits && visible(body, options))
            if node.isHidden { continue }
            let parentRel = body.parent.map { containers[$0.rawValue].simdPosition } ?? sunRel
            node.simdPosition = parentRel
            if body.kind == .moon, body.parent != nil {
                // only near the parent, so moon orbits do not clutter the overview
                let a = length(Ephemeris.relativeToParent(id, jd: jd)) / Self.unitKm
                node.isHidden = Double(simd_length(parentRel - camPos)) > a * 60
            }
        }
        updateTrails(jd: jd, sunRel: sunRel, options: options, show: options.trails && mode == .galactic)
        if mode == .galactic {
            let v = normalize(Frames.eclToScene * GalacticMotion.velocityEcliptic)
            motionArrow.simdPosition = sunRel
            motionArrow.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0),
                                                     to: SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)))
            let s = Float(max(sunDist * 0.18, 2e5))
            motionArrow.simdScale = SIMD3<Float>(s, s, s)
        }
        beltNode.isHidden = !options.belt
        if options.belt {
            beltNode.simdPosition = sunRel
            updateBelt(jd: jd)
        }

        // Comet tails point away from the Sun; length grows near perihelion.
        for (id, tail) in cometTails {
            let p = st[id]
            let rAU = length(p) / Frames.au
            tail.isHidden = rAU > 5 || !options.comets
            if tail.isHidden { continue }
            let len = min(1.5e8, 2.0e7 / pow(max(rAU, 0.3), 2)) / Self.unitKm
            let away = normalize(Frames.eclToScene * p)
            tail.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(away.x), Float(away.y), Float(away.z)))
            tail.simdScale = SIMD3<Float>(Float(len), Float(len), Float(len))
            tail.simdPosition = SIMD3<Float>(Float(away.x), Float(away.y), Float(away.z)) * Float(len / 2)
        }

        let items = LabelLayout.compute(renderer: self, state: st, cameraPos: camPos, options: options, focus: state.focus)
        state.labels = items
        state.markers = items.map { ScreenMarker(id: $0.id, point: $0.point) }

        if now - lastSnapshot > 0.25 {
            lastSnapshot = now
            let cb = onSnapshot
            Task { @MainActor in cb?(st) }
        }
    }

    // MARK: Projection helpers (render thread)

    /// Screen position in UIKit points (origin top-left) and the camera-space depth; nil when behind the camera.
    func project(_ p: SIMD3<Float>, viewSize: CGSize) -> (CGPoint, Float)? {
        let inv = cameraNode.simdWorldTransform.inverse
        let c = inv * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.z < 0 else { return nil }
        let fov = Float((cameraNode.camera?.fieldOfView ?? 50) * .pi / 180)
        let f = Float(viewSize.height) / 2 / tan(fov / 2)
        let x = Float(viewSize.width) / 2 + c.x * f / -c.z
        let y = Float(viewSize.height) / 2 - c.y * f / -c.z
        return (CGPoint(x: CGFloat(x), y: CGFloat(y)), -c.z)
    }

    func containerPosition(_ id: BodyID) -> SIMD3<Float> { containers[id.rawValue].simdPosition }
    var cameraFovRadians: Float { Float((cameraNode.camera?.fieldOfView ?? 50) * .pi / 180) }
}

extension BodyID {
    var radiusUnits: Double { Catalog.body(self).radiusKm / SolarRenderer.unitKm }
}
