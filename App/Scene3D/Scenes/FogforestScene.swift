import SceneKit
import AppKit

/// 雾林 — old-growth evergreen broadleaf forest (中山湿性常绿阔叶林) in the Ailao Mountains (哀牢山),
/// Yunnan, ~2,700 m, November: fog that never lifts, drizzle, moss on everything.
///
/// Layout (meters): a steep gully runs along z, its floor rising up-valley to the north (−z). The stream
/// comes down it toward the camera (+z) in pools and small falls at x ≈ 5…8. The camp is a tarp lean-to
/// against the buttresses of a giant mossy stone oak (石栎) on a bench of the west (−x) side at the
/// origin, ~2 m above the water, with the gravel bar of the stream camp just below it to the east; the
/// gully's east wall rises steeply beyond the stream. Up-valley at z ≈ −15 a fallen giant (lying across
/// the stream) has opened a gap in the canopy (林窗).
/// State shown: the smoky fire of wet wood; red plot tape on the branches, a silver blanket spread out,
/// then the big SOS of logs and peeled trunks in the gap (var.signal, project/flag sos) and the signal
/// pyre with its column of white smoke (project/flag pyre, var.signal ≥ 70); headlamps far upslope at
/// night (var.search); cairns and footprints down the stream bank (var.route); the camp moved down to the
/// gravel bar (flag stream_camp); a drone over the stream corridor (flag drone, event drone_pass); the old
/// cattle trail with stone steps and a split-rail fence on the far bank (flag trail); a stretcher
/// (flag/project stretcher); the search team in orange with helmets, headlamps and a dog (flag rescued,
/// event rescue_team).
final class FogforestScene: ScenarioScene {
    private let noise = SK.Noise(seed: 2711)
    /// Raw terrain height at the camp bench (subtracted so the bench sits at y ≈ 0).
    private var yOff: Float = 0
    private var benchLevel: Float = 0
    /// The bench keeps a little of the natural slope (per meter in x and z).
    private var benchGrad = SIMD2<Float>(0, 0)
    private var barLevel: Float = 0
    /// The lean-to camp under the big oak, and the camp on the gravel bar by the stream (x, z).
    private let campC = SIMD2<Float>(0.9, -0.9)
    private var barC = SIMD2<Float>(5.0, -3.4)
    /// The mother tree the lean-to is built against.
    private let oakC = SIMD2<Float>(-1.5, -3.1)
    /// The canopy gap up-valley (fallen giant, SOS, drone, smoke column).
    private let gapC = SIMD2<Float>(0.4, -14.5)
    /// Default camera position (kept clear of trunks).
    private var camXZ = SIMD2<Float>(0, 0)
    private var firePos = SCNVector3Zero
    private var barFirePos = SCNVector3Zero

    private var leanTo: SCNNode?
    private var oldCamp: SCNNode?
    private var barCamp: SCNNode?
    private var wetSmoke: (SCNParticleSystem, SCNNode)?
    private var fireHalo: SCNNode?
    private var ribbons: [SCNNode] = []
    private var sos: [SCNNode] = []
    private var signalFire: SCNNode?
    private var sosExtras: SCNNode?
    private var spreadBlanket: SCNNode?
    private var pyreHeap: SCNNode?
    private var pyreFlames: (SCNParticleSystem, SCNNode)?
    private var stretcher: SCNNode?
    private var signalSmoke: (SCNParticleSystem, SCNNode)?
    private var headlamps: [SCNNode] = []
    private var cairns: [SCNNode] = []
    private var prints: [SCNNode] = []
    private var drone: SCNNode?
    private var droneBeam: SCNNode?
    private var trail: SCNNode?
    private var rescue: SCNNode?
    private var rescueAtBar = false
    private var rescueLamps: [SCNNode] = []
    private var lichenMat: SCNMaterial?
    private var fireGlow: SCNLight?
    /// Glow sprites that only show after dark.
    private var nightGlows: [SCNNode] = []
    /// Points along the camp oak's low limb (tape gets tied there too).
    private var oakLimb: [V3] = []
    private var mist: [SCNNode] = []
    private var mistKey = ""
    private var mistSky: NSImage?

    required init() {
        super.init()
        skyStyle = .overcast
        sunPeak = 46                 // ~24°N in November
        sunAzimuth = 190
        exposure = 0.1
        sunScale = 0.5               // the canopy takes most of the direct light
        iblScale = 1.15
        hazeColor = SK.rgb(0xB3BCB4)  // milky, faintly green fog
        stormColor = SK.rgb(0x9DA7A0)
        nightColor = SK.rgb(0x080B0A)
        clearVisibility = 220
        precipKind = .rain
        weatherArea = 36
        weatherCenter = SCNVector3(2, 13, -3)
        cameraTarget = SCNVector3(2.6, 0.8, -2.0)
        cameraDistance = 10.5
        cameraYaw = 6
        cameraPitch = 4.5
        cameraFOV = 46
        minPitch = -4
        cameraNode.camera?.contrast = 0.22
        cameraNode.camera?.saturation = 1.0
        yOff = rawHeight(campC.x, campC.y)
        benchLevel = 0
        let gx = (rawHeight(campC.x + 1, campC.y) - rawHeight(campC.x - 1, campC.y)) / 2
        let gz = (rawHeight(campC.x, campC.y + 1) - rawHeight(campC.x, campC.y - 1)) / 2
        benchGrad = SIMD2(gx, gz) * 0.3
        barC = SIMD2(streamX(barC.y) - 1.95, barC.y)
        barLevel = bed(barC.y) + 0.62 - yOff
        let yaw = Float(cameraYaw) * .pi / 180, pitch = Float(cameraPitch) * .pi / 180
        let d = Float(cameraDistance)
        camXZ = SIMD2(Float(cameraTarget.x) + sin(yaw) * cos(pitch) * d, Float(cameraTarget.z) + cos(yaw) * cos(pitch) * d)
    }

    // MARK: Terrain

    /// The stream's centerline (x) at z.
    func streamX(_ z: Float) -> Float { 6.7 + 1.3 * sin(z * 0.08 + 0.3) + 0.45 * sin(z * 0.23 + 1.4) }

    /// The gully floor along z: rising up-valley, steeper the further up.
    private func axis(_ z: Float) -> Float {
        z < 0 ? -0.13 * z + 0.0042 * z * z : -0.13 * z - 0.002 * z * z
    }

    /// The stream bed: pools and small falls (a step every ~4 m, higher where the gully is steeper).
    private func bed(_ z: Float) -> Float {
        let L: Float = 4.3, o: Float = 1.6
        let u = (z + o) / L
        let f = u - floor(u)
        let zq = L * (floor(u) + 0.3 * f + 0.7 * SK.smoothstep(0.80, 0.97, f)) - o
        return axis(zq) - 0.55
    }

    /// Where the falls are (the lip of each step), up-valley first.
    private func fallZs() -> [Float] {
        let L: Float = 4.3, o: Float = 1.6
        return stride(from: -11, through: 4, by: 1).map { Float($0) * L + 0.885 * L - o }.filter { $0 > -46 && $0 < 9 }
    }

    /// Ground height at (x, z) before the camp bench and the gravel bar are levelled.
    private func rawHeight(_ x: Float, _ z: Float) -> Float {
        let d = x - streamX(z)
        let a = abs(d)
        // valley sides: the west side (camp) climbs ~36 %, the gully's east wall ~65 %
        var side: Float
        if d < 0 {
            side = 0.36 * a + 0.011 * a * a * SK.smoothstep(5, 28, a)
        } else {
            side = 0.66 * a + 0.014 * a * a
        }
        side *= SK.smoothstep(0.4, 2.6, a)            // the gully floor rounds off by the water
        // near the water the floor follows the stream's steps, further out the smooth axis
        let near = 1 - SK.smoothstep(2.2, 6.5, a)
        var h = axis(z) * (1 - near) + (bed(z) + 0.55) * near + side
        // the channel
        let w: Float = 1.25 + 0.35 * noise.value(z * 0.31, 7.7)
        if a < w {
            let t = 1 - (a / w) * (a / w)
            h -= 0.62 * t * t
        }
        // rolling ground, root mounds and hollows, fine roughness (calm near the water)
        let off = SK.smoothstep(1.4, 3.5, a)
        h += (noise.fbm(x / 21 + 3, z / 21, octaves: 3) - 0.5) * 3.2 * SK.smoothstep(3, 14, a)
        h += (noise.fbm(x / 4.6, z / 4.6 + 9, octaves: 3) - 0.5) * 0.7 * off
        h += (noise.fbm(x / 1.2 + 4, z / 1.2, octaves: 2) - 0.5) * 0.14 * off
        return h
    }

    /// Ground height (scene units) at (x, z).
    private func height(_ x: Float, _ z: Float) -> Float {
        var h = rawHeight(x, z) - yOff
        // the camp bench: soil banked up against the oak's buttresses, levelled a little more by hand
        let dc = simd_length((SIMD2(x, z) - campC) * SIMD2(x > campC.x ? 1.05 : 0.8, 1.0))
        let k = 1 - SK.smoothstep(2.7, 6.0, dc)
        if k > 0 {
            let flat = benchLevel + simd_dot(benchGrad, SIMD2(x, z) - campC)
            h = h * (1 - k) + flat * k
        }
        // the gravel bar by the stream, just above the water
        let db = simd_length((SIMD2(x, z) - barC) * SIMD2(1, 0.7))
        let kb = 1 - SK.smoothstep(1.3, 2.2, db)
        if kb > 0 {
            let flat = barLevel + 0.04 * (barC.x - x) + 0.03 * (barC.y - z)
            h = h * (1 - kb) + flat * kb
        }
        return h
    }

    private func gy(_ x: Float, _ z: Float) -> Float { height(x, z) }
    /// Water surface height in the channel at z.
    private func waterY(_ z: Float) -> Float { bed(z) - yOff - 0.62 + 0.55 + 0.2 }

    /// A height field over a rectangle, vertex colors from `color(x, y, z)`.
    private func heightField(x0: Float, x1: Float, z0: Float, z1: Float, cell: Float,
                             height: (Float, Float) -> Float, color: (Float, Float, Float) -> V3,
                             material: SCNMaterial) -> SCNNode {
        let nx = Int(((x1 - x0) / cell).rounded()), nz = Int(((z1 - z0) / cell).rounded())
        var pts: [V3] = [], cols: [V3] = [], uvs: [CGPoint] = []
        pts.reserveCapacity((nx + 1) * (nz + 1))
        cols.reserveCapacity((nx + 1) * (nz + 1))
        uvs.reserveCapacity((nx + 1) * (nz + 1))
        for j in 0...nz {
            for i in 0...nx {
                let x = x0 + Float(i) * cell, z = z0 + Float(j) * cell
                let y = height(x, z)
                pts.append(V3(x, y, z))
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
        buildTerrain()
        buildStream()
        buildForest()
        buildUnderstory()
        buildGroundCover()
        buildLogsAndRocks()
        buildMist()
        buildCamp()
        buildBarCamp()
        buildSignals()
        buildSearch()
        buildRoute()
        buildDrone()
        buildTrail()
        // a small, smoky fire of wet wood in front of the lean-to (it goes down to the bar with the camp)
        let fire = addFire(at: firePos, scale: 0.62)
        // wet wood burns low: a dimmer, redder light that doesn't reach far into the trees
        fire.childNodes.first(where: { $0 is SK.FlickerLight })?.light?.attenuationEndDistance = 8.5
        let holder = SCNNode()
        holder.position = SCNVector3(0, 0.55, 0)
        fire.addChildNode(holder)
        wetSmoke = (SK.smoke(scale: 0.75, color: NSColor(white: 0.8, alpha: 0.3)), holder)
        // the firelight caught in the fog around it after dark
        let glow = halo(4.0, SK.rgb(0xFF8A3A), intensity: 0.5)
        glow.position = SCNVector3(0, 0.8, 0)
        fire.addChildNode(glow)
        fireHalo = glow
        fireGlow = fire.childNodes.first(where: { $0 is SK.FlickerLight })?.light
    }

    // MARK: Ground and stream

    private func buildTerrain() {
        // brown leaf litter on the level, dark mossy soil and rock on the steep cuts (per pixel)
        let groundMat = SK.terrainMaterial(flat: SK.rgb(0x4E4030), steep: SK.rgb(0x434730), from: 0.45, to: 0.72,
                                           grain: 0.5, noiseScale: 0.3, roughness: 0.88)
        SK.addGrain(groundMat, scale: 12, strength: 3, intensity: 0.45, seed: 13)
        let color: (Float, Float, Float) -> V3 = { x, _, z in
            // moss patches, wet dark ground by the water, paler where the gap lets light in
            let m = SK.smoothstep(0.52, 0.68, self.noise.fbm(x / 3.1 + 11, z / 3.1, octaves: 3))
            var c = V3(1.0, 0.93, 0.8) + (V3(0.72, 1.45, 0.62) - V3(1.0, 0.93, 0.8)) * m
            let a = abs(x - self.streamX(z))
            c *= 0.62 + 0.38 * SK.smoothstep(0.9, 3.2, a)
            c *= 0.84 + 0.32 * self.noise.value(x * 0.8, z * 0.8)
            let g = simd_length(SIMD2(x, z) - self.gapC)
            c *= 1 + 0.18 * (1 - SK.smoothstep(3, 9, g))
            return c
        }
        world.addChildNode(heightField(x0: -24, x1: 30, z0: -40, z1: 18, cell: 0.3,
                                       height: { self.height($0, $1) }, color: color, material: groundMat))
        // the rest of the valley, coarser, tucked under the near ground
        let farMat = SK.terrainMaterial(flat: SK.rgb(0x544937), steep: SK.rgb(0x474A35), from: 0.45, to: 0.72,
                                        grain: 0.2, noiseScale: 0.12, roughness: 0.9)
        let far = SK.terrain(size: 420, segments: 210, height: { x, z in
            let inside = SK.smoothstep(-24, -22.5, x) * (1 - SK.smoothstep(28.5, 30, x)) * SK.smoothstep(-40, -38.5, z) * (1 - SK.smoothstep(16.5, 18, z))
            return self.height(x, z) - 1.6 * inside
        }, color: { x, _, z, _ in
            let k = 0.85 + 0.3 * self.noise.value(x * 0.21, z * 0.21)
            return V3(k, k, k * 0.96)
        }, material: farMat, uvRepeat: 105)
        world.addChildNode(far)
    }

    /// Foam in the falls and the pools below them (0…1).
    private func foam(_ z: Float) -> Float {
        func slope(_ z: Float) -> Float { (bed(z - 0.06) - bed(z + 0.06)) / 0.12 }
        let fall = SK.smoothstep(0.25, 0.9, slope(z))
        let below = max(SK.smoothstep(0.3, 0.9, slope(z - 0.5)), 0.7 * SK.smoothstep(0.3, 0.9, slope(z - 1.0)))
        return max(fall, below * 0.85)
    }

    private func buildStream() {
        // the water: one ribbon down the channel, dark and glossy, white where it falls
        var w = FogMesh()
        var z: Float = -62
        var rows = 0
        while z <= 20 {
            let sx = streamX(z)
            let width: Float = (1.25 + 0.35 * noise.value(z * 0.31, 7.7)) * 0.56
            let y = waterY(z)
            let f = foam(z)
            for k in 0...4 {
                let u = Float(k) / 4 * 2 - 1
                // a little crown across the falls
                let lift = f * 0.05 * (1 - u * u)
                w.pts.append(V3(sx + u * width, y + lift, z))
                w.cols.append(V3(f, 0.5, 0))
                w.uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(z)))
            }
            rows += 1
            z += 0.2
        }
        for r in 0..<UInt32(rows - 1) {
            for k in 0..<UInt32(4) {
                let a = r * 5 + k, b = a + 1, c = a + 5, d = c + 1
                w.idx += [a, c, b, b, c, d]
            }
        }
        let water = SK.mat(SK.rgb(0x1F2722), roughness: 0.06)
        water.shaderModifiers = [.surface: """
        #pragma arguments
        float4 waterColor;
        float4 foamColor;

        #pragma declaration
        float ws_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
        float ws_noise(float3 x) {
            float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
            return mix(mix(mix(ws_hash(i + float3(0,0,0)), ws_hash(i + float3(1,0,0)), f.x),
                           mix(ws_hash(i + float3(0,1,0)), ws_hash(i + float3(1,1,0)), f.x), f.y),
                       mix(mix(ws_hash(i + float3(0,0,1)), ws_hash(i + float3(1,0,1)), f.x),
                           mix(ws_hash(i + float3(0,1,1)), ws_hash(i + float3(1,1,1)), f.x), f.y), f.z);
        }

        #pragma body
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float t = scn_frame.time;
        float foamK = _surface.diffuse.r;
        // streaks drawn downstream (+z), faster in the falls
        float sp = 1.2 + 2.2 * foamK;
        float s1 = ws_noise(float3(wp.x * 5.0, wp.y * 2.0, wp.z * 1.3 - t * sp));
        float s2 = ws_noise(float3(wp.x * 13.0, wp.y * 4.0, wp.z * 3.1 - t * sp * 1.4));
        float streak = s1 * 0.6 + s2 * 0.4;
        float f = smoothstep(0.32, 0.72, foamK + (streak - 0.5) * 0.9);
        // ripples: tilt the normal by the streak pattern
        float dx = ws_noise(float3(wp.x * 7.0 + 0.4, 0.0, wp.z * 2.4 - t * sp)) - 0.5;
        float dz = ws_noise(float3(wp.x * 7.0, 3.0, wp.z * 2.4 + 0.4 - t * sp)) - 0.5;
        float3 nw = normalize(float3(dx * 0.5, 1.0, dz * 0.5));
        _surface.normal = normalize((scn_frame.viewTransform * float4(nw, 0.0)).xyz);
        _surface.diffuse.rgb = mix(waterColor.rgb * (0.75 + 0.5 * streak), foamColor.rgb * (0.82 + 0.18 * s2), f);
        _surface.roughness = mix(0.05, 0.55, f);
        """]
        water.setValue(NSValue(scnVector4: SK.linear(SK.rgb(0x1E2721))), forKey: "waterColor")
        water.setValue(NSValue(scnVector4: SK.linear(SK.rgb(0xDCE3E0))), forKey: "foamColor")
        world.addChildNode(w.node(water))

        // spray drifting off the bigger falls in view
        for zf in fallZs() where zf > -26 && zf < 6 {
            let spray = SK.smoke(scale: 0.22, color: NSColor(white: 0.92, alpha: 0.06))
            spray.birthRate = 2
            spray.particleLifeSpan = 2.5
            spray.particleVelocity = 0.25
            spray.acceleration = SCNVector3(0, 0.05, 0.1)
            let n = SCNNode()
            n.position = SCNVector3(CGFloat(streamX(zf + 0.5)), CGFloat(waterY(zf + 0.6) + 0.15), CGFloat(zf + 0.6))
            n.addParticleSystem(spray)
            world.addChildNode(n)
        }
    }

