import SceneKit
import ModelIO
import AppKit

/// Procedural-modeling toolkit shared by all scenario scenes.
/// No external assets: terrain, textures, sky, weather, people are all generated in code.
enum SK {

    // MARK: - Math / noise

    /// Deterministic 2D value noise with fractal Brownian motion.
    struct Noise {
        private var perm: [Int] = []

        init(seed: UInt64) {
            var s = seed &+ 0x9E3779B97F4A7C15
            var p = Array(0..<256)
            for i in stride(from: 255, to: 0, by: -1) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let j = Int((s >> 33) % UInt64(i + 1))
                p.swapAt(i, j)
            }
            perm = p + p
        }

        private func hash(_ x: Int, _ y: Int) -> Float {
            Float(perm[(perm[x & 255] + y) & 511]) / 255
        }

        private func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

        /// Value noise in [0, 1].
        func value(_ x: Float, _ y: Float) -> Float {
            let xi = Int(floor(x)), yi = Int(floor(y))
            let xf = x - floor(x), yf = y - floor(y)
            let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
            let u = smooth(xf), v = smooth(yf)
            return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
        }

        /// Fractal noise in roughly [0, 1].
        func fbm(_ x: Float, _ y: Float, octaves: Int = 5, lacunarity: Float = 2, gain: Float = 0.5) -> Float {
            var amp: Float = 0.5, freq: Float = 1, sum: Float = 0, norm: Float = 0
            for _ in 0..<octaves {
                sum += value(x * freq, y * freq) * amp
                norm += amp
                amp *= gain
                freq *= lacunarity
            }
            return sum / norm
        }

