import SceneKit
import AppKit
import CoreText

/// 冰封 · 高速雪困 — the Beijing–Zhuhai Expressway (京珠高速) in the hills south of Chenzhou, Hunan,
/// 26 January 2008. Days of freezing rain have sealed everything in ice — the road, the trees and
/// bamboo bowed to the ground, the power lines (the pylons are coming down, the region has no power) —
/// and the homeward Spring Festival traffic has stopped dead on an uphill stretch.
///
/// Layout (metres): the expressway runs along x; y = 0 is its surface where the group is stranded.
/// North (uphill, toward Chenzhou) is +x, east is +z. The road is level by the group, then climbs
/// (4.5 %) to a crest ~390 m ahead where the queue disappears, and dips beyond (`ry`). The group's
/// northbound carriageway lies on the +z side of the planted central reserve (|z| < 1): inner lane
/// z ≈ 3.6, outer lane z ≈ 7.4, hard shoulder 9.25…12.25, the W-beam guardrail at z ≈ 12.4. East of
/// it the embankment drops 13 m into the valley: frozen paddies, 坳上村 on the far side climbing the
/// slope, a 10 kV line along the foot of the bank, a 220 kV line crossing the valley and the road
/// from the far ridge. West of the southbound carriageway the road is cut into the hillside: a 12 m
/// rock cut held by a concrete frame, bamboo and firs bowed over its edge. The group: a sleeper coach in the
/// inner lane, a semi-trailer of sugar oranges (its doors open on the cartons) in the outer lane, the
/// black Passat across the head of the hard-shoulder queue behind them, the silver hatchback behind
/// the semi; ahead a gap of a dozen metres, then the queue climbing into the mist. The service area
/// sits on the crest on the east side. The default camera hangs above the southbound lanes behind the
/// group and looks up the road and out over the valley.
///
/// Shown from state:
/// - var `ice` (0–100): the glaze on everything (a white crust on top, gloss and drips on the sides,
///   the road a sheet of rutted ice), icicles in three tiers, the trees bowed further, and at the top
///   end branches and snapped trees down.
/// - var `clear` (0–100): the road crews chipping their way back down from the crest: beyond their
///   front the carriageway is wet black asphalt, salted, the hard-shoulder queue towed away, a loader
///   and a salt spreader at work, ice heaped along the edges — until they reach the group.
/// - `fireLit` (the engines running for the heaters): exhaust steaming from the group's vehicles,
///   their windows lit at night; var `co` (hidden): their windows fogging up.
/// - project `fire_barrel` / flag `bonfire`: the oil-drum fire behind the semi (burning when lit),
///   moved to the guardrail with `barrel_moved`; event `fireworks_fire`: the semi's cargo on fire.
/// - flag `market` (by day): villagers up the bank from 坳上村 with baskets on poles, a stall by the
///   guardrail, a pot of tea eggs steaming. `oranges_*`: cartons of oranges out on the shoulder.
///   `ropes` / project `tire_ropes`: straw rope on the group's drive wheels.
/// - event `army_arrives`: armed police coming up from behind in single file along the central
///   reserve with picks and shovels, a red flag at their head; flag `army`: breaking the ice round the
///   group, ice heaped along the lanes, the flag planted in the reserve.
/// - flag `walked`: footprints in the slush along the guardrail, leading ahead.
/// - flag `pylon_down`: the 220 kV tower on the far ridge folded over, its conductors trailing down
///   into the paddies; `lines_marked`: sticks with red rags round the wire.
/// - flag `road_open` / event `road_opens`: lights on all up the queue, gaps opening, a police car
///   with its light bar going and an officer waving traffic on; the message board changes.
/// - flag `village`: everyone down in 坳上村. Night: hazard lights blinking up the hill, a few dome
///   lights, candles in the village; dusk; freezing rain falls as rain.
final class IceboundScene: ScenarioScene {

    // MARK: - Set-out

    private let noise = SK.Noise(seed: 2008)
    /// Lane centres (z) of the northbound carriageway; mirrored southbound.
    private let laneIn: Float = 3.625, laneOut: Float = 7.375, laneHard: Float = 10.6
    /// The oil drum: behind the semi's tail, and by the guardrail once it has been moved.
    private let drumAt = SIMD2<Float>(-7.1, 7.5), drumMoved = SIMD2<Float>(-3.4, 11.85)
    /// The group's coach (inner lane) and semi (outer lane): centre x.
    private let coachX: Float = -1, semiX: Float = 3.0
    /// The 220 kV towers: on the far ridge (the one that comes down), at the foot of the bank, above the cut.
    private let towerA = SIMD2<Float>(170, 176), towerB = SIMD2<Float>(186, 47), towerC = SIMD2<Float>(204, -78)
    /// The service area's forecourt east of the road: x0, x1, z0, z1.
    private let pad = SIMD4<Float>(360, 470, 12.25, 66)
    /// The gap ahead of the group where the soldiers break the ice (x).
    private let hackX0: Float = 5.5, hackX1: Float = 23
    /// Roughly where the default camera hangs (levels of detail).
    private let eye = SIMD3<Float>(-27, 8, -4)

    // MARK: - Nodes the game changes

    private var glazeMats: [SCNMaterial] = []
    private var vanishMats: [SCNMaterial] = []
    private var roadMat: SCNMaterial?
    private var groundMat: SCNMaterial?
    /// Icicles gathered while building, shown in three tiers as the ice thickens.
    private var iceAcc = [IBMesh(), IBMesh(), IBMesh()]
    private var icicles: [SCNNode] = []
    private let treesLight = SCNNode(), treesHeavy = SCNNode()
    private var fallen: SCNNode?
    private var hazards: [SCNNode] = []
    private var bodyMat: SCNMaterial?, glassMat: SCNMaterial?, fruitMat: SCNMaterial?
    private var hazardMat: SCNMaterial?, litMat: SCNMaterial?, groupGlass: SCNMaterial?
    private var hazGlow: SCNMaterial?, tailGlowN: SCNMaterial?, tailGlowS: SCNMaterial?, headGlow: SCNMaterial?
    private var tailN: SCNMaterial?, headN: SCNMaterial?, tailS: SCNMaterial?, headS: SCNMaterial?
    private var candleMat: SCNMaterial?
    private var drum: SCNNode?
    private var drumFire: [(SCNParticleSystem, SCNNode)] = []
    private var drumLight: SK.FlickerLight?
    private var holesMat: SCNMaterial?
    private var cargoFire: [(SCNParticleSystem, SCNNode)] = []
    private var cargoLight: SK.FlickerLight?
    private var exhaust: [(SCNParticleSystem, SCNNode)] = []
    private var cartons: SCNNode?
    private var ropes: SCNNode?
    private var crew: SCNNode?, crewTruck: SCNNode?
    private var crewLight: SCNNode?
    private var salt: (SCNParticleSystem, SCNNode)?
    private var windrow: [(SCNNode, Float)] = []
    private var soldiers: SCNNode?, column: SCNNode?, chunks: SCNNode?
    private var market: SCNNode?
    private var eggSteam: (SCNParticleSystem, SCNNode)?
    private var police: SCNNode?
    private var towerUp: SCNNode?, towerDown: SCNNode?, wireMarks: SCNNode?
    private var chimneys: [(SCNParticleSystem, SCNNode)] = []
    private var vmsMat: SCNMaterial?
    private var vmsImages: (closed: NSImage, open: NSImage)?
    private var lastGlaze: Float = -1

    required init() {
        super.init()
        skyStyle = .overcast
        sunPeak = 46                 // ~25.8°N at the end of January
        sunAzimuth = 225             // what sun there is comes from the south-west, behind the camera
        exposure = -0.2
        sunScale = 0.9
        iblScale = 1.05
        hazeColor = SK.rgb(0xBDC5CC)
        stormColor = SK.rgb(0xA3ABB3)
        nightColor = SK.rgb(0x0A0E14)
        clearVisibility = 1500
        weatherArea = 70
        weatherCenter = SCNVector3(-8, 22, 2)
        precipKind = .rain
        cameraTarget = SCNVector3(6, 3, 8)
        cameraDistance = 36
        cameraYaw = -110
        cameraPitch = 8
        cameraFOV = 42
        minPitch = 2
        // the flat light of freezing rain wants a little more bite
        cameraNode.camera?.contrast = 0.22
        cameraNode.camera?.saturation = 1.0
    }

    // MARK: - The road's profile

    /// Grade along x: level by the group, the climb, the crest ~390 m ahead, gently down beyond.
    private static func gradeAt(_ x: Float) -> Float {
        0.045 * SK.smoothstep(30, 100, x) * (1 - SK.smoothstep(280, 420, x)) - 0.022 * SK.smoothstep(330, 470, x)
    }

    /// The road's level every metre from x = −700.
    private static let profile: [Float] = {
        var ys: [Float] = []
        ys.reserveCapacity(2202)
        var y: Float = 0
        for i in 0...2201 {
            ys.append(y)
            y += gradeAt(Float(i) - 699.5)
        }
        let y0 = ys[700]
        return ys.map { $0 - y0 }
    }()

    /// The road's level at x.
    private func ry(_ x: Float) -> Float {
        let t = min(max(x + 700, 0), 2200.999)
        let i = Int(t), f = t - Float(i)
        return IceboundScene.profile[i] * (1 - f) + IceboundScene.profile[i + 1] * f
    }

    /// The road's pitch at x (radians, + uphill toward +x).
    private func pitchAt(_ x: Float) -> Float { atan(IceboundScene.gradeAt(x)) }

    /// A vehicle's frame on the road: centre (x, z), facing +x (north) or −x.
    private func onRoad(_ x: Float, _ z: Float, north: Bool, skew: Float = 0) -> IBFrame {
        IBFrame(o: IV3(x, ry(x), z), yaw: (north ? 0 : .pi) + skew, roll: north ? pitchAt(x) : -pitchAt(x))
    }

    // MARK: - Terrain

    /// The ground as it was before the expressway: the hillside the road is cut into (west), the
    /// valley 13 m below with its paddies and 坳上村 (east), the far ridge, hills closing in at the crest.
    private func natural(_ x: Float, _ z: Float) -> Float {
        let d = abs(z) - 13
        var h: Float
        if z < 0 {
            h = ry(x) + 4.5 + 0.42 * d + 34 * (1 - exp(-d / 140))
            h += (noise.fbm(x / 120 + 3, z / 120, octaves: 4) - 0.5) * 18 * SK.smoothstep(10, 120, d)
        } else {
            h = -13 + 0.012 * x + 42 * SK.smoothstep(60, 230, d)
            h += (noise.fbm(x / 140 + 11, z / 140, octaves: 4) - 0.5) * 22 * SK.smoothstep(60, 200, d)
        }
        // where the road tops out the hills close in on both sides
        let saddle = SK.smoothstep(290, 420, x) * (1 - SK.smoothstep(560, 760, x))
        if saddle > 0 { h += saddle * (z > 0 ? 20 : 8) * (1 - exp(-d / 30)) }
        // hummocks and hollows (they also shape the terraces' contours)
        h += (noise.fbm(x / 30, z / 30, octaves: 3) - 0.5) * 2.2 * SK.smoothstep(4, 30, d)
        return h
    }

    /// 0…1: how much of the ground here is paddy terraces (the valley floor and its lower slopes).
    private func paddy(_ x: Float, _ z: Float) -> Float {
        guard z > 0 else { return 0 }
        let d = z - 13
        var k: Float = SK.smoothstep(19, 24, d) * (1 - SK.smoothstep(150, 185, d))
        k *= (1 - SK.smoothstep(300, 360, x)) * SK.smoothstep(-560, -460, x)
        guard k > 0 else { return 0 }
        let edge = noise.fbm(x / 80 + 40, z / 80, octaves: 2) + 0.35 * (1 - SK.smoothstep(60, 130, d))
        return k * SK.smoothstep(0.32, 0.42, edge)
    }

    /// The natural ground levelled into terraces where there are paddies.
    private func terraced(_ x: Float, _ z: Float, _ n: Float) -> Float {
        let k = paddy(x, z)
        guard k > 0.001 else { return n }
        let step: Float = 0.8
        let t = n / step
        let f = t - floor(t)
        let level = (floor(t) + SK.smoothstep(0.84, 1.0, f)) * step
        return n + (level - n) * k
    }

    /// Ground height with the embankment (1:1.5), the rock cut (1:0.8 above a ditch) and the service
    /// area's forecourt; under the paved surfaces it drops out of sight.
    private func height(_ x: Float, _ z: Float) -> Float {
        let az = abs(z), f = ry(x)
        if az < 12.1 { return f - 0.8 }
        if z > 0 && x > pad.x && x < pad.y && z < pad.w { return f - 0.8 }
        var d = az - 13
        if z > 0 && x > pad.x - 60 && x < pad.y + 60 {
            let dx = max(max(pad.x - x, x - pad.y), 0), dz = max(z - pad.w, 0)
            d = min(d, sqrt(dx * dx + dz * dz))
        }
        if d <= 0 { return f - 0.03 - 0.77 * (1 - SK.smoothstep(12.1, 12.3, az)) }
        let n = terraced(x, z, natural(x, z)) - f
        let fill = max(n, -0.03 - d / 1.5)
        let ditch: Float = -0.5 + 0.47 * (1 - SK.smoothstep(0.1, 0.6, d))
        // the rock cut: benches and ribs, not a plane
        let framed = SK.smoothstep(-200, -150, x) * (1 - SK.smoothstep(300, 360, x))
        let rough = (noise.fbm(x / 7 + 30, (z + f) / 5, octaves: 3) - 0.5) * (2.4 - 2.1 * framed) * SK.smoothstep(2, 5, d)
        let cut = min(n, max(ditch, (d - 1.6) * 1.25 + rough))
        let k = SK.smoothstep(-0.8, 0.8, n)
        return f + fill + (cut - fill) * k
    }

    /// Where someone stands (on the carriageway: its surface).
    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat {
        abs(z) < 12.3 ? CGFloat(ry(Float(x))) : CGFloat(height(Float(x), Float(z)))
    }

    /// Grid coordinates from contiguous (from, to, step) spans.
    private static func axis(_ spans: [(Float, Float, Float)]) -> [Float] {
        var a: [Float] = []
        for (lo, hi, st) in spans {
            let n = max(1, Int(((hi - lo) / st).rounded()))
            for i in 0..<n { a.append(lo + (hi - lo) * Float(i) / Float(n)) }
        }
        if let last = spans.last { a.append(last.1) }
        return a
    }

    /// Large-scale tint of the ground (×): gravel verges, frosted grass on the bank, darker woods.
    private func groundTint(_ x: Float, _ y: Float, _ z: Float) -> IV3 {
        let az = abs(z)
        let v = 0.9 + 0.2 * noise.value(x / 11 + 50, z / 11)
        if az <= 13.05 { return IV3(0.84, 0.84, 0.83) * v }
        let d = az - 13
        if z < 0 {
            // the rock cut, streaked with seepage, then the wooded hillside above it
            let streak = noise.value(x / 1.7 + 9, y / 9)
            let rock = 1 - SK.smoothstep(12, 16, d)
            return IV3(0.78, 0.78, 0.8) * (v * (1 - 0.25 * rock * streak) * (1 - 0.3 * SK.smoothstep(14, 30, d)))
        }
        // the bank: dead grass under the ice; the paddies: dark ice over the water, bunds and risers of
        // earth along the contours; the woods
        let bank = 1 - SK.smoothstep(17, 21, d)
        let pk = paddy(x, z)
        let wood = (1 - pk) * SK.smoothstep(40, 90, d)
        var c = IV3(v, v, v) * (1 - bank) + IV3(0.62, 0.68, 0.58) * (v * bank)
        if pk > 0.01 {
            let ph = natural(x, z) / 0.8
            let f = ph - floor(ph)
            let riser = SK.smoothstep(0.74, 0.84, f) + (1 - SK.smoothstep(0.0, 0.09, f))
            let field = IV3(0.8, 0.86, 0.92) * (0.92 + 0.16 * noise.value(x / 6 + 3, z / 6))
            c = c * (1 - pk) + (field * (1 - min(1, riser)) + IV3(0.44, 0.41, 0.35) * min(1, riser)) * (v * pk)
        }
        c *= 1 - 0.38 * wood
        return c
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        buildTerrain()
        buildRoad()
        buildMedianAndRails()
        buildCutFrame()
        buildLines()
        buildTrees()
        buildVillage()
        buildServiceArea()
        buildSigns(english: s.lang == "en")
        buildJam()
        buildDrum()
        buildCrew()
        buildArmy()
        buildMarket(english: s.lang == "en")
        buildPolice()
        // the icicles from everything above, in three tiers
        let im = SK.mat(SK.rgb(0xD6E4EC), roughness: 0.05, metalness: 0.05)
        vanishing(im)
        for m in iceAcc {
            let n = m.node(im, shadow: false)
            world.addChildNode(n)
            icicles.append(n)
        }
        iceAcc = []
    }

    // MARK: Materials

    /// Vertex-coloured PBR material that takes the ice glaze (a crust on top, gloss and drips on the
    /// sides, more of them with `side`).
    private func glazed(_ roughness: CGFloat = 0.8, metal: CGFloat = 0, side: CGFloat = 0.25, crust: CGFloat = 1, doubleSided: Bool = false) -> SCNMaterial {
        let m = SK.mat(.white, roughness: roughness, metalness: metal, doubleSided: doubleSided)
        m.shaderModifiers = [.surface: ibGlazeShader]
        m.setValue(NSNumber(value: 0.5), forKey: "glaze")
        m.setValue(NSNumber(value: Double(side)), forKey: "sideIce")
        m.setValue(NSNumber(value: Double(crust)), forKey: "crust")
        glazeMats.append(m)
        return m
    }

    /// Lets the vehicles in a merged mesh drive off: each carries a key in its texture coordinates
    /// (x: its front, gone once the clearing passes it; y: a lot, drawn when the queue starts moving).
    private func vanishing(_ m: SCNMaterial) {
        var mods = m.shaderModifiers ?? [:]
        mods[.geometry] = ibVanishShader
        m.shaderModifiers = mods
        m.setValue(NSNumber(value: 9999.0), forKey: "goneX")
        m.setValue(NSNumber(value: -1.0), forKey: "thinK")
        vanishMats.append(m)
    }

    private func glow(_ c: NSColor, _ k: CGFloat = 2) -> SCNMaterial {
        let m = SK.mat(.black, roughness: 0.4, emission: c)
        m.emission.intensity = k
        return m
    }

    // MARK: Terrain, road, central reserve

    private func buildTerrain() {
        let xs = IceboundScene.axis([(-700, -150, 12), (-150, 250, 2.5), (250, 520, 4), (520, 900, 8), (900, 1500, 25)])
        let zs = IceboundScene.axis([(-900, -400, 20), (-400, -160, 6), (-160, -40, 2.5), (-40, -13, 0.9), (-13, -12.25, 0.75),
                                     (-12.25, -12.1, 0.15), (-12.1, 12.1, 4.84), (12.1, 12.25, 0.15), (12.25, 13, 0.75),
                                     (13, 36, 0.75), (36, 200, 1.6), (200, 420, 6), (420, 900, 20)])
        let nx = xs.count, nz = zs.count
        var pts: [IV3] = [], cols: [IV3] = []
        pts.reserveCapacity(nx * nz)
        cols.reserveCapacity(nx * nz)
        for z in zs {
            for x in xs {
                let y = height(x, z)
                pts.append(IV3(x, y, z))
                cols.append(groundTint(x, y, z))
            }
        }
        var idx = [UInt32](repeating: 0, count: (nx - 1) * (nz - 1) * 6)
        idx.withUnsafeMutableBufferPointer { b in
            var t = 0
            for j in 0..<(nz - 1) {
                for i in 0..<(nx - 1) {
                    let a = UInt32(j * nx + i), c = a + UInt32(nx)
                    b[t] = a; b[t + 1] = c; b[t + 2] = a + 1
                    b[t + 3] = a + 1; b[t + 4] = c; b[t + 5] = c + 1
                    t += 6
                }
            }
        }
        // ice over the paddies and the frozen grass on level ground; earth, dead grass and rock on the steeps
        let gm = SK.terrainMaterial(flat: SK.rgb(0xC2C9CE), steep: SK.rgb(0x77746A), from: 0.2, to: 0.42,
                                    grain: 0.22, noiseScale: 0.07, roughness: 0.6)
        SK.addGrain(gm, scale: 10, strength: 2.5, intensity: 0.3)
        groundMat = gm
        let g = ibGeometry(pts, cols, nil, idx)
        g.materials = [gm]
        let n = SCNNode(geometry: g)
        n.castsShadow = false
        world.addChildNode(n)

        // distant hills beyond the detailed ground (pushed under it inside)
        let farMat = SK.terrainMaterial(flat: SK.rgb(0xAEB6BB), steep: SK.rgb(0x5F5E55), from: 0.25, to: 0.5, grain: 0.1, noiseScale: 0.01)
        let far = SK.terrain(size: 5000, segments: 110, height: { x, z in
            let inside = x > -690 && x < 1490 && abs(z) < 890
            return self.natural(x, z) - (inside ? 40 : 0)
        }, color: { _, _, _, _ in SIMD3(1, 1, 1) }, material: farMat, uvRepeat: 300)
        world.addChildNode(far)
    }

    private func buildRoad() {
        let m = SK.mat(.white, roughness: 0.6)
        m.shaderModifiers = [.surface: ibRoadShader]
        let initial: [(String, Double)] = [("glaze", 0.5), ("clearX", 9999), ("openK", 0), ("walkK", 0),
                                           ("hackX0", Double(hackX0)), ("hackX1", Double(hackX1)), ("hackK", 0)]
        for (k, v) in initial { m.setValue(NSNumber(value: v), forKey: k) }
        roadMat = m
        var deck = IBMesh()
        let w = IV3(1, 1, 1)
        var x: Float = -700
        while x < 1500 {
            let xb = min(1500, x + (x > 0 && x < 800 ? 10 : 25))
            let ya = ry(x), yb = ry(xb)
            deck.quad(IV3(x, ya, 1), IV3(x, ya, 12.25), IV3(xb, yb, 12.25), IV3(xb, yb, 1), w)
            deck.quad(IV3(x, ya, -12.25), IV3(x, ya, -1), IV3(xb, yb, -1), IV3(xb, yb, -12.25), w)
            // the edges drop to the earth shoulder
            deck.quad(IV3(x, ya - 0.8, 12.25), IV3(xb, yb - 0.8, 12.25), IV3(xb, yb, 12.25), IV3(x, ya, 12.25), w)
            deck.quad(IV3(xb, yb - 0.8, -12.25), IV3(x, ya - 0.8, -12.25), IV3(x, ya, -12.25), IV3(xb, yb, -12.25), w)
            x = xb
        }
        // the service area's forecourt (the same icy surface), following the crest
        var px = pad.x
        while px < pad.y {
            let pb = min(pad.y, px + 10)
            let ya = ry(px), yb = ry(pb)
            deck.quad(IV3(px, ya, pad.z), IV3(px, ya, pad.w), IV3(pb, yb, pad.w), IV3(pb, yb, pad.z), w)
            deck.quad(IV3(px, ya - 0.8, pad.w), IV3(pb, yb - 0.8, pad.w), IV3(pb, yb, pad.w), IV3(px, ya, pad.w), w)
            px = pb
        }
        let y0 = ry(pad.x), y1 = ry(pad.y)
        deck.quad(IV3(pad.x, y0 - 0.8, pad.z), IV3(pad.x, y0 - 0.8, pad.w), IV3(pad.x, y0, pad.w), IV3(pad.x, y0, pad.z), w)
        deck.quad(IV3(pad.y, y1 - 0.8, pad.w), IV3(pad.y, y1 - 0.8, pad.z), IV3(pad.y, y1, pad.z), IV3(pad.y, y1, pad.w), w)
        world.addChildNode(deck.node(m, shadow: false))
    }