    // MARK: Forest

    /// Keeps trees off the camp, the bar, the water, the gap, the trail and the camera's line of sight.
    private func free(_ x: Float, _ z: Float, _ r: Float, gap: Bool = true) -> Bool {
        let p = SIMD2(x, z)
        if simd_length(p - campC) < 3.9 + r { return false }
        if simd_length(p - barC) < 2.6 + r { return false }
        if abs(x - streamX(z)) < 1.5 + r { return false }
        if gap && simd_length(p - gapC) < 7.0 + r { return false }
        if x > -9.6 - r && x < 6.0 + r && z > -16.2 - r && z < -8.6 + r { return false }      // the SOS
        if z > -36 && z < 7.5 && abs(x - trailX(z)) < 0.7 + r { return false }
        // the line of sight from the default camera to the camp
        let a = camXZ, b = SIMD2(Float(cameraTarget.x), Float(cameraTarget.z))
        let ab = b - a
        let t = max(0, min(1, simd_dot(p - a, ab) / simd_dot(ab, ab)))
        if simd_length(p - (a + ab * t)) < 1.6 + r + 1.4 * t { return false }
        return simd_length(p - a) > 2.5 + r
    }

    /// The old herders' trail on the far bank (x at z), climbing up-valley across the gully's east wall.
    private func trailX(_ z: Float) -> Float { streamX(z) + 1.9 + (7 - z) * 0.16 }

    private struct Tree {
        var x: Float, z: Float, r: Float, h: Float, buttresses: Int, moss: Float, lean: SIMD2<Float>
        var seed: Float
    }

    /// The trunk of a forest tree: a slightly bent tube with an irregular, buttressed cross-section,
    /// sunk into the ground. Returns the axis (centers and radii) for the limbs.
    private func trunk(_ m: inout FogMesh, _ t: Tree, base y0: Float, segs: Int, rings: [Float]) -> ([V3], [Float]) {
        var rr = FogRng(UInt64(t.seed * 977) + 17)
        var bt: [(Float, Float)] = []
        for k in 0..<t.buttresses {
            bt.append((Float(k) / Float(max(1, t.buttresses)) * 2 * .pi + rr.r(-0.45, 0.45), rr.r(0.45, 1.0)))
        }
        var centers: [V3] = [], radii: [Float] = [], cols: [V3] = [], hs: [Float] = []
        for y in rings where y < t.h * 0.97 { hs.append(y) }
        hs.append(t.h)
        for y in hs {
            let k = max(0, y) / t.h
            let bend = V3(t.lean.x * k * k * t.h, 0, t.lean.y * k * k * t.h)
            let wob = V3(noise.value(t.seed + y * 0.13, 3) - 0.5, 0, noise.value(t.seed + y * 0.13, 9) - 0.5) * (t.r * 0.9 * k)
            centers.append(V3(t.x, y0 + y, t.z) + bend + wob)
            radii.append(t.r * (1 - 0.62 * pow(k, 0.85)) * (1 + 0.16 * exp(-max(0, y) / 1.1)))
            let moss = t.moss * (0.42 + 0.52 * exp(-max(0, y) / 2.4))
            cols.append(V3(moss, 0.42 + 0.16 * noise.value(t.seed, y * 0.3), 0.3 + 0.35 * k))
        }
        let seed = t.seed
        let flare: (Int, Int) -> Float = { i, j in
            let y = max(0, hs[i])
            let th = Float(j) / Float(segs) * 2 * .pi
            var e: Float = 0
            for (a, s) in bt {
                var d = abs(th - a).truncatingRemainder(dividingBy: 2 * .pi)
                if d > .pi { d = 2 * .pi - d }
                e += s * 1.35 * exp(-(d / 0.36) * (d / 0.36)) * exp(-y / (0.55 + 0.75 * s))
            }
            let n = self.noise.value(cos(th) * 1.4 + seed, sin(th) * 1.4 + y * 0.45) - 0.5
            return 1 + e + 0.16 * n
        }
        m.limb(centers, radii, cols, segs: segs, wobble: flare)
        return (centers, radii)
    }

    private func buildForest() {
        var wood = FogMesh(), woodFar = FogMesh()
        var crown = FogMesh()
        var beard = FogMesh()
        var epi = FogMesh()
        var rr = FogRng(91)
        // the big ones placed by hand: the camp oak and the giants that frame the view
        var trees: [Tree] = [
            Tree(x: oakC.x, z: oakC.y, r: 1.15, h: 27, buttresses: 5, moss: 1.0, lean: SIMD2(0.02, -0.03), seed: 1.3),
            Tree(x: -4.2, z: 4.6, r: 0.95, h: 25, buttresses: 4, moss: 0.95, lean: SIMD2(0.03, 0.02), seed: 2.7),
            Tree(x: 9.0, z: 0.6, r: 0.85, h: 24, buttresses: 3, moss: 0.9, lean: SIMD2(-0.06, 0), seed: 3.1),
            Tree(x: 8.9, z: -10.5, r: 1.05, h: 27, buttresses: 4, moss: 0.95, lean: SIMD2(-0.03, 0.01), seed: 4.4),
            Tree(x: -6.4, z: -13.5, r: 1.35, h: 30, buttresses: 5, moss: 1.0, lean: SIMD2(0.02, 0.0), seed: 5.9),
            Tree(x: 6.9, z: -26, r: 1.1, h: 28, buttresses: 4, moss: 0.9, lean: SIMD2(0, 0.02), seed: 6.2),
            Tree(x: -2.6, z: -30, r: 1.5, h: 32, buttresses: 5, moss: 1.0, lean: SIMD2(0.01, 0.02), seed: 7.7),
            Tree(x: 13.5, z: -31, r: 1.2, h: 28, buttresses: 4, moss: 0.9, lean: SIMD2(-0.02, 0), seed: 8.1),
            Tree(x: -12, z: -5.5, r: 1.1, h: 26, buttresses: 4, moss: 0.95, lean: SIMD2(0.03, 0), seed: 9.3),
            Tree(x: -14, z: -24, r: 1.3, h: 30, buttresses: 5, moss: 1.0, lean: SIMD2(0, 0), seed: 10.6),
            Tree(x: -0.4, z: -46, r: 1.4, h: 30, buttresses: 4, moss: 1.0, lean: SIMD2(0, 0), seed: 11.2)
        ]
        let placed = trees
        // the rest of the forest: a jittered grid, thinned in patches, a giant here and there
        var gz: Float = -96
        while gz < 24 {
            var gx: Float = -52
            while gx < 58 {
                let x = gx + rr.r(-1.9, 1.9), z = gz + rr.r(-1.9, 1.9)
                gx += 4.4
                if noise.fbm(x / 17 + 40, z / 17, octaves: 2) < 0.36 { continue }
                let giant = rr.next() < 0.07
                let r: Float = giant ? rr.r(0.9, 1.4) : (rr.next() < 0.5 ? rr.r(0.16, 0.32) : rr.r(0.3, 0.6))
                guard free(x, z, r) else { continue }
                if placed.contains(where: { simd_length(SIMD2($0.x - x, $0.z - z)) < $0.r + r + 2.2 }) { continue }
                let h: Float = giant ? rr.r(25, 32) : 9 + r * 26 + rr.r(-2, 3)
                trees.append(Tree(x: x, z: z, r: r, h: h, buttresses: giant ? 4 : (r > 0.4 ? 3 : 0), moss: rr.r(0.55, 1.0),
                                  lean: SIMD2(rr.r(-0.05, 0.05), rr.r(-0.05, 0.05)), seed: Float(trees.count) * 1.37 + 0.5))
            }
            gz += 4.4
        }
        let bigRings: [Float] = [-0.9, 0, 0.12, 0.3, 0.55, 0.9, 1.4, 2.1, 3.0, 4.2, 5.8, 8, 11, 15, 20, 26]
        let midRings: [Float] = [-0.7, 0, 0.35, 1.0, 2.5, 5, 9, 14, 20]
        let farRings: [Float] = [-0.6, 0, 1.5, 6, 13]
        for t in trees {
            let dist = simd_length(SIMD2(t.x, t.z) - camXZ)
            let near = dist < 34
            let y0 = minGround(t.x, t.z, t.r * (t.buttresses > 0 ? 1.6 : 1))
            let segs = t.r > 0.8 ? (dist < 25 ? 22 : 14) : (near ? 9 : 6)
            let rings = t.r > 0.8 ? bigRings : (near ? midRings : farRings)
            let axisPts = near || t.r > 0.8 ? trunk(&wood, t, base: y0, segs: segs, rings: rings) : trunk(&woodFar, t, base: y0, segs: segs, rings: rings)
            limbs(t, axis: axisPts, near: near, wood: &wood, woodFar: &woodFar, crown: &crown, beard: &beard, epi: &epi, rng: &rr)
        }
        let bark = mossMaterial(bark: SK.rgb(0x5C564C), moss: SK.rgb(0x66872D), pale: SK.rgb(0xA7AC98))
        world.addChildNode(wood.node(bark, shadow: true))
        world.addChildNode(woodFar.node(bark))
        let leaves = leafMaterial(roughness: 0.85)
        world.addChildNode(crown.node(leaves))
        let lichen = leafMaterial(roughness: 0.95)
        lichen.emission.contents = SK.rgb(0x5A6152)
        lichenMat = lichen
        world.addChildNode(beard.node(lichen))
        world.addChildNode(epi.node(leaves))
    }