        /// Ridged noise (sharp crests), [0, 1].
        func ridged(_ x: Float, _ y: Float, octaves: Int = 5) -> Float {
            var amp: Float = 0.5, freq: Float = 1, sum: Float = 0, norm: Float = 0
            for _ in 0..<octaves {
                let n = 1 - abs(value(x * freq, y * freq) * 2 - 1)
                sum += n * n * amp
                norm += amp
                amp *= 0.5
                freq *= 2
            }
            return sum / norm
        }
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * max(0, min(1, t))
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    static func rgb(_ hex: UInt32) -> NSColor {
        color(CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    // MARK: - Materials

    /// Physically based material.
    static func mat(_ color: NSColor, roughness: CGFloat = 0.8, metalness: CGFloat = 0, emission: NSColor? = nil, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        if let emission { m.emission.contents = emission }
        m.isDoubleSided = doubleSided
        return m
    }

    /// Material with a procedural noise texture (two colors blended by fractal noise).
    static func noiseMat(_ a: NSColor, _ b: NSColor, scale: CGFloat = 4, roughness: CGFloat = 0.85, metalness: CGFloat = 0, seed: UInt64 = 1, repeatUV: CGFloat = 1) -> SCNMaterial {
        let m = mat(a, roughness: roughness, metalness: metalness)
        m.diffuse.contents = noiseImage(a, b, size: 256, scale: Float(scale), seed: seed)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatUV, repeatUV, 1)
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.normal.contents = normalNoiseImage(size: 256, scale: Float(scale) * 2, strength: 2, seed: seed &+ 7)
        m.normal.mipFilter = .linear
        m.normal.maxAnisotropy = 8
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.contentsTransform = SCNMatrix4MakeScale(repeatUV, repeatUV, 1)
        m.normal.intensity = 0.6
        return m
    }

    /// Adds a tiling noise normal map (surface grain) to a material. Mipmapped so it doesn't shimmer far away.
    static func addGrain(_ m: SCNMaterial, scale: Float = 8, strength: Float = 2.5, intensity: CGFloat = 0.4, seed: UInt64 = 5) {
        m.normal.contents = normalNoiseImage(size: 256, scale: scale, strength: strength, seed: seed)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.maxAnisotropy = 16
        m.normal.intensity = intensity
    }

    /// sRGB color → linear components (what shader math expects).
    static func linear(_ c: NSColor) -> SCNVector4 {
        let d = c.usingColorSpace(.sRGB) ?? c
        func f(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return SCNVector4(f(d.redComponent), f(d.greenComponent), f(d.blueComponent), 1)
    }

    /// Ground material shaded per pixel: `flat` on level ground, `steep` on slopes (by the
    /// world-space normal), broken up by procedural noise so it stays crisp up close and far away.
    /// Vertex colors of the mesh still tint the result (use them for large-scale variation).
    static func terrainMaterial(flat: NSColor, steep: NSColor, from: CGFloat = 0.32, to: CGFloat = 0.55,
                                grain: CGFloat = 0.18, noiseScale: CGFloat = 0.08, roughness: CGFloat = 0.85) -> SCNMaterial {
        let m = mat(.white, roughness: roughness)
        m.shaderModifiers = [.surface: """
        #pragma arguments
        float4 flatColor;
        float4 steepColor;
        float slopeFrom;
        float slopeTo;
        float grain;
        float noiseScale;

        #pragma declaration
        float tn_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
        float tn_noise(float3 x) {
            float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
            return mix(mix(mix(tn_hash(i + float3(0,0,0)), tn_hash(i + float3(1,0,0)), f.x),
                           mix(tn_hash(i + float3(0,1,0)), tn_hash(i + float3(1,1,0)), f.x), f.y),
                       mix(mix(tn_hash(i + float3(0,0,1)), tn_hash(i + float3(1,0,1)), f.x),
                           mix(tn_hash(i + float3(0,1,1)), tn_hash(i + float3(1,1,1)), f.x), f.y), f.z);
        }
        float tn_fbm(float3 p) { float a = 0.5; float s = 0.0; for (int k = 0; k < 5; k++) { s += a * tn_noise(p); p *= 2.07; a *= 0.5; } return s; }

        #pragma body
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
        // fade noise out where it would be finer than a pixel (no shimmering rings far away)
        float3 q = wp * noiseScale;
        float fw = length(fwidth(q));
        float n = mix(tn_fbm(q), 0.5, smoothstep(0.25, 0.9, fw));
        float slope = 1.0 - wn.y;
        float t = smoothstep(slopeFrom, slopeTo, slope + (n - 0.5) * 0.3);
        float3 c = mix(flatColor.rgb, steepColor.rgb * (0.65 + 0.7 * n), t);
        float fine = mix(tn_fbm(q * 9.0), 0.5, smoothstep(0.03, 0.12, fw));
        c *= (1.0 - grain * 0.5) + grain * fine;
        _surface.diffuse.rgb = c * _surface.diffuse.rgb;
        """]
        m.setValue(NSValue(scnVector4: linear(flat)), forKey: "flatColor")
        m.setValue(NSValue(scnVector4: linear(steep)), forKey: "steepColor")
        m.setValue(NSNumber(value: Double(from)), forKey: "slopeFrom")
        m.setValue(NSNumber(value: Double(to)), forKey: "slopeTo")
        m.setValue(NSNumber(value: Double(grain)), forKey: "grain")
        m.setValue(NSNumber(value: Double(noiseScale)), forKey: "noiseScale")
        return m
    }

    // Scenes are built on a background thread; the texture cache is shared, so it's locked.
    private static var imageCacheStore: [String: NSImage] = [:]
    private static let imageCacheLock = NSLock()
    private static func cachedImage(_ key: String) -> NSImage? {
        imageCacheLock.lock(); defer { imageCacheLock.unlock() }
        return imageCacheStore[key]
    }
    private static func cacheImage(_ key: String, _ img: NSImage) {
        imageCacheLock.lock(); defer { imageCacheLock.unlock() }
        imageCacheStore[key] = img
    }

    /// Tileable-ish fractal noise image blending two colors.
    static func noiseImage(_ a: NSColor, _ b: NSColor, size: Int, scale: Float, seed: UInt64) -> NSImage {
        let key = "n|\(a)|\(b)|\(size)|\(scale)|\(seed)"
        if let img = cachedImage(key) { return img }
        let noise = Noise(seed: seed)
        let ca = a.usingColorSpace(.deviceRGB) ?? a, cb = b.usingColorSpace(.deviceRGB) ?? b
        var px = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let n = noise.fbm(Float(x) / Float(size) * scale, Float(y) / Float(size) * scale, octaves: 5)
                let t = CGFloat(max(0, min(1, (n - 0.25) * 2)))
                let i = (y * size + x) * 4
                px[i] = UInt8(255 * (ca.redComponent * (1 - t) + cb.redComponent * t))
                px[i + 1] = UInt8(255 * (ca.greenComponent * (1 - t) + cb.greenComponent * t))
                px[i + 2] = UInt8(255 * (ca.blueComponent * (1 - t) + cb.blueComponent * t))
            }
        }
        let img = image(from: px, size: size)
        cacheImage(key, img)
        return img
    }