    private func buildMedianAndRails() {
        var conc = IBMesh(), steel = IBMesh(), shrubs = IBMesh()
        var rng = IBRng(31)
        let soil = ibLin(0x5F5B4F), kerb = ibLin(0xA6A6A0), beam = ibLin(0xA3A9AD), post = ibLin(0x80868B)
        /// Pieces along the road, shorter where it bends over the crest.
        func pieces(_ body: (Float, Float) -> Void) {
            var x: Float = -700
            while x < 1500 {
                let xb = min(1500, x + (x > 20 && x < 800 ? 8 : 25))
                body(x, xb)
                x = xb
            }
        }
        pieces { x0, x1 in
            let xc = (x0 + x1) / 2, hx = (x1 - x0) / 2 + 0.02, y = ry(xc), p = pitchAt(xc)
            conc.box(IV3(xc, y + 0.05, 0), IV3(hx, 0.13, 0.85), soil, roll: p)
            conc.box(IV3(xc, y + 0.06, 0.92), IV3(hx, 0.15, 0.08), kerb, roll: p)
            conc.box(IV3(xc, y + 0.06, -0.92), IV3(hx, 0.15, 0.08), kerb, roll: p)
        }
        // W-beam guardrails on both sides of the central reserve and along the hard shoulders' outer edges
        let rails: [(Float, Float)] = [(1.12, 1), (-1.12, -1), (12.42, -1), (-12.42, 1)]
        let iceCol = ibLin(0xD6E4EC)
        for (zr, face) in rails {
            pieces { x0, x1 in
                if zr > 12 && x1 > pad.x - 25 && x0 < pad.y + 5 { return }      // the slip road into the service area
                let xc = (x0 + x1) / 2, hx = (x1 - x0) / 2 + 0.02, y = ry(xc), p = pitchAt(xc)
                steel.box(IV3(xc, y + 0.6, zr), IV3(hx, 0.155, 0.018), beam, roll: p)
                steel.box(IV3(xc, y + 0.525, zr + face * 0.02), IV3(hx, 0.035, 0.012), beam * 1.12, roll: p)
                steel.box(IV3(xc, y + 0.675, zr + face * 0.02), IV3(hx, 0.035, 0.012), beam * 1.12, roll: p)
            }
            var xp: Float = -700
            while xp < 1500 {
                if !(zr > 12 && xp > pad.x - 25 && xp < pad.y + 5) {
                    steel.box(IV3(xp, ry(xp) + 0.38, zr - face * 0.12), IV3(0.055, 0.38, 0.055), post)
                }
                xp += (xp > -160 && xp < 320) ? 4 : 8
            }
            // icicles under the beam, near enough to see
            var xi: Float = -60
            while xi < 200 {
                let r = rng.next()
                let tier = r < 0.4 ? 0 : (r < 0.72 ? 1 : 2)
                let len = (0.04 + 0.08 * rng.next()) * (1 + 0.8 * Float(tier))
                iceAcc[tier].icicle(IV3(xi, ry(xi) + 0.447, zr + face * 0.008), len, 0.007 + 0.004 * Float(tier), iceCol)
                xi += rng.r(0.07, 0.2)
            }
        }
        // a clipped hedge of privet in the central reserve, its top crusted with ice, sagging here and there
        pieces { x0, x1 in
            let xc = (x0 + x1) / 2, hx = (x1 - x0) / 2, y = ry(xc), p = pitchAt(xc)
            let g = ibLin(0x3E5636) * rng.r(0.9, 1.08)
            shrubs.box(IV3(xc, y + 0.62, 0), IV3(hx, 0.5, 0.52), g, roll: p)
            shrubs.box(IV3(xc, y + 1.15, 0), IV3(hx, 0.07, 0.4), g * 1.05, roll: p)
        }
        world.addChildNode(conc.node(glazed(0.85, side: 0.2)))
        world.addChildNode(steel.node(glazed(0.35, metal: 0.6, side: 0.55)))
        world.addChildNode(shrubs.node(glazed(0.85, side: 0.3)))
    }