    /// Lowest ground under a footprint (so trunks never float on a slope).
    private func minGround(_ x: Float, _ z: Float, _ r: Float) -> Float {
        var y = gy(x, z)
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            y = min(y, gy(x + cos(a) * r, z + sin(a) * r))
        }
        return y
    }

    /// Limbs, hanging lichen and the crown of a tree.
    private func limbs(_ t: Tree, axis: ([V3], [Float]), near: Bool, wood: inout FogMesh, woodFar: inout FogMesh,
                       crown: inout FogMesh, beard: inout FogMesh, epi: inout FogMesh, rng rr: inout FogRng) {
        let (cs, rs) = axis
        let top = cs[cs.count - 1]
        let big = t.r > 0.8
        let count = big ? 5 : (t.r > 0.3 ? 3 : 2)
        let leafCol = fogLin(0x2F3D24) * rr.r(0.8, 1.15)
        func radiusAt(_ y: Float) -> (V3, Float) {
            // the axis point and radius at height y
            for i in 1..<cs.count where cs[i].y >= y {
                let k = (y - cs[i - 1].y) / max(0.01, cs[i].y - cs[i - 1].y)
                return (cs[i - 1] + (cs[i] - cs[i - 1]) * k, rs[i - 1] + (rs[i] - rs[i - 1]) * k)
            }
            return (top, rs[rs.count - 1])
        }
        for k in 0..<count {
            // the camp oak has one great low limb reaching out over the lean-to
            let low = t.seed == 1.3 && k == 0
            let yb = low ? 4.4 : t.h * rr.r(0.45, 0.78) + cs[0].y + 0.9
            let (p0, r0) = radiusAt(yb)
            let a: Float = low ? 0.35 : Float(k) / Float(count) * 2 * .pi + rr.r(-0.5, 0.5)
            let el: Float = low ? 1.28 : rr.r(0.55, 1.05)          // from vertical
            let len: Float = low ? 7.5 : t.h * (big ? rr.r(0.22, 0.32) : rr.r(0.18, 0.28))
            let dir = V3(cos(a) * sin(el), cos(el), sin(a) * sin(el))
            var pts: [V3] = [], rad: [Float] = [], col: [V3] = []
            let n = big ? 6 : 4
            for i in 0...n {
                let s = Float(i) / Float(n)
                let rise: Float = low ? (s < 0.6 ? -0.25 * s : -0.15 + 0.9 * (s - 0.6)) : 0.12 * s * s
                pts.append(p0 + dir * (len * s) + V3(0, rise * len, 0) + V3(noise.value(t.seed + s * 3, 5) - 0.5, 0, noise.value(t.seed + s * 3, 8) - 0.5) * (len * 0.12 * s))
                rad.append(max(0.03, r0 * (low ? 0.42 : 0.5) * (1 - 0.72 * s)))
                col.append(V3(t.moss * (low ? 0.95 : 0.8), 0.45, 0.6))
            }
            if near || big { wood.limb(pts, rad, col, segs: big ? 8 : 5) } else { woodFar.limb(pts, rad, col, segs: 4) }
            if low { oakLimb = zip(pts, rad).map { $0.0 - V3(0, $0.1 * 0.9, 0) } }
            // a fork near the end, and the leaves at the tips
            let fork = pts[n - 1]
            let fa = a + rr.r(0.6, 1.2) * (rr.next() < 0.5 ? -1 : 1)
            let fdir = fogUnit(V3(cos(fa) * 0.8, 0.6, sin(fa) * 0.8))
            let fend = fork + fdir * (len * 0.45)
            if near || big { wood.tube(fork, fend, rad[n - 1] * 0.8, 0.03, col[n - 1], segs: 4) }
            for tip in [pts[n], fend] {
                let cr = big ? rr.r(1.8, 2.8) : rr.r(1.0, 1.9) + t.r
                crown.blob(tip + V3(0, cr * 0.25, 0), V3(cr, cr * 0.55, cr * 0.9), leafCol, noise, seed: tip.x + tip.z,
                           jitter: 0.3, rings: near ? 5 : 3, segs: near ? 8 : 6, under: 0.45, vary: 0.35, yaw: rr.r(0, 3))
            }
            // hanging lichen (松萝) and moss curtains along the limb's underside
            if near {
                var s: Float = 0.15
                while s < 0.95 {
                    let i = min(n - 1, Int(s * Float(n)))
                    let f = s * Float(n) - Float(i)
                    let p = pts[i] + (pts[i + 1] - pts[i]) * f - V3(0, rad[i] * 0.8, 0)
                    hangBeard(&beard, from: p, length: rr.r(0.35, low ? 1.6 : 1.2), rng: &rr)
                    s += low ? rr.r(0.035, 0.07) : rr.r(0.06, 0.13)
                }
                // ferns and moss cushions on top of the bigger limbs, near the trunk
                if big && rr.next() < 0.8 {
                    let p = pts[1] + V3(0, rad[1] * 0.9, 0)
                    fernClump(&epi, at: p, size: rr.r(0.45, 0.75), fronds: 7, seed: p.x * 3 + p.z, color: fogLin(0x4A6A2A))
                }
            }
        }
        // the crown on top of the trunk
        let cr = big ? rr.r(3.0, 4.2) : rr.r(1.4, 2.4) + t.r * 2
        crown.blob(top + V3(0, cr * 0.2, 0), V3(cr, cr * 0.62, cr), leafCol, noise, seed: top.x - top.z,
                   jitter: 0.3, rings: near ? 5 : 3, segs: near ? 8 : 6, under: 0.45, vary: 0.35)
        // epiphyte ferns and lichen tufts on the lower trunk of the near giants
        if big && near {
            for k in 0..<5 {
                let y = cs[0].y + 2.2 + Float(k) * 1.7 + rr.r(-0.4, 0.4)
                let (p, r) = radiusAt(y)
                let a = rr.r(0, 6.28)
                let out = V3(cos(a), 0, sin(a))
                fernClump(&epi, at: p + out * (r * 1.02), size: rr.r(0.35, 0.6), fronds: 6, seed: y + t.seed, color: fogLin(0x51702C), lean: out)
            }
        }
    }

    /// A beard of hanging lichen: a few thin strands of different lengths.
    private func hangBeard(_ m: inout FogMesh, from p: V3, length: Float, rng rr: inout FogRng) {
        let usnea = rr.next() < 0.85
        let base = usnea ? fogLin(0xB7C0A6) : fogLin(0x7C8150)
        let strands = 5
        for _ in 0..<strands {
            let a = rr.r(0, 6.28)
            let side = V3(cos(a), 0, sin(a))
            let l = length * rr.r(0.45, 1.0)
            let sway = V3(rr.r(-0.06, 0.06), 0, rr.r(-0.06, 0.06))
            let off = side * rr.r(0, 0.05)
            let c = [p + off, p + off + V3(0, -l * 0.5, 0) + sway * 0.5, p + off + V3(0, -l, 0) + sway]
            let w: [Float] = [0.022, 0.016, 0.004]
            let col = base * rr.r(0.85, 1.12)
            m.strip(c, w, side: V3(-side.z, 0, side.x), fold: 0, [col, col * 0.95, col * 0.85])
        }
    }

    /// A spray of small leathery leaves around a twig tip.
    private func leafSpray(_ m: inout FogMesh, at c: V3, radius: Float, count: Int, color: V3, seed: Float) {
        var rr = FogRng(UInt64(abs(seed) * 733) + 11)
        for _ in 0..<count {
            let d = fogUnit(V3(rr.r(-1, 1), rr.r(-0.5, 0.7), rr.r(-1, 1)))
            let p = c + d * (radius * rr.r(0.2, 1.0))
            let l = rr.r(0.12, 0.2)
            let dir = fogUnit(d + V3(0, -0.5, 0))
            let side = fogUnit(SK.cross(dir, V3(0, 1, 0)))
            let col = color * rr.r(0.75, 1.25)
            m.strip([p, p + dir * (l * 0.5), p + dir * l], [0.004, l * 0.24, 0.003], side: side, fold: 0.25, [col * 0.9, col, col * 1.1])
        }
    }

    /// A rosette of fern fronds (on the ground, on limbs, on trunks when `lean` points outward).
    private func fernClump(_ m: inout FogMesh, at p: V3, size: Float, fronds: Int, seed: Float, color: V3, lean: V3 = V3(0, 0, 0)) {
        var rr = FogRng(UInt64(abs(seed) * 1301) + 7)
        for f in 0..<fronds {
            let a = Float(f) / Float(fronds) * 2 * .pi + rr.r(-0.3, 0.3)
            let out = fogUnit(V3(cos(a), 0, sin(a)) + lean * 0.8)
            let len = size * rr.r(0.75, 1.15)
            let rise = rr.r(0.7, 1.15)
            var c: [V3] = [], w: [Float] = [], col: [V3] = []
            let n = 6
            for i in 0...n {
                let s = Float(i) / Float(n)
                // up and out, the tip arching over
                c.append(p + out * (len * s) + V3(0, len * (rise * s - 1.15 * s * s), 0))
                let edge = (i % 2 == 0) ? 1.0 : 0.72                     // a hint of the pinnae
                w.append(len * 0.16 * pow(sin(.pi * min(1, s * 1.08 + 0.04)), 0.7) * Float(edge) + 0.004)
                col.append(color * (0.72 + 0.45 * s) * rr.r(0.9, 1.1))
            }
            m.strip(c, w, side: V3(-out.z, 0, out.x), fold: 0.35, col)
        }
    }

    // MARK: Understory

    /// Twig tips where the flagging tape gets tied (position, facing).
    private var ribbonSpots: [(V3, Float)] = []

    private func buildUnderstory() {
        var ferns = FogMesh(), bamboo = FogMesh(), bambooLeaves = FogMesh(), stems = FogMesh(), shrubs = FogMesh()
        var rr = FogRng(404)
        let fernGreen = fogLin(0x4C6B2B), fernPale = fogLin(0x6B8236), fernRust = fogLin(0x7A6438)

        // ferns carpet the ground, thickest by the water and in the gap, thinning far off
        var placedFerns = 0
        for _ in 0..<2600 {
            let x = rr.r(-30, 34), z = rr.r(-56, 15)
            let dc = simd_length(SIMD2(x, z) - camXZ)
            if dc < 3.5 || dc > 52 { continue }
            if rr.next() > 1.1 - dc / 55 { continue }
            let d = abs(x - streamX(z))
            if d < 1.15 { continue }
            if simd_length(SIMD2(x, z) - campC) < 2.9 || simd_length(SIMD2(x, z) - barC) < 2.0 { continue }
            if x > -8.8 && x < 5.2 && z > -15.6 && z < -9.2 { continue }
            let wet = 1 - SK.smoothstep(1.5, 6, d)
            let gapK = 1 - SK.smoothstep(3, 8, simd_length(SIMD2(x, z) - gapC))
            if noise.fbm(x / 6 + 70, z / 6, octaves: 2) + 0.25 * wet + 0.2 * gapK < 0.5 { continue }
            let size = rr.r(0.4, 0.95) * (1 + 0.35 * wet) * (0.55 + 0.45 * SK.smoothstep(3.5, 9, dc))
            let col = rr.next() < 0.12 ? fernRust : (rr.next() < 0.3 ? fernPale : fernGreen)
            fernClump(&ferns, at: V3(x, gy(x, z) - 0.03, z), size: size, fronds: Int(rr.r(6, 10)), seed: x * 7 + z, color: col * rr.r(0.85, 1.1))
            placedFerns += 1
        }

        let target = SIMD2(Float(cameraTarget.x), Float(cameraTarget.z))
        for _ in 0..<160 {
            let a = rr.r(-1.1, 1.1) + atan2(target.x - camXZ.x, target.y - camXZ.y)
            let d = rr.r(4.0, 9.5)
            let x = camXZ.x + sin(a) * d, z = camXZ.y + cos(a) * d
            let ab = target - camXZ
            let t = max(0, min(1, simd_dot(SIMD2(x, z) - camXZ, ab) / simd_dot(ab, ab)))
            if simd_length(SIMD2(x, z) - (camXZ + ab * t)) < 1.3 { continue }
            if abs(x - streamX(z)) < 1.2 || simd_length(SIMD2(x, z) - campC) < 3.2 || simd_length(SIMD2(x, z) - barC) < 2.2 { continue }
            let col = rr.next() < 0.25 ? fernPale : fernGreen
            fernClump(&ferns, at: V3(x, gy(x, z) - 0.03, z), size: rr.r(0.55, 1.0), fronds: Int(rr.r(7, 11)), seed: x * 5 + z * 3, color: col * rr.r(0.85, 1.1))
        }

        // thickets of arrow bamboo (箭竹) on the slopes
        let clumps: [SIMD2<Float>] = [SIMD2(-9, -10), SIMD2(-11, 0), SIMD2(-4.5, -21), SIMD2(10, -18), SIMD2(12.5, -6),
                                      SIMD2(-16, -16), SIMD2(-8.5, -31), SIMD2(15, -24), SIMD2(-19, -4), SIMD2(5.5, -37),
                                      SIMD2(-13.5, 8), SIMD2(11.5, 7.5), SIMD2(18, -12), SIMD2(-22, -22)]
        for c in clumps {
            let count = Int(rr.r(30, 46))
            let radius = rr.r(0.7, 1.2)
            for _ in 0..<count {
                let a = rr.r(0, 6.28), rd = radius * sqrt(rr.next())
                let x = c.x + cos(a) * rd, z = c.y + sin(a) * rd
                let out = V3(cos(a), 0, sin(a)) * (0.4 + rd / radius) + V3(rr.r(-0.3, 0.3), 0, rr.r(-0.3, 0.3))
                let h = rr.r(2.2, 4.2)
                let b = V3(x, gy(x, z) - 0.1, z)
                var pts: [V3] = [], rad: [Float] = [], col: [V3] = []
                let culm = (rr.next() < 0.3 ? fogLin(0x7C7A44) : fogLin(0x5E6A38)) * rr.r(0.85, 1.15)
                for i in 0...3 {
                    let s = Float(i) / 3
                    pts.append(b + V3(0, h * s, 0) + out * (h * 0.3 * s * s))
                    rad.append(0.016 * (1 - 0.5 * s))
                    col.append(culm)
                }
                bamboo.limb(pts, rad, col, segs: 3)
                // narrow leaves in fans at the upper nodes
                for node in 0..<4 {
                    let s = 0.58 + Float(node) * 0.13
                    let p = b + V3(0, h * s, 0) + out * (h * 0.3 * s * s)
                    for _ in 0..<3 {
                        let la = rr.r(0, 6.28)
                        let ld = fogUnit(V3(cos(la), rr.r(-0.5, 0.2), sin(la)) + fogUnit(out) * 0.5)
                        let l = rr.r(0.16, 0.27)
                        let tip = p + ld * l - V3(0, l * 0.3, 0)
                        let leaf = fogLin(0x4F6B34) * rr.r(0.8, 1.2)
                        bambooLeaves.strip([p, p + ld * (l * 0.5) - V3(0, l * 0.05, 0), tip], [0.004, 0.018, 0.002],
                                           side: fogUnit(SK.cross(ld, V3(0, 1, 0))), fold: 0.2, [leaf, leaf, leaf * 0.9])
                    }
                }
            }
        }

        // tree ferns in the wet ravine
        let treeFerns: [SIMD2<Float>] = [SIMD2(2.6, -8.2), SIMD2(9.6, -4.0), SIMD2(1.4, -21), SIMD2(8.9, -16.8),
                                         SIMD2(-9.8, -9.5), SIMD2(10.4, 4.4), SIMD2(-0.9, 4.6), SIMD2(5.9, -31), SIMD2(11.2, -27)]
        for (i, p) in treeFerns.enumerated() {
            treeFern(&stems, &ferns, at: p, height: rr.r(1.4, 3.0), seed: Float(i) * 3.3 + 1)
        }

        // rhododendrons (杜鹃): twisted mossy stems leaning out, leathery leaves in clusters at the tips
        let rhodos: [SIMD2<Float>] = [SIMD2(-5.2, -6.5), SIMD2(5.2, -7.6), SIMD2(-11.5, -17.5), SIMD2(11.6, -13),
                                      SIMD2(-2.8, -24), SIMD2(-8.6, 6.8), SIMD2(14.5, -1.5), SIMD2(-17, -11)]
        for (i, p) in rhodos.enumerated() {
            let b = V3(p.x, gy(p.x, p.y) - 0.15, p.y)
            for k in 0..<Int(rr.r(3, 5)) {
                let a = Float(k) * 1.9 + rr.r(-0.4, 0.4)
                let out = V3(cos(a), 0, sin(a))
                let len = rr.r(2.6, 4.6)
                var pts: [V3] = [], rad: [Float] = [], col: [V3] = []
                for j in 0...4 {
                    let s = Float(j) / 4
                    let twist = V3(sin(s * 5 + Float(i)), 0, cos(s * 4 + Float(k))) * 0.18
                    pts.append(b + out * (len * 0.55 * s) + V3(0, len * s * (1 - 0.15 * s), 0) + twist * s)
                    rad.append(0.075 * (1 - 0.6 * s))
                    col.append(V3(0.85, 0.42, 0.55))
                }
                stems.limb(pts, rad, col, segs: 5)
                for q in 0..<3 {
                    let c = pts[4 - q / 2] + V3(rr.r(-0.35, 0.35), rr.r(0, 0.3), rr.r(-0.35, 0.35))
                    leafSpray(&shrubs, at: c, radius: rr.r(0.45, 0.7), count: 34, color: fogLin(0x2F4527), seed: c.x * 3 + c.z)
                }
            }
        }

        // saplings around the camp and on the way to the gap (the tape gets tied to their twigs)
        let saplings: [(Float, Float, Float)] = [(-2.9, 1.0, 0.6), (4.2, -3.3, 2.2), (-3.9, -1.6, 1.2), (2.2, -5.6, 2.8),
                                                 (0.4, -7.4, 1.9), (4.6, -11.0, 2.5), (-1.8, -6.8, 0.9), (5.9, -8.6, 2.0),
                                                 (-4.6, 3.4, 0.4), (10.2, 2.4, 2.9), (5.0, -19.6, 1.1), (-8.2, -15.5, 0.3)]
        for (i, s) in saplings.enumerated() {
            let b = V3(s.0, gy(s.0, s.1) - 0.1, s.1)
            let h = rr.r(3.2, 5.2)
            let lean = V3(rr.r(-0.25, 0.25), 0, rr.r(-0.25, 0.25))
            stems.limb([b, b + V3(0, h * 0.5, 0) + lean * 0.4, b + V3(0, h, 0) + lean], [0.05, 0.035, 0.012],
                       [V3(0.7, 0.5, 0.5), V3(0.6, 0.5, 0.6), V3(0.5, 0.5, 0.6)], segs: 5)
            // the twig for the tape
            let ty = rr.r(1.7, 2.2)
            let p = b + V3(0, ty, 0) + lean * (ty / h * 0.8)
            let dir = V3(cos(s.2), 0.25, sin(s.2))
            let tip = p + dir * 0.55
            stems.tube(p, tip, 0.016, 0.006, V3(0.5, 0.5, 0.5), segs: 3)
            ribbonSpots.append((tip - dir * 0.12, s.2))
            // sprays of leathery leaves on the upper twigs
            for k in 0..<4 {
                let c = b + V3(0, h * (0.62 + 0.11 * Float(k)), 0) + lean * 0.9 + V3(rr.r(-0.35, 0.35), 0, rr.r(-0.35, 0.35))
                stems.tube(b + V3(0, h * (0.55 + 0.11 * Float(k)), 0) + lean * 0.8, c, 0.012, 0.005, V3(0.5, 0.5, 0.5), segs: 3)
                leafSpray(&shrubs, at: c, radius: rr.r(0.25, 0.4), count: 14, color: fogLin(0x3A5130), seed: Float(i * 5 + k))
            }
        }

        let leaves = leafMaterial(roughness: 0.8)
        world.addChildNode(ferns.node(leaves))
        world.addChildNode(bamboo.node(leafMaterial(roughness: 0.6, doubleSided: false)))
        world.addChildNode(bambooLeaves.node(leaves))
        world.addChildNode(shrubs.node(leaves))
        world.addChildNode(stems.node(mossMaterial(bark: SK.rgb(0x5E554A), moss: SK.rgb(0x5A7430), pale: SK.rgb(0xA3A994), scale: 2.2), shadow: true))
    }

    /// What lies on the forest floor near the camera: the oak's surface roots, fallen twigs and leaves,
    /// moss cushions and seedlings.
    private func buildGroundCover() {
        var roots = FogMesh(), twigs = FogMesh(), leaves = FogMesh(), moss = FogMesh(), seedlings = FogMesh()
        var rr = FogRng(1201)
        // surface roots snaking out from the oak's buttresses across the bench, half buried
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + rr.r(-0.25, 0.25)
            let len = rr.r(2.4, 4.6)
            var pts: [V3] = [], rad: [Float] = [], col: [V3] = []
            var p = oakC + SIMD2(cos(a), sin(a)) * 1.4
            var dir = SIMD2(cos(a), sin(a))
            let n = 9
            for i in 0...n {
                let t = Float(i) / Float(n)
                let r = 0.16 * (1 - 0.8 * t) + 0.02
                pts.append(V3(p.x, gy(p.x, p.y) + r * 0.25, p.y))
                rad.append(r)
                col.append(V3(0.9, 0.42, 0.4))
                let turn = (noise.value(Float(k) * 3 + t * 4, 1.7) - 0.5) * 0.9
                dir = SIMD2(dir.x * cos(turn) - dir.y * sin(turn), dir.x * sin(turn) + dir.y * cos(turn))
                p += dir * (len / Float(n))
            }
            roots.limb(pts, rad, col, segs: 6)
        }
        // twigs and fallen leaves, densest near the camera, none in the water
        for _ in 0..<1700 {
            let a = rr.r(0, 6.28), d = 1.5 + 13 * pow(rr.next(), 1.4)
            let x = camXZ.x + cos(a) * d, z = camXZ.y + sin(a) * d - 3
            if abs(x - streamX(z)) < 1.2 { continue }
            let y = gy(x, z)
            if rr.next() < 0.08 {
                let ta = rr.r(0, 6.28), l = rr.r(0.3, 1.1)
                let dv = V3(cos(ta), 0, sin(ta)) * (l / 2)
                let p0 = V3(x, 0, z) - dv, p1 = V3(x, 0, z) + dv
                twigs.tube(V3(p0.x, gy(p0.x, p0.z) + 0.02, p0.z), V3(p1.x, gy(p1.x, p1.z) + 0.02, p1.z), rr.r(0.012, 0.026), 0.008, V3(1, 1, 1), segs: 4)
                continue
            }
            let la = rr.r(0, 6.28), l = rr.r(0.08, 0.16)
            let u = V3(cos(la), 0, sin(la)) * l, v = V3(-sin(la), 0, cos(la)) * (l * 0.42)
            let c = V3(x, y + 0.015, z)
            let tint = [fogLin(0x7A5634), fogLin(0xA07A42), fogLin(0x5E4028), fogLin(0xB0662E), fogLin(0x8A8460)][Int(rr.next() * 4.99)] * rr.r(0.85, 1.2)
            leaves.quad(c - u - v, c + u - v, c + u + v + V3(0, 0.01, 0), c - u + v, tint)
        }
        // a mossy log lying across the slope in front of the camp
        var log: [V3] = [], lr: [Float] = [], lc: [V3] = []
        for i in 0...8 {
            let t = Float(i) / 8
            let x = 2.2 + 3.6 * t, z = 3.2 + 1.6 * t
            log.append(V3(x, gy(x, z) + 0.22, z))
            lr.append(0.34 * (1 - 0.3 * t))
            lc.append(V3(0.95, 0.45, 0.35))
        }
        roots.limb(log, lr, lc, segs: 10)
        for k in 0..<4 {
            let p = log[2 + k] + V3(0, lr[2 + k] * 0.9, 0)
            fernClump(&moss, at: p, size: rr.r(0.3, 0.5), fronds: 6, seed: p.x * 7, color: fogLin(0x55742E))
        }
        // seedlings of the forest trees pushing up through the litter
        for _ in 0..<70 {
            let a = rr.r(0, 6.28), d = rr.r(2.5, 14)
            let x = camXZ.x + cos(a) * d, z = camXZ.y + sin(a) * d - 4
            if abs(x - streamX(z)) < 1.5 || simd_length(SIMD2(x, z) - campC) < 3 || simd_length(SIMD2(x, z) - barC) < 2.2 { continue }
            let h = rr.r(0.2, 0.55)
            let b = V3(x, gy(x, z) - 0.02, z)
            seedlings.tube(b, b + V3(0, h, 0), 0.008, 0.005, fogLin(0x4A5A2A), segs: 3)
            leafSpray(&seedlings, at: b + V3(0, h, 0), radius: 0.12, count: 6, color: fogLin(0x3E5A2A), seed: x * 5 + z)
        }
        world.addChildNode(roots.node(mossMaterial(bark: SK.rgb(0x5C564C), moss: SK.rgb(0x66872D), pale: SK.rgb(0xA7AC98), scale: 2), shadow: true))
        world.addChildNode(twigs.node(poleMat))
        let litter = leafMaterial(roughness: 0.85, doubleSided: false)
        world.addChildNode(leaves.node(litter))
        world.addChildNode(moss.node(leafMaterial(roughness: 0.8)))
        world.addChildNode(seedlings.node(leafMaterial(roughness: 0.8)))
    }

    /// A tree fern: a dark fibrous trunk, a crown of arching fronds, dead fronds hanging below.
    private func treeFern(_ stems: inout FogMesh, _ ferns: inout FogMesh, at p: SIMD2<Float>, height h: Float, seed: Float) {
        var rr = FogRng(UInt64(seed * 1000) + 3)
        let b = V3(p.x, gy(p.x, p.y) - 0.2, p.y)
        let lean = V3(rr.r(-0.25, 0.25), 0, rr.r(-0.25, 0.25))
        let top = b + V3(0, h + 0.2, 0) + lean
        stems.limb([b, b + V3(0, h * 0.5, 0) + lean * 0.3, top], [0.16, 0.12, 0.13],
                   [V3(0.55, 0.18, 0.2), V3(0.35, 0.16, 0.2), V3(0.2, 0.15, 0.2)], segs: 7)
        let n = Int(rr.r(9, 13))
        for f in 0..<n {
            let a = Float(f) / Float(n) * 2 * .pi + rr.r(-0.2, 0.2)
            let out = V3(cos(a), 0, sin(a))
            let len = rr.r(1.5, 2.3)
            var c: [V3] = [], w: [Float] = [], col: [V3] = []
            let steps = 9
            let green = fogLin(0x4A6E2A) * rr.r(0.85, 1.15)
            for i in 0...steps {
                let s = Float(i) / Float(steps)
                c.append(top + out * (len * s) + V3(0, len * (0.75 * s - 0.95 * s * s), 0))
                let edge: Float = (i % 2 == 0) ? 1 : 0.75
                w.append(len * 0.15 * pow(sin(.pi * min(1, 0.1 + s * 0.95)), 0.6) * edge + 0.005)
                col.append(green * (0.75 + 0.4 * s))
            }
            ferns.strip(c, w, side: V3(-out.z, 0, out.x), fold: 0.3, col)
        }
        // a skirt of dead fronds
        for f in 0..<4 {
            let a = Float(f) * 1.6 + rr.r(-0.3, 0.3)
            let out = V3(cos(a), 0, sin(a))
            let len = rr.r(0.9, 1.4)
            let brown = fogLin(0x6E5636) * rr.r(0.8, 1.1)
            ferns.strip([top - V3(0, 0.05, 0), top + out * 0.25 - V3(0, len * 0.5, 0), top + out * 0.3 - V3(0, len, 0)],
                        [0.02, 0.11, 0.02], side: V3(-out.z, 0, out.x), fold: 0.2, [brown, brown, brown * 0.8])
        }
    }

    // MARK: Logs and rocks

    private func buildLogsAndRocks() {
        var logs = FogMesh(), rocks = FogMesh(), fungi = FogMesh(), epi = FogMesh()
        var rr = FogRng(777)
        // the fallen giant that opened the gap, across the stream, its root plate torn up on the west bank
        let fallen: [(SIMD2<Float>, SIMD2<Float>, Float)] = [
            (SIMD2(-8.4, -21.6), SIMD2(8.6, -17.8), 0.78),
            (SIMD2(-6.0, -2.4), SIMD2(-9.8, -8.6), 0.42),
            (SIMD2(11.2, -4.0), SIMD2(13.0, -15.0), 0.5),
            (SIMD2(-9.0, -21.0), SIMD2(-3.6, -25.4), 0.55),
            (SIMD2(-1.6, 7.6), SIMD2(-6.4, 10.4), 0.36),
            (SIMD2(8.0, -36), SIMD2(1.0, -40), 0.6)
        ]
        for (k, f) in fallen.enumerated() {
            let a = V3(f.0.x, 0, f.0.y), b = V3(f.1.x, 0, f.1.y)
            let r = f.2
            let n = Int(fogLen(b - a) / 0.8) + 1
            var c: [V3] = [], rad: [Float] = [], col: [V3] = []
            // rest on the high points: never sink more than a third of the way in
            var ys: [Float] = []
            for i in 0...n {
                let p = a + (b - a) * (Float(i) / Float(n))
                ys.append(gy(p.x, p.z))
            }
            let y0 = ys[0], y1 = ys[n]
            var lift: Float = 0
            for i in 0...n {
                let lin = y0 + (y1 - y0) * Float(i) / Float(n)
                lift = max(lift, ys[i] - lin)
            }
            for i in 0...n {
                let s = Float(i) / Float(n)
                let p = a + (b - a) * s
                let y = y0 + (y1 - y0) * s + lift * 0.75 + r * 0.55
                c.append(V3(p.x, y, p.z))
                rad.append(r * (1 - 0.35 * s) * (1 + 0.06 * (noise.value(s * 9 + Float(k), 2) - 0.5)))
                col.append(V3(0.95, 0.4, 0.4))
            }
            logs.limb(c, rad, col, segs: k == 0 ? 16 : 10)
            // shelf fungi and ferns on the log
            for _ in 0..<Int(fogLen(b - a) * 0.8) {
                let s = rr.r(0.05, 0.95)
                let i = min(n - 1, Int(s * Float(n)))
                let p = c[i]
                let side = fogUnit(SK.cross(b - a, V3(0, 1, 0))) * (rr.next() < 0.5 ? 1 : -1)
                if rr.next() < 0.55 {
                    let q = p + side * (rad[i] * 0.95) + V3(0, rr.r(-0.2, 0.2) * rad[i], 0)
                    let fr = rr.r(0.06, 0.14)
                    fungi.blob(q, V3(fr, fr * 0.28, fr), fogLin(0xC9BCA0), noise, seed: q.x, jitter: 0.15, rings: 3, segs: 7, under: 0.6, vary: 0.25)
                } else {
                    fernClump(&epi, at: p + V3(0, rad[i] * 0.9, 0), size: rr.r(0.3, 0.55), fronds: 6, seed: p.x + p.z * 3, color: fogLin(0x4F6E2C))
                }
            }
            if k == 0 {
                // the root plate: a ragged disc of earth and roots standing on edge
                let dir = fogUnit(b - a)
                let side = fogUnit(SK.cross(dir, V3(0, 1, 0)))
                let center = c[0] - dir * 0.3 + V3(0, 0.6, 0)
                var ring: [V3] = []
                for j in 0..<14 {
                    let t = Float(j) / 14 * 2 * .pi
                    let rr2 = 1.9 * (0.75 + 0.5 * noise.value(cos(t) * 2 + 4, sin(t) * 2))
                    ring.append(center + side * (cos(t) * rr2) + V3(0, sin(t) * rr2 * 0.8, 0))
                }
                let earth = V3(0.55, 0.22, 0.3)
                for j in 0..<14 {
                    let p0 = ring[j], p1 = ring[(j + 1) % 14]
                    logs.quad(center - dir * 0.35, p0 - dir * 0.2, p1 - dir * 0.2, center - dir * 0.35, earth)
                    logs.quad(center + dir * 0.25, p1 + dir * 0.1, p0 + dir * 0.1, center + dir * 0.25, earth)
                    logs.quad(p0 - dir * 0.2, p0 + dir * 0.1, p1 + dir * 0.1, p1 - dir * 0.2, earth)
                    // roots sticking out of the plate
                    if j % 2 == 0 {
                        let out = fogUnit(p0 - center)
                        logs.tube(p0, p0 + out * rr.r(0.4, 0.9) - dir * rr.r(0.0, 0.4), 0.06, 0.012, V3(0.3, 0.3, 0.3), segs: 4)
                    }
                }
            }
        }

        // boulders: at the lips of the falls, breaking the pools, along the banks, a few on the slopes
        func boulder(_ x: Float, _ z: Float, _ r: Float, sink: Float, moss: Float) {
            let y = gy(x, z)
            rocks.blob(V3(x, y + r * (0.42 - sink), z), V3(r * rr.r(0.9, 1.4), r * rr.r(0.45, 0.7), r * rr.r(0.8, 1.2)),
                       V3(moss, 0.42, 0.5), noise, seed: x * 1.3 + z, jitter: 0.36, rings: 7, segs: 11, under: 0.35, vary: 0.4,
                       yaw: rr.r(0, 6.28))
        }
        for zf in fallZs() {
            let sx = streamX(zf)
            for side in [-1.0, 1.0] as [Float] {
                boulder(sx + side * rr.r(0.75, 1.15), zf + rr.r(-0.3, 0.3), rr.r(0.4, 0.7), sink: 0.25, moss: 0.55)
            }
            if rr.next() < 0.6 { boulder(sx + rr.r(-0.35, 0.35), zf - 0.35, rr.r(0.22, 0.36), sink: 0.35, moss: 0.25) }
        }
        var z: Float = -50
        while z < 12 {
            let d = rr.r(1.3, 3.2) * (rr.next() < 0.5 ? -1 : 1)
            let x = streamX(z) + d
            if simd_length(SIMD2(x, z) - barC) > 2.4 && simd_length(SIMD2(x, z) - campC) > 3.5 && simd_length(SIMD2(x, z) - camXZ) > 2.5 {
                boulder(x, z, rr.r(0.35, 1.1), sink: 0.3, moss: 0.62)
            }
            z += rr.r(1.6, 3.4)
        }
        for _ in 0..<26 {
            let x = rr.r(-24, 26), z = rr.r(-48, 12)
            guard free(x, z, 1.2, gap: false) else { continue }
            boulder(x, z, rr.r(0.5, 1.4), sink: 0.35, moss: 0.8)
        }
        let rock = mossMaterial(bark: SK.rgb(0x6E6E68), moss: SK.rgb(0x58752C), pale: SK.rgb(0xB4B6A8), scale: 1.4)
        world.addChildNode(rocks.node(rock, shadow: true))
        world.addChildNode(logs.node(mossMaterial(bark: SK.rgb(0x5A5046), moss: SK.rgb(0x5B782C), pale: SK.rgb(0xA6A892), scale: 1.2), shadow: true))
        world.addChildNode(fungi.node(leafMaterial(roughness: 0.7, doubleSided: false)))
        world.addChildNode(epi.node(leafMaterial(roughness: 0.8)))
    }

    // MARK: Camp

    /// Plain material with the ground's (cached) grain normal map: cheap to build, fine for props.
    private func grainMat(_ hex: UInt32, roughness: CGFloat = 0.85, doubleSided: Bool = false, intensity: CGFloat = 0.4) -> SCNMaterial {
        let m = SK.mat(SK.rgb(hex), roughness: roughness, doubleSided: doubleSided)
        SK.addGrain(m, scale: 12, strength: 3, intensity: intensity, seed: 13)
        return m
    }

    private lazy var tarpMat: SCNMaterial = grainMat(0x2C5884, roughness: 0.55, doubleSided: true, intensity: 0.2)
    private lazy var stoneMat: SCNMaterial = grainMat(0x5E5E59, roughness: 0.9, intensity: 0.6)

    /// Crinkled mylar: gold on one side, silver on the other (shown as two materials).
    private func mylar(gold: Bool) -> SCNMaterial {
        let m = SK.mat(gold ? SK.rgb(0xD8B25A) : SK.rgb(0xC9CDD2), roughness: 0.28, metalness: 0.9, doubleSided: true)
        m.normal.contents = SK.normalNoiseImage(size: 256, scale: 22, strength: 9, seed: 151)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        m.normal.intensity = 0.9
        return m
    }

    private lazy var poleMat: SCNMaterial = grainMat(0x5A4836, roughness: 0.9, intensity: 0.6)

    /// A sagging sheet between a top edge (a→b) and a bottom edge (c→d); `sag` pulls the middle down.
    private func cloth(_ a: V3, _ b: V3, _ c: V3, _ d: V3, sag: Float, nu: Int = 10, nv: Int = 6, color: V3 = V3(1, 1, 1)) -> FogMesh {
        var m = FogMesh()
        m.sheet(nu: nu, nv: nv, color, uvScale: (fogLen(b - a) / 1.2, fogLen(c - a) / 1.2)) { u, v in
            let top = a + (b - a) * u, bot = c + (d - c) * u
            return top + (bot - top) * v - V3(0, sag * sin(.pi * u) * (0.35 + 0.65 * sin(.pi * min(1, v * 1.15))), 0)
        }
        return m
    }

    private func backpack(_ color: NSColor, at p: V3, yaw: Float, lying: Bool = false) -> SCNNode {
        let n = SCNNode()
        let body = SK.mat(color, roughness: 0.75)
        let dark = SK.mat(color.blended(withFraction: 0.45, of: .black) ?? color, roughness: 0.8)
        n.addChildNode(SK.box(0.36, 0.56, 0.24, body, chamfer: 0.07, at: SCNVector3(0, 0.28, 0)))
        n.addChildNode(SK.box(0.34, 0.12, 0.26, dark, chamfer: 0.05, at: SCNVector3(0, 0.6, -0.01)))
        n.addChildNode(SK.box(0.24, 0.22, 0.08, dark, chamfer: 0.03, at: SCNVector3(0, 0.22, 0.14)))
        for x in [-0.2, 0.2] as [CGFloat] {
            n.addChildNode(SK.box(0.06, 0.26, 0.14, dark, chamfer: 0.02, at: SCNVector3(x, 0.2, 0.02)))
        }
        n.position = SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
        n.eulerAngles = lying ? SCNVector3(-CGFloat.pi / 2 + 0.1, CGFloat(yaw), 0) : SCNVector3(-0.18, CGFloat(yaw), 0)
        if lying { n.position.y += 0.12 }
        return n
    }

    private func buildCamp() {
        let camp = SCNNode()
        world.addChildNode(camp)
        firePos = SCNVector3(1.35, CGFloat(gy(1.35, -0.2)), -0.2)
        // the ridge pole: lashed to the oak at the west end, on a forked stake at the east end
        let W = V3(-0.42, gy(-0.42, -2.05) + 1.78, -2.05)
        let E = V3(3.35, gy(3.35, -1.75) + 1.5, -1.75)
        var wood = FogMesh()
        wood.tube(W - V3(0.25, 0.02, 0.1), E + V3(0.25, -0.02, 0.05), 0.045, 0.035, V3(1, 1, 1), segs: 6)
        wood.tube(V3(E.x + 0.05, gy(E.x + 0.05, E.z) - 0.2, E.z), E + V3(0.05, 0.12, 0), 0.04, 0.035, V3(1, 1, 1), segs: 6)
        wood.tube(E + V3(0.05, -0.08, 0), E + V3(-0.1, 0.25, 0.12), 0.025, 0.02, V3(1, 1, 1), segs: 4)
        // the tarp: from the ridge down to stakes on the uphill side, a short flap over the front
        let backW = V3(-0.3, gy(-0.3, -3.65) + 0.05, -3.65), backE = V3(3.35, gy(3.35, -3.45) + 0.05, -3.45)
        let tarp = cloth(W + V3(0.05, 0.06, 0), E + V3(0, 0.06, 0), backW, backE, sag: 0.16)
        let leanTo = SCNNode()
        leanTo.addChildNode(tarp.node(tarpMat, shadow: true))
        let flap = cloth(W + V3(0.05, 0.06, 0.02), E + V3(0, 0.06, 0.02), W + V3(0.05, -0.18, 0.42), E + V3(0, -0.2, 0.42), sag: 0.05, nu: 8, nv: 2)
        leanTo.addChildNode(flap.node(tarpMat, shadow: true))
        // guy lines to the corners
        var ropes = FogMesh()
        for (p, q) in [(backE, backE + V3(0.5, -0.05, -0.4)), (backW, backW + V3(-0.3, -0.05, -0.5)), (E + V3(0, 0.1, 0), V3(4.1, gy(4.1, -1.2), -1.2))] {
            ropes.tube(p, q, 0.006, 0.006, V3(1, 1, 1), segs: 3)
        }
        leanTo.addChildNode(ropes.node(SK.mat(SK.rgb(0xD8D2B8), roughness: 0.8)))
        // an emergency blanket spread on the ground under it, another over the packs
        let gs = SCNNode(geometry: SCNPlane(width: 3.1, height: 1.5))
        gs.geometry?.materials = [mylar(gold: false)]
        gs.eulerAngles.x = -.pi / 2
        gs.eulerAngles.y = 0.06
        gs.position = SCNVector3(1.45, CGFloat(gy(1.45, -2.45)) + 0.03, -2.45)
        leanTo.addChildNode(gs)
        // packs against the oak's buttress and by the stake
        leanTo.addChildNode(backpack(SK.rgb(0xA8342A), at: V3(-0.2, gy(-0.2, -2.9) - 0.02, -2.9), yaw: 0.5))
        leanTo.addChildNode(backpack(SK.rgb(0x56603A), at: V3(0.25, gy(0.25, -3.15) - 0.02, -3.15), yaw: 0.1))
        leanTo.addChildNode(backpack(SK.rgb(0xD27428), at: V3(3.65, gy(3.65, -1.25) - 0.02, -1.25), yaw: -0.9))
        leanTo.addChildNode(backpack(SK.rgb(0x2C3A55), at: V3(2.6, gy(2.6, 0.45), 0.45), yaw: 1.2, lying: true))
        // the gold side of a blanket closes the east end against the wind off the stream
        var wall = FogMesh()
        let wTop = E + V3(-0.02, 0.02, 0.02), wFront = V3(E.x + 0.05, gy(E.x, E.z + 0.25) + 0.02, E.z + 0.25)
        wall.sheet(nu: 4, nv: 5, V3(1, 1, 1), uvScale: (1.5, 1.5)) { u, v in
            let back = backE + (wTop - backE) * (1 - u) * 0.0 + V3(-0.05, 0, 0)
            let bottom = wFront + (back - wFront) * u
            let top = wTop + (backE - wTop) * (u * 0.9)
            let p = top + (bottom - top) * v
            return p + V3(0.06 * sin(.pi * v) * sin(.pi * u), 0, 0)
        }
        leanTo.addChildNode(wall.node(mylar(gold: true)))
        // a jacket and socks drying on the ridge pole
        var dry = FogMesh()
        let j0 = W + (E - W) * 0.62
        dry.quad(j0 + V3(-0.28, 0, 0.02), j0 + V3(0.28, 0, 0.02), j0 + V3(0.24, -0.62, 0.05), j0 + V3(-0.24, -0.62, 0.05), V3(1, 1, 1))
        leanTo.addChildNode(dry.node(SK.mat(SK.rgb(0xB0382C), roughness: 0.85, doubleSided: true)))
        var socks = FogMesh()
        let s0 = W + (E - W) * 0.3
        socks.quad(s0 + V3(-0.05, 0, 0.03), s0 + V3(0.05, 0, 0.03), s0 + V3(0.05, -0.3, 0.04), s0 + V3(-0.05, -0.3, 0.04), V3(1, 1, 1))
        socks.quad(s0 + V3(0.12, 0, 0.03), s0 + V3(0.22, 0, 0.03), s0 + V3(0.22, -0.28, 0.04), s0 + V3(0.12, -0.28, 0.04), V3(1, 1, 1))
        leanTo.addChildNode(socks.node(SK.mat(SK.rgb(0x7E8178), roughness: 0.9, doubleSided: true)))
        camp.addChildNode(leanTo)
        self.leanTo = leanTo

        // survey gear: a GNSS receiver on its tripod and the orange-and-white pole against the stake
        let gear = SCNNode()
        let head = V3(-0.75, gy(-0.75, 0.75) + 1.42, 0.75)
        var tri = FogMesh(), triTop = FogMesh()
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi + 0.4
            let foot = V3(head.x + cos(a) * 0.62, gy(head.x + cos(a) * 0.62, head.z + sin(a) * 0.62) - 0.05, head.z + sin(a) * 0.62)
            let mid = head + (foot - head) * 0.45
            triTop.tube(head, mid, 0.024, 0.022, V3(1, 1, 1), segs: 5)
            tri.tube(mid, foot, 0.016, 0.012, V3(1, 1, 1), segs: 5)
        }
        gear.addChildNode(tri.node(SK.mat(SK.rgb(0xB9BCBE), roughness: 0.35, metalness: 0.8)))
        gear.addChildNode(triTop.node(SK.mat(SK.rgb(0xD9A82A), roughness: 0.5)))
        let plate = SK.cylinder(0.09, 0.04, SK.mat(SK.rgb(0x2A2A2C), roughness: 0.5), at: SCNVector3(CGFloat(head.x), CGFloat(head.y) + 0.02, CGFloat(head.z)))
        gear.addChildNode(plate)
        let dome = SK.sphere(0.1, SK.mat(SK.rgb(0xECEBE4), roughness: 0.4), at: SCNVector3(CGFloat(head.x), CGFloat(head.y) + 0.1, CGFloat(head.z)), segments: 16)
        dome.scale = SCNVector3(1, 0.55, 1)
        gear.addChildNode(dome)
        gear.addChildNode(SK.cylinder(0.1, 0.05, SK.mat(SK.rgb(0xE0A62C), roughness: 0.5), at: SCNVector3(CGFloat(head.x), CGFloat(head.y) + 0.07, CGFloat(head.z))))
        // the pole: 2.4 m, banded
        let p0 = V3(3.78, gy(3.78, -1.05) - 0.05, -1.05), p1 = V3(3.3, gy(3.3, -1.7) + 2.3, -1.7)
        var orange = FogMesh(), white = FogMesh()
        for k in 0..<8 {
            let a = p0 + (p1 - p0) * (Float(k) / 8), b = p0 + (p1 - p0) * (Float(k + 1) / 8)
            if k % 2 == 0 { orange.tube(a, b, 0.018, 0.018, V3(1, 1, 1), segs: 6) } else { white.tube(a, b, 0.018, 0.018, V3(1, 1, 1), segs: 6) }
        }
        gear.addChildNode(orange.node(SK.mat(SK.rgb(0xF06A1C), roughness: 0.45)))
        gear.addChildNode(white.node(SK.mat(SK.rgb(0xEEEEE8), roughness: 0.45)))
        // a hard hat and a field book on the orange pack
        gear.addChildNode(SK.sphere(0.13, SK.mat(SK.rgb(0xF2F0E8), roughness: 0.35), at: SCNVector3(3.62, CGFloat(gy(3.62, -1.25)) + 0.72, -1.23), segments: 14))
        leanTo.addChildNode(gear)

        // firewood: wet sticks drying by the fire, a mess tin on the stones
        var sticks = FogMesh()
        var rr = FogRng(161)
        for k in 0..<9 {
            let c = V3(0.35 + rr.r(-0.2, 0.2), 0, 0.35 + rr.r(-0.2, 0.2))
            let a = rr.r(-0.5, 0.5) + (k % 2 == 0 ? 0 : 1.4)
            let d = V3(cos(a), 0, sin(a)) * rr.r(0.4, 0.6)
            let y = gy(c.x, c.z) + 0.05 + Float(k / 3) * 0.07
            sticks.tube(V3(c.x, y, c.z) - d, V3(c.x, y + 0.02, c.z) + d, 0.035, 0.025, V3(1, 1, 1), segs: 5)
        }
        leanTo.addChildNode(sticks.node(poleMat))
        leanTo.addChildNode(SK.cylinder(0.08, 0.1, SK.mat(SK.rgb(0x9EA3A6), roughness: 0.35, metalness: 0.8),
                                        at: SCNVector3(firePos.x + 0.42, firePos.y + 0.13, firePos.z - 0.3)))
        leanTo.addChildNode(wood.node(poleMat, shadow: true))

        // a stretcher of two poles and a jacket, for whoever can't walk
        let st = SCNNode()
        var poles = FogMesh()
        let sc = V3(3.9, 0, 0.2)
        for dx in [-0.28, 0.28] as [Float] {
            let a = V3(sc.x + dx, gy(sc.x + dx, sc.z - 1.15) + 0.08, sc.z - 1.15), b = V3(sc.x + dx, gy(sc.x + dx, sc.z + 1.15) + 0.08, sc.z + 1.15)
            poles.tube(a, b, 0.035, 0.03, V3(1, 1, 1), segs: 5)
        }
        st.addChildNode(poles.node(poleMat, shadow: true))
        var bed = FogMesh()
        bed.sheet(nu: 3, nv: 6, V3(1, 1, 1)) { u, v in
            let x = sc.x + (u - 0.5) * 0.56, z = sc.z + (v - 0.5) * 1.7
            return V3(x, self.gy(x, z) + 0.1 - 0.05 * sin(.pi * u), z)
        }
        st.addChildNode(bed.node(SK.mat(SK.rgb(0xB0382C), roughness: 0.85, doubleSided: true)))
        st.isHidden = true
        world.addChildNode(st)
        stretcher = st

        // what's left when the camp moves down to the water: the ridge pole and a cold fire ring
        let old = SCNNode()
        var oldWood = FogMesh()
        let dropped = V3(E.x + 0.1, gy(E.x + 0.1, E.z + 0.4) + 0.05, E.z + 0.4)
        oldWood.tube(W - V3(0.25, 0.02, 0.1), dropped, 0.045, 0.035, V3(1, 1, 1), segs: 6)
        oldWood.tube(V3(E.x + 0.4, gy(E.x + 0.4, E.z - 0.3) + 0.05, E.z - 0.3), V3(E.x - 0.9, gy(E.x - 0.9, E.z - 0.6) + 0.06, E.z - 0.6), 0.04, 0.035, V3(1, 1, 1), segs: 6)
        old.addChildNode(oldWood.node(poleMat))
        let stone = stoneMat
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * 2 * .pi
            let r = SK.rock(0.09, stone, seed: UInt64(180 + i))
            r.position = SCNVector3(firePos.x + sin(a) * 0.36, firePos.y + 0.02, firePos.z + cos(a) * 0.36)
            old.addChildNode(r)
        }
        let ash = SK.cylinder(0.27, 0.03, SK.mat(SK.rgb(0x2A2622), roughness: 1), at: SCNVector3(firePos.x, firePos.y + 0.01, firePos.z))
        old.addChildNode(ash)
        old.isHidden = true
        world.addChildNode(old)
        oldCamp = old
    }

    /// The camp moved down beside the stream: the tarp against a big boulder on the gravel bar.
    private func buildBarCamp() {
        let bar = SCNNode()
        let c = barC
        let y = barLevel
        // the bar itself: rounded grey stones
        var gravel = FogMesh()
        var rr = FogRng(211)
        for _ in 0..<40 {
            let a = rr.r(0, 6.28), d = 1.9 * sqrt(rr.next())
            let x = c.x + cos(a) * d * 0.9, z = c.y + sin(a) * d * 1.3
            let r = rr.r(0.05, 0.16)
            gravel.blob(V3(x, gy(x, z) + r * 0.15, z), V3(r, r * 0.5, r * 0.8), V3(0.12, 0.36, 0.2), noise, seed: x + z, jitter: 0.2,
                        rings: 3, segs: 6, under: 0.7, vary: 0.3, yaw: rr.r(0, 3))
        }
        world.addChildNode(gravel.node(mossMaterial(bark: SK.rgb(0x66645E), moss: SK.rgb(0x5A7330), pale: SK.rgb(0xB9BBB2), scale: 3)))
        // the tarp: ridge between two staves, staked down on the uphill side
        let W = V3(c.x - 1.6, y + 1.45, c.y - 0.75), E = V3(c.x + 1.5, y + 1.3, c.y - 0.95)
        var wood = FogMesh()
        wood.tube(W - V3(0.2, 0, 0), E + V3(0.2, 0, 0), 0.04, 0.032, V3(1, 1, 1), segs: 6)
        for p in [W, E] {
            wood.tube(V3(p.x, gy(p.x, p.z) - 0.2, p.z), p + V3(0, 0.14, 0), 0.035, 0.03, V3(1, 1, 1), segs: 5)
        }
        bar.addChildNode(wood.node(poleMat, shadow: true))
        let backW = V3(W.x + 0.1, gy(W.x + 0.1, c.y - 2.4) + 0.04, c.y - 2.4), backE = V3(E.x, gy(E.x, c.y - 2.55) + 0.04, c.y - 2.55)
        bar.addChildNode(cloth(W + V3(0, 0.05, 0), E + V3(0, 0.05, 0), backW, backE, sag: 0.14).node(tarpMat, shadow: true))
        let gs = SCNNode(geometry: SCNPlane(width: 2.8, height: 1.3))
        gs.geometry?.materials = [mylar(gold: true)]
        gs.eulerAngles.x = -.pi / 2
        gs.position = SCNVector3(CGFloat(c.x), CGFloat(gy(c.x, c.y - 1.45)) + 0.04, CGFloat(c.y - 1.45))
        bar.addChildNode(gs)
        bar.addChildNode(backpack(SK.rgb(0xA8342A), at: V3(W.x + 0.2, gy(W.x + 0.2, W.z - 0.5), W.z - 0.5), yaw: 0.3))
        bar.addChildNode(backpack(SK.rgb(0x56603A), at: V3(W.x + 0.65, gy(W.x + 0.65, W.z - 0.8), W.z - 0.8), yaw: -0.2))
        bar.addChildNode(backpack(SK.rgb(0xD27428), at: V3(E.x + 0.3, gy(E.x + 0.3, E.z + 0.3), E.z + 0.3), yaw: -1.0))
        // the survey pole goes along, stuck upright in the gravel as a marker
        var orange = FogMesh(), white = FogMesh()
        let p0 = V3(E.x + 0.6, gy(E.x + 0.6, E.z + 0.9) - 0.15, E.z + 0.9)
        for k in 0..<8 {
            let a = p0 + V3(0, Float(k) * 0.3, 0), b = p0 + V3(0, Float(k + 1) * 0.3, 0)
            if k % 2 == 0 { orange.tube(a, b, 0.018, 0.018, V3(1, 1, 1), segs: 6) } else { white.tube(a, b, 0.018, 0.018, V3(1, 1, 1), segs: 6) }
        }
        bar.addChildNode(orange.node(SK.mat(SK.rgb(0xF06A1C), roughness: 0.45)))
        bar.addChildNode(white.node(SK.mat(SK.rgb(0xEEEEE8), roughness: 0.45)))
        bar.isHidden = true
        world.addChildNode(bar)
        barCamp = bar
        barFirePos = SCNVector3(CGFloat(c.x + 0.1), CGFloat(gy(c.x + 0.1, c.y + 0.75)), CGFloat(c.y + 0.75))
    }

    // MARK: Mist

    private func buildMist() {
        // banks of mist drifting between the trunks (billboards turning about the vertical only)
        let images = (0..<3).map { mistImage(seed: UInt64(500 + $0)) }
        var rr = FogRng(515)
        let spots: [(Float, Float, Float, Float)] = [(-6, -12, 16, 3.5), (6, -17, 18, 2.5), (-1, -24, 22, 4.5), (10, -30, 20, 5),
                                                     (-12, -27, 22, 5.5), (2, -38, 26, 6), (-8, -6, 12, 2.2), (14, -8, 14, 4),
                                                     (-16, -14, 18, 5), (8, -44, 28, 8), (-5, -48, 28, 9)]
        for (i, sp) in spots.enumerated() {
            let w = CGFloat(sp.2), h = CGFloat(sp.2 * rr.r(0.28, 0.4))
            let plane = SCNPlane(width: w, height: h)
            let m = SK.mat(.white, roughness: 1)
            m.lightingModel = .constant
            m.diffuse.contents = images[i % images.count]
            m.multiply.contents = hazeColor
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(CGFloat(sp.0), CGFloat(gy(sp.0, sp.1) + sp.3), CGFloat(sp.1))
            let bb = SCNBillboardConstraint()
            bb.freeAxes = .Y
            n.constraints = [bb]
            n.castsShadow = false
            n.renderingOrder = 5
            let dx = CGFloat(rr.r(1.2, 2.6)), dt = Double(rr.r(14, 24))
            n.runAction(.repeatForever(.sequence([.moveBy(x: dx, y: 0, z: 0, duration: dt), .moveBy(x: -dx, y: 0, z: 0, duration: dt)])))
            world.addChildNode(n)
            mist.append(n)
        }
    }

    // MARK: Signals, search, route, drone, trail

    /// Glowing additive sprite (lamp halos, glints in the fog).
    private func halo(_ size: CGFloat, _ color: NSColor, intensity: CGFloat = 1) -> SCNNode {
        // (only shown after dark: in daylight fog an additive quad picks up the fog color and shows as a square)
        let m = SK.mat(.black, roughness: 1, doubleSided: true)
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.emission.contents = glowImage()
        m.emission.intensity = intensity
        m.multiply.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        let n = SCNNode(geometry: SCNPlane(width: size, height: size))
        n.geometry?.materials = [m]
        n.constraints = [SCNBillboardConstraint()]
        n.castsShadow = false
        n.renderingOrder = 12
        nightGlows.append(n)
        return n
    }

    private func buildSignals() {
        // fluorescent flagging tape tied to twigs around the camp and on toward the gap
        let tape = SK.mat(SK.rgb(0xF2461A), roughness: 0.5, emission: SK.rgb(0x5A1404), doubleSided: true)
        var rr = FogRng(611)
        if oakLimb.count > 4 {
            for k in [2, 3, 4] { ribbonSpots.insert((oakLimb[k], Float(k) * 1.3), at: k - 2) }
        }
        for (p, facing) in ribbonSpots {
            var m = FogMesh()
            for k in 0..<2 {
                let side = V3(cos(facing), 0, sin(facing))
                let off = V3(-side.z, 0, side.x) * (Float(k) * 0.05 - 0.025)
                let l = rr.r(0.32, 0.52)
                let tw = V3(rr.r(-0.05, 0.05), 0, rr.r(-0.05, 0.05))
                m.strip([off, off + V3(0, -l * 0.5, 0) + tw, off + V3(0, -l, 0) + tw * 2], [0.014, 0.014, 0.012], side: side, fold: 0,
                        [V3(1, 1, 1), V3(1, 1, 1), V3(1, 1, 1)])
            }
            m.box(V3(0, 0, 0), V3(0.03, 0.02, 0.03), V3(1, 1, 1))
            let n = m.node(tape)
            n.position = SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
            let a = CGFloat(rr.r(0.08, 0.16)), t = Double(rr.r(1.6, 2.6))
            n.runAction(.repeatForever(.sequence([.rotateBy(x: a, y: 0, z: a * 0.6, duration: t), .rotateBy(x: -a, y: 0, z: -a * 0.6, duration: t)])))
            n.isHidden = true
            world.addChildNode(n)
            ribbons.append(n)
        }

        // the big SOS on the floor of the gap (林窗): fallen logs and peeled white trunks, each letter ~5 m
        // long, silver blankets and red strips laid in between; it goes down stroke by stroke
        let c = sosC
        let peeled = grainMat(0xD2C9B5, roughness: 0.75, intensity: 0.7)
        let dark = grainMat(0x5E5446, roughness: 0.9, intensity: 0.7)
        rr = FogRng(623)
        func stroke(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            let n = SCNNode()
            var light = FogMesh(), old = FogMesh()
            let a = V3(c.x + x0, 0, c.y + z0), b = V3(c.x + x1, 0, c.y + z1)
            let side = fogUnit(SK.cross(b - a, V3(0, 1, 0)))
            for k in 0..<2 {
                // two trunks side by side, a little crooked, resting on the ground
                let off = side * (Float(k) * 0.34 - 0.17)
                var pts: [V3] = [], rad: [Float] = [], col: [V3] = []
                let r: Float = k == 0 ? rr.r(0.13, 0.17) : rr.r(0.1, 0.15)
                for i in 0...5 {
                    let q = a + (b - a) * (Float(i) / 5) + off + side * (rr.r(-0.05, 0.05))
                    pts.append(V3(q.x, gy(q.x, q.z) + r * 0.8, q.z))
                    rad.append(r)
                    col.append(V3(1, 1, 1))
                }
                if k == 0 || rr.next() < 0.5 { light.limb(pts, rad, col, segs: 6) } else { old.limb(pts, rad, col, segs: 6) }
            }
            n.addChildNode(light.node(peeled, shadow: true))
            n.addChildNode(old.node(dark, shadow: true))
            n.isHidden = true
            world.addChildNode(n)
            sos.append(n)
        }
        // letters 2.8 m wide and 5 m long, reading toward the camera (along +z)
        let w: Float = 2.8, h: Float = 2.5
        func letterS(_ x: Float) {
            stroke(x + w, -h, x, -h); stroke(x, -h, x, 0); stroke(x, 0, x + w, 0)
            stroke(x + w, 0, x + w, h); stroke(x + w, h, x, h)
        }
        letterS(-5.3)
        stroke(-w / 2, -h, w / 2, -h); stroke(w / 2, -h, w / 2, h); stroke(w / 2, h, -w / 2, h); stroke(-w / 2, h, -w / 2, -h)
        letterS(2.5)
        // silver blankets weighted with stones inside the O and in the bends of the S's, red strips on the logs
        let blankets = SCNNode()
        for (x, z, yaw) in [(0.0, -1.2, 0.1), (0.0, 1.2, -0.08), (-3.9, -1.3, 0.2), (3.9, 1.3, -0.15)] as [(Float, Float, Float)] {
            let bx = c.x + x, bz = c.y + z
            var m = FogMesh()
            m.sheet(nu: 4, nv: 3, V3(1, 1, 1)) { u, v in
                let lx = (u - 0.5) * 1.9, lz = (v - 0.5) * 1.35
                let q = SIMD2(bx, bz) + SIMD2(lx * cos(yaw) - lz * sin(yaw), lx * sin(yaw) + lz * cos(yaw))
                return V3(q.x, self.gy(q.x, q.y) + 0.05 + 0.04 * self.noise.value(u * 4 + x, v * 4), q.y)
            }
            blankets.addChildNode(m.node(mylar(gold: false)))
        }
        var strips = FogMesh()
        for _ in 0..<14 {
            let x = c.x + rr.r(-6.5, 6.5), z = c.y + rr.r(-2.6, 2.6)
            let a = rr.r(0, 6.28)
            let d = V3(cos(a), 0, sin(a)) * 0.35
            let p0 = V3(x, gy(x, z) + 0.06, z)
            strips.quad(p0 - d + V3(0, 0, 0.05), p0 + d + V3(0, 0, 0.05), p0 + d - V3(0, 0, 0.05), p0 - d - V3(0, 0, 0.05), V3(1, 1, 1))
        }
        blankets.addChildNode(strips.node(SK.mat(SK.rgb(0xD93A24), roughness: 0.6, emission: SK.rgb(0x3A0A04), doubleSided: true)))
        blankets.isHidden = true
        world.addChildNode(blankets)
        sosExtras = blankets

        // the third blanket, spread silver side up on the slope in front of the camp
        var spread = FogMesh()
        let sp = SIMD2<Float>(-0.6, 2.2)
        spread.sheet(nu: 5, nv: 4, V3(1, 1, 1)) { u, v in
            let x = sp.x + (u - 0.5) * 2.0, z = sp.y + (v - 0.5) * 1.4
            return V3(x, self.gy(x, z) + 0.06 + 0.05 * sin(u * 9) * sin(v * 7), z)
        }
        let sheet = spread.node(mylar(gold: false))
        let stone = stoneMat
        for (i, (dx, dz)) in [(-1.0, -0.7), (1.0, -0.7), (-1.0, 0.7), (1.0, 0.7)].enumerated() {
            let x = sp.x + Float(dx), z = sp.y + Float(dz)
            let r = SK.rock(0.11, stone, seed: UInt64(650 + i))
            r.position = SCNVector3(CGFloat(x), CGFloat(gy(x, z)), CGFloat(z))
            sheet.addChildNode(r)
        }
        sheet.isHidden = true
        world.addChildNode(sheet)
        spreadBlanket = sheet

        // the signal pyre in the gap: dry wood and pitch pine underneath, green boughs and moss on top;
        // lit, it sends up a column of white smoke
        let py = V3(pyreC.x, gy(pyreC.x, pyreC.y), pyreC.y)
        let sf = SCNNode()
        sf.position = SCNVector3(CGFloat(py.x), CGFloat(py.y), CGFloat(py.z))
        var heap = FogMesh(), boughs = FogMesh()
        for k in 0..<22 {
            let a = Float(k) * 0.83 + rr.r(-0.2, 0.2)
            let r = rr.r(0.9, 1.5)
            heap.tube(V3(cos(a) * r, -0.1, sin(a) * r), V3(cos(a + 2.4) * 0.15, rr.r(1.6, 2.2), sin(a + 2.4) * 0.15), 0.06, 0.035, V3(1, 1, 1), segs: 4)
        }
        for k in 0..<9 {
            let a = Float(k) * 0.7
            let p0 = V3(cos(a) * 0.7, rr.r(0.7, 1.5), sin(a) * 0.7)
            boughs.blob(p0, V3(0.7, 0.35, 0.55), fogLin(0x2F4426), noise, seed: Float(k) * 3.1, jitter: 0.35, rings: 4, segs: 7, under: 0.55, vary: 0.35, yaw: a)
        }
        let pile = SCNNode()
        pile.addChildNode(heap.node(poleMat, shadow: true))
        pile.addChildNode(boughs.node(leafMaterial(roughness: 0.85)))
        sf.addChildNode(pile)
        pyreHeap = pile
        let flames = SK.fire(scale: 1.4)
        let fh = SCNNode()
        fh.position = SCNVector3(0, 0.5, 0)
        sf.addChildNode(fh)
        pyreFlames = (flames, fh)
        let glow = halo(3.2, SK.rgb(0xFF7A2A), intensity: 0.8)
        glow.position = SCNVector3(0, 0.9, 0)
        sf.addChildNode(glow)
        let col = SK.smoke(scale: 2.0, color: NSColor(white: 0.95, alpha: 0.45))
        col.birthRate = 30
        col.particleLifeSpan = 12
        col.particleVelocity = 1.7
        col.spreadingAngle = 7
        col.acceleration = SCNVector3(0.1, 0.22, 0.04)
        let holder = SCNNode()
        holder.position = SCNVector3(0, 1.8, 0)
        sf.addChildNode(holder)
        sf.isHidden = true
        world.addChildNode(sf)
        signalFire = sf
        signalSmoke = (col, holder)
    }

    /// A light beam in the fog: additive, fading out along the cone (alpha-masked, so the fog can't fill it in).
    private func beamMaterial(_ color: NSColor) -> SCNMaterial {
        let m = SK.mat(color, roughness: 1, emission: color, doubleSided: true)
        m.lightingModel = .constant
        var px = [UInt8](repeating: 255, count: 4 * 64 * 4)
        for y in 0..<64 {
            let a = UInt8(255 * pow(1 - Float(y) / 63, 1.6) * 0.75)
            for x in 0..<4 { let i = (y * 4 + x) * 4; px[i] = a; px[i + 1] = a; px[i + 2] = a; px[i + 3] = a }
        }
        m.transparent.contents = SK.image(from: px, size: 4, height: 64)
        m.transparencyMode = .aOne
        m.blendMode = .add
        m.writesToDepthBuffer = false
        return m
    }

    /// Where the SOS is laid out: the open floor of the gap, in front of the fallen giant.
    private var sosC: SIMD2<Float> { SIMD2(-1.9, -12.4) }
    /// The signal pyre at the back of the gap.
    private var pyreC: SIMD2<Float> { SIMD2(1.6, -17.0) }

    private func buildSearch() {
        // the searchers' headlamps far up the slopes, bobbing as they climb
        let spots: [(Float, Float)] = [(-9, -16), (-3, -27), (-14, -11), (9.5, -24), (-12, -24), (2, -33)]
        var rr = FogRng(701)
        for (x, z) in spots {
            let n = SCNNode()
            n.position = SCNVector3(CGFloat(x), CGFloat(gy(x, z) + 1.65), CGFloat(z))
            n.addChildNode(SK.sphere(0.05, SK.mat(.black, roughness: 1, emission: SK.rgb(0xF4F8FF)), segments: 8))
            n.childNodes[0].geometry?.firstMaterial?.emission.intensity = 8
            let h = halo(2.4, SK.rgb(0xDDE8FF), intensity: 2.2)
            n.addChildNode(h)
            let dx = CGFloat(rr.r(-2.5, 2.5)), dy = CGFloat(rr.r(0.4, 1.2)), t = Double(rr.r(7, 12))
            n.runAction(.repeatForever(.sequence([.moveBy(x: dx, y: dy, z: 0, duration: t), .moveBy(x: -dx, y: -dy, z: 0, duration: t)])))
            // now and then the lamp turns away
            n.runAction(.repeatForever(.sequence([.wait(duration: Double(rr.r(2, 5))), .fadeOpacity(to: 0.15, duration: 0.4),
                                                  .wait(duration: Double(rr.r(0.5, 1.5))), .fadeOpacity(to: 1, duration: 0.4)])))
            n.isHidden = true
            world.addChildNode(n)
            headlamps.append(n)
        }
    }

    private func buildRoute() {
        // cairns down the west bank toward the way out, footprints in the mud between them
        let stone = mossMaterial(bark: SK.rgb(0x7A7870), moss: SK.rgb(0x5A7330), pale: SK.rgb(0xBDBFB5), scale: 3)
        let mud = SK.mat(SK.rgb(0x2E261E), roughness: 0.35)
        var rr = FogRng(801)
        var z: Float = -1.6
        for i in 0..<9 {
            let x = streamX(z) - 1.55 - rr.r(0, 0.4)
            var m = FogMesh()
            var y = gy(x, z) - 0.04
            let layers = 4 + i % 2
            for k in 0..<layers {
                let r = 0.22 - Float(k) * 0.035
                let h = r * 0.42
                m.blob(V3(x + rr.r(-0.03, 0.03), y + h * 0.8, z + rr.r(-0.03, 0.03)), V3(r * 1.15, h, r), V3(0.2, 0.45, 0.6), noise,
                       seed: x + Float(k), jitter: 0.18, rings: 4, segs: 8, under: 0.6, vary: 0.3, yaw: rr.r(0, 3))
                y += h * 1.55
            }
            let cairn = m.node(stone, shadow: true)
            cairn.isHidden = true
            world.addChildNode(cairn)
            cairns.append(cairn)
            // footprints on to the next cairn
            var f = FogMesh()
            let z1 = z + 2.6
            for k in 0..<5 {
                let t = (Float(k) + 0.5) / 5
                let zz = z + (z1 - z) * t
                let xx = streamX(zz) - 1.3 + (k % 2 == 0 ? -0.13 : 0.13)
                f.blob(V3(xx, gy(xx, zz) + 0.005, zz), V3(0.055, 0.012, 0.13), V3(1, 1, 1), noise, seed: zz, jitter: 0.1,
                       rings: 3, segs: 8, under: 1, vary: 0)
            }
            let prints = f.node(mud)
            prints.isHidden = true
            world.addChildNode(prints)
            self.prints.append(prints)
            z = z1
        }
    }

    private func buildDrone() {
        // a survey quadcopter holding over the gap, lights blinking
        let d = SCNNode()
        let body = SK.mat(SK.rgb(0x2B2D30), roughness: 0.4, metalness: 0.3)
        let grey = SK.mat(SK.rgb(0x55585C), roughness: 0.5)
        d.addChildNode(SK.box(0.34, 0.12, 0.42, body, chamfer: 0.04))
        for k in 0..<4 {
            let a = CGFloat(k) * .pi / 2 + .pi / 4
            let arm = SK.box(0.55, 0.035, 0.05, body, chamfer: 0.01, at: SCNVector3(cos(a) * 0.3, 0.02, sin(a) * 0.3))
            arm.eulerAngles.y = -a
            d.addChildNode(arm)
            let rotor = SCNNode(geometry: SCNCylinder(radius: 0.21, height: 0.006))
            let rm = SK.mat(SK.rgb(0x8A8E92), roughness: 0.5)
            rm.transparency = 0.35
            rotor.geometry?.materials = [rm]
            rotor.position = SCNVector3(cos(a) * 0.56, 0.07, sin(a) * 0.56)
            d.addChildNode(rotor)
            d.addChildNode(SK.cylinder(0.03, 0.06, grey, at: SCNVector3(cos(a) * 0.56, 0.035, sin(a) * 0.56)))
        }
        d.addChildNode(SK.box(0.1, 0.1, 0.1, grey, chamfer: 0.02, at: SCNVector3(0, -0.12, 0.1)))
        for x in [-0.12, 0.12] as [CGFloat] {
            d.addChildNode(SK.box(0.02, 0.2, 0.3, grey, chamfer: 0.005, at: SCNVector3(x, -0.14, 0)))
        }
        let blink = SCNAction.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.12),
                                                       .fadeOpacity(to: 0.05, duration: 0.05), .wait(duration: 0.9)]))
        for (i, (hex, x, z)) in [(0xFF2A1A, -0.56, 0.0), (0x2AFF5A, 0.56, 0.0), (0xFFFFFF, 0, -0.24)].enumerated() {
            let m = SK.mat(.black, roughness: 0.3, emission: SK.rgb(UInt32(hex)))
            m.emission.intensity = 6
            let l = SK.sphere(0.035, m, at: SCNVector3(CGFloat(x), 0.0, CGFloat(z)), segments: 8)
            let h = halo(0.5, SK.rgb(UInt32(hex)))
            l.addChildNode(h)
            l.runAction(.sequence([.wait(duration: Double(i) * 0.37), blink]))
            d.addChildNode(l)
        }
        // a searchlight cone after dark
        let beam = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 2.6, height: 9))
        beam.geometry?.materials = [beamMaterial(SK.rgb(0x5E666C))]
        beam.position = SCNVector3(0, -4.6, 0)
        beam.castsShadow = false
        beam.renderingOrder = 11
        beam.isHidden = true
        d.addChildNode(beam)
        droneBeam = beam
        // over the open stream corridor beside the gap, below the canopy, where it can look in
        let p = V3(7.2, gy(gapC.x, gapC.y) + 5.2, -12.6)
        d.position = SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
        d.eulerAngles.y = 0.6
        d.runAction(.repeatForever(.sequence([.moveBy(x: 0.4, y: 0.25, z: 0, duration: 2.6), .moveBy(x: -0.4, y: -0.25, z: 0, duration: 2.6)])))
        d.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.35, z: 0, duration: 5), .rotateBy(x: 0, y: -0.35, z: 0, duration: 5)])))
        d.isHidden = true
        world.addChildNode(d)
        drone = d
    }

    private func buildTrail() {
        // the old herders' trail: a worn path climbing the east wall, stone steps, a split-rail cattle fence
        let t = SCNNode()
        var path = FogMesh(), steps = FogMesh(), fence = FogMesh()
        var rr = FogRng(901)
        var z: Float = 7.5
        var lastStep: Float = 99
        var lastPost: Float = 99
        var prevPost: V3?
        while z > -36 {
            let x = trailX(z)
            let dx = (trailX(z - 0.3) - x) / 0.3
            let along = fogUnit(V3(dx, 0, -1))
            let across = V3(-along.z, 0, along.x)
            // the tread: a strip of trodden earth
            let w: Float = 0.42
            let a = V3(x, 0, z) - across * w, b = V3(x, 0, z) + across * w
            path.pts += [V3(a.x, gy(a.x, a.z) + 0.03, a.z), V3(x, gy(x, z) + 0.03, z), V3(b.x, gy(b.x, b.z) + 0.03, b.z)]
            path.cols += [V3(0.85, 0.85, 0.85), V3(1, 1, 1), V3(0.85, 0.85, 0.85)]
            path.uvs += [CGPoint(x: 0, y: CGFloat(z)), CGPoint(x: 0.5, y: CGFloat(z)), CGPoint(x: 1, y: CGFloat(z))]
            // where it climbs steeply, stone steps set into the slope
            let grade = (gy(x, z - 0.5) - gy(x, z)) / 0.5
            if grade > 0.18 && lastStep - z > 0.42 {
                lastStep = z
                let y = gy(x, z + 0.1)
                steps.box(V3(x + rr.r(-0.05, 0.05), y + 0.02, z - 0.12), V3(rr.r(0.36, 0.48), 0.09, 0.2), yaw: rr.r(-0.12, 0.12),
                          V3(0.35, 0.42, 0.55), top: V3(0.55, 0.45, 0.45))
            }
            // the fence along the downhill (stream) side
            if lastPost - z > 2.1 {
                lastPost = z
                let p = V3(x, 0, z) - across * 0.95
                let base = V3(p.x, gy(p.x, p.z) - 0.25, p.z)
                let lean = V3(rr.r(-0.06, 0.06), 0, rr.r(-0.06, 0.06))
                fence.tube(base, base + V3(0, 1.45, 0) + lean, 0.065, 0.055, V3(0.3, 0.55, 0.7), segs: 5)
                if let q = prevPost, rr.next() > 0.12 {
                    for hgt in [0.6, 1.05] as [Float] where rr.next() > 0.1 {
                        let sag = V3(0, -0.04, 0)
                        let a2 = q + V3(0, hgt, 0), b2 = base + lean * (hgt / 1.45) + V3(0, hgt, 0)
                        fence.limb([a2, (a2 + b2) * 0.5 + sag, b2], [0.04, 0.035, 0.04], [V3(0.3, 0.5, 0.7), V3(0.3, 0.5, 0.7), V3(0.3, 0.5, 0.7)], segs: 4)
                    }
                }
                prevPost = base + lean * 0.2
            }
            z -= 0.3
        }
        let rows = path.pts.count / 3
        for r in 0..<UInt32(rows - 1) {
            let a = r * 3
            path.idx += [a, a + 1, a + 3, a + 1, a + 4, a + 3, a + 1, a + 2, a + 4, a + 2, a + 5, a + 4]
        }
        let earth = grainMat(0x65543F, roughness: 0.8, intensity: 0.5)
        t.addChildNode(path.node(earth))
        t.addChildNode(steps.node(mossMaterial(bark: SK.rgb(0x7C7A72), moss: SK.rgb(0x5A7330), pale: SK.rgb(0xB6B8AE), scale: 2.5), shadow: true))
        t.addChildNode(fence.node(mossMaterial(bark: SK.rgb(0x7A7268), moss: SK.rgb(0x56702E), pale: SK.rgb(0xA9AC9E), scale: 2.5), shadow: true))
        t.isHidden = true
        world.addChildNode(t)
        trail = t
    }

    /// The search team: orange and red jackets, helmets and headlamps, a dog.
    private func buildRescue(atBar: Bool) -> SCNNode {
        let r = SCNNode()
        let c = atBar ? barC + SIMD2(-1.4, 1.9) : SIMD2<Float>(1.4, 2.4)
        let team: [(Float, Float, CGFloat, NSColor, SK.Pose)] = [
            (c.x - 1.9, c.y - 0.2, -0.4, SK.rgb(0xE8701E), .standing), (c.x + 1.6, c.y - 0.9, -2.6, SK.rgb(0xC8302A), .standing),
            (c.x - 0.4, c.y + 0.9, .pi + 0.3, SK.rgb(0xE8701E), .waving), (c.x + 2.6, c.y - 2.8, -1.6, SK.rgb(0xE8701E), .standing),
            (c.x - 3.0, c.y - 2.0, 1.1, SK.rgb(0xC8302A), .standing)
        ]
        let helmet = SK.mat(SK.rgb(0xF2F0EA), roughness: 0.35)
        let lampM = SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xF4F8FF))
        lampM.emission.intensity = 4
        let reflect = SK.mat(SK.rgb(0xD8DCDD), roughness: 0.3, metalness: 0.6)
        rescueLamps = []
        for (i, m) in team.enumerated() {
            let p = SK.person(color: m.3, pose: m.4)
            p.position = SCNVector3(CGFloat(m.0), CGFloat(gy(m.0, m.1)), CGFloat(m.1))
            p.eulerAngles.y = m.2
            p.addChildNode(SK.sphere(0.14, helmet, at: SCNVector3(0, 1.73, 0), segments: 14))
            p.addChildNode(SK.box(0.36, 0.05, 0.3, reflect, chamfer: 0.01, at: SCNVector3(0, 1.0, 0.04)))
            let lamp = SK.sphere(0.035, lampM, at: SCNVector3(0, 1.72, 0.13), segments: 8)
            p.addChildNode(lamp)
            if i < 3 {
                // the beam, and the light it throws after dark
                // narrow end at the lamp, pointing ahead and a little down
                let beam = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.8, height: 4.5))
                beam.geometry?.materials = [beamMaterial(SK.rgb(0x6A7380))]
                beam.eulerAngles.x = -(.pi / 2 - 0.35)
                beam.position = SCNVector3(0, 1.72 - 0.343 * 2.25, 0.13 + 0.94 * 2.25)
                beam.castsShadow = false
                beam.renderingOrder = 11
                p.addChildNode(beam)
                let l = SCNLight()
                l.type = .spot
                l.color = SK.rgb(0xE8EEFF)
                l.intensity = 150
                l.spotInnerAngle = 12
                l.spotOuterAngle = 34
                l.attenuationStartDistance = 0
                l.attenuationEndDistance = 12
                l.attenuationFalloffExponent = 2
                l.castsShadow = false
                let ln = SCNNode()
                ln.light = l
                ln.position = SCNVector3(0, 1.72, 0.15)
                ln.eulerAngles = SCNVector3(-0.35, CGFloat.pi, 0)
                p.addChildNode(ln)
                rescueLamps += [beam, ln]
            }
            r.addChildNode(p)
        }
        // the search dog in its orange vest
        let dog = SK.animal(weight: 28, color: SK.rgb(0x3A3028))
        dog.position = SCNVector3(CGFloat(c.x + 0.7), CGFloat(gy(c.x + 0.7, c.y - 0.4)), CGFloat(c.y - 0.4))
        dog.eulerAngles.y = -2.4
        dog.addChildNode(SK.box(0.26, 0.1, 0.34, SK.mat(SK.rgb(0xE8701E), roughness: 0.6), chamfer: 0.03, at: SCNVector3(0, 0.5, 0)))
        r.addChildNode(dog)
        return r
    }

    // MARK: Atmosphere

    /// The forest's own fog: milky and close, but the camp always stays readable. No sky shows through
    /// the cloud and the canopy, so the background (and the light it gives) is a gradient of the fog.
    override func updateEnvironment(_ s: SceneState) {
        super.updateEnvironment(s)
        let elev = s.sunElevation(peak: sunPeak)
        let day = CGFloat(SK.smoothstep(-7, 6, Float(elev)))
        let overcast = CGFloat(max(0, min(1, (1 - s.sun) * 1.15 + s.precip * 0.2)))
        let vis = max(0.03, min(1, s.visibility))
        let dusk = CGFloat(max(0, min(1, 1 - abs(elev - 2) / 10))) * day
        var fogDay = hazeColor.blended(withFraction: overcast * 0.7, of: stormColor) ?? hazeColor
        fogDay = fogDay.blended(withFraction: dusk * 0.35, of: SK.rgb(0x8E8A86)) ?? fogDay
        let fog = nightColor.blended(withFraction: pow(day, 0.8), of: fogDay) ?? fogDay
        scene.fogColor = fog
        scene.fogStartDistance = 5
        scene.fogEndDistance = CGFloat(21 + 140 * pow(vis, 1.4) - 4 * min(1, s.precip / 2))
        scene.fogDensityExponent = 0.95
        let f = fog.usingColorSpace(.deviceRGB) ?? fog
        let key = "\(Int(f.redComponent * 90))|\(Int(f.greenComponent * 90))|\(Int(f.blueComponent * 90))"
        if key != mistKey || mistSky == nil {
            mistKey = key
            let top = f.blended(withFraction: 0.12 * day, of: .white) ?? f
            mistSky = SK.gradientSky(top: top, horizon: f)
        }
        scene.background.contents = mistSky
        scene.lightingEnvironment.contents = mistSky
        // soft, cool green-grey light under the canopy; the flat fill kept low so the forest keeps its depth
        if day > 0.3 { ambientNode.light?.color = SK.rgb(0xDCE6DC) }
        ambientNode.light?.intensity = CGFloat(14 + 46 * day)
        for n in mist {
            n.geometry?.firstMaterial?.multiply.contents = fog.blended(withFraction: 0.08 * day, of: .white) ?? fog
            n.opacity = CGFloat(0.12 + 0.36 * (1 - vis)) * (0.35 + 0.65 * day)
        }
    }

    override func updateWeather(_ s: SceneState) {
        super.updateWeather(s)
        for p in weatherNode.particleSystems ?? [] where p.stretchFactor > 0 {
            p.particleSize = 0.018
            p.stretchFactor = 0.035
            p.birthRate *= 0.6
            p.particleColor = NSColor(white: CGFloat(0.88 - 0.45 * darkness), alpha: CGFloat(0.2 - 0.12 * darkness))
        }
    }

    // MARK: Apply state

    /// 0 by day … 1 at night (from the sun alone: under this cloud `darkness` never drops below ~0.6).
    private func nightK(_ s: SceneState) -> CGFloat {
        1 - CGFloat(SK.smoothstep(-6, 4, Float(s.sunElevation(peak: sunPeak))))
    }

    override func apply(_ s: SceneState, old: SceneState?) {
        let night = nightK(s)
        let atBar = s.has("stream_camp")
        // moving camp happens off-screen: no sliding fire
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        leanTo?.isHidden = atBar
        oldCamp?.isHidden = !atBar
        barCamp?.isHidden = !atBar
        fireNode?.position = atBar ? barFirePos : firePos
        SCNTransaction.commit()

        // wet wood: thick white smoke whenever it burns; the glow in the fog after dark
        if let (smoke, holder) = wetSmoke {
            smoke.particleColor = NSColor(white: 0.86 - 0.62 * night, alpha: 0.3 - 0.14 * night)
            let attached = holder.particleSystems?.contains(smoke) ?? false
            if s.fireLit && !attached { holder.addParticleSystem(smoke) }
            if !s.fireLit && attached { holder.removeParticleSystem(smoke) }
        }
        for g in nightGlows { g.isHidden = night < 0.5 }
        fireHalo?.opacity = s.fireLit ? 0.65 * night : 0
        // by day the low fire hardly lights anything; after dark it fills the lean-to
        // (down on the bar the rock wall across the water is close: a little less light)
        let glowK: CGFloat = atBar ? 0.62 : 1
        fireGlow?.color = SK.color(0.42 * glowK, 0.24 * glowK, 0.1 * glowK).blended(withFraction: 0.6 * (1 - night), of: .black) ?? .black
        lichenMat?.emission.intensity = 0.5 * (1 - night)

        // the distress signal: tape on the twigs, then the SOS in the gap, then a smoke column there
        let signal = s.v("signal")
        let tied = Int((Double(ribbons.count) * max(0, min(1, (signal - 5) / 40))).rounded())
        for (i, r) in ribbons.enumerated() { r.isHidden = i >= tied }
        // the SOS goes down stroke by stroke as the project is worked on (or the signal says it's there)
        let sosK = max(s.project("sos"), s.has("sos") ? 1 : 0, max(0, min(1, (signal - 35) / 25)))
        let strokes = Int((Double(sos.count) * sosK).rounded())
        for (i, n) in sos.enumerated() { n.isHidden = i >= strokes }
        sosExtras?.isHidden = sosK < 0.99
        spreadBlanket?.isHidden = signal < 25 && !s.now("drone_pass")
        // the pyre grows as it's built; lit (or a strong signal), it sends up the smoke column
        let pyreK = max(s.project("pyre"), s.has("pyre") || s.has("pyre_used") ? 1 : 0)
        let smoking = signal >= 70 || (s.has("pyre_used") && (s.now("drone_pass") || s.now("rescue_team")))
        signalFire?.isHidden = pyreK < 0.05 && !smoking
        let heapK = CGFloat(0.35 + 0.65 * (smoking ? max(pyreK, 0.5) : pyreK))
        pyreHeap?.scale = SCNVector3(heapK, heapK, heapK)
        if let (flames, holder) = pyreFlames {
            let attached = holder.particleSystems?.contains(flames) ?? false
            if smoking && !attached { holder.addParticleSystem(flames) }
            if !smoking && attached { holder.removeParticleSystem(flames) }
        }
        signalFire?.childNodes.first(where: { nightGlows.contains($0) })?.opacity = smoking ? 1 : 0
        stretcher?.isHidden = !(s.has("stretcher") || s.project("stretcher") >= 1)
        if let (column, holder) = signalSmoke {
            column.particleColor = NSColor(white: 0.97 - 0.7 * night, alpha: 0.45 - 0.2 * night)
            let attached = holder.particleSystems?.contains(column) ?? false
            if smoking && !attached { holder.addParticleSystem(column) }
            if !smoking && attached { holder.removeParticleSystem(column) }
        }

        // the searchers' lamps far up the slopes after dark, more of them as the search closes in
        let search = s.v("search")
        let lamps = night > 0.6 ? Int((Double(headlamps.count) * max(0, min(1, (search - 10) / 70))).rounded()) : 0
        for (i, h) in headlamps.enumerated() { h.isHidden = i >= lamps }

        // the way out down the stream: cairns, footprints between them
        let walked = Int((Double(cairns.count) * max(0, min(1, s.v("route") / 100))).rounded())
        for (i, c) in cairns.enumerated() { c.isHidden = i >= walked }
        for (i, p) in prints.enumerated() { p.isHidden = i >= walked }

        // the drone over the gap; the herders' trail once it's found
        drone?.isHidden = !(s.has("drone") || s.now("drone_pass"))
        droneBeam?.isHidden = night < 0.6
        trail?.isHidden = !s.has("trail")

        // the search team (wherever the camp is by then)
        let rescued = s.has("rescued") || s.happened("rescue_team") || s.event == "rescue_team"
        if rescued && (rescue == nil || rescueAtBar != atBar) {
            rescue?.removeFromParentNode()
            let r = buildRescue(atBar: atBar)
            world.addChildNode(r)
            rescue = r
            rescueAtBar = atBar
        }
        rescue?.isHidden = !rescued
        for n in rescueLamps { n.isHidden = night < 0.6 }

        showPeople(s, spots: spots(for: s, atBar: atBar, rescued: rescued))
        let c = atBar ? barC + SIMD2(-3.4, 1.4) : SIMD2<Float>(-2.6, 0.9)
        showBodies(s.dead, spots: (0..<4).map { i in
            let x = c.x - Float(i) * 0.75, z = c.y + Float(i) * 0.35
            return Spot(CGFloat(x), CGFloat(gy(x, z)), CGFloat(z), facing: 0.3)
        })
    }

    private func spots(for s: SceneState, atBar: Bool, rescued: Bool) -> [Spot] {
        func at(_ x: Float, _ z: Float, _ facing: CGFloat, _ pose: SK.Pose? = nil) -> Spot {
            Spot(CGFloat(x), CGFloat(gy(x, z)), CGFloat(z), facing: facing, pose: pose)
        }
        if atBar {
            let c = barC
            if rescued {
                return [at(c.x - 0.3, c.y + 1.9, 0.2, .waving), at(c.x + 0.8, c.y + 1.6, -0.3), at(c.x - 1.2, c.y + 1.2, 0.5),
                        at(c.x + 1.5, c.y + 0.6, -0.8), at(c.x - 0.6, c.y - 1.4, 0.1), at(c.x + 0.4, c.y - 1.5, -0.1),
                        at(c.x - 1.8, c.y + 0.2, 0.9), at(c.x + 1.9, c.y - 0.4, -1.1)]
            }
            return [at(c.x - 0.8, c.y - 1.45, 0.15, .sitting), at(c.x + 0.1, c.y - 1.55, 0, .sitting), at(c.x + 0.9, c.y - 1.5, -0.2, .sitting),
                    at(c.x - 0.9, c.y + 0.6, .pi / 2 + 0.3), at(c.x + 1.1, c.y + 0.9, -.pi / 2 - 0.2), at(c.x + 0.2, c.y + 1.9, .pi),
                    at(c.x - 1.6, c.y - 0.3, 1.0), at(c.x + 1.8, c.y - 0.2, -1.2)]
        }
        if rescued {
            // out in front of the lean-to, with the team
            return [at(0.4, 0.9, 0.2, .waving), at(1.8, 1.3, -0.1), at(-0.5, 0.2, 0.6), at(2.9, 0.7, -0.5),
                    at(0.9, -2.2, 0, .sitting), at(1.9, -2.3, 0, .sitting), at(-0.9, -0.9, 0.9), at(3.4, -0.3, -0.9)]
        }
        return [at(0.55, -2.3, 0.25, .sitting), at(1.6, -2.4, 0, .sitting), at(2.6, -2.25, -0.3, .sitting),
                at(0.15, -0.25, .pi / 2 + 0.15), at(2.6, 0.05, -.pi / 2 - 0.15), at(1.45, 1.05, .pi),
                at(-0.45, -1.35, 1.2, .sitting), at(3.35, -0.85, -1.4)]
    }
}

