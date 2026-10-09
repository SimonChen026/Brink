import SceneKit
import AppKit

/// 沙海 · 罗布泊迷途 — two broken-down 4×4s on the Lop Nur salt pan, 45 °C at noon.
///
/// Layout (metres, wind from the north-east): the camp sits on a flat salt pan around (2, 4);
/// the Land Cruiser that bogged down in soft earth stands at the camp with the shade sheet
/// rigged off its roof rack; the Prado that rolled into a yardang gully lies on its side in the
/// trench at (−14, −5); the yardang field (parallel wind-cut ridges with corridors between them)
/// runs north-east; the convoy's ruts come in from the south-east; the salt-crust SOS is written
/// north of the camp; the mountains stand on the far horizon.
///
/// State shown: water left (res.water → standing bottles and empties), the SOS (var.signal),
/// the solar stills (var.stills), the survey stakes that mark the way out (var.route), the Prado
/// on its side / half-lifted / back on its wheels / repaired (projects flip_car, fix_car), the
/// Land Cruiser stripped for parts (flag.lc_ruined), the bitter well (flag.well_found), the
/// lookout on the highest yardang (flag.sms_sent), 葛长贵's tarpaulin pickup while he is at camp,
/// the search convoy and the search plane, someone who walked out (flag.trek_started), the dead
/// under tarpaulins, and the heat — negative exposure, a sun below 1, mirage bands and blowing
/// sand.
final class SandseaScene: ScenarioScene {

    // MARK: - Layout constants

    /// Prevailing wind axis (unit vector in XZ). The yardang ridges are cut along it.
    private let windX: Float = 0.82
    private let windZ: Float = -0.57
    /// The camp clearing stays flat and free of ridges.
    private let campX: Float = 2
    private let campZ: Float = 4
    /// The track the convoy came in on (from the south-east).
    private let trackX: Float = 0.94
    private let trackZ: Float = 0.34
    /// The gully the Prado rolled into: a broad trench along the wind axis.
    private let gullyX: Float = -20
    private let gullyZ: Float = -8

    private let noise = SK.Noise(seed: 7117)

    // MARK: - Nodes that follow the game state

    private var bottles: [SCNNode] = []          // drinking water still in the crate
    private var empties: [SCNNode] = []          // finished bottles in the sand
    private var sosMarks: [SCNNode] = []         // the SOS laid out on the salt crust
    private var stillPits: [SCNNode] = []        // solar stills (var.stills)
    private var stakes: [SCNNode] = []           // oil-survey stakes toward the lorry road
    private var trackRutsFaded: SCNNode?         // the old ruts lose themselves in the pan
    private var rutsOut: SCNNode?                // fresh ruts leaving for the north-east
    private var pradoSide: SCNNode?
    private var pradoUpright: SCNNode?
    private var pradoWheels: [SCNNode] = []
    private var pradoLights: [SCNNode] = []
    private var hood: SCNNode?
    private var jack: SCNNode?
    private var parts: SCNNode?
    private var lcWheels: [SCNNode] = []
    private var shadeSheet: SCNNode?
    private var shadeUpper: SCNNode?
    private var shadePole: SCNNode?
    private var shadeRag: SCNNode?
    private var well: SCNNode?
    private var cart: SCNNode?
    private var lookout: SCNNode?
    private var convoy: SCNNode?
    private var plane: SCNNode?
    private var pickup: SCNNode?
    private var herd: SCNNode?
    private var marcher: SCNNode?
    private var mirage: [SCNNode] = []
    private var haze: [SCNNode] = []
    private let moonFill = SCNNode()
    private var dustNode: SCNNode?
    private var sand: SCNParticleSystem?
    private var sandOn = false

    required init() {
        super.init()
        skyStyle = .desert
        sunPeak = 56                 // ~40°N in mid-July, and merciless at noon
        sunAzimuth = 305
        exposure = -1.45             // a white salt pan at 45 °C is the brightest thing there is
        sunScale = 0.95
        iblScale = 0.42
        hazeColor = SK.rgb(0xEADCBF)
        stormColor = SK.rgb(0xB98F5C)
        nightColor = SK.rgb(0x0A0E16)
        clearVisibility = 1300
        dustColor = SK.rgb(0xDCBE93)
        precipKind = .auto           // the rare rain; blowing sand is this scene's own business
        weatherArea = 100
        weatherCenter = SCNVector3(0, 18, 0)
        cameraTarget = SCNVector3(-3.0, 2.4, 2)
        cameraDistance = 23
        cameraYaw = -6
        cameraPitch = 12
        cameraFOV = 45
        minPitch = 2
    }

    // MARK: - Terrain

    /// Height of the salt pan / yardang surface at (x, z).
    private func height(_ x: Float, _ z: Float) -> Float {
        let a = x * windX + z * windZ                 // along a ridge (north-east)
        let c = -x * windZ + z * windX                // across the ridges
        let r = sqrt(x * x + z * z)

        var h: Float = 0

        // 1 — the clearing and the track in stay flat, so the camp reads at a glance
        let dcx = x - campX, dcz = z - campZ
        let clearing = SK.smoothstep(24, 42, sqrt(dcx * dcx + dcz * dcz))
        let toTrack = dcx * -trackZ + dcz * trackX                 // distance off the track line
        let alongTrack = dcx * trackX + dcz * trackZ               // + on the way they came
        let onTrack = (1 - SK.smoothstep(9, 24, abs(toTrack))) * SK.smoothstep(-30, -4, alongTrack)
        let open = min(clearing, 1 - onTrack)

        // 2 — the gully: a trench along the wind that the Prado rolled into
        h -= trench(x, z) * 2.7

        // 3 — the yardang field: long ridges, flat crests, corridors between them.
        //     Only beyond the clearing; the near ridges are built as real meshes.
        let mask = max(SK.smoothstep(26, 44, r), 1 - open)
        let wander = (noise.fbm(a / 46, 5.1, octaves: 2) - 0.5) * 0.3
            + (noise.value(a / 17, 2.7) - 0.5) * 0.14
        let phase = c / 28 + wander + (noise.value(a / 11, 3.1) - 0.5) * 0.05
        let crest = abs(phase - phase.rounded()) * 2               // 0 on a crest, 1 in a corridor
        // flat crest, a hard break and steep flanks: what the sand leaves behind
        let flank = max(0, min(1, (crest - 0.22) / 0.34))
        let profile = pow(1 - flank, 0.42) + 0.10 * (1 - SK.smoothstep(0.72, 1.0, crest))
        let along = noise.fbm(a / 88, 21.7, octaves: 3)
        let jags = 0.85 + 0.28 * noise.value(a / 26, 9.1)
        // a ridge dies out and another one starts further downwind, in separate bluffs
        let life = SK.smoothstep(0.1, 0.4, along) * (1 - SK.smoothstep(0.75, 0.96, along))
        let breaks = 0.3 + 0.7 * SK.smoothstep(0.34, 0.5, noise.fbm(a / 30 + 13, 3.3, octaves: 2))
        h += profile * (6 + 8 * along) * jags * life * breaks * mask * open
        h += profile * 1.6 * mask * open
        // fluting: grooves cut down the walls by the sand
        let fluteA = SK.smoothstep(0.46, 0.94, crest) * (1 - SK.smoothstep(0.97, 1.0, crest))
        h += (noise.value(a / 28, c / 15) - 0.5) * 2.2 * fluteA * mask * open
        h += (noise.value(a / 18, c / 26) - 0.5) * 2.8 * fluteA * mask * open

        // 4 — the pan itself: a shallow, almost level basin of cracked salt
        h += (noise.fbm(x / 27, z / 27, octaves: 2) - 0.5) * 0.9
        h += (noise.fbm(x / 90 + 4, z / 90, octaves: 3) - 0.5) * 1.6 * (1 - mask)
        h -= 0.9 * (1 - mask) * open * open

        // 5 — the ranges on the far horizon, hazed into silhouettes
        let far = SK.smoothstep(260, 440, r)
        let towardRoad = (x * windX + z * windZ) / max(1, r)        // 1 toward the north-east
        let gap = 0.4 + 0.6 * (1 - 0.75 * SK.smoothstep(0.55, 0.95, towardRoad))
        h += far * gap * (16 + noise.ridged(x / 130 + 9, z / 130, octaves: 4) * 74
                             + noise.ridged(x / 44 + 21, z / 44, octaves: 2) * 24)
        return h
    }