    /// The rock cut's face at height `h` above the road (its z, by bisection).
    private func faceZ(_ x: Float, _ h: Float) -> Float {
        var lo: Float = -45, hi: Float = -13.2
        let target = ry(x) + h
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if height(x, mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// How high the rock cut stands at x (where its face meets the hillside).
    private func cutTop(_ x: Float) -> Float {
        var d: Float = 2
        while d < 34 {
            if (d - 1.6) * 1.25 >= natural(x, -(13 + d)) - ry(x) { return (d - 1.6) * 1.25 }
            d += 0.25
        }
        return 40
    }

    /// The concrete frame anchored onto the rock cut west of the road (锚杆框架梁): beams across and
    /// up the face in 3 m squares, and the lined ditch at its foot.
    private func buildCutFrame() {
        var m = IBMesh()
        let conc = ibLin(0x96938B)
        var x: Float = -150
        var topA = cutTop(x)
        while x < 330 {
            let xb = x + 3.2
            let topB = cutTop(xb)
            for h in [Float(1.2), 4.2, 7.2, 10.2, 13.2] where h < min(topA, topB) - 0.9 {
                m.tube(IV3(x, ry(x) + h, faceZ(x, h) + 0.1), IV3(xb, ry(xb) + h, faceZ(xb, h) + 0.1), 0.16, 0.16, conc, segs: 4)
            }
            var prev: IV3? = nil
            var h: Float = 0.4
            while h < topA - 0.7 {
                let p = IV3(x, ry(x) + h, faceZ(x, h) + 0.1)
                if let q = prev { m.tube(q, p, 0.16, 0.16, conc, segs: 4) }
                prev = p
                h += 1.5
            }
            x = xb
            topA = topB
        }
        var xd: Float = -150
        while xd < 330 {
            let xe = xd + 10, xc = xd + 5, y = ry(xc), p = pitchAt(xc)
            m.box(IV3(xc, y - 0.22, -13.12), IV3(5.02, 0.24, 0.07), conc, roll: p)
            m.box(IV3(xc, y - 0.1, -14.55), IV3(5.02, 0.36, 0.08), conc, roll: p)
            xd = xe
        }
        world.addChildNode(m.node(glazed(0.85, side: 0.35, crust: 0.45)))
    }

    // MARK: Power lines

    private func buildLines() {
        var poles = IBMesh(), wires = IBMesh()
        var rng = IBRng(53)
        let conc = ibLin(0xA09C92), steel = ibLin(0x45484B), insul = ibLin(0xD9D6CC), wireC = ibLin(0x4A4E52)
        let iceCol = ibLin(0xD6E4EC)
        /// Icicles hanging from a sagging span, where it is near enough to see them.
        func hang(_ a: IV3, _ b: IV3, sag: Float) {
            let n = Int(simd_length(b - a) / 0.16)
            for k in 0..<n {
                let t = (Float(k) + rng.next()) / Float(n)
                let p = a + (b - a) * t - IV3(0, sag * 4 * t * (1 - t), 0)
                guard p.x > -60 && p.x < 200 else { continue }
                let r = rng.next()
                let tier = r < 0.45 ? 0 : (r < 0.75 ? 1 : 2)
                iceAcc[tier].icicle(p - IV3(0, 0.03, 0), (0.05 + 0.1 * rng.next()) * (1 + 0.8 * Float(tier)), 0.009 + 0.004 * Float(tier), iceCol)
            }
        }
        /// A concrete pole with a cross-arm across `dir`; returns the three conductor points.
        func pole(_ x: Float, _ z: Float, lean: Float, across: Float) -> [IV3] {
            let base = IV3(x, height(x, z) - 0.3, z)
            let up = simd_normalize(IV3(lean * 0.3, 1, lean))
            let top = base + up * 11
            poles.tube(base, top, 0.14, 0.09, conc, segs: 6)
            let arm = base + up * 10.4
            let a = IV3(cos(across), 0, sin(across))
            poles.box(arm, IV3(0.85, 0.05, 0.06), steel, yaw: -across)
            var pts: [IV3] = []
            for k in [Float(-0.75), 0.75] {
                let p = arm + a * k
                poles.box(p + IV3(0, 0.1, 0), IV3(0.04, 0.08, 0.04), insul)
                pts.append(p + IV3(0, 0.19, 0))
            }
            pts.append(top + IV3(0, 0.06, 0))
            return pts
        }
        // the 10 kV line along the foot of the bank, and its branch across the paddies to the village
        var prev: [IV3] = []
        var i = 0
        var x: Float = -175
        while x <= 420 {
            let z: Float = 37 + 2 * sin(x / 90)
            let p = pole(x, z, lean: i == 5 ? -0.17 : 0.02 * sin(Float(i) * 1.7), across: .pi / 2)
            if !prev.isEmpty {
                for k in 0..<3 {
                    let sag: Float = i == 5 || i == 6 ? 2.4 : 1.4
                    wires.rope(prev[k], p[k], sag: sag, r: 0.032, wireC, segs: 12)
                    hang(prev[k], p[k], sag: sag)
                }
            }
            prev = p
            x += 45
            i += 1
        }
        prev = []
        for (k, (bx, bz)) in [(Float(50), Float(37.5)), (58, 72), (66, 106)].enumerated() {
            let p = pole(bx, bz, lean: k == 1 ? 0.12 : 0, across: 0)
            if !prev.isEmpty { for j in 0..<3 { wires.rope(prev[j], p[j], sag: 1.8, r: 0.03, wireC, segs: 12) } }
            prev = p
        }
        world.addChildNode(poles.node(glazed(0.85, side: 0.35)))
        world.addChildNode(wires.node(glazed(0.4, metal: 0.3, side: 0.9), shadow: false))

        // the 220 kV line from the far ridge across the valley and over the road; tower A comes down
        var fixed = IBMesh(), up = IBMesh(), down = IBMesh()
        let wc = ibLin(0x55595D)
        let dir = simd_normalize(SIMD2<Float>(towerC.x - towerA.x, towerC.y - towerA.y))
        let lineYaw = atan2(-dir.y, dir.x)          // the arms run across the line
        func site(_ t: SIMD2<Float>) -> IV3 { IV3(t.x, height(t.x, t.y) - 0.3, t.y) }
        let attA = tower(&up, at: site(towerA), yaw: lineYaw)
        let attB = tower(&fixed, at: site(towerB), yaw: lineYaw)
        let attC = tower(&fixed, at: site(towerC), yaw: lineYaw)
        // and on beyond C up the hill, and back over the far ridge from A
        let beyondC = site(towerC + dir * 260), beyondA = site(towerA - dir * 260)
        for j in 0..<7 {
            let sag: Float = j == 6 ? 7 : 9.5
            up.rope(attA[j], attB[j], sag: sag, r: 0.07, wc, segs: 20, sides: 4)
            up.rope(beyondA + IV3(0, 40 + Float(j % 3) * 5, 0), attA[j], sag: sag, r: 0.07, wc, segs: 14, sides: 4)
            fixed.rope(attB[j], attC[j], sag: sag, r: 0.07, wc, segs: 20, sides: 4)
            fixed.rope(attC[j], beyondC + IV3(0, 30 + Float(j % 3) * 5, 0), sag: sag, r: 0.07, wc, segs: 14, sides: 4)
        }
        // the collapsed tower: buckled above the legs, the head folded down the slope
        let fallenPts = tower(&down, at: site(towerA), yaw: lineYaw, fold: { p in
            if p.y <= 7 { return IV3(p.x, p.y, p.z + 0.06 * p.y) }
            let a1: Float = 0.95, a2: Float = 2.25
            let pivot = IV3(0, 7, 0.42)
            func rot(_ q: IV3, _ a: Float) -> IV3 { IV3(q.x, q.y * cos(a) - q.z * sin(a), q.y * sin(a) + q.z * cos(a)) }
            let wob = IV3(0.25 * sin(p.y * 1.3), 0, 0.2 * cos(p.y * 0.9))
            if p.y <= 21 { return pivot + rot(IV3(p.x, p.y - 7, p.z), a1) + wob }
            let hinge = pivot + rot(IV3(0, 14, 0), a1)
            return hinge + rot(IV3(p.x, p.y - 21, p.z), a2) + wob
        })
        // its conductors: from tower B they droop down into the paddies below the road, trailing on the ice
        for j in 0..<7 {
            let t = Float(j) / 6
            let gx = towerB.x - dir.x * (26 + 5 * t) + Float(j % 2) * 2, gz = towerB.y - dir.y * (26 + 5 * t)
            let g = IV3(gx, height(gx, gz) + 0.08, gz)
            down.rope(attB[j], g, sag: 3, r: 0.07, wc, segs: 16, sides: 4)
            let ex = gx - dir.x * 30 + Float(j) * 1.2, ez = gz - dir.y * 30
            down.rope(g, IV3(ex, height(ex, ez) + 0.08, ez), sag: 0, r: 0.07, wc, segs: 8, sides: 4)
            let p = fallenPts[min(j, 5)]
            let q = IV3(p.x + 4 + Float(j), 0, p.z + 6)
            down.rope(p, IV3(q.x, height(q.x, q.z) + 0.1, q.z), sag: 1, r: 0.07, wc, segs: 8, sides: 4)
            down.rope(beyondA + IV3(0, 40 + Float(j % 3) * 5, 0), IV3(p.x - 3, height(p.x - 3, p.z - 8) + 0.1, p.z - 8), sag: 12, r: 0.07, wc, segs: 14, sides: 4)
        }
        let towerMat = glazed(0.5, metal: 0.55, side: 0.6)
        world.addChildNode(fixed.node(towerMat))
        let u = up.node(towerMat), d = down.node(towerMat)
        d.isHidden = true
        world.addChildNode(u)
        world.addChildNode(d)
        towerUp = u
        towerDown = d
        // sticks with red rags round the fallen wire where it lies across the paddies
        var mk = IBMesh()
        for k in 0..<7 {
            let t = Float(k) / 6
            let px = towerB.x - dir.x * (32 + 26 * t) + rng.r(-2.5, 2.5), pz = towerB.y - dir.y * (32 + 26 * t) + rng.r(-2.5, 2.5)
            let b = IV3(px, height(px, pz), pz)
            mk.tube(b - IV3(0, 0.2, 0), b + IV3(0.1, 1.3, 0.05), 0.02, 0.015, ibLin(0x5A4632), segs: 3)
            mk.box(b + IV3(0.12, 1.15, 0.05), IV3(0.12, 0.09, 0.01), ibLin(0xC8221A), yaw: rng.r(0, 3))
        }
        let marks = mk.node(glazed(0.8, side: 0.1))
        marks.isHidden = true
        world.addChildNode(marks)
        wireMarks = marks
    }

    /// A 220 kV double-circuit lattice tower (~42 m) at `b`, its arms across the line; `fold` bends it
    /// for the collapsed one. Returns the conductors' six attachment points and the earth wire's.
    @discardableResult
    private func tower(_ m: inout IBMesh, at b: IV3, yaw: Float, fold: ((IV3) -> IV3)? = nil) -> [IV3] {
        func f(_ p: IV3) -> IV3 { b + ibRot(fold?(p) ?? p, yaw: yaw) }
        let steel = ibLin(0x8C9196), leg: Float = 0.12, brace: Float = 0.05
        func half(_ y: Float) -> Float { y < 26 ? 3.5 - 2.7 * (y / 26) : 0.8 }
        let levels: [Float] = [-2, 0, 4, 8, 12, 16, 20, 23, 26, 29.5, 33, 36.5, 40, 42]
        for k in 0..<(levels.count - 1) {
            let y0 = levels[k], y1 = levels[k + 1]
            let h0 = half(y0), h1 = half(y1)
            let c0 = [IV3(-h0, y0, -h0), IV3(h0, y0, -h0), IV3(h0, y0, h0), IV3(-h0, y0, h0)]
            let c1 = [IV3(-h1, y1, -h1), IV3(h1, y1, -h1), IV3(h1, y1, h1), IV3(-h1, y1, h1)]
            for i in 0..<4 {
                let j = (i + 1) % 4
                m.tube(f(c0[i]), f(c1[i]), leg, leg * 0.92, steel, segs: 4)
                m.tube(f(c0[i]), f(c1[j]), brace, brace, steel, segs: 3)
                m.tube(f(c0[j]), f(c1[i]), brace, brace, steel, segs: 3)
                m.tube(f(c1[i]), f(c1[j]), brace, brace, steel, segs: 3)
            }
        }
        var pts: [IV3] = []
        for (y, reach) in [(Float(27.5), Float(5.6)), (33, 6.6), (38.5, 5.2)] {
            for s in [Float(-1), 1] {
                let tip = IV3(0, y + 0.3, s * (0.8 + reach))
                m.tube(f(IV3(-0.8, y, s * 0.8)), f(tip), brace * 1.6, brace, steel, segs: 3)
                m.tube(f(IV3(0.8, y, s * 0.8)), f(tip), brace * 1.6, brace, steel, segs: 3)
                m.tube(f(IV3(0, y + 1.6, s * 0.8)), f(tip), brace * 1.3, brace, steel, segs: 3)
                let low = tip - IV3(0, 2.6, 0)
                m.tube(f(tip), f(low), 0.1, 0.1, ibLin(0x707C80), segs: 5)
                pts.append(f(low))
            }
        }
        pts.append(f(IV3(0, 42.2, 0)))
        return pts
    }

    // MARK: Trees

    /// One tree into the merged crown and wood meshes. `bend` 0…1: how far the ice has bowed it,
    /// toward the angle `toward` (x → z); `lod` 0 near … 2 far off.
    private func tree(_ crown: inout IBMesh, _ wood: inout IBMesh, kind: Int, at b: IV3, s: Float, bend: Float,
                      toward: Float, seed: Float, lod: Int) {
        let dir = IV3(cos(toward), 0, sin(toward))
        let tint: Float = 0.86 + 0.28 * noise.value(seed * 1.7 + 3, 1.1)
        let bark = ibLin(0x4B4038)
        switch kind {
        case 0:
            // Chinese fir (杉木): a straight stem and overlapping tiers making a narrow cone; under the ice
            // the branches hang (steeper, narrower tiers) and the leader bows over
            let H: Float = 11 * s
            func stem(_ t: Float) -> IV3 {
                let t3 = t * t * t
                return b + IV3(0, H * t - bend * 0.1 * H * t3 * t, 0) + dir * (bend * 0.2 * H * t3)
            }
            wood.tube(b - IV3(0, 0.3, 0), stem(0.5), 0.2 * s, 0.12 * s, bark, segs: lod == 0 ? 6 : 4)
            let tiers = lod == 0 ? 5 : (lod == 1 ? 3 : 2)
            let col = ibLin(0x2A4330) * tint
            let t0: Float = 0.14, span: Float = 0.8
            let step = span / Float(tiers)
            for i in 0..<tiers {
                let t = t0 + step * Float(i)
                let r = (2.3 * pow(1 - t, 0.85) + 0.25) * s * (1 - 0.12 * bend)
                let h = (step * 2.6 + 0.05) * H * (1 + 0.25 * bend)
                let c = stem(t)
                let top = i == tiers - 1 ? stem(1) : c + IV3(0, h, 0) + dir * (bend * 0.25 * h)
                crown.cone(c, r, apex: top, col * (0.9 + 0.12 * Float(i % 2)),
                           segs: lod == 0 ? 7 : (lod == 1 ? 6 : 5), rot: seed + Float(i), cap: lod == 0)
            }
        case 1:
            // Masson pine (马尾松): a leaning stem, a flat-topped crown in pads
            let H: Float = 10 * s
            let top = b + IV3(0, H * (1 - 0.15 * bend), 0) + dir * ((0.12 + 0.25 * bend) * H)
            wood.tube(b - IV3(0, 0.3, 0), top, 0.18 * s, 0.07 * s, bark, segs: lod == 0 ? 5 : 4)
            let col = ibLin(0x30482F) * tint
            for k in 0..<(lod == 2 ? 1 : 3) {
                let t = 0.62 + 0.14 * Float(k)
                let c = b + (top - b) * t + IV3(sin(seed + Float(k) * 2.1), 0, cos(seed + Float(k) * 1.7)) * (0.6 * s)
                crown.blob(c, IV3(2.0, 1.6 - 0.3 * bend, 2.0) * (s * (1 - 0.18 * Float(k))), col * (0.9 + 0.08 * Float(k)), noise,
                           seed: seed + Float(k), jitter: 0.32, rings: lod == 0 ? 4 : 3, segs: lod == 0 ? 7 : 5)
            }
        case 2:
            // camphor / evergreen oak (樟树): a round crown, flattened and drooping under the ice
            let top = b + IV3(0, 8 * s * 0.55, 0) + dir * (0.4 * bend * s)
            wood.tube(b - IV3(0, 0.3, 0), top, 0.32 * s, 0.2 * s, bark, segs: lod == 0 ? 6 : 4)
            let col = ibLin(0x3B5733) * tint
            let n = lod == 0 ? 4 : (lod == 1 ? 2 : 1)
            for k in 0..<n {
                let a = seed + Float(k) * 1.9
                let off = lod == 2 ? IV3(0, 0, 0) : IV3(cos(a), 0, sin(a)) * (1.7 * s)
                let c = top + off + IV3(0, (1.6 - 0.9 * bend) * s, 0) + dir * (bend * 0.9 * s)
                crown.blob(c, IV3(2.8, 2.3 * (1 - 0.35 * bend), 2.8) * s, col * (0.88 + 0.07 * Float(k)), noise,
                           seed: seed + Float(k) * 3, jitter: 0.28, rings: lod == 0 ? 5 : 3, segs: lod == 0 ? 8 : 5)
            }
        case 3:
            // bamboo clump (竹丛): culms arching over, the leafy ends bowed toward the ground
            let n = lod == 0 ? 6 : (lod == 1 ? 4 : 2)
            let culm = ibLin(0x7C8C4C), leaf = ibLin(0x55703A) * tint
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi + seed
                let spread = IV3(cos(a), 0, sin(a))
                let o = simd_normalize(spread * 0.45 + dir * 0.8)
                let L = (8 + 2.5 * noise.value(seed + Float(i), 1.3)) * s
                let p0 = b + spread * (0.45 * s) - IV3(0, 0.2, 0)
                let p1 = p0 + IV3(0, L * 0.6, 0) + o * (L * 0.08)
                let p2 = p0 + o * (L * (0.3 + 0.42 * bend)) + IV3(0, L * (0.95 - 0.78 * bend), 0)
                func bez(_ t: Float) -> IV3 { p0 * ((1 - t) * (1 - t)) + p1 * (2 * t * (1 - t)) + p2 * (t * t) }
                let segs = lod == 0 ? 4 : (lod == 1 ? 3 : 2)
                var prev = p0
                for k in 1...segs {
                    let t = Float(k) / Float(segs)
                    let p = bez(t)
                    wood.tube(prev, p, 0.05 * s * (1.05 - 0.6 * (t - 1 / Float(segs))), 0.05 * s * (1.05 - 0.6 * t), culm, segs: lod == 0 ? 4 : 3)
                    prev = p
                }
                // the foliage: a plume thinning toward the bowed tip
                let plumes = lod == 0 ? 3 : 1
                for k in 0..<plumes {
                    let t: Float = plumes == 1 ? 0.78 : 0.5 + 0.48 * Float(k) / Float(plumes - 1)
                    let rr = (0.95 - 0.5 * Float(k) / Float(max(1, plumes - 1))) * s
                    crown.blob(bez(t) - IV3(0, 0.3 * rr, 0), IV3(rr, rr * 1.1, rr) * (plumes == 1 ? 1.25 : 1), leaf * (0.86 + 0.08 * Float(k % 2)), noise,
                               seed: seed + Float(i * 5 + k), jitter: 0.32, rings: 3, segs: 5)
                }
            }
        default:
            // a shrub or a young tea-oil tree (油茶)
            let c = b + IV3(0, (1.2 - 0.4 * bend) * s, 0) + dir * (0.3 * bend * s)
            wood.tube(b - IV3(0, 0.2, 0), c, 0.08 * s, 0.05 * s, bark, segs: 4)
            crown.blob(c + IV3(0, 0.4 * s, 0), IV3(1.3, 1.0 - 0.3 * bend, 1.3) * s, ibLin(0x3E5534) * tint, noise,
                       seed: seed, jitter: 0.3, rings: lod == 0 ? 4 : 3, segs: lod == 0 ? 6 : 5)
        }
    }

    private func buildTrees() {
        var cL = IBMesh(), wL = IBMesh(), cH = IBMesh(), wH = IBMesh(), cF = IBMesh(), wF = IBMesh()
        var rng = IBRng(77)
        let eye2 = SIMD2<Float>(eye.x, eye.z)
        func plant(_ x: Float, _ z: Float, _ kind: Int, _ s: Float, toward: Float) {
            let p = IV3(x, height(x, z), z)
            let d = simd_length(SIMD2<Float>(x, z) - eye2)
            let lod = d < 150 ? 0 : (d < 380 ? 1 : 2)
            let seed = x * 0.731 + z * 0.377
            if d < 240 {
                tree(&cL, &wL, kind: kind, at: p, s: s, bend: 0.2, toward: toward, seed: seed, lod: lod)
                tree(&cH, &wH, kind: kind, at: p, s: s, bend: 0.85, toward: toward, seed: seed, lod: lod)
            } else {
                tree(&cF, &wF, kind: kind, at: p, s: s, bend: 0.55, toward: toward, seed: seed, lod: lod)
            }
        }
        /// Downhill, a little at random: the way an iced tree bows.
        func downhill(_ x: Float, _ z: Float) -> Float {
            let gx = natural(x + 3, z) - natural(x - 3, z), gz = natural(x, z + 3) - natural(x, z - 3)
            return atan2(-gz, -gx) + rng.r(-0.7, 0.7)
        }
        // the woods on the hills, in 40 m tiles, thinning with distance
        var tz: Float = -760
        while tz < 680 {
            var tx: Float = -480
            while tx < 1320 {
                let d = simd_length(SIMD2<Float>(tx + 20, tz + 20) - eye2)
                if d > 680 { tx += 40; continue }                                         // lost in the mist
                let spacing: Float = d < 200 ? 6.5 : (d < 450 ? 9 : 13)
                let count = Int((40 / spacing) * (40 / spacing))
                for _ in 0..<count {
                    let x = tx + rng.r(0, 40), z = tz + rng.r(0, 40)
                    if z > -30 && z < 36 { continue }                                  // the road, its cut and bank
                    if paddy(x, z) > 0.15 { continue }
                    if x > 15 && x < 190 && z > 36 && z < 140 { continue }             // the village plants its own
                    if z > 0 && x > pad.x - 30 && x < pad.y + 30 && z < pad.w + 20 { continue }
                    let woods = noise.fbm(x / 45 + 7, z / 45, octaves: 3)
                    if woods < 0.4 && rng.next() > 0.12 { continue }
                    let k2 = noise.value(x / 30 + 70, z / 30)
                    let k3 = rng.next()
                    let kind = k2 > 0.76 ? 3 : (k3 < 0.6 ? 0 : (k3 < 0.74 ? 1 : (k3 < 0.92 ? 2 : 4)))
                    plant(x, z, kind, (d < 200 ? 1 : (d < 450 ? 1.15 : 1.4)) * rng.r(0.75, 1.15), toward: downhill(x, z))
                }
                tx += 40
            }
            tz += 40
        }
        // bamboo and firs along the top of the cut, bowed over its edge toward the road
        var xr: Float = -110
        while xr < 330 {
            let z = -(13 + 1.6 + 12.5 / 1.25) - rng.r(0.5, 6)
            let kind = rng.next() < 0.6 ? 3 : (rng.next() < 0.5 ? 0 : 2)
            plant(xr, z, kind, rng.r(0.8, 1.1), toward: .pi / 2 + rng.r(-0.5, 0.5))
            xr += rng.r(6, 14)
        }
        // a few at the foot of the bank on the valley side
        var xb: Float = -80
        while xb < 260 {
            if rng.next() < 0.55 {
                let z = 13 + 19.5 + rng.r(2, 9)
                plant(xb, z, rng.next() < 0.5 ? 3 : 4, rng.r(0.75, 1.0), toward: rng.r(0, 6.28))
            }
            xb += rng.r(14, 24)
        }
        let crownMat = glazed(0.85, side: 0.35), woodMat = glazed(0.9, side: 0.4)
        treesLight.addChildNode(cL.node(crownMat))
        treesLight.addChildNode(wL.node(woodMat))
        treesHeavy.addChildNode(cH.node(crownMat))
        treesHeavy.addChildNode(wH.node(woodMat))
        world.addChildNode(treesLight)
        world.addChildNode(treesHeavy)
        world.addChildNode(cF.node(crownMat, shadow: false))
        world.addChildNode(wF.node(woodMat, shadow: false))

        // when the ice is at its worst: trees snapped along the cut's edge, branches down on the road
        var fc = IBMesh(), fw = IBMesh()
        let bark = ibLin(0x4B4038), needles = ibLin(0x2C4532)
        for k in 0..<9 {
            let x = -50 + Float(k) * 30 + rng.r(-6, 6)
            let z = -(13 + 1.6 + 12.5 / 1.25) - rng.r(1, 5)
            let y = height(x, z)
            let stub = IV3(x, y + rng.r(2, 3.5), z)
            fw.tube(IV3(x, y - 0.2, z), stub, 0.2, 0.17, bark, segs: 5)
            let a = rng.r(0.6, 2.4)
            let tipP = IV3(x + cos(a) * 7, 0, z + sin(a) * 7)
            let tip = IV3(tipP.x, height(tipP.x, tipP.z) + 0.3, tipP.z)
            fw.tube(stub - IV3(0, 0.3, 0), tip, 0.17, 0.05, bark, segs: 5)
            for j in 0..<3 {
                let c = stub + (tip - stub) * (0.45 + 0.2 * Float(j))
                fc.blob(c, IV3(1.6, 0.8, 1.6), needles, noise, seed: Float(k * 5 + j), jitter: 0.35, rings: 3, segs: 6)
            }
        }
        // a broken bamboo lying across the southbound hard shoulder, a branch on ours
        for (p, a) in [(IV3(-38, 0.1, -11.4), Float(0.35)), (IV3(-31, 0.1, -10.2), Float(-0.5))] {
            let q = IV3(p.x, ry(p.x) + p.y, p.z)
            let e = q + IV3(cos(a) * 4.2, 0.05, sin(a) * 1.2)
            fw.tube(q, e, 0.06, 0.03, ibLin(0x7C8C4C), segs: 4)
            fc.blob((q + e) * 0.5 + IV3(0.8, 0.22, 0), IV3(1.4, 0.32, 0.55), ibLin(0x55703A), noise, seed: p.x, rings: 3, segs: 6)
        }
        let fall = SCNNode()
        fall.addChildNode(fc.node(crownMat))
        fall.addChildNode(fw.node(woodMat))
        fall.isHidden = true
        world.addChildNode(fall)
        fallen = fall
    }

    // MARK: 坳上村 and the service area

    private func buildVillage() {
        var walls = IBMesh(), roofs = IBMesh(), wins = IBMesh(), lit = IBMesh(), cr = IBMesh(), wd = IBMesh()
        // on the far side of the valley floor and up the slope behind (x, z, yaw toward the road, kind)
        let houses: [(Float, Float, Float, Int)] = [
            (36, 52, 0.05, 2), (52, 58, -0.08, 1), (74, 55, 0.1, 0), (61, 72, 0.0, 3),
            (95, 66, 0.12, 0), (118, 60, -0.05, 1), (138, 72, 0.15, 2), (84, 86, 0.05, 1), (110, 88, -0.1, 0),
            (132, 98, 0.12, 1), (154, 90, 0.0, 0), (70, 104, 0.2, 2), (98, 112, 0.05, 1), (122, 120, -0.1, 0),
            (160, 116, 0.1, 2), (44, 80, 0.0, 3)]
        for (i, h) in houses.enumerated() {
            house(&walls, &roofs, &wins, &lit, x: h.0, z: h.1, yaw: h.2, kind: h.3, seed: UInt64(40 + i), lamp: [1, 4, 9, 13].contains(i))
        }
        // bamboo behind the houses, a camphor in front of every other one
        var rng = IBRng(91)
        for (i, h) in houses.enumerated() {
            let bx = h.0 + rng.r(-6, 6), bz = h.1 + 9 + rng.r(0, 5)
            for k in 0..<(i % 3 == 0 ? 3 : 2) {
                let x = bx + Float(k) * 3.5 + rng.r(-1, 1), z = bz + rng.r(-2, 2)
                tree(&cr, &wd, kind: 3, at: IV3(x, height(x, z), z), s: rng.r(0.8, 1.05), bend: 0.75,
                     toward: -.pi / 2 + rng.r(-1, 1), seed: x + z, lod: 1)
            }
            if i % 2 == 0 {
                let x = h.0 + rng.r(-9, 9), z = h.1 - 8 - rng.r(0, 3)
                tree(&cr, &wd, kind: 2, at: IV3(x, height(x, z), z), s: rng.r(0.8, 1.1), bend: 0.6, toward: rng.r(0, 6.28), seed: x, lod: 1)
            }
        }
        world.addChildNode(walls.node(glazed(0.9, side: 0.12)))
        world.addChildNode(roofs.node(glazed(0.7, side: 0.1)))
        world.addChildNode(wins.node(glazed(0.15, metal: 0.3, side: 0.3)))
        let cm = SK.mat(SK.rgb(0x2A2620), roughness: 0.3, emission: SK.rgb(0xFFB25A))
        cm.emission.intensity = 0
        candleMat = cm
        world.addChildNode(lit.node(cm, shadow: false))
        world.addChildNode(cr.node(glazed(0.85, side: 0.35)))
        world.addChildNode(wd.node(glazed(0.9, side: 0.4)))
        // wood smoke from a few kitchen stoves (no power: everyone cooks on firewood)
        for i in [2, 6, 10] {
            let h = houses[i]
            let n = SCNNode()
            n.position = SCNVector3(CGFloat(h.0 - 2), CGFloat(height(h.0, h.1)) + (h.3 == 0 ? 11.5 : 8), CGFloat(h.1 + 1))
            world.addChildNode(n)
            chimneys.append((SK.smoke(scale: 0.9, color: NSColor(white: 0.8, alpha: 0.16)), n))
        }
    }

    /// A village house on its levelled plot (the plinth runs down to the lowest ground under it), its
    /// front (door, windows) facing the road (−z). kind 0: three storeys and a flat roof, 1: two storeys
    /// under a hipped roof, 2: an old single-storey house, 3: a shed.
    private func house(_ walls: inout IBMesh, _ roofs: inout IBMesh, _ wins: inout IBMesh, _ lit: inout IBMesh,
                       x: Float, z: Float, yaw: Float, kind: Int, seed: UInt64, lamp: Bool) {
        var r = IBRng(seed)
        let dims: [(Float, Float, Float)] = [(5.2, 5.4, 9.6), (4.6, 4.6, 6.4), (5.6, 3.5, 3.3), (2.6, 2.0, 2.5)]
        let (L, W, H) = dims[min(kind, 3)]
        let turn = yaw + .pi                   // local +z (the front) toward the road
        var lo: Float = 1e9, hi: Float = -1e9
        for (cx, cz) in [(-L, -W), (L, -W), (-L, W), (L, W), (0, 0)] {
            let p = IV3(x, 0, z) + ibRot(IV3(cx, 0, cz), yaw: turn)
            let y = height(p.x, p.z)
            lo = min(lo, y)
            hi = max(hi, y)
        }
        let base = hi + 0.1
        func P(_ dx: Float, _ dy: Float, _ dz: Float) -> IV3 { IV3(x, base, z) + ibRot(IV3(dx, dy, dz), yaw: turn) }
        let tiles = ibLin(0xE0DED6), render = ibLin(0xB8B3A7), brick = ibLin(0x98583F), oldBrick = ibLin(0x8B877F)
        let glassC = ibLin(0x22292E), frame = ibLin(0xC9CBC8), door = ibLin(0x6B3A2A)
        walls.box(P(0, (lo - base - 0.3) / 2, 0), IV3(L + 0.2, (base - lo + 0.3) / 2, W + 0.2), ibLin(0x86827A), yaw: turn)
        func window(_ u: Float, _ v: Float, _ w: Float, _ h: Float, lamp: Bool = false) {
            walls.box(P(u, v, W + 0.07), IV3(w / 2 + 0.06, h / 2 + 0.06, 0.03), frame, yaw: turn)
            if lamp { lit.box(P(u, v, W + 0.12), IV3(w / 2, h / 2, 0.02), IV3(1, 1, 1), yaw: turn) }
            else { wins.box(P(u, v, W + 0.12), IV3(w / 2, h / 2, 0.02), glassC, yaw: turn) }
        }
        switch kind {
        case 0:
            let side = r.next() < 0.5 ? render : brick
            walls.box(P(0, H / 2, 0), IV3(L, H / 2, W), side, yaw: turn)
            walls.box(P(0, H / 2, W + 0.01), IV3(L + 0.02, H / 2, 0.03), tiles, yaw: turn)
            walls.box(P(0, H + 0.45, W - 0.1), IV3(L, 0.45, 0.1), tiles, yaw: turn)
            walls.box(P(0, H + 0.45, -W + 0.1), IV3(L, 0.45, 0.1), side, yaw: turn)
            walls.box(P(L - 0.1, H + 0.45, 0), IV3(0.1, 0.45, W), side, yaw: turn)
            walls.box(P(-L + 0.1, H + 0.45, 0), IV3(0.1, 0.45, W), side, yaw: turn)
            walls.box(P(-L + 1.6, H + 1.4, -W + 1.8), IV3(1.5, 1.4, 1.7), side, yaw: turn)
            roofs.box(P(0, H + 0.02, 0), IV3(L - 0.2, 0.04, W - 0.2), ibLin(0x8E8C86), yaw: turn)
            for f in 0..<3 {
                let v = 1.7 + Float(f) * 3.2
                for u in [Float(-L * 0.6), 0, L * 0.6] where !(f == 0 && u == 0) {
                    window(u, v, 1.3, 1.4, lamp: lamp && f == 1 && u > 0)
                }
                if f > 0 {
                    walls.box(P(0, v - 1.0, W + 0.65), IV3(1.6, 0.08, 0.65), tiles, yaw: turn)
                    walls.box(P(0, v - 0.55, W + 1.27), IV3(1.6, 0.4, 0.03), frame, yaw: turn)
                }
            }
            walls.box(P(0, 1.2, W + 0.09), IV3(0.95, 1.2, 0.03), door, yaw: turn)
        case 1:
            walls.box(P(0, H / 2, 0), IV3(L, H / 2, W), brick, yaw: turn)
            walls.box(P(0, H / 2, W + 0.01), IV3(L + 0.02, H / 2, 0.03), tiles, yaw: turn)
            roofs.hipRoof(P(0, H, 0), halfL: L, halfW: W, rise: 2.2, over: 0.45, yaw: turn, ibLin(0x5B6067) * r.r(0.85, 1.1))
            for f in 0..<2 {
                let v = 1.6 + Float(f) * 3.1
                for u in [Float(-L * 0.55), L * 0.55] { window(u, v, 1.2, 1.3, lamp: lamp && f == 0 && u < 0) }
            }
            walls.box(P(0, 1.15, W + 0.09), IV3(0.8, 1.15, 0.03), door, yaw: turn)
        case 2:
            let wallC = r.next() < 0.5 ? oldBrick : ibLin(0xA3845F)
            walls.box(P(0, H / 2, 0), IV3(L, H / 2, W), wallC, yaw: turn)
            roofs.gable(P(0, H, 0), halfL: L, halfW: W, rise: 1.9, over: 0.5, yaw: turn, ibLin(0x3C3F44), gableCol: wallC)
            window(-L * 0.55, 1.6, 0.8, 0.8, lamp: lamp)
            window(L * 0.55, 1.6, 0.8, 0.8)
            walls.box(P(0, 1.05, W + 0.09), IV3(0.6, 1.05, 0.03), door, yaw: turn)
        default:
            walls.box(P(0, H / 2, 0), IV3(L, H / 2, W), oldBrick, yaw: turn)
            roofs.gable(P(0, H, 0), halfL: L, halfW: W, rise: 0.9, over: 0.3, yaw: turn, ibLin(0x9A9A94), gableCol: oldBrick)
        }
    }

    private func buildServiceArea() {
        var walls = IBMesh(), roofs = IBMesh(), wins = IBMesh(), lit = IBMesh()
        // the main building at the back of the forecourt: shop, restaurant, toilets
        let c = IV3(430, ry(430), 58)
        walls.box(c + IV3(0, 4.2, 0), IV3(24, 4.2, 7), ibLin(0xDCDDD8))
        wins.box(c + IV3(0, 2.0, -7.03), IV3(21, 1.2, 0.03), ibLin(0x23323E))
        wins.box(c + IV3(0, 5.9, -7.03), IV3(21, 0.85, 0.03), ibLin(0x23323E))
        lit.box(c + IV3(-8, 2.0, -7.2), IV3(3.5, 1.1, 0.04), IV3(1, 1, 1))
        walls.box(c + IV3(0, 8.3, 0), IV3(24.4, 0.3, 7.4), ibLin(0x2F5DA0))
        roofs.box(c + IV3(0, 8.65, 0), IV3(24.2, 0.06, 7.2), ibLin(0x8E9294))
        walls.box(c + IV3(-12, 10.2, -1), IV3(6, 1.5, 0.15), ibLin(0x2F5DA0))
        // the fuel station's canopy and its pumps
        let f = IV3(384, ry(384), 30)
        roofs.box(f + IV3(0, 5.8, 0), IV3(14, 0.45, 8), ibLin(0xE6E6E2))
        walls.box(f + IV3(0, 5.6, 0), IV3(14.05, 0.2, 8.05), ibLin(0xB0322A))
        for px in [Float(-9), 0, 9] {
            walls.box(f + IV3(px, 2.7, 0), IV3(0.3, 2.7, 0.3), ibLin(0xD9D9D5))
            walls.box(f + IV3(px, 0.8, -2.2), IV3(0.4, 0.8, 0.25), ibLin(0xC9C9C4))
        }
        world.addChildNode(walls.node(glazed(0.8, side: 0.12)))
        world.addChildNode(roofs.node(glazed(0.6, side: 0.1)))
        world.addChildNode(wins.node(glazed(0.12, metal: 0.4, side: 0.3)))
        world.addChildNode(lit.node(candleMat ?? glow(SK.rgb(0xFFB25A), 0), shadow: false))
        // lorries that made it in and stopped
        var fl = IBFleet(detail: false, seed: 61)
        var rng = IBRng(62)
        for i in 0..<5 {
            let x: Float = 410 + Float(i) * 11
            let kind: IBKind = i % 3 == 0 ? .semi : (i % 3 == 1 ? .tarpTruck : .boxTruck)
            fl.truck(IBFrame(o: IV3(x, ry(x), 34), yaw: -.pi / 2 + rng.r(-0.05, 0.05), roll: 0), kind: kind,
                     cabCol: ibLin(rng.pick(IceboundScene.cabColors)), load: ibLin(rng.pick(IceboundScene.loadColors)), hz: -1, inside: false)
        }
        addFleet(fl, parent: world, north: false)
    }

    // MARK: Signs

    private func buildSigns(english: Bool) {
        let green = CGColor(red: 0.0, green: 0.42, blue: 0.25, alpha: 1), white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let zh = "PingFangSC-Semibold", lat = "Helvetica-Bold"
        // the guide sign: distances to the next towns
        let guide = ibDraw(1024, 500) { ctx in
            ctx.setFillColor(green); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 500))
            ctx.setStrokeColor(white); ctx.setLineWidth(10); ctx.stroke(CGRect(x: 18, y: 18, width: 988, height: 464))
            let rows: [(String, String, String)] = [("郴州", "Chenzhou", "15 km"), ("耒阳", "Leiyang", "78 km"), ("衡阳", "Hengyang", "157 km")]
            for (i, r) in rows.enumerated() {
                let y = CGFloat(355 - i * 140)
                if english {
                    ibText(ctx, r.1, font: lat, size: 92, x: 70, y: y, color: white)
                } else {
                    ibText(ctx, r.0, font: zh, size: 96, x: 70, y: y + 4, color: white)
                    ibText(ctx, r.1, font: lat, size: 46, x: 300, y: y + 10, color: white)
                }
                ibText(ctx, r.2, font: lat, size: 84, x: 960, y: y, color: white, align: 2)
            }
        }
        sign(guide, w: 5.4, h: 2.64, at: IV3(62, 4.0, 14.6), posts: [13.3, 15.9])
        // the service area on the crest
        let sa = ibDraw(800, 440) { ctx in
            ctx.setFillColor(green); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 440))
            ctx.setStrokeColor(white); ctx.setLineWidth(9); ctx.stroke(CGRect(x: 16, y: 16, width: 768, height: 408))
            if english {
                ibText(ctx, "Chenzhou", font: lat, size: 70, x: 400, y: 330, color: white, align: 1)
                ibText(ctx, "Service Area", font: lat, size: 70, x: 400, y: 240, color: white, align: 1)
            } else {
                ibText(ctx, "郴州服务区", font: zh, size: 100, x: 400, y: 300, color: white, align: 1)
                ibText(ctx, "Chenzhou Service Area", font: lat, size: 40, x: 400, y: 240, color: white, align: 1)
            }
            ctx.setFillColor(white)
            ctx.fill(CGRect(x: 90, y: 60, width: 120, height: 120))
            ibText(ctx, "P", font: lat, size: 110, x: 150, y: 80, color: green, align: 1)
            ctx.fill(CGRect(x: 250, y: 60, width: 120, height: 120))
            ctx.setFillColor(green)
            ctx.fill(CGRect(x: 280, y: 78, width: 44, height: 80))
            ctx.fill(CGRect(x: 330, y: 120, width: 10, height: 46))
            ibText(ctx, "300 m", font: lat, size: 84, x: 720, y: 85, color: white, align: 2)
        }
        sign(sa, w: 4.2, h: 2.3, at: IV3(150, 3.8, 14.2), posts: [13.2, 15.2])
        // icy road warning (a yellow triangle and its plate)
        let warn = ibDraw(400, 520) { ctx in
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: 200, y: 505)); tri.addLine(to: CGPoint(x: 392, y: 175)); tri.addLine(to: CGPoint(x: 8, y: 175)); tri.closeSubpath()
            ctx.setFillColor(CGColor(red: 0.95, green: 0.78, blue: 0.1, alpha: 1)); ctx.addPath(tri); ctx.fillPath()
            ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 1)); ctx.setLineWidth(18); ctx.addPath(tri); ctx.strokePath()
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.fill(CGRect(x: 135, y: 300, width: 130, height: 50))
            ctx.fill(CGRect(x: 160, y: 345, width: 80, height: 40))
            for k in 0..<2 {
                let p = CGMutablePath()
                let y0 = CGFloat(255 - k * 30)
                p.move(to: CGPoint(x: 120, y: y0))
                p.addCurve(to: CGPoint(x: 280, y: y0), control1: CGPoint(x: 170, y: y0 + 28), control2: CGPoint(x: 230, y: y0 - 28))
                ctx.setLineWidth(10); ctx.addPath(p); ctx.strokePath()
            }
            ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 40, y: 0, width: 320, height: 150))
            ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 1)); ctx.setLineWidth(8); ctx.stroke(CGRect(x: 44, y: 4, width: 312, height: 142))
            if english { ibText(ctx, "ICY ROAD", font: lat, size: 62, x: 200, y: 52, color: CGColor(gray: 0.05, alpha: 1), align: 1) }
            else { ibText(ctx, "路面结冰", font: zh, size: 76, x: 200, y: 46, color: CGColor(gray: 0.05, alpha: 1), align: 1) }
        }
        sign(warn, w: 1.0, h: 1.3, at: IV3(34, 2.3, 13.5), posts: [13.5], postW: 0.05)

        // the variable-message board on its gantry over the northbound lanes
        vmsImages = (IceboundScene.led(english ? ["ICY ROAD AHEAD", "ROAD CLOSED"] : ["前方路面结冰", "道路封闭 禁止通行"], english: english),
                     IceboundScene.led(english ? ["ROAD REOPENED", "DRIVE SLOWLY"] : ["道路恢复通行", "减速慢行 注意安全"], english: english))
        let gx: Float = 112, gy = ry(gx)
        var g = IBMesh()
        let grey = ibLin(0x8A9095)
        for z in [Float(0), 13.4] {
            let y0 = z > 13 ? height(gx, z) : gy + 0.2
            g.tube(IV3(gx, y0 - 0.3, z), IV3(gx, gy + 7.2, z), 0.2, 0.18, grey, segs: 8)
        }
        for y in [Float(6.6), 7.15] {
            g.box(IV3(gx, gy + y, 6.7), IV3(0.09, 0.09, 6.9), grey)
            g.box(IV3(gx + 0.6, gy + y, 6.7), IV3(0.09, 0.09, 6.9), grey)
        }
        var zt: Float = 0.3
        while zt < 13.2 {
            g.tube(IV3(gx, gy + 6.6, zt), IV3(gx + 0.6, gy + 7.15, zt + 0.7), 0.04, 0.04, grey, segs: 3)
            zt += 0.7
        }
        g.box(IV3(gx + 0.12, gy + 5.75, 6.4), IV3(0.12, 0.82, 3.35), ibLin(0x2C2F33))
        world.addChildNode(g.node(glazed(0.45, metal: 0.5, side: 0.5)))
        var gi = IBRng(7)
        var u: Float = 3.1
        while u < 9.7 {
            iceAcc[gi.next() < 0.5 ? 1 : 2].icicle(IV3(gx - 0.01, gy + 4.93, u), gi.r(0.08, 0.35), 0.014, ibLin(0xD6E4EC))
            u += gi.r(0.08, 0.2)
        }
        let face = SK.mat(.black, roughness: 0.3)
        face.emission.contents = vmsImages?.closed
        face.emission.intensity = 1.2
        let panel = SCNNode(geometry: SCNPlane(width: 6.4, height: 1.37))
        panel.geometry?.materials = [face]
        panel.position = SCNVector3(CGFloat(gx) - 0.06, CGFloat(gy) + 5.75, 6.4)
        panel.eulerAngles.y = -.pi / 2
        world.addChildNode(panel)
        vmsMat = face
    }

    /// A sign panel facing the oncoming traffic (−x) on one or two posts beyond the guardrail; `at.y`
    /// is its height above the road.
    private func sign(_ img: NSImage, w: CGFloat, h: CGFloat, at c0: IV3, posts: [Float], postW: Float = 0.09) {
        let c = IV3(c0.x, c0.y + ry(c0.x), c0.z)
        let front = SK.mat(.white, roughness: 0.5)
        front.diffuse.contents = img
        front.diffuse.mipFilter = .linear
        front.diffuse.maxAnisotropy = 8
        let back = SK.mat(SK.rgb(0x8D9297), roughness: 0.5, metalness: 0.5)
        let box = SCNBox(width: w, height: h, length: 0.06, chamferRadius: 0)
        box.materials = [front, back, back, back, back, back]
        let n = SCNNode(geometry: box)
        n.position = SCNVector3(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z))
        n.eulerAngles.y = -.pi / 2
        world.addChildNode(n)
        var m = IBMesh()
        for z in posts {
            m.tube(IV3(c.x + 0.08, height(c.x, z) - 0.3, z), IV3(c.x + 0.08, c.y + Float(h) / 2 - 0.05, z), postW, postW, ibLin(0x8A9095), segs: 6)
        }
        var rng = IBRng(UInt64(c.x * 10))
        let hw = Float(w) / 2
        var u = -hw + 0.05
        while u < hw {
            let tier = rng.next() < 0.5 ? 0 : (rng.next() < 0.6 ? 1 : 2)
            iceAcc[tier].icicle(IV3(c.x + 0.02, c.y - Float(h) / 2, c.z + u), (0.05 + 0.1 * rng.next()) * (1 + Float(tier)),
                                0.01 + 0.004 * Float(tier), ibLin(0xD6E4EC))
            u += rng.r(0.06, 0.16)
        }
        world.addChildNode(m.node(glazed(0.45, metal: 0.5, side: 0.5)))
    }

    /// An amber LED board: the text rendered small, every lit pixel drawn as a round LED.
    private static func led(_ lines: [String], english: Bool) -> NSImage {
        let cw = 224, ch = 48, k = 4
        var small = [UInt8](repeating: 0, count: cw * ch * 4)
        small.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setShouldAntialias(false)
            let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            for (i, l) in lines.enumerated() {
                ibText(ctx, l, font: english ? "Helvetica-Bold" : "PingFangSC-Semibold", size: english ? 17 : 19,
                       x: CGFloat(cw) / 2, y: CGFloat(i == 0 ? 27 : 4), color: white, align: 1)
            }
        }
        let w = cw * k, h = ch * k
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let s = small[((y / k) * cw + x / k) * 4]
                let fx = Float(x % k) - 1.5, fy = Float(y % k) - 1.5
                let dot = fx * fx + fy * fy < 2.6
                let i = (y * w + x) * 4
                if dot && s > 90 { px[i] = 255; px[i + 1] = 168; px[i + 2] = 40 }
                else if dot { px[i] = 26; px[i + 1] = 20; px[i + 2] = 14 }
                else { px[i] = 6; px[i + 1] = 6; px[i + 2] = 7 }
            }
        }
        return SK.image(from: px, size: w, height: h)
    }

    // MARK: The jam

    fileprivate static let paint: [UInt32] = [0xA8ADB1, 0xA8ADB1, 0xE4E6E6, 0xE4E6E6, 0x22252A, 0x22252A, 0x5A5F64, 0x962421,
                                              0x26385C, 0xBBAA8A, 0x2F4F3E, 0x2F5D9A, 0x5E1F2A, 0xD8D9D6]
    fileprivate static let cabColors: [UInt32] = [0x2A5C9F, 0x2A5C9F, 0x2A5C9F, 0x9E2A22, 0x9E2A22, 0xDADDDB, 0x3E6A44, 0xD6A72A, 0xD0662A]
    fileprivate static let loadColors: [UInt32] = [0x3F6440, 0x2F5B9A, 0xC86A2A, 0xC9A23A, 0x7A7E80, 0x3A3D40, 0x8E3328, 0x2E5C8E, 0x9C9A92]
    fileprivate static let stripes: [UInt32] = [0xB02A26, 0x2B5DA8, 0x3A8A52, 0xD87A22, 0x6A3F8E]

    private func pickKind(_ rng: inout IBRng, lane: Int, south: Bool) -> IBKind {
        let r = rng.next()
        switch lane {
        case 0:   // inner lane
            if r < 0.1 { return south ? .boxTruck : .coach }
            if r < 0.17 { return .sleeper }
            if r < 0.23 { return .tarpTruck }
            if r < 0.31 { return .van }
            if r < 0.41 { return .mpv }
            if r < 0.51 { return .suv }
            if r < 0.63 { return .hatch }
            return .sedan
        case 1:   // outer lane: lorries and coaches
            if r < 0.17 { return .tarpTruck }
            if r < 0.29 { return .semi }
            if r < 0.37 { return .boxTruck }
            if r < 0.42 { return .tanker }
            if r < 0.46 { return .carrier }
            if r < 0.54 { return .lightTruck }
            if r < 0.66 { return south ? .tarpTruck : .sleeper }
            if r < 0.72 { return .van }
            if r < 0.86 { return .sedan }
            return rng.next() < 0.5 ? .suv : .hatch
        default:  // the hard shoulder: whoever squeezed in
            if r < 0.3 { return .sedan }
            if r < 0.45 { return .suv }
            if r < 0.6 { return .van }
            if r < 0.72 { return .lightTruck }
            if r < 0.85 { return .tarpTruck }
            return .hatch
        }
    }

    /// One vehicle of the jam into a fleet (paint, hazard lamps, a light inside).
    private func addVehicle(_ fl: inout IBFleet, _ kind: IBKind, _ f: IBFrame, _ rng: inout IBRng) {
        let hz = rng.next() < 0.45 ? Int(rng.next() * 3) % 3 : -1
        let inside = rng.next() < 0.13
        switch kind {
        case .sedan, .hatch, .suv, .mpv:
            fl.car(f, kind: kind, col: ibLin(rng.pick(IceboundScene.paint)), hz: hz, inside: inside)
        case .van:
            fl.van(f, col: ibLin(rng.pick([0xE4E6E6, 0xE4E6E6, 0xA8ADB1, 0x2F5D9A, 0xC9C2A8])), hz: hz, inside: inside)
        case .coach, .sleeper:
            fl.coach(f, stripe: ibLin(rng.pick(IceboundScene.stripes)), sleeper: kind == .sleeper, hz: hz, inside: inside || rng.next() < 0.2)
        default:
            fl.truck(f, kind: kind, cabCol: ibLin(rng.pick(IceboundScene.cabColors)), load: ibLin(rng.pick(IceboundScene.loadColors)),
                     hz: hz, inside: inside)
        }
    }

    private func buildJam() {
        var near = IBFleet(detail: true, seed: 11), far = IBFleet(detail: false, seed: 12)
        var south = IBFleet(detail: true, seed: 14), southFar = IBFleet(detail: false, seed: 15)
        var rng = IBRng(2008)
        // northbound: the two lanes and the hard shoulder, from the gap ahead of the group up over the
        // crest, and back down behind the camera
        for (lane, z) in [(0, laneIn), (1, laneOut), (2, laneHard)] {
            var x: Float = [24, 22.5, 26][lane]
            while x < 1000 {
                let k = pickKind(&rng, lane: lane, south: false)
                let L = k.length
                let cx = x + L / 2
                let f = onRoad(cx, z + rng.r(-0.2, 0.2), north: true, skew: rng.r(-0.025, 0.025))
                // the shoulder's queue is towed off as the crews come through; the lanes thin out once it moves
                let key = SIMD2<Float>(lane == 2 ? x + L : -1e4, cx > 60 && lane < 2 ? rng.next() : 2)
                if cx < 170 { near.key(key); addVehicle(&near, k, f, &rng) } else { far.key(key); addVehicle(&far, k, f, &rng) }
                x += L + rng.r(1.3, 3.6)
            }
            var xr: Float = [-13.2, -22.5, -38][lane]
            while xr > -700 {
                let k = pickKind(&rng, lane: lane, south: false)
                let L = k.length
                if lane == 2 && rng.next() < 0.25 { xr -= L + 6; continue }
                let f = onRoad(xr - L / 2, z + rng.r(-0.2, 0.2), north: true, skew: rng.r(-0.025, 0.025))
                if xr > -90 { near.key(IBMesh.noKey); addVehicle(&near, k, f, &rng) } else { far.key(IBMesh.noKey); addVehicle(&far, k, f, &rng) }
                xr -= L + rng.r(1.3, 3.6)
            }
        }
        // southbound, a little thinner, a few on its hard shoulder
        for (lane, z) in [(0, -laneIn), (1, -laneOut), (2, -laneHard)] {
            var x: Float = -700
            while x < 900 {
                let k = pickKind(&rng, lane: lane, south: true)
                let L = k.length
                let gap = rng.next() < 0.2 ? rng.r(8, 30) : rng.r(1.5, 4)
                let keep = (lane == 2 ? rng.next() < 0.35 : rng.next() < 0.88) && !(x + L > -50 && x < -12)
                if keep {
                    let f = onRoad(x + L / 2, z + rng.r(-0.2, 0.2), north: false, skew: rng.r(-0.025, 0.025))
                    if x > -60 && x < 150 { addVehicle(&south, k, f, &rng) } else { addVehicle(&southFar, k, f, &rng) }
                }
                x += L + gap
            }
        }
        addFleet(near, parent: world, north: true)
        addFleet(far, parent: world, north: true)
        addFleet(south, parent: world, north: false)
        addFleet(southFar, parent: world, north: false)

        // the group's own: the sleeper coach to Hubei, the semi of sugar oranges, the black Passat
        // across the head of the hard-shoulder queue, the silver hatchback
        var grp = IBFleet(detail: true, seed: 21)
        grp.coach(onRoad(coachX, laneIn, north: true, skew: -0.008), stripe: ibLin(0xC2302A), sleeper: true, hz: 0, inside: false)
        grp.orangeSemi(onRoad(semiX, laneOut, north: true, skew: 0.01), noise: noise)
        grp.car(onRoad(-11.6, laneHard - 0.25, north: true, skew: 0.32), kind: .sedan, col: ibLin(0x1C1E22), hz: -1, inside: false)
        grp.car(onRoad(-13.3, laneOut + 0.1, north: true, skew: -0.03), kind: .hatch, col: ibLin(0xB7BCC0), hz: 1, inside: false)
        addFleet(grp, parent: world, north: true, glass: groupGlass)
        // straw rope wound round their drive wheels (project tire_ropes)
        var rp = IBMesh()
        let straw = ibLin(0xB89A5A)
        for (x, z, r, hw) in [(coachX - 2.75, laneIn, Float(0.5), Float(1.21)), (coachX - 3.85, laneIn, 0.5, 1.21),
                              (-11.6 - 1.5, laneHard - 0.25, 0.31, 0.85), (-13.3 + 1.2, laneOut + 0.1, 0.31, 0.81)] {
            for s in [Float(-1), 1] {
                for k in 0..<5 {
                    let a = Float(k) / 5 * 2 * .pi
                    let c = IV3(x + cos(a) * r, r + sin(a) * r, z + s * (hw - 0.11))
                    rp.box(c, IV3(0.035, 0.035, 0.13), straw, yaw: 0, roll: a)
                }
            }
        }
        let rn = rp.node(glazed(0.95, side: 0.2))
        rn.isHidden = true
        world.addChildNode(rn)
        ropes = rn
        // cartons of oranges carried out and opened by the drum
        var ct = IBMesh(), fr = IBMesh()
        var crng = IBRng(23)
        for i in 0..<5 {
            let c = IV3(-7.7 + Float(i % 3) * 0.62, 0.18 + (i >= 3 ? 0.36 : 0), 9.95 + Float(i % 2) * 0.1 - (i >= 3 ? 0.05 : 0))
            ct.box(c, IV3(0.29, 0.18, 0.21), ibLin(i % 2 == 0 ? 0xD9862A : 0xE6A23A), yaw: crng.r(-0.2, 0.2))
            if i == 1 || i == 4 {
                for k in 0..<8 {
                    fr.blob(c + IV3(Float(k % 4) * 0.13 - 0.2, 0.2, Float(k / 4) * 0.14 - 0.07), IV3(0.07, 0.065, 0.07),
                            ibLin(0xE57A16), noise, seed: Float(i * 9 + k), jitter: 0.08, rings: 3, segs: 6)
                }
            }
        }
        let cn = SCNNode()
        cn.addChildNode(ct.node(glazed(0.85, side: 0.1)))
        cn.addChildNode(fr.node(SK.mat(.white, roughness: 0.5)))
        cn.isHidden = true
        world.addChildNode(cn)
        cartons = cn

        // exhaust from the idling engines: the coach, the semi's stack, the Passat, the hatchback
        for p in [SCNVector3(CGFloat(coachX) - 6.05, 0.45, CGFloat(laneIn) - 0.75), SCNVector3(CGFloat(semiX) + 5.9, 3.5, CGFloat(laneOut) - 1.05),
                  SCNVector3(-13.85, 0.32, CGFloat(laneHard) - 0.6), SCNVector3(-15.35, 0.3, CGFloat(laneOut) - 0.45)] {
            let h = SCNNode()
            h.position = p
            world.addChildNode(h)
            exhaust.append((SK.smoke(scale: 0.3, color: NSColor(white: 0.86, alpha: 0.2)), h))
        }
        // the semi's cargo on fire (event fireworks_fire): flames and smoke out of the door gap
        let cf = SCNNode()
        cf.position = SCNVector3(CGFloat(semiX) - 8.2, 2.2, CGFloat(laneOut))
        world.addChildNode(cf)
        cargoFire = [(SK.fire(scale: 1.6), cf), (SK.smoke(scale: 2.2, color: NSColor(white: 0.35, alpha: 0.3)), cf)]
        let cl = SK.fireLight(intensity: 1400, color: SK.rgb(0xFF8A3A), range: 22)
        cl.position = SCNVector3(CGFloat(semiX) - 9.5, 2.8, CGFloat(laneOut) + 1)
        cl.isHidden = true
        world.addChildNode(cl)
        cargoLight = cl
    }

    /// Turns a fleet's meshes into nodes under `parent` (lamps, hazards and glass share the scene's materials).
    private func addFleet(_ fl: IBFleet, parent: SCNNode, north: Bool, glass: SCNMaterial? = nil) {
        if bodyMat == nil {
            let b = glazed(0.42, metal: 0.25, side: 0.18, crust: 0.5); vanishing(b); bodyMat = b
            let g = glazed(0.08, metal: 0.4, side: 0.6, crust: 0.7); vanishing(g); glassMat = g
            let fm = SK.mat(.white, roughness: 0.5); vanishing(fm); fruitMat = fm
            let lm = SK.mat(SK.rgb(0x1E2328), roughness: 0.15, emission: SK.rgb(0xFFC27A)); lm.emission.intensity = 0; vanishing(lm); litMat = lm
            let gg = SK.mat(SK.rgb(0x1F272D), roughness: 0.12, metalness: 0.3, emission: SK.rgb(0xFFC98A)); gg.emission.intensity = 0; groupGlass = gg
            let t = SK.mat(SK.rgb(0x3A0806), roughness: 0.3, emission: SK.rgb(0xFF2A18)); t.emission.intensity = 0.2; vanishing(t); tailN = t
            let t2 = SK.mat(SK.rgb(0x3A0806), roughness: 0.3, emission: SK.rgb(0xFF2A18)); t2.emission.intensity = 0.1; vanishing(t2); tailS = t2
            let hd = SK.mat(SK.rgb(0xC9CACA), roughness: 0.2, emission: SK.rgb(0xFFF1D8)); hd.emission.intensity = 0; vanishing(hd); headN = hd
            let hs = SK.mat(SK.rgb(0xC9CACA), roughness: 0.2); vanishing(hs); headS = hs
            let hz = SK.mat(SK.rgb(0x3A2400), roughness: 0.3, emission: SK.rgb(0xFFA21A)); hz.emission.intensity = 1.5; vanishing(hz); hazardMat = hz
            func halo(_ c: NSColor) -> SCNMaterial {
                let m = SK.mat(c, roughness: 1)
                m.lightingModel = .constant
                m.blendMode = .add
                m.writesToDepthBuffer = false
                m.isDoubleSided = true
                m.diffuse.intensity = 0
                vanishing(m)
                return m
            }
            hazGlow = halo(SK.rgb(0xFF9A2A)); tailGlowN = halo(SK.rgb(0xFF2A1A)); tailGlowS = halo(SK.rgb(0xFF2A1A)); headGlow = halo(SK.rgb(0xFFF0D0))
            for i in 0..<3 {
                let n = SCNNode()
                let on = 0.38 + 0.04 * Double(i)
                n.runAction(.sequence([.wait(duration: 0.23 * Double(i)), .repeatForever(.sequence([
                    .fadeOpacity(to: 1, duration: 0.04), .wait(duration: on), .fadeOpacity(to: 0.04, duration: 0.04), .wait(duration: on)]))]))
                world.addChildNode(n)
                hazards.append(n)
            }
        }
        guard let bodyMat, let glassMat, let litMat, let tailN, let tailS, let headN, let headS, let hazardMat, let fruitMat else { return }
        parent.addChildNode(fl.body.node(bodyMat))
        parent.addChildNode(fl.glass.node(glass ?? glassMat))
        if !fl.lit.isEmpty { parent.addChildNode(fl.lit.node(litMat, shadow: false)) }
        if !fl.fruit.isEmpty { parent.addChildNode(fl.fruit.node(fruitMat)) }
        if !fl.tail.isEmpty { parent.addChildNode(fl.tail.node(north ? tailN : tailS, shadow: false)) }
        if !fl.head.isEmpty { parent.addChildNode(fl.head.node(north ? headN : headS, shadow: false)) }
        if let m = north ? tailGlowN : tailGlowS, !fl.glowT.isEmpty { parent.addChildNode(fl.glowT.node(m, shadow: false)) }
        if north, let m = headGlow, !fl.glowH.isEmpty { parent.addChildNode(fl.glowH.node(m, shadow: false)) }
        for i in 0..<3 {
            if !fl.haz[i].isEmpty { hazards[i].addChildNode(fl.haz[i].node(hazardMat, shadow: false)) }
            if let m = hazGlow, !fl.glowZ[i].isEmpty { hazards[i].addChildNode(fl.glowZ[i].node(m, shadow: false)) }
            iceAcc[i].append(fl.ice[i])
        }
    }

    // MARK: The fire drum

    private func buildDrum() {
        let b = SCNNode()
        var m = IBMesh()
        let rust = ibLin(0x5E3420), soot = ibLin(0x1E1A18), wood = ibLin(0x3A2C22)
        // propped on bricks
        for a in [Float(0.3), 2.4, 4.5] { m.box(IV3(cos(a) * 0.2, 0.06, sin(a) * 0.2), IV3(0.11, 0.06, 0.06), ibLin(0x8E4A36), yaw: a) }
        m.tube(IV3(0, 0.12, 0), IV3(0, 0.7, 0), 0.29, 0.29, rust, segs: 14)
        m.tube(IV3(0, 0.7, 0), IV3(0, 0.98, 0), 0.29, 0.29, soot, segs: 14)
        for y in [Float(0.38), 0.68] { m.tube(IV3(0, y, 0), IV3(0, y + 0.05, 0), 0.302, 0.302, rust * 0.8, segs: 14) }
        m.tube(IV3(0, 0.96, 0), IV3(0, 1.0, 0), 0.302, 0.302, soot, segs: 14)
        m.tube(IV3(-0.05, 0.65, 0.05), IV3(0.27, 1.22, -0.12), 0.035, 0.03, wood, segs: 4)
        m.tube(IV3(0.08, 0.65, -0.04), IV3(-0.24, 1.18, 0.14), 0.03, 0.025, wood, segs: 4)
        // fuel: branches and bamboo broken off by the ice, stacked by the drum
        var rng = IBRng(5)
        for k in 0..<7 {
            let a = rng.r(-0.4, 0.4)
            let c = IV3(-0.85 + rng.r(-0.15, 0.15), 0.06 + 0.07 * Float(k / 3), -0.35 + rng.r(-0.1, 0.1))
            m.tube(c - IV3(cos(a), 0, sin(a)) * 0.6, c + IV3(cos(a), 0, sin(a)) * 0.6, 0.04, 0.025, wood * rng.r(0.8, 1.2), segs: 4)
        }
        // a blue crate to sit on, a kettle warming
        m.box(IV3(-0.2, 0.19, 1.2), IV3(0.27, 0.19, 0.2), ibLin(0x2E5E9E), yaw: 0.3)
        m.tube(IV3(0.55, 0, -0.85), IV3(0.55, 0.34, -0.85), 0.17, 0.14, ibLin(0x2E6E9E), segs: 8, cap: true)
        b.addChildNode(m.node(glazed(0.8, side: 0.1)))
        // holes punched round the bottom, glowing when it burns
        var holes = IBMesh()
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi
            holes.box(IV3(cos(a) * 0.29, 0.25 + 0.05 * Float(i % 2), sin(a) * 0.29), IV3(0.035, 0.028, 0.008), IV3(1, 1, 1), yaw: .pi / 2 - a)
        }
        let hm = SK.mat(.black, roughness: 0.6, emission: SK.rgb(0xFF7A22))
        hm.emission.intensity = 0
        holesMat = hm
        b.addChildNode(holes.node(hm, shadow: false))
        let ember = SK.cylinder(0.25, 0.03, glow(SK.rgb(0xFF6A1A), 1.5), at: SCNVector3(0, 0.97, 0))
        ember.name = "drumEmbers"
        b.addChildNode(ember)
        // its own flames, smoke and light (the base class's fire stands for the engines' heaters here)
        let fn = SCNNode(); fn.position.y = 1.12; b.addChildNode(fn)
        let sn = SCNNode(); sn.position.y = 1.7; b.addChildNode(sn)
        drumFire = [(SK.fire(scale: 0.72), fn), (SK.smoke(scale: 0.7), sn)]
        let l = SK.fireLight(intensity: 360, color: SK.rgb(0xFF9442), range: 13)
        l.position.y = 2.4
        b.addChildNode(l)
        drumLight = l
        b.isHidden = true
        world.addChildNode(b)
        drum = b
    }

    // MARK: The road crews

    /// The clearing front: x where the crews have got to, from var `clear` (out of sight over the
    /// crest at 0, at the group at 100).
    private func clearFront(_ c: Float) -> Float { 12 + 636 * pow(1 - c, 1.7) }

    private func buildCrew() {
        let crewNode = SCNNode()
        var m = IBMesh(), glass = IBMesh(), steelM = IBMesh(), lampM = IBMesh()
        let yellow = ibLin(0xE3AE14), dark = ibLin(0x2A2B2D), steel = ibLin(0x55595D), zc: Float = 10.4
        // a wheel loader on the hard shoulder, bucket toward the group (−x), pushing the broken ice
        for x in [Float(-1.2), 1.4] {
            for s in [Float(-1), 1] {
                m.tube(IV3(x, 0.72, zc + s * 0.78), IV3(x, 0.72, zc + s * 1.2), 0.72, 0.72, dark, segs: 12, cap: true)
            }
        }
        m.box(IV3(-1.0, 1.25, zc), IV3(0.75, 0.45, 0.72), yellow)
        m.box(IV3(1.5, 1.45, zc), IV3(1.0, 0.6, 0.8), yellow)
        m.box(IV3(0.1, 1.2, zc), IV3(0.4, 0.3, 0.5), dark)
        glass.box(IV3(0.15, 2.45, zc), IV3(0.6, 0.6, 0.7), ibLin(0x26323A))
        m.box(IV3(0.15, 3.1, zc), IV3(0.7, 0.06, 0.78), yellow)
        for s in [Float(-0.55), 0.55] {
            m.tube(IV3(-0.6, 1.4, zc + s), IV3(-2.4, 0.75, zc + s), 0.1, 0.1, yellow, segs: 5)
        }
        steelM.box(IV3(-2.75, 0.42, zc), IV3(0.35, 0.4, 1.25), steel, roll: 0.2)
        // ice the bucket is pushing
        var rng = IBRng(5)
        for _ in 0..<18 {
            let s = rng.r(0.1, 0.3)
            m.box(IV3(-3.3 - rng.r(0, 0.8), s * 0.4, zc + rng.r(-1.1, 1.1)), IV3(s, s * 0.45, s * 0.8), ibLin(0xBFCAD2) * rng.r(0.8, 1.05),
                  yaw: rng.r(0, 3), pitch: rng.r(-0.3, 0.3))
        }
        // the salt spreader behind it (it pulls back once they reach the group)
        let spreader = SCNNode()
        crewNode.addChildNode(spreader)
        crewTruck = spreader
        var fl = IBFleet(detail: true, seed: 71)
        let sf = IBFrame(o: IV3(11.5, 0, zc), yaw: .pi, roll: 0)
        fl.cab(sf, fx: 3.25, hw: 1.15, col: ibLin(0xE06A1E), hz: -1, inside: false)
        fl.part(\.body, sf, -0.7, 0.88, 0, 3.0, 0.12, 0.45, IBFleet.dark)
        fl.slab(\.body, sf, -3.1, 1.2, 1.1, 2.7, 0.55, -3.3, 1.35, 1.15, ibLin(0xD9A23A))
        fl.part(\.body, sf, -3.5, 0.75, 0, 0.25, 0.08, 0.5, IBFleet.dark)
        fl.wheels(sf, [2.1, -2.0], hw: 1.11, r: 0.47, w: 0.26, dual: [false, true])
        // amber beacons, flashing
        let beacon = glow(SK.rgb(0xFFA21A), 3)
        for (i, p) in [SCNVector3(0.15, 3.25, CGFloat(zc)), SCNVector3(8.6, 3.0, CGFloat(zc))].enumerated() {
            let bn = SK.box(0.22, 0.16, 0.22, beacon, chamfer: 0.04, at: p)
            bn.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.3),
                                                  .fadeOpacity(to: 0.1, duration: 0.05), .wait(duration: 0.3)])))
            (i == 0 ? crewNode : spreader).addChildNode(bn)
        }
        for s in [Float(-0.5), 0.5] { lampM.box(IV3(-1.78, 1.6, zc + s), IV3(0.02, 0.08, 0.1), IV3(1, 1, 1)) }
        crewNode.addChildNode(m.node(glazed(0.5, metal: 0.2, side: 0.15)))
        crewNode.addChildNode(glass.node(glazed(0.08, metal: 0.4, side: 0.4)))
        crewNode.addChildNode(steelM.node(glazed(0.35, metal: 0.7, side: 0.2)))
        crewNode.addChildNode(lampM.node(glow(SK.rgb(0xFFF4DC), 2.2), shadow: false))
        addFleet(fl, parent: spreader, north: false)
        // road workers in orange chipping at the ice between the stranded lorries, a flagman
        let jobs: [(Float, Float, Bool)] = [(-1.2, 5.5, true), (0.8, 5.4, true), (-0.4, 1.7, true), (2.2, 1.65, true), (-4.5, 9.1, false), (4.0, 9.6, true)]
        for (i, j) in jobs.enumerated() {
            let p = worker(color: SK.rgb(0xEF7A1A), work: j.2, pick: i % 2 == 0, phase: Double(i) * 0.37)
            p.position = SCNVector3(CGFloat(j.0), 0, CGFloat(j.1))
            p.eulerAngles.y = j.2 ? -.pi / 2 + CGFloat(i % 3) * 0.3 - 0.3 : -.pi / 2
            p.addChildNode(SK.sphere(0.14, SK.mat(SK.rgb(0xF2C21A), roughness: 0.4), at: SCNVector3(0, 1.74, 0)))
            crewNode.addChildNode(lighten(p))
        }
        // work light at night
        let l = SCNLight()
        l.type = .omni
        l.color = SK.rgb(0xFFF0D8)
        l.intensity = 0
        l.attenuationStartDistance = 0
        l.attenuationEndDistance = 22
        l.attenuationFalloffExponent = 2
        let ln = SCNNode()
        ln.light = l
        ln.position = SCNVector3(0, 4.8, 7)
        crewNode.addChildNode(ln)
        crewLight = ln
        // salt flung from the spinner
        let sp = SCNParticleSystem()
        sp.birthRate = 260
        sp.particleLifeSpan = 0.6
        sp.emitterShape = SCNSphere(radius: 0.1)
        sp.particleImage = SK.dotImage(size: 16, hardness: 0.8)
        sp.particleSize = 0.025
        sp.particleColor = NSColor(white: 0.92, alpha: 0.8)
        sp.particleVelocity = 4
        sp.particleVelocityVariation = 2
        sp.emittingDirection = SCNVector3(0.3, -0.4, 0)
        sp.spreadingAngle = 70
        sp.acceleration = SCNVector3(0, -9.8, 0)
        sp.isLightingEnabled = false
        let spn = SCNNode()
        spn.position = SCNVector3(15.1, 0.8, CGFloat(zc))
        spreader.addChildNode(spn)
        salt = (sp, spn)
        crewNode.isHidden = true
        world.addChildNode(crewNode)
        crew = crewNode

        // the broken ice heaped along the guardrail and the central reserve behind them, in 20 m pieces
        var wr = IBRng(81)
        var x0: Float = 4
        while x0 < 700 {
            var w = IBMesh()
            var x = x0
            while x < x0 + 20 {
                let s = wr.r(0.1, 0.32)
                let z = wr.next() < 0.6 ? 11.95 + wr.r(-0.15, 0.12) : 1.95 + wr.r(-0.1, 0.15)
                w.box(IV3(x, ry(x) + s * 0.4, z), IV3(s, s * 0.45, s * 0.8), ibLin(0xB9C4CC) * wr.r(0.75, 1.05),
                      yaw: wr.r(0, 3), pitch: wr.r(-0.3, 0.3))
                x += wr.r(0.2, 0.45)
            }
            let n = w.node(glazed(0.2, side: 0.5), shadow: false)
            n.isHidden = true
            world.addChildNode(n)
            windrow.append((n, x0))
            x0 += 20
        }
    }

    // MARK: The army

    /// Fewer segments on a figure's capsules and spheres (the defaults cost ~25k triangles a person;
    /// the extras here are seen small).
    @discardableResult
    private func lighten(_ n: SCNNode) -> SCNNode {
        n.enumerateHierarchy { c, _ in
            if let g = c.geometry as? SCNCapsule { g.radialSegmentCount = 10; g.capSegmentCount = 4; g.heightSegmentCount = 1 }
            if let g = c.geometry as? SCNSphere { g.segmentCount = 10 }
            if let g = c.geometry as? SCNCylinder { g.radialSegmentCount = 10 }
        }
        return n
    }

    /// Someone in work clothes; `work`: swinging a pick or a shovel (animated), otherwise carrying it
    /// on the shoulder.
    private func worker(color: NSColor, work: Bool, pick: Bool, phase: Double) -> SCNNode {
        let p = SK.person(color: color, pose: .standing, seed: 0)
        let wood = SK.mat(SK.rgb(0x7A5A3A), roughness: 0.8), iron = SK.mat(SK.rgb(0x3E4246), roughness: 0.5, metalness: 0.6)
        guard let body = p.childNodes.first else { return p }
        func tool() -> SCNNode {
            let t = SCNNode()
            t.addChildNode(SK.cylinder(0.025, 1.1, wood, at: SCNVector3(0, -0.55, 0)))
            if pick { t.addChildNode(SK.box(0.05, 0.05, 0.62, iron, chamfer: 0.01, at: SCNVector3(0, -1.1, 0))) }
            else { t.addChildNode(SK.box(0.24, 0.3, 0.025, iron, chamfer: 0.01, at: SCNVector3(0, -1.22, 0))) }
            return t
        }
        if work {
            // arms that swing from the shoulder
            let armMat = body.childNodes.count > 6 ? body.childNodes[6].geometry?.firstMaterial : nil
            if body.childNodes.count > 6 { body.childNodes[6].removeFromParentNode(); body.childNodes[5].removeFromParentNode() }
            body.eulerAngles.x = 0.18
            for s in [CGFloat(-1), 1] {
                let pivot = SCNNode()
                pivot.position = SCNVector3(s * 0.25, 1.45, 0.02)
                let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.66))
                arm.geometry?.firstMaterial = armMat ?? SK.mat(color)
                arm.position = SCNVector3(0, -0.3, 0)
                pivot.addChildNode(arm)
                if s > 0 {
                    let t = tool()
                    t.position = SCNVector3(-0.25, -0.58, 0)
                    t.eulerAngles.x = -0.25
                    pivot.addChildNode(t)
                }
                pivot.eulerAngles.x = -1.6
                pivot.runAction(.sequence([.wait(duration: phase), .repeatForever(.sequence([
                    .rotateTo(x: -2.5, y: 0, z: 0, duration: 0.55, usesShortestUnitArc: false),
                    .rotateTo(x: -0.7, y: 0, z: 0, duration: 0.22, usesShortestUnitArc: false),
                    .wait(duration: 0.18)]))]))
                body.addChildNode(pivot)
            }
        } else {
            let t = tool()
            t.position = SCNVector3(0.3, 1.5, 0.05)
            t.eulerAngles = SCNVector3(-2.5, 0, 0.12)
            p.addChildNode(t)
        }
        return p
    }

    private func buildArmy() {
        let olive = SK.rgb(0x56603F)
        let hatMat = SK.mat(SK.rgb(0x3C3A2A), roughness: 0.95)
        // breaking the ice in the gap ahead of the group and round the vehicles
        let work = SCNNode()
        let posts: [(Float, Float, Float)] = [(7.6, 3.4, 0.5), (10.2, 2.3, -0.4), (13.0, 4.5, 2.6), (15.6, 2.9, 0.2), (14.2, 7.7, 1.2),
                                              (17.2, 8.5, -1.0), (19.6, 6.5, 2.2), (21.6, 3.5, 0.9), (18.2, 1.9, -2.2), (8.0, 9.7, 1.6),
                                              (4.6, 10.6, -2.6)]
        for (i, p) in posts.enumerated() {
            let s = worker(color: olive, work: true, pick: i % 3 != 1, phase: Double(i) * 0.31)
            s.addChildNode(SK.cylinder(0.14, 0.14, hatMat, at: SCNVector3(0, 1.76, 0)))
            lighten(s)
            s.position = SCNVector3(CGFloat(p.0), 0, CGFloat(p.1))
            s.eulerAngles.y = CGFloat(p.2)
            work.addChildNode(s)
        }
        // a red flag on the central reserve
        var fm = IBMesh()
        fm.tube(IV3(17, 0.2, 0), IV3(17, 3.0, 0), 0.025, 0.025, ibLin(0xB8B8B4), segs: 5)
        fm.sheet(nu: 6, nv: 3) { u, v in IV3(17 + 1.05 * u, 2.95 - 0.68 * v - 0.12 * u * u, 0.08 * sin(u * 5)) }
        work.addChildNode(fm.node(SK.mat(SK.rgb(0xC81E18), roughness: 0.7, doubleSided: true)))
        work.isHidden = true
        world.addChildNode(work)
        soldiers = work

        // coming up from behind in single file between the stranded cars and the central reserve, chipping
        // as they come, the flag at their head
        let col = SCNNode()
        let fz: CGFloat = 1.8
        for i in 0..<12 {
            let s = worker(color: olive, work: i % 3 == 0, pick: i % 2 == 0, phase: Double(i) * 0.27)
            s.addChildNode(SK.cylinder(0.14, 0.14, hatMat, at: SCNVector3(0, 1.76, 0)))
            lighten(s)
            s.position = SCNVector3(-16 + CGFloat(i) * 1.75, 0, fz)
            s.eulerAngles.y = .pi / 2
            col.addChildNode(s)
        }
        var cf = IBMesh()
        cf.tube(IV3(5.6, 1.0, Float(fz)), IV3(5.6, 3.2, Float(fz)), 0.025, 0.025, ibLin(0xB8B8B4), segs: 5)
        cf.sheet(nu: 6, nv: 3) { u, v in IV3(5.6 - 0.95 * u, 3.15 - 0.62 * v - 0.1 * u * u, Float(fz) + 0.08 * sin(u * 5)) }
        col.addChildNode(cf.node(SK.mat(SK.rgb(0xC81E18), roughness: 0.7, doubleSided: true)))
        let flagger = SK.person(color: olive, pose: .standing, seed: 0)
        flagger.addChildNode(SK.cylinder(0.14, 0.14, hatMat, at: SCNVector3(0, 1.76, 0)))
        lighten(flagger)
        flagger.position = SCNVector3(5.6, 0, fz - 0.3)
        flagger.eulerAngles.y = .pi / 2
        col.addChildNode(flagger)
        col.isHidden = true
        world.addChildNode(col)
        column = col

        // broken ice heaped along the lane edges where they've been working
        var ch = IBMesh()
        var rng = IBRng(97)
        for _ in 0..<170 {
            let x = rng.r(hackX0 + 6, hackX1)
            let z = rng.next() < 0.5 ? rng.r(1.8, 2.4) : rng.r(9.0, 9.6)
            let s = rng.r(0.08, 0.26)
            ch.box(IV3(x, s * 0.4, z), IV3(s, s * 0.35, s * 0.8), ibLin(0xBFCAD2) * rng.r(0.8, 1.05), yaw: rng.r(0, 3), pitch: rng.r(-0.4, 0.4))
        }
        for _ in 0..<60 {
            let x = rng.r(hackX0 + 1, hackX1), z = rng.r(2.0, 5.0)
            let s = rng.r(0.05, 0.16)
            ch.box(IV3(x, s * 0.3, z), IV3(s, s * 0.3, s * 0.7), ibLin(0xBFCAD2) * rng.r(0.8, 1.05), yaw: rng.r(0, 3))
        }
        let cn = ch.node(glazed(0.2, side: 0.5))
        cn.isHidden = true
        world.addChildNode(cn)
        chunks = cn
    }

    // MARK: The villagers' market

    private func buildMarket(english: Bool) {
        let mk = SCNNode()
        var m = IBMesh()
        let wood = ibLin(0x7A5A3A)
        // a stall by the guardrail beside the semi: a plank on two baskets, a coal stove and its pot
        let cx: Float = 2.2, cz: Float = 11.55
        m.box(IV3(cx, 0.62, cz), IV3(1.0, 0.03, 0.32), wood)
        for s in [Float(-0.75), 0.75] { m.tube(IV3(cx + s, 0, cz), IV3(cx + s, 0.6, cz), 0.25, 0.28, ibLin(0x9C7A4A), segs: 9, cap: true) }
        var rng = IBRng(17)
        for k in 0..<5 {
            let col = ibLin(k % 2 == 0 ? 0xC23B2A : 0xE0B23A)
            m.box(IV3(cx - 0.7 + Float(k) * 0.34, 0.75, cz + rng.r(-0.1, 0.1)), IV3(0.15, 0.1, 0.2), col, yaw: rng.r(-0.2, 0.2))
        }
        for k in 0..<3 {
            m.tube(IV3(cx + 1.35, 0, cz - 0.3 + Float(k) * 0.28), IV3(cx + 1.35, 0.4, cz - 0.3 + Float(k) * 0.28), 0.065, 0.065,
                   ibLin(k == 1 ? 0x3E7A4A : 0xC8322B), segs: 8, cap: true)
        }
        let sx: Float = cx - 2.0, sz: Float = 11.85
        m.tube(IV3(sx, 0, sz), IV3(sx, 0.48, sz), 0.2, 0.2, ibLin(0xD2CFC6), segs: 10, cap: true)
        m.tube(IV3(sx, 0.48, sz), IV3(sx, 0.68, sz), 0.24, 0.23, ibLin(0x9EA2A6), segs: 12, cap: true)
        for (bx, bz) in [(Float(cx + 2.4), Float(11.7)), (cx + 3.1, 11.9)] {
            m.tube(IV3(bx, 0, bz), IV3(bx, 0.34, bz), 0.22, 0.26, ibLin(0x9C7A4A), segs: 9, cap: true)
            m.blob(IV3(bx, 0.36, bz), IV3(0.2, 0.08, 0.2), ibLin(0xB86A3A), noise, seed: bx, rings: 3, segs: 6)
        }
        m.tube(IV3(cx + 2.0, 0.05, 11.2), IV3(cx + 3.6, 0.05, 12.2), 0.03, 0.03, ibLin(0x9A8650), segs: 4)
        mk.addChildNode(m.node(glazed(0.75, side: 0.1)))
        let signImg = ibDraw(300, 200) { ctx in
            ctx.setFillColor(CGColor(red: 0.69, green: 0.54, blue: 0.35, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            let ink = CGColor(gray: 0.08, alpha: 1)
            if english {
                ibText(ctx, "HOT WATER", font: "MarkerFelt-Wide", size: 40, x: 150, y: 130, color: ink, align: 1)
                ibText(ctx, "EGGS · NOODLES", font: "MarkerFelt-Wide", size: 36, x: 150, y: 60, color: ink, align: 1)
            } else {
                ibText(ctx, "开水 鸡蛋", font: "PingFangSC-Semibold", size: 58, x: 150, y: 115, color: ink, align: 1)
                ibText(ctx, "方便面", font: "PingFangSC-Semibold", size: 58, x: 150, y: 35, color: ink, align: 1)
            }
        }
        let sm = SK.mat(.white, roughness: 0.9)
        sm.diffuse.contents = signImg
        let board = SCNNode(geometry: SCNBox(width: 0.62, height: 0.42, length: 0.015, chamferRadius: 0))
        board.geometry?.materials = [sm] + Array(repeating: SK.mat(SK.rgb(0xA07E52), roughness: 0.9), count: 5)
        board.position = SCNVector3(CGFloat(cx) - 0.9, 0.42, CGFloat(cz) - 0.4)
        board.eulerAngles = SCNVector3(-0.25, -.pi / 2 - 0.3, 0)
        mk.addChildNode(board)
        // the villagers: at the stall, at the stove, two going along the queue with poles and baskets,
        // one climbing up the bank from the village with a thermos
        let clothes: [UInt32] = [0x2E3A52, 0x6B2F30, 0x5C5C5A, 0x5F4A38, 0x3E4A3A]
        let spots: [(Float, Float, CGFloat, Bool)] = [(2.4, 12.12, .pi, false), (0.0, 12.22, .pi + 0.4, false),
                                                    (-1.4, 10.3, -.pi / 2, true), (6.4, 10.5, .pi / 2 + 0.3, true), (3.2, 15.3, .pi + 0.25, false)]
        for (i, sp) in spots.enumerated() {
            let p = SK.person(color: SK.rgb(clothes[i]), pose: .standing, seed: 0)
            p.position = SCNVector3(CGFloat(sp.0), ground(CGFloat(sp.0), CGFloat(sp.1)), CGFloat(sp.1))
            p.eulerAngles.y = sp.2
            if sp.3 {
                // a carrying pole (扁担) on the shoulder, a basket at each end
                var pm = IBMesh()
                pm.tube(IV3(-0.85, 1.48, 0), IV3(0.85, 1.48, 0), 0.03, 0.03, ibLin(0x9A8650), segs: 4)
                for s in [Float(-1), 1] {
                    pm.tube(IV3(s * 0.8, 1.48, 0), IV3(s * 0.8, 0.62, 0), 0.006, 0.006, ibLin(0x5A4A30), segs: 3)
                    pm.tube(IV3(s * 0.8, 0.28, 0), IV3(s * 0.8, 0.6, 0), 0.2, 0.24, ibLin(0x9C7A4A), segs: 8, cap: true)
                }
                p.addChildNode(pm.node(SK.mat(.white, roughness: 0.85)))
            }
            if i == 4 { p.addChildNode(SK.cylinder(0.07, 0.38, SK.mat(SK.rgb(0xC8322B), roughness: 0.5), at: SCNVector3(0.32, 0.75, 0.1))) }
            mk.addChildNode(lighten(p))
        }
        let steam = SK.smoke(scale: 0.35, color: NSColor(white: 0.95, alpha: 0.3))
        let sn = SCNNode()
        sn.position = SCNVector3(CGFloat(sx), 0.8, CGFloat(sz))
        mk.addChildNode(sn)
        eggSteam = (steam, sn)
        mk.isHidden = true
        world.addChildNode(mk)
        market = mk
    }

    // MARK: The police

    private func buildPolice() {
        let n = SCNNode()
        var fl = IBFleet(detail: true, seed: 101)
        let x: Float = 30
        let f = onRoad(x, laneHard, north: true)
        fl.car(f, kind: .sedan, col: ibLin(0xE8EAEA), hz: -1, inside: false)
        for s in [Float(-1), 1] { fl.part(\.body, f, 0.1, 0.6, s * 0.885, 2.0, 0.1, 0.006, ibLin(0x1F4FA0)) }
        addFleet(fl, parent: n, north: true)
        // the light bar, red and blue in turn
        let y = CGFloat(ry(x))
        for (i, hex) in [UInt32(0xFF2418), 0x2A5BFF].enumerated() {
            let l = SK.box(0.36, 0.11, 0.42, glow(SK.rgb(hex), 2.8), chamfer: 0.03, at: SCNVector3(CGFloat(x) - 0.3, y + 1.5, CGFloat(laneHard) + (i == 0 ? -0.22 : 0.22)))
            let flash = SCNAction.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.04), .wait(duration: 0.28),
                                                           .fadeOpacity(to: 0.08, duration: 0.04), .wait(duration: 0.28)]))
            l.runAction(.sequence([.wait(duration: Double(i) * 0.32), flash]))
            n.addChildNode(l)
        }
        let light = SCNLight()
        light.type = .omni
        light.intensity = 260
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 14
        light.attenuationFalloffExponent = 2
        light.color = SK.rgb(0xFF3020)
        let ln = SCNNode()
        ln.light = light
        ln.position = SCNVector3(CGFloat(x) - 0.3, y + 2.2, CGFloat(laneHard))
        let red = SK.rgb(0xFF3020), blue = SK.rgb(0x3060FF)
        ln.runAction(.repeatForever(.sequence([
            .customAction(duration: 0) { node, _ in node.light?.color = red }, .wait(duration: 0.32),
            .customAction(duration: 0) { node, _ in node.light?.color = blue }, .wait(duration: 0.32)])))
        n.addChildNode(ln)
        // an officer in a reflective vest waving the queue on
        let cop = SK.person(color: SK.rgb(0xC7D93A), pose: .waving, seed: 0)
        cop.position = SCNVector3(26.6, CGFloat(ry(26.6)), 11.7)
        cop.eulerAngles.y = -.pi / 2
        cop.addChildNode(SK.cylinder(0.14, 0.08, SK.mat(SK.rgb(0xE8E8E4), roughness: 0.5), at: SCNVector3(0, 1.78, 0)))
        n.addChildNode(lighten(cop))
        n.isHidden = true
        world.addChildNode(n)
        police = n
    }

    // MARK: - Weather

    private var sleetKey = ""

    /// Freezing rain falls as rain however cold it is (that is what glazes everything); snow and sleet
    /// come only with weather ids that say so.
    override func updateWeather(_ s: SceneState) {
        let w = s.weather.lowercased()
        let sleet = w.contains("sleet") || w.contains("mix")
        precipKind = w.contains("snow") && !sleet ? .snow : .rain
        var st = s
        if sleet { st.precip = min(s.precip, 1.2) }
        super.updateWeather(st)
        let key = "\(sleet)|\(Int(s.precip * 2))|\(Int(s.wind / 10))|\(Int(darkness * 3))"
        guard key != sleetKey else { return }
        sleetKey = key
        weatherNode.childNode(withName: "sleet", recursively: false)?.removeFromParentNode()
        if sleet && s.precip > 0.05 {
            let n = SCNNode()
            n.name = "sleet"
            n.addParticleSystem(SK.snow(intensity: min(1, s.precip / 2) * 0.6, wind: s.wind, area: weatherArea))
            weatherNode.addChildNode(n)
        }
    }

    // MARK: - Apply

    /// Adds or removes particle systems on their holders.
    private func emit(_ list: [(SCNParticleSystem, SCNNode)], _ on: Bool) {
        for (p, h) in list {
            let attached = h.particleSystems?.contains(p) ?? false
            if on && !attached { h.addParticleSystem(p) }
            if !on && attached { h.removeParticleSystem(p) }
        }
    }

    override func apply(_ s: SceneState, old: SceneState?) {
        let ice = Float(max(0, min(100, s.v("ice", 70)))) / 100
        let clear = Float(max(0, min(100, s.v("clear", 0)))) / 100
        let co = CGFloat(max(0, min(100, s.v("co", 0))) / 100)
        let open = s.has("road_open") || s.happened("road_opens") || s.event == "road_opens"
        // 0 by day … 1 at night (from the sun; the base class's `darkness` also counts the overcast)
        let night = CGFloat(SK.smoothstep(4, -6, Float(s.sunElevation(peak: sunPeak))))
        let gloom = max(night, CGFloat(darkness) * 0.35)

        // the glaze, the icicles, the trees bowed lower, things breaking under the load
        if abs(ice - lastGlaze) > 0.003 {
            lastGlaze = ice
            let g = NSNumber(value: Double(0.06 + 0.94 * ice))
            for m in glazeMats { m.setValue(g, forKey: "glaze") }
            roadMat?.setValue(g, forKey: "glaze")
            let flat = SK.rgb(0x8F938C).blended(withFraction: CGFloat(ice), of: SK.rgb(0xBEC4C6)) ?? SK.rgb(0xAAB0B0)
            let steep = SK.rgb(0x5F5A4F).blended(withFraction: CGFloat(ice * 0.6), of: SK.rgb(0x8A8B86)) ?? SK.rgb(0x6E6B62)
            groundMat?.setValue(NSValue(scnVector4: SK.linear(flat)), forKey: "flatColor")
            groundMat?.setValue(NSValue(scnVector4: SK.linear(steep)), forKey: "steepColor")
        }
        for (i, n) in icicles.enumerated() { n.isHidden = ice < [0.12, 0.38, 0.62][min(i, 2)] }
        treesHeavy.isHidden = ice < 0.5
        treesLight.isHidden = ice >= 0.5
        fallen?.isHidden = ice < 0.75

        // the crews coming down from the crest; behind them the shoulder's queue towed away, and once
        // the road opens, gaps up the queue
        let front = clearFront(clear)
        let gone = NSNumber(value: Double(front - 4)), thin = NSNumber(value: open ? 0.45 : -1.0)
        for m in vanishMats { m.setValue(gone, forKey: "goneX"); m.setValue(thin, forKey: "thinK") }
        roadMat?.setValue(NSNumber(value: Double(front)), forKey: "clearX")
        roadMat?.setValue(NSNumber(value: open ? 1.0 : 0.0), forKey: "openK")
        crew?.position = SCNVector3(CGFloat(front), CGFloat(ry(front)), 0)
        crew?.eulerAngles.z = CGFloat(pitchAt(front))
        crew?.isHidden = open || front > 640
        crewLight?.light?.intensity = 700 * night
        crewTruck?.isHidden = front < 40
        emit(salt.map { [$0] } ?? [], !(crew?.isHidden ?? true) && front < 420 && front >= 40)
        for (n, x0) in windrow { n.isHidden = !(x0 > front + 1) }

        // lights: hazards up the queue, a few dome lights, candles in the village; everyone's lamps once it moves
        hazardMat?.emission.intensity = 0.9 + 2.4 * night
        litMat?.emission.intensity = 0.05 + 1.4 * night
        candleMat?.emission.intensity = 1.1 * night
        tailN?.emission.intensity = open ? 2.4 : 0.15 + 0.5 * night
        headN?.emission.intensity = open ? 3.0 : 0
        tailS?.emission.intensity = 0.1 + 0.35 * night
        // halos in the freezing drizzle, only once it's dark
        let dark = max(0, (gloom - 0.2) / 0.8)
        hazGlow?.diffuse.intensity = 0.9 * dark
        tailGlowN?.diffuse.intensity = (open ? 1.0 : 0.22) * dark
        tailGlowS?.diffuse.intensity = 0.15 * dark
        headGlow?.diffuse.intensity = open ? 0.8 * dark : 0
        vmsMat?.emission.contents = open ? vmsImages?.open : vmsImages?.closed
        vmsMat?.emission.intensity = 1.0 + 1.2 * night
        emit(chimneys, true)
        for (p, _) in chimneys { p.particleColor = NSColor(white: 0.8 - 0.55 * night, alpha: 0.16) }

        // the group's vehicles: engines idling for the heaters (fireLit), windows lit at night and
        // fogging up as the fumes build (co)
        let engines = s.fireLit
        let running: [Bool] = s.has("one_bus") ? [true, false, false, false] : (s.has("split") ? [true, true, true, true] : [true, false, true, true])
        for (i, e) in exhaust.enumerated() {
            let on = (engines && running[i]) || open
            e.0.birthRate = CGFloat(2.5 + 5 * (open ? 0.5 : 1 - co * 0.6))
            e.0.particleColor = NSColor(white: 0.86 - 0.5 * night, alpha: 0.12 + 0.1 * (1 - night))
            emit([e], on)
        }
        if let gg = groupGlass {
            gg.diffuse.contents = SK.rgb(0x1F272D).blended(withFraction: min(0.85, co * 1.3), of: SK.rgb(0x9AA3A8))
            gg.roughness.contents = 0.12 + 0.6 * co
            gg.emission.intensity = engines ? 0.85 * night : 0
        }
        ropes?.isHidden = !(s.has("ropes") || s.done.contains("tire_ropes"))
        cartons?.isHidden = !(s.has("oranges_given") || s.has("oranges_taken") || s.has("oranges_deal"))

        // the fire drum behind the semi (by the guardrail once moved), burning when there's wood
        let hasDrum = s.done.contains("fire_barrel") || s.has("barrel") || s.has("bonfire")
        let lit = s.has("bonfire")
        let at = s.has("barrel_moved") ? drumMoved : drumAt
        drum?.isHidden = !hasDrum
        drum?.position = SCNVector3(CGFloat(at.x), CGFloat(ry(at.x)), CGFloat(at.y))
        emit(drumFire, hasDrum && lit)
        drumLight?.isHidden = !(hasDrum && lit)
        drumLight?.base = 360 * (0.12 + 0.88 * CGFloat(darkness))
        holesMat?.emission.intensity = lit ? 1.6 : 0
        drum?.childNode(withName: "drumEmbers", recursively: false)?.isHidden = !lit
        let dk = CGFloat(darkness)
        if let f = drumFire.first?.0 { f.particleColor = SK.rgb(0xFF8A2A).withAlphaComponent(0.35 + 0.65 * dk) }
        if drumFire.count > 1 { drumFire[1].0.particleColor = NSColor(white: 0.82 - 0.62 * dk, alpha: 0.22 - 0.1 * dk) }
        // the semi's cargo of fireworks going up
        let cargoBurning = s.now("fireworks_fire")
        emit(cargoFire, cargoBurning)
        cargoLight?.isHidden = !cargoBurning

        // the villagers' market
        let marketOn = s.has("market") && !s.isNight
        market?.isHidden = !marketOn
        emit(eggSteam.map { [$0] } ?? [], marketOn)

        // the army: coming up from behind, then at work on the ice
        let marching = s.event == "army_arrives" || (s.now("army_arrives") && !s.has("army"))
        let working = !marching && (s.has("army") || s.happened("army_arrives"))
        column?.isHidden = !marching
        soldiers?.isHidden = !working
        chunks?.isHidden = !working
        roadMat?.setValue(NSNumber(value: working || open ? 1.0 : 0.0), forKey: "hackK")

        roadMat?.setValue(NSNumber(value: s.has("walked") ? 1.0 : 0.0), forKey: "walkK")
        towerUp?.isHidden = s.has("pylon_down")
        towerDown?.isHidden = !s.has("pylon_down")
        wireMarks?.isHidden = !(s.has("pylon_down") && s.has("lines_marked"))
        police?.isHidden = !open

        showPeople(s, spots: spots(for: s, at: at, lit: hasDrum && lit), parent: world)
        showBodies(s.dead, spots: (0..<5).map { i in Spot(22 + CGFloat(i) * 2.3, CGFloat(ry(22 + Float(i) * 2.3)) + 0.02, 11.95, facing: .pi / 2) }, parent: world)
    }

    private func spots(for s: SceneState, at drum: SIMD2<Float>, lit: Bool) -> [Spot] {
        let fx = CGFloat(drum.x), fz = CGFloat(drum.y)
        func toward(_ x: CGFloat, _ z: CGFloat, _ tx: CGFloat, _ tz: CGFloat) -> CGFloat { atan2(tx - x, tz - z) }
        let cold = s.isNight || s.precip >= 1.5 || s.temp < -5
        if s.has("village") {
            // down in 坳上村, round a doorway
            return (0..<12).map { i in
                let x = 52 + CGFloat(i % 4) * 1.1, z = 52 - 6.5 - CGFloat(i / 4) * 1.0
                return Spot(x, ground(x, z), z, facing: .pi, pose: cold ? .huddled : .standing)
            }
        }
        // on the coach's door step (its door is at the front, on the right, facing the semi)
        let step = Spot(CGFloat(coachX) + 4.5, 0.35, CGFloat(laneIn) + 1.35, facing: 0.3, pose: .sitting)
        if lit {
            // round the drum, two on crates; by the guardrail the ring opens toward the road
            var out: [Spot] = []
            let moved = drum.y > 10
            let ring: [CGFloat] = moved ? [270, 235, 305, 200, 340, 170, 10] : [90, 135, 180, 225, 270, 45, 315]
            for (i, deg) in ring.enumerated() {
                let a = deg * .pi / 180, r: CGFloat = 1.15 + CGFloat(i % 2) * 0.15
                let x = fx + cos(a) * r, z = fz + sin(a) * r
                out.append(Spot(x, 0.02, z, facing: toward(x, z, fx, fz), pose: cold && i % 3 != 2 ? .huddled : .standing))
            }
            out.insert(Spot(fx - 0.2, 0.02, fz + (moved ? -1.5 : 1.2), facing: toward(fx - 0.2, fz + (moved ? -1.5 : 1.2), fx, fz), pose: .sitting), at: 2)
            out.insert(step, at: 4)
            out += [Spot(fx + 2.6, 0.02, 9.9, facing: -1.6, pose: .standing), Spot(-0.6, 0.02, 10.4, facing: 2.2, pose: .standing),
                    Spot(6.2, 0.02, 10.2, facing: 1.4, pose: .standing)]
            return out
        }
        if s.isNight {
            // most of them inside the coach (out of sight), one on its step, one smoking by the semi's tail
            var out: [Spot] = [step, Spot(CGFloat(semiX) - 9.3, 0.02, CGFloat(laneOut) + 1.4, facing: -0.4, pose: .standing)]
            for i in 0..<12 { out.append(Spot(CGFloat(coachX) - 4.5 + CGFloat(i) * 0.75, 1.25, CGFloat(laneIn), facing: .pi / 2, pose: .sitting)) }
            return out
        }
        // daytime: at the semi's open doors, along the shoulder, by the coach
        let day: [(CGFloat, CGFloat, CGFloat, SK.Pose)] = [
            (CGFloat(semiX) - 9.4, 8.2, 1.4, .standing), (-0.4, 10.4, 0.6, .standing), (CGFloat(semiX) - 9.6, 6.4, 1.9, .standing),
            (3.6, 10.5, 1.5, .standing), (-5.2, 10.7, 0.9, .standing), (8.6, 10.5, 1.7, .standing), (-9.6, 9.0, 0.4, .standing),
            (10.8, 11.6, 1.6, .standing), (CGFloat(coachX) - 7.1, 5.1, 1.2, .standing), (-1.6, 11.7, -2.4, .standing)]
        var out = day.map { Spot($0.0, 0.02, $0.1, facing: $0.2, pose: $0.3) }
        out.insert(step, at: 2)
        return out
    }
}