// MARK: - Helpers

fileprivate typealias V3 = SIMD3<Float>

/// sRGB hex → linear RGB (vertex colours are used as linear values).
fileprivate func fogLin(_ hex: UInt32, _ k: Float = 1) -> V3 {
    func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return V3(f(Float((hex >> 16) & 0xFF) / 255), f(Float((hex >> 8) & 0xFF) / 255), f(Float(hex & 0xFF) / 255)) * k
}

fileprivate func fogLen(_ v: V3) -> Float { sqrt(v.x * v.x + v.y * v.y + v.z * v.z) }
fileprivate func fogUnit(_ v: V3) -> V3 { let l = fogLen(v); return l < 1e-6 ? V3(0, 1, 0) : v / l }

/// Rotate roll (z) → pitch (x) → yaw (y), right-handed like SceneKit's euler angles.
fileprivate func fogRot(_ p: V3, yaw: Float, pitch: Float = 0, roll: Float = 0) -> V3 {
    var q = p
    if roll != 0 { let c = cos(roll), s = sin(roll); q = V3(q.x * c - q.y * s, q.x * s + q.y * c, q.z) }
    if pitch != 0 { let c = cos(pitch), s = sin(pitch); q = V3(q.x, q.y * c - q.z * s, q.y * s + q.z * c) }
    if yaw != 0 { let c = cos(yaw), s = sin(yaw); q = V3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c) }
    return q
}