    /// Normal map derived from fractal noise.
    static func normalNoiseImage(size: Int, scale: Float, strength: Float, seed: UInt64) -> NSImage {
        let key = "nn|\(size)|\(scale)|\(strength)|\(seed)"
        if let img = cachedImage(key) { return img }
        let noise = Noise(seed: seed)
        func h(_ x: Int, _ y: Int) -> Float { noise.fbm(Float(x) / Float(size) * scale, Float(y) / Float(size) * scale, octaves: 4) }
        var px = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (h(x + 1, y) - h(x - 1, y)) * strength
                let dy = (h(x, y + 1) - h(x, y - 1)) * strength
                var n = SIMD3<Float>(-dx, -dy, 1)
                n = n / sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
                let i = (y * size + x) * 4
                px[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                px[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                px[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        let img = image(from: px, size: size)
        cacheImage(key, img)
        return img
    }

    static func image(from px: [UInt8], size: Int, height: Int? = nil) -> NSImage {
        let h = height ?? size
        var data = px
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: size, height: h, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: size, height: h))
    }

    /// Soft round sprite for particles.
    static func dotImage(size: Int = 64, hardness: CGFloat = 0.3) -> NSImage {
        let key = "dot|\(size)|\(hardness)"
        if let img = cachedImage(key) { return img }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.6).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, hardness, 1])!
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        img.unlockFocus()
        cacheImage(key, img)
        return img
    }

    // MARK: - Geometry helpers

    static func node(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        return n
    }

    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, chamfer: CGFloat = 0.02, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        node(SCNBox(width: w, height: h, length: l, chamferRadius: chamfer), m, at: p)
    }

    static func cylinder(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        node(SCNCylinder(radius: r, height: h), m, at: p)
    }

    static func sphere(_ r: CGFloat, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero, segments: Int = 24) -> SCNNode {
        let s = SCNSphere(radius: r)
        s.segmentCount = segments
        return node(s, m, at: p)
    }

    /// Irregular rock (or snow block, boulder …): a sphere mesh pushed in and out by noise.
    /// `radius` in meters; flattened a little so it sits on the ground.
    static func rock(_ radius: Float, _ m: SCNMaterial, seed: UInt64, rings: Int = 10, segments: Int = 14, flatten: Float = 0.65) -> SCNNode {
        let noise = Noise(seed: seed)
        var pts: [SIMD3<Float>] = []
        var uvs: [CGPoint] = []
        var idx: [UInt32] = []
        for r in 0...rings {
            let v = Float(r) / Float(rings)
            let phi = v * .pi
            for sgm in 0...segments {
                let u = Float(sgm) / Float(segments)
                let theta = u * 2 * .pi
                let dir = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                // seamless noise: sample on the unit sphere in 3D-ish via two 2D lookups
                let n = noise.fbm(dir.x * 1.7 + dir.y * 0.9 + 5, dir.z * 1.7 - dir.y * 0.6 + 5, octaves: 3)
                let k = radius * (0.72 + n * 0.62)
                pts.append(SIMD3(dir.x * k, dir.y * k * flatten, dir.z * k))
                uvs.append(CGPoint(x: CGFloat(u) * 2, y: CGFloat(v)))
            }
        }
        let row = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for sgm in 0..<UInt32(segments) {
                let a = r * row + sgm, b = a + 1, c = a + row, d = c + 1
                idx += [a, b, c, b, d, c]
            }
        }
        // the seam column duplicates positions: make them identical so normals match
        for r in 0...rings { pts[r * (segments + 1) + segments] = pts[r * (segments + 1)] }
        let g = mesh(pts, idx, uvs: uvs)
        let nd = node(g, m)
        nd.position.y = CGFloat(radius * flatten * 0.55)
        let holder = SCNNode()
        holder.addChildNode(nd)
        holder.eulerAngles.y = CGFloat(seed % 628) / 100
        return holder
    }

    /// Rebuilds a geometry with each vertex transformed (flat-ish normals recomputed).
    static func displaced(_ g: SCNGeometry, by f: (SIMD3<Float>) -> SIMD3<Float>) -> SCNGeometry? {
        guard let vs = g.sources(for: .vertex).first, let el = g.elements.first else { return nil }
        let count = vs.vectorCount
        var pts: [SIMD3<Float>] = []
        vs.data.withUnsafeBytes { raw in
            for i in 0..<count {
                let off = vs.dataOffset + i * vs.dataStride
                let x = raw.load(fromByteOffset: off, as: Float.self)
                let y = raw.load(fromByteOffset: off + 4, as: Float.self)
                let z = raw.load(fromByteOffset: off + 8, as: Float.self)
                pts.append(f(SIMD3(x, y, z)))
            }
        }
        var idx: [UInt32] = []
        el.data.withUnsafeBytes { raw in
            let n = el.primitiveCount * 3
            for i in 0..<n {
                switch el.bytesPerIndex {
                case 2: idx.append(UInt32(raw.load(fromByteOffset: i * 2, as: UInt16.self)))
                case 4: idx.append(raw.load(fromByteOffset: i * 4, as: UInt32.self))
                default: idx.append(UInt32(raw.load(fromByteOffset: i, as: UInt8.self)))
                }
            }
        }
        guard el.primitiveType == .triangles else { return nil }
        return mesh(pts, idx)
    }

    /// Triangle mesh with smooth normals (and optional per-vertex colors / UVs).
    static func mesh(_ pts: [SIMD3<Float>], _ idx: [UInt32], colors: [SIMD3<Float>]? = nil, uvs: [CGPoint]? = nil) -> SCNGeometry {
        var normals = [SIMD3<Float>](repeating: .zero, count: pts.count)
        var t = 0
        while t + 2 < idx.count {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2])
            let n = cross(pts[b] - pts[a], pts[c] - pts[a])
            normals[a] += n; normals[b] += n; normals[c] += n
            t += 3
        }
        let ns = normals.map { n -> SCNVector3 in
            let l = max(1e-6, sqrt(n.x * n.x + n.y * n.y + n.z * n.z))
            return SCNVector3(CGFloat(n.x / l), CGFloat(n.y / l), CGFloat(n.z / l))
        }
        var sources = [SCNGeometrySource(vertices: pts.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }),
                       SCNGeometrySource(normals: ns)]
        if let uvs { sources.append(SCNGeometrySource(textureCoordinates: uvs)) }
        if let colors {
            var floats: [Float] = []
            floats.reserveCapacity(colors.count * 4)
            for c in colors { floats += [c.x, c.y, c.z, 1] }
            let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                             componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }
        let element = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    /// Height-field terrain centered at the origin. `height(x, z)` in world units;
    /// `color(x, y, z, slope)` gives per-vertex albedo (slope: 0 flat … 1 vertical).
    static func terrain(size: Float, segments: Int, height: (Float, Float) -> Float,
                        color: (Float, Float, Float, Float) -> SIMD3<Float>, material: SCNMaterial, uvRepeat: CGFloat = 12) -> SCNNode {
        let n = segments + 1
        var pts: [SIMD3<Float>] = []
        var uvs: [CGPoint] = []
        pts.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                let x = (Float(i) / Float(segments) - 0.5) * size
                let z = (Float(j) / Float(segments) - 0.5) * size
                pts.append(SIMD3(x, height(x, z), z))
                uvs.append(CGPoint(x: CGFloat(i) / CGFloat(segments) * uvRepeat, y: CGFloat(j) / CGFloat(segments) * uvRepeat))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(segments * segments * 6)
        for j in 0..<segments {
            for i in 0..<segments {
                let a = UInt32(j * n + i), b = a + 1, c = a + UInt32(n), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        // slope from neighbors
        let cell = size / Float(segments)
        var colors: [SIMD3<Float>] = []
        colors.reserveCapacity(pts.count)
        for j in 0..<n {
            for i in 0..<n {
                let p = pts[j * n + i]
                let hx = pts[j * n + min(n - 1, i + 1)].y - pts[j * n + max(0, i - 1)].y
                let hz = pts[min(n - 1, j + 1) * n + i].y - pts[max(0, j - 1) * n + i].y
                let grad = sqrt(hx * hx + hz * hz) / (2 * cell)
                let slope = min(1, grad / 1.2)
                colors.append(color(p.x, p.y, p.z, slope))
            }
        }
        let g = mesh(pts, idx, colors: colors, uvs: uvs)
        g.materials = [material]
        let terrainNode = SCNNode(geometry: g)
        // terrain receives shadows but doesn't cast them: self-shadowing a large height field
        // gives acne (banding) and hard polygonal shadows from distant ridges
        terrainNode.castsShadow = false
        return terrainNode
    }

    // MARK: - People

    enum Pose { case standing, sitting, lying, huddled, waving }

    /// Same hues as the character colors in the UI (Theme.person), a little muted like real fabric.
    static let clothing: [NSColor] = [
        color(0.42, 0.60, 0.80), color(0.80, 0.45, 0.38), color(0.45, 0.68, 0.46), color(0.82, 0.66, 0.30),
        color(0.60, 0.48, 0.80), color(0.38, 0.70, 0.68), color(0.78, 0.44, 0.62)
    ]

    /// Index into `clothing` for a character id (same hash as Theme.person in the UI).
    static func colorIndex(_ id: String) -> Int {
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return Int(h % 7)
    }

    /// Simple, readable human figure (~1.75 m), origin at the feet.
    static func person(color: NSColor, pose: Pose, child: Bool = false, seed: Int = 0) -> SCNNode {
        let root = SCNNode()
        let cloth = mat(color, roughness: 0.9)
        let dark = mat(color.blended(withFraction: 0.45, of: .black) ?? color, roughness: 0.9)
        let skin = mat(rgb(0xD8B49A), roughness: 0.7)
        let s: CGFloat = child ? 0.62 : 1
        func cap(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial) -> SCNNode { node(SCNCapsule(capRadius: r * s, height: h * s), m) }

        let body = SCNNode()
        let torso = cap(0.19, 0.72, cloth); torso.position = SCNVector3(0, 1.18 * s, 0)
        let head = sphere(0.12 * s, skin); head.position = SCNVector3(0, 1.66 * s, 0)
        let hat = sphere(0.125 * s, dark); hat.position = SCNVector3(0, 1.70 * s, -0.01); hat.scale = SCNVector3(1, 0.6, 1)
        let legL = cap(0.08, 0.85, dark); legL.position = SCNVector3(-0.1 * s, 0.45 * s, 0)
        let legR = cap(0.08, 0.85, dark); legR.position = SCNVector3(0.1 * s, 0.45 * s, 0)
        let armL = cap(0.065, 0.66, cloth); armL.position = SCNVector3(-0.27 * s, 1.18 * s, 0)
        let armR = cap(0.065, 0.66, cloth); armR.position = SCNVector3(0.27 * s, 1.18 * s, 0)
        [torso, head, hat, legL, legR, armL, armR].forEach { body.addChildNode($0) }
        root.addChildNode(body)

        switch pose {
        case .standing:
            armL.eulerAngles.z = -0.12
            armR.eulerAngles.z = 0.12
        case .waving:
            armR.eulerAngles.z = 2.6
            armR.position = SCNVector3(0.36 * s, 1.5 * s, 0)
            let wave = SCNAction.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.5, duration: 0.35), .rotateBy(x: 0, y: 0, z: -0.5, duration: 0.35)]))
            armR.runAction(wave)
        case .sitting:
            body.position.y = -0.42 * s
            legL.eulerAngles.x = -1.45; legL.position = SCNVector3(-0.1 * s, 0.82 * s, 0.32 * s)
            legR.eulerAngles.x = -1.45; legR.position = SCNVector3(0.1 * s, 0.82 * s, 0.32 * s)
            armL.eulerAngles.x = -0.9; armR.eulerAngles.x = -0.9
        case .huddled:
            body.position.y = -0.5 * s
            torso.eulerAngles.x = 0.45
            head.position.z += 0.25 * s; hat.position.z += 0.25 * s
            head.position.y -= 0.12 * s; hat.position.y -= 0.12 * s
            legL.eulerAngles.x = -1.2; legL.position = SCNVector3(-0.1 * s, 0.78 * s, 0.3 * s)
            legR.eulerAngles.x = -1.2; legR.position = SCNVector3(0.1 * s, 0.78 * s, 0.3 * s)
            armL.eulerAngles.x = -1.2; armR.eulerAngles.x = -1.2
        case .lying:
            body.eulerAngles.z = .pi / 2
            body.position = SCNVector3(0.9 * s, 0.2 * s, 0)
        }
        root.eulerAngles.y = CGFloat(seed % 628) / 100
        root.castsShadow = true
        return root
    }

    /// Places a group of people around a point. `layout`: arc in front of a shelter, or ring around a fire.
    static func group(_ people: [ScenePerson], around center: SCNVector3, radius: CGFloat, ring: Bool, sitting: Bool, groundY: (CGFloat, CGFloat) -> CGFloat) -> SCNNode {
        let g = SCNNode()
        let n = max(1, people.count)
        for (i, p) in people.enumerated() {
            let a = ring ? (CGFloat(i) / CGFloat(n)) * 2 * .pi : (-0.7 + 1.4 * CGFloat(i) / CGFloat(max(1, n - 1)))
            let x = center.x + cos(a) * radius
            let z = center.z + sin(a) * radius
            let pose: Pose = p.injured ? .lying : (sitting ? .sitting : .standing)
            let fig = person(color: clothing[p.colorIndex % clothing.count], pose: pose, child: p.child, seed: i * 97 + p.colorIndex)
            fig.position = SCNVector3(x, groundY(x, z), z)
            if ring && !p.injured {
                // face the center
                fig.eulerAngles.y = -a - .pi / 2
            }
            g.addChildNode(fig)
        }
        return g
    }

    /// A four-legged animal (dog, camel, pig, cat …) sized by body weight; origin at the feet, facing +z.
    static func animal(weight: Double, color: NSColor, lying: Bool = false, seed: Int = 0) -> SCNNode {
        let outer = SCNNode()
        let root = SCNNode()
        outer.addChildNode(root)
        // characteristic size: a 25 kg dog ≈ 0.55 m at the shoulder; a 450 kg camel ≈ 1.9 m
        let k = CGFloat(pow(max(2, weight) / 25, 1.0 / 3.0))
        let coat = mat(color, roughness: 0.95)
        let darker = mat(color.blended(withFraction: 0.35, of: .black) ?? color, roughness: 0.95)
        let legLen: CGFloat = (weight > 200 ? 0.62 : 0.34) * k
        let bodyLen: CGFloat = 0.62 * k
        let bodyR: CGFloat = 0.17 * k
        let body = node(SCNCapsule(capRadius: bodyR, height: bodyLen + bodyR * 2), coat)
        body.eulerAngles.x = .pi / 2
        body.position = SCNVector3(0, legLen + bodyR * 0.8, 0)
        root.addChildNode(body)
        let neck = node(SCNCapsule(capRadius: bodyR * 0.45, height: (weight > 200 ? 0.9 : 0.3) * k), coat)
        neck.position = SCNVector3(0, legLen + bodyR * 1.4 + (weight > 200 ? 0.25 * k : 0), bodyLen * 0.55)
        neck.eulerAngles.x = weight > 200 ? 0.35 : 0.9
        root.addChildNode(neck)
        let head = node(SCNCapsule(capRadius: bodyR * 0.55, height: bodyR * 2.4), coat)
        head.eulerAngles.x = .pi / 2 - 0.25
        head.position = SCNVector3(0, legLen + bodyR * 1.9 + (weight > 200 ? 0.6 * k : 0.05 * k), bodyLen * 0.78)
        root.addChildNode(head)
        if weight > 200 {
            // a camel's humps
            for dz in [-0.12, 0.16] as [CGFloat] {
                let hump = sphere(bodyR * 0.75, coat, at: SCNVector3(0, legLen + bodyR * 1.6, dz * k))
                hump.scale = SCNVector3(0.8, 1, 0.9)
                root.addChildNode(hump)
            }
        } else {
            for dx in [-1, 1] as [CGFloat] {
                let ear = node(SCNCone(topRadius: 0, bottomRadius: bodyR * 0.22, height: bodyR * 0.6), darker)
                ear.position = SCNVector3(dx * bodyR * 0.3, legLen + bodyR * 2.6, bodyLen * 0.7)
                root.addChildNode(ear)
            }
            let tail = node(SCNCapsule(capRadius: bodyR * 0.12, height: bodyLen * 0.5), darker)
            tail.position = SCNVector3(0, legLen + bodyR * 1.2, -bodyLen * 0.75)
            tail.eulerAngles.x = -0.8
            root.addChildNode(tail)
        }
        for (dx, dz) in [(-1, 1), (1, 1), (-1, -1), (1, -1)] as [(CGFloat, CGFloat)] {
            let leg = node(SCNCapsule(capRadius: bodyR * 0.25, height: legLen + bodyR * 0.5), darker)
            leg.position = SCNVector3(dx * bodyR * 0.55, (legLen + bodyR * 0.5) / 2, dz * bodyLen * 0.42)
            root.addChildNode(leg)
        }
        if lying {
            root.eulerAngles.z = .pi / 2
            root.position.y = bodyR
        }
        outer.eulerAngles.y = CGFloat(seed % 628) / 100
        return outer
    }

    /// A body covered with a blanket or tarp (for the dead).
    static func shroud(color: NSColor = rgb(0x5B6470), seed: Int = 0) -> SCNNode {
        let n = node(SCNCapsule(capRadius: 0.24, height: 1.8), mat(color, roughness: 0.95))
        n.eulerAngles.x = .pi / 2
        n.scale = SCNVector3(1, 1, 0.55)
        n.position.y = 0.12
        let r = SCNNode()
        r.addChildNode(n)
        r.eulerAngles.y = CGFloat(seed % 314) / 100
        return r
    }

    // MARK: - Particles

    static func snow(intensity: Double, wind: Double, area: CGFloat = 80, height: CGFloat = 30) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(300 + 2400 * intensity)
        p.particleLifeSpan = 6
        p.particleLifeSpanVariation = 2
        p.emitterShape = SCNBox(width: area, height: 1, length: area, chamferRadius: 0)
        p.birthLocation = .volume
        p.particleImage = dotImage(size: 32, hardness: 0.4)
        p.particleSize = 0.07
        p.particleSizeVariation = 0.04
        p.particleColor = NSColor(white: 1, alpha: 0.9)
        p.particleVelocity = CGFloat(2 + intensity * 2)
        p.particleVelocityVariation = 1
        p.emittingDirection = SCNVector3(0, -1, 0)
        p.acceleration = SCNVector3(CGFloat(wind / 6), -1.5, CGFloat(wind / 20))
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.warmupDuration = 6
        p.particleColorVariation = SCNVector4(0, 0, 0, 0.2)
        _ = height
        return p
    }

    static func rain(intensity: Double, wind: Double, area: CGFloat = 80) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(800 + 4000 * intensity)
        p.particleLifeSpan = 1.6
        p.emitterShape = SCNBox(width: area, height: 1, length: area, chamferRadius: 0)
        p.birthLocation = .volume
        p.particleImage = dotImage(size: 16, hardness: 0.8)
        p.particleSize = 0.035
        p.stretchFactor = 0.08
        p.particleColor = NSColor(white: 0.85, alpha: 0.45)
        p.particleVelocity = 22
        p.emittingDirection = SCNVector3(CGFloat(wind / 60), -1, 0)
        p.acceleration = SCNVector3(CGFloat(wind / 4), -9.8, 0)
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.warmupDuration = 2
        return p
    }

    /// Blowing sand / dust.
    static func dust(intensity: Double, wind: Double, color: NSColor, area: CGFloat = 90) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(200 + 3000 * intensity)
        p.particleLifeSpan = 5
        p.emitterShape = SCNBox(width: area, height: 8, length: area, chamferRadius: 0)
        p.birthLocation = .volume
        p.particleImage = dotImage(size: 64, hardness: 0.1)
        p.particleSize = CGFloat(0.4 + intensity * 0.8)
        p.particleSizeVariation = 0.3
        p.particleColor = color.withAlphaComponent(CGFloat(0.08 + intensity * 0.12))
        p.particleVelocity = CGFloat(wind / 4)
        p.emittingDirection = SCNVector3(1, 0.05, 0.2)
        p.spreadingAngle = 25
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.warmupDuration = 5
        return p
    }

    static func fire(scale: CGFloat = 1) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 160 * scale
        p.particleLifeSpan = 0.7
        p.particleLifeSpanVariation = 0.3
        p.emitterShape = SCNSphere(radius: 0.25 * scale)
        p.birthLocation = .volume
        p.particleImage = dotImage(size: 64, hardness: 0.2)
        p.particleSize = 0.32 * scale
        p.particleSizeVariation = 0.15 * scale
        p.particleColor = rgb(0xFF8A2A)
        p.particleColorVariation = SCNVector4(0.05, 0.1, 0.1, 0)
        p.particleVelocity = 1.4 * scale
        p.particleVelocityVariation = 0.6
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 12
        p.blendMode = .additive
        p.isLightingEnabled = false
        p.warmupDuration = 1
        let fade = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0.2, 1, 0.6, 0] as [NSNumber]
            a.keyTimes = [0, 0.15, 0.6, 1] as [NSNumber]
            return a
        }())
        p.propertyControllers = [.opacity: fade]
        return p
    }

    static func smoke(scale: CGFloat = 1, color: NSColor = NSColor(white: 0.78, alpha: 0.22)) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 10 * scale
        p.particleLifeSpan = 6
        p.emitterShape = SCNSphere(radius: 0.3 * scale)
        p.particleImage = dotImage(size: 64, hardness: 0.05)
        p.particleSize = 0.8 * scale
        p.particleSizeVariation = 0.4
        p.particleColor = color
        p.particleVelocity = 1.2
        p.emittingDirection = SCNVector3(0.15, 1, 0)
        p.spreadingAngle = 15
        p.acceleration = SCNVector3(0.3, 0.2, 0)
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.warmupDuration = 6
        let grow = SCNParticlePropertyController(animation: {
            let a = CABasicAnimation()
            a.fromValue = 0.6
            a.toValue = 3.0
            return a
        }())
        let fade = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0, 0.8, 0] as [NSNumber]
            a.keyTimes = [0, 0.2, 1] as [NSNumber]
            return a
        }())
        p.propertyControllers = [.size: grow, .opacity: fade]
        return p
    }

    // MARK: - Lights

    /// A light node whose flicker follows an adjustable base intensity.
    final class FlickerLight: SCNNode {
        var base: CGFloat = 900
    }

    /// A warm flickering point light (fire, lamp). Change `base` to dim or brighten it.
    static func fireLight(intensity: CGFloat = 900, color: NSColor = rgb(0xFF9A4A), range: CGFloat = 14) -> FlickerLight {
        let l = SCNLight()
        l.type = .omni
        l.color = color
        l.intensity = intensity
        l.attenuationStartDistance = 0
        l.attenuationEndDistance = range
        l.attenuationFalloffExponent = 2
        l.castsShadow = false
        let n = FlickerLight()
        n.base = intensity
        n.light = l
        let flicker = SCNAction.repeatForever(.sequence([
            .customAction(duration: 0.12) { node, _ in
                node.light?.intensity = ((node as? FlickerLight)?.base ?? intensity) * CGFloat.random(in: 0.75...1.1)
            },
            .wait(duration: 0.05)
        ]))
        n.runAction(flicker)
        return n
    }

    // MARK: - Water

    /// Animated water surface (vertex waves in a shader modifier).
    static func water(size: CGFloat, color: NSColor, amplitude: Float = 0.25, choppiness: Float = 1, transparency: CGFloat = 0.85, roughness: CGFloat = 0.12, segments: Int = 160) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        plane.widthSegmentCount = segments
        plane.heightSegmentCount = segments
        let m = mat(color, roughness: roughness, metalness: 0.05)
        m.transparency = transparency
        m.transparencyMode = .dualLayer
        m.normal.contents = normalNoiseImage(size: 256, scale: 8, strength: 3, seed: 99)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.contentsTransform = SCNMatrix4MakeScale(size / 6, size / 6, 1)
        m.normal.mipFilter = .linear
        m.normal.maxAnisotropy = 16
        m.normal.intensity = 0.5
        m.shaderModifiers = [.geometry: """
        #pragma arguments
        float amplitude;
        float choppiness;
        #pragma body
        float t = scn_frame.time;
        float3 p = _geometry.position.xyz;
        float k1 = 0.18 * choppiness, k2 = 0.29 * choppiness, k3 = 0.71 * choppiness;
        float h = sin(p.x * k1 + t * 0.9) * 0.55 + sin(p.y * k2 - t * 1.25) * 0.35 + sin((p.x + p.y) * k3 + t * 1.9) * 0.10;
        float dx = cos(p.x * k1 + t * 0.9) * 0.55 * k1 + cos((p.x + p.y) * k3 + t * 1.9) * 0.10 * k3;
        float dy = cos(p.y * k2 - t * 1.25) * 0.35 * k2 + cos((p.x + p.y) * k3 + t * 1.9) * 0.10 * k3;
        _geometry.position.z += h * amplitude;
        _geometry.normal = normalize(float3(-dx * amplitude, -dy * amplitude, 1.0));
        """]
        m.setValue(NSNumber(value: amplitude), forKey: "amplitude")
        m.setValue(NSNumber(value: choppiness), forKey: "choppiness")
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.castsShadow = false
        return n
    }

    // MARK: - Sky & atmosphere

    enum SkyStyle { case alpine, sea, desert, tropical, polar, overcast, none }

    /// Physical daylight sky (Preetham-like, via ModelIO), an overcast gradient, or a starry night sky.
    /// Returns something SceneKit accepts as `background.contents` / `lightingEnvironment.contents`.
    static func skyImage(style: SkyStyle, sunElevationDeg: Double, overcast: Double, azimuthDeg: Double = 150) -> Any? {
        if style == .none { return NSColor.black }
        let elev = sunElevationDeg
        // how dark: 0 day … 1 night
        let dark = CGFloat(max(0, min(1, (2 - elev) / 10)))
        if elev < -7 {
            if overcast > 0.6 { return gradientSky(top: rgb(0x05070B), horizon: rgb(0x10141A)) }
            return nightSky(seed: 7, aurora: style == .polar)
        }
        if overcast > 0.6 {
            let top = rgb(0x8A929C).blended(withFraction: dark * 0.92, of: rgb(0x05070B)) ?? .gray
            let hor = rgb(0xB7BDC4).blended(withFraction: dark * 0.9, of: rgb(0x0E1218)) ?? .gray
            return gradientSky(top: top, horizon: hor)
        }
        let turbidity: Float
        switch style {
        case .alpine, .polar: turbidity = 0.08
        case .desert: turbidity = 0.6
        case .tropical, .sea: turbidity = 0.32
        default: turbidity = 0.28
        }
        let sky = MDLSkyCubeTexture(name: nil, channelEncoding: .uInt8, textureDimensions: vector_int2(256, 256),
                                    turbidity: turbidity, sunElevation: Float(max(0.01, elev / 90)), upperAtmosphereScattering: 0.3,
                                    groundAlbedo: style == .alpine || style == .polar ? 0.85 : 0.3)
        sky.sunAzimuth = Float(azimuthDeg * .pi / 180)
        sky.brightness = Float(0.25 - 0.2 * Double(dark))
        sky.exposure = Float(-1.5 * Double(dark))
        sky.saturation = 1.1
        sky.groundColor = rgb(style == .desert ? 0x8A6E52 : (style == .sea || style == .tropical ? 0x1E3A4A : 0x9AA4AE)).cgColor
        sky.update()
        return sky.imageFromTexture()?.takeUnretainedValue()
    }

    static func gradientSky(top: NSColor, horizon: NSColor) -> NSImage {
        let w = 512, h = 256
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let a = top.usingColorSpace(.deviceRGB) ?? top, b = horizon.usingColorSpace(.deviceRGB) ?? horizon
        for y in 0..<h {
            let t = CGFloat(y) / CGFloat(h)      // 0 top → 1 bottom
            let k = min(1, t * 1.8)
            for x in 0..<w {
                let i = (y * w + x) * 4
                px[i] = UInt8(255 * (a.redComponent * (1 - k) + b.redComponent * k))
                px[i + 1] = UInt8(255 * (a.greenComponent * (1 - k) + b.greenComponent * k))
                px[i + 2] = UInt8(255 * (a.blueComponent * (1 - k) + b.blueComponent * k))
            }
        }
        return image(from: px, size: w, height: h)
    }

    /// Equirectangular night sky with stars (and an optional aurora band).
    static func nightSky(seed: UInt64, aurora: Bool) -> NSImage {
        let key = "night|\(seed)|\(aurora)"
        if let img = cachedImage(key) { return img }
        // large enough that a star is about one screen pixel
        let w = 4096, h = 2048
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let noise = Noise(seed: seed)
        var s = seed
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        for y in 0..<h {
            let t = Double(y) / Double(h)
            // deep blue to black, a little lighter near the horizon (t = 0.5)
            let k = max(0, 1 - abs(t - 0.5) * 2.4)
            let r0 = 0.008 + 0.03 * k * k, g0 = 0.012 + 0.036 * k * k, b0 = 0.03 + 0.06 * k * k
            for x in 0..<w {
                var r = r0, g = g0, b = b0
                if aurora && t > 0.18 && t < 0.42 {
                    let band = exp(-pow((t - 0.3 - 0.05 * Double(noise.fbm(Float(x) / 560, 3, octaves: 3))) / 0.045, 2))
                    if band > 0.01 {
                        let curtain = Double(noise.fbm(Float(x) / 120, Float(y) / 360, octaves: 4))
                        r += 0.03 * band * curtain; g += 0.5 * band * curtain; b += 0.2 * band * curtain
                    }
                }
                let i = (y * w + x) * 4
                px[i] = UInt8(min(255, r * 255)); px[i + 1] = UInt8(min(255, g * 255)); px[i + 2] = UInt8(min(255, b * 255))
            }
        }
        // stars: mostly faint, a few bright ones; fewer toward the horizon (haze)
        for _ in 0..<9000 {
            let x = Int(rnd() * Double(w)), y = Int(pow(rnd(), 1.2) * Double(h) * 0.49)
            let haze = Double(y) / (Double(h) * 0.5)
            let m = pow(rnd(), 3)
            let bright = (60 + 195 * m) * (1 - 0.6 * haze)
            let tint = rnd()
            let i = (y * w + x) * 4
            px[i] = UInt8(min(255, bright * (tint < 0.2 ? 1.0 : 0.92)))
            px[i + 1] = UInt8(min(255, bright * 0.95))
            px[i + 2] = UInt8(min(255, bright * (tint > 0.8 ? 1.0 : 0.9) + 10))
        }
        let img = image(from: px, size: w, height: h)
        cacheImage(key, img)
        return img
    }
}