// MARK: - File-private toolkit

fileprivate typealias IV3 = SIMD3<Float>

/// sRGB hex → linear RGB (vertex colours are used as linear values).
fileprivate func ibLin(_ hex: UInt32, _ k: Float = 1) -> IV3 {
    func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return IV3(f(Float((hex >> 16) & 0xFF) / 255), f(Float((hex >> 8) & 0xFF) / 255), f(Float(hex & 0xFF) / 255)) * k
}

/// Rotate roll (z) → pitch (x) → yaw (y), like SceneKit's euler angles.
fileprivate func ibRot(_ p: IV3, yaw: Float, pitch: Float = 0, roll: Float = 0) -> IV3 {
    var q = p
    if roll != 0 { let c = cos(roll), s = sin(roll); q = IV3(q.x * c - q.y * s, q.x * s + q.y * c, q.z) }
    if pitch != 0 { let c = cos(pitch), s = sin(pitch); q = IV3(q.x, q.y * c - q.z * s, q.y * s + q.z * c) }
    if yaw != 0 { let c = cos(yaw), s = sin(yaw); q = IV3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c) }
    return q
}

fileprivate struct IBRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x7F4A7C15 }
    mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
    mutating func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    mutating func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(next() * Float(a.count)))] }
}

/// Packs a triangle mesh into SceneKit sources: float positions, face-averaged normals, vertex colours
/// and (optionally) texture coordinates.
fileprivate func ibGeometry(_ pts: [IV3], _ cols: [IV3], _ uvs: [SIMD2<Float>]?, _ idx: [UInt32]) -> SCNGeometry {
    let n = pts.count
    var nrm = [IV3](repeating: .zero, count: n)
    idx.withUnsafeBufferPointer { ib in
        pts.withUnsafeBufferPointer { pb in
            nrm.withUnsafeMutableBufferPointer { nb in
                var t = 0
                while t + 2 < ib.count {
                    let a = Int(ib[t]), b = Int(ib[t + 1]), c = Int(ib[t + 2])
                    let e1 = pb[b] - pb[a], e2 = pb[c] - pb[a]
                    let fn = IV3(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
                    nb[a] += fn; nb[b] += fn; nb[c] += fn
                    t += 3
                }
            }
        }
    }
    var pos = [Float](repeating: 0, count: n * 3)
    var nor = [Float](repeating: 0, count: n * 3)
    var col = [Float](repeating: 1, count: n * 4)
    pos.withUnsafeMutableBufferPointer { pp in
        nor.withUnsafeMutableBufferPointer { np in
            col.withUnsafeMutableBufferPointer { cp in
                pts.withUnsafeBufferPointer { pb in
                    nrm.withUnsafeBufferPointer { nb in
                        cols.withUnsafeBufferPointer { cb in
                            for i in 0..<n {
                                let p = pb[i], q = nb[i]
                                pp[i * 3] = p.x; pp[i * 3 + 1] = p.y; pp[i * 3 + 2] = p.z
                                let l = max(1e-6, sqrt(q.x * q.x + q.y * q.y + q.z * q.z))
                                np[i * 3] = q.x / l; np[i * 3 + 1] = q.y / l; np[i * 3 + 2] = q.z / l
                                if i < cb.count { let c = cb[i]; cp[i * 4] = c.x; cp[i * 4 + 1] = c.y; cp[i * 4 + 2] = c.z }
                            }
                        }
                    }
                }
            }
        }
    }
    var sources = [
        SCNGeometrySource(data: pos.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                          componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
        SCNGeometrySource(data: nor.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                          componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
        SCNGeometrySource(data: col.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: n, usesFloatComponents: true,
                          componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
    ]
    if let uvs, uvs.count == n {
        var tex = [Float](repeating: 0, count: n * 2)
        for i in 0..<n { tex[i * 2] = uvs[i].x; tex[i * 2 + 1] = uvs[i].y }
        sources.append(SCNGeometrySource(data: tex.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: n,
                                         usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8))
    }
    let el = SCNGeometryElement(data: idx.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                                primitiveCount: idx.count / 3, bytesPerIndex: 4)
    return SCNGeometry(sources: sources, elements: [el])
}

/// Merged triangle mesh with vertex colours: many small parts, one node. Parts can carry a key (their
/// texture coordinates) that the vanishing shader reads.
fileprivate struct IBMesh {
    var pts: [IV3] = []
    var cols: [IV3] = []
    var idx: [UInt32] = []
    /// (first vertex, key) runs.
    var keys: [(Int, SIMD2<Float>)] = []

    static let noKey = SIMD2<Float>(-1e4, 2)

    var isEmpty: Bool { idx.isEmpty }

    mutating func setKey(_ k: SIMD2<Float>) { keys.append((pts.count, k)) }

    func node(_ m: SCNMaterial, shadow: Bool = true) -> SCNNode {
        guard !idx.isEmpty else { return SCNNode() }
        var uvs = [SIMD2<Float>](repeating: IBMesh.noKey, count: pts.count)
        for (i, (s, k)) in keys.enumerated() {
            let e = i + 1 < keys.count ? keys[i + 1].0 : pts.count
            if s < e { for j in s..<e { uvs[j] = k } }
        }
        let g = ibGeometry(pts, cols, uvs, idx)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.castsShadow = shadow
        return n
    }

    mutating func append(_ o: IBMesh) {
        let base = pts.count
        if !keys.isEmpty || !o.keys.isEmpty {
            if o.keys.first?.0 != 0 { keys.append((base, IBMesh.noKey)) }
            for (s, k) in o.keys { keys.append((s + base, k)) }
        }
        pts += o.pts
        cols += o.cols
        idx += o.idx.map { $0 + UInt32(base) }
    }

    mutating func quad(_ a: IV3, _ b: IV3, _ c: IV3, _ d: IV3, _ col: IV3) {
        let n = UInt32(pts.count)
        pts.append(a); pts.append(b); pts.append(c); pts.append(d)
        cols.append(col); cols.append(col); cols.append(col); cols.append(col)
        idx.append(n); idx.append(n + 1); idx.append(n + 2)
        idx.append(n); idx.append(n + 2); idx.append(n + 3)
    }

    mutating func tri(_ a: IV3, _ b: IV3, _ c: IV3, _ col: IV3) {
        let n = UInt32(pts.count)
        pts.append(a); pts.append(b); pts.append(c)
        cols.append(col); cols.append(col); cols.append(col)
        idx.append(n); idx.append(n + 1); idx.append(n + 2)
    }

    /// Six faces through eight corners (index = x + 2y + 4z bits): any convex hexahedron.
    mutating func hexa(_ P: [IV3], _ col: IV3, top: IV3? = nil, bottom: Bool = true) {
        quad(P[1], P[3], P[7], P[5], col)                 // +x
        quad(P[0], P[4], P[6], P[2], col)                 // −x
        quad(P[2], P[6], P[7], P[3], top ?? col)          // +y
        if bottom { quad(P[0], P[1], P[5], P[4], col) }   // −y
        quad(P[4], P[5], P[7], P[6], col)                 // +z
        quad(P[0], P[2], P[3], P[1], col)                 // −z
    }

    /// Flat-shaded box: centre, half extents, rotated roll → pitch → yaw.
    mutating func box(_ c: IV3, _ h: IV3, _ col: IV3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, top: IV3? = nil, bottom: Bool = true) {
        var P = [IV3](repeating: .zero, count: 8)
        for i in 0..<8 {
            let s = IV3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1)
            P[i] = c + ibRot(s * h, yaw: yaw, pitch: pitch, roll: roll)
        }
        hexa(P, col, top: top, bottom: bottom)
    }

    /// Tapered cylinder from `a` to `b` (smooth sides, optional caps).
    mutating func tube(_ a: IV3, _ b: IV3, _ r0: Float, _ r1: Float, _ col: IV3, segs: Int = 6, cap: Bool = false) {
        let axis = b - a
        let len = simd_length(axis)
        guard len > 1e-4 else { return }
        let w = axis / len
        let up: IV3 = abs(w.y) < 0.95 ? IV3(0, 1, 0) : IV3(1, 0, 0)
        let u = simd_normalize(simd_cross(up, w))
        let v = simd_cross(w, u)
        let base = UInt32(pts.count)
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            let d = u * cos(t) + v * sin(t)
            pts.append(a + d * r0); cols.append(col)
            pts.append(b + d * r1); cols.append(col)
        }
        let S = UInt32(segs)
        for j in 0..<S {
            let p0 = base + j * 2, p1 = p0 + 1
            let q0 = base + ((j + 1) % S) * 2, q1 = q0 + 1
            idx.append(p0); idx.append(q0); idx.append(p1)
            idx.append(q0); idx.append(q1); idx.append(p1)
        }
        if cap {
            let c0 = UInt32(pts.count)
            pts.append(b); cols.append(col)
            for j in 0..<S { idx.append(c0); idx.append(base + j * 2 + 1); idx.append(base + ((j + 1) % S) * 2 + 1) }
            let c1 = UInt32(pts.count)
            pts.append(a); cols.append(col)
            for j in 0..<S { idx.append(c1); idx.append(base + ((j + 1) % S) * 2); idx.append(base + j * 2) }
        }
    }

    /// A cone from a ring (radius r at `base`) to `apex`; `cap` closes the underside.
    mutating func cone(_ base: IV3, _ r: Float, apex: IV3, _ col: IV3, segs: Int = 6, rot: Float = 0, cap: Bool = false) {
        let b0 = UInt32(pts.count)
        pts.append(apex); cols.append(col * 1.12)
        for j in 0..<segs {
            let t = rot + Float(j) / Float(segs) * 2 * .pi
            pts.append(base + IV3(cos(t) * r, 0, sin(t) * r)); cols.append(col * 0.8)
        }
        let S = UInt32(segs)
        for j in 0..<S { idx.append(b0); idx.append(b0 + 1 + (j + 1) % S); idx.append(b0 + 1 + j) }
        if cap {
            let c0 = UInt32(pts.count)
            pts.append(base + (apex - base) * 0.15); cols.append(col * 0.55)
            for j in 0..<S { idx.append(c0); idx.append(b0 + 1 + j); idx.append(b0 + 1 + (j + 1) % S) }
        }
    }

    /// A soft round glow facing `n`: a fan, full colour in the middle, black at the rim (drawn additively).
    mutating func halo(_ c: IV3, _ r: Float, facing n: IV3) {
        let up: IV3 = abs(n.y) < 0.9 ? IV3(0, 1, 0) : IV3(1, 0, 0)
        let u = simd_normalize(simd_cross(up, n)), v = simd_cross(n, u)
        let b = UInt32(pts.count)
        pts.append(c + n * 0.03); cols.append(IV3(1, 1, 1))
        for j in 0..<8 {
            let a = Float(j) / 8 * 2 * .pi
            pts.append(c + (u * cos(a) + v * sin(a)) * r); cols.append(IV3(0, 0, 0))
        }
        for j in 0..<UInt32(8) { idx.append(b); idx.append(b + 1 + j); idx.append(b + 1 + (j + 1) % 8) }
    }

    /// An icicle hanging from `top`.
    mutating func icicle(_ top: IV3, _ len: Float, _ r: Float, _ col: IV3) {
        let b = UInt32(pts.count)
        for j in 0..<4 {
            let a = Float(j) * .pi / 2 + 0.4
            pts.append(top + IV3(cos(a) * r, 0, sin(a) * r)); cols.append(col)
        }
        pts.append(top - IV3(0, len, 0)); cols.append(col)
        for j in 0..<UInt32(4) { idx.append(b + j); idx.append(b + (j + 1) % 4); idx.append(b + 4) }
    }

    /// Lumpy ellipsoid (tree crowns, hedges, fruit): darker underneath, noise-varied colour.
    mutating func blob(_ c: IV3, _ r: IV3, _ col: IV3, _ nz: SK.Noise, seed: Float, jitter: Float = 0.22, rings: Int = 5, segs: Int = 8,
                       under: Float = 0.55, vary: Float = 0.25) {
        let base = UInt32(pts.count)
        for i in 0...rings {
            let v = Float(i) / Float(rings)
            let phi = v * .pi
            for j in 0..<segs {
                let th = Float(j) / Float(segs) * 2 * .pi
                let d = IV3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                let n = nz.value(d.x * 1.7 + seed, d.z * 1.7 + d.y * 1.2 + seed * 0.37)
                let k = 1 + jitter * (2 * n - 1)
                pts.append(c + IV3(d.x * r.x, d.y * r.y, d.z * r.z) * k)
                let shade = under + (1 - under) * (0.5 + 0.5 * d.y)
                cols.append(col * (shade * (1 - vary * 0.5 + vary * n)))
            }
        }
        let S = UInt32(segs)
        for i in 0..<UInt32(rings) {
            for j in 0..<S {
                let a = base + i * S + j, b = base + i * S + (j + 1) % S
                let cc = a + S, d = b + S
                idx.append(a); idx.append(b); idx.append(cc)
                idx.append(b); idx.append(d); idx.append(cc)
            }
        }
    }

    /// A sagging wire or rope from `a` to `b`.
    mutating func rope(_ a: IV3, _ b: IV3, sag: Float, r: Float, _ col: IV3, segs: Int = 10, sides: Int = 4) {
        var prev = a
        for i in 1...segs {
            let t = Float(i) / Float(segs)
            let p = a + (b - a) * t - IV3(0, sag * 4 * t * (1 - t), 0)
            tube(prev, p, r, r, col, segs: sides)
            prev = p
        }
    }

    /// A grid sheet (flags, tarps) from a position function over (u, v) ∈ [0, 1]².
    mutating func sheet(nu: Int, nv: Int, _ col: IV3 = IV3(1, 1, 1), _ p: (Float, Float) -> IV3) {
        let base = UInt32(pts.count)
        for j in 0...nv {
            for i in 0...nu {
                pts.append(p(Float(i) / Float(nu), Float(j) / Float(nv)))
                cols.append(col)
            }
        }
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) {
            for i in 0..<UInt32(nu) {
                let a = base + j * row + i, b = a + 1, c = a + row, d = c + 1
                idx.append(a); idx.append(c); idx.append(b)
                idx.append(b); idx.append(c); idx.append(d)
            }
        }
    }

    /// Hipped roof over an eave rectangle centred at `c` (ridge along local x).
    mutating func hipRoof(_ c: IV3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ col: IV3) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> IV3 { c + ibRot(IV3(x, y, z), yaw: yaw) }
        let Le = halfL + over, We = halfW + over
        let drop = over * rise / max(0.1, halfW)
        let R = max(0.3, halfL - halfW)
        quad(P(-Le, -drop, We), P(Le, -drop, We), P(R, rise, 0), P(-R, rise, 0), col)
        quad(P(Le, -drop, -We), P(-Le, -drop, -We), P(-R, rise, 0), P(R, rise, 0), col * 0.8)
        tri(P(Le, -drop, We), P(Le, -drop, -We), P(R, rise, 0), col * 0.9)
        tri(P(-Le, -drop, -We), P(-Le, -drop, We), P(-R, rise, 0), col * 0.86)
        quad(P(-Le, -drop, We), P(-Le, -drop, -We), P(Le, -drop, -We), P(Le, -drop, We), col * 0.4)
    }

    /// Pitched roof with gable ends; `c` is the centre at eave height, ridge along local x.
    mutating func gable(_ c: IV3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ col: IV3, gableCol: IV3) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> IV3 { c + ibRot(IV3(x, y, z), yaw: yaw) }
        let L = halfL + over, W = halfW + over
        let drop = over * rise / max(0.1, halfW)
        quad(P(-L, -drop, W), P(L, -drop, W), P(L, rise, 0), P(-L, rise, 0), col)
        quad(P(L, -drop, -W), P(-L, -drop, -W), P(-L, rise, 0), P(L, rise, 0), col * 0.75)
        tri(P(halfL, 0, -halfW), P(halfL, rise, 0), P(halfL, 0, halfW), gableCol)
        tri(P(-halfL, 0, halfW), P(-halfL, rise, 0), P(-halfL, 0, -halfW), gableCol)
        quad(P(-L, -drop, W), P(-L, -drop, -W), P(L, -drop, -W), P(L, -drop, W), col * 0.4)
        box(P(0, rise + 0.05, 0), IV3(L, 0.08, 0.14), col * 0.7, yaw: yaw)
    }
}