fileprivate struct FogRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x2545F491 }
    mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
    mutating func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
}

/// Merged triangle mesh with vertex colours and UVs: many small parts, one node.
fileprivate struct FogMesh {
    var pts: [V3] = []
    var cols: [V3] = []
    var uvs: [CGPoint] = []
    var idx: [UInt32] = []

    func node(_ m: SCNMaterial, shadow: Bool = false) -> SCNNode {
        guard !idx.isEmpty else { return SCNNode() }
        let g = SK.mesh(pts, idx, colors: cols, uvs: uvs)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.castsShadow = shadow
        return n
    }

    mutating func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V3) {
        let base = UInt32(pts.count)
        pts += [a, b, c, d]
        cols += [col, col, col, col]
        uvs += [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// Box, half extents `h`, rotated roll → pitch → yaw about its centre (flat faces).
    mutating func box(_ c: V3, _ h: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, _ col: V3, top: V3? = nil) {
        func P(_ sx: Float, _ sy: Float, _ sz: Float) -> V3 { c + fogRot(V3(sx * h.x, sy * h.y, sz * h.z), yaw: yaw, pitch: pitch, roll: roll) }
        quad(P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1), col)
        quad(P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1), col)
        quad(P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), top ?? col)
        quad(P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1), col)
        quad(P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1), col)
        quad(P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), col)
    }

    /// Tapered cylinder from `a` to `b` (smooth sides, open ends).
    mutating func tube(_ a: V3, _ b: V3, _ r0: Float, _ r1: Float, _ col: V3, segs: Int = 6, top: V3? = nil) {
        limb([a, b], [r0, r1], [col, top ?? col], segs: segs)
    }

    /// A bent tube through ring centres (branches, logs, culms); u around, v along in meters.
    mutating func limb(_ c: [V3], _ r: [Float], _ col: [V3], segs: Int, wobble: ((Int, Int) -> Float)? = nil) {
        guard c.count >= 2 else { return }
        let base = UInt32(pts.count)
        var along: Float = 0
        var side = V3(1, 0, 0)
        for i in 0..<c.count {
            let dir = fogUnit(i < c.count - 1 ? c[i + 1] - c[i] : c[i] - c[i - 1])
            if i > 0 { along += fogLen(c[i] - c[i - 1]) }
            // carry the frame along so the rings don't twist
            var s = side - dir * simd_dot(side, dir)
            if fogLen(s) < 1e-3 { s = SK.cross(dir, abs(dir.y) < 0.9 ? V3(0, 1, 0) : V3(1, 0, 0)) }
            side = fogUnit(s)
            let up = SK.cross(dir, side)
            let around = max(1, (2 * .pi * r[i] / 0.9).rounded())
            for j in 0...segs {
                let t = Float(j) / Float(segs) * 2 * .pi
                let k = wobble?(i, j % segs) ?? 1
                pts.append(c[i] + (side * cos(t) + up * sin(t)) * (r[i] * k))
                cols.append(col[i])
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs) * around), y: CGFloat(along / 0.9)))
            }
        }
        let row = UInt32(segs + 1)
        for i in 0..<UInt32(c.count - 1) {
            for j in 0..<UInt32(segs) {
                let a = base + i * row + j, b = a + 1, cc = a + row, d = cc + 1
                idx += [a, cc, b, b, cc, d]
            }
        }
    }

    /// Lumpy ellipsoid (crowns, boulders, moss cushions): darker underneath, noise-varied colour.
    mutating func blob(_ c: V3, _ r: V3, _ col: V3, _ nz: SK.Noise, seed: Float, jitter: Float = 0.22, rings: Int = 6, segs: Int = 9,
                       under: Float = 0.5, vary: Float = 0.25, yaw: Float = 0, top: V3? = nil) {
        let base = UInt32(pts.count)
        for i in 0...rings {
            let v = Float(i) / Float(rings)
            let phi = v * .pi
            for j in 0...segs {
                let th = Float(j % segs) / Float(segs) * 2 * .pi
                let d = V3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                let n = nz.value(d.x * 1.7 + seed, d.z * 1.7 + d.y * 1.2 + seed * 0.37)
                let k = 1 + jitter * (2 * n - 1)
                pts.append(c + fogRot(V3(d.x * r.x, d.y * r.y, d.z * r.z) * k, yaw: yaw))
                let shade = under + (1 - under) * (0.5 + 0.5 * d.y)
                var cc = col * shade * (1 - vary * 0.5 + vary * n)
                if let top { cc = cc + (top - cc) * SK.smoothstep(0.1, 0.6, d.y + (n - 0.5) * 0.6) }
                cols.append(cc)
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs) * 3), y: CGFloat(v * 2)))
            }
        }
        let S = UInt32(segs + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segs) {
                let a = base + i * S + j, b = a + 1
                let cc = a + S, d = b + S
                idx += [a, b, cc, b, d, cc]
            }
        }
    }

    /// A leaf-like strip along a polyline (fern fronds, bamboo leaves, lichen beards, tape):
    /// `w` half-widths, `side` the direction across, folded up along the midrib by `fold`.
    mutating func strip(_ c: [V3], _ w: [Float], side: V3, fold: Float = 0, _ col: [V3], up: V3 = V3(0, 1, 0)) {
        guard c.count >= 2 else { return }
        let base = UInt32(pts.count)
        for i in 0..<c.count {
            let lift = up * (w[i] * fold)
            pts += [c[i] - side * w[i] + lift, c[i], c[i] + side * w[i] + lift]
            cols += [col[i] * 0.9, col[i], col[i] * 0.9]
            let v = CGFloat(i) / CGFloat(c.count - 1)
            uvs += [CGPoint(x: 0, y: v), CGPoint(x: 0.5, y: v), CGPoint(x: 1, y: v)]
        }
        for i in 0..<UInt32(c.count - 1) {
            let a = base + i * 3
            idx += [a, a + 3, a + 1, a + 1, a + 3, a + 4]
            idx += [a + 1, a + 4, a + 2, a + 2, a + 4, a + 5]
        }
    }

    /// A ground-hugging sheet over (u, v) ∈ [0, 1]² (paths, tarps, cloth).
    mutating func sheet(nu: Int, nv: Int, _ col: V3, uvScale: (Float, Float) = (1, 1), _ p: (Float, Float) -> V3) {
        let base = UInt32(pts.count)
        for j in 0...nv {
            for i in 0...nu {
                let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                pts.append(p(u, v)); cols.append(col)
                uvs.append(CGPoint(x: CGFloat(u * uvScale.0), y: CGFloat(v * uvScale.1)))
            }
        }
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) {
            for i in 0..<UInt32(nu) {
                let a = base + j * row + i, b = a + 1, c = a + row, d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
    }
}

