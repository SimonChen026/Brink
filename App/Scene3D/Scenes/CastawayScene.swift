import SceneKit
import AppKit

/// 孤岛 · 荒岛余生 — a low coral cay in the South China Sea, early August, noon sun almost overhead.
///
/// Layout (metres, sea level y = 0). The island is a leaf-shaped sand cay about 136 × 54 m with its
/// long axis along x. The camera looks at it from the outer reef on the +z (leeward) side, where the
/// white beach, the shallow turquoise reef flat and the wreck of the yacht 海燕号 lie. The camp —
/// lean-to, fire, water stores, rain catcher — sits in the lee of the rocky headland at the north
/// end (x ≈ +50); the coconut grove runs along the west shore, the interior is pisonia scrub, and
/// the windward (−z) shore is wave-washed reef rock where the boobies nest.
///
/// State shown: `vars` palms (how many trees are left), signal (coral-stone SOS, the flag on the
/// headland), raft, discord/split (a second camp at the south end), birds, friction, storage and
/// `res.water` (water containers), flags fire_on / wreck_gone / inland_well / lookout / burial /
/// raft_built / raft_sailed / banca_sailed, projects catcher · cistern · beacon · banca, the dead,
/// the dog 锚仔, and a night watchman by the fire.
final class CastawayScene: ScenarioScene {
    private let noise = SK.Noise(seed: 1965)

    // Island shape: a super-ellipse (rounded rectangle) 2A × 2B, exponent P.
    private let A: Float = 68
    private let B: Float = 27
    private let P: Float = 3

    // MARK: State-dependent nodes

    private var sea: SCNNode?
    private var palms: [SCNNode] = []
    private var hutRoof: [SCNNode] = []
    private var hutSides: [SCNNode] = []
    private var fence: [SCNNode] = []
    private var stores: [SCNNode] = []
    private var sosLetters: [[SCNNode]] = []
    private var flagCloths: [SCNNode] = []
    private var birds: [SCNNode] = []
    private var graves: [SCNNode] = []
    private var catcher: SCNNode?
    private var catcherLoose: SCNNode?
    private var cistern: SCNNode?
    private var cisternLog: SCNNode?
    private var beacon: SCNNode?
    private var beaconFlame: SCNNode?
    private var banca: SCNNode?
    private var bancaWreck: SCNNode?
    private var raftLogs: SCNNode?
    private var raftLash: SCNNode?
    private var raftMast: SCNNode?
    private var raft: SCNNode?
    private var raftAtSea: SCNNode?
    private var bancaAtSea: SCNNode?
    private var wreck: SCNNode?
    private var wreckSunk: SCNNode?
    private var well: SCNNode?
    private var lookout: SCNNode?
    private var southCamp: SCNNode?
    private var southFire: SK.FlickerLight?
    private var plane: SCNNode?
    private var rescueBoat: SCNNode?
    private var poacherBoat: SCNNode?
    private var rulePlank: SCNNode?
    private var tallyMarks: [SCNNode] = []
    private var distillery: SCNNode?
    private var birdsPivot: SCNNode?

    required init() {
        super.init()
        skyStyle = .tropical
        sunPeak = 82                 // ~15°N in early August: the sun is nearly overhead at noon
        sunAzimuth = 68              // morning sun off the sea, so the beach and reef are lit from the east
        exposure = -0.50
        sunScale = 0.95
        iblScale = 1.05
        precipKind = .rain
        hazeColor = SK.rgb(0xD9E2DE)
        stormColor = SK.rgb(0x8C979D)
        clearVisibility = 2600
        weatherArea = 130
        weatherCenter = SCNVector3(10, 26, 10)
        // close enough that the people at camp read in the small in-game view; zoom out for the whole island
        cameraTarget = SCNVector3(32, 2.5, 15)
        cameraDistance = 46
        cameraYaw = -14
        cameraPitch = 13
        cameraFOV = 46
        minPitch = 2
    }

    // MARK: - Island field

    /// Super-ellipse field: 1 exactly on the nominal shoreline, < 1 inside.
    private func field(_ x: Float, _ z: Float) -> Float {
        let ax = abs(x) / A, bz = abs(z) / B
        return powf(powf(ax, P) + powf(bz, P), 1 / P)
    }

    /// Approximate signed distance to the shoreline in metres (negative on land).
    private func shoreDist(_ x: Float, _ z: Float) -> Float {
        let e: Float = 0.6
        let gx = (field(x + e, z) - field(x - e, z)) / (2 * e)
        let gz = (field(x, z + e) - field(x, z - e)) / (2 * e)
        let g = sqrtf(gx * gx + gz * gz)
        return (field(x, z) - 1) / max(0.002, g)
    }

    /// The rocky headland at the north end (1 on its crest).
    private func hillMask(_ x: Float, _ z: Float) -> Float {
        let hx = (x - 52) / 18, hz = (z + 2) / 15.5
        let hd = sqrtf(hx * hx + hz * hz)
        return SK.smoothstep(1.05, 0.10, hd) * SK.smoothstep(8, -1, shoreDist(x, z))
    }

    /// Terrain height. `d` is the distance seaward of the vegetation line, so the beach, the reef
    /// flat and the drop-off keep their real widths all round the island; the windward side is
    /// compressed (narrow beach, wave-washed rock, a narrower reef).
    private func height(_ x: Float, _ z: Float) -> Float {
        let d0 = shoreDist(x, z)
        let k = 1 + 0.62 * SK.smoothstep(8, -8, z)          // windward (−z) profile is squeezed
        let d = d0 > 0 ? d0 * k : d0
        var y: Float = 2.45                                  // interior plateau
        y += 0.55 * SK.smoothstep(-9, -2.5, d)               // dune ridge at the vegetation line
        y -= 3.05 * SK.smoothstep(-2.5, 11, d)               // beach face, waterline at d = 11
        y -= 1.0 * SK.smoothstep(11, 21, d)                  // wet sand into the shallows
        y -= 1.6 * SK.smoothstep(21, 78, d)                  // reef flat, ~1 m deep
        y -= 11.5 * SK.smoothstep(78, 98, d)                 // the drop-off at the reef edge
        y -= 8.5 * SK.smoothstep(98, 260, d)                 // deep sea floor
        // dunes, scrub mounds and the low spine of the cay
        let inland = SK.smoothstep(3, -7, d)
        y += (noise.fbm(x / 24, z / 24, octaves: 4) - 0.5) * 1.7 * inland
        y += 0.9 * expf(-powf(z / 11, 2)) * inland
        // coral heads and sand channels on the reef flat
        y += (noise.fbm(x / 11 + 5, z / 11, octaves: 4) - 0.5) * 0.8
            * SK.smoothstep(14, 30, d) * SK.smoothstep(96, 70, d)
        // the headland
        let hm = hillMask(x, z)
        y += 12.0 * hm
        y += (noise.ridged(x / 5 + 3, z / 5, octaves: 4) - 0.40) * 5.4 * SK.smoothstep(0.02, 0.45, hm)
        return y
    }