/// A vehicle's frame: origin on the road under its centre, front toward local +x, tilted (`roll`) with
/// the road's grade.
fileprivate struct IBFrame {
    var o: IV3
    var yaw: Float
    var roll: Float
    func p(_ x: Float, _ y: Float, _ z: Float) -> IV3 { o + ibRot(IV3(x, y, z), yaw: yaw, roll: roll) }
}

fileprivate enum IBKind {
    case sedan, hatch, suv, mpv, van, coach, sleeper, boxTruck, tarpTruck, semi, tanker, carrier, lightTruck

    var length: Float {
        switch self {
        case .sedan, .suv: return 4.6
        case .hatch: return 4.0
        case .mpv: return 4.8
        case .van: return 4.3
        case .coach, .sleeper: return 12
        case .boxTruck: return 9
        case .tarpTruck: return 11
        case .semi: return 16.5
        case .tanker: return 13
        case .carrier: return 18
        case .lightTruck: return 6.2
        }
    }
}

/// Merged meshes for a set of vehicles: paintwork and running gear, glass (and glass lit from
/// inside), fruit, lamps, hazard lamps in three blink groups, icicles in three tiers.
fileprivate struct IBFleet {
    var body = IBMesh(), glass = IBMesh(), lit = IBMesh(), fruit = IBMesh(), tail = IBMesh(), head = IBMesh()
    var haz = [IBMesh(), IBMesh(), IBMesh()]
    var ice = [IBMesh(), IBMesh(), IBMesh()]
    /// Halos round the lamps (seen at night through the freezing rain): rear, front, hazards.
    var glowT = IBMesh(), glowH = IBMesh()
    var glowZ = [IBMesh(), IBMesh(), IBMesh()]
    var detail: Bool
    var rng: IBRng

    init(detail: Bool, seed: UInt64) {
        self.detail = detail
        rng = IBRng(seed)
    }

    static let dark = ibLin(0x1B1C1E)
    static let white = ibLin(0xE4E6E5)
    static let glassCol = ibLin(0x1F272D)
    static let iceCol = ibLin(0xD6E4EC)
    static let one = IV3(1, 1, 1)

    /// Keys everything built from now on (see `IBMesh.setKey`).
    mutating func key(_ k: SIMD2<Float>) {
        body.setKey(k); glass.setKey(k); lit.setKey(k); fruit.setKey(k); tail.setKey(k); head.setKey(k)
        glowT.setKey(k); glowH.setKey(k)
        for i in 0..<3 { haz[i].setKey(k); ice[i].setKey(k); glowZ[i].setKey(k) }
    }

    // MARK: Parts

    /// A box in the vehicle's frame: centre and half extents.
    mutating func part(_ m: WritableKeyPath<IBFleet, IBMesh>, _ f: IBFrame, _ x: Float, _ y: Float, _ z: Float,
                       _ hx: Float, _ hy: Float, _ hz: Float, _ col: IV3, top: IV3? = nil) {
        self[keyPath: m].box(f.p(x, y, z), IV3(hx, hy, hz), col, yaw: f.yaw, roll: f.roll, top: top)
    }

    /// A block between two horizontal rectangles in the vehicle's frame: bottom x0…x1 × ±w0 at y0,
    /// top tx0…tx1 × ±w1 at y1 (bonnets, raked windscreens, tarps over a load).
    mutating func slab(_ m: WritableKeyPath<IBFleet, IBMesh>, _ f: IBFrame, _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ w0: Float,
                       _ tx0: Float, _ tx1: Float, _ w1: Float, _ col: IV3, top: IV3? = nil, bottom: Bool = false) {
        var P = [IV3](repeating: .zero, count: 8)
        for i in 0..<8 {
            let up = (i & 2) != 0
            let x = (i & 1) == 0 ? (up ? tx0 : x0) : (up ? tx1 : x1)
            let w = up ? w1 : w0
            P[i] = f.p(x, up ? y1 : y0, (i & 4) == 0 ? -w : w)
        }
        self[keyPath: m].hexa(P, col, top: top, bottom: bottom)
    }

    mutating func wheels(_ f: IBFrame, _ xs: [Float], hw: Float, r: Float, w: Float = 0.22, dual: [Bool]? = nil) {
        let rim = ibLin(0x8D9195)
        for (i, x) in xs.enumerated() {
            let ww = (dual?[i] ?? false) ? w * 2 : w
            for side in [Float(-1), 1] {
                let zo = side * hw, zi = side * (hw - ww)
                if detail {
                    body.tube(f.p(x, r, zi), f.p(x, r, zo), r, r, IBFleet.dark, segs: 10, cap: true)
                    body.tube(f.p(x, r, zo), f.p(x, r, zo + side * 0.015), r * 0.55, r * 0.5, rim, segs: 8, cap: true)
                } else {
                    part(\.body, f, x, r, (zo + zi) / 2, r * 0.9, r, ww / 2, IBFleet.dark)
                }
            }
        }
    }

    /// A halo at a lamp, facing back (−x) or forward.
    mutating func glow(_ m: WritableKeyPath<IBFleet, IBMesh>, _ f: IBFrame, _ x: Float, _ y: Float, _ z: Float, radius: Float, back: Bool) {
        self[keyPath: m].halo(f.p(x, y, z), radius, facing: ibRot(IV3(back ? -1 : 1, 0, 0), yaw: f.yaw, roll: f.roll))
    }

    /// Rear lamps and headlamps, and the indicators at the corners (hazard group `hz`, −1: off).
    mutating func lamps(_ f: IBFrame, front: Float?, rear: Float?, y: Float, hw: Float, hz: Int, big: Bool = false) {
        let s: Float = big ? 0.2 : 0.14
        for side in [Float(-1), 1] {
            let zc = side * (hw - s - 0.07)
            if let r = rear {
                part(\.tail, f, r - 0.012, y, zc, 0.02, big ? 0.1 : 0.065, s, IBFleet.one)
                glow(\.glowT, f, r - 0.05, y, zc, radius: big ? 0.34 : 0.26, back: true)
                if hz >= 0 {
                    part(\.haz[hz], f, r - 0.016, y, side * (hw - 0.05), 0.02, 0.05, 0.05, IBFleet.one)
                    glow(\.glowZ[hz], f, r - 0.06, y, side * (hw - 0.05), radius: 0.36, back: true)
                }
            }
            if let fr = front {
                part(\.head, f, fr + 0.012, y - 0.04, zc, 0.02, big ? 0.09 : 0.06, s, IBFleet.one)
                glow(\.glowH, f, fr + 0.05, y - 0.04, zc, radius: 0.4, back: false)
                if hz >= 0 {
                    part(\.haz[hz], f, fr + 0.016, y - 0.04, side * (hw - 0.05), 0.02, 0.045, 0.05, IBFleet.one)
                    glow(\.glowZ[hz], f, fr + 0.06, y - 0.04, side * (hw - 0.05), radius: 0.34, back: false)
                }
            }
        }
    }

    /// Icicles along an edge (vehicle frame), spread over the three tiers.
    mutating func icicles(_ f: IBFrame, _ a: IV3, _ b: IV3, every: Float = 0.12) {
        guard detail else { return }
        let len = simd_length(b - a)
        let n = max(1, Int(len / every))
        for k in 0..<n {
            let t = (Float(k) + rng.next()) / Float(n)
            let p = a + (b - a) * t
            let r = rng.next()
            let tier = r < 0.42 ? 0 : (r < 0.75 ? 1 : 2)
            let l = (0.03 + 0.07 * rng.next()) * (1 + Float(tier) * 0.9)
            ice[tier].icicle(f.p(p.x, p.y, p.z), l, 0.007 + 0.0035 * Float(tier), IBFleet.iceCol)
        }
    }

    // MARK: Vehicles

    mutating func car(_ f: IBFrame, kind: IBKind, col: IV3, hz: Int, inside: Bool) {
        var hl: Float = 2.3, hw: Float = 0.88, y0: Float = 0.3, belt: Float = 0.8, roof: Float = 1.43, r: Float = 0.31
        // greenhouse: bottom rear…front, top rear…front
        var gb0: Float = -1.3, gb1: Float = 0.85, gt0: Float = -0.95, gt1: Float = 0.28
        switch kind {
        case .hatch: hl = 2.0; hw = 0.84; roof = 1.47; gb0 = -1.9; gb1 = 0.62; gt0 = -1.75; gt1 = 0.05
        case .suv: hw = 0.9; y0 = 0.4; belt = 1.0; roof = 1.74; r = 0.36; gb0 = -2.05; gb1 = 0.95; gt0 = -1.95; gt1 = 0.38
        case .mpv: hl = 2.4; hw = 0.9; y0 = 0.33; belt = 0.93; roof = 1.75; gb0 = -2.3; gb1 = 1.3; gt0 = -2.22; gt1 = 0.45
        default: break
        }
        let ax = hl - 0.82
        wheels(f, [ax, -ax + 0.05], hw: hw - 0.03, r: r)
        slab(\.body, f, -hl, hl, y0, belt, hw, -hl + 0.05, hl - 0.1, hw - 0.02, col, bottom: true)
        part(\.body, f, hl - 0.03, y0 + 0.13, 0, 0.06, 0.12, hw - 0.05, IBFleet.dark)
        part(\.body, f, -hl + 0.03, y0 + 0.13, 0, 0.06, 0.12, hw - 0.05, IBFleet.dark)
        let g: WritableKeyPath<IBFleet, IBMesh> = inside ? \.lit : \.glass
        slab(g, f, gb0, gb1, belt, roof - 0.04, hw - 0.07, gt0, gt1, hw - 0.2, IBFleet.glassCol)
        slab(\.body, f, gt0 - 0.03, gt1 + 0.03, roof - 0.05, roof, hw - 0.19, gt0 + 0.03, gt1 - 0.03, hw - 0.24, col)
        if detail {
            for side in [Float(-1), 1] {
                part(\.body, f, (gt0 + gt1) / 2 + 0.05, (belt + roof) / 2, side * (hw - 0.14), 0.05, (roof - belt) / 2 - 0.02, 0.07, col)
                part(\.body, f, gb1 - 0.05, belt + 0.18, side * (hw + 0.06), 0.05, 0.06, 0.07, col)
                icicles(f, IV3(-hl + 0.1, y0, side * (hw - 0.01)), IV3(hl - 0.1, y0, side * (hw - 0.01)))
                icicles(f, IV3(gt0, roof - 0.05, side * (hw - 0.19)), IV3(gt1, roof - 0.05, side * (hw - 0.19)), every: 0.15)
            }
            icicles(f, IV3(hl + 0.03, y0 + 0.01, -hw + 0.1), IV3(hl + 0.03, y0 + 0.01, hw - 0.1), every: 0.1)
            icicles(f, IV3(-hl - 0.03, y0 + 0.01, -hw + 0.1), IV3(-hl - 0.03, y0 + 0.01, hw - 0.1), every: 0.1)
        }
        lamps(f, front: hl, rear: -hl, y: belt - 0.12, hw: hw, hz: hz)
    }

    mutating func van(_ f: IBFrame, col: IV3, hz: Int, inside: Bool) {
        let hl: Float = 2.15, hw: Float = 0.84
        wheels(f, [hl - 0.7, -hl + 0.75], hw: hw - 0.03, r: 0.3)
        slab(\.body, f, -hl, hl, 0.3, 1.02, hw, -hl, hl - 0.03, hw, col, bottom: true)
        let g: WritableKeyPath<IBFleet, IBMesh> = inside ? \.lit : \.glass
        slab(g, f, -hl + 0.03, hl - 0.05, 1.02, 1.6, hw - 0.02, -hl + 0.05, hl - 0.34, hw - 0.04, IBFleet.glassCol)
        slab(\.body, f, -hl + 0.01, hl - 0.33, 1.6, 1.93, hw - 0.03, -hl + 0.04, hl - 0.45, hw - 0.07, col)
        part(\.body, f, hl - 0.01, 0.42, 0, 0.05, 0.11, hw - 0.04, IBFleet.dark)
        if detail {
            for x in [Float(-1.1), 0.0, 0.9] {
                for side in [Float(-1), 1] { part(\.body, f, x, 1.31, side * (hw - 0.025), 0.06, 0.29, 0.03, col) }
            }
            for side in [Float(-1), 1] {
                icicles(f, IV3(-hl + 0.1, 0.3, side * hw), IV3(hl - 0.1, 0.3, side * hw))
                icicles(f, IV3(-hl + 0.05, 1.93, side * (hw - 0.05)), IV3(hl - 0.45, 1.93, side * (hw - 0.05)), every: 0.14)
            }
        }
        lamps(f, front: hl, rear: -hl, y: 0.8, hw: hw, hz: hz)
    }

    mutating func coach(_ f: IBFrame, stripe: IV3, sleeper: Bool, hz: Int, inside: Bool) {
        let hl: Float = 6, hw: Float = 1.25, white = IBFleet.white
        let g: WritableKeyPath<IBFleet, IBMesh> = inside ? \.lit : \.glass
        wheels(f, [4.0, -2.75, -3.85], hw: hw - 0.04, r: 0.5, w: 0.3)
        part(\.body, f, 0, 0.93, 0, hl, 0.48, hw, white)                          // luggage bays
        part(\.body, f, 0, 0.52, 0, hl - 0.04, 0.09, hw + 0.004, IBFleet.dark)
        part(\.body, f, 0, 1.33, 0, hl + 0.004, 0.09, hw + 0.006, stripe)
        let top: Float = sleeper ? 3.1 : 2.6
        if sleeper {
            part(g, f, -0.3, 1.78, 0, hl - 0.75, 0.32, hw - 0.01, IBFleet.glassCol)   // the lower bunks' windows
            part(\.body, f, -0.52, 2.28, 0, hl - 0.52, 0.18, hw, white)
            part(g, f, -0.3, 2.78, 0, hl - 0.75, 0.32, hw - 0.01, IBFleet.glassCol)   // the upper bunks'
            part(\.body, f, 0, 3.32, 0, hl, 0.22, hw, white)
            slab(\.body, f, -hl + 0.03, hl - 0.15, 3.54, 3.7, hw - 0.02, -hl + 0.25, hl - 0.6, hw - 0.3, white)
        } else {
            part(g, f, -0.3, 2.0, 0, hl - 0.75, 0.56, hw - 0.01, IBFleet.glassCol)
            part(\.body, f, 0, 2.88, 0, hl, 0.32, hw, white)
            slab(\.body, f, -hl + 0.03, hl - 0.15, 3.2, 3.36, hw - 0.02, -hl + 0.25, hl - 0.6, hw - 0.3, white)
        }
        // windscreen, the door at the front on the right, the rear wall and its small window
        part(\.glass, f, hl - 0.52, (1.42 + top) / 2, 0, 0.52, (top - 1.42) / 2, hw - 0.02, IBFleet.glassCol)
        part(\.body, f, -hl + 0.23, (1.42 + top) / 2, 0, 0.23, (top - 1.42) / 2, hw, white)
        part(\.glass, f, -hl - 0.004, top - 0.35, 0, 0.006, 0.25, hw - 0.35, IBFleet.glassCol)
        part(\.glass, f, 4.55, 1.55, hw + 0.006, 0.45, 1.0, 0.006, IBFleet.glassCol)
        part(\.body, f, -hl - 0.005, 1.0, 0, 0.01, 0.3, hw - 0.3, IBFleet.dark)
        if detail {
            let roofY: Float = sleeper ? 3.54 : 3.2
            for side in [Float(-1), 1] {
                var x: Float = -5.2
                while x < 4.6 {
                    part(\.body, f, x, (1.42 + top) / 2, side * (hw + 0.003), 0.05, (top - 1.42) / 2, 0.006, white)
                    x += sleeper ? 1.05 : 1.6
                }
                // mirrors on their arms (the "rabbit ears")
                part(\.body, f, hl + 0.25, 2.25, side * (hw + 0.12), 0.03, 0.3, 0.03, IBFleet.dark)
                part(\.body, f, hl + 0.32, 1.95, side * (hw + 0.15), 0.04, 0.2, 0.1, IBFleet.dark)
                icicles(f, IV3(-hl + 0.1, roofY, side * (hw - 0.02)), IV3(hl - 0.2, roofY, side * (hw - 0.02)), every: 0.14)
                icicles(f, IV3(-hl + 0.1, 0.45, side * (hw + 0.004)), IV3(hl - 0.1, 0.45, side * (hw + 0.004)), every: 0.16)
            }
            icicles(f, IV3(hl + 0.01, 1.42, -hw + 0.1), IV3(hl + 0.01, 1.42, hw - 0.1), every: 0.1)
        }
        lamps(f, front: hl, rear: -hl, y: 0.82, hw: hw, hz: hz, big: true)
    }

    /// A flat-fronted cab-over cab (Dongfeng, FAW), its front at x = `fx`.
    mutating func cab(_ f: IBFrame, fx: Float, hw: Float, col: IV3, hz: Int, inside: Bool, big: Bool = false) {
        let L: Float = big ? 2.3 : 1.85, bx = fx - L
        let top: Float = big ? 3.35 : 2.85, gb: Float = big ? 1.95 : 1.7
        part(\.body, f, fx - L / 2, 0.82, 0, L / 2, 0.12, hw - 0.1, IBFleet.dark)
        slab(\.body, f, bx, fx, 0.95, gb, hw, bx, fx - 0.03, hw, col, bottom: true)
        let g: WritableKeyPath<IBFleet, IBMesh> = inside ? \.lit : \.glass
        slab(g, f, bx + 0.08, fx - 0.03, gb, top - 0.32, hw - 0.02, bx + 0.08, fx - 0.2, hw - 0.06, IBFleet.glassCol)
        slab(\.body, f, bx, fx - 0.2, top - 0.32, top, hw - 0.05, bx + 0.05, fx - 0.32, hw - 0.12, col)
        part(\.body, f, bx + 0.07, (gb + top - 0.32) / 2, 0, 0.07, (top - 0.32 - gb) / 2 + 0.01, hw - 0.01, col)
        part(\.body, f, fx + 0.02, 0.72, 0, 0.08, 0.17, hw - 0.02, IBFleet.dark)
        part(\.body, f, fx + 0.004, gb - 0.38, 0, 0.012, 0.2, hw - 0.42, IBFleet.dark)
        if detail {
            for side in [Float(-1), 1] {
                part(\.body, f, fx - 0.1, gb + 0.32, side * (hw + 0.2), 0.03, 0.2, 0.08, IBFleet.dark)
                part(\.body, f, fx - 0.55, 0.72, side * (hw - 0.05), 0.25, 0.04, 0.12, IBFleet.dark)
                icicles(f, IV3(bx + 0.05, top, side * (hw - 0.12)), IV3(fx - 0.32, top, side * (hw - 0.12)), every: 0.13)
            }
            icicles(f, IV3(fx + 0.05, gb, -hw + 0.1), IV3(fx + 0.05, gb, hw - 0.1), every: 0.1)
            icicles(f, IV3(fx + 0.1, 0.55, -hw + 0.1), IV3(fx + 0.1, 0.55, hw - 0.1), every: 0.1)
        }
        for side in [Float(-1), 1] {
            part(\.head, f, fx + 0.1, 0.78, side * (hw - 0.38), 0.02, 0.07, 0.17, IBFleet.one)
            glow(\.glowH, f, fx + 0.14, 0.78, side * (hw - 0.38), radius: 0.45, back: false)
            if hz >= 0 {
                part(\.haz[hz], f, fx + 0.1, 0.78, side * (hw - 0.09), 0.02, 0.06, 0.07, IBFleet.one)
                glow(\.glowZ[hz], f, fx + 0.15, 0.78, side * (hw - 0.09), radius: 0.38, back: false)
            }
        }
    }

    mutating func truck(_ f: IBFrame, kind: IBKind, cabCol: IV3, load: IV3, hz: Int, inside: Bool) {
        let hw: Float = 1.25, dark = IBFleet.dark
        switch kind {
        case .boxTruck:
            cab(f, fx: 4.5, hw: hw, col: cabCol, hz: hz, inside: inside)
            part(\.body, f, -0.9, 0.88, 0, 3.6, 0.12, 0.45, dark)
            part(\.body, f, -1.05, 2.3, 0, 3.45, 1.25, hw, load)
            wheels(f, [3.3, -2.5, -3.6], hw: hw - 0.04, r: 0.48, w: 0.26, dual: [false, true, true])
            lamps(f, front: nil, rear: -4.5, y: 0.95, hw: hw, hz: hz, big: true)
            if detail { for s in [Float(-1), 1] { icicles(f, IV3(-4.45, 3.55, s * hw), IV3(2.35, 3.55, s * hw), every: 0.14) } }
        case .tarpTruck:
            cab(f, fx: 5.5, hw: hw, col: cabCol, hz: hz, inside: inside)
            part(\.body, f, -1.1, 0.88, 0, 4.3, 0.12, 0.45, dark)
            part(\.body, f, -1.05, 1.18, 0, 4.45, 0.08, hw, ibLin(0x5B4B3A))
            for s in [Float(-1), 1] { part(\.body, f, -1.05, 1.6, s * (hw - 0.03), 4.45, 0.36, 0.03, cabCol * 0.85) }
            part(\.body, f, -5.47, 1.6, 0, 0.03, 0.36, hw, cabCol * 0.85)
            slab(\.body, f, -5.42, 3.33, 1.96, 3.25, hw - 0.04, -5.2, 3.1, hw - 0.42, load)
            wheels(f, [4.3, -2.9, -4.1], hw: hw - 0.04, r: 0.5, w: 0.26, dual: [false, true, true])
            lamps(f, front: nil, rear: -5.5, y: 0.95, hw: hw, hz: hz, big: true)
            if detail { for s in [Float(-1), 1] { icicles(f, IV3(-5.4, 1.24, s * hw), IV3(3.3, 1.24, s * hw), every: 0.13) } }
        case .semi:
            cab(f, fx: 8.25, hw: hw, col: cabCol, hz: hz, inside: inside, big: true)
            part(\.body, f, 0, 0.95, 0, 7.5, 0.13, 0.5, dark)
            part(\.body, f, -1.4, 2.66, 0, 6.85, 1.34, hw, load)
            wheels(f, [7.0, 5.0, 3.75, -5.2, -6.45, -7.65], hw: hw - 0.04, r: 0.5, w: 0.26, dual: [false, true, true, true, true, true])
            lamps(f, front: nil, rear: -8.25, y: 0.95, hw: hw, hz: hz, big: true)
            if detail { for s in [Float(-1), 1] { icicles(f, IV3(-8.2, 4.0, s * hw), IV3(5.4, 4.0, s * hw), every: 0.15) } }
        case .tanker:
            cab(f, fx: 6.5, hw: hw, col: cabCol, hz: hz, inside: inside)
            part(\.body, f, -0.9, 0.88, 0, 5.5, 0.12, 0.45, dark)
            body.tube(f.p(-6.3, 2.05, 0), f.p(4.4, 2.05, 0), 1.0, 1.0, ibLin(0xB9BDC0), segs: detail ? 14 : 8, cap: true)
            wheels(f, [5.3, -3.6, -4.8], hw: hw - 0.04, r: 0.5, w: 0.26, dual: [false, true, true])
            lamps(f, front: nil, rear: -6.5, y: 0.95, hw: hw, hz: hz, big: true)
        case .carrier:
            cab(f, fx: 9, hw: hw, col: cabCol, hz: hz, inside: inside, big: true)
            part(\.body, f, -1.4, 0.85, 0, 7.6, 0.08, hw, dark)
            part(\.body, f, -1.4, 2.55, 0, 7.6, 0.06, hw, dark)
            var x: Float = -8.8
            while x < 6.4 {
                for s in [Float(-1), 1] { part(\.body, f, x, 1.7, s * (hw - 0.05), 0.06, 0.85, 0.06, cabCol * 0.8) }
                x += 3.0
            }
            let saved = detail
            detail = false
            for (i, y) in [Float(0.93), 2.61].enumerated() {
                for k in 0..<4 {
                    let cx: Float = 4.6 - Float(k) * 3.9 - Float(i) * 0.3
                    let c = ibLin(rng.pick([0xE4E6E6, 0xA8ADB1, 0x22252A, 0x962421, 0x2F5D9A]))
                    car(IBFrame(o: f.p(cx, y, 0), yaw: f.yaw, roll: f.roll), kind: .hatch, col: c, hz: -1, inside: false)
                }
            }
            detail = saved
            wheels(f, [7.8, 5.9, -5.8, -7.0, -8.2], hw: hw - 0.04, r: 0.45, w: 0.24)
            lamps(f, front: nil, rear: -9, y: 0.8, hw: hw, hz: hz, big: true)
        default:
            // a light lorry with an open bed and a load under a tarp
            let lw: Float = 1.0
            cab(f, fx: 3.1, hw: lw, col: cabCol, hz: hz, inside: inside)
            part(\.body, f, -0.6, 0.8, 0, 2.4, 0.1, 0.35, dark)
            part(\.body, f, -1.05, 1.05, 0, 2.05, 0.07, lw, ibLin(0x5B4B3A))
            for s in [Float(-1), 1] { part(\.body, f, -1.05, 1.35, s * (lw - 0.03), 2.05, 0.25, 0.03, cabCol * 0.85) }
            slab(\.body, f, -3.0, 1.0, 1.6, 2.3, lw - 0.05, -2.9, 0.85, lw - 0.3, load)
            wheels(f, [2.2, -1.9], hw: lw - 0.03, r: 0.4, w: 0.22, dual: [false, true])
            lamps(f, front: nil, rear: -3.1, y: 0.85, hw: lw, hz: hz)
        }
    }

    /// The group's semi-trailer: a red tractor, a box trailer of sugar oranges from Guangdong, its rear
    /// doors swung open on the stacked cartons (and, right at the back, a secret).
    mutating func orangeSemi(_ f: IBFrame, noise: SK.Noise) {
        let hw: Float = 1.25, shell = ibLin(0xD3D6D5), dark = IBFleet.dark
        cab(f, fx: 8.25, hw: hw, col: ibLin(0xA42B22), hz: 2, inside: false, big: true)
        part(\.body, f, 0, 0.95, 0, 7.5, 0.13, 0.5, dark)
        // the box: floor, roof, sides and front wall, open at the back
        let x0: Float = -8.25, x1: Float = 5.45, y0: Float = 1.32, y1: Float = 4.0
        part(\.body, f, (x0 + x1) / 2, y0 - 0.06, 0, (x1 - x0) / 2, 0.06, hw, dark)
        part(\.body, f, (x0 + x1) / 2, y1 - 0.04, 0, (x1 - x0) / 2, 0.04, hw, shell)
        for s in [Float(-1), 1] {
            part(\.body, f, (x0 + x1) / 2, (y0 + y1) / 2, s * (hw - 0.03), (x1 - x0) / 2, (y1 - y0) / 2, 0.03, shell)
            part(\.body, f, (x0 + x1) / 2, y0 + 0.5, s * (hw + 0.004), (x1 - x0) / 2 - 0.1, 0.12, 0.004, ibLin(0x2F5DA0))
        }
        part(\.body, f, x1 - 0.03, (y0 + y1) / 2, 0, 0.03, (y1 - y0) / 2, hw, shell)
        part(\.body, f, (x0 + x1) / 2, (y0 + y1) / 2, 0, (x1 - x0) / 2 - 0.08, (y1 - y0) / 2 - 0.06, hw - 0.08, ibLin(0x2A2622))
        // its doors, swung right round against the sides
        for s in [Float(-1), 1] {
            part(\.body, f, x0 + 0.62, (y0 + y1) / 2, s * (hw + 0.06), 0.62, (y1 - y0) / 2 - 0.02, 0.025, shell * 0.94)
        }
        // cartons of sugar oranges stacked to the roof, a few gone from the back rows
        var x = x0 + 0.35
        var row = 0
        while x < x0 + 3.2 {
            var z = -hw + 0.32
            var col = 0
            while z < hw - 0.2 {
                var y = y0
                for level in 0..<6 {
                    // the back row is short of a few cartons (taken down, given away)
                    let gone = row == 0 && ((col == 1 && level >= 4) || (col == 3 && level == 5))
                    if !gone {
                        let c = rng.next() < 0.65 ? ibLin(0xD9862A) : ibLin(0xE6A23A)
                        part(\.body, f, x + rng.r(-0.03, 0.03), y + 0.21, z, 0.27, 0.2, 0.2, c * rng.r(0.85, 1.05))
                        part(\.body, f, x - 0.272, y + 0.27, z, 0.004, 0.04, 0.08, ibLin(0x2E6B2E))
                    }
                    y += 0.42
                    if y > y1 - 0.3 { break }
                }
                z += 0.44
                col += 1
            }
            x += 0.58
            row += 1
        }
        wheels(f, [7.0, 5.0, 3.75, -5.2, -6.45, -7.65], hw: hw - 0.04, r: 0.5, w: 0.26, dual: [false, true, true, true, true, true])
        lamps(f, front: nil, rear: -8.25, y: 0.95, hw: hw, hz: 2, big: true)
        for s in [Float(-1), 1] {
            icicles(f, IV3(x0 + 0.05, y1, s * hw), IV3(x1 - 0.05, y1, s * hw), every: 0.12)
            icicles(f, IV3(x0 + 0.05, y0 - 0.1, s * hw), IV3(x1 - 0.05, y0 - 0.1, s * hw), every: 0.14)
        }
        icicles(f, IV3(x0 - 0.02, y1, -hw + 0.1), IV3(x0 - 0.02, y1, hw - 0.1), every: 0.1)
        // net bags of oranges set down by the tailboard
        for (i, p) in [(-8.9, -0.4), (-9.2, 0.2), (-8.8, 0.75)].enumerated() {
            fruit.blob(f.p(Float(p.0), 0.17, Float(p.1)), IV3(0.22, 0.17, 0.2), ibLin(i == 1 ? 0xD8641A : 0xE0781C), noise,
                       seed: Float(i) * 5, jitter: 0.25, rings: 4, segs: 7)
        }
    }
}