/// Moss, bark and lichen shaded per pixel on trunks, logs and boulders. The vertex colour carries the
/// mix: red = how mossy, green = tone, blue = pale lichen crust; world-space noise breaks up the edges.
fileprivate func mossMaterial(bark: NSColor, moss: NSColor, pale: NSColor, scale: CGFloat = 0.9) -> SCNMaterial {
    let m = SK.mat(.white, roughness: 0.9)
    m.shaderModifiers = [.surface: """
    #pragma arguments
    float4 barkColor;
    float4 mossColor;
    float4 paleColor;
    float noiseScale;

    #pragma declaration
    float mz_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
    float mz_noise(float3 x) {
        float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
        return mix(mix(mix(mz_hash(i + float3(0,0,0)), mz_hash(i + float3(1,0,0)), f.x),
                       mix(mz_hash(i + float3(0,1,0)), mz_hash(i + float3(1,1,0)), f.x), f.y),
                   mix(mix(mz_hash(i + float3(0,0,1)), mz_hash(i + float3(1,0,1)), f.x),
                       mix(mz_hash(i + float3(0,1,1)), mz_hash(i + float3(1,1,1)), f.x), f.y), f.z);
    }
    float mz_fbm(float3 p) { float a = 0.5; float s = 0.0; for (int k = 0; k < 4; k++) { s += a * mz_noise(p); p *= 2.13; a *= 0.5; } return s / 0.9375; }

    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 v = _surface.diffuse.rgb;
    float3 q = wp * noiseScale;
    float fw = length(fwidth(q));
    float n = mix(mz_fbm(q), 0.5, smoothstep(0.35, 1.2, fw));
    float fine = mix(mz_fbm(q * 5.0 + 3.1), 0.5, smoothstep(0.06, 0.25, fw));
    float m = smoothstep(0.40, 0.60, v.r + (n - 0.5) * 0.85 + wn.y * 0.22 + (fine - 0.5) * 0.25);
    float p = smoothstep(0.52, 0.72, v.b + (fine - 0.5) * 0.9 + (n - 0.5) * 0.3) * (1.0 - m);
    float3 c = mix(barkColor.rgb * (0.7 + 0.6 * fine), mossColor.rgb * (0.62 + 0.7 * n) * (0.85 + 0.3 * fine), m);
    c = mix(c, paleColor.rgb * (0.85 + 0.3 * fine), p);
    _surface.diffuse.rgb = c * (0.55 + 0.9 * v.g);
    """]
    m.setValue(NSValue(scnVector4: SK.linear(bark)), forKey: "barkColor")
    m.setValue(NSValue(scnVector4: SK.linear(moss)), forKey: "mossColor")
    m.setValue(NSValue(scnVector4: SK.linear(pale)), forKey: "paleColor")
    m.setValue(NSNumber(value: Double(scale)), forKey: "noiseScale")
    m.normal.contents = barkNormalImage()
    m.normal.wrapS = .repeat
    m.normal.wrapT = .repeat
    m.normal.mipFilter = .linear
    m.normal.maxAnisotropy = 8
    m.normal.intensity = 0.75
    return m
}