    /// Ground height for placing things (CGFloat flavour).
    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(height(Float(x), Float(z))) }

    /// Ground for someone standing in the shallows: never deeper than knee height.
    private func wetGround(_ x: CGFloat, _ z: CGFloat) -> CGFloat { max(ground(x, z), -0.42) }

    /// Graded grid coordinate: ~1.2 m cells over the island, stretching to ±2250 m at the horizon.
    private func gridCoord(_ i: Int, _ n: Int) -> Float {
        let s = Float(i) / Float(n - 1) * 2 - 1
        let a = abs(s)
        return (s < 0 ? -1 : 1) * 150 * a * (1 + 14 * powf(a, 6))
    }

    /// Point on the shoreline at direction `angle` (radians, 0 = +x), pushed `offset` metres
    /// seaward (positive) or inland (negative).
    private func shore(_ angle: Float, _ offset: Float) -> (Float, Float) {
        let c = cosf(angle), s = sinf(angle)
        let r = powf(powf(abs(c) / A, P) + powf(abs(s) / B, P), -1 / P)
        let x = r * c, z = r * s
        let e: Float = 0.5
        let gx = (field(x + e, z) - field(x - e, z)) / (2 * e)
        let gz = (field(x, z + e) - field(x, z - e)) / (2 * e)
        let g = max(0.002, sqrtf(gx * gx + gz * gz))
        return (x + gx / g * offset, z + gz / g * offset)
    }

    // MARK: - Small helpers

    private struct Rng {
        var s: UInt64
        mutating func next() -> Float {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Float(s >> 40) / Float(1 << 24)
        }
        mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    }

    private func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z)
        return l < 1e-6 ? SIMD3(0, 1, 0) : v / l
    }

    /// Tapered tube through a list of ring centres (palm trunks, spars, masts).
    private func tube(rings: [SIMD3<Float>], radii: [Float], segments: Int, uvScale: Float = 1) -> SCNGeometry {
        var pts: [SIMD3<Float>] = [], uvs: [CGPoint] = [], idx: [UInt32] = []
        let n = rings.count
        for i in 0..<n {
            let dir = unit(i < n - 1 ? rings[i + 1] - rings[i] : rings[i] - rings[i - 1])
            var side = SK.cross(dir, SIMD3<Float>(0, 1, 0))
            if abs(side.x) + abs(side.z) < 1e-4 { side = SIMD3(1, 0, 0) }
            let sx = unit(side), sy = unit(SK.cross(sx, dir))
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                pts.append(rings[i] + sx * (cosf(a) * radii[i]) + sy * (sinf(a) * radii[i]))
                uvs.append(CGPoint(x: CGFloat(s) / CGFloat(segments) * 2, y: CGFloat(i) * CGFloat(uvScale)))
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(n - 1) {
            for s in 0..<UInt32(segments) {
                let a = i * row + s, b = a + 1, c = a + row, d = c + 1
                idx += [a, b, c, b, d, c]
            }
        }
        return SK.mesh(pts, idx, uvs: uvs)
    }

    /// A sea-worn log / driftwood stick.
    private func driftwood(_ length: CGFloat, _ r: CGFloat, seed: UInt64, mat: SCNMaterial) -> SCNNode {
        var rr = Rng(s: seed)
        var rings: [SIMD3<Float>] = [], radii: [Float] = []
        let n = 5
        for i in 0...n {
            let t = Float(i) / Float(n)
            rings.append(SIMD3(Float(length) * (t - 0.5), rr.range(-0.05, 0.05), rr.range(-0.06, 0.06)))
            radii.append(Float(r) * rr.range(0.75, 1.15) * (1 - 0.25 * abs(t - 0.5)))
        }
        let g = tube(rings: rings, radii: radii, segments: 6)
        let node = SK.node(g, mat)
        let holder = SCNNode()
        holder.addChildNode(node)
        holder.eulerAngles.y = CGFloat(seed % 628) / 100
        return holder
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        buildTerrain()
        buildSea()
        buildPalms()
        buildScrub()
        buildWreck()
        buildCamp()
        buildProjects()
        buildRaft()
        buildBanca()
        buildSignal()
        buildFlotsam()
        buildHeadland()
        buildBoats()
        // the shelter fire: a beach fire pit in front of the lean-to
        addFire(at: SCNVector3(34, ground(34, 17), 17), scale: 1.05)
        buildSouthCamp()
    }

    // MARK: Terrain

    private func buildTerrain() {
        let n = 201
        let grid = { (i: Int) in self.gridCoord(i, n) }
        var pts: [SIMD3<Float>] = [], uvs: [CGPoint] = [], cols: [SIMD3<Float>] = []
        pts.reserveCapacity(n * n)
        for j in 0..<n {
            let z = grid(j)
            for i in 0..<n {
                let x = grid(i)
                pts.append(SIMD3(x, height(x, z), z))
                uvs.append(CGPoint(x: CGFloat(x) / 4, y: CGFloat(z) / 4))
                cols.append(groundColor(x, z, pts[pts.count - 1].y))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity((n - 1) * (n - 1) * 6)
        for j in 0..<n - 1 {
            for i in 0..<n - 1 {
                let a = UInt32(j * n + i), b = a + 1, c = a + UInt32(n), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let m = SK.terrainMaterial(flat: SK.rgb(0xFFFFFF), steep: SK.rgb(0x6E655A),
                                   from: 0.30, to: 0.54, grain: 0.09, noiseScale: 0.06, roughness: 0.92)
        SK.addGrain(m, scale: 7, strength: 3.0, intensity: 0.42, seed: 12)
        let g = SK.mesh(pts, idx, colors: cols, uvs: uvs)
        g.materials = [m]
        let t = SCNNode(geometry: g)
        t.castsShadow = false
        world.addChildNode(t)
    }

    /// Per-vertex albedo: coral sand, the wet tide line, the reef flat and the deep bottom.
    private func groundColor(_ x: Float, _ z: Float, _ y: Float) -> SIMD3<Float> {
        let d = shoreDist(x, z)
        let n1 = noise.fbm(x / 8, z / 8, octaves: 4)
        let n2 = noise.fbm(x / 30 + 11, z / 30, octaves: 3)
        var c: SIMD3<Float>
        if y > 0.30 {
            // dry land: glaring white coral sand on the beach, sandy soil with leaf litter inland
            var sand = SIMD3<Float>(0.84, 0.80, 0.69)
            sand = SK.mix(sand, SIMD3(0.34, 0.36, 0.21), SK.smoothstep(-3, -13, d) * (0.45 + 0.55 * n2))
            let fine = noise.fbm(x / 2.4, z / 2.4, octaves: 3)
            c = sand * (0.92 + 0.13 * n1) * (0.94 + 0.12 * fine)
            // coral rubble and damp sand patches just above the waterline
            let near = SK.smoothstep(-11, -1, d)
            c = SK.mix(c, SIMD3(0.62, 0.60, 0.50), near * SK.smoothstep(0.55, 0.9, n2) * 0.75)
        } else if y > -0.65 {
            // wet sand and the wrack line at the top of the tide
            c = SK.mix(SIMD3(0.70, 0.65, 0.51), SIMD3<Float>(0.42, 0.44, 0.28), n1)
        } else if y > -3.2 {
            // reef flat: coral sand, rubble and algae patches — this is what makes the lagoon pale
            let rubble = SIMD3<Float>(0.66, 0.72, 0.58)
            let algae = SIMD3<Float>(0.16, 0.28, 0.22)
            let sand = SIMD3<Float>(0.80, 0.78, 0.62)
            c = SK.mix(rubble, algae, SK.smoothstep(0.38, 0.80, n2))
            c = SK.mix(c, sand, SK.smoothstep(0.45, 0.88, n1) * 0.75)
        } else {
            // the drop-off and the deep floor
            let t = SK.smoothstep(-3.2, -12, y)
            c = SK.mix(SIMD3(0.10, 0.20, 0.20), SIMD3(0.01, 0.03, 0.07), t)
        }
        let hm = hillMask(x, z)
        if hm > 0.03 {
            let rock = SK.mix(SIMD3(0.24, 0.21, 0.17), SIMD3(0.50, 0.47, 0.40), n1 * n1)
            c = SK.mix(c, rock, SK.smoothstep(0.03, 0.4, hm))
        }
        return c
    }

    // MARK: Sea

    private func buildSea() {
        // The sea is our own flat sheet: every vertex is coloured by how deep the bottom is
        // under it, so the lagoon reads pale green over coral sand and the open sea beyond the
        // drop-off goes dark blue — a single transparent plane cannot do that here.
        let n = 201
        var pts: [SIMD3<Float>] = [], cols: [SIMD3<Float>] = [], uvs: [CGPoint] = []
        pts.reserveCapacity(n * n)
        for j in 0..<n {
            let z = gridCoord(j, n)
            for i in 0..<n {
                let x = gridCoord(i, n)
                pts.append(SIMD3(x, 0, z))
                cols.append(waterColor(x, z, -height(x, z)))
                uvs.append(CGPoint(x: CGFloat(x) / 11, y: CGFloat(z) / 11))
            }
        }
        var idx: [UInt32] = []
        for j in 0..<n - 1 {
            for i in 0..<n - 1 {
                let a = UInt32(j * n + i), b = a + 1, c = a + UInt32(n), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let m = SK.mat(.white, roughness: 0.11, metalness: 0.03)
        m.normal.contents = SK.normalNoiseImage(size: 256, scale: 8, strength: 3, seed: 99)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.maxAnisotropy = 16
        m.normal.intensity = 0.38
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
        _geometry.position.y += h * amplitude;
        _geometry.normal = normalize(float3(-dx * amplitude, 1.0, -dy * amplitude));
        """]
        m.setValue(NSNumber(value: 0.16), forKey: "amplitude")
        m.setValue(NSNumber(value: 0.55), forKey: "choppiness")
        let g = SK.mesh(pts, idx, colors: cols, uvs: uvs)
        g.materials = [m]
        let w = SCNNode(geometry: g)      // built directly in world x/z: a flat sheet at y = 0
        w.castsShadow = false
        world.addChildNode(w)
        sea = w
    }

    /// Water colour by depth below the surface: foam at the waterline, pale turquoise over the
    /// reef flat, teal down the drop-off, deep blue in the open sea.
    private func waterColor(_ x: Float, _ z: Float, _ depth: Float) -> SIMD3<Float> {
        let n = noise.fbm(x / 34 + 3, z / 34, octaves: 3)
        var c: SIMD3<Float>
        if depth < 0.45 {
            c = SK.mix(SIMD3(0.60, 0.86, 0.80), SIMD3(0.24, 0.66, 0.60), SK.smoothstep(-0.25, 0.45, depth))
        } else if depth < 3.4 {
            c = SK.mix(SIMD3(0.24, 0.66, 0.60), SIMD3(0.05, 0.36, 0.40), SK.smoothstep(0.45, 3.4, depth))
        } else {
            c = SK.mix(SIMD3(0.05, 0.36, 0.40), SIMD3(0.01, 0.08, 0.18), SK.smoothstep(3.4, 15, depth))
        }
        return c * (0.90 + 0.20 * n)
    }

    // MARK: Palms

    /// One coconut palm: a bent trunk, a crown of nine fronds, a few coconuts.
    private func makePalm(height h: CGFloat, lean: CGFloat, seed: UInt64) -> SCNNode {
        var rr = Rng(s: seed)
        let root = SCNNode()
        let bendX = Float(lean), bendZ = Float(lean) * 0.35
        var rings: [SIMD3<Float>] = [], radii: [Float] = []
        let n = 8
        for i in 0...n {
            let t = Float(i) / Float(n)
            rings.append(SIMD3(bendX * t * t, Float(h) * t, bendZ * t * t))
            radii.append(0.30 - 0.13 * t)
        }
        let trunk = SK.node(tube(rings: rings, radii: radii, segments: 7, uvScale: 2), trunkMat)
        trunk.castsShadow = true
        root.addChildNode(trunk)
        // crown
        var pts: [SIMD3<Float>] = [], cols: [SIMD3<Float>] = [], idx: [UInt32] = []
        let fronds = 11
        for f in 0..<fronds {
            let yaw = Float(f) / Float(fronds) * 2 * .pi + rr.range(-0.16, 0.16)
            let len = rr.range(2.8, 3.9)
            let lift = rr.range(0.30, 0.55)
            let droop = rr.range(0.85, 1.55)
            let base = UInt32(pts.count)
            let steps = 7
            for i in 0...steps {
                let t = Float(i) / Float(steps)
                let dd = len * t
                let yy = lift * t * 2.0 - droop * t * t * 1.25
                let w = 0.46 * (1 - t * 0.8) + 0.03
                let cx = cosf(yaw) * dd, cz = sinf(yaw) * dd
                let px = -sinf(yaw), pz = cosf(yaw)
                let green = SK.mix(SIMD3(0.07, 0.24, 0.07), SIMD3(0.24, 0.50, 0.13), rr.next())
                pts.append(SIMD3(cx + px * w, yy, cz + pz * w))
                pts.append(SIMD3(cx, yy + 0.10 * (1 - t), cz))
                pts.append(SIMD3(cx - px * w, yy, cz - pz * w))
                cols.append(green); cols.append(green * 1.15); cols.append(green)
            }
            for i in 0..<UInt32(steps) {
                let a = base + i * 3
                idx += [a, a + 1, a + 3, a + 1, a + 4, a + 3]
                idx += [a + 1, a + 2, a + 4, a + 2, a + 5, a + 4]
            }
        }
        let crown = SCNNode(geometry: SK.mesh(pts, idx, colors: cols))
        crown.geometry?.materials = [frondMat]
        crown.position = SCNVector3(CGFloat(bendX), h, CGFloat(bendZ))
        crown.castsShadow = true
        root.addChildNode(crown)
        // coconuts
        if rr.next() > 0.35 {
            let nuts = SCNNode()
            for k in 0..<Int(rr.range(2.5, 5.4)) {
                let a = Float(k) * 1.9
                let nut = SK.sphere(0.12, nutMat, at: SCNVector3(CGFloat(cosf(a) * 0.26), -0.12 - CGFloat(k % 2) * 0.1, CGFloat(sinf(a) * 0.26)))
                nut.scale = SCNVector3(1, 0.9, 1)
                nuts.addChildNode(nut)
            }
            nuts.position = crown.position
            root.addChildNode(nuts)
        }
        return root
    }

    private func buildPalms() {
        var rr = Rng(s: 0xC0C0)
        var spots: [(Float, Float)] = []
        // a grove along the leeward beach and around the camp, thinner on the windward shore
        for i in 0..<46 {
            let a = Float(i) / 46 * 2 * .pi + rr.range(-0.07, 0.07)
            let west = max(0, sinf(a))                      // 1 on the +z (leeward) side
            let off = -(rr.range(1.5, 7.5) + west * rr.range(0, 5))
            var p = shore(a, off)
            // keep the camp clearing clear
            if p.0 > 33 && p.0 < 49 && p.1 > 4 && p.1 < 22 {
                p = shore(a, off - 9)
            }
            spots.append(p)
        }
        // an inland stand at the south end ("南头椰林")
        for i in 0..<10 {
            let sx: Float = Float(i) * 3.0 - 58
            let sz: Float = Float(i) * 1.1 - 2
            spots.append((sx + rr.range(-2, 2), sz + rr.range(-4, 4)))
        }
        for (i, p) in spots.enumerated() {
            guard abs(p.0) < A - 3, abs(p.1) < B - 2 else { continue }
            let y = ground(CGFloat(p.0), CGFloat(p.1))
            guard y > 1.2 else { continue }
            let palm = makePalm(height: CGFloat(rr.range(5.2, 9.4)), lean: CGFloat(rr.range(-0.9, 0.9)), seed: UInt64(700 + i))
            palm.position = SCNVector3(CGFloat(p.0), y, CGFloat(p.1))
            palm.eulerAngles.y = CGFloat(rr.range(0, 6.28))
            palm.scale = SCNVector3(1, CGFloat(rr.range(0.85, 1.15)), 1)
            world.addChildNode(palm)
            palms.append(palm)
        }
    }

    private var trunkMat: SCNMaterial {
        SK.noiseMat(SK.rgb(0x9E9078), SK.rgb(0x6B6252), scale: 6, roughness: 0.9, seed: 4)
    }
    private var frondMat: SCNMaterial {
        SK.mat(.white, roughness: 0.75, doubleSided: true)
    }
    private var nutMat: SCNMaterial { SK.mat(SK.rgb(0x7E6B2E), roughness: 0.8) }

    // MARK: Scrub (抗风桐 and beach shrubs)

    private func buildScrub() {
        var rr = Rng(s: 0x5C2B)
        let bushMat = SK.noiseMat(SK.rgb(0x2F5A24), SK.rgb(0x6A7C33), scale: 5, roughness: 0.85, seed: 7)
        let pisoniaMat = SK.noiseMat(SK.rgb(0x5C7C33), SK.rgb(0x9BB05A), scale: 4, roughness: 0.85, seed: 9)
        for i in 0..<300 {
            let x = rr.range(-64, 62), z = rr.range(-24, 24)
            let y = height(x, z)
            guard y > 1.6 else { continue }
            if x > 32 && x < 50 && z > 2 && z < 22 { continue }          // camp clearing
            let r = rr.range(0.55, 1.5)
            let bush = SK.rock(r, i % 5 == 0 ? pisoniaMat : bushMat, seed: UInt64(900 + i),
                               rings: 6, segments: 9, flatten: 0.60)
            bush.position = SCNVector3(CGFloat(x), CGFloat(y) - 0.12, CGFloat(z))
            bush.scale = SCNVector3(CGFloat(rr.range(0.9, 1.5)), CGFloat(rr.range(0.7, 1.2)), CGFloat(rr.range(0.9, 1.5)))
            bush.castsShadow = true
            world.addChildNode(bush)
        }
        // a few proper 抗风桐 trees with pale trunks
        for _ in 0..<12 {
            let x = rr.range(-55, 45), z = rr.range(-18, 18)
            let y = height(x, z)
            guard y > 1.8 else { continue }
            let tree = SCNNode()
            let trunk = SK.cylinder(0.16, 3.0, SK.noiseMat(SK.rgb(0xB8AE9A), SK.rgb(0x8A8270), scale: 5, seed: 3), at: SCNVector3(0, 1.5, 0))
            tree.addChildNode(trunk)
            for k in 0..<4 {
                let a = Float(k) * 1.6
                let blob = SK.rock(Float(rr.range(1.0, 1.7)), pisoniaMat, seed: UInt64(1500 + k), rings: 6, segments: 9, flatten: 0.7)
                blob.position = SCNVector3(CGFloat(cosf(a) * rr.range(0.3, 1.2)), CGFloat(rr.range(2.6, 3.6)), CGFloat(sinf(a) * rr.range(0.3, 1.2)))
                blob.scale = SCNVector3(1.2, 0.85, 1.2)
                blob.castsShadow = true
                tree.addChildNode(blob)
            }
            tree.position = SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
            tree.scale = SCNVector3(1, CGFloat(rr.range(0.8, 1.3)), 1)
            world.addChildNode(tree)
        }
    }

    // MARK: The wreck of 海燕号

    private func buildWreck() {
        let hullMat = SK.mat(SK.rgb(0xEDF0F2), roughness: 0.30, metalness: 0.08)
        let dark = SK.mat(SK.rgb(0x1E2A33), roughness: 0.5)
        let navy = SK.mat(SK.rgb(0x1B4F86), roughness: 0.42)
        let wood = SK.noiseMat(SK.rgb(0xA08E70), SK.rgb(0x6E6047), scale: 5, seed: 21)
        let sailMat = SK.mat(SK.rgb(0xE8E4D8), roughness: 0.88, doubleSided: true)

        let w = SCNNode()
        w.position = SCNVector3(-2, -0.6, 74)
        w.scale = SCNVector3(0.92, 0.92, 0.92)
        w.eulerAngles = SCNVector3(0.06, 0.5, 0.42)          // heeled hard over, half awash
        // hull: a long flattened capsule, a raked bow and a sugar-scoop stern
        let hull = SK.node(SCNCapsule(capRadius: 1.05, height: 7.6), hullMat)
        hull.eulerAngles.z = .pi / 2
        hull.scale = SCNVector3(1.0, 1.0, 0.60)
        w.addChildNode(hull)
        let bow = SK.node(SCNCone(topRadius: 0.06, bottomRadius: 1.0, height: 2.6), hullMat)
        bow.eulerAngles.z = .pi / 2
        bow.scale = SCNVector3(1.0, 1.0, 0.60)
        bow.position = SCNVector3(4.9, 0.28, 0)
        w.addChildNode(bow)
        // boot-top stripe and the dark underwater body
        let stripe = SK.box(8.4, 0.14, 0.03, navy, at: SCNVector3(0.4, -0.30, 1.28))
        w.addChildNode(stripe)
        let under = SK.box(8.0, 0.5, 1.5, navy, at: SCNVector3(0.4, -0.75, 0))
        w.addChildNode(under)
        // deck, coachroof, windows, a pulpit and a wheel
        let deck = SK.box(8.6, 0.12, 2.0, SK.mat(SK.rgb(0xD9D2C4), roughness: 0.7), chamfer: 0.03, at: SCNVector3(0.4, 0.62, 0))
        w.addChildNode(deck)
        let cabin = SK.box(3.2, 0.62, 1.5, hullMat, chamfer: 0.14, at: SCNVector3(0.6, 1.0, 0))
        w.addChildNode(cabin)
        for i in 0..<3 {
            w.addChildNode(SK.box(0.52, 0.22, 0.04, dark, chamfer: 0.04, at: SCNVector3(-0.3 + CGFloat(i) * 0.9, 1.05, 0.78)))
        }
        let wheelPost = SK.cylinder(0.06, 0.8, hullMat, at: SCNVector3(-2.4, 1.05, 0.2))
        w.addChildNode(wheelPost)
        // the mast broke at the spreaders and is lying across the water
        let mast = driftwood(9.0, 0.11, seed: 3, mat: wood)
        mast.position = SCNVector3(-1.6, 0.75, -0.6)
        mast.eulerAngles = SCNVector3(0.35, 0.6, -1.02)
        w.addChildNode(mast)
        let boom = driftwood(4.4, 0.09, seed: 8, mat: wood)
        boom.position = SCNVector3(2.0, 0.55, 1.1)
        boom.eulerAngles = SCNVector3(0.12, 2.3, 0.16)
        w.addChildNode(boom)
        let sail = SK.box(2.6, 0.05, 2.0, sailMat, at: SCNVector3(-5.0, 0.12, -2.6))
        sail.eulerAngles = SCNVector3(0.06, 0.45, 0.05)
        w.addChildNode(sail)
        for i in 0..<3 {
            let shroud = SK.cylinder(0.014, 4.0, SK.mat(SK.rgb(0xD9D2BE), roughness: 0.9))
            shroud.position = SCNVector3(-1.0 + CGFloat(i) * 1.4, 1.2, 0.9 - CGFloat(i) * 0.3)
            shroud.eulerAngles = SCNVector3(0.5 - CGFloat(i) * 0.4, 0, -1.1)
            w.addChildNode(shroud)
        }
        w.castsShadow = true
        world.addChildNode(w)
        wreck = w

        // the after part that has already broken off and slipped under the reef edge
        let sunk = SCNNode()
        sunk.position = SCNVector3(-14, -2.2, 78)
        sunk.eulerAngles = SCNVector3(0, 0.8, -0.5)
        sunk.addChildNode(SK.box(4.2, 0.8, 1.4, hullMat, chamfer: 0.25))
        sunk.addChildNode(SK.cylinder(0.10, 4.5, wood, at: SCNVector3(1.0, 0.9, 0)))
        sunk.isHidden = true
        world.addChildNode(sunk)
        wreckSunk = sunk
    }

    // MARK: Camp

    private func buildCamp() {
        let poleMat = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 31)
        let thatch = SK.noiseMat(SK.rgb(0x8E7C42), SK.rgb(0x4E5C2C), scale: 7, roughness: 0.9, seed: 33)
        let matMat = SK.noiseMat(SK.rgb(0xC2B183), SK.rgb(0x7C7A46), scale: 8, roughness: 0.95, seed: 35)

        let hut = SCNNode()
        hut.position = SCNVector3(40.5, ground(40.5, 13), 13)
        hut.scale = SCNVector3(1.4, 1.35, 1.4)
        hut.eulerAngles.y = 0.9
        world.addChildNode(hut)

        // posts, ridge and eave beams (a lean-to, high at the back, open toward the fire)
        for (x, z, h) in [(-1.8, 1.5, 1.55), (1.8, 1.5, 1.55), (-1.8, -1.5, 2.35), (1.8, -1.5, 2.35)] as [(CGFloat, CGFloat, CGFloat)] {
            hut.addChildNode(SK.cylinder(0.075, h, poleMat, at: SCNVector3(x, h / 2, z)))
        }
        let beam = SK.cylinder(0.07, 3.9, poleMat)
        beam.eulerAngles.z = .pi / 2
        beam.position = SCNVector3(0, 2.35, -1.5)
        hut.addChildNode(beam)
        let eave = SK.cylinder(0.07, 3.9, poleMat)
        eave.eulerAngles.z = .pi / 2
        eave.position = SCNVector3(0, 1.55, 1.5)
        hut.addChildNode(eave)
        // three overlapping thatch panels up the roof slope
        for i in 0..<3 {
            let t = 0.18 + CGFloat(i) * 0.32
            let panel = SK.box(4.0, 0.08, 1.15, thatch, chamfer: 0.05)
            panel.position = SCNVector3(0, 2.35 - 0.80 * t, -1.5 + 3.0 * t)
            panel.eulerAngles.x = -0.26
            panel.castsShadow = true
            hut.addChildNode(panel)
            hutRoof.append(panel)
        }
        // side windbreaks
        for x in [-1.8, 1.8] as [CGFloat] {
            let side = SK.box(0.06, 1.1, 2.9, thatch, chamfer: 0.03)
            side.position = SCNVector3(x, 0.75, 0)
            side.castsShadow = true
            hut.addChildNode(side)
            hutSides.append(side)
        }
        // a floor of palm mats and a rolled blanket — someone lies here out of the sun
        let floorMat = SK.box(3.4, 0.08, 2.7, matMat, chamfer: 0.02, at: SCNVector3(0, 0.06, 0))
        hut.addChildNode(floorMat)
        let bed = SK.box(1.0, 0.16, 1.9, matMat, chamfer: 0.06, at: SCNVector3(0.9, 0.16, 0.1))
        hut.addChildNode(bed)

        // driftwood windbreak fence on the seaward side of the camp
        for i in 0..<6 {
            let p = shore(1.15 + Float(i) * 0.055, -13)
            let post = SCNNode()
            post.position = SCNVector3(CGFloat(p.0), ground(CGFloat(p.0), CGFloat(p.1)), CGFloat(p.1))
            post.eulerAngles.y = CGFloat(1.15 + Float(i) * 0.055) + .pi / 2
            post.addChildNode(SK.cylinder(0.06, 1.5, poleMat, at: SCNVector3(0, 0.75, 0)))
            let panel = SK.box(2.0, 0.95, 0.06, thatch, chamfer: 0.02, at: SCNVector3(0, 0.95, 0))
            panel.castsShadow = true
            post.addChildNode(panel)
            world.addChildNode(post)
            fence.append(post)
        }

        // water: a barrel, jerry cans and a row of coconut-shell cups; the liferaft basin is
        // flipped over and used as a tank once the stores grow.
        let blue = SK.mat(SK.rgb(0x2E6FA8), roughness: 0.55)
        let barrel = SK.cylinder(0.34, 0.92, blue, at: SCNVector3(36.5, ground(36.5, 13) + 0.46, 13))
        world.addChildNode(barrel); stores.append(barrel)
        for i in 0..<2 {
            let can = SK.box(0.28, 0.42, 0.19, SK.mat(SK.rgb(0xD8D3C4), roughness: 0.6),
                             at: SCNVector3(37.6 + CGFloat(i) * 0.36, ground(37.6, 12) + 0.21, 12.2 + CGFloat(i) * 0.3))
            world.addChildNode(can); stores.append(can)
        }
        let shells = SCNNode()
        for i in 0..<7 {
            let a = Float(i) * 0.9
            let s = SK.sphere(0.11, nutMat, at: SCNVector3(CGFloat(cosf(a)) * 0.5, 0.05, CGFloat(sinf(a)) * 0.5))
            s.scale = SCNVector3(1, 0.6, 1)
            shells.addChildNode(s)
        }
        shells.position = SCNVector3(35.5, ground(35.5, 12.4), 12.4)
        world.addChildNode(shells); stores.append(shells)
        let raftTank = SCNNode()
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 1.15, pipeRadius: 0.24))
        ring.geometry?.materials = [SK.mat(SK.rgb(0xE2662A), roughness: 0.7)]
        ring.eulerAngles.x = .pi / 2
        ring.position.y = 0.25
        raftTank.addChildNode(ring)
        let basin = SK.cylinder(1.05, 0.42, SK.mat(SK.rgb(0xC9551F), roughness: 0.75), at: SCNVector3(0, 0.21, 0))
        raftTank.addChildNode(basin)
        raftTank.position = SCNVector3(38.6, ground(38.6, 15.5), 15.5)
        world.addChildNode(raftTank); stores.append(raftTank)

        // the tally plank: days scratched into a ship's board, and the rule it stands for
        let plank = SCNNode()
        plank.position = SCNVector3(33.2, ground(33.2, 14), 14)
        plank.eulerAngles.y = 0.4
        plank.addChildNode(SK.cylinder(0.05, 1.3, poleMat, at: SCNVector3(0, 0.65, 0)))
        let board = SK.box(0.9, 0.55, 0.05, SK.noiseMat(SK.rgb(0xB9A87F), SK.rgb(0x8A7A55), scale: 6, seed: 41),
                           chamfer: 0.02, at: SCNVector3(0, 1.05, 0.04))
        board.name = "board"
        board.eulerAngles.x = -0.18
        plank.addChildNode(board)
        for i in 0..<30 {
            let mark = SK.box(0.02, 0.30, 0.01, SK.mat(SK.rgb(0x3A2C1A), roughness: 1), chamfer: 0)
            mark.position = SCNVector3(-0.38 + CGFloat(i % 15) * 0.055, 1.05 + (i < 15 ? 0.09 : -0.09), 0.08)
            mark.eulerAngles.x = -0.18
            plank.addChildNode(mark)
            tallyMarks.append(mark)
        }
        board.isHidden = true // the board itself is shown from round 4 on
        rulePlank = plank
        world.addChildNode(plank)

        // fishing gear: a spear, a net frame and a drying rack with a few fish
        let spear = SCNNode()
        let shaft = SK.cylinder(0.035, 3.0, poleMat, at: SCNVector3(0, 1.5, 0))
        spear.addChildNode(shaft)
        for k in -1...1 {
            let prong = SK.cylinder(0.012, 0.4, SK.mat(SK.rgb(0xB9BEC4), roughness: 0.3, metalness: 0.8),
                                    at: SCNVector3(CGFloat(k) * 0.06, 3.15, 0))
            prong.eulerAngles.z = CGFloat(k) * 0.12
            spear.addChildNode(prong)
        }
        spear.position = SCNVector3(31.5, ground(31.5, 18.5), 18.5)
        spear.eulerAngles = SCNVector3(0.12, 0.6, 0.05)
        world.addChildNode(spear)
        world.addChildNode(fishRack(at: SCNVector3(44, ground(44, 17), 17)))
        // a cook pot on the fire stones is part of the fire (see addFire) — add the tripod here
        let tripod = SCNNode()
        tripod.position = SCNVector3(34, ground(34, 17), 17)
        for i in 0..<3 {
            let a = CGFloat(i) / 3 * 2 * .pi
            let leg = SK.cylinder(0.035, 1.5, poleMat)
            leg.position = SCNVector3(cos(a) * 0.55, 0.72, sin(a) * 0.55)
            leg.eulerAngles = SCNVector3(cos(a) * 0.35, 0, -sin(a) * 0.35)
            tripod.addChildNode(leg)
        }
        let pot = SK.sphere(0.26, SK.mat(SK.rgb(0x2A2A2C), roughness: 0.7, metalness: 0.4), at: SCNVector3(0, 0.95, 0))
        pot.scale = SCNVector3(1, 0.85, 1)
        tripod.addChildNode(pot)
        world.addChildNode(tripod)

        // the distillation rig (pot, copper tube, bottle) appears once they boil sea water
        let still = SCNNode()
        still.position = SCNVector3(36.4, ground(36.4, 18.4), 18.4)
        still.addChildNode(SK.cylinder(0.30, 0.42, SK.mat(SK.rgb(0x3A3A3C), roughness: 0.6, metalness: 0.5), at: SCNVector3(0, 0.21, 0)))
        let lid = SK.cylinder(0.32, 0.06, SK.mat(SK.rgb(0x8A6A3A), roughness: 0.4, metalness: 0.6), at: SCNVector3(0, 0.45, 0))
        still.addChildNode(lid)
        let tubeN = SK.cylinder(0.04, 1.1, SK.mat(SK.rgb(0xB0723A), roughness: 0.35, metalness: 0.7), at: SCNVector3(0.35, 0.75, 0.2))
        tubeN.eulerAngles.z = -0.9
        still.addChildNode(tubeN)
        still.addChildNode(SK.cylinder(0.14, 0.36, SK.mat(SK.rgb(0x9FB4A8), roughness: 0.15), at: SCNVector3(0.9, 0.18, 0.4)))
        still.isHidden = true
        world.addChildNode(still)
        distillery = still
    }

    /// A driftwood frame with a few split fish drying in the sun.
    private func fishRack(at p: SCNVector3) -> SCNNode {
        let rack = SCNNode()
        rack.position = p
        rack.eulerAngles.y = 0.5
        let wood = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 31)
        for dx in [-1.1, 1.1] as [CGFloat] {
            rack.addChildNode(SK.cylinder(0.055, 1.7, wood, at: SCNVector3(dx, 0.85, 0)))
            rack.addChildNode(SK.cylinder(0.04, 0.9, wood, at: SCNVector3(dx, 0.45, 0)))
        }
        for dy in [1.45, 1.05] as [CGFloat] {
            let bar = SK.cylinder(0.035, 2.3, wood)
            bar.eulerAngles.z = .pi / 2
            bar.position = SCNVector3(0, dy, 0)
            rack.addChildNode(bar)
        }
        let fishMat = SK.noiseMat(SK.rgb(0xB9C6CC), SK.rgb(0x6E8288), scale: 6, roughness: 0.55, seed: 51)
        for i in 0..<4 {
            let f = SCNNode()
            let body = SK.sphere(0.16, fishMat)
            body.scale = SCNVector3(0.55, 1.6, 0.3)
            f.addChildNode(body)
            let tail = SK.node(SCNCone(topRadius: 0.13, bottomRadius: 0.02, height: 0.2), fishMat)
            tail.position.y = -0.34
            tail.eulerAngles.z = .pi
            f.addChildNode(tail)
            f.position = SCNVector3(-0.8 + CGFloat(i) * 0.55, dy0(i), 0)
            rack.addChildNode(f)
        }
        return rack
    }
    private func dy0(_ i: Int) -> CGFloat { i % 2 == 0 ? 1.24 : 0.84 }

    // MARK: Projects (rain catcher, cistern, signal beacon)

    private func buildProjects() {
        let poleMat = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 31)
        let canvas = SK.mat(SK.rgb(0xCBC3AD), roughness: 0.9, doubleSided: true)
        let blue = SK.mat(SK.rgb(0x2E6FA8), roughness: 0.55)

        // 集雨棚: a canvas funnel slung between four poles, running down into a barrel
        let c = SCNNode()
        c.position = SCNVector3(29, ground(29, 12), 12)
        c.eulerAngles.y = -0.35
        for (x, z, h) in [(-2.6, -1.9, 3.2), (2.6, -1.9, 3.2), (-2.6, 1.9, 1.7), (2.6, 1.9, 1.7)] as [(CGFloat, CGFloat, CGFloat)] {
            c.addChildNode(SK.cylinder(0.06, h, poleMat, at: SCNVector3(x, h / 2, z)))
        }
        // the two halves of the sheet sag toward the middle line, where the water runs off
        for (sgn, ang) in [(-1.0, CGFloat(-0.78)), (1.0, CGFloat(0.78))] as [(CGFloat, CGFloat)] {
            let half = SK.box(4.4, 0.05, 1.9, canvas, chamfer: 0)
            half.position = SCNVector3(0, 2.2, sgn * 0.72)
            half.eulerAngles.x = ang
            half.castsShadow = true
            c.addChildNode(half)
        }
        let gutter = SK.box(4.6, 0.12, 0.26, canvas, chamfer: 0, at: SCNVector3(0, 1.40, 0))
        c.addChildNode(gutter)
        let spout = SK.cylinder(0.05, 0.6, poleMat, at: SCNVector3(1.4, 1.1, 0))
        c.addChildNode(spout)
        let barrel = SK.cylinder(0.30, 0.85, blue, at: SCNVector3(1.4, 0.42, 0))
        c.addChildNode(barrel)
        world.addChildNode(c)
        catcher = c
        // the same canvas lying in a heap before it is rigged
        let loose = SK.box(3.6, 0.55, 2.2, canvas, chamfer: 0.22)
        loose.position = SCNVector3(28.6, ground(28.6, 14.5) + 0.22, 14.5)
        loose.eulerAngles = SCNVector3(0.05, 0.4, 0.06)
        let fold = SK.box(2.2, 0.40, 1.4, canvas, chamfer: 0.18)
        fold.position = SCNVector3(1.1, 0.32, -0.7)
        fold.eulerAngles = SCNVector3(-0.1, 0.9, -0.12)
        loose.addChildNode(fold)
        loose.castsShadow = true
        world.addChildNode(loose)
        catcherLoose = loose

        // 树干水槽: a hollowed palm trunk on trestles, in the shade of the grove
        let t = SCNNode()
        t.position = SCNVector3(43.5, ground(43.5, 19.5), 19.5)
        t.eulerAngles.y = 0.25
        let log = SCNNode(geometry: SCNCylinder(radius: 0.42, height: 4.2))
        log.geometry?.materials = [SK.noiseMat(SK.rgb(0xA8967A), SK.rgb(0x6E6248), scale: 5, seed: 61)]
        log.eulerAngles.z = .pi / 2
        log.position.y = 0.62
        log.castsShadow = true
        t.addChildNode(log)
        // the hollow and the water in it
        let hollow = SK.box(3.6, 0.30, 0.42, SK.mat(SK.rgb(0x2A231A), roughness: 1), at: SCNVector3(0, 0.86, 0))
        t.addChildNode(hollow)
        let water = SK.box(3.4, 0.10, 0.34, SK.mat(SK.rgb(0x2E6B6E), roughness: 0.1), at: SCNVector3(0, 0.88, 0))
        t.addChildNode(water)
        for dx in [-1.3, 1.3] as [CGFloat] {
            t.addChildNode(SK.box(0.3, 0.5, 0.7, poleMat, chamfer: 0.02, at: SCNVector3(dx, 0.25, 0)))
        }
        for (dz, ang) in [(-0.30, CGFloat(0.35)), (0.30, CGFloat(-0.35))] as [(CGFloat, CGFloat)] {
            let lid = SK.box(4.3, 0.05, 0.62, SK.noiseMat(SK.rgb(0x8A9A4A), SK.rgb(0x5C6B2E), scale: 6, seed: 63),
                             at: SCNVector3(0, 1.06, dz))
            lid.eulerAngles.x = ang
            lid.castsShadow = true
            t.addChildNode(lid)
        }
        t.isHidden = true
        world.addChildNode(t)
        cistern = t
        // before it is finished: a trunk lying in the sand, only the ends opened
        let raw = SCNNode()
        raw.position = SCNVector3(43.5, ground(43.5, 21.5), 21.5)
        raw.eulerAngles = SCNVector3(0, 0.3, 0)
        let rawLog = SCNNode(geometry: SCNCylinder(radius: 0.42, height: 4.2))
        rawLog.geometry?.materials = [SK.noiseMat(SK.rgb(0xA8967A), SK.rgb(0x6E6248), scale: 5, seed: 61)]
        rawLog.eulerAngles.z = .pi / 2
        rawLog.position.y = 0.42
        raw.addChildNode(rawLog)
        raw.addChildNode(SK.sphere(0.2, SK.mat(SK.rgb(0x2A231A), roughness: 1), at: SCNVector3(2.1, 0.42, 0)))
        raw.isHidden = true
        world.addChildNode(raw)
        cisternLog = raw

        // 高地信号火堆: a beacon of driftwood and palm fronds on the headland
        var rr = Rng(s: 0xBEA)
        let b = SCNNode()
        let bx: CGFloat = 48.5, bz: CGFloat = 1.5
        b.position = SCNVector3(bx, ground(bx, bz), bz)
        b.scale = SCNVector3(1.25, 1.25, 1.25)
        let wood = SK.noiseMat(SK.rgb(0x9C8A6A), SK.rgb(0x6A5C42), scale: 4, seed: 71)
        for i in 0..<16 {
            let a = Float(i) * 2.4
            let r = CGFloat(rr.range(0.1, 0.9))
            let logNode = driftwood(CGFloat(rr.range(2.2, 3.4)), 0.11, seed: UInt64(300 + i), mat: wood)
            logNode.position = SCNVector3(CGFloat(cosf(a)) * r, CGFloat(rr.range(0.1, 1.9)), CGFloat(sinf(a)) * r)
            logNode.eulerAngles = SCNVector3(CGFloat(rr.range(-0.5, 0.5)), CGFloat(rr.range(0, 6.28)), CGFloat(rr.range(-0.6, 0.6)))
            b.addChildNode(logNode)
        }
        for i in 0..<5 {
            let a = Float(i) * 1.3
            let frond = SK.box(1.5, 0.05, 0.7, SK.noiseMat(SK.rgb(0x8A7040), SK.rgb(0x5E6B33), scale: 6, seed: 73),
                               at: SCNVector3(CGFloat(cosf(a)) * 0.8, 2.1 + CGFloat(i % 2) * 0.25, CGFloat(sinf(a)) * 0.8))
            frond.eulerAngles = SCNVector3(0.2, CGFloat(a), 0.3)
            b.addChildNode(frond)
        }
        b.isHidden = true
        world.addChildNode(b)
        beacon = b

        // the flame: an emissive cone shown when the beacon is touched off
        let flame = SCNNode()
        let cone = SK.node(SCNCone(topRadius: 0.05, bottomRadius: 0.55, height: 1.5),
                           SK.mat(SK.rgb(0xFF8A2A), roughness: 1, emission: SK.rgb(0xFF6A18)))
        cone.position.y = 1.9
        flame.addChildNode(cone)
        let glow = SK.fireLight(intensity: 900, color: SK.rgb(0xFF9442), range: 22)
        glow.position.y = 2.0
        flame.addChildNode(glow)
        flame.isHidden = true
        b.addChildNode(flame)
        beaconFlame = flame
    }

    // MARK: Raft and banca boat

    private func buildRaft() {
        let wood = SK.noiseMat(SK.rgb(0xA8967A), SK.rgb(0x6E6248), scale: 5, seed: 61)
        let rope = SK.mat(SK.rgb(0xC9B98A), roughness: 0.95)
        let logs = SCNNode()
        logs.position = SCNVector3(16, ground(16, 33) + 0.22, 33)
        logs.eulerAngles.y = 0.18
        world.addChildNode(logs)
        for i in 0..<6 {
            let z = -1.4 + CGFloat(i) * 0.56
            let log = SK.cylinder(0.24, 4.6, wood, at: SCNVector3(0, 0, z))
            log.eulerAngles.z = .pi / 2
            log.castsShadow = true
            logs.addChildNode(log)
        }
        raftLogs = logs
        let lash = SCNNode()
        lash.position = logs.position
        lash.eulerAngles.y = logs.eulerAngles.y
        for x in [-1.7, 0, 1.7] as [CGFloat] {
            let beam = SK.box(0.14, 0.1, 3.6, wood, chamfer: 0.02, at: SCNVector3(x, 0.24, 0))
            lash.addChildNode(beam)
            for i in 0..<5 {
                let tie = SK.cylinder(0.03, 0.5, rope, at: SCNVector3(x, 0.24, -1.3 + CGFloat(i) * 0.64))
                tie.eulerAngles.x = .pi / 2
                lash.addChildNode(tie)
            }
        }
        world.addChildNode(lash)
        raftLash = lash
        let mast = SCNNode()
        mast.position = SCNVector3(15.6, ground(16, 33), 33)
        mast.addChildNode(SK.cylinder(0.09, 3.6, wood, at: SCNVector3(0, 1.8, 0)))
        let boom = SK.cylinder(0.06, 2.1, wood)
        boom.eulerAngles.z = .pi / 2
        boom.position = SCNVector3(0.9, 1.0, 0)
        mast.addChildNode(boom)
        // a scrap of sail: a triangle bent on the boom and the mast
        let sp: [SIMD3<Float>] = [SIMD3(0.1, 1.0, 0), SIMD3(2.0, 1.0, 0), SIMD3(0.1, 3.3, 0)]
        let sail = SCNNode(geometry: SK.mesh(sp, [0, 1, 2]))
        sail.geometry?.materials = [SK.mat(SK.rgb(0xE4DFD0), roughness: 0.9, doubleSided: true)]
        sail.eulerAngles.y = 0.6
        sail.castsShadow = true
        mast.addChildNode(sail)
        mast.isHidden = true
        world.addChildNode(mast)
        raftMast = mast
        // the finished raft (shown when flag raft_built)
        let done = SCNNode()
        done.position = logs.position
        done.eulerAngles.y = logs.eulerAngles.y
        for i in 0..<10 {
            let a = Float(i) * 1.9
            done.addChildNode(SK.cylinder(0.05, 0.55, rope, at: SCNVector3(CGFloat(cosf(a)) * 0.9, 0.1, CGFloat(sinf(a)) * 0.9)))
        }
        done.isHidden = true
        world.addChildNode(done)
        raft = done
        // a tiny raft far out at sea once someone sails it
        let sea = SCNNode()
        sea.position = SCNVector3(-120, 0.1, 300)
        sea.addChildNode(SK.box(3.0, 0.2, 1.6, wood))
        sea.addChildNode(SK.cylinder(0.06, 2.4, wood, at: SCNVector3(0, 1.2, 0)))
        let ds = SCNNode(geometry: SK.mesh([SIMD3(0, 1.2, 0), SIMD3(1.4, 1.2, 0), SIMD3(0, 2.7, 0)], [0, 1, 2]))
        ds.geometry?.materials = [SK.mat(SK.rgb(0xE4DFD0), roughness: 0.9, doubleSided: true)]
        sea.addChildNode(ds)
        sea.isHidden = true
        world.addChildNode(sea)
        raftAtSea = sea
    }

    private func buildBanca() {
        let hullMat = SK.noiseMat(SK.rgb(0xC8BFA6), SK.rgb(0x8A7E62), scale: 4, seed: 81)
        let bamboo = SK.noiseMat(SK.rgb(0xC9C08A), SK.rgb(0x8E8A50), scale: 6, seed: 83)
        let good = SCNNode()
        good.position = SCNVector3(-14, -0.25, 39)
        good.eulerAngles = SCNVector3(0.03, 0.5, 0.02)
        let hull = SK.node(SCNCapsule(capRadius: 0.42, height: 4.6), hullMat)
        hull.eulerAngles.z = .pi / 2
        hull.scale = SCNVector3(1, 1, 0.75)
        hull.position.y = 0.42
        hull.castsShadow = true
        good.addChildNode(hull)
        good.addChildNode(SK.box(1.2, 0.4, 0.5, SK.mat(SK.rgb(0x2E6FA8), roughness: 0.7), at: SCNVector3(0.2, 0.72, 0)))
        for dx in [-1.1, 1.1] as [CGFloat] {
            let float = SK.cylinder(0.11, 5.2, bamboo)
            float.eulerAngles.z = .pi / 2
            float.position = SCNVector3(0, 0.35, dx * 1.5)
            good.addChildNode(float)
            let arm = SK.cylinder(0.07, 3.0, bamboo)
            arm.eulerAngles.x = .pi / 2
            arm.position = SCNVector3(0, 1.0, dx * 0.75)
            good.addChildNode(arm)
        }
        let mast = SK.cylinder(0.07, 3.0, bamboo, at: SCNVector3(0, 1.5, 0))
        good.addChildNode(mast)
        let sail = SK.box(0.05, 1.9, 1.5, SK.mat(SK.rgb(0xDCD6C4), roughness: 0.9, doubleSided: true), at: SCNVector3(0.05, 1.7, -0.8))
        sail.castsShadow = true
        good.addChildNode(sail)
        world.addChildNode(good)
        banca = good
        // the wreck of it: hull on its side with a split seam, no outrigger
        let bad = SCNNode()
        bad.position = SCNVector3(-15, ground(-15, 32), 32)
        bad.eulerAngles = SCNVector3(0.12, 0.5, 0.55)
        let badHull = SK.node(SCNCapsule(capRadius: 0.42, height: 4.6), hullMat)
        badHull.eulerAngles.z = .pi / 2
        badHull.scale = SCNVector3(1, 1, 0.75)
        bad.addChildNode(badHull)
        bad.addChildNode(SK.box(1.6, 0.06, 0.3, SK.mat(SK.rgb(0x2A231A), roughness: 1), at: SCNVector3(0.3, 0.2, 0)))
        for i in 0..<3 {
            bad.addChildNode(driftwood(1.6, 0.09, seed: UInt64(400 + i), mat: bamboo))
        }
        world.addChildNode(bad)
        bancaWreck = bad
    }

    // MARK: Signal — coral-stone SOS on the sand, a flag mast on the headland

    private func buildSignal() {
        // three letters 5 m tall laid out on the open beach, made of white coral stones
        let coral = SK.mat(SK.rgb(0xF2F0E6), roughness: 0.85)
        let origin = SCNVector3(-34, 0, 34)
        func stroke(_ x0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ z1: CGFloat, _ letter: Int) {
            let n = 8
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n - 1)
                let x = origin.x + x0 + (x1 - x0) * t
                let z = origin.z + z0 + (z1 - z0) * t
                for s in 0..<3 {
                    let ox = CGFloat(s) * 0.34 - 0.34
                    let stone = SK.rock(Float(0.30 + Double(k % 3) * 0.05), coral, seed: UInt64(500 + letter * 40 + k * 3 + s), rings: 6, segments: 8, flatten: 0.45)
                    stone.position = SCNVector3(x + ox, ground(x + ox, z) + 0.05, z)
                    stone.isHidden = true
                    world.addChildNode(stone)
                    sosLetters[letter].append(stone)
                }
            }
        }
        sosLetters = [[], [], []]
        // letters run along +x, "up" is −z so they read from a boat off the beach
        stroke(0, -3.6, 3.6, -3.6, 0); stroke(0, -3.6, 0, 0, 0); stroke(0, 0, 3.6, 0, 0)
        stroke(3.6, 0, 3.6, 3.6, 0); stroke(3.6, 3.6, 0, 3.6, 0)
        stroke(5.6, -3.6, 9.2, -3.6, 1); stroke(9.2, -3.6, 9.2, 3.6, 1)
        stroke(9.2, 3.6, 5.6, 3.6, 1); stroke(5.6, 3.6, 5.6, -3.6, 1)
        stroke(11.2, -3.6, 14.8, -3.6, 2); stroke(11.2, -3.6, 11.2, 0, 2); stroke(11.2, 0, 14.8, 0, 2)
        stroke(14.8, 0, 14.8, 3.6, 2); stroke(14.8, 3.6, 11.2, 3.6, 2)

        // the flag mast on the headland: driftwood, a scrap of sail, a tin can that clatters
        let wood = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 91)
        let mast = SCNNode()
        let mx: CGFloat = 53, mz: CGFloat = -1
        mast.position = SCNVector3(mx, ground(mx, mz), mz)
        let pole = SK.cylinder(0.075, 5.2, wood, at: SCNVector3(0, 2.6, 0))
        mast.addChildNode(pole)
        for i in 0..<3 {
            let guy = SK.cylinder(0.012, 3.2, SK.mat(SK.rgb(0xD9D2BE), roughness: 0.9))
            let a = CGFloat(i) / 3 * 2 * .pi
            guy.position = SCNVector3(cos(a) * 0.85, 1.4, sin(a) * 0.85)
            guy.eulerAngles = SCNVector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
            mast.addChildNode(guy)
        }
        for i in 0..<3 {
            let a = CGFloat(i) * 2.0
            let cloth = SK.box(1.5 + CGFloat(i) * 1.0, 1.0 + CGFloat(i) * 0.6, 0.03,
                               SK.mat(SK.rgb(i == 1 ? 0xE2662A : 0xE8E4D8), roughness: 0.92, doubleSided: true),
                               at: SCNVector3(0.55 + CGFloat(i) * 0.35, 4.4 - CGFloat(i) * 0.75, 0))
            cloth.eulerAngles.y = a * 0.25
            cloth.castsShadow = true
            cloth.isHidden = true
            mast.addChildNode(cloth)
            flagCloths.append(cloth)
        }
        world.addChildNode(mast)
    }

    // MARK: Flotsam and the tide line

    private func buildFlotsam() {
        var rr = Rng(s: 0xF107)
        let wood = SK.noiseMat(SK.rgb(0xA08E70), SK.rgb(0x6E6047), scale: 5, seed: 21)
        let plastic = SK.mat(SK.rgb(0xD8D3C4), roughness: 0.5)
        // the tide line: weed, shells and rubbish along the top of the beach all round the island
        for i in 0..<70 {
            let a = Float(i) / 70 * 2 * .pi + rr.range(-0.03, 0.03)
            let off = rr.range(5.0, 10.5)
            let p = shore(a, off)
            let y = ground(CGFloat(p.0), CGFloat(p.1))
            guard y > -0.4 else { continue }
            switch i % 7 {
            case 0, 1:
                let stick = driftwood(CGFloat(rr.range(0.5, 2.4)), 0.07, seed: UInt64(1000 + i), mat: wood)
                stick.position = SCNVector3(CGFloat(p.0), y + 0.06, CGFloat(p.1))
                stick.eulerAngles = SCNVector3(CGFloat(rr.range(-0.1, 0.1)), CGFloat(rr.range(0, 6.3)), CGFloat(rr.range(-0.1, 0.1)))
                world.addChildNode(stick)
            case 2:
                let shell = SK.rock(Float(rr.range(0.10, 0.24)), SK.mat(SK.rgb(0xE8E2D2), roughness: 0.7), seed: UInt64(1100 + i), rings: 5, segments: 7, flatten: 0.4)
                shell.position = SCNVector3(CGFloat(p.0), y + 0.03, CGFloat(p.1))
                world.addChildNode(shell)
            case 3:
                let weed = SK.sphere(CGFloat(rr.range(0.22, 0.5)), SK.noiseMat(SK.rgb(0x5A5A2E), SK.rgb(0x2E3A1E), scale: 6, seed: 5),
                                     at: SCNVector3(CGFloat(p.0), y + 0.1, CGFloat(p.1)), segments: 8)
                weed.scale = SCNVector3(1.4, 0.35, 1.4)
                world.addChildNode(weed)
            case 4:
                let bottle = SK.cylinder(0.07, 0.26, SK.mat(SK.rgb(0x7FBFA8), roughness: 0.25),
                                         at: SCNVector3(CGFloat(p.0), y + 0.13, CGFloat(p.1)))
                bottle.eulerAngles = SCNVector3(1.4, CGFloat(rr.range(0, 6.3)), 0)
                world.addChildNode(bottle)
            case 5:
                let crate = SK.box(0.55, 0.3, 0.4, SK.mat(SK.rgb(0x2E6FA8), roughness: 0.6),
                                   at: SCNVector3(CGFloat(p.0), y + 0.15, CGFloat(p.1)))
                crate.eulerAngles.y = CGFloat(rr.range(0, 6.3))
                world.addChildNode(crate)
            default:
                break
            }
        }
        // the salvage pile above the tide line: ship's gear dragged off the reef
        let pile = SCNNode()
        pile.position = SCNVector3(6, ground(6, 29), 29)
        pile.eulerAngles.y = 0.7
        pile.addChildNode(SK.box(1.5, 0.2, 1.1, SK.mat(SK.rgb(0xEDF0F2), roughness: 0.35), chamfer: 0.05, at: SCNVector3(0, 0.1, 0)))
        for i in 0..<3 {
            pile.addChildNode(SK.cylinder(0.3, 0.85, plastic, at: SCNVector3(-1.4 + CGFloat(i) * 0.75, 0.43, 0.9)))
        }
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.42, pipeRadius: 0.11))
        ring.geometry?.materials = [SK.mat(SK.rgb(0xE2662A), roughness: 0.7)]
        ring.eulerAngles.x = .pi / 2
        ring.position = SCNVector3(0.9, 0.09, -0.7)
        pile.addChildNode(ring)
        pile.addChildNode(SK.cylinder(0.06, 3.6, wood, at: SCNVector3(-1.6, 0.25, -0.9)))
        let sail = SK.box(2.0, 0.1, 1.6, SK.mat(SK.rgb(0xE8E4D8), roughness: 0.9, doubleSided: true), at: SCNVector3(2.0, 0.12, 0.3))
        sail.eulerAngles = SCNVector3(0.1, 0.4, 0.05)
        pile.addChildNode(sail)
        world.addChildNode(pile)
        // a debris trail from the wreck up the beach
        for i in 0..<14 {
            let t = CGFloat(i) / 14
            let x = -6 + t * 18 + CGFloat(rr.range(-3, 3))
            let z = 50 - t * 16 + CGFloat(rr.range(-2.5, 2.5))
            let y = ground(x, z)
            let n = i % 3 == 0
                ? SK.box(0.7, 0.06, 0.5, SK.mat(SK.rgb(0xEDF0F2), roughness: 0.35), chamfer: 0)
                : driftwood(CGFloat(rr.range(0.6, 1.8)), 0.09, seed: UInt64(1200 + i), mat: wood)
            n.position = SCNVector3(x, max(y, 0.06), z)
            n.eulerAngles.y = CGFloat(rr.range(0, 6.3))
            world.addChildNode(n)
        }
    }

    // MARK: Headland — birds, graves, lookout

    private func buildHeadland() {
        // a flock of boobies and terns circling the rock: a pivot that turns, one node per bird
        let pivot = SCNNode()
        pivot.position = SCNVector3(50, 15, -2)
        world.addChildNode(pivot)
        birdsPivot = pivot
        let bodyMat = SK.mat(SK.rgb(0xF2F2EE), roughness: 0.8)
        let wingMat = SK.mat(SK.rgb(0xE4E4DC), roughness: 0.85)
        for i in 0..<18 {
            let b = SCNNode()
            b.addChildNode(SK.sphere(0.12, bodyMat))
            b.childNodes[0].scale = SCNVector3(0.6, 0.6, 1.5)
            for s in [-1, 1] as [CGFloat] {
                let wing = SK.box(0.85, 0.03, 0.24, wingMat, chamfer: 0, at: SCNVector3(s * 0.45, 0.05, 0))
                wing.eulerAngles.z = s * 0.25
                b.addChildNode(wing)
            }
            let a = CGFloat(i) / 18 * 2 * .pi
            let r = 7 + CGFloat(i % 5) * 2.4
            b.position = SCNVector3(cos(a) * r, CGFloat(i % 4) * 2.2, sin(a) * r)
            b.eulerAngles.y = -a
            pivot.addChildNode(b)
            birds.append(b)
        }
        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 42)))

        // boulders and coral outcrops on the headland
        var rb = Rng(s: 0x120CC)
        let stoneMat = SK.noiseMat(SK.rgb(0x6E6A62), SK.rgb(0x3E3C38), scale: 4, seed: 13)
        for i in 0..<16 {
            let a = Float(i) * 0.9
            let r = CGFloat(rb.range(3, 15))
            let x = 52 + CGFloat(cosf(a)) * r, z = -2 + CGFloat(sinf(a)) * r * 0.8
            let y = height(Float(x), Float(z))
            guard y > 1.2 else { continue }
            let b = SK.rock(Float(rb.range(0.5, 1.6)), stoneMat, seed: UInt64(1700 + i), rings: 7, segments: 10, flatten: 0.7)
            b.position = SCNVector3(x, CGFloat(y) - 0.2, z)
            b.castsShadow = true
            world.addChildNode(b)
        }

        // a lookout sunshade on the headland (flag lookout)
        let shade = SCNNode()
        shade.position = SCNVector3(57.5, ground(57.5, 8.5), 8.5)
        shade.eulerAngles.y = -0.6
        for (x, z, h) in [(-0.9, -0.9, 2.0), (0.9, -0.9, 2.0), (-0.9, 0.9, 1.6), (0.9, 0.9, 1.6)] as [(CGFloat, CGFloat, CGFloat)] {
            shade.addChildNode(SK.cylinder(0.05, h, SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 31), at: SCNVector3(x, h / 2, z)))
        }
        let roof = SK.box(2.4, 0.06, 2.4, SK.noiseMat(SK.rgb(0x9C8A50), SK.rgb(0x63703A), scale: 7, seed: 33))
        roof.position = SCNVector3(0, 1.95, 0)
        roof.eulerAngles.x = -0.18
        roof.castsShadow = true
        shade.addChildNode(roof)
        shade.isHidden = true
        world.addChildNode(shade)
        lookout = shade

        // grave markers on the headland (after the burial event)
        let wood = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 91)
        for i in 0..<6 {
            let g = SCNNode()
            let x = 43 + CGFloat(i) * 2.1, z = 13 - CGFloat(i) * 0.8
            g.position = SCNVector3(x, ground(x, z), z)
            g.eulerAngles.y = 0.25
            g.addChildNode(SK.cylinder(0.05, 1.15, wood, at: SCNVector3(0, 0.58, 0)))
            let bar = SK.cylinder(0.04, 0.6, wood)
            bar.eulerAngles.z = .pi / 2
            bar.position = SCNVector3(0, 0.85, 0)
            g.addChildNode(bar)
            g.isHidden = true
            world.addChildNode(g)
            graves.append(g)
        }

        // the inland well (flag inland_well): a shallow pit with a shell scoop, mid-island
        let w = SCNNode()
        w.position = SCNVector3(4, ground(4, 2), 2)
        let rim = SK.node(SCNTorus(ringRadius: 0.6, pipeRadius: 0.16), SK.noiseMat(SK.rgb(0xD8D2C0), SK.rgb(0xA89E86), scale: 5, seed: 17))
        rim.eulerAngles.x = .pi / 2
        rim.position.y = 0.06
        w.addChildNode(rim)
        w.addChildNode(SK.cylinder(0.62, 0.22, SK.mat(SK.rgb(0x2E5A5E), roughness: 0.15), at: SCNVector3(0, 0.02, 0)))
        w.isHidden = true
        world.addChildNode(w)
        well = w
    }

    // MARK: Rescue boats and the search plane

    private func buildBoats() {
        // the search plane, high and far off (event plane)
        let p = SCNNode()
        let white = SK.mat(SK.rgb(0xF0F2F4), roughness: 0.4, metalness: 0.2)
        p.addChildNode(SK.node(SCNCapsule(capRadius: 0.7, height: 9), white))
        p.childNodes[0].eulerAngles.x = .pi / 2
        p.addChildNode(SK.box(14, 0.2, 1.7, white))
        p.addChildNode(SK.box(4.2, 0.15, 1.1, white, at: SCNVector3(0, 0, -4.0)))
        let orbit = SCNNode()
        orbit.position = SCNVector3(140, 300, -40)
        p.position = SCNVector3(180, 0, 0)
        orbit.addChildNode(p)
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)))
        orbit.isHidden = true
        world.addChildNode(orbit)
        plane = orbit

        // a rescue launch lying off the reef (events rescue_boat / final_boat / season_boat)
        let b = SCNNode()
        let hull = SK.mat(SK.rgb(0xF2F4F5), roughness: 0.35)
        let stripe = SK.mat(SK.rgb(0xD8452A), roughness: 0.5)
        let hb = SK.node(SCNCapsule(capRadius: 1.1, height: 8), hull)
        hb.eulerAngles.z = .pi / 2
        hb.scale = SCNVector3(1, 1, 0.72)
        hb.position.y = 0.4
        b.addChildNode(hb)
        b.addChildNode(SK.box(7.0, 0.3, 0.05, stripe, at: SCNVector3(0, -0.2, 1.5)))
        let wheel = SK.box(2.4, 1.3, 2.0, hull, chamfer: 0.2, at: SCNVector3(-0.6, 1.5, 0))
        b.addChildNode(wheel)
        b.addChildNode(SK.cylinder(0.06, 2.4, SK.mat(SK.rgb(0xB9BEC4), roughness: 0.3, metalness: 0.7), at: SCNVector3(-0.4, 3.0, 0)))
        b.position = SCNVector3(-56, 0.2, 150)
        b.eulerAngles.y = -0.5
        b.isHidden = true
        world.addChildNode(b)
        rescueBoat = b

        // the black poacher (event n_poachers): a dark steel hull with work lights
        let k = SCNNode()
        let dark = SK.mat(SK.rgb(0x23282C), roughness: 0.6, metalness: 0.3)
        let kb = SK.node(SCNCapsule(capRadius: 1.3, height: 11), dark)
        kb.eulerAngles.z = .pi / 2
        kb.scale = SCNVector3(1, 1, 0.7)
        kb.position.y = 0.5
        k.addChildNode(kb)
        k.addChildNode(SK.box(3.0, 1.6, 2.2, dark, chamfer: 0.15, at: SCNVector3(-3.0, 1.9, 0)))
        for i in 0..<3 {
            let lamp = SK.sphere(0.13, SK.mat(.black, roughness: 0.4, emission: SK.rgb(0xFFE8B0)),
                                 at: SCNVector3(-4.0 + CGFloat(i) * 4.0, 1.4, 0.8))
            k.addChildNode(lamp)
        }
        k.position = SCNVector3(-36, 0.2, 128)
        k.eulerAngles.y = 0.9
        k.isHidden = true
        world.addChildNode(k)
        poacherBoat = k
    }

    // MARK: The second camp (split / discord)

    private func buildSouthCamp() {
        let c = SCNNode()
        c.position = SCNVector3(-44, ground(-44, 12), 12)
        c.eulerAngles.y = 0.5
        let poleMat = SK.noiseMat(SK.rgb(0xB6A88C), SK.rgb(0x7E7259), scale: 5, seed: 31)
        let thatch = SK.noiseMat(SK.rgb(0x9C8A50), SK.rgb(0x63703A), scale: 7, roughness: 0.9, seed: 33)
        // a rougher shelter: four sticks and a sheet of fronds
        for (x, z) in [(-1.2, -1.0), (1.2, -1.0), (-1.2, 1.0), (1.2, 1.0)] as [(CGFloat, CGFloat)] {
            c.addChildNode(SK.cylinder(0.06, 1.7, poleMat, at: SCNVector3(x, 0.85, z)))
        }
        let roof = SK.box(3.0, 0.07, 2.6, thatch, chamfer: 0.04, at: SCNVector3(0, 1.8, 0))
        roof.eulerAngles.x = -0.2
        roof.castsShadow = true
        c.addChildNode(roof)
        // their own fire pit, well away from the north camp
        let pit = SCNNode()
        for i in 0..<7 {
            let a = CGFloat(i) / 7 * 2 * .pi
            let stone = SK.rock(0.14, SK.noiseMat(SK.rgb(0x6B6B6B), SK.rgb(0x3E3E40), scale: 3, seed: 11), seed: UInt64(30 + i))
            stone.position = SCNVector3(cos(a) * 0.6, 0.05, sin(a) * 0.6)
            pit.addChildNode(stone)
        }
        let ember = SK.cylinder(0.34, 0.05, SK.mat(.black, roughness: 1, emission: SK.rgb(0x000000)), at: SCNVector3(0, 0.03, 0))
        ember.name = "embers"
        pit.addChildNode(ember)
        let light = SK.fireLight(intensity: 700, color: SK.rgb(0xFF9442), range: 14)
        light.position.y = 0.6
        light.isHidden = true
        pit.addChildNode(light)
        southFire = light
        pit.position = SCNVector3(1.6, 0, 2.6)
        c.addChildNode(pit)
        c.isHidden = true
        world.addChildNode(c)
        southCamp = c
    }

    /// Tropical rain: the framework's downpour is heavy enough to read as white scratches,
    /// especially after dark, so the emitter is thinned and dimmed here.
    private var rainBase: [ObjectIdentifier: (CGFloat, NSColor, CGFloat)] = [:]

    override func updateWeather(_ s: SceneState) {
        super.updateWeather(s)
        let night = CGFloat(darkness)
        if weatherNode.childNodes.isEmpty { rainBase.removeAll() }
        for n in weatherNode.childNodes {
            for ps in n.particleSystems ?? [] {
                let id = ObjectIdentifier(ps)
                if rainBase[id] == nil { rainBase[id] = (ps.birthRate, ps.particleColor, ps.particleSize) }
                guard let b = rainBase[id] else { continue }
                ps.birthRate = b.0 * 0.55
                ps.particleSize = b.2 * 0.85
                ps.particleColor = b.1.withAlphaComponent(b.1.alphaComponent * (1 - 0.62 * night))
            }
        }
    }

    // MARK: - Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        let storm = s.precip >= 1.5 || s.wind >= 45

        // — sea: colour and wave height follow the weather, calmer and clearer in the lagoon
        if let m = sea?.geometry?.firstMaterial {
            let amp: Float = storm ? 0.55 : (s.wind > 25 ? 0.30 : 0.16)
            m.setValue(NSNumber(value: amp), forKey: "amplitude")
            m.setValue(NSNumber(value: storm ? 0.9 : 0.55), forKey: "choppiness")
            // the vertex colours carry the depth gradient; the diffuse tints the whole sheet
            m.diffuse.contents = storm ? SK.rgb(0x8E9AA0) : (s.isNight ? SK.rgb(0x4A5A6E) : NSColor.white)
            m.roughness.contents = storm ? 0.34 : 0.11
        }

        // — palms: how many are still standing (raft and cistern eat trees)
        let palmCount = Int((s.v("palms", 580) / 700 * Double(palms.count)).rounded())
        for (i, p) in palms.enumerated() { p.isHidden = i >= palmCount }

        // — shelter: roof panels and the windbreak fence grow with the shelter's integrity
        let shelter = max(0, min(1, s.shelter / 100))
        for (i, r) in hutRoof.enumerated() { r.isHidden = Double(i) > shelter * 3.2 + 0.55 }
        for r in hutSides { r.isHidden = shelter < 0.55 }
        for (i, f) in fence.enumerated() { f.isHidden = Double(i) >= shelter * 6.6 - 0.4 }

        // — water stores: barrels and cans only as long as there is water and capacity
        let water = s.res("water"), storage = s.v("storage", 60)
        let storeLevel = min(1.0, (water + storage / 40) / 60)
        for (i, n) in stores.enumerated() { n.isHidden = Double(i) > storeLevel * Double(stores.count) + 0.4 }

        // — projects
        let catcherP = s.project("catcher")
        catcher?.isHidden = catcherP < 0.35
        catcherLoose?.isHidden = catcherP >= 0.35
        let cisternP = s.project("cistern")
        cisternLog?.isHidden = !(cisternP > 0.02 && cisternP < 1)
        cistern?.isHidden = cisternP < 1
        let beaconP = s.project("beacon")
        beacon?.isHidden = beaconP < 0.1
        beacon?.scale = SCNVector3(1, CGFloat(0.45 + 0.55 * beaconP), 1)
        let beaconLit = beaconP >= 1 && s.fireLit && s.v("signal", 5) >= 40
        beaconFlame?.isHidden = !beaconLit
        let bancaP = s.project("banca")
        banca?.isHidden = bancaP < 1 || s.has("banca_sailed")
        bancaWreck?.isHidden = !(bancaP < 1 && !s.has("banca_sailed"))

        // — rule plank: days are scratched into it from the first rules on
        let hasRule = s.has("tongan_rules") || s.has("merit_rule") || s.has("captain_rule") || s.has("fire_rule")
        rulePlank?.isHidden = !(hasRule || s.round >= 4)
        for (i, m) in tallyMarks.enumerated() { m.isHidden = i >= s.round }
        if let board = rulePlank?.childNode(withName: "board", recursively: false) { board.isHidden = false }
        distillery?.isHidden = !s.has("boil_water")

        // — raft: logs, lashings, mast, then the finished raft; out to sea once sailed
        let raftP = max(s.v("raft") / 100, s.has("raft_built") ? 1 : 0)
        raftLogs?.isHidden = raftP < 0.05
        raftLash?.isHidden = raftP < 0.35
        raftMast?.isHidden = raftP < 0.6
        raft?.isHidden = raftP < 0.98
        let sailed = s.has("raft_sailed")
        if sailed {
            raftLogs?.isHidden = true; raftLash?.isHidden = true; raftMast?.isHidden = true; raft?.isHidden = true
        }
        raftAtSea?.isHidden = !(sailed && !s.has("raft_success"))
        bancaAtSea?.isHidden = true

        // — signal: more coral letters, bigger flags
        let signal = s.v("signal", 5)
        let letterStage = signal < 18 ? 0 : (signal < 34 ? 1 : (signal < 52 ? 2 : 3))
        for (i, letter) in sosLetters.enumerated() {
            for st in letter { st.isHidden = i >= letterStage }
        }
        for (i, c) in flagCloths.enumerated() { c.isHidden = signal < Double(22 + i * 16) }

        // — flotsam state
        wreck?.isHidden = s.has("wreck_gone")
        wreckSunk?.isHidden = !s.has("wreck_gone")
        well?.isHidden = !s.has("inland_well")
        lookout?.isHidden = !s.has("lookout")

        // — birds: the flock thins out when they are hunted, and roosts at night
        let birdCount = Int((s.v("birds", 80) / 100 * Double(birds.count)).rounded())
        for (i, b) in birds.enumerated() { b.isHidden = i >= birdCount }
        birdsPivot?.isHidden = s.isNight || birdCount == 0

        // — the split: a second fire and shelter at the south end
        let split = s.has("split") || s.v("discord") >= 62
        southCamp?.isHidden = !split
        southFire?.isHidden = !(split && s.isNight)
        if let e = southCamp?.childNode(withName: "embers", recursively: true) {
            e.geometry?.firstMaterial?.emission.contents = (split && s.fireLit) ? SK.rgb(0xFF6A1A) : NSColor.black
            e.geometry?.firstMaterial?.emission.intensity = (split && s.fireLit) ? 1.4 : 0
        }

        // — boats and aircraft
        let planeNow = s.now("plane")
        plane?.isHidden = !planeNow
        let boatNow = s.now("rescue_boat") || s.now("final_boat") || s.has("season_boat") || s.has("rescued")
        rescueBoat?.isHidden = !boatNow
        let poacherNow = s.now("n_poachers") || s.now("n_poacher_seat")
        poacherBoat?.isHidden = !poacherNow

        // — the dead: laid out in the shade until they are buried on the headland
        let buried = s.happened("burial")
        for (i, g) in graves.enumerated() { g.isHidden = !(buried && i < s.dead) }
        showBodies(buried ? 0 : s.dead,
                   spots: Spot.line(from: SCNVector3(46, 0, 20), to: SCNVector3(51, 0, 24), count: 8, facing: 1.1, y: ground))

        showPeople(s, spots: spots(for: s, storm: storm))
    }

    // MARK: - People

    private func spots(for s: SceneState, storm: Bool) -> [Spot] {
        if storm {
            // everyone crammed into the lee of the lean-to and the rock behind it
            let base: [(CGFloat, CGFloat)] = [(40.2, 9.6), (41.0, 12.2), (42.2, 9.4), (43.0, 12.4),
                                              (44.0, 9.8), (44.6, 12.6), (38.8, 11.0), (42.0, 14.0),
                                              (39.6, 13.6), (45.4, 11.0), (41.4, 7.8), (43.6, 7.2)]
            return base.map { Spot($0.0, ground($0.0, $0.1) + 0.05, $0.1, facing: 2.6, pose: .huddled) }
        }
        if s.isNight || s.fireLit {
            var list = Spot.ring(SCNVector3(34, 0, 17), radius: 2.3, count: 11, start: 0.5, y: ground)
            if s.has("lookout") {
                // someone is up on the headland with the beacon: the last place in the list
                list[list.count - 1] = Spot(54, ground(54, 6), 6, facing: -1.4)
            }
            return list
        }
        // daytime: work parties on the reef, in the camp and up on the headland
        let day: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (34.8, 15.8, 2.4, 0),      // by the fire
            (36.6, 12.4, 2.0, 0),      // water stores
            (41.6, 13.6, -0.7, 0),     // at the lean-to
            (29.6, 12.6, 0.5, 0),      // rigging the rain catcher
            (27.0, 34.0, 2.9, 0),      // fishing on the reef flat
            (20.0, 37.0, 2.6, 0),      // gleaning the reef
            (44.6, 17.4, 1.2, 0),      // the drying rack
            (38.6, 20.0, 1.9, 0),      // hauling driftwood up the beach
            (52.0, 2.0, -1.2, 0),      // on the headland by the beacon
            (-16.0, 24.0, 1.5, 0),     // down the beach to the south
            (-38.0, 16.0, -0.4, 0),    // the far side of the island
            (10.0, 30.0, 0.6, 0)       // wading in the shallows
        ]
        return day.map { Spot($0.0, wetGround($0.0, $0.1), $0.1, facing: $0.2) }
    }
}