// MARK: - Drawing (thread-safe: scenes are built off the main thread)

fileprivate func ibDraw(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> NSImage {
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return NSImage(size: NSSize(width: w, height: h))
    }
    body(ctx)
    guard let img = ctx.makeImage() else { return NSImage(size: NSSize(width: w, height: h)) }
    return NSImage(cgImage: img, size: NSSize(width: w, height: h))
}

/// One line of text at (x, baseline y); align 0 left, 1 centre, 2 right.
@discardableResult
fileprivate func ibText(_ ctx: CGContext, _ s: String, font: String, size: CGFloat, x: CGFloat, y: CGFloat,
                        color: CGColor, align: Int = 0) -> CGFloat {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: x - (align == 1 ? w / 2 : (align == 2 ? w : 0)), y: y)
    CTLineDraw(line, ctx)
    return w
}

// MARK: - Shaders

/// Ice on vertex-coloured things: a white crust of ice and sleet on whatever faces up, a clear glaze
/// on the sides (gloss, drips), all scaled by `glaze`.
fileprivate let ibGlazeShader = """
#pragma arguments
float glaze;
float sideIce;
float crust;
#pragma declaration
float ibg_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float ibg_noise(float3 x) {
    float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(ibg_hash(i + float3(0,0,0)), ibg_hash(i + float3(1,0,0)), f.x),
                   mix(ibg_hash(i + float3(0,1,0)), ibg_hash(i + float3(1,1,0)), f.x), f.y),
               mix(mix(ibg_hash(i + float3(0,0,1)), ibg_hash(i + float3(1,0,1)), f.x),
                   mix(ibg_hash(i + float3(0,1,1)), ibg_hash(i + float3(1,1,1)), f.x), f.y), f.z);
}
#pragma body
if (glaze > 0.001) {
    float3 gN = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 gP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float gF = length(fwidth(gP * 6.0));
    float gn = mix(ibg_noise(gP * 2.1) * 0.55 + ibg_noise(gP * 6.0) * 0.45, 0.5, smoothstep(0.4, 1.2, gF));
    float gUp = smoothstep(0.3, 0.85, gN.y + (gn - 0.5) * 0.4);
    float gDrip = mix(ibg_noise(float3(gP.x * 11.0, gP.y * 1.3, gP.z * 11.0)), 0.5, smoothstep(0.4, 1.2, gF * 1.8));
    float gK = glaze * (gUp * crust * (0.6 + 0.4 * gn) + sideIce * (1.0 - gUp) * (0.3 + 0.7 * gDrip));
    gK = clamp(gK, 0.0, 0.9);
    float3 gIce = float3(0.58, 0.64, 0.70) * (0.88 + 0.24 * gn);
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, gIce, gK);
    _surface.roughness = mix(_surface.roughness, 0.1, clamp(glaze * (0.45 + 0.55 * gUp), 0.0, 0.8));
    _surface.metalness = _surface.metalness * (1.0 - gK);
}
"""