private let barkLock = NSLock()
nonisolated(unsafe) private var barkCache: NSImage?

/// Normal map of furrowed bark: ridges running along the trunk (v), broken up by fine noise.
fileprivate func barkNormalImage() -> NSImage {
    barkLock.lock(); defer { barkLock.unlock() }
    if let img = barkCache { return img }
    let size = 256
    let nz = SK.Noise(seed: 2741)
    var hgt = [Float](repeating: 0, count: size * size)
    for y in 0..<size {
        for x in 0..<size {
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            // tileable along u by sampling on a circle; furrows stretched along v
            let a = u * 2 * .pi
            let r = nz.ridged(cos(a) * 1.6 + 5, sin(a) * 1.6 + v * 1.4 + 5, octaves: 3)
            let f = nz.fbm(cos(a) * 4 + 9, sin(a) * 4 + v * 10, octaves: 3)
            hgt[y * size + x] = r * 0.8 + f * 0.35
        }
    }
    var px = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let h = { (i: Int, j: Int) in hgt[((j + size) % size) * size + (i + size) % size] }
            let dx = (h(x + 1, y) - h(x - 1, y)) * 10, dy = (h(x, y + 1) - h(x, y - 1)) * 10
            let l = sqrt(dx * dx + dy * dy + 1)
            let i = (y * size + x) * 4
            px[i] = UInt8((-dx / l * 0.5 + 0.5) * 255); px[i + 1] = UInt8((-dy / l * 0.5 + 0.5) * 255); px[i + 2] = UInt8((1 / l * 0.5 + 0.5) * 255)
        }
    }
    let img = SK.image(from: px, size: size)
    barkCache = img
    return img
}

