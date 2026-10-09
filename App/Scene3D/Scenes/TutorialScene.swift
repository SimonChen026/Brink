import SceneKit
import AppKit

/// 雨夜 (the tutorial) — an abandoned road-maintenance hut (道班房) on a county road in north-west
/// Yunnan, ~2,100 m, an October evening in the rain.
///
/// Layout (meters): the road runs along x at z ≈ 0, cut into a forested slope that rises to the north
/// (−z) behind a stone retaining wall and drops into a deep valley to the south (+z). The hut stands on
/// a pad north of the road at x ≈ −6, its door facing the road; the bus is stopped in the right-hand
/// lane at x ≈ 8…20, hazard lights blinking, facing the landslide that buries the road at x ≈ 30…48.
/// State shown: the stove (windows and door glow, chimney smoke), the leaking roof and the tarp over it
/// (shelter), the firewood stack (res.fuel), the warning triangle, SOS stones and a torch (var.signal),
/// the shop cartons (flags goods_*), the drone's parcel (flag drone), and the rescue — excavator, road
/// crew, a van and a cleared lane (event r4_rescue / flag rescued).
final class TutorialScene: ScenarioScene {
    private let noise = SK.Noise(seed: 1007)
    /// The hut's center on its pad (front wall at z = hutZ + 2.5).
    private let hutX: CGFloat = -6, hutZ: CGFloat = -9.5
    private var glowMats: [SCNMaterial] = []
    private var chimney: (SCNParticleSystem, SCNNode)?
    private var roofHole: SCNNode?
    private var tarp: SCNNode?
    private var logs: [SCNNode] = []
    private var triangle: SCNNode?
    private var sosStones: [SCNNode] = []
    private var torch: SCNNode?
    private var cartonsClosed: SCNNode?
    private var cartonsOpen: SCNNode?
    private var parcel: SCNNode?
    private var slide: SCNNode?
    private var slideCleared: SCNNode?
    private var rescue: SCNNode?
    private var workLight: SCNNode?

    required init() {
        super.init()
        skyStyle = .alpine
        sunPeak = 55                 // ~27°N in October
        sunAzimuth = 200
        exposure = -0.1
        iblScale = 1.1
        hazeColor = SK.rgb(0xB9C3CA)
        stormColor = SK.rgb(0x939CA4)
        clearVisibility = 1500
        weatherArea = 75
        weatherCenter = SCNVector3(22, 20, 0)
        cameraTarget = SCNVector3(6, 2.2, 0.3)
        cameraDistance = 42.5
        cameraYaw = -92
        cameraPitch = 8.5
        cameraFOV = 44
    }

    // MARK: Terrain