/// Collapses a merged vehicle whose key says it has driven off: x beyond `goneX` (the crews have
/// cleared past it), or y below `thinK` (the queue is moving).
fileprivate let ibVanishShader = """
#pragma arguments
float goneX;
float thinK;
#pragma body
float2 vk = _geometry.texcoords[0];
if (vk.x > goneX || vk.y < thinK) { _geometry.position = float4(0.0, -9999.0, 0.0, 1.0); }
"""

/// The carriageways: asphalt and markings under a sheet of rutted ice (`glaze`); the northbound
/// carriageway cleared beyond `clearX`, wet and salted (the ruts worn to wet tracks once `openK`);
/// the ice broken up where the soldiers worked (`hack*`); footprints along the guardrail (`walkK`).
fileprivate let ibRoadShader = """
#pragma arguments
float glaze;
float clearX;
float openK;
float walkK;
float hackX0;
float hackX1;
float hackK;
#pragma declaration
float ibr_hash(float2 p) { float2 q = fract(p * 0.3183099 + 0.1) * 17.0; return fract(q.x * q.y * (q.x + q.y)); }
float ibr_noise(float2 p) {
    float2 i = floor(p); float2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(ibr_hash(i), ibr_hash(i + float2(1.0, 0.0)), f.x), mix(ibr_hash(i + float2(0.0, 1.0)), ibr_hash(i + float2(1.0, 1.0)), f.x), f.y);
}
float ibr_fbm(float2 p) { float s = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { s += a * ibr_noise(p); p = p * 2.07 + 13.7; a *= 0.5; } return s / 0.9375; }
float ibr_line(float d, float w, float fw) { return 1.0 - smoothstep(w - fw, w + fw, d); }
#pragma body
float3 rP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
float2 rQ = rP.xz;
float rZ = abs(rP.z);
float rFw = max(length(fwidth(rQ)), 0.0001);
float rFine = 1.0 - smoothstep(0.015, 0.08, rFw);
float rMid = 1.0 - smoothstep(0.12, 0.6, rFw);
// asphalt and markings: edge lines at 1.75 and 9.25, the dashed lane line at 5.5 (6 m on, 9 off)
float rA = mix(0.5, ibr_fbm(rQ * 1.9), rMid);
float3 rCol = float3(0.032, 0.034, 0.037) * (0.75 + 0.5 * rA);
float rMk = max(ibr_line(abs(rZ - 1.75), 0.08, rFw), ibr_line(abs(rZ - 9.25), 0.08, rFw));
float rPh = fract((rP.x + 3000.0) / 15.0);
float rDash = smoothstep(0.0, 0.005 + rFw / 15.0, rPh) * (1.0 - smoothstep(0.4, 0.405 + rFw / 15.0, rPh));
rMk = max(rMk, rDash * ibr_line(abs(rZ - 5.5), 0.08, rFw));
rCol = mix(rCol, float3(0.55, 0.55, 0.53), rMk * 0.9);
// the ice sheet, thinner in the frozen wheel ruts
float rLn = min(abs(rZ - 3.625), abs(rZ - 7.375));
float rRut = (1.0 - smoothstep(0.15, 0.45, abs(rLn - 0.85))) * step(1.75, rZ) * step(rZ, 9.25);
float rI1 = mix(0.5, ibr_fbm(rQ * 0.37 + 5.0), rMid);
float rI2 = mix(0.5, ibr_fbm(rQ * 4.3 + 9.0), rFine);
float rCover = clamp(glaze * (0.78 + 0.5 * (rI1 - 0.5)) * (1.0 - 0.45 * rRut), 0.0, 1.0);
float3 rIce = mix(float3(0.26, 0.29, 0.33), float3(0.56, 0.61, 0.67), smoothstep(0.25, 0.8, rI2 * 0.6 + rI1 * 0.4));
// cleared beyond the crews' front (the northbound side); once traffic moves, the ruts worn to wet tracks
float rClr = step(1.0, rP.z) * smoothstep(clearX - 0.4, clearX + 0.4, rP.x);
float rTrack = openK * rRut * step(0.0, rP.z);
// broken up with picks where the soldiers worked
if (hackK > 0.0 && rP.x > hackX0 && rP.x < hackX1 && rP.z > 1.75 && rP.z < 9.3) {
    float2 cq = rQ * float2(1.6, 2.2);
    float2 cf = fract(cq);
    float edge = min(min(cf.x, 1.0 - cf.x), min(cf.y, 1.0 - cf.y));
    float h = ibr_hash(floor(cq) + 3.1);
    rCover *= (h < 0.45 ? 0.12 : 1.0) * smoothstep(0.02, 0.09, edge);
}
// a fringe of slush along the edge of the cleared road
float rEdge = (1.0 - smoothstep(0.4, 2.5, abs(rP.x - clearX))) * step(1.0, rP.z) * (1.0 - openK);
rCover *= (1.0 - rClr) * (1.0 - 0.75 * rTrack);
rCol = mix(rCol, rIce, rCover);
float rSalt = step(0.9, ibr_hash(floor(rQ * 22.0))) * rFine;
float rWet = max(rClr, rTrack * 0.8);
rCol = mix(rCol, float3(0.018, 0.02, 0.022) + rSalt * 0.22, rWet);
rCol = mix(rCol, float3(0.2, 0.21, 0.22), rEdge * 0.5 * glaze);
// footprints in the slush along the guardrail, leading ahead
if (walkK > 0.0 && rP.z > 11.6 && rP.z < 12.4 && rP.x > -2.0) {
    float zc = 12.06 + 0.06 * sin(rP.x * 0.13) + 0.03 * sin(rP.x * 0.47);
    float st = 0.37;
    float k = floor(rP.x / st);
    float sd = (fmod(abs(k), 2.0) < 0.5) ? -1.0 : 1.0;
    float2 dd = float2((rP.x - (k + 0.5) * st) / 0.15, (rP.z - zc - sd * 0.1) / 0.055);
    float fp = 1.0 - smoothstep(0.7, 1.0, length(dd));
    float trail = 1.0 - smoothstep(0.08, 0.28, abs(rP.z - zc));
    float pr = mix(trail * 0.45, fp, rFine);
    rCol = mix(rCol, float3(0.1, 0.105, 0.11), clamp(pr * walkK * (0.3 + 0.7 * rCover), 0.0, 0.85));
}
_surface.diffuse.rgb = rCol;
_surface.roughness = mix(mix(0.6, 0.22, rWet), 0.08, rCover);
"""
