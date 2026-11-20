import simd
import SceneKit
import UIKit
import AstroCore

enum Geo {
    /// Unit UV sphere in body-fixed axes (x = prime meridian, z = north). Texture u = 0 at longitude -180,
    /// v = 0 at the north pole: the usual equirectangular planet map with longitude 0 in the middle.
    /// Built here rather than with SCNSphere so the texture-to-longitude mapping is exact.
    static func sphere(segments: Int = 96, rings: Int = 48, inward: Bool = false) -> SCNGeometry {
        var pos: [SCNVector3] = [], nor: [SCNVector3] = [], uv: [CGPoint] = []
        pos.reserveCapacity((segments + 1) * (rings + 1))
        for i in 0...rings {
            let lat = Double.pi / 2 - Double(i) / Double(rings) * .pi
            for j in 0...segments {
                let lon = -Double.pi + Double(j) / Double(segments) * 2 * .pi
                let p = SCNVector3(Float(cos(lat) * cos(lon)), Float(cos(lat) * sin(lon)), Float(sin(lat)))
                pos.append(p)
                nor.append(inward ? SCNVector3(-p.x, -p.y, -p.z) : p)
                uv.append(CGPoint(x: Double(j) / Double(segments), y: Double(i) / Double(rings)))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(segments * rings * 6)
        let w = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segments) {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                // counter-clockwise seen from outside: a(top-left) c(bottom-left) d(bottom-right)
                if inward { idx += [a, d, c, a, b, d] } else { idx += [a, c, d, a, d, b] }
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                      SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }

    /// Flat annulus in the body's equatorial (x-y) plane; texture u runs from inner to outer edge.
    static func ring(inner: Float, outer: Float, segments: Int = 180) -> SCNGeometry {
        var pos: [SCNVector3] = [], nor: [SCNVector3] = [], uv: [CGPoint] = []
        for j in 0...segments {
            let a = Float(j) / Float(segments) * 2 * .pi
            pos.append(SCNVector3(cos(a) * inner, sin(a) * inner, 0)); uv.append(CGPoint(x: 0, y: 0.5))
            pos.append(SCNVector3(cos(a) * outer, sin(a) * outer, 0)); uv.append(CGPoint(x: 1, y: 0.5))
            nor.append(SCNVector3(0, 0, 1)); nor.append(SCNVector3(0, 0, 1))
        }
        var idx: [UInt32] = []
        for j in 0..<UInt32(segments) {
            let a = j * 2, b = a + 1, c = a + 2, d = a + 3
            idx += [a, b, d, a, d, c]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// Line strip with per-vertex colours (RGB pre-multiplied by brightness; drawn additively).
    static func lineStrip(_ pts: [SIMD3<Float>], colors: [SIMD3<Float>], closed: Bool) -> SCNGeometry {
        let verts = pts.map { SCNVector3($0.x, $0.y, $0.z) }
        var idx: [UInt32] = []
        idx.reserveCapacity(pts.count * 2)
        if pts.count > 1 {
            for k in 0..<(pts.count - 1) { idx += [UInt32(k), UInt32(k + 1)] }
            if closed { idx += [UInt32(pts.count - 1), 0] }
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), colorSource],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        g.firstMaterial = lineMaterial()
        return g
    }

    static func lineMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// Points (asteroid belt) with one colour.
    static func points(_ pts: [SIMD3<Float>], size: CGFloat, color: UIColor) -> SCNGeometry {
        let verts = pts.map { SCNVector3($0.x, $0.y, $0.z) }
        let el = SCNGeometryElement(indices: (0..<UInt32(pts.count)).map { $0 }, primitiveType: .point)
        el.pointSize = size
        el.minimumPointScreenSpaceRadius = 0.8
        el.maximumPointScreenSpaceRadius = size
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        g.firstMaterial = m
        return g
    }

    /// Bright-star catalogue as small quads on the unit sphere, each facing the centre (the camera is
    /// always at the centre of the sky node). Ecliptic J2000 axes.
    static func starField() -> SCNGeometry? {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "bin", subdirectory: "Data"),
              let data = try? Data(contentsOf: url) else { return nil }
        let stride = 20
        let n = data.count / stride
        var pos: [SCNVector3] = [], uv: [CGPoint] = [], col: [SIMD4<Float>] = [], idx: [UInt32] = []
        pos.reserveCapacity(n * 4); uv.reserveCapacity(n * 4); col.reserveCapacity(n * 4); idx.reserveCapacity(n * 6)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for s in 0..<n {
                let o = s * stride
                let x = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                let y = raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                let z = raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self)
                let mag = raw.loadUnaligned(fromByteOffset: o + 12, as: Float.self)
                let r = Float(raw[o + 16]) / 255, g = Float(raw[o + 17]) / 255, b = Float(raw[o + 18]) / 255
                let d = simd_normalize(SIMD3<Float>(x, y, z))
                // angular half-size (radians) and brightness from magnitude
                let expo: Float = -0.11 * (mag - 6)
                let size: Float = 0.0011 * powf(10, expo)
                let lin: Float = 0.25 + (6.2 - mag) * 0.16
                let bright: Float = min(1, max(0.12, lin))
                var up = SIMD3<Float>(0, 0, 1)
                if abs(simd_dot(up, d)) > 0.95 { up = SIMD3<Float>(1, 0, 0) }
                let e1 = simd_normalize(simd_cross(up, d)) * size
                let e2 = simd_normalize(simd_cross(d, e1)) * size
                let base = UInt32(pos.count)
                let c: SIMD3<Float> = d * 0.995
                let corners: [SIMD3<Float>] = [c - e1 - e2, c + e1 - e2, c + e1 + e2, c - e1 + e2]
                let uvs: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
                let rgba = SIMD4<Float>(r * bright, g * bright, b * bright, 1)
                for k in 0..<4 {
                    let p = corners[k]
                    pos.append(SCNVector3(p.x, p.y, p.z)); uv.append(uvs[k]); col.append(rgba)
                }
                let quad: [UInt32] = [base, base + 1, base + 2, base, base + 2, base + 3]
                idx.append(contentsOf: quad)
            }
        }
        let colorData = col.withUnsafeBufferPointer { Data(buffer: $0) }
        let cs = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: col.count, usesFloatComponents: true,
                                   componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(textureCoordinates: uv), cs],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = texture("star_sprite.png")
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = true
        g.firstMaterial = m
        return g
    }

    static func texture(_ name: String) -> UIImage? {
        let parts = name.split(separator: ".")
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Textures")
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

extension Mat3 {
    /// SceneKit orientation for a body-fixed (or ecliptic) frame: scene <- ecliptic <- self.
    var sceneQuaternion: simd_quatf {
        let m = Frames.eclToScene * self
        let (c0, c1, c2) = m.columns
        let f = simd_float3x3(SIMD3<Float>(Float(c0.x), Float(c0.y), Float(c0.z)),
                              SIMD3<Float>(Float(c1.x), Float(c1.y), Float(c1.z)),
                              SIMD3<Float>(Float(c2.x), Float(c2.y), Float(c2.z)))
        return simd_quatf(f)
    }
}

extension SIMD3 where Scalar == Double {
    /// Ecliptic km -> scene units (1 unit = 1000 km), as Float.
    var sceneUnits: SIMD3<Float> {
        let s = Frames.eclToScene * self / SolarRenderer.unitKm
        return SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z))
    }
}