    /// Height of the ground (without the landslide) at (x, z).
    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(baseHeight(Float(x), Float(z))) }

    private func baseHeight(_ x: Float, _ z: Float) -> Float {
        // the road bench and the hut pad stay flat at road level
        let pad = SK.smoothstep(-14.5, -13, x) * (1 - SK.smoothstep(1, 2.5, x))  // 1 behind the hut (the gap in the wall)
        let flatTo: Float = 7.0 + 6.5 * pad                                       // how far back the flat ground reaches
        if z < -flatTo {
            // up the mountain: behind the retaining wall (or the earth bank behind the hut)
            let d = -z - flatTo
            var h = 2.4 * (1 - pad) + d * 0.9 * pad * (1 - SK.smoothstep(4, 12, d))
            h += 170 * (1 - exp(-d / 190)) + 0.12 * d
            h += (noise.fbm(x / 70, z / 70, octaves: 4) - 0.5) * 34 * SK.smoothstep(6, 70, d)
            h += (noise.ridged(x / 36 + 3, z / 36, octaves: 3) - 0.3) * 9 * SK.smoothstep(8, 45, d)
            h += (noise.fbm(x / 9, z / 9, octaves: 3) - 0.5) * 1.4 * SK.smoothstep(1, 6, d)
            return h
        }
        if z > 4.9 {
            // a narrow shoulder, then the drop into the valley; the far side rises again
            let d = z - 4.9
            let t = min(1, max(0, (d - 1.5) / 240))
            var h = -0.2 * SK.smoothstep(0, 1.5, d) - 175 * (1 - pow(1 - t, 1.7))
            h += 330 * SK.smoothstep(330, 950, d)
            h += (noise.fbm(x / 90, z / 90, octaves: 4) - 0.5) * 44 * SK.smoothstep(20, 140, d)
            h += (noise.ridged(x / 150 + 9, z / 150, octaves: 4) - 0.3) * 120 * SK.smoothstep(380, 800, d)
            h += (noise.fbm(x / 11, z / 11, octaves: 3) - 0.5) * 1.6 * SK.smoothstep(2, 10, d)
            return h
        }
        return 0
    }

    /// How much the landslide adds on top of the ground (m). `cleared`: the road crew's lane through it.
    private func bump(_ x: Float, _ z: Float, cleared: Bool = false) -> Float {
        let up = max(0, -z - 7.5)                                  // distance up the scar
        let cx: Float = 38 + up * 0.06
        let width: Float = 9.5 + 5 * SK.smoothstep(18, 42, up)      // the head scarp is wider than the chute
        let across = exp(-pow((x - cx) / width, 2))
        var b: Float
        if z > 6 {
            b = 4.6 * across * exp(-(z - 6) / 30)                   // the debris tongue running down into the valley
        } else if z > -7.5 {
            b = 4.6 * across                                       // the road buried
        } else {
            let fade = 1 - SK.smoothstep(24, 36, up)
            b = (0.55 + 4.0 * exp(-up / 6)) * across * fade        // raw earth up the scar
            b *= SK.smoothstep(0.25, 0.45, noise.fbm(x / 9 + 20, z / 9, octaves: 3) + 0.25 * across)
        }
        b *= 0.8 + 0.5 * noise.fbm(x / 4, z / 4, octaves: 3)
        if cleared {
            // the inner lane cut through from the far side, a low ridge of mud still across it
            let lane = SK.smoothstep(-4.6, -3.8, z) * (1 - SK.smoothstep(0.2, 1.0, z))
            b *= 1 - lane * (0.55 + 0.45 * SK.smoothstep(31, 33.5, x))
        }
        return b
    }

    /// The landslide's surface: tucked under the ground where it doesn't reach.
    private func slideHeight(_ x: Float, _ z: Float, cleared: Bool = false) -> Float {
        let b = bump(x, z, cleared: cleared)
        return baseHeight(x, z) + b - 0.6 * (1 - SK.smoothstep(0, 0.25, b))
    }

    private func slideGround(_ x: CGFloat, _ z: CGFloat) -> CGFloat {
        max(0.03, CGFloat(slideHeight(Float(x), Float(z))))
    }

    /// A height field over a rectangle, vertex colors from `color(x, y, z)`.
    private func heightField(x0: Float, x1: Float, z0: Float, z1: Float, cell: Float,
                             height: (Float, Float) -> Float, color: (Float, Float, Float) -> SIMD3<Float>,
                             material: SCNMaterial) -> SCNNode {
        let nx = Int(((x1 - x0) / cell).rounded()), nz = Int(((z1 - z0) / cell).rounded())
        var pts: [SIMD3<Float>] = [], cols: [SIMD3<Float>] = [], uvs: [CGPoint] = []
        pts.reserveCapacity((nx + 1) * (nz + 1))
        for j in 0...nz {
            for i in 0...nx {
                let x = x0 + Float(i) * cell, z = z0 + Float(j) * cell
                let y = height(x, z)
                pts.append(SIMD3(x, y, z))
                cols.append(color(x, y, z))
                uvs.append(CGPoint(x: CGFloat(x / 4), y: CGFloat(z / 4)))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(nx * nz * 6)
        let row = UInt32(nx + 1)
        for j in 0..<UInt32(nz) {
            for i in 0..<UInt32(nx) {
                let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let g = SK.mesh(pts, idx, colors: cols, uvs: uvs)
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.castsShadow = false
        return n
    }

    // MARK: Build

    override func build(_ s: SceneState) {
        // forest floor and grass on gentle ground, wet rock on the steep cuts (per pixel)
        let groundMat = SK.terrainMaterial(flat: SK.rgb(0x5D6A47), steep: SK.rgb(0x6C665C), from: 0.55, to: 0.75,
                                           grain: 0.2, noiseScale: 0.06, roughness: 0.8)
        SK.addGrain(groundMat, scale: 10, strength: 2.5, intensity: 0.3)
        let terrain = SK.terrain(size: 640, segments: 320, height: baseHeight, color: { x, y, z, _ in
            // damp hollows a little darker, the valley floor bluish in the haze
            let k = 0.82 + 0.3 * self.noise.fbm(x / 23, z / 23, octaves: 3)
            return SIMD3(k * 0.98, k, k * (y < -60 ? 1.06 : 0.97))
        }, material: groundMat, uvRepeat: 160)
        world.addChildNode(terrain)
        // distant ridges beyond the near terrain (pushed under it inside)
        let farMat = SK.terrainMaterial(flat: SK.rgb(0x4E5C45), steep: SK.rgb(0x5E5B56), from: 0.5, to: 0.7, grain: 0.1, noiseScale: 0.01)
        let far = SK.terrain(size: 3600, segments: 200, height: { x, z in
            let inside = 1 - SK.smoothstep(296, 318, max(abs(x), abs(z)))
            return self.baseHeight(x, z) - 60 * inside
        }, color: { _, _, _, _ in SIMD3(1, 1, 1) }, material: farMat, uvRepeat: 300)
        world.addChildNode(far)

        buildRoad()
        buildWall()
        buildGuardrail()
        buildForest()
        buildMist()
        buildHut(english: s.lang == "en")
        buildBus()
        buildSlide()
        buildSignal()
        buildProps()
        // the stove inside the hut: its light spills out of the door and windows onto the porch and the road
        let stove = addFire(at: SCNVector3(hutX + 1.6, 0, hutZ - 0.6), scale: 0.8, style: .stove)
        if let glow = stove.childNodes.first(where: { $0 is SK.FlickerLight }), let l = glow.light {
            l.type = .spot
            l.spotInnerAngle = 50
            l.spotOuterAngle = 150
            l.attenuationEndDistance = 16
            glow.position = SCNVector3(-1.2, 1.5, 2.9)       // just inside the front wall
            glow.eulerAngles.y = .pi                          // facing out toward the road
        }
    }

    private func buildRoad() {
        let asphalt = SK.noiseMat(SK.rgb(0x2C2F32), SK.rgb(0x383B3E), scale: 30, roughness: 0.3, seed: 41)
        asphalt.diffuse.contentsTransform = SCNMatrix4MakeScale(80, 1, 1)
        asphalt.normal.contentsTransform = SCNMatrix4MakeScale(320, 4, 1)
        asphalt.normal.intensity = 0.12
        world.addChildNode(SK.box(640, 0.06, 8.5, asphalt, chamfer: 0))
        // gutter at the foot of the wall, gravel shoulder on the valley side
        world.addChildNode(SK.box(640, 0.04, 0.6, SK.mat(SK.rgb(0x77777A), roughness: 0.9), chamfer: 0, at: SCNVector3(0, 0.0, -4.55)))
        world.addChildNode(SK.box(640, 0.05, 0.62, SK.noiseMat(SK.rgb(0x6A6660), SK.rgb(0x575350), scale: 40, seed: 43), chamfer: 0, at: SCNVector3(0, 0.0, 4.55)))
        // markings: yellow dashes down the middle, white edge lines
        let marks = SCNNode()
        let yellow = SK.mat(SK.rgb(0xD8B23C), roughness: 0.5)
        let white = SK.mat(SK.rgb(0xD9DBDC), roughness: 0.5)
        for i in 0..<70 {
            let x = -315 + CGFloat(i) * 9
            marks.addChildNode(SK.box(4, 0.012, 0.15, yellow, chamfer: 0, at: SCNVector3(x, 0.034, 0)))
        }
        for z in [-3.95, 3.95] as [CGFloat] {
            marks.addChildNode(SK.box(640, 0.012, 0.12, white, chamfer: 0, at: SCNVector3(0, 0.034, z)))
        }
        world.addChildNode(marks.flattenedClone())
    }

    private func buildWall() {
        // a masonry retaining wall with a concrete coping; it breaks off where the slide came down
        let ends = SK.noiseMat(SK.rgb(0x8C877D), SK.rgb(0x625E57), scale: 9, roughness: 0.9, seed: 51)
        for (a, b) in [(-320, -14.5), (2.5, 27.5), (49, 320)] as [(CGFloat, CGFloat)] {
            let len = b - a
            let stone = SK.noiseMat(SK.rgb(0x8C877D), SK.rgb(0x625E57), scale: 9, roughness: 0.9, seed: 51)
            stone.diffuse.contentsTransform = SCNMatrix4MakeScale(len / 5, 0.7, 1)
            stone.normal.contentsTransform = SCNMatrix4MakeScale(len / 5, 0.7, 1)
            stone.normal.intensity = 1.0
            let wall = SK.box(len, 2.4, 2.2, stone, chamfer: 0.03, at: SCNVector3((a + b) / 2, 1.2, -6.0))
            // box faces: front, right, back, left, top, bottom (the ends get an unstretched texture)
            wall.geometry?.materials = [stone, ends, stone, ends, ends, ends]
            world.addChildNode(wall)
            world.addChildNode(SK.box(len, 0.18, 0.5, SK.mat(SK.rgb(0x9C9A94), roughness: 0.85), chamfer: 0.02, at: SCNVector3((a + b) / 2, 2.45, -5.15)))
        }
        // drain holes along the stretch near the hut
        let holes = SCNNode()
        let dark = SK.mat(SK.rgb(0x151513), roughness: 1)
        for i in 0..<30 {
            let x = -60 + CGFloat(i) * 3.4
            if x > -16 && x < 4 { continue }
            if x > 27 { break }
            holes.addChildNode(SK.box(0.14, 0.14, 0.02, dark, chamfer: 0, at: SCNVector3(x, 0.7, -4.89)))
        }
        world.addChildNode(holes.flattenedClone())
    }

    private func buildGuardrail() {
        // white concrete posts with red tops and a steel beam, missing where the slide went over the edge
        let rail = SCNNode()
        let concrete = SK.mat(SK.rgb(0xDADAD5), roughness: 0.8)
        let red = SK.mat(SK.rgb(0xB0352B), roughness: 0.6)
        let steel = SK.mat(SK.rgb(0x9DA2A6), roughness: 0.4, metalness: 0.7)
        var x: CGFloat = -150
        while x <= 150 {
            if x < 27 || x > 51 {
                rail.addChildNode(SK.box(0.2, 0.8, 0.2, concrete, chamfer: 0.02, at: SCNVector3(x, 0.4, 4.6)))
                rail.addChildNode(SK.box(0.21, 0.14, 0.21, red, chamfer: 0.01, at: SCNVector3(x, 0.74, 4.6)))
            }
            x += 3
        }
        for (a, b) in [(-150, 26), (52, 150)] as [(CGFloat, CGFloat)] {
            rail.addChildNode(SK.box(b - a, 0.3, 0.06, steel, chamfer: 0.01, at: SCNVector3((a + b) / 2, 0.55, 4.48)))
        }
        world.addChildNode(rail.flattenedClone())
    }

    private func buildForest() {
        // Yunnan pines on both slopes, thinning out with patchy density. Built as three merged meshes
        // (trunks and two shades of crown); geometry shared between nodes doesn't survive flattening.
        struct Buffer { var pts: [SIMD3<Float>] = []; var cols: [SIMD3<Float>] = []; var idx: [UInt32] = [] }
        func cone(_ b: inout Buffer, _ base: SIMD3<Float>, _ r: Float, _ h: Float, _ tint: Float, _ turn: Float) {
            let n = 7, first = UInt32(b.pts.count)
            for i in 0..<n {
                let a = turn + Float(i) / Float(n) * 2 * .pi
                b.pts.append(base + SIMD3(cos(a) * r, 0, sin(a) * r))
                b.cols.append(SIMD3(repeating: tint))
            }
            for i in 0..<n {
                // one apex per face keeps the facets readable
                let apex = UInt32(b.pts.count)
                b.pts.append(base + SIMD3(0, h, 0))
                b.cols.append(SIMD3(repeating: tint * 1.08))
                b.idx += [first + UInt32(i), apex, first + UInt32((i + 1) % n)]
            }
        }
        func trunk(_ b: inout Buffer, _ base: SIMD3<Float>, _ r: Float, _ h: Float) {
            let n = 5, first = UInt32(b.pts.count)
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi
                b.pts.append(base + SIMD3(cos(a) * r, 0, sin(a) * r))
                b.pts.append(base + SIMD3(cos(a) * r * 0.7, h, sin(a) * r * 0.7))
                b.cols += [SIMD3(repeating: 1), SIMD3(repeating: 1)]
            }
            for i in 0..<n {
                let b0 = first + UInt32(i * 2), t0 = b0 + 1
                let b1 = first + UInt32(((i + 1) % n) * 2), t1 = b1 + 1
                b.idx += [b0, t0, b1, b1, t0, t1]
            }
        }
        var trunks = Buffer()
        var crowns = [Buffer(), Buffer()]
        var gz: Float = -150
        while gz <= 150 {
            var gx: Float = -150
            while gx <= 150 {
                let x = gx + (noise.value(gx * 0.37, gz * 0.11) - 0.5) * 4
                let z = gz + (noise.value(gx * 0.13 + 5, gz * 0.41) - 0.5) * 4
                gx += 4.5
                if z > -9.5 && z < 14 { continue }                             // road, wall, the bare cut below the road
                if x > -22 && x < 7 && z < 0 && z > -20 { continue }           // the hut's pad and bank
                if bump(x, z) > 0.05 || (x > 22 && x < 56 && z < -6) { continue } // the slide and its scar
                if noise.fbm(x / 25, z / 25, octaves: 3) < 0.42 { continue }
                let k = 0.75 + noise.value(x * 0.7, z * 0.7) * 0.75
                let v = Int(noise.value(x * 1.3, z * 0.9) * 2) % 2
                let g = SIMD3<Float>(x, baseHeight(x, z) - 0.1, z)
                let tint = 0.85 + 0.3 * noise.value(x * 2.1, z * 1.7)
                let turn = noise.value(x, z) * 6
                trunk(&trunks, g, 0.15 * k, 3.2 * k)
                cone(&crowns[v], g + SIMD3(0, 2.3 * k, 0), 1.6 * k, 3.4 * k, tint, turn)
                cone(&crowns[v], g + SIMD3(0, 4.2 * k, 0), 1.15 * k, 2.8 * k, tint, turn + 0.4)
            }
            gz += 4.5
        }
        let bark = SK.mat(SK.rgb(0x4A3829), roughness: 0.95)
        let needles = [SK.mat(SK.rgb(0x26402C), roughness: 0.9), SK.mat(SK.rgb(0x34502F), roughness: 0.9)]
        for (b, m) in [(trunks, bark), (crowns[0], needles[0]), (crowns[1], needles[1])] where !b.idx.isEmpty {
            let geo = SK.mesh(b.pts, b.idx, colors: b.cols)
            geo.materials = [m]
            let n = SCNNode(geometry: geo)
            n.castsShadow = false
            world.addChildNode(n)
        }
    }

    private func buildMist() {
        // cloud lying in the valley below the road
        for (y, alpha) in [(-70, 0.2), (-115, 0.32)] as [(CGFloat, CGFloat)] {
            let plane = SCNPlane(width: 1400, height: 800)
            let m = SK.mat(SK.rgb(0xD5DBE0), roughness: 1)
            m.lightingModel = .lambert
            m.transparency = alpha
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.eulerAngles.x = -.pi / 2
            n.position = SCNVector3(0, y, 420)
            n.castsShadow = false
            world.addChildNode(n)
        }
    }

    /// Corrugated iron: galvanized grey ribs, rusting in patches.
    private static func corrugated() -> SCNMaterial {
        let size = 128
        let n = SK.Noise(seed: 77)
        var px = [UInt8](repeating: 255, count: size * size * 4)
        var nm = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let phase = Float(x) / Float(size) * 2 * .pi * 8
                let rib = 0.5 + 0.5 * sin(phase)
                let rust = SK.smoothstep(0.42, 0.72, n.fbm(Float(x) / 38, Float(y) / 38, octaves: 4))
                let c = SK.mix(SIMD3<Float>(0.56, 0.58, 0.58), SIMD3<Float>(0.50, 0.29, 0.17), rust) * (0.8 + 0.2 * rib)
                let i = (y * size + x) * 4
                px[i] = UInt8(min(255, c.x * 255)); px[i + 1] = UInt8(min(255, c.y * 255)); px[i + 2] = UInt8(min(255, c.z * 255))
                let slope = cos(phase) * 0.55
                let l = sqrt(slope * slope + 1)
                nm[i] = UInt8((slope / l * 0.5 + 0.5) * 255); nm[i + 1] = 128; nm[i + 2] = UInt8((1 / l * 0.5 + 0.5) * 255)
            }
        }
        let m = SK.mat(.white, roughness: 0.55, metalness: 0.35, doubleSided: true)
        m.diffuse.contents = SK.image(from: px, size: size)
        m.normal.contents = SK.image(from: nm, size: size)
        for p in [m.diffuse, m.normal] {
            p.wrapS = .repeat; p.wrapT = .repeat
            p.mipFilter = .linear
            p.contentsTransform = SCNMatrix4MakeScale(4, 2, 1)
        }
        return m
    }

    private func buildHut(english: Bool) {
        let hut = SCNNode()
        hut.position = SCNVector3(hutX, 0, hutZ)
        world.addChildNode(hut)
        let lime = SK.noiseMat(SK.rgb(0xDAD6CB), SK.rgb(0xB9B3A4), scale: 6, roughness: 0.95, seed: 61)
        let band = SK.noiseMat(SK.rgb(0x8E3B2F), SK.rgb(0x6E2C24), scale: 8, roughness: 0.9, seed: 62)
        let green = SK.mat(SK.rgb(0x2F5A48), roughness: 0.7)
        let iron = SK.mat(SK.rgb(0x3A3B3C), roughness: 0.5, metalness: 0.7)
        let wood = SK.mat(SK.rgb(0x5B4632), roughness: 0.9)
        let roof = TutorialScene.corrugated()
        let front: CGFloat = 2.5

        // walls, a faded red band round the bottom
        hut.addChildNode(SK.box(7, 2.7, 5, lime, chamfer: 0.03, at: SCNVector3(0, 1.35, 0)))
        hut.addChildNode(SK.box(7.04, 0.85, 5.04, band, chamfer: 0.02, at: SCNVector3(0, 0.425, 0)))
        // gable ends
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: -2.5, y: 0)); tri.line(to: NSPoint(x: 2.5, y: 0)); tri.line(to: NSPoint(x: 0, y: 0.9)); tri.close()
        for side in [-1.0, 1.0] as [CGFloat] {
            let shape = SCNShape(path: tri, extrusionDepth: 0.2)
            shape.materials = [lime]
            let g = SCNNode(geometry: shape)
            g.eulerAngles.y = .pi / 2
            g.position = SCNVector3(side * 3.4, 2.7, 0)
            hut.addChildNode(g)
        }
        // the roof: two slopes of corrugated iron; one sheet on the front slope is gone
        let pitch: CGFloat = 0.345
        for side in [-1.0, 1.0] as [CGFloat] {
            let panel = SK.box(7.7, 0.05, 3.0, roof, chamfer: 0, at: SCNVector3(0, 3.1, side * 1.3))
            panel.eulerAngles.x = side * pitch
            hut.addChildNode(panel)
        }
        /// A point on the front slope: `along` from the panel's middle toward the eaves, `lift` off its surface.
        func onFront(_ x: CGFloat, _ along: CGFloat, _ lift: CGFloat) -> SCNVector3 {
            SCNVector3(x, 3.1 - sin(pitch) * along + cos(pitch) * lift, 1.3 + cos(pitch) * along + sin(pitch) * lift)
        }
        let hole = SK.box(1.1, 0.02, 1.5, SK.mat(SK.rgb(0x0D0C0B), roughness: 1), chamfer: 0)
        hole.position = onFront(1.3, -0.25, 0.035)
        hole.eulerAngles.x = pitch
        hut.addChildNode(hole)
        roofHole = hole
        // ... until someone climbs up with a blue tarp and weighs it down with stones
        let patch = SCNNode()
        patch.position = onFront(1.3, -0.25, 0.05)
        patch.eulerAngles.x = pitch
        patch.addChildNode(SK.box(1.9, 0.03, 2.1, SK.mat(SK.rgb(0x2D62A8), roughness: 0.55), chamfer: 0.01))
        let stone = SK.noiseMat(SK.rgb(0x7A766F), SK.rgb(0x55524D), scale: 3, seed: 63)
        for (i, p) in ([(-0.8, -0.9), (0.8, -0.9), (-0.8, 0.9), (0.8, 0.9), (0, 0)] as [(CGFloat, CGFloat)]).enumerated() {
            let r = SK.rock(0.16, stone, seed: UInt64(70 + i))
            r.position = SCNVector3(p.0, 0.0, p.1)
            patch.addChildNode(r)
        }
        patch.isHidden = true
        hut.addChildNode(patch)
        tarp = patch
        // the missing sheet, blown down against the west wall
        let fallen = SK.box(1.0, 0.04, 2.2, roof, chamfer: 0, at: SCNVector3(-3.82, 0.95, -0.6))
        fallen.eulerAngles = SCNVector3(0, 0, -1.15)
        hut.addChildNode(fallen)

        // stovepipe through the back slope, smoking when the stove is lit
        let pipe = SK.cylinder(0.08, 1.5, iron, at: SCNVector3(1.6, 3.4, -1.3))
        hut.addChildNode(pipe)
        hut.addChildNode(SK.cylinder(0.14, 0.08, iron, at: SCNVector3(1.6, 4.17, -1.3)))
        let smokeHolder = SCNNode()
        smokeHolder.position = SCNVector3(1.6, 4.3, -1.3)
        hut.addChildNode(smokeHolder)
        chimney = (SK.smoke(scale: 0.5, color: NSColor(white: 0.7, alpha: 0.2)), smokeHolder)

        // door and windows on the road side: dark inside, warm when the stove burns
        let glass = SK.mat(SK.rgb(0x15191B), roughness: 0.1, metalness: 0.2)
        let opening = SK.mat(SK.rgb(0x0B0907), roughness: 1)
        glowMats = [glass, opening]
        hut.addChildNode(SK.box(1.1, 2.15, 0.08, green, chamfer: 0.01, at: SCNVector3(-0.8, 1.07, front + 0.01)))
        hut.addChildNode(SK.box(0.92, 2.0, 0.04, opening, chamfer: 0, at: SCNVector3(-0.8, 1.0, front + 0.05)))
        // the door itself stands open against the wall
        let door = SK.box(0.9, 2.0, 0.05, green, chamfer: 0.01, at: SCNVector3(-1.7, 1.0, front + 0.12))
        door.eulerAngles.y = 0.19
        hut.addChildNode(door)
        for x in [-2.7, 1.6] as [CGFloat] {
            hut.addChildNode(SK.box(1.05, 0.9, 0.07, green, chamfer: 0.01, at: SCNVector3(x, 1.55, front + 0.01)))
            hut.addChildNode(SK.box(0.88, 0.74, 0.03, glass, chamfer: 0, at: SCNVector3(x, 1.55, front + 0.05)))
            hut.addChildNode(SK.box(0.04, 0.74, 0.04, green, chamfer: 0, at: SCNVector3(x, 1.55, front + 0.07)))
        }
        // 道班 painted beside the door, the way road crews marked their huts
        let text = SCNText(string: english ? "ROAD CREW" : "道班", extrusionDepth: 0.01)
        text.font = english ? NSFont.systemFont(ofSize: 0.42, weight: .heavy) : (NSFont(name: "PingFang SC", size: 1) ?? NSFont.systemFont(ofSize: 1))
        text.flatness = 0.02
        text.materials = [SK.mat(SK.rgb(0xA8322A), roughness: 0.8)]
        let label = SCNNode(geometry: text)
        let (lo, hi) = label.boundingBox
        label.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0)
        label.scale = SCNVector3(0.36, 0.36, 0.36)
        label.position = SCNVector3(0.42, 1.62, front + 0.02)
        hut.addChildNode(label)

        // a lean-to porch over the door on two wooden posts
        let porch = SK.box(7.7, 0.05, 1.8, roof, chamfer: 0, at: SCNVector3(0, 2.38, front + 0.85))
        porch.eulerAngles.x = 0.16
        hut.addChildNode(porch)
        for x in [-3.5, 3.5] as [CGFloat] {
            hut.addChildNode(SK.box(0.12, 2.26, 0.12, wood, chamfer: 0.01, at: SCNVector3(x, 1.13, front + 1.6)))
        }

        // firewood stacked against the east wall (as much as there is)
        for i in 0..<12 {
            let log = SK.cylinder(0.1, 0.95, wood, at: SCNVector3(3.65 + CGFloat(i % 2) * 0.2, 0.1 + CGFloat(i / 4) * 0.19, -1.9 + CGFloat((i / 2) % 2) * 1.0 + CGFloat(i % 2) * 0.05))
            log.eulerAngles.x = .pi / 2
            hut.addChildNode(log)
            logs.append(log)
        }
    }

    private func buildBus() {
        let bus = SCNNode()
        bus.position = SCNVector3(14, 0.03, 1.85)
        world.addChildNode(bus)
        let white = SK.mat(SK.rgb(0xEEF0F1), roughness: 0.3, metalness: 0.2)
        let teal = SK.mat(SK.rgb(0x1E7F8F), roughness: 0.4, metalness: 0.2)
        let glass = SK.mat(SK.rgb(0x141B20), roughness: 0.06, metalness: 0.4)
        let rubber = SK.mat(SK.rgb(0x1A1A1A), roughness: 0.9)
        let rim = SK.mat(SK.rgb(0x9DA3A8), roughness: 0.4, metalness: 0.8)
        let skirt = SK.mat(SK.rgb(0x3A4148), roughness: 0.5)
        bus.addChildNode(SK.box(12, 2.95, 2.5, white, chamfer: 0.22, at: SCNVector3(0, 1.98, 0)))
        bus.addChildNode(SK.box(11.9, 0.5, 2.52, skirt, chamfer: 0.05, at: SCNVector3(0, 0.78, 0)))
        for side in [-1.0, 1.0] as [CGFloat] {
            bus.addChildNode(SK.box(9.4, 1.0, 0.02, glass, chamfer: 0, at: SCNVector3(-0.75, 2.6, side * 1.256)))
            bus.addChildNode(SK.box(11.8, 0.24, 0.02, teal, chamfer: 0, at: SCNVector3(0, 1.45, side * 1.256)))
            bus.addChildNode(SK.box(11.8, 0.06, 0.02, teal, chamfer: 0, at: SCNVector3(0, 1.73, side * 1.256)))
        }
        // windscreen, rear window, destination sign, the passenger door on the right
        bus.addChildNode(SK.box(0.02, 1.55, 2.25, glass, chamfer: 0, at: SCNVector3(6.005, 2.4, 0)))
        bus.addChildNode(SK.box(0.02, 0.85, 2.0, glass, chamfer: 0, at: SCNVector3(-6.005, 2.65, 0)))
        let sign = SK.mat(.black, roughness: 0.4, emission: SK.rgb(0xFF8A1F))
        bus.addChildNode(SK.box(0.02, 0.22, 1.4, sign, chamfer: 0, at: SCNVector3(6.012, 3.27, 0)))
        bus.addChildNode(SK.box(0.9, 2.15, 0.02, glass, chamfer: 0, at: SCNVector3(4.95, 1.6, 1.262)))
        // an open luggage hatch on the near side
        let hatch = SK.box(1.8, 0.06, 0.9, skirt, chamfer: 0.01, at: SCNVector3(-1.2, 1.35, 1.65))
        hatch.eulerAngles.x = 0.35
        bus.addChildNode(hatch)
        bus.addChildNode(SK.box(1.7, 0.75, 0.02, SK.mat(SK.rgb(0x0E0F10), roughness: 1), chamfer: 0, at: SCNVector3(-1.2, 0.85, 1.263)))
        for x in [4.2, -2.6, -3.75] as [CGFloat] {
            for side in [-1.0, 1.0] as [CGFloat] {
                let w = SK.cylinder(0.5, 0.32, rubber, at: SCNVector3(x, 0.5, side * 1.1))
                w.eulerAngles.x = .pi / 2
                bus.addChildNode(w)
                let hub = SK.cylinder(0.27, 0.34, rim, at: SCNVector3(x, 0.5, side * 1.1))
                hub.eulerAngles.x = .pi / 2
                bus.addChildNode(hub)
            }
        }
        // hazard lights, blinking; red tail lights
        let amber = SK.mat(SK.rgb(0x3A2400), roughness: 0.3, emission: SK.rgb(0xFFA21A))
        amber.emission.intensity = 2.4
        let blink = SCNAction.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.06), .wait(duration: 0.42),
                                                       .fadeOpacity(to: 0.08, duration: 0.06), .wait(duration: 0.42)]))
        for (x, z) in [(6.02, 1.05), (6.02, -1.05), (-6.02, 1.05), (-6.02, -1.05)] as [(CGFloat, CGFloat)] {
            let l = SK.sphere(0.1, amber, at: SCNVector3(x, 0.98, z), segments: 12)
            l.runAction(blink)
            bus.addChildNode(l)
        }
        let red = SK.mat(SK.rgb(0x300000), roughness: 0.3, emission: SK.rgb(0xD01A10))
        for z in [0.95, -0.95] as [CGFloat] {
            bus.addChildNode(SK.box(0.03, 0.3, 0.18, red, chamfer: 0, at: SCNVector3(-6.01, 1.3, z)))
        }
        // a suitcase left on the road by the hatch
        bus.addChildNode(SK.box(0.45, 0.65, 0.25, SK.mat(SK.rgb(0x7A2E3A), roughness: 0.5), chamfer: 0.04, at: SCNVector3(-0.4, 0.33, 2.0)))
    }

    private func buildSlide() {
        let mud = SK.terrainMaterial(flat: SK.rgb(0x7A5C3E), steep: SK.rgb(0x5A4430), from: 0.45, to: 0.75,
                                     grain: 0.3, noiseScale: 0.25, roughness: 0.5)
        SK.addGrain(mud, scale: 14, strength: 3, intensity: 0.45)
        let color: (Float, Float, Float) -> SIMD3<Float> = { x, _, z in
            let wet = self.noise.fbm(x / 6 + 40, z / 6, octaves: 3)
            let k = 0.78 + 0.35 * wet
            return SIMD3(k, k * 0.97, k * 0.94)
        }
        let full = heightField(x0: 18, x1: 60, z0: -136, z1: 46, cell: 0.5,
                               height: { self.slideHeight($0, $1) }, color: color, material: mud)
        world.addChildNode(full)
        slide = full
        let cleared = heightField(x0: 18, x1: 60, z0: -136, z1: 46, cell: 0.5,
                                  height: { self.slideHeight($0, $1, cleared: true) }, color: color, material: mud)
        cleared.isHidden = true
        world.addChildNode(cleared)
        slideCleared = cleared

        // boulders and broken pines in the mud
        let rock = SK.noiseMat(SK.rgb(0x77736C), SK.rgb(0x4E4B46), scale: 3, seed: 81)
        let debris = SCNNode()
        for i in 0..<18 {
            let x = 30 + CGFloat(noise.value(Float(i) * 3.1, 2) * 17)
            let z = -6 + CGFloat(noise.value(Float(i) * 1.7, 9) * 18)
            let r = Float(0.35 + noise.value(Float(i), 5) * 1.0)
            let b = SK.rock(r, rock, seed: UInt64(200 + i))
            b.position = SCNVector3(x, slideGround(x, z) - CGFloat(r) * 0.25, z)
            debris.addChildNode(b)
        }
        let bark = SK.mat(SK.rgb(0x4A3829), roughness: 0.95)
        let needles = SK.mat(SK.rgb(0x2D4530), roughness: 0.9)
        for i in 0..<6 {
            let x = 31 + CGFloat(i) * 2.8, z = -4 + CGFloat(noise.value(Float(i) * 2.3, 4) * 9)
            let tree = SCNNode()
            let trunk = SK.cylinder(0.16, 7, bark)
            trunk.eulerAngles.z = .pi / 2
            tree.addChildNode(trunk)
            let crown = SK.node(SCNCone(topRadius: 0, bottomRadius: 1.3, height: 3), needles, at: SCNVector3(4.2, 0.3, 0))
            crown.eulerAngles.z = -.pi / 2
            tree.addChildNode(crown)
            tree.position = SCNVector3(x, slideGround(x, z) + 0.25, z)
            tree.eulerAngles = SCNVector3(0.15, CGFloat(i) * 1.1 + 0.4, 0.12)
            debris.addChildNode(tree)
        }
        world.addChildNode(debris)
    }

    private func buildSignal() {
        // a red warning triangle on the road behind the bus, facing the way traffic would come
        let red = SK.mat(SK.rgb(0x8A1008), roughness: 0.3, emission: SK.rgb(0xFF2A1A))
        red.emission.intensity = 0.5
        let t = SCNNode()
        let side: CGFloat = 0.62
        for k in 0..<3 {
            let bar = SK.box(side, 0.06, 0.03, red, chamfer: 0)
            let a = CGFloat(k) * 2 * .pi / 3
            let holder = SCNNode()
            holder.position = SCNVector3(0, side * 0.29, 0)
            holder.eulerAngles.z = a
            bar.position = SCNVector3(0, -side * 0.29, 0)
            holder.addChildNode(bar)
            t.addChildNode(holder)
        }
        t.eulerAngles.y = -.pi / 2
        let stand = SCNNode()
        stand.position = SCNVector3(4, 0.06, 1.8)
        stand.eulerAngles.z = 0.15
        stand.addChildNode(t)
        stand.isHidden = true
        world.addChildNode(stand)
        triangle = stand

        // SOS laid out in pale stones across the left-hand lane (letters run along +x, readable from above)
        let pale = SK.noiseMat(SK.rgb(0xCFCCC4), SK.rgb(0x9D9890), scale: 3, seed: 91)
        let shapes = (0..<4).map { SK.rock(0.2, pale, seed: UInt64(300 + $0), flatten: 0.45) }
        func stroke(_ x0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ z1: CGFloat) {
            let len = hypot(x1 - x0, z1 - z0)
            let n = max(2, Int(len / 0.45) + 1)
            for k in 0..<n {
                let f = CGFloat(k) / CGFloat(n - 1)
                let st = shapes[(sosStones.count * 7) % shapes.count].clone()
                st.position = SCNVector3(x0 + (x1 - x0) * f, 0.03, z0 + (z1 - z0) * f)
                st.eulerAngles.y = CGFloat(sosStones.count) * 1.3
                st.isHidden = true
                world.addChildNode(st)
                sosStones.append(st)
            }
        }
        func letterS(_ x: CGFloat) {
            stroke(x, -3.1, x + 2.2, -3.1); stroke(x, -3.1, x, -1.75); stroke(x, -1.75, x + 2.2, -1.75)
            stroke(x + 2.2, -1.75, x + 2.2, -0.4); stroke(x + 2.2, -0.4, x, -0.4)
        }
        letterS(-3.5)
        stroke(-0.3, -3.1, 1.9, -3.1); stroke(1.9, -3.1, 1.9, -0.4); stroke(1.9, -0.4, -0.3, -0.4); stroke(-0.3, -0.4, -0.3, -3.1)
        letterS(2.9)

        // a torch left switched on at the edge of the road, after dark
        let lamp = SCNNode()
        lamp.position = SCNVector3(6.6, 0.12, -0.6)
        let body = SK.cylinder(0.05, 0.28, SK.mat(SK.rgb(0x1B1B1D), roughness: 0.4))
        body.eulerAngles.z = .pi / 2
        lamp.addChildNode(body)
        lamp.addChildNode(SK.cylinder(0.06, 0.02, SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xF2F6FF)), at: SCNVector3(0.15, 0, 0)))
        let l = SCNLight()
        l.type = .omni
        l.color = SK.rgb(0xE6EEFF)
        l.intensity = 110
        l.attenuationStartDistance = 0
        l.attenuationEndDistance = 5
        l.attenuationFalloffExponent = 2
        let ln = SCNNode()
        ln.light = l
        ln.position = SCNVector3(0.5, 0.3, 0)
        lamp.addChildNode(ln)
        lamp.isHidden = true
        world.addChildNode(lamp)
        torch = lamp
    }

    private func buildProps() {
        let card = SK.noiseMat(SK.rgb(0xB08A5A), SK.rgb(0x8E6B42), scale: 6, seed: 101)
        let tape = SK.mat(SK.rgb(0xC9B48A), roughness: 0.6)
        let porchFront = hutZ + 2.5
        // the shop's two cartons under the porch: closed, then opened and shared out
        let closed = SCNNode()
        closed.position = SCNVector3(hutX + 2.9, 0, porchFront + 0.55)
        closed.addChildNode(SK.box(0.62, 0.42, 0.45, card, chamfer: 0.01, at: SCNVector3(0, 0.21, 0)))
        closed.addChildNode(SK.box(0.62, 0.02, 0.08, tape, chamfer: 0, at: SCNVector3(0, 0.43, 0)))
        let top = SK.box(0.55, 0.38, 0.4, card, chamfer: 0.01, at: SCNVector3(0.05, 0.62, 0))
        top.eulerAngles.y = 0.2
        closed.addChildNode(top)
        world.addChildNode(closed)
        cartonsClosed = closed
        let open = SCNNode()
        open.position = closed.position
        for (i, x) in [-0.2, 0.55].enumerated() {
            let box = SCNNode()
            box.position = SCNVector3(CGFloat(x), 0, CGFloat(i) * 0.2)
            box.addChildNode(SK.box(0.6, 0.4, 0.44, card, chamfer: 0.01, at: SCNVector3(0, 0.2, 0)))
            for side in [-1.0, 1.0] as [CGFloat] {
                let flap = SK.box(0.6, 0.02, 0.22, card, chamfer: 0, at: SCNVector3(0, 0.42, side * 0.3))
                flap.eulerAngles.x = side * 0.9
                box.addChildNode(flap)
            }
            open.addChildNode(box)
        }
        let cupColors = [0xC8322B, 0xE2B13C, 0xC8322B, 0xF0EDE6].map { SK.mat(SK.rgb(UInt32($0)), roughness: 0.5) }
        for i in 0..<5 {
            open.addChildNode(SK.cylinder(0.06, 0.1, cupColors[i % cupColors.count], at: SCNVector3(-0.8 - CGFloat(i % 3) * 0.16, 0.05, 0.1 + CGFloat(i / 3) * 0.16)))
        }
        open.isHidden = true
        world.addChildNode(open)
        cartonsOpen = open

        // the parcel the drone dropped
        let p = SCNNode()
        p.position = SCNVector3(hutX + 3.2, 0, porchFront + 1.3)
        p.addChildNode(SK.box(0.5, 0.32, 0.4, SK.mat(SK.rgb(0xE8701C), roughness: 0.55), chamfer: 0.02, at: SCNVector3(0, 0.16, 0)))
        p.addChildNode(SK.box(0.52, 0.33, 0.06, SK.mat(SK.rgb(0xF2F2EE), roughness: 0.5), chamfer: 0, at: SCNVector3(0, 0.16, 0)))
        p.eulerAngles.y = 0.5
        p.isHidden = true
        world.addChildNode(p)
        parcel = p

        // buckets and a basin under the eaves catching the rain
        let blue = SK.mat(SK.rgb(0x2E6FB0), roughness: 0.4)
        world.addChildNode(SK.cylinder(0.18, 0.34, blue, at: SCNVector3(hutX - 3.3, 0.17, porchFront + 1.95)))
        world.addChildNode(SK.cylinder(0.18, 0.34, blue, at: SCNVector3(hutX + 1.4, 0.17, porchFront + 1.95)))
        world.addChildNode(SK.cylinder(0.32, 0.12, SK.mat(SK.rgb(0xB23A33), roughness: 0.4), at: SCNVector3(hutX - 1.2, 0.06, porchFront + 1.9)))

        // a kilometre post and a rockfall warning sign
        world.addChildNode(SK.box(0.22, 0.7, 0.12, SK.mat(SK.rgb(0xE6E6E1), roughness: 0.7), chamfer: 0.02, at: SCNVector3(-18, 0.35, -4.5)))
        world.addChildNode(SK.box(0.23, 0.16, 0.13, SK.mat(SK.rgb(0xB0352B), roughness: 0.6), chamfer: 0.01, at: SCNVector3(-18, 0.66, -4.5)))
        let sign = SCNNode()
        sign.position = SCNVector3(-24, 0, 4.75)
        sign.addChildNode(SK.cylinder(0.04, 2.3, SK.mat(SK.rgb(0x9DA2A6), roughness: 0.4, metalness: 0.7), at: SCNVector3(0, 1.15, 0)))
        let warn = NSBezierPath()
        warn.move(to: NSPoint(x: -0.45, y: 0)); warn.line(to: NSPoint(x: 0.45, y: 0)); warn.line(to: NSPoint(x: 0, y: 0.78)); warn.close()
        let plate = SCNShape(path: warn, extrusionDepth: 0.02)
        plate.materials = [SK.mat(SK.rgb(0xEBC23A), roughness: 0.5)]
        let pn = SCNNode(geometry: plate)
        pn.position = SCNVector3(0, 1.75, 0.05)
        pn.eulerAngles.y = -0.9
        sign.addChildNode(pn)
        world.addChildNode(sign)

        // rocks that came down onto the gutter before
        let stone = SK.noiseMat(SK.rgb(0x7D7871), SK.rgb(0x57534D), scale: 3, seed: 111)
        for i in 0..<9 {
            let x = -50 + CGFloat(noise.value(Float(i) * 4.3, 1) * 70)
            if x > -16 && x < 4 { continue }
            let r = SK.rock(Float(0.12 + noise.value(Float(i), 3) * 0.25), stone, seed: UInt64(400 + i))
            r.position = SCNVector3(x, 0.02, -4.4 + CGFloat(noise.value(Float(i), 8)) * 0.5)
            world.addChildNode(r)
        }
    }

    /// The road crew clearing the last of the slide from the far side.
    private func buildRescue() -> SCNNode {
        let r = SCNNode()
        let yellow = SK.mat(SK.rgb(0xF0B308), roughness: 0.45, metalness: 0.2)
        let dark = SK.mat(SK.rgb(0x262728), roughness: 0.8)
        let steel = SK.mat(SK.rgb(0x5A5D60), roughness: 0.5, metalness: 0.7)
        let glass = SK.mat(SK.rgb(0x1E2A30), roughness: 0.08, metalness: 0.3)
        // excavator, facing west into the mud
        let ex = SCNNode()
        ex.position = SCNVector3(37.5, 0.03, -1.8)
        ex.eulerAngles.y = .pi
        for side in [-1.0, 1.0] as [CGFloat] {
            ex.addChildNode(SK.box(3.7, 0.8, 0.6, dark, chamfer: 0.25, at: SCNVector3(0, 0.4, side * 1.1)))
        }
        let upper = SCNNode()
        upper.position.y = 0.85
        upper.addChildNode(SK.box(3.0, 1.15, 2.4, yellow, chamfer: 0.08, at: SCNVector3(-0.3, 0.6, 0)))
        upper.addChildNode(SK.box(0.9, 1.0, 2.3, yellow, chamfer: 0.15, at: SCNVector3(-1.55, 0.55, 0)))
        upper.addChildNode(SK.box(1.05, 1.45, 1.0, glass, chamfer: 0.04, at: SCNVector3(0.75, 1.85, -0.65)))
        upper.addChildNode(SK.box(1.1, 0.08, 1.05, yellow, chamfer: 0.02, at: SCNVector3(0.75, 2.6, -0.65)))
        // boom, arm and bucket, bobbing as it digs
        let boom = SCNNode()
        boom.position = SCNVector3(1.0, 1.1, 0.45)
        boom.eulerAngles.z = 0.55
        boom.addChildNode(SK.box(3.4, 0.42, 0.36, yellow, chamfer: 0.05, at: SCNVector3(1.7, 0, 0)))
        let arm = SCNNode()
        arm.position = SCNVector3(3.35, 0, 0)
        arm.eulerAngles.z = -1.45
        arm.addChildNode(SK.box(2.6, 0.32, 0.3, yellow, chamfer: 0.04, at: SCNVector3(1.3, 0, 0)))
        let bucket = SK.box(0.75, 0.7, 1.0, steel, chamfer: 0.06, at: SCNVector3(2.65, -0.1, 0))
        bucket.eulerAngles.z = -0.5
        arm.addChildNode(bucket)
        boom.addChildNode(arm)
        boom.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.18, duration: 2.2), .rotateBy(x: 0, y: 0, z: -0.18, duration: 2.2)])))
        upper.addChildNode(boom)
        ex.addChildNode(upper)
        let lamp = SCNLight()
        lamp.type = .omni
        lamp.color = SK.rgb(0xFFF1D6)
        lamp.intensity = 260
        lamp.attenuationStartDistance = 0
        lamp.attenuationEndDistance = 14
        lamp.attenuationFalloffExponent = 2
        let ln = SCNNode()
        ln.light = lamp
        ln.position = SCNVector3(0.8, 3.0, 0)
        ex.addChildNode(ln)
        workLight = ln
        r.addChildNode(ex)

        // road crew in orange
        let orange = SK.rgb(0xEF7A1A)
        for (x, z, pose, face) in [(34.5, 2.6, SK.Pose.waving, -CGFloat.pi / 2), (40.5, -3.5, .standing, -CGFloat.pi / 2 + 0.4), (42.5, 0.4, .standing, -2.2)] {
            let p = SK.person(color: orange, pose: pose)
            p.position = SCNVector3(CGFloat(x), max(0.03, CGFloat(slideHeight(Float(x), Float(z), cleared: true))), CGFloat(z))
            p.eulerAngles.y = face
            // a white hard hat
            p.addChildNode(SK.sphere(0.14, SK.mat(SK.rgb(0xF2F2EE), roughness: 0.4), at: SCNVector3(0, 1.74, 0)))
            r.addChildNode(p)
        }

        // the road maintenance station's van, lights flashing
        let van = SCNNode()
        van.position = SCNVector3(47, 0.03, -1.9)
        van.eulerAngles.y = .pi
        let white = SK.mat(SK.rgb(0xF1F2F2), roughness: 0.35, metalness: 0.2)
        van.addChildNode(SK.box(4.8, 1.9, 1.95, white, chamfer: 0.18, at: SCNVector3(0, 1.3, 0)))
        van.addChildNode(SK.box(4.82, 0.18, 1.97, SK.mat(SK.rgb(0xC0392B), roughness: 0.4), chamfer: 0, at: SCNVector3(0, 1.0, 0)))
        van.addChildNode(SK.box(0.02, 0.7, 1.7, glass, chamfer: 0, at: SCNVector3(2.41, 1.75, 0)))
        for x in [1.6, -1.5] as [CGFloat] {
            for side in [-1.0, 1.0] as [CGFloat] {
                let w = SK.cylinder(0.36, 0.25, dark, at: SCNVector3(x, 0.36, side * 0.88))
                w.eulerAngles.x = .pi / 2
                van.addChildNode(w)
            }
        }
        for (i, hex) in [0xFF2A1A, 0x2A5BFF].enumerated() {
            let m = SK.mat(.black, roughness: 0.3, emission: SK.rgb(UInt32(hex)))
            m.emission.intensity = 2.2
            let light = SK.box(0.3, 0.14, 0.5, m, chamfer: 0.03, at: SCNVector3(0.4, 2.33, CGFloat(i) * 0.6 - 0.3))
            let flash = SCNAction.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.3),
                                                           .fadeOpacity(to: 0.1, duration: 0.05), .wait(duration: 0.3)]))
            light.runAction(.sequence([.wait(duration: Double(i) * 0.35), flash]))
            van.addChildNode(light)
        }
        r.addChildNode(van)
        return r
    }

    // MARK: Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        // the stove: glowing windows and door, smoke from the pipe
        let lit = s.fireLit
        for m in glowMats {
            m.emission.contents = lit ? SK.rgb(0xFF9A48) : NSColor.black
            m.emission.intensity = lit ? CGFloat(0.3 + 1.2 * darkness) : 0
        }
        if let c = chimney {
            let (smoke, holder) = c
            smoke.particleColor = NSColor(white: CGFloat(0.78 - 0.55 * darkness), alpha: CGFloat(0.24 - 0.1 * darkness))
            let attached = holder.particleSystems?.contains(smoke) ?? false
            if lit && !attached { holder.addParticleSystem(smoke) }
            if !lit && attached { holder.removeParticleSystem(smoke) }
        }

        // the roof leaks until it's patched (the shelter starts at 55)
        let patched = s.shelter >= 70
        roofHole?.isHidden = patched
        tarp?.isHidden = !patched

        // firewood against the wall, as much as is left
        let shownLogs = min(logs.count, Int((s.res("fuel") * 2.5).rounded()))
        for (i, l) in logs.enumerated() { l.isHidden = i >= shownLogs }

        // the distress signal: a warning triangle, then SOS in stones, then a torch after dark
        let signal = s.v("signal", 0)
        triangle?.isHidden = signal < 10
        let stones = Int((Double(sosStones.count) * max(0, min(1, (signal - 25) / 35))).rounded())
        for (i, st) in sosStones.enumerated() { st.isHidden = i >= stones }
        torch?.isHidden = !(signal >= 55 && darkness > 0.45)

        // the shop's cartons, and the drone's parcel
        let opened = s.has("goods_bought") || s.has("goods_taken")
        cartonsClosed?.isHidden = opened
        cartonsOpen?.isHidden = !opened
        parcel?.isHidden = !s.has("drone")

        // daybreak on the last morning: the road crew cuts through from the far side
        let rescued = s.has("rescued") || s.happened("r4_rescue") || s.event == "r4_rescue"
        if rescued && rescue == nil {
            let r = buildRescue()
            world.addChildNode(r)
            rescue = r
        }
        rescue?.isHidden = !rescued
        slide?.isHidden = rescued
        slideCleared?.isHidden = !rescued
        workLight?.isHidden = darkness < 0.35

        showPeople(s, spots: spots(for: s, rescued: rescued))
        showBodies(s.dead, spots: Spot.line(from: SCNVector3(hutX - 4.3, 0, hutZ + 1.6), to: SCNVector3(hutX - 4.3, 0, hutZ - 2.0), count: 4, facing: 0))
    }

    private func spots(for s: SceneState, rescued: Bool) -> [Spot] {
        if rescued {
            // out on the road, waving to the road crew
            let road: [(CGFloat, CGFloat, SK.Pose?)] = [(2.0, 1.2, .waving), (3.4, -0.4, nil), (4.8, 2.4, .waving), (1.0, -1.6, nil), (6.2, 0.6, nil), (2.6, 3.0, nil)]
            return road.map { Spot($0.0, 0.03, $0.1, facing: .pi / 2, pose: $0.2) }
        }
        let front = hutZ + 2.5 + 0.6
        if s.isNight || s.precip > 0.4 || (s.fireLit && s.hour >= 17) {
            // under the porch along the front wall, out of the rain
            return (0..<8).map { i in Spot(hutX - 3.0 + CGFloat(i) * 0.9, 0, front, facing: 0.15 - CGFloat(i) * 0.04) }
        }
        // a dry spell: about the hut, the road and the bus
        let day: [(CGFloat, CGFloat, CGFloat)] = [(-4.2, -5.6, 0.3), (-1.4, -3.2, 1.2), (2.2, -1.2, 1.9), (7.0, 3.6, 1.6),
                                                  (10.6, 3.9, 0.2), (-8.2, -6.1, 0.0), (0.4, 1.6, 2.6)]
        return day.map { Spot($0.0, $0.1 > -4.25 ? 0.03 : 0, $0.1, facing: $0.2, pose: $0.1 > -4.25 ? .standing : nil) }
    }
}