/// Plain material for vertex-coloured meshes (foliage, ferns, lichen).
fileprivate func leafMaterial(roughness: CGFloat = 0.8, doubleSided: Bool = true) -> SCNMaterial {
    let m = SK.mat(.white, roughness: roughness, doubleSided: doubleSided)
    return m
}

private let glowLock = NSLock()
nonisolated(unsafe) private var glowCache: NSImage?

/// A soft round glow with the falloff in the colour itself (opaque black outside), for additive sprites.
fileprivate func glowImage() -> NSImage {
    glowLock.lock(); defer { glowLock.unlock() }
    if let img = glowCache { return img }
    let size = 64
    var px = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let dx = (Float(x) + 0.5) / Float(size) * 2 - 1, dy = (Float(y) + 0.5) / Float(size) * 2 - 1
            let r = min(1, sqrt(dx * dx + dy * dy))
            let g = UInt8(255 * pow(1 - r, 2.4))
            let i = (y * size + x) * 4
            px[i] = g; px[i + 1] = g; px[i + 2] = g
        }
    }
    let img = SK.image(from: px, size: size)
    glowCache = img
    return img
}

/// A soft drifting bank of mist: alpha from fractal noise, faded to nothing at the edges.
fileprivate func mistImage(seed: UInt64) -> NSImage {
    let w = 256, h = 128
    let nz = SK.Noise(seed: seed)
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let u = Float(x) / Float(w), v = Float(y) / Float(h)
            let edge = SK.smoothstep(0, 0.3, u) * SK.smoothstep(0, 0.3, 1 - u) * SK.smoothstep(0, 0.45, v) * SK.smoothstep(0, 0.3, 1 - v)
            let n = nz.fbm(u * 5, v * 2.5, octaves: 4)
            let a = max(0, min(1, (n - 0.32) * 1.9)) * edge
            let i = (y * w + x) * 4
            // premultiplied white
            let b = UInt8(255 * a)
            px[i] = b; px[i + 1] = b; px[i + 2] = b; px[i + 3] = b
        }
    }
    return SK.image(from: px, size: w, height: h)
}