    /// Ground height, for placing anything on the surface.
    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(height(Float(x), Float(z))) }

    /// 1 in the bottom of the gully, 0 on the open pan.
    private func trench(_ x: Float, _ z: Float) -> Float {
        let gx = x - gullyX, gz = z - gullyZ
        let ga = gx * windX + gz * windZ
        let gc = -gx * windZ + gz * windX
        return (1 - SK.smoothstep(5.5, 11.0, abs(gc))) * (1 - SK.smoothstep(34, 58, abs(ga)))
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        cameraNode.camera?.saturation = 0.95
        cameraNode.camera?.contrast = 0.2
        // a cold moonlit fill so the pan still reads after dark
        let moon = SCNLight()
        moon.type = .directional
        moon.castsShadow = false
        moon.color = SK.rgb(0x9FB6E2)
        moon.intensity = 0
        moonFill.light = moon
        moonFill.eulerAngles = SCNVector3(-0.7, 2.1, 0)
        world.addChildNode(moonFill)
        buildGround()
        buildYardangs()
        buildGully()
        buildRuts()
        buildLandCruiser()
        buildPrado()
        buildShade()
        buildWaterPoint()
        buildStills()
        buildSOS()
        buildStakes()
        buildBones()
        buildMilestone()
        buildCampClutter()
        buildHeat()
        buildSand()
        addFire(at: SCNVector3(5.6, ground(5.6, 1.2), 1.2), scale: 0.9)
        buildFireRing()
    }

    private func buildGround() {
        // white salt on the flat pan, ochre clay on the ridges, blue-grey ranges on the horizon
        let mat = SK.terrainMaterial(flat: SK.rgb(0xF3EAD3), steep: SK.rgb(0x9A7440),
                                     from: 0.26, to: 0.46, grain: 0.16, noiseScale: 0.05, roughness: 0.85)
        SK.addGrain(mat, scale: 20, strength: 1.2, intensity: 0.1, seed: 9)
        let terrain = SK.terrain(size: 900, segments: 300, height: height, color: { x, y, z, slope in
            let pan = 1 - SK.smoothstep(0.7, 4.0, y)                     // 1 on the salt, 0 on a ridge
            let mottle = 0.90 + 0.20 * self.noise.fbm(x / 24, z / 24, octaves: 3)
            let broad = 0.90 + 0.20 * self.noise.fbm(x / 95 + 3, z / 95, octaves: 3)
            let gravel = SK.smoothstep(0.44, 0.6, self.noise.fbm(x / 55 + 7, z / 55, octaves: 3))
            let inGully = self.trench(x, z)
            let salt = SIMD3<Float>(1.02, 0.96, 0.85)
            let clay = SIMD3<Float>(0.60, 0.41, 0.21)
            var c = SK.mix(clay, salt, pan) * mottle * broad
            c *= 1 - 0.26 * gravel * pan
            c *= 1 - 0.22 * inGully                      // drifted sand, in the shade of the walls
            c = SK.mix(c, SIMD3<Float>(0.72, 0.62, 0.44), 0.5 * inGully)
            let far = SK.smoothstep(250, 430, sqrt(x * x + z * z))
            c = SK.mix(c, SIMD3<Float>(0.62, 0.58, 0.55), far)
            return c
        }, material: mat, uvRepeat: 220)
        terrain.castsShadow = false
        world.addChildNode(terrain)

        // gravel and crust fragments scattered over the pan
        let stone = SK.noiseMat(SK.rgb(0x7C6E58), SK.rgb(0x4A4034), scale: 4, seed: 15)
        for i in 0..<90 {
            let a = Float(noise.value(Float(i) * 1.7, 2.3)) * 2 * .pi
            let d = 6 + Float(noise.value(Float(i) * 3.1, 8.1)) * 44
            let x = campX + sin(a) * d, z = campZ + cos(a) * d
            let pebble = SK.sphere(CGFloat(0.07 + noise.value(Float(i) * 5.3, 1.1) * 0.16), stone, segments: 6)
            pebble.scale = SCNVector3(1, 0.45, 1)
            pebble.position = SCNVector3(CGFloat(x), ground(CGFloat(x), CGFloat(z)) + 0.02, CGFloat(z))
            pebble.castsShadow = false
            world.addChildNode(pebble)
        }
        world.addChildNode(crackNet())
    }

    /// The cracked salt crust: irregular polygons of shallow fissures, drawn as one thin mesh.
    private func crackNet() -> SCNNode {
        var pts: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        func strip(_ p0: (Float, Float), _ p1: (Float, Float), _ width: Float) {
            let dx = p1.0 - p0.0, dz = p1.1 - p0.1
            let l = max(0.001, sqrt(dx * dx + dz * dz))
            let nx = -dz / l * width / 2, nz = dx / l * width / 2
            let base = UInt32(pts.count)
            for p in [(p0.0 + nx, p0.1 + nz), (p1.0 + nx, p1.1 + nz), (p0.0 - nx, p0.1 - nz), (p1.0 - nx, p1.1 - nz)] {
                pts.append(SIMD3(p.0, height(p.0, p.1) + 0.006, p.1))
            }
            idx += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
        }
        for poly in 0..<95 {
            let a = Float(noise.value(Float(poly) * 2.7, 5.5)) * 2 * .pi
            let d = 4 + Float(noise.value(Float(poly) * 4.1, 11.3)) * 34
            let cx = campX + sin(a) * d, cz = campZ + cos(a) * d
            let n = 5 + poly % 3
            var ring: [(Float, Float)] = []
            for k in 0..<n {
                let ang = Float(k) / Float(n) * 2 * .pi + noise.value(Float(poly), Float(k)) * 0.6
                let rad = 0.5 + noise.value(Float(poly) * 3 + Float(k), 7.7) * 1.5
                ring.append((cx + sin(ang) * rad, cz + cos(ang) * rad))
            }
            for k in 0..<n { strip(ring[k], ring[(k + 1) % n], 0.05) }
        }
        let m = SK.mat(SK.rgb(0x8E8064), roughness: 1)
        let n = SK.node(SK.mesh(pts, idx), m)
        n.castsShadow = false
        return n
    }

    // MARK: Yardangs

    /// A wind-cut yardang: a long wall with a blunt, undercut windward nose, a flat crest,
    /// steep fluted flanks and a lower bench part-way down. Long axis along local +x, origin
    /// on the ground.
    private func yardang(length: Float, width: Float, height hgt: Float, seed: UInt64) -> SCNNode {
        let n = SK.Noise(seed: seed)
        let nu = 44, nv = 18
        var pts: [SIMD3<Float>] = [], cols: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0...nu {
            let u = Float(i) / Float(nu)
            let nose = SK.smoothstep(0, 0.06, u)                      // a blunt, undercut face to windward
            let lee = 1 - SK.smoothstep(0.84, 1.0, u)                 // tapering lee end
            let body = nose * lee
            let w = width * (0.66 + 0.34 * nose) * (0.86 + 0.14 * lee)
            let wander = (n.fbm(u * 2.6, 7.7, octaves: 2) - 0.5) * width * 0.22
            let flute = (n.value(u * 31, 2.2) - 0.5) * 0.16 + (n.value(u * 9.5, 5.5) - 0.5) * 0.2
            for j in 0...nv {
                let v = Float(j) / Float(nv) * 2 - 1
                let flat = 1 - SK.smoothstep(0.40, 0.97, abs(v))       // flat crest, steep flank
                let bench = 0.20 * SK.smoothstep(0.40, 0.60, abs(v)) * (1 - SK.smoothstep(0.62, 0.88, abs(v)))
                var y = hgt * body * (flat + bench)
                y += hgt * body * flute * flat * 0.45
                y += (n.fbm(u * 7, v * 5 + 3, octaves: 2) - 0.5) * hgt * 0.07
                let z = v * w * 0.5 * (1 + flute * 0.3) + wander
                pts.append(SIMD3((u - 0.5) * length, max(0, y), z))
                let t = min(1, max(0, y / max(0.001, hgt)))
                let c = SK.mix(SIMD3<Float>(1.0, 0.97, 0.9), SIMD3<Float>(0.58, 0.45, 0.30), t)
                cols.append(c * (0.88 + 0.24 * n.value(u * 52, v * 3)))
            }
        }
        for i in 0..<nu {
            for j in 0..<nv {
                let a = UInt32(i * (nv + 1) + j), b = a + 1, c = a + UInt32(nv + 1), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let m = SK.noiseMat(SK.rgb(0xEFE6D0), SK.rgb(0xB49A70), scale: 9, roughness: 0.92, seed: seed)
        let node = SK.node(SK.mesh(pts, idx, colors: cols, uvs: nil), m)
        node.castsShadow = true
        return node
    }

    @discardableResult
    private func addYardang(_ x: CGFloat, _ z: CGFloat, length: CGFloat, width: CGFloat,
                            height hgt: CGFloat, seed: UInt64, turn: CGFloat = 0) -> SCNNode {
        let n = yardang(length: Float(length), width: Float(width), height: Float(hgt), seed: seed)
        let base = CGFloat(atan2(-windZ, windX))
        n.position = SCNVector3(x, ground(x, z) - 0.9, z)
        n.eulerAngles = SCNVector3(0, base + turn, 0)
        world.addChildNode(n)
        return n
    }

    /// The near walls, placed by hand: long ridges that frame the camp, out where the
    /// heightfield has not taken over yet.
    private func buildYardangs() {
        addYardang(-31, -17, length: 40, width: 16, height: 8.5, seed: 101)
        addYardang(24, 22, length: 34, width: 15, height: 6.5, seed: 102, turn: 0.05)
        addYardang(30, -30, length: 40, width: 17, height: 9.5, seed: 103, turn: -0.05)
    }

    /// The lookout: a mirror and a rag tied to a stake on the highest yardang (flag.sms_sent).
    private func buildLookout() {
        let n = SCNNode()
        let top = ground(-16, -40) + 15.5 - 0.7 - 0.5
        n.position = SCNVector3(-16, top, -40)
        let stick = SK.cylinder(0.05, 2.4, SK.mat(SK.rgb(0x4A3A28), roughness: 0.9), at: SCNVector3(0, 1.2, 0))
        n.addChildNode(stick)
        let mirror = SK.box(0.5, 0.5, 0.03, SK.mat(SK.rgb(0xF2F6FA), roughness: 0.08, metalness: 0.9), chamfer: 0.01,
                            at: SCNVector3(0.28, 2.0, 0))
        mirror.eulerAngles = SCNVector3(0.3, 0.5, 0.2)
        n.addChildNode(mirror)
        let rag = SK.box(0.5, 0.7, 0.02, SK.mat(SK.rgb(0xC8402F), roughness: 0.85, doubleSided: true), at: SCNVector3(-0.3, 1.9, 0))
        n.addChildNode(rag)
        n.isHidden = true
        world.addChildNode(n)
        lookout = n
    }

    // MARK: The gully

    /// The trench floor, drifted sand down the middle and the dug ramp (once they got the Prado up).
    private func buildGully() {
        // a sand fan and a few fallen blocks on the gully floor
        let sand = SK.noiseMat(SK.rgb(0xCBB28A), SK.rgb(0xA98D68), scale: 5, seed: 33)
        for i in 0..<10 {
            let t = -30 + Float(i) * 7
            let x = gullyX + t * windX, z = gullyZ + t * windZ
            let b = SK.rock(Float(0.5 + noise.value(Float(i) * 3.3, 4.4) * 0.9), sand, seed: UInt64(200 + i))
            b.position = SCNVector3(CGFloat(x), ground(CGFloat(x), CGFloat(z)) + 0.15, CGFloat(z))
            world.addChildNode(b)
        }
    }

    // MARK: Ruts and footprints

    /// Shallow grooves on the ground along a path.
    private func grooveMesh(_ path: [(CGFloat, CGFloat)], width: CGFloat, offset: CGFloat, step: CGFloat) -> SCNGeometry? {
        var pts: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        var t: CGFloat = 0
        while t < 1 {
            let t1 = min(1, t + step / max(1, pathLength(path)))
            let p0 = pointOn(path, t), p1 = pointOn(path, t1)
            let dx = p1.0 - p0.0, dz = p1.1 - p0.1
            let l = max(0.001, sqrt(dx * dx + dz * dz))
            let nx = -dz / l * width / 2, nz = dx / l * width / 2
            let ox = -dz / l * offset, oz = dx / l * offset
            for p in [(p0.0 + nx + ox, p0.1 + nz + oz), (p1.0 + nx + ox, p1.1 + nz + oz),
                      (p0.0 - nx + ox, p0.1 - nz + oz), (p1.0 - nx + ox, p1.1 - nz + oz)] {
                pts.append(SIMD3(Float(p.0), height(Float(p.0), Float(p.1)) + 0.035, Float(p.1)))
            }
            let base = UInt32(pts.count - 4)
            idx += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
            t = t1
        }
        return pts.isEmpty ? nil : SK.mesh(pts, idx)
    }

    private func pathLength(_ p: [(CGFloat, CGFloat)]) -> CGFloat {
        var s: CGFloat = 0
        for i in 1..<max(1, p.count) { s += hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1) }
        return max(1, s)
    }

    private func pointOn(_ p: [(CGFloat, CGFloat)], _ t: CGFloat) -> (CGFloat, CGFloat) {
        guard p.count > 1 else { return p.first ?? (0, 0) }
        let total = pathLength(p)
        var want = t * total
        for i in 1..<p.count {
            let d = hypot(p[i].0 - p[i - 1].0, p[i].1 - p[i - 1].1)
            if want <= d {
                let k = d <= 0.0001 ? 0 : want / d
                return (p[i - 1].0 + (p[i].0 - p[i - 1].0) * k, p[i - 1].1 + (p[i].1 - p[i - 1].1) * k)
            }
            want -= d
        }
        return p[p.count - 1]
    }

    private func buildRuts() {
        // the convoy came in from the south-east, weaving a little over the pan
        let track: [(CGFloat, CGFloat)] = [(148, 55), (96, 38), (60, 25), (34, 17), (20, 12), (10, 8)]
        let m = SK.mat(SK.rgb(0x8A7659), roughness: 1)
        let n = SCNNode()
        if let g = grooveMesh(track, width: 0.45, offset: 0.95, step: 2.4) { n.addChildNode(SK.node(g, m)) }
        if let g = grooveMesh(track, width: 0.45, offset: -0.95, step: 2.4) { n.addChildNode(SK.node(g, m)) }
        n.castsShadow = false
        world.addChildNode(n)
        trackRutsFaded = n

        // where the Land Cruiser dug itself in: chewed-up ground behind the rear wheels
        let spin: [(CGFloat, CGFloat)] = [(-1.5, 8.2), (-1.2, 6.6), (-0.2, 5.8), (0.6, 6.4), (-1.0, 7.4)]
        let s = SCNNode()
        let sm = SK.mat(SK.rgb(0x9A8464), roughness: 1)
        for k in [0.3, 0.85, 1.3] as [CGFloat] {
            if let g = grooveMesh(spin, width: 0.5 * k, offset: 0.2 + k, step: 1.2) { s.addChildNode(SK.node(g, sm)) }
        }
        s.castsShadow = false
        world.addChildNode(s)

        // fresh ruts out of the gully toward the lorry road (drive_out / trek)
        let out: [(CGFloat, CGFloat)] = [(-14, -12), (10, -26), (44, -46), (86, -72), (132, -100)]
        let o = SCNNode()
        if let g = grooveMesh(out, width: 0.5, offset: 1.0, step: 2.6) { o.addChildNode(SK.node(g, m)) }
        if let g = grooveMesh(out, width: 0.5, offset: -1.0, step: 2.6) { o.addChildNode(SK.node(g, m)) }
        o.castsShadow = false
        o.isHidden = true
        world.addChildNode(o)
        rutsOut = o

        // footprints of whoever walked out toward the road
        let walk: [(CGFloat, CGFloat)] = [(3, 2), (16, -6), (34, -18), (56, -34), (84, -52), (112, -70)]
        let wnode = SCNNode()
        let foot = SK.mat(SK.rgb(0x8D7A5D), roughness: 1)
        for i in 0..<60 {
            let p = pointOn(walk, CGFloat(i) / 60)
            let q = pointOn(walk, min(1, CGFloat(i) / 60 + 0.004))
            let f = SK.box(0.14, 0.03, 0.34, foot, chamfer: 0.01)
            f.position = SCNVector3(p.0, ground(p.0, p.1) + 0.02, p.1)
            f.eulerAngles.y = atan2(q.0 - p.0, q.1 - p.1) + (i % 2 == 0 ? 0.25 : -0.25)
            f.castsShadow = false
            wnode.addChildNode(f)
        }
        wnode.isHidden = true
        world.addChildNode(wnode)
        marcher = wnode
    }

    // MARK: The vehicles

    private func wheel(_ r: CGFloat, _ m: SCNMaterial, _ rims: SCNMaterial) -> SCNNode {
        let n = SCNNode()
        let tire = SK.node(SCNTorus(ringRadius: r * 0.72, pipeRadius: r * 0.3), m)
        n.addChildNode(tire)
        let hub = SK.cylinder(r * 0.45, 0.16, rims)
        hub.eulerAngles.z = .pi / 2
        n.addChildNode(hub)
        return n
    }

    /// 陆地巡洋舰 — bogged down in soft earth, rear wheels buried, the camp's windbreak.
    private func buildLandCruiser() {
        let body0 = SK.mat(SK.rgb(0x2E4A63), roughness: 0.42, metalness: 0.4)
        let glass = SK.mat(SK.rgb(0x12191F), roughness: 0.12, metalness: 0.3)
        let dark = SK.mat(SK.rgb(0x1B1D20), roughness: 0.6)
        let chrome = SK.mat(SK.rgb(0xB9BEC2), roughness: 0.3, metalness: 0.85)
        let rubber = SK.mat(SK.rgb(0x18181A), roughness: 0.95)
        let dust = SK.mat(SK.rgb(0xCDB894), roughness: 0.95)

        let car = SCNNode()
        let px: CGFloat = -1.5, pz: CGFloat = 4.6
        car.position = SCNVector3(px, ground(px, pz) - 0.18, pz)
        car.eulerAngles = SCNVector3(-0.09, 0.55, 0.05)      // nose up, rear sunk, a little roll
        world.addChildNode(car)

        let hull = SK.box(2.0, 0.95, 4.9, body0, chamfer: 0.12, at: SCNVector3(0, 0.95, 0))
        car.addChildNode(hull)
        let cabin = SK.box(1.9, 0.78, 2.5, body0, chamfer: 0.1, at: SCNVector3(0, 1.8, -0.25))
        car.addChildNode(cabin)
        // windscreen, side glass and rear glass
        let wind = SK.box(1.76, 0.6, 0.06, glass, at: SCNVector3(0, 1.82, 0.98))
        wind.eulerAngles.x = -0.32
        car.addChildNode(wind)
        car.addChildNode(SK.box(0.06, 0.5, 2.2, glass, at: SCNVector3(0.96, 1.84, -0.3)))
        car.addChildNode(SK.box(0.06, 0.5, 2.2, glass, at: SCNVector3(-0.96, 1.84, -0.3)))
        car.addChildNode(SK.box(1.7, 0.52, 0.06, glass, at: SCNVector3(0, 1.84, -1.52)))
        // roof rack with the sheet lashed to it
        for dz in [-1.05, 0.55, 1.5] as [CGFloat] {
            car.addChildNode(SK.box(1.72, 0.06, 0.07, chrome, at: SCNVector3(0, 2.24, dz)))
        }
        for dx in [-0.8, 0.8] as [CGFloat] {
            car.addChildNode(SK.box(0.06, 0.1, 2.7, chrome, at: SCNVector3(dx, 2.26, 0.2)))
        }
        // bull bar, lights, snorkel, spare wheel on the back
        car.addChildNode(SK.box(1.9, 0.24, 0.16, chrome, at: SCNVector3(0, 0.62, 2.45)))
        for dx in [-0.62, 0.62] as [CGFloat] {
            car.addChildNode(SK.box(0.44, 0.26, 0.1, SK.mat(SK.rgb(0xE8E2CE), roughness: 0.2), at: SCNVector3(dx, 1.06, 2.44)))
        }
        car.addChildNode(SK.box(0.16, 0.9, 0.16, dark, at: SCNVector3(0.98, 1.6, 1.3)))
        let spare = SK.node(SCNTorus(ringRadius: 0.34, pipeRadius: 0.14), rubber)
        spare.position = SCNVector3(0, 1.1, -2.55)
        spare.eulerAngles.y = .pi / 2
        car.addChildNode(spare)
        // a very dusty vehicle
        car.addChildNode(SK.box(2.02, 0.3, 1.2, dust, at: SCNVector3(0, 0.72, 1.6)))
        car.childNodes.last?.opacity = 0.5

        // wheels: rear pair half swallowed by the soft earth
        for (dx, dz, r) in [(-0.95, 1.55, 0.42), (0.95, 1.55, 0.42), (-0.95, -1.6, 0.42), (0.95, -1.6, 0.42)] as [(CGFloat, CGFloat, CGFloat)] {
            let w = wheel(r, rubber, chrome)
            w.position = SCNVector3(dx, dz > 0 ? r : r - 0.26, dz)
            car.addChildNode(w)
            lcWheels.append(w)
        }
        // sand banked against the buried rear wheels
        let sand = SK.noiseMat(SK.rgb(0xD3BB95), SK.rgb(0xB39A75), scale: 3, seed: 41)
        for dz in [-1.6, -2.3] as [CGFloat] {
            for dx in [-0.95, 0.95] as [CGFloat] {
                let mound = SK.sphere(0.62, sand, at: SCNVector3(dx, 0.16, dz))
                mound.scale = SCNVector3(1.1, 0.42, 1.5)
                car.addChildNode(mound)
            }
        }
        // the tailgate propped open against the sun
        let gate = SK.box(1.9, 1.0, 0.08, body0, chamfer: 0.05, at: SCNVector3(0, 1.5, -2.75))
        gate.eulerAngles.x = 1.25
        car.addChildNode(gate)

        // the door panel that became part of the shade frame
        let door = SK.box(1.1, 0.9, 0.07, body0, chamfer: 0.06, at: SCNVector3(2.6, ground(2.6, 7.4) + 0.45, 7.4))
        door.eulerAngles = SCNVector3(0.2, 0.4, -1.1)
        world.addChildNode(door)
    }

    /// 普拉多 — rolled off the ridge into the gully. Two versions: on its side and back on its wheels.
    private func buildPrado() {
        let paint = SK.mat(SK.rgb(0xD9D3C4), roughness: 0.55, metalness: 0.3)
        let glass = SK.mat(SK.rgb(0x1A2026), roughness: 0.12, metalness: 0.3)
        let chrome = SK.mat(SK.rgb(0xB4B9BE), roughness: 0.32, metalness: 0.8)
        let rubber = SK.mat(SK.rgb(0x18181A), roughness: 0.95)

        // ---- lying on its side in the trench ----
        let px: CGFloat = -14.4, pz: CGFloat = -5.2
        let side = SCNNode()
        side.position = SCNVector3(px, ground(px, pz) + 0.75, pz)
        side.eulerAngles = SCNVector3(-0.22, 1.15, 1.42)         // rolled over, nose into the bank
        world.addChildNode(side)
        side.addChildNode(SK.box(1.95, 0.92, 4.7, paint, chamfer: 0.14, at: SCNVector3(0, 0.95, 0)))
        side.addChildNode(SK.box(1.86, 0.76, 2.4, paint, chamfer: 0.12, at: SCNVector3(0, 1.78, -0.2)))
        side.addChildNode(SK.box(1.7, 0.56, 0.06, glass, at: SCNVector3(0, 1.8, 1.02)))
        side.addChildNode(SK.box(0.06, 0.48, 2.1, glass, at: SCNVector3(0.94, 1.82, -0.3)))
        side.addChildNode(SK.box(0.06, 0.48, 2.1, glass, at: SCNVector3(-0.94, 1.82, -0.3)))
        side.addChildNode(SK.box(1.9, 0.2, 0.16, chrome, at: SCNVector3(0, 0.6, 2.35)))
        // roof rack, snout and a crushed door: enough to read as a 4x4 on its side
        for dz in [-1.0, 0.6] as [CGFloat] {
            side.addChildNode(SK.box(1.5, 0.07, 0.07, chrome, at: SCNVector3(0, 2.2, dz)))
        }
        side.addChildNode(SK.box(1.6, 0.5, 0.12, paint, chamfer: 0.03, at: SCNVector3(0, 0.55, 2.45)))
        side.addChildNode(SK.box(0.9, 0.16, 0.5, SK.mat(SK.rgb(0x9A4A32), roughness: 0.6), at: SCNVector3(1.05, 1.3, 0.9)))
        let snorkel = SK.box(0.12, 0.7, 0.12, SK.mat(SK.rgb(0x22252A), roughness: 0.7), at: SCNVector3(0.98, 1.5, 1.6))
        side.addChildNode(snorkel)
        // one wheel torn off and standing in the sand, the rest still on the axles
        for (dx, dz) in [(-0.95, 1.5), (0.95, 1.5), (-0.95, -1.55), (0.95, -1.55)] as [(CGFloat, CGFloat)] {
            let w = wheel(0.42, rubber, chrome)
            w.position = SCNVector3(dx, 0.42, dz)
            side.addChildNode(w)
            pradoWheels.append(w)
        }
        let loose = wheel(0.42, rubber, chrome)
        loose.position = SCNVector3(px + 2.6, ground(px + 2.6, pz + 1.2) + 0.42, pz + 1.2)
        loose.eulerAngles = SCNVector3(0, 0.6, 1.5)
        world.addChildNode(loose)
        // the stuff that flew out of it
        let crate = SK.mat(SK.rgb(0x8A6A44), roughness: 0.9)
        for i in 0..<6 {
            let b = SK.box(0.5, 0.34, 0.4, i % 2 == 0 ? crate : paint, chamfer: 0.03)
            let a = CGFloat(i) * 1.1
            b.position = SCNVector3(px + 2.2 + sin(a) * 1.6, ground(px + 2.2, pz - 1.4) + 0.2, pz - 1.4 + cos(a) * 1.4)
            b.eulerAngles = SCNVector3(0.2, a, 0.1)
            world.addChildNode(b)
        }
        pradoSide = side

        // ---- back on its wheels in the trench ----
        let up = SCNNode()
        up.position = SCNVector3(px, ground(px, pz) + 0.06, pz)
        up.eulerAngles = SCNVector3(0.02, 1.4, 0)
        up.isHidden = true
        world.addChildNode(up)
        up.addChildNode(SK.box(1.95, 0.92, 4.7, paint, chamfer: 0.14, at: SCNVector3(0, 0.95, 0)))
        up.addChildNode(SK.box(1.86, 0.76, 2.4, paint, chamfer: 0.12, at: SCNVector3(0, 1.78, -0.2)))
        up.addChildNode(SK.box(1.7, 0.56, 0.06, glass, at: SCNVector3(0, 1.8, 1.02)))
        up.addChildNode(SK.box(0.06, 0.48, 2.1, glass, at: SCNVector3(0.94, 1.82, -0.3)))
        up.addChildNode(SK.box(0.06, 0.48, 2.1, glass, at: SCNVector3(-0.94, 1.82, -0.3)))
        up.addChildNode(SK.box(1.9, 0.2, 0.16, chrome, at: SCNVector3(0, 0.6, 2.35)))
        for (dx, dz) in [(-0.95, 1.5), (0.95, 1.5), (-0.95, -1.55), (0.95, -1.55)] as [(CGFloat, CGFloat)] {
            let w = wheel(0.42, rubber, chrome)
            w.position = SCNVector3(dx, 0.42, dz)
            up.addChildNode(w)
        }
        for dx in [-0.62, 0.62] as [CGFloat] {
            let lamp = SK.box(0.4, 0.24, 0.1, SK.mat(SK.rgb(0xF3EEDC), roughness: 0.2,
                                                    emission: SK.rgb(0xFFF0C8)), at: SCNVector3(dx, 1.02, 2.36))
            up.addChildNode(lamp)
            pradoLights.append(lamp)
        }
        // the bonnet up while they work on it
        let bonnet = SK.box(1.8, 0.1, 1.5, paint, chamfer: 0.06, at: SCNVector3(0, 1.86, 1.5))
        bonnet.eulerAngles.x = -1.15
        up.addChildNode(bonnet)
        hood = bonnet
        pradoUpright = up

        // tools, jack and the parts they hauled up out of the trench
        let metal = SK.mat(SK.rgb(0x6B6E72), roughness: 0.45, metalness: 0.7)
        let j = SCNNode()
        j.position = SCNVector3(px + 1.9, ground(px + 1.9, pz + 0.6), pz + 0.6)
        j.addChildNode(SK.box(0.5, 0.12, 0.3, metal, at: SCNVector3(0, 0.06, 0)))
        j.addChildNode(SK.cylinder(0.05, 0.5, metal, at: SCNVector3(0, 0.3, 0)))
        j.addChildNode(SK.box(0.24, 0.18, 0.24, SK.mat(SK.rgb(0xB03A2E), roughness: 0.6), at: SCNVector3(0, 0.6, 0)))
        j.isHidden = true
        world.addChildNode(j)
        jack = j

        let pile = SCNNode()
        pile.position = SCNVector3(px + 2.4, ground(px + 2.4, pz - 2.2), pz - 2.2)
        pile.addChildNode(SK.box(0.9, 0.34, 0.6, SK.mat(SK.rgb(0x2A2E33), roughness: 0.7), chamfer: 0.03, at: SCNVector3(0, 0.18, 0)))
        pile.addChildNode(SK.node(SCNTorus(ringRadius: 0.3, pipeRadius: 0.12), rubber, at: SCNVector3(0.7, 0.13, 0.5)))
        pile.addChildNode(SK.cylinder(0.22, 0.5, SK.mat(SK.rgb(0x9A4A2A), roughness: 0.5), at: SCNVector3(-0.8, 0.25, 0.3)))
        pile.isHidden = true
        world.addChildNode(pile)
        parts = pile

        // the ramp they dug out of the trench (only once the Prado is upright)
        let ramp = SK.node(SK.mesh([SIMD3(-8, 0, -5), SIMD3(2, 0, -3), SIMD3(2, 3.4, -3), SIMD3(-8, 0.2, -5)], [0, 1, 2, 0, 2, 3]),
                           SK.noiseMat(SK.rgb(0xCDB68E), SK.rgb(0xA88F6C), scale: 5, seed: 51))
        ramp.position = SCNVector3(px - 2, ground(px - 2, pz) - 4.4, pz + 6)
        ramp.isHidden = true
        world.addChildNode(ramp)
    }

    // MARK: The shade

    /// The plastic sheet rigged off the roof rack: the only shade for eighty kilometres.
    private func buildShade() {
        let plastic = SK.mat(NSColor(calibratedRed: 0.74, green: 0.83, blue: 0.88, alpha: 1), roughness: 0.3)
        plastic.transparency = 0.55
        plastic.transparencyMode = .dualLayer
        plastic.isDoubleSided = true
        plastic.blendMode = .alpha

        let sheet = SCNNode()
        let w: CGFloat = 3.9, l: CGFloat = 3.9
        var pts: [SIMD3<Float>] = [], idx: [UInt32] = []
        let nu = 12, nv = 12
        for i in 0...nu {
            for j in 0...nv {
                let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                let sag = sin(.pi * u) * sin(.pi * v)
                pts.append(SIMD3(Float(-w / 2 + CGFloat(u) * w), Float(-0.34 * sag - 0.20 * v), Float(CGFloat(v) * l)))
            }
        }
        for i in 0..<nu {
            for j in 0..<nv {
                let a = UInt32(i * (nv + 1) + j), b = a + 1, c = a + UInt32(nv + 1), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let cloth = SK.node(SK.mesh(pts, idx), plastic)
        cloth.castsShadow = true
        sheet.addChildNode(cloth)
        sheet.position = SCNVector3(0.2, ground(0.2, 6.6) + 2.34, 6.6)
        sheet.eulerAngles = SCNVector3(-0.17, 0.12, 0)
        world.addChildNode(sheet)
        shadeSheet = sheet

        // the second layer they tie on when the sun is at its worst
        let upper = SK.node(SK.mesh(pts, idx), plastic)
        upper.scale = SCNVector3(0.92, 1, 0.9)
        upper.position = SCNVector3(0, 0.42, -0.2)
        upper.isHidden = true
        sheet.addChildNode(upper)
        shadeUpper = upper

        // poles: one under each free corner
        let poleMat = SK.mat(SK.rgb(0x9AA0A6), roughness: 0.4, metalness: 0.6)
        let p1 = SCNNode()
        p1.position = SCNVector3(-1.6, ground(-1.6, 10.2), 10.2)
        p1.addChildNode(SK.cylinder(0.035, 2.05, poleMat, at: SCNVector3(0, 1.02, 0)))
        world.addChildNode(p1)
        shadePole = p1

        let poleMat2 = poleMat
        let p2 = SCNNode()
        p2.position = SCNVector3(1.9, ground(1.9, 10.3), 10.3)
        p2.addChildNode(SK.cylinder(0.035, 2.05, poleMat2, at: SCNVector3(0, 1.02, 0)))
        world.addChildNode(p2)
        shadePole2 = p2

        // the corner that tears off in a sandstorm and lies in the sand
        let rag = SK.node(SK.mesh(pts, idx), plastic)
        rag.scale = SCNVector3(0.3, 1, 0.26)
        rag.position = SCNVector3(3.0, ground(3.0, 11.2) + 0.06, 11.2)
        rag.eulerAngles = SCNVector3(-0.1, 0.8, 0.06)
        rag.isHidden = true
        world.addChildNode(rag)
        shadeRag = rag
    }
    private var shadePole2: SCNNode?

    // MARK: Water, stills, signals

    private func buildWaterPoint() {
        // the big blue drum and the crate of bottles they are rationing
        let blue = SK.mat(SK.rgb(0x2E6FA8), roughness: 0.55)
        let drum = SCNNode()
        drum.position = SCNVector3(-3.6, ground(-3.6, 9.4), 9.4)
        drum.addChildNode(SK.cylinder(0.29, 0.88, blue, at: SCNVector3(0, 0.44, 0)))
        drum.addChildNode(SK.cylinder(0.3, 0.06, SK.mat(SK.rgb(0xD8DDE2), roughness: 0.4, metalness: 0.6), at: SCNVector3(0, 0.9, 0)))
        let tap = SK.cylinder(0.03, 0.16, SK.mat(SK.rgb(0xEEEEEE), roughness: 0.3), at: SCNVector3(0.28, 0.3, 0))
        tap.eulerAngles.z = .pi / 2
        drum.addChildNode(tap)
        world.addChildNode(drum)

        // five-litre cans and bottles, straight out of the crate
        let clear = SK.mat(NSColor(calibratedRed: 0.62, green: 0.78, blue: 0.86, alpha: 1), roughness: 0.2)
        clear.transparency = 0.72
        clear.transparencyMode = .dualLayer
        let cap = SK.mat(SK.rgb(0x2E6FA8), roughness: 0.4)
        for i in 0..<10 {
            let b = SCNNode()
            let x = -2.8 + CGFloat(i % 5) * 0.5, z = 11.0 + CGFloat(i / 5) * 0.5
            b.position = SCNVector3(x, ground(x, z), z)
            b.addChildNode(SK.cylinder(0.06, 0.26, clear, at: SCNVector3(0, 0.13, 0)))
            b.addChildNode(SK.cylinder(0.03, 0.05, cap, at: SCNVector3(0, 0.28, 0)))
            world.addChildNode(b)
            bottles.append(b)
        }

        // the empties, kicked over in the sand
        let empty = SK.mat(NSColor(calibratedWhite: 0.92, alpha: 1), roughness: 0.3)
        empty.transparency = 0.65
        empty.transparencyMode = .dualLayer
        for i in 0..<12 {
            let b = SCNNode()
            let x = 4.6 + CGFloat(i % 4) * 0.85 + CGFloat(i % 3) * 0.2
            let z = 6.4 + CGFloat(i / 4) * 1.1 + CGFloat(i % 2) * 0.5
            b.position = SCNVector3(x, ground(x, z) + 0.075, z)
            b.eulerAngles = SCNVector3(0, CGFloat(i) * 0.9, 1.55)
            b.addChildNode(SK.cylinder(0.06, 0.26, empty, at: SCNVector3(0, 0.13, 0)))
            world.addChildNode(b)
            b.isHidden = true
            empties.append(b)
        }
    }

    /// Solar stills: a dimple in the salt with a sheet pegged over it and a stone on top.
    private func buildStills() {
        let mound = SK.noiseMat(SK.rgb(0xE2D8C2), SK.rgb(0xB6A382), scale: 4, seed: 61)
        let sheet = SK.mat(NSColor(calibratedWhite: 0.95, alpha: 1), roughness: 0.12, metalness: 0.05)
        sheet.transparency = 0.34
        sheet.transparencyMode = .dualLayer
        sheet.isDoubleSided = true
        let stone = SK.noiseMat(SK.rgb(0x7E7261), SK.rgb(0x4E463B), scale: 5, seed: 62)
        let spots: [(CGFloat, CGFloat)] = [(-8.5, 3.0), (-10.4, 6.4), (-6.6, 8.6), (-12.6, 1.4), (-9.2, 11.2), (-13.4, 6.2)]
        for p in spots {
            let n = SCNNode()
            n.position = SCNVector3(p.0, ground(p.0, p.1), p.1)
            let rim = SK.cylinder(0.72, 0.13, mound, at: SCNVector3(0, 0.06, 0))
            rim.scale = SCNVector3(1, 1, 1.15)
            n.addChildNode(rim)
            n.addChildNode(SK.cylinder(0.5, 0.05, SK.mat(SK.rgb(0x4E463A), roughness: 1), at: SCNVector3(0, 0.1, 0)))
            let dome = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 0.7, height: 0.2))
            dome.geometry?.materials = [sheet]
            dome.position.y = 0.16
            n.addChildNode(dome)
            n.addChildNode(SK.sphere(0.09, stone, at: SCNVector3(0, 0.27, 0), segments: 8))
            // a cup half sunk in the middle of it
            n.addChildNode(SK.cylinder(0.06, 0.1, SK.mat(SK.rgb(0xE8E4DA), roughness: 0.4), at: SCNVector3(0.5, 0.2, 0.3)))
            n.isHidden = true
            world.addChildNode(n)
            stillPits.append(n)
        }
    }

    /// The SOS on the salt crust: seat cushions, tyres and stones, laid out letter by letter.
    private func buildSOS() {
        let cushion = SK.mat(SK.rgb(0x24282D), roughness: 0.9)
        let stone = SK.noiseMat(SK.rgb(0x8A7E6B), SK.rgb(0x5A5145), scale: 5, seed: 71)
        let origin = SCNVector3(1, 0, -15)
        func stroke(_ x0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ z1: CGFloat) {
            let (x0, z0, x1, z1) = (x0 * 0.95, z0 * 0.95, x1 * 0.95, z1 * 0.95)
            let n = max(2, Int(hypot(x1 - x0, z1 - z0) / 0.7))
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n - 1)
                let x = origin.x + x0 + (x1 - x0) * t, z = origin.z + z0 + (z1 - z0) * t
                let node: SCNNode
                if k % 4 == 3 {
                    node = SK.rock(Float(0.26 + noise.value(Float(k), Float(x)) * 0.16), stone, seed: UInt64(300 + k))
                } else {
                    node = SK.box(1.05, 0.16, 1.05, cushion, chamfer: 0.06)
                }
                node.position = SCNVector3(x, ground(x, z) + 0.07, z)
                node.eulerAngles.y = atan2(x1 - x0, z1 - z0) + CGFloat(k % 2) * 0.1
                node.isHidden = true
                world.addChildNode(node)
                sosMarks.append(node)
            }
        }
        // letters 6 m tall, read from the air with "up" toward −z
        stroke(0, 0, 0, -8); stroke(0, -8, 6, -8); stroke(6, -8, 6, -4); stroke(6, -4, 0, -4); stroke(0, -4, 0, 0)
        stroke(8.6, 0, 8.6, -8); stroke(8.6, -8, 14.6, -8); stroke(14.6, -8, 14.6, 0); stroke(14.6, 0, 8.6, 0)
        stroke(17.2, 0, 17.2, -8); stroke(17.2, -8, 23.2, -8); stroke(23.2, -8, 23.2, -4); stroke(23.2, -4, 17.2, -4); stroke(17.2, -4, 17.2, 0)
        // an arrow pointing back at the camp
        stroke(8.6, 3.4, 16.0, 3.4); stroke(16.0, 3.4, 13.4, 1.5); stroke(16.0, 3.4, 13.4, 5.3)
    }

    /// The old survey stakes that run north-east toward the lorry road (var.route).
    private func buildStakes() {
        let wood = SK.noiseMat(SK.rgb(0x7A6244), SK.rgb(0x4E3E2C), scale: 4, seed: 81)
        for i in 0..<16 {
            let d = CGFloat(26 + i * 12)
            let x = CGFloat(campX) + CGFloat(windX) * d, z = CGFloat(campZ) + CGFloat(windZ) * d
            let n = SCNNode()
            n.position = SCNVector3(x, ground(x, z), z)
            let p = SK.box(0.1, 1.25, 0.1, wood, at: SCNVector3(0, 0.6, 0))
            p.eulerAngles = SCNVector3(0.05, CGFloat(i) * 0.4, 0.04)
            n.addChildNode(p)
            n.addChildNode(SK.box(0.34, 0.16, 0.04, SK.mat(SK.rgb(0xB9B2A2), roughness: 0.8), at: SCNVector3(0, 1.1, 0.02)))
            n.isHidden = true
            world.addChildNode(n)
            stakes.append(n)
        }
    }

    /// A camel that died out here years ago, half sunk in the crust.
    private func buildBones() {
        let bone = SK.mat(SK.rgb(0xD8CCB0), roughness: 0.9)
        let n = SCNNode()
        let bx: CGFloat = 11, bz: CGFloat = 13
        n.position = SCNVector3(bx, ground(bx, bz) + 0.02, bz)
        n.eulerAngles.y = -0.5
        n.scale = SCNVector3(1.45, 1.45, 1.45)
        // spine and ribs
        for i in 0..<9 {
            let t = CGFloat(i) * 0.34 - 1.4
            let v = SK.cylinder(0.05, 0.34, bone, at: SCNVector3(0, 0.1, t))
            v.eulerAngles.x = .pi / 2
            n.addChildNode(v)
            let rib = SK.node(SCNTorus(ringRadius: 0.36 - CGFloat(i % 3) * 0.05, pipeRadius: 0.028), bone)
            rib.position = SCNVector3(0, 0.06, t)
            rib.eulerAngles = SCNVector3(.pi / 2, 0, 0.25 * CGFloat(i % 2 == 0 ? 1 : -1))
            n.addChildNode(rib)
        }
        // skull, jaw and legs
        let skull = SK.node(SCNCone(topRadius: 0.1, bottomRadius: 0.2, height: 0.5), bone)
        skull.eulerAngles = SCNVector3(.pi / 2, 0, 0.2)
        skull.position = SCNVector3(0.1, 0.14, -2.0)
        n.addChildNode(skull)
        n.addChildNode(SK.box(0.12, 0.1, 0.5, bone, at: SCNVector3(0.1, 0.05, -1.7)))
        for (i, dx) in [-0.5, -0.3, 0.3, 0.5].enumerated() {
            let leg = SK.cylinder(0.045, 1.3, bone, at: SCNVector3(CGFloat(dx), 0.07, 0.9 + CGFloat(i) * 0.22))
            leg.eulerAngles = SCNVector3(.pi / 2, 0, 0.1 * CGFloat(i))
            n.addChildNode(leg)
        }
        world.addChildNode(n)
    }

    /// A cracked concrete milestone left over from the survey line.
    private func buildMilestone() {
        let concrete = SK.noiseMat(SK.rgb(0xAFA89A), SK.rgb(0x7C7466), scale: 5, seed: 91)
        let n = SCNNode()
        let mx: CGFloat = -5.4, mz: CGFloat = -7.5
        n.position = SCNVector3(mx, ground(mx, mz), mz)
        n.eulerAngles = SCNVector3(0.05, 0.55, -0.05)
        n.addChildNode(SK.box(0.4, 2.05, 0.28, concrete, chamfer: 0.02, at: SCNVector3(0, 1.02, 0)))
        n.addChildNode(SK.box(0.42, 0.12, 0.3, SK.mat(SK.rgb(0xA8342A), roughness: 0.8), at: SCNVector3(0, 1.94, 0)))
        // the characters are cut into the face; a small extruded label reads at close range
        let face = SK.mat(SK.rgb(0x4A4238), roughness: 0.9)
        let plate = SCNNode()
        plate.position = SCNVector3(0, 1.52, 0.15)
        let c1 = label("罗布泊", cap: 0.2, face)
        plate.addChildNode(c1)
        let c2 = label("K 512", cap: 0.13, face)
        c2.position = SCNVector3(0, -0.28, 0)
        plate.addChildNode(c2)
        n.addChildNode(plate)
        world.addChildNode(n)
    }

    /// Extruded text with its baseline-left at the origin, scaled to a cap height in metres.
    private func label(_ text: String, cap: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0.012)
        t.font = NSFont(name: "PingFangSC-Semibold", size: 1) ?? NSFont.systemFont(ofSize: 1)
        t.flatness = 0.06
        t.materials = [m]
        let n = SCNNode(geometry: t)
        let bb = n.boundingBox
        let h = CGFloat(bb.max.y - bb.min.y)
        let k = h > 0.01 ? cap / h : cap
        n.pivot = SCNMatrix4MakeTranslation((bb.min.x + bb.max.x) / 2, bb.min.y, 0)
        n.scale = SCNVector3(k, k, k)
        return n
    }

    /// Camp clutter: the tripod, the jerry cans, the toolbox, a folded chair, the drone case.
    private func buildCampClutter() {
        let metal = SK.mat(SK.rgb(0x6E7176), roughness: 0.45, metalness: 0.6)
        let cloth = SK.mat(SK.rgb(0x3E5A6E), roughness: 0.9)
        // camera tripod
        let tri = SCNNode()
        tri.position = SCNVector3(4.0, ground(4.0, 6.0), 6.0)
        for i in 0..<3 {
            let leg = SK.cylinder(0.025, 1.5, metal)
            leg.eulerAngles = SCNVector3(0, CGFloat(i) * 2.1, 0.22)
            leg.position = SCNVector3(sin(CGFloat(i) * 2.1) * 0.18, 0.72, cos(CGFloat(i) * 2.1) * 0.18)
            tri.addChildNode(leg)
        }
        tri.addChildNode(SK.box(0.24, 0.16, 0.18, SK.mat(SK.rgb(0x22242A), roughness: 0.5), chamfer: 0.02, at: SCNVector3(0, 1.52, 0)))
        world.addChildNode(tri)
        // jerry cans
        for i in 0..<3 {
            let x = 1.6 + CGFloat(i) * 0.3, z = 12.0
            let can = SK.box(0.18, 0.44, 0.32, i == 0 ? metal : SK.mat(SK.rgb(0x3E6B3A), roughness: 0.6),
                             chamfer: 0.03, at: SCNVector3(x, ground(x, z) + 0.22, z))
            can.eulerAngles.y = CGFloat(i) * 0.3
            world.addChildNode(can)
        }
        // a toolbox and a folded camp chair
        let box = SK.box(0.62, 0.3, 0.34, SK.mat(SK.rgb(0xA03A2A), roughness: 0.55), chamfer: 0.03,
                         at: SCNVector3(-0.6, ground(-0.6, 11.6) + 0.15, 11.6))
        box.eulerAngles.y = 0.4
        world.addChildNode(box)
        let chair = SK.box(0.5, 0.12, 0.5, cloth, chamfer: 0.02, at: SCNVector3(3.0, ground(3.0, 12.2) + 0.08, 12.2))
        chair.eulerAngles = SCNVector3(0.1, 0.5, 0.06)
        world.addChildNode(chair)
        // spare wheels stacked by the Land Cruiser
        let rubber = SK.mat(SK.rgb(0x1A1A1C), roughness: 0.95)
        for i in 0..<3 {
            let t = SK.node(SCNTorus(ringRadius: 0.32, pipeRadius: 0.13), rubber)
            let x = -4.6, z = 6.2 + CGFloat(i) * 0.05
            t.position = SCNVector3(x, ground(x, z) + 0.14 + CGFloat(i) * 0.06, z)
            t.eulerAngles = SCNVector3(0.2, CGFloat(i) * 0.5, 0.1)
            world.addChildNode(t)
        }
    }

    /// The fire: stones, a couple of tyres and a blackened patch — the signal they burn at night.
    private func buildFireRing() {
        let stone = SK.noiseMat(SK.rgb(0x7E7261), SK.rgb(0x4E463B), scale: 5, seed: 97)
        let rubber = SK.mat(SK.rgb(0x18181A), roughness: 0.95)
        let n = SCNNode()
        n.position = SCNVector3(5.6, ground(5.6, 1.2), 1.2)
        for i in 0..<9 {
            let a = CGFloat(i) / 9 * 2 * .pi
            let r = SK.rock(Float(0.14 + noise.value(Float(i), 3) * 0.08), stone, seed: UInt64(400 + i))
            r.position = SCNVector3(sin(a) * 0.85, 0.06, cos(a) * 0.85)
            n.addChildNode(r)
        }
        // tyres ready to be thrown on, and one already burnt out
        let t1 = SK.node(SCNTorus(ringRadius: 0.33, pipeRadius: 0.14), rubber, at: SCNVector3(1.5, 0.15, 0.5))
        n.addChildNode(t1)
        let t2 = SK.node(SCNTorus(ringRadius: 0.33, pipeRadius: 0.14), rubber, at: SCNVector3(1.2, 0.45, 0.9))
        n.addChildNode(t2)
        let burnt = SK.node(SCNTorus(ringRadius: 0.3, pipeRadius: 0.1), SK.mat(SK.rgb(0x0E0E10), roughness: 1),
                            at: SCNVector3(-1.3, 0.12, -0.7))
        burnt.eulerAngles.x = 1.4
        n.addChildNode(burnt)
        world.addChildNode(n)
    }

    // MARK: Heat and weather

    /// Mirage bands: the sky laid flat on the pan, and the shimmer that melts the horizon.
    private func buildHeat() {
        let m = SK.mat(.black, roughness: 1)
        m.lightingModel = .constant
        m.diffuse.contents = softImage(size: 128, horizontal: true)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        m.transparency = 0.26

        // pooled sky on the ground, well out on the pan
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi + 0.4
            let d: CGFloat = 150 + CGFloat(i % 3) * 60
            let x = CGFloat(campX) + sin(CGFloat(a)) * d, z = CGFloat(campZ) + cos(CGFloat(a)) * d
            let plane = SCNPlane(width: 130, height: 24)
            plane.firstMaterial = m
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(-.pi / 2, 0, CGFloat(a))
            n.position = SCNVector3(x, ground(x, z) + 0.9, z)
            n.castsShadow = false
            n.opacity = 0.5
            n.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.7, duration: 2.2 + Double(i) * 0.3),
                                                  .fadeOpacity(to: 0.35, duration: 2.4 + Double(i) * 0.3)])))
            world.addChildNode(n)
            mirage.append(n)
        }
        // vertical shimmer standing over the far ridges
        let hm = SK.mat(.black, roughness: 1)
        hm.lightingModel = .constant
        hm.diffuse.contents = softImage(size: 128, horizontal: false)
        hm.blendMode = .add
        hm.writesToDepthBuffer = false
        hm.isDoubleSided = true
        hm.transparency = 0.16
        for i in 0..<4 {
            let plane = SCNPlane(width: 70, height: 5)
            plane.firstMaterial = hm
            let n = SCNNode(geometry: plane)
            let a = CGFloat(i) * 1.6 + 0.2
            n.position = SCNVector3(CGFloat(campX) + sin(a) * 330, 1.4 + CGFloat(i) * 0.4, CGFloat(campZ) + cos(a) * 330)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            n.constraints = [billboard]
            n.castsShadow = false
            n.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.34, duration: 1.7 + Double(i) * 0.4),
                                                  .fadeOpacity(to: 0.16, duration: 2.1 + Double(i) * 0.4)])))
            world.addChildNode(n)
            haze.append(n)
        }
    }

    /// A soft blob: bright in the middle, fading to nothing at the edges.
    private func softImage(size: Int, horizontal: Bool) -> NSImage {
        var px = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let u = Double(x) / Double(size) * 2 - 1
                let v = Double(y) / Double(size) * 2 - 1
                let r = (u * u + v * v).squareRoot()
                let k = max(0, 1 - r)
                let a = k * k * (horizontal ? 1 : 0.9)
                let i = (y * size + x) * 4
                px[i] = UInt8(196 * a)
                px[i + 1] = UInt8(220 * a)
                px[i + 2] = UInt8(255 * a)
                px[i + 3] = UInt8(255 * min(1, a))
            }
        }
        return SK.image(from: px, size: size)
    }

    /// Blowing sand: one particle system, driven by the wind (the rare rain is the base's job).
    private func buildSand() {
        let p = SK.dust(intensity: 0.5, wind: 30, color: SK.rgb(0xDCBE93), area: 90)
        p.birthRate = 0
        let n = SCNNode()
        n.position = SCNVector3(0, 5, 0)
        n.eulerAngles.y = CGFloat(atan2(-windX, -windZ))       // sand blows downwind
        n.addParticleSystem(p)
        world.addChildNode(n)
        dustNode = n
        sand = p
    }

    // MARK: - Rescue, neighbours and the missing

    private func makeConvoyVehicle(_ truck: Bool) -> SCNNode {
        let n = SCNNode()
        let paint = SK.mat(SK.rgb(0xE8E5DC), roughness: 0.45, metalness: 0.3)
        let dark = SK.mat(SK.rgb(0x1B1D20), roughness: 0.6)
        let rubber = SK.mat(SK.rgb(0x18181A), roughness: 0.95)
        let chrome = SK.mat(SK.rgb(0xB4B9BE), roughness: 0.3, metalness: 0.8)
        if truck {
            n.addChildNode(SK.box(2.3, 1.5, 5.4, paint, chamfer: 0.12, at: SCNVector3(0, 1.5, 0.4)))
            n.addChildNode(SK.box(2.3, 1.3, 2.2, paint, chamfer: 0.1, at: SCNVector3(0, 2.0, -2.2)))
            n.addChildNode(SK.box(2.1, 0.7, 0.08, dark, at: SCNVector3(0, 2.15, -3.25)))
            n.addChildNode(SK.box(2.2, 1.4, 2.6, SK.mat(SK.rgb(0x2E6FA8), roughness: 0.7), chamfer: 0.05, at: SCNVector3(0, 2.2, 1.6)))
        } else {
            n.addChildNode(SK.box(1.9, 0.9, 4.6, paint, chamfer: 0.12, at: SCNVector3(0, 0.95, 0)))
            n.addChildNode(SK.box(1.8, 0.7, 2.0, paint, chamfer: 0.1, at: SCNVector3(0, 1.75, -0.4)))
            n.addChildNode(SK.box(1.6, 0.5, 0.06, dark, at: SCNVector3(0, 1.78, 0.62)))
        }
        let wz: CGFloat = truck ? 2.1 : 1.5
        for (dx, dz) in [(-1.0, wz), (1.0, wz), (-1.0, -wz), (1.0, -wz)] as [(CGFloat, CGFloat)] {
            let w = wheel(truck ? 0.55 : 0.42, rubber, chrome)
            w.position = SCNVector3(dx, truck ? 0.55 : 0.42, dz)
            n.addChildNode(w)
        }
        // headlights, and the glow they throw at night
        for dx in [-0.6, 0.6] as [CGFloat] {
            let lamp = SK.box(0.34, 0.2, 0.08, SK.mat(SK.rgb(0xF6F1DE), roughness: 0.2, emission: SK.rgb(0xFFF2CE)),
                              at: SCNVector3(dx, 1.0, truck ? -3.3 : 2.32))
            lamp.name = "lamp"
            n.addChildNode(lamp)
        }
        return n
    }

    private func buildRescue() {
        let c = SCNNode()
        let lead = makeConvoyVehicle(true)
        let follow = makeConvoyVehicle(false)
        lead.position = SCNVector3(0, 0, 4.5)
        follow.position = SCNVector3(-3.4, 0, -3)
        c.addChildNode(lead)
        c.addChildNode(follow)
        c.position = SCNVector3(52, ground(52, -44) + 0.1, -44)
        c.eulerAngles.y = CGFloat(atan2(-windX, -windZ)) + 0.15
        c.isHidden = true
        world.addChildNode(c)
        convoy = c

        // a spotter plane droning over the pan
        let p = SCNNode()
        let m = SK.mat(SK.rgb(0x7E858C), roughness: 0.5, metalness: 0.4)
        let body = SK.node(SCNCapsule(capRadius: 0.55, height: 8), m)
        body.eulerAngles.x = .pi / 2
        p.addChildNode(body)
        p.addChildNode(SK.box(13, 0.14, 1.5, m))
        p.addChildNode(SK.box(3.6, 0.12, 0.9, m, at: SCNVector3(0, 0, -3.6)))
        let orbit = SCNNode()
        orbit.position = SCNVector3(90, 190, -40)
        p.position = SCNVector3(130, 0, 0)
        orbit.addChildNode(p)
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 60)))
        orbit.isHidden = true
        world.addChildNode(orbit)
        plane = orbit
    }

    /// 葛长贵's pickup: a canvas over the load bed, parked off to one side while he is here.
    private func buildPickup() {
        let n = SCNNode()
        let paint = SK.mat(SK.rgb(0x7E8A72), roughness: 0.7, metalness: 0.2)
        let canvas = SK.mat(SK.rgb(0x6E6552), roughness: 0.9, doubleSided: true)
        n.addChildNode(SK.box(1.85, 0.85, 4.4, paint, chamfer: 0.1, at: SCNVector3(0, 0.9, 0)))
        n.addChildNode(SK.box(1.75, 0.7, 1.8, paint, chamfer: 0.08, at: SCNVector3(0, 1.68, -0.5)))
        n.addChildNode(SK.box(1.6, 0.5, 0.06, SK.mat(SK.rgb(0x1E242A), roughness: 0.2), at: SCNVector3(0, 1.7, 0.44)))
        // the load bed and its tarpaulin
        n.addChildNode(SK.box(1.8, 0.5, 2.0, paint, chamfer: 0.04, at: SCNVector3(0, 1.05, 1.9)))
        for dz in [1.0, 2.8] as [CGFloat] {
            n.addChildNode(SK.box(1.86, 0.9, 0.08, canvas, at: SCNVector3(0, 1.7, dz)))
        }
        n.addChildNode(SK.box(1.86, 0.1, 1.9, canvas, at: SCNVector3(0, 2.14, 1.9)))
        let rubber = SK.mat(SK.rgb(0x18181A), roughness: 0.95)
        let chrome = SK.mat(SK.rgb(0x9EA3A8), roughness: 0.4, metalness: 0.7)
        for (dx, dz) in [(-0.95, 1.5), (0.95, 1.5), (-0.95, -1.5), (0.95, -1.5)] as [(CGFloat, CGFloat)] {
            let w = wheel(0.4, rubber, chrome)
            w.position = SCNVector3(dx, 0.4, dz)
            n.addChildNode(w)
        }
        n.position = SCNVector3(16, ground(16, 17) + 0.05, 17)
        n.eulerAngles = SCNVector3(0.02, 2.2, 0.03)
        n.isHidden = true
        world.addChildNode(n)
        pickup = n
    }

    /// 艾山's camels: the herd that walks in out of the east.
    private func buildHerd() {
        let n = SCNNode()
        n.position = SCNVector3(30, ground(30, -18), -18)
        for i in 0..<4 {
            let a = CGFloat(i) * 1.7
            let c = SK.animal(weight: i == 3 ? 90 : 420, color: SK.rgb(0xC6A87A), seed: i * 13)
            c.position = SCNVector3(sin(a) * 4.5, 0, cos(a) * 3.2)
            c.eulerAngles.y = a
            n.addChildNode(c)
        }
        n.isHidden = true
        world.addChildNode(n)
        herd = n
    }

    /// The bitter well they found in the east: a collapsed timber frame and a bucket.
    private func buildWell() {
        let wood = SK.noiseMat(SK.rgb(0x6E5738), SK.rgb(0x453320), scale: 4, seed: 111)
        let n = SCNNode()
        let x: CGFloat = 36, z: CGFloat = 10
        n.position = SCNVector3(x, ground(x, z), z)
        let shaft = SK.cylinder(0.75, 0.5, SK.mat(SK.rgb(0x2A2620), roughness: 1), at: SCNVector3(0, 0.05, 0))
        n.addChildNode(shaft)
        for i in 0..<4 {
            let a = CGFloat(i) * .pi / 2 + 0.3
            let post = SK.box(0.16, 1.3, 0.16, wood, at: SCNVector3(sin(a) * 0.75, 0.6, cos(a) * 0.75))
            post.eulerAngles = SCNVector3(0.06, a, 0.1)
            n.addChildNode(post)
        }
        for i in 0..<6 {
            let a = CGFloat(i) * 1.05
            let rim = SK.rock(Float(0.22 + noise.value(Float(i), 5) * 0.2), wood, seed: UInt64(500 + i))
            rim.position = SCNVector3(sin(a) * 0.95, 0.08, cos(a) * 0.95)
            n.addChildNode(rim)
        }
        let bucket = SK.cylinder(0.16, 0.28, SK.mat(SK.rgb(0x4E5A66), roughness: 0.6), at: SCNVector3(1.1, 0.14, 0.3))
        n.addChildNode(bucket)
        n.isHidden = true
        world.addChildNode(n)
        well = n
    }

    /// 何川's two-wheeled water cart, if it is ever found.
    private func buildCart() {
        let n = SCNNode()
        let metal = SK.mat(SK.rgb(0x8A9298), roughness: 0.5, metalness: 0.6)
        let wood = SK.noiseMat(SK.rgb(0x8A6A44), SK.rgb(0x5A4126), scale: 4, seed: 121)
        n.addChildNode(SK.box(0.9, 0.12, 1.8, wood, chamfer: 0.02, at: SCNVector3(0, 0.6, 0)))
        n.addChildNode(SK.box(0.08, 0.5, 0.08, metal, at: SCNVector3(0.4, 0.85, -0.9)))
        n.addChildNode(SK.box(0.08, 0.5, 0.08, metal, at: SCNVector3(-0.4, 0.85, -0.9)))
        for i in 0..<4 {
            let can = SK.box(0.3, 0.42, 0.3, i % 2 == 0 ? metal : SK.mat(SK.rgb(0x3E6B3A), roughness: 0.6),
                             chamfer: 0.03, at: SCNVector3(CGFloat(i % 2) * 0.34 - 0.17, 0.87, CGFloat(i / 2) * 0.4 - 0.2))
            n.addChildNode(can)
        }
        let rubber = SK.mat(SK.rgb(0x1A1A1C), roughness: 0.95)
        for dx in [-0.62, 0.62] as [CGFloat] {
            let w = wheel(0.34, rubber, metal)
            w.position = SCNVector3(dx, 0.34, 0.2)
            n.addChildNode(w)
        }
        n.position = SCNVector3(24, ground(24, 26), 26)
        n.eulerAngles = SCNVector3(0.03, 1.1, 0.05)
        n.isHidden = true
        world.addChildNode(n)
        cart = n
    }

    // MARK: - State

    override func apply(_ s: SceneState, old: SceneState?) {
        // ---- water: what is left stands in bottles, what is gone lies in the sand
        let water = max(0, s.res("water"))
        let full = min(bottles.count, Int((water / 11).rounded(.up)))
        for (i, b) in bottles.enumerated() { b.isHidden = i >= full }
        let empt = min(empties.count, max(0, 10 - full))
        for (i, b) in empties.enumerated() { b.isHidden = i >= empt }

        // ---- SOS on the salt: it grows with the signal and the wind wears it down again
        let signal = s.v("signal", 8)
        let shown = Int((Double(sosMarks.count) * max(0, min(1, (signal - 5) / 70))).rounded())
        for (i, m) in sosMarks.enumerated() { m.isHidden = i >= shown }

        // ---- solar stills
        let stills = Int(s.v("stills", 0))
        for (i, p) in stillPits.enumerated() { p.isHidden = i >= stills }

        // ---- the way out: survey stakes appear as they work out where the road is
        let route = s.v("route", 0)
        let st = Int((Double(stakes.count) * max(0, min(1, route / 95))).rounded())
        for (i, k) in stakes.enumerated() { k.isHidden = i >= st }

        // ---- the Prado: on its side, half-lifted, back on its wheels, running
        let flipped = s.done.contains("flip_car")
        let lifting = s.project("flip_car")
        pradoSide?.isHidden = flipped
        pradoUpright?.isHidden = !flipped
        // while they dig under it the wreck rolls slowly back toward level
        pradoSide?.eulerAngles = SCNVector3(0.06, 1.15, 1.35 - 0.55 * CGFloat(min(1, lifting)))
        jack?.isHidden = !(lifting > 0.05)
        parts?.isHidden = !(s.done.contains("fix_car") || s.done.contains("lc_ruined"))
        let running = s.done.contains("fix_car") || s.has("car_ready")
        hood?.isHidden = !(s.project("fix_car") > 0.05 && !running)
        for l in pradoLights { l.geometry?.firstMaterial?.emission.intensity = running ? 1.6 : 0.15 }
        rutsOut?.isHidden = !(running || s.has("drove_out") || s.has("trek_started"))

        // ---- the Land Cruiser stripped for parts
        let stripped = s.has("lc_ruined")
        for w in lcWheels { w.isHidden = stripped }

        // ---- the shade: the sheet is only as good as the shelter number says
        let good = s.shelter >= 45 || s.has("storm_secured")
        shadeSheet?.eulerAngles = good ? SCNVector3(-0.02, 0.55, 0) : SCNVector3(-0.26, 0.5, 0.09)
        shadeSheet?.scale = SCNVector3(1, good ? 1 : 0.72, 1)
        shadePole2?.isHidden = !good
        shadePole?.eulerAngles = SCNVector3(0, 0, good ? 0 : 0.35)
        shadeRag?.isHidden = good
        shadeUpper?.isHidden = s.shelter < 78

        // ---- someone walked out for help
        marcher?.childNodes.forEach { $0.isHidden = !(s.has("trek_started") && !s.has("trek_success")) }

        // ---- the well, the cart, the lookout, the neighbours
        well?.isHidden = !s.has("well_found")
        cart?.isHidden = !s.has("cart_found")
        if s.has("sms_sent") || s.has("signal_spot"), lookout == nil { buildLookout() }
        lookout?.isHidden = !(s.has("sms_sent") || s.has("signal_spot"))
        herd?.isHidden = !s.has("herder_came")
        let poacher = s.people.contains { $0.id == "ge" }
        if poacher, pickup == nil { buildPickup() }
        pickup?.isHidden = !poacher

        // ---- rescue: the convoy on the road, the plane overhead
        if s.now("rescue") || s.has("rescued") || s.has("spotted"), convoy == nil { buildRescue() }
        let rescue = s.now("rescue") || s.has("rescued") || s.has("spotted")
        convoy?.isHidden = !rescue
        plane?.isHidden = !(s.now("r_plane") || s.v("search", 0) >= 25)
        for l in convoy?.childNodes.flatMap({ $0.childNodes }).filter({ $0.name == "lamp" }) ?? [] {
            l.geometry?.firstMaterial?.emission.intensity = s.isNight ? 2.2 : 0.2
        }

        // ---- heat: the mirage only exists when the sun is beating down
        let hot = s.sun > 0.45 && s.visibility > 0.25 && !s.isNight
        for m in mirage { m.isHidden = !hot }
        for h in haze { h.isHidden = s.visibility < 0.2 }

        // ---- after dark: a cold, moonlit pan instead of a black hole
        let night = s.isNight
        iblScale = night ? 1.6 : 0.42
        cameraNode.camera?.exposureOffset = night ? (exposure + 1.0) : exposure
        moonFill.light?.intensity = night ? 300 : 0
        // the base leaves a strong white ambient: pull it down so the sun does the shading
        ambientNode.light?.intensity = night ? 24 : 58

        // ---- blowing sand
        let blowing = s.precip < 0.05 && s.wind >= 14
        if blowing != sandOn, let p = sand, let n = dustNode {
            sandOn = blowing
            if blowing { n.addParticleSystem(p) } else { n.removeParticleSystem(p) }
        }
        if blowing, let p = sand {
            let k = min(1, max(0, (s.wind - 12) / 55))
            p.birthRate = CGFloat(140 + 3400 * k * k)
            p.particleVelocity = CGFloat(2 + s.wind / 5)
            p.particleSize = CGFloat(0.35 + 0.85 * k)
            p.particleColor = SK.rgb(0xDCBE93).withAlphaComponent(CGFloat(0.05 + 0.16 * k))
        }

        // ---- people and the dead
        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: Spot.line(from: SCNVector3(6.2, 0, 4.6), to: SCNVector3(9.4, 0, 0.8),
                                            count: 6, facing: 1.9, y: ground))
    }

    /// Where everyone is standing: in the shade by day, around the fire at night.
    private func spots(for s: SceneState) -> [Spot] {
        let storm = s.visibility < 0.25 || s.wind >= 45
        let working = s.project("flip_car") > 0.05 || s.project("fix_car") > 0.05
        let shade: [(CGFloat, CGFloat, CGFloat)] = [
            (0.8, 9.0, 0.2), (2.0, 9.6, -0.4), (-0.6, 10.0, 0.6), (1.2, 10.8, -0.2),
            (3.0, 10.2, 0.4), (0.0, 11.6, -0.8), (2.2, 11.8, 0.1), (4.0, 9.2, -0.5)
        ]
        let gully: [(CGFloat, CGFloat, CGFloat)] = [(-15.0, -2.2, 2.0), (-12.4, -8.6, -1.2)]
        let night: [(CGFloat, CGFloat, CGFloat)] = [(2.8, 2.6, 0.4), (5.6, 2.4, -0.5), (5.2, 0.0, 2.6),
                                                    (2.6, -0.4, 3.0), (4.2, 3.2, 1.2), (6.4, 1.2, 2.0)]
        if storm {
            return shade.prefix(6).map { Spot($0.0 + 0.4, ground($0.0, $0.1), $0.1, facing: $0.2, pose: .huddled) }
        }
        if s.isNight {
            var out = night.map { Spot($0.0, ground($0.0, $0.1), $0.1, facing: $0.2) }
            out.append(Spot(-14.0, ground(-14, -2.4), -2.4, facing: 2.4))    // one still at the wreck
            return out
        }
        var out = shade.map { Spot($0.0, ground($0.0, $0.1), $0.1, facing: $0.2, pose: .sitting) }
        if working { out.insert(contentsOf: gully.map { Spot($0.0, ground($0.0, $0.1), $0.1, facing: $0.2) }, at: 2) }
        out.append(Spot(5.0, ground(5.0, -2.0), -2.0, facing: 0.6))         // watching the horizon
        out.append(Spot(-2.6, ground(-2.6, 2.0), 2.0, facing: 1.8))
        return out
    }
}
