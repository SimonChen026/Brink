import SceneKit
import AppKit

/// 终章 · 潮见町 — a fishing town on a Sanriku-style ria coast, a Friday afternoon in March,
/// 14:46: a magnitude-9 earthquake, and some forty minutes later the tsunami.
///
/// Layout (metres): x → east (the sea), z → south, y ↑; y = 0 is the town's ground datum, the sea
/// normally lies at y = −0.8. The shrine hill's flat top (境内, the precinct of 八幡神社) is at the
/// origin, 30 m up, radius ≈ 24 m; the hill's foot is ≈ 90 m out. The town fills the valley north
/// and west of the hill; its coast runs NNE from the harbour at the hill's north-east foot. A cedar
/// ridge closes the valley to the north and runs out to sea as the north headland, the south ridge
/// becomes the south headland: the bay opens to the east. The stone steps run straight down from
/// the torii at the precinct's north-east corner to the street at the hill's foot, where the
/// two-storey 水产与防灾研修中心 stands on the quay; the three-storey 潮见小学 is 300 m inland.
/// The default camera stands at the south-west edge of the precinct and looks past the fire and
/// the people, down over the town, the harbour and the bay.
///
/// Shown from state:
/// - flag `wave_hit`: the intact town (houses with lit windows at night, roads, poles, cars, the
///   fish market, oil tanks, boats at the quay, the pine row) becomes a field of wooden rubble —
///   bare foundations, debris heaps and carpets, roofs, whole houses dumped askew, overturned cars,
///   boats thrown inland (one on the roof of the training centre), snapped poles, bent steel
///   frames; the concrete buildings (centre, school, flats, town office, inn) stand as gutted
///   shells with a mud line at the high water; the slopes below the run-up are stripped.
/// - var `flood` (m): the water level in the low town (one sheet for the bay and the town; black
///   and full of floating wreckage while it is high, a muddy bay and puddles once it has fallen).
/// - vars `town_fire`, `hill_fire`: fires and smoke columns in the rubble, their glow on the smoke
///   and an orange night sky; the fire climbing the hill's north slope, burnt trees below it.
/// - var `signal`: the SOS in front of the shrine (white boards, or swept into the snow), then a
///   smoke fire and a flag, then the radio antenna with its lamp and a torch signalling at night.
/// - var `crowd`: townspeople (one merged mesh, up to 40 figures) around the shrine and the store.
/// - var `rescue`: ships out in the bay, a far-off helicopter, an army convoy coming down the road over
///   the north ridge (headlights at night), a lane being cleared through the rubble by an excavator;
///   flags `heli` (helicopter hovering over the hill top, people waving), `sdf` (army trucks, a tent
///   and soldiers on the harbour road below the hill), `road_open` (the whole lane and convoy).
/// - projects `tarp` (blue tarp shelter), `firebreak` (a cleared band on the north slope), `sos`,
///   `spring` (bamboo pipe to the fountain), `radio` (antenna), `route` (marker flags on the path
///   up the back ridge); shelter integrity (damaged shrine roof); flags `snow_ground` (snow on the
///   ground and roofs), `sos_swept`, `fled_fire` (everyone on the back slope, the precinct burnt),
///   `waited` / `at_school` (round 1: people on the roof of the centre / school), event `r_tide`
///   (a torch blinking in the school); before the wave the people stand on the street by the centre
///   (seen through the torii); the fire, the people, the dead (a row of blankets at the edge).
final class FinaleScene: ScenarioScene {

    // MARK: - Set-out

    private let noise = SK.Noise(seed: 311)
    private let topY: Float = 30                       // the precinct on the hill top
    private let plateauR: Float = 24
    private let hillR: Float = 90
    private let seaY: Float = -0.8
    private let runup: Float = 13.5                    // how high up the slopes the wave ran
    private let stairT = SIMD2<Float>(18.79, -14.93)   // top of the stone steps (precinct edge)
    private let stairB = SIMD2<Float>(59.5, -47.3)     // their foot, on the street
    private let stairDir = SIMD2<Float>(0.783, -0.622)
    private let stairBY: Float = 1.5
    private let fireXZ = SIMD2<Float>(3, -1)
    private let hallXZ = SIMD2<Float>(-10, -8)         // 拝殿, facing ESE
    private let hallYaw: Float = -0.6
    private let officeXZ = SIMD2<Float>(13, 11)        // 社务所
    private let storeXZ = SIMD2<Float>(17, -5)         // 防灾仓库
    private let fountainXZ = SIMD2<Float>(6.5, -7)     // 手水舍
    // the town grid: origin on the coast at the hill's foot, u along the coast (NNE), v inland (WNW)
    private let townO = SIMD2<Float>(158, -60)
    private let townU = SIMD2<Float>(0.313, -0.950)
    private let townV = SIMD2<Float>(-0.950, -0.313)
    private let townYaw: Float = 1.2525                // turns local +x onto townU (+z then faces the sea)
    private let centerXZ = SIMD2<Float>(118, -88)      // 水产与防灾研修中心
    private let schoolXZ = SIMD2<Float>(-20, -430)     // 潮见小学
    private let marketXZ = SIMD2<Float>(212, -235)     // fish market on the quay
    // ridges as polylines: (x, z, crest height, half width)
    private let northRidge: [SIMD4<Float>] = [SIMD4(-3200, -940, 300, 380), SIMD4(-1000, -900, 220, 330), SIMD4(-200, -880, 180, 300),
                                               SIMD4(260, -895, 170, 290), SIMD4(560, -1060, 150, 270), SIMD4(820, -1330, 90, 240), SIMD4(1000, -1560, 20, 200)]
    private let southRidge: [SIMD4<Float>] = [SIMD4(-3200, 470, 300, 380), SIMD4(-900, 400, 220, 310), SIMD4(-100, 350, 185, 270),
                                               SIMD4(520, 330, 160, 260), SIMD4(1050, 360, 110, 240), SIMD4(1480, 430, 15, 200)]

    // MARK: - Nodes the game changes

    private var terrainMat: SCNMaterial?
    private var water: SCNNode?
    private var waterMat: SCNMaterial?
    private let floatRoot = SCNNode()                  // wreckage floating on the water: y = water level
    private var snowMats: [(SCNMaterial, CGFloat)] = []
    private var townLow: SCNNode?                      // houses below the run-up (swept away)
    private var townHigh: SCNNode?
    private var harborIntact: SCNNode?
    private var centerIntact: SCNNode?
    private var centerShell: SCNNode?
    private var schoolGlass: SCNNode?
    private var schoolShell: SCNNode?
    private var mudLines: [(SCNNode, SCNNode, CGFloat)] = []
    private var yardMat: SCNMaterial?
    private var townWindowMat: SCNMaterial?
    private var townLampMat: SCNMaterial?
    private var haidenRoofNode: SCNNode?
    private var haidenDamage: SCNNode?
    private var lots: [FinaleLot] = []
    private var rubble: SCNNode?
    private var townFires: [FinaleFireSite] = []
    private var hillFires: [FinaleFireSite] = []
    private var fireLights: [SCNNode] = []
    private var townGlowLight: SCNNode?
    private var sosBoards: [SCNNode] = []
    private var sosSwept: SCNNode?
    private var signalFlag: SCNNode?
    private var signalSmoke: SCNNode?
    private var signalSmokePS: SCNParticleSystem?
    private var antenna: SCNNode?
    private var antennaLamp: SCNNode?
    private var antennaDown: SCNNode?
    private var torchBeam: SCNNode?
    private var tarpPoles: SCNNode?
    private var tarpSheet: SCNNode?
    private var tarpRoll: SCNNode?
    private var firebreakStrip: [SCNNode] = []
    private var springPipe: [SCNNode] = []
    private var springWater: SCNNode?
    private var routeMarkers: [SCNNode] = []
    private var trampled: SCNNode?
    private var crowdLayouts: [Int: [SCNNode]] = [:]
    private var ships: [SCNNode] = []
    private var farHeli: SCNNode?
    private var heli: SCNNode?
    private var heliWash: SCNNode?
    private var washPS: SCNParticleSystem?
    private var convoy: [SCNNode] = []
    private var lane: [(SCNNode, SIMD2<Float>)] = []
    private var digger: SCNNode?
    private var sdfCamp: SCNNode?
    private var tideTorch: SCNNode?
    private var noticeBoard: SCNNode?
    private var supplies: [SCNNode] = []
    private lazy var smokeDayDark = smokeControllers(dark: true, night: false)
    private lazy var smokeNightDark = smokeControllers(dark: true, night: true)
    private lazy var smokeDayLight = smokeControllers(dark: false, night: false)
    private lazy var smokeNightLight = smokeControllers(dark: false, night: true)
    private var hillBands: [(SCNNode, SCNNode, Float)] = []      // north slope trees by elevation: green, burnt, lower edge
    private var breakTrees: [(SCNNode, SCNNode)] = []           // trees in the firebreak band, by sector
    private var lowTrees: (SCNNode, SCNNode)?                   // below the run-up: green, stripped
    private var southTrees: (SCNNode, SCNNode)?
    private let breakLo: Float = 16.5, breakHi: Float = 21.0     // the firebreak band on the north slope
    private let breakA0: Float = -2.75, breakA1: Float = -0.25
    private var floatHigh: SCNNode?
    private var floatMid: SCNNode?
    /// Concrete buildings in the town that stand through the wave: council flats, the town office, an inn.
    private lazy var rcBuildings: [FinaleLot] = {
        let defs: [(Float, Float, Float, Float, Float, UInt32)] = [(330, 175, 22, 6.5, 4, 0xD8D2C2), (430, 210, 18, 9, 3, 0xC8C4B8), (120, 40, 14, 7, 3, 0xE0D8C8)]
        return defs.map { d in
            let c = townP(d.0, d.1)
            return FinaleLot(x: c.x, z: c.y, y: gy(c.x, c.y), yaw: townYaw, L: d.2, W: d.3, H: d.4 * 3.4 + 0.6, rise: 0, kind: Int(d.4),
                             wall: finaleLin(d.5), roof: finaleLin(0x8E8C86), seed: 0, big: true)
        }
    }()
    private var rcGlass: [SCNNode] = []
    private var rcShell: [SCNNode] = []

    required init() {
        super.init()
        skyStyle = .none                 // the sky is drawn in updateEnvironment (cheaper night sky, fire glow)
        sunPeak = 47                     // 39°N in mid-March
        sunAzimuth = 296                 // afternoon sun from the WSW, over the hills behind the camera
        exposure = -0.3
        sunScale = 0.95
        iblScale = 1.0
        hazeColor = SK.rgb(0xB9C2CB)
        stormColor = SK.rgb(0x8E959C)
        nightColor = SK.rgb(0x07090D)
        clearVisibility = 3200
        weatherArea = 115
        weatherCenter = SCNVector3(18, 50, -54)
        cameraTarget = SCNVector3(28.6, 24.3, -45.4)
        cameraDistance = 70
        cameraYaw = -30
        cameraPitch = 13
        cameraFOV = 48
        minPitch = 7                     // lower, and the orbit would sink into the hill top
        world.addChildNode(floatRoot)
    }

    // MARK: - Terrain field

    /// x of the coastline at z: the town's quay runs NNE from the hill; south of it the hill spur.
    private func shoreX(_ z: Float) -> Float {
        z <= -60 ? 158 + (-60 - z) * 0.33 : 158 + (z + 60) * 0.45
    }

    private func riverZ(_ x: Float) -> Float { -330 + 26 * sin(x / 210 + 0.5) }

    /// Height of a ridge given as a polyline of (x, z, crest, half width): convex flanks, steep at the foot.
    private func ridge(_ r: [SIMD4<Float>], _ x: Float, _ z: Float) -> Float {
        var best = Float.greatestFiniteMagnitude, bh: Float = 0, bw: Float = 1
        for i in 0..<(r.count - 1) {
            let a = r[i], b = r[i + 1]
            let ex = b.x - a.x, ez = b.y - a.y
            let t = max(0, min(1, ((x - a.x) * ex + (z - a.y) * ez) / (ex * ex + ez * ez)))
            let px = a.x + ex * t - x, pz = a.y + ez * t - z
            let d2 = px * px + pz * pz
            if d2 < best { best = d2; bh = a.z + (b.z - a.z) * t; bw = a.w + (b.w - a.w) * t }
        }
        let d = sqrt(best) / bw
        if d > 1.35 { return -100 }
        var h = bh * (1 - pow(d, 1.5))
        let g = noise.fbm(x / 95 + 3.3, z / 95 - 1.1, octaves: 3)
        h += (g - 0.5) * bh * 0.38 * max(0, 1 - d)
        return h
    }

    /// The stone steps are cut in a straight line down the north-east slope of the hill.
    private func stairCut(_ x: Float, _ z: Float, _ h: Float) -> Float {
        let d = stairB - stairT
        let len = sqrt(d.x * d.x + d.y * d.y)
        let dx = d.x / len, dz = d.y / len
        let px = x - stairT.x, pz = z - stairT.y
        let t = (px * dx + pz * dz) / len
        if t < -0.06 || t > 1.12 { return h }
        let lat = abs(px * dz - pz * dx)
        if lat > 5.5 { return h }
        let line = topY + (stairBY - topY) * max(0, min(1, t)) - 0.12
        let k = 1 - SK.smoothstep(2.0, 5.5, lat)
        return h + (line - h) * k
    }

    private func height(_ x: Float, _ z: Float) -> Float {
        // valley floor: ~0.7 m behind the quay, rising slowly inland and faster up the valley
        var h: Float = 1.25 + 0.003 * max(0, 150 - x) + 0.012 * max(0, -520 - x)
        h += (noise.value(x / 14, z / 14) - 0.5) * 0.25
        // old paddies and hollows near the harbour: the first places to flood again
        let sd = shoreX(z) - x
        if sd < 340 {
            let hollow = noise.value(x / 46 + 3.1, z / 46 - 1.7)
            h -= 1.25 * SK.smoothstep(0.62, 0.74, hollow) * (1 - SK.smoothstep(200, 360, sd))
        }
        // the river between concrete banks
        let dzr = abs(z - riverZ(x))
        if dzr < 11 { h -= 2.7 * (1 - SK.smoothstep(7.2, 8.6, dzr)) }
        // the harbour basin and the bay
        if sd < 0 { h = min(h, -3.2 + 0.03 * sd) }
        if sd >= 0 && sd < 14 { h = min(h, 1.25 + 0.01 * sd) }
        // the shrine hill
        let r = sqrt(x * x + z * z)
        if r < hillR + 12 {
            var hk = topY * (1 - SK.smoothstep(plateauR, hillR, r))
            let rough = SK.smoothstep(plateauR + 3, plateauR + 16, r) * (1 - SK.smoothstep(hillR - 22, hillR + 4, r))
            if rough > 0 { hk += (noise.fbm(x / 21, z / 21, octaves: 3) - 0.5) * 7 * rough }
            hk = stairCut(x, z, hk)
            h = max(h, hk)
        }
        // the saddle behind the hill (the back slope) up to the south ridge
        if z > 0 && z < 330 && x > -150 && x < 160 {
            let sx = abs(x - 6)
            let sdl = 22 * (1 - SK.smoothstep(16, 80, sx)) * SK.smoothstep(18, 72, z)
            h = max(h, sdl + (noise.value(x / 26, z / 26) - 0.5) * 3 * SK.smoothstep(18, 72, z))
        }
        h = max(h, ridge(northRidge, x, z))
        h = max(h, ridge(southRidge, x, z))
        // mountains far inland and behind the ridges (not out at sea)
        let fx = x + 400, fz = z + 250
        let far = sqrt(fx * fx + fz * fz)
        if far > 1250 && x < 1500 {
            let m = SK.smoothstep(1250, 2300, far) * (1 - SK.smoothstep(500, 1500, x))
            if m > 0 { h = max(h, m * (170 + noise.ridged(x / 430, z / 430, octaves: 3) * 360) - 30) }
        }
        return h
    }

    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(height(Float(x), Float(z))) }
    private func gy(_ x: Float, _ z: Float) -> Float { height(x, z) }

    /// Point of the town grid: `a` metres along the coast, `b` metres inland.
    private func townP(_ a: Float, _ b: Float) -> SIMD2<Float> { townO + townU * a + townV * b }

    // MARK: - Materials

    /// Vertex-coloured PBR material that takes snow on its upward faces (`snow` scales the cover).
    private func vc(_ roughness: CGFloat = 0.85, snow: CGFloat = 1, doubleSided: Bool = false, metal: CGFloat = 0) -> SCNMaterial {
        let m = SK.mat(.white, roughness: roughness, metalness: metal, doubleSided: doubleSided)
        if snow > 0 {
            m.shaderModifiers = [.surface: finaleSnowShader]
            m.setValue(NSNumber(value: 0.0), forKey: "snowAmt")
            snowMats.append((m, snow))
        }
        return m
    }

    private func glow(_ c: NSColor, _ k: CGFloat = 2) -> SCNMaterial {
        let m = SK.mat(.black, roughness: 1, emission: c)
        m.emission.intensity = k
        return m
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        buildTerrain()
        buildWater()
        computeLots()
        buildPrecinct()
        buildStairs()
        buildHillTrees()
        buildRidgeTrees()
        buildCenter()
        buildSchool()
        buildRCBuildings()
        buildHarbor()
        buildHighTown()
        buildFires()
        buildSignals()
        buildProjects()
        buildRescue()
        buildDetails()
        addFire(at: SCNVector3(CGFloat(fireXZ.x), CGFloat(topY) + 0.02, CGFloat(fireXZ.y)), scale: 1.05)
    }

    // MARK: Terrain

    /// Graded grid axis: 2.5 m over the hill, 6 m over the town, growing toward the horizon.
    private func axis(_ lo: Float, _ hi: Float, core: ClosedRange<Float>, mid: ClosedRange<Float>) -> [Float] {
        var out: [Float] = []
        var x = lo
        while x < hi {
            out.append(x)
            var step: Float
            if core.contains(x) { step = 2.5 }
            else if mid.contains(x) { step = 6 }
            else {
                let dist = x < mid.lowerBound ? mid.lowerBound - x : x - mid.upperBound
                step = min(170, 6 + dist * 0.08)
            }
            if x < core.lowerBound && x + step > core.lowerBound && mid.contains(x) { step = core.lowerBound - x }
            if x < mid.lowerBound && x + step > mid.lowerBound { step = max(2.5, mid.lowerBound - x) }
            x += step
        }
        out.append(hi)
        return out
    }

    private func buildTerrain() {
        let xs = axis(-3000, 3000, core: -96...96, mid: -560...330)
        let zs = axis(-3000, 3000, core: -96...96, mid: -640...220)
        let nx = xs.count, nz = zs.count
        var hs = [Float](repeating: 0, count: nx * nz)
        for j in 0..<nz {
            let z = zs[j]
            for i in 0..<nx { hs[j * nx + i] = height(xs[i], z) }
        }
        var pts: [FinaleV3] = [], nrm: [FinaleV3] = [], cols: [FinaleV3] = []
        pts.reserveCapacity(nx * nz); nrm.reserveCapacity(nx * nz); cols.reserveCapacity(nx * nz)
        let sea = finaleLin(0x2E3330), rock = finaleLin(0x5F5B54), grass = finaleLin(0x7B7356), earth = finaleLin(0x6A6252)
        let cedar = finaleLin(0x26341F), cedar2 = finaleLin(0x34452A), bare = finaleLin(0x5E5446), gravel = finaleLin(0x8C877C)
        let stone = finaleLin(0x8A8780), paved = finaleLin(0x7E7C76), earthP = finaleLin(0x5E574C)
        for j in 0..<nz {
            let z = zs[j]
            let j0 = max(0, j - 1), j1 = min(nz - 1, j + 1)
            for i in 0..<nx {
                let x = xs[i]
                let i0 = max(0, i - 1), i1 = min(nx - 1, i + 1)
                let h = hs[j * nx + i]
                let dhx = (hs[j * nx + i1] - hs[j * nx + i0]) / max(0.01, xs[i1] - xs[i0])
                let dhz = (hs[j1 * nx + i] - hs[j0 * nx + i]) / max(0.01, zs[j1] - zs[j0])
                var n = FinaleV3(-dhx, 1, -dhz)
                n /= sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
                pts.append(FinaleV3(x, h, z))
                nrm.append(n)
                let slope = 1 - n.y
                let n1 = noise.value(x / 9, z / 9), n2 = noise.value(x / 37 + 7, z / 37 - 2)
                var c: FinaleV3
                let r = sqrt(x * x + z * z)
                if h < -1.4 {
                    c = sea
                } else if r < plateauR + 1.5 && h > topY - 0.6 {
                    let worn = noise.value(x / 5 + 2, z / 5 - 3)
                    c = SK.mix(gravel, earthP, SK.smoothstep(0.55, 0.8, worn) * 0.7 + SK.smoothstep(plateauR - 4, plateauR + 1, r) * 0.6) * (0.9 + 0.15 * n1)
                } else if slope > 0.55 {
                    c = SK.mix(rock, cedar, n2 * 0.6)
                } else if h < 9 && slope < 0.12 {
                    c = SK.mix(grass, earth, n1) * (0.9 + 0.15 * n2)
                    if x < shoreX(z) - 5 && x > -620 && z < 120 && z > -640 {
                        // inside the town: yards, car parks and lanes, more concrete than grass
                        c = SK.mix(c, paved * (0.9 + 0.2 * n1), SK.smoothstep(0.35, 0.6, n2) * 0.8 + 0.15)
                    }
                    if h < 0.5 { c = SK.mix(c, earth * 0.8, 0.5) }
                } else {
                    c = SK.mix(cedar, cedar2, n1)
                    c = SK.mix(c, bare, SK.smoothstep(0.62, 0.8, n2) * 0.8)
                    c *= 0.85 + 0.3 * noise.value(x / 4, z / 4)
                }
                // stone of the steps' cutting
                let sd = stairB - stairT
                let sl = sqrt(sd.x * sd.x + sd.y * sd.y)
                let px = x - stairT.x, pz = z - stairT.y
                let t = (px * sd.x + pz * sd.y) / (sl * sl)
                if t > -0.02 && t < 1.05 && abs(px * sd.y / sl - pz * sd.x / sl) < 3.2 { c = stone }
                cols.append(c)
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity((nx - 1) * (nz - 1) * 6)
        for j in 0..<(nz - 1) {
            for i in 0..<(nx - 1) {
                let a = UInt32(j * nx + i), b = a + 1, c = a + UInt32(nx), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let g = finaleGeometry(pts, cols, nil, idx, normals: nrm)
        let m = SK.mat(.white, roughness: 0.92)
        m.shaderModifiers = [.surface: finaleTerrainShader]
        m.setValue(NSNumber(value: 0.0), forKey: "wreck")
        m.setValue(NSNumber(value: Double(runup)), forKey: "runup")
        m.setValue(NSNumber(value: 0.0), forKey: "snowAmt")
        m.setValue(NSNumber(value: -100.0), forKey: "burnY")
        m.setValue(NSNumber(value: 0.0), forKey: "wet")
        g.materials = [m]
        terrainMat = m
        let t = SCNNode(geometry: g)
        t.castsShadow = false
        t.name = "terrain"
        world.addChildNode(t)
    }

    // MARK: Water

    private func buildWater() {
        let size: CGFloat = 9000
        let plane = SCNPlane(width: size, height: size)
        plane.widthSegmentCount = 140
        plane.heightSegmentCount = 140
        let m = SK.mat(.white, roughness: 0.16, metalness: 0.0)
        m.diffuse.contents = FinaleTex.silt()
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(size / 60, size / 60, 1)
        m.normal.contents = SK.normalNoiseImage(size: 128, scale: 6, strength: 3, seed: 99)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.normal.mipFilter = .linear
        m.normal.maxAnisotropy = 16
        m.normal.contentsTransform = SCNMatrix4MakeScale(size / 7, size / 7, 1)
        m.normal.intensity = 0.45
        m.shaderModifiers = [.geometry: finaleWaveShader, .surface: finaleWaterShader]
        m.setValue(NSNumber(value: 0.06), forKey: "amplitude")
        m.setValue(NSNumber(value: 0.5), forKey: "choppiness")
        m.setValue(NSNumber(value: 0.0), forKey: "murk")
        m.setValue(NSNumber(value: 0.0), forKey: "puddle")
        m.setValue(NSValue(scnVector4: SK.linear(SK.rgb(0x2C3E44))), forKey: "seaCol")
        m.setValue(NSValue(scnVector4: SK.linear(SK.rgb(0x2E2820))), forKey: "mudCol")
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(400, CGFloat(seaY), -300)
        n.castsShadow = false
        n.name = "water"
        world.addChildNode(n)
        water = n
        waterMat = m
    }

    // MARK: The precinct (境内)

    private func buildPrecinct() {
        let T = topY
        var wood = FinaleMesh(), roof = FinaleMesh(), stoneM = FinaleMesh(), paint = FinaleMesh(), misc = FinaleMesh()
        let darkWood = finaleLin(0x5A4230), wallWood = finaleLin(0x6E5238), plaster = finaleLin(0xD9D3C4)
        let copper = finaleLin(0x5C8573), tileGrey = finaleLin(0x3C4046), granite = finaleLin(0x8F8B82)
        let vermilion = finaleLin(0xB8432C), black = finaleLin(0x1C1B1A)

        // 拝殿 (worship hall) in the north-west of the precinct, facing ESE over the fire; 本殿 behind it
        let hc = FinaleV3(hallXZ.x, T, hallXZ.y), hyaw = hallYaw
        func H(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { hc + finaleRot(FinaleV3(x, y, z), yaw: hyaw) }
        stoneM.box(H(0, 0.22, 0), FinaleV3(4.2, 0.24, 5.2), granite, yaw: hyaw)
        wood.box(H(0, 0.95, 0), FinaleV3(3.9, 0.08, 4.9), darkWood, yaw: hyaw)
        for x in [Float(-3.0), 3.0] {
            for z in [Float(-4.0), -1.35, 1.35, 4.0] { wood.tube(H(x, 1.0, z), H(x, 4.25, z), 0.15, 0.14, darkWood, segs: 6) }
        }
        wood.box(H(-0.2, 2.65, 0), FinaleV3(2.75, 1.6, 3.85), wallWood, yaw: hyaw)
        wood.box(H(0, 4.15, 0), FinaleV3(3.05, 0.14, 4.05), darkWood, yaw: hyaw)
        // the front: lattice doors, plaster above
        wood.box(H(2.58, 2.25, 0), FinaleV3(0.04, 1.2, 2.55), finaleLin(0x3E2E22), yaw: hyaw)
        for k in 0..<9 { wood.box(H(2.63, 2.25, -2.4 + Float(k) * 0.6), FinaleV3(0.025, 1.2, 0.025), finaleLin(0x8A6A4A), yaw: hyaw) }
        for k in 0..<4 { wood.box(H(2.63, 1.3 + Float(k) * 0.65, 0), FinaleV3(0.025, 0.025, 2.55), finaleLin(0x8A6A4A), yaw: hyaw) }
        misc.box(H(2.6, 3.75, 0), FinaleV3(0.04, 0.3, 3.9), plaster, yaw: hyaw)
        for k in 0..<4 { wood.box(H(4.15 + Float(k) * 0.3, 0.88 - Float(k) * 0.22, 0), FinaleV3(0.16, 0.08, 1.3), darkWood, yaw: hyaw) }
        // the roof: hip-and-gable look, copper gone green, ridge along the facade
        roof.hipRoof(H(0, 4.3, 0), halfL: 4.0, halfW: 3.05, rise: 3.5, over: 1.55, yaw: hyaw + .pi / 2, ridgeK: 0.72, copper)
        roof.box(H(0, 7.86, 0), FinaleV3(0.24, 0.16, 3.0), finaleLin(0x3E5E52), yaw: hyaw)
        for z in [Float(-2.95), 2.95] {
            if z > 0 { roof.tri(H(-1.1, 6.6, z), H(1.1, 6.6, z), H(0, 7.8, z), finaleLin(0x4A3628)) }
            else { roof.tri(H(1.1, 6.6, z), H(-1.1, 6.6, z), H(0, 7.8, z), finaleLin(0x4A3628)) }
        }
        roof.hipRoof(H(4.3, 3.65, 0), halfL: 1.6, halfW: 1.4, rise: 0.9, over: 0.5, yaw: hyaw + .pi / 2, ridgeK: 0.9, copper)
        for z in [Float(-1.3), 1.3] { wood.tube(H(5.15, 0.2, z), H(5.15, 3.65, z), 0.11, 0.1, darkWood, segs: 6) }
        misc.rope(H(3.15, 3.35, -2.0), H(3.15, 3.35, 2.0), sag: 0.32, r: 0.1, finaleLin(0xC6B07A))
        for k in 0..<4 { misc.box(H(3.2, 2.95, -1.2 + Float(k) * 0.8), FinaleV3(0.01, 0.16, 0.05), finaleLin(0xEDEBE4), yaw: hyaw) }
        misc.tube(H(3.4, 3.2, 0), H(3.4, 1.45, 0), 0.035, 0.035, finaleLin(0xC9322A), segs: 5)
        misc.blob(H(3.4, 3.28, 0), FinaleV3(0.12, 0.12, 0.12), finaleLin(0xC8A040), noise, seed: 2, jitter: 0, rings: 4, segs: 7)
        wood.box(H(3.45, 1.32, 0), FinaleV3(0.36, 0.3, 0.75), finaleLin(0x6A4A32), yaw: hyaw)
        stoneM.box(H(-6.4, 0.45, 0), FinaleV3(2.4, 0.46, 2.4), granite, yaw: hyaw)
        wood.box(H(-6.4, 2.3, 0), FinaleV3(1.75, 1.4, 1.75), wallWood, yaw: hyaw)
        roof.hipRoof(H(-6.4, 3.75, 0), halfL: 1.9, halfW: 1.75, rise: 2.2, over: 0.9, yaw: hyaw, ridgeK: 0.8, copper)
        wood.box(H(-3.9, 2.1, 0), FinaleV3(0.95, 1.1, 1.05), wallWood, yaw: hyaw)
        roof.box(H(-3.9, 3.35, 0), FinaleV3(1.0, 0.12, 1.3), copper * 0.85, yaw: hyaw)

        // 社务所 (shrine office) on the south-east side, glass doors toward the fire
        let oc = FinaleV3(officeXZ.x, T, officeXZ.y), oyaw: Float = .pi
        func O(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { oc + finaleRot(FinaleV3(x, y, z), yaw: oyaw) }
        stoneM.box(O(0, 0.15, 0), FinaleV3(2.8, 0.18, 4.3), granite, yaw: oyaw)
        wood.box(O(0, 1.6, 0), FinaleV3(2.5, 1.35, 4.0), plaster, yaw: oyaw)
        wood.box(O(0, 0.55, 0), FinaleV3(2.53, 0.4, 4.03), darkWood, yaw: oyaw)
        for k in 0..<3 { misc.box(O(2.52, 1.55, -2.6 + Float(k) * 2.6), FinaleV3(0.03, 0.85, 1.05), finaleLin(0x26303A), yaw: oyaw) }
        var offRoof = FinaleMesh()
        offRoof.gableRoof(O(0, 2.95, 0), halfL: 4.0, halfW: 2.5, rise: 1.6, over: 0.7, yaw: oyaw + .pi / 2, tileGrey, gable: plaster, walls: &wood)

        // 防灾仓库: the town's disaster store, a cream sheet-steel shed near the steps
        let wx = storeXZ.x, wz = storeXZ.y
        func W(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { FinaleV3(wx + x, T + y, wz + z) }
        let steelC = finaleLin(0xD3CBAE)
        misc.box(W(0, 1.35, 0), FinaleV3(1.6, 1.35, 2.4), steelC)
        for k in 0..<13 {
            let z = -2.3 + Float(k) * 0.383
            misc.box(W(1.62, 1.33, z), FinaleV3(0.02, 1.3, 0.04), steelC * 0.86)
            misc.box(W(-1.62, 1.33, z), FinaleV3(0.02, 1.3, 0.04), steelC * 0.86)
        }
        misc.box(W(-1.63, 1.05, 0.2), FinaleV3(0.03, 1.0, 0.85), finaleLin(0x9A947E))
        misc.box(W(0, 2.78, 0), FinaleV3(1.8, 0.07, 2.6), finaleLin(0x8A3A30))
        misc.box(W(-1.66, 2.3, 0.2), FinaleV3(0.02, 0.22, 0.75), finaleLin(0xF2F0EA))

        // 手水舍: the purification fountain by the approach
        let cx = fountainXZ.x, cz = fountainXZ.y
        func C(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { FinaleV3(cx + x, T + y, cz + z) }
        for (x, z) in [(Float(-1.0), Float(-0.7)), (1.0, -0.7), (-1.0, 0.7), (1.0, 0.7)] { wood.tube(C(x, 0, z), C(x, 2.3, z), 0.08, 0.08, darkWood, segs: 5) }
        var chozuRoof = FinaleMesh()
        chozuRoof.gableRoof(C(0, 2.3, 0), halfL: 1.1, halfW: 0.75, rise: 0.75, over: 0.45, yaw: 0, tileGrey, gable: darkWood, walls: &wood)
        stoneM.box(C(0, 0.4, 0), FinaleV3(0.75, 0.4, 0.35), granite)
        misc.box(C(0, 0.81, 0), FinaleV3(0.65, 0.012, 0.26), finaleLin(0x40565C))
        misc.tube(C(-1.2, 1.0, 0.1), C(-0.4, 0.95, 0.05), 0.04, 0.04, finaleLin(0x9AA060), segs: 5)

        // the approach (参道): flagstones from the torii to the hall, stone lanterns, guardian dogs
        let dir = stairDir
        let a0 = FinaleV3(stairT.x - dir.x * 2.4, T, stairT.y - dir.y * 2.4), a1 = H(5.0, 0, 0)
        let ayaw = atan2(a1.x - a0.x, a1.z - a0.z)
        let steps = 24
        for k in 0..<steps {
            let t = Float(k) / Float(steps - 1)
            let p = a0 + (a1 - a0) * t
            stoneM.box(FinaleV3(p.x, T + 0.03, p.z), FinaleV3(0.62, 0.03, 0.62), granite * (0.92 + 0.05 * Float(k % 3)), yaw: ayaw)
        }
        let ad = simd_normalize(SIMD2<Float>(a1.x - a0.x, a1.z - a0.z))
        for t in [Float(0.2), 0.48, 0.76] {
            let p = a0 + (a1 - a0) * t
            for sgn in [Float(-1), 1] { lantern(&stoneM, FinaleV3(p.x + ad.y * 2.0 * sgn, T, p.z - ad.x * 2.0 * sgn), granite) }
        }
        for sgn in [Float(-1), 1] {
            let q = H(5.6, 0, 2.6 * sgn)
            stoneM.box(q + FinaleV3(0, 0.45, 0), FinaleV3(0.45, 0.45, 0.4), granite, yaw: hyaw)
            stoneM.blob(q + FinaleV3(0, 1.15, 0), FinaleV3(0.32, 0.36, 0.26), granite * 0.95, noise, seed: sgn, jitter: 0.12, rings: 4, segs: 7)
            stoneM.blob(q + FinaleV3(0.12, 1.6, 0), FinaleV3(0.2, 0.2, 0.2), granite, noise, seed: sgn + 3, jitter: 0.1, rings: 4, segs: 6)
        }
        // the torii at the head of the steps
        torii(&paint, &misc, base: FinaleV3(stairT.x - dir.x * 1.3, T, stairT.y - dir.y * 1.3), dirX: dir.x, dirZ: dir.y, height: 4.7, span: 4.4, col: vermilion, cap: black)
        // stone posts and a rope along the north edge, where people stand and look down at the town
        var prevPost: FinaleV3? = nil
        for k in 0..<15 {
            let a = Float(-2.2) + Float(k) * 0.115
            let q = FinaleV3(sin(a) * (plateauR - 0.8), T, cos(a) * (plateauR - 0.8))
            stoneM.box(q + FinaleV3(0, 0.42, 0), FinaleV3(0.12, 0.42, 0.12), granite)
            if let p = prevPost { misc.rope(p + FinaleV3(0, 0.75, 0), q + FinaleV3(0, 0.75, 0), sag: 0.12, r: 0.025, finaleLin(0x6A5E4A), segs: 3, sides: 3) }
            prevPost = q
        }
        world.addChildNode(wood.node(vc(0.8)))
        let roofMat = vc(0.55, metal: 0.25)
        let rn = roof.node(roofMat)
        rn.name = "haidenRoof"
        world.addChildNode(rn)
        haidenRoofNode = rn
        world.addChildNode(offRoof.node(vc(0.6)))
        world.addChildNode(chozuRoof.node(vc(0.6)))
        world.addChildNode(stoneM.node(vc(0.9)))
        world.addChildNode(paint.node(vc(0.6)))
        world.addChildNode(misc.node(vc(0.7)))
        // the damaged roof (low shelter integrity): torn copper sheets lying about, a tarp patch
        var dmg = FinaleMesh()
        var rng = FinaleRng(91)
        for _ in 0..<9 {
            let q = H(rng.r(-6, 7), 0.04, rng.r(-6, 6))
            dmg.box(q, FinaleV3(rng.r(0.3, 0.7), 0.02, rng.r(0.2, 0.5)), copper * rng.r(0.8, 1.0), yaw: rng.r(0, 3), roll: rng.r(-0.2, 0.2))
        }
        // holes torn in the copper roof (just above its slopes: ridge 7.8 m, eaves 4.3 m at |x| = 3.05)
        func rs(_ x: Float) -> Float { 4.3 + 3.5 * (1 - min(1, abs(x) / 3.05)) + 0.06 }
        dmg.quad(H(0.6, rs(0.6), 0.2), H(0.5, rs(0.5), 1.7), H(2.0, rs(2.0), 1.6), H(2.2, rs(2.2), 0.0), finaleLin(0x1C1C1E))
        dmg.quad(H(-2.4, rs(-2.4), -1.4), H(-2.5, rs(-2.5), 0.0), H(-1.0, rs(-1.0), -0.2), H(-0.9, rs(-0.9), -1.6), finaleLin(0x1C1C1E))
        dmg.quad(H(1.0, rs(1.0), -1.7), H(1.1, rs(1.1), -0.8), H(2.3, rs(2.3), -0.7), H(2.4, rs(2.4), -1.5), finaleLin(0x2A2420))
        let dn = dmg.node(vc(0.9))
        dn.isHidden = true
        world.addChildNode(dn)
        haidenDamage = dn

        // 防災倉庫 written on the store's sign
        let text = SCNText(string: "防災倉庫", extrusionDepth: 0)
        text.font = NSFont(name: "HiraginoSans-W6", size: 10) ?? NSFont.boldSystemFont(ofSize: 10)
        text.flatness = 0.3
        text.firstMaterial = SK.mat(SK.rgb(0xB01E1E), roughness: 0.9, doubleSided: true)
        let tn = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        let k: CGFloat = 0.05
        tn.scale = SCNVector3(k, k, k)
        tn.eulerAngles.y = -.pi / 2
        tn.position = SCNVector3(CGFloat(wx) - 1.69, CGFloat(T) + 2.3 - (mn.y + mx.y) / 2 * k, CGFloat(wz) + 0.2 - (mn.x + mx.x) / 2 * k)
        world.addChildNode(tn)
    }

    private func lantern(_ m: inout FinaleMesh, _ q: FinaleV3, _ col: FinaleV3) {
        m.box(q + FinaleV3(0, 0.15, 0), FinaleV3(0.32, 0.15, 0.32), col)
        m.tube(q + FinaleV3(0, 0.3, 0), q + FinaleV3(0, 1.15, 0), 0.12, 0.1, col, segs: 6)
        m.box(q + FinaleV3(0, 1.22, 0), FinaleV3(0.26, 0.07, 0.26), col)
        m.box(q + FinaleV3(0, 1.48, 0), FinaleV3(0.2, 0.19, 0.2), col * 0.9)
        m.cone(q + FinaleV3(0, 1.67, 0), 0.42, 0.34, col, segs: 4)
        m.blob(q + FinaleV3(0, 2.05, 0), FinaleV3(0.07, 0.09, 0.07), col, noise, seed: 1, jitter: 0, rings: 3, segs: 5)
    }

    private func torii(_ m: inout FinaleMesh, _ caps: inout FinaleMesh, base: FinaleV3, dirX: Float, dirZ: Float, height: Float, span: Float, col: FinaleV3, cap: FinaleV3) {
        let lx = -dirZ, lz = dirX                 // across the path
        let yaw = atan2(lx, lz) + .pi / 2         // local x across the path
        for sgn in [Float(-1), 1] {
            let p = base + FinaleV3(lx * span / 2 * sgn, 0, lz * span / 2 * sgn)
            m.tube(p, p + FinaleV3(lx * -0.12 * sgn, height, lz * -0.12 * sgn), 0.24, 0.2, col, segs: 8)
            caps.tube(p, p + FinaleV3(0, 0.35, 0), 0.29, 0.29, cap, segs: 8)
        }
        let top = base + FinaleV3(0, height, 0)
        m.box(top + FinaleV3(0, -0.85, 0), FinaleV3(span / 2 + 0.55, 0.15, 0.13), col, yaw: yaw)                // 貫
        m.box(top + FinaleV3(0, -0.35, 0), FinaleV3(0.16, 0.35, 0.12), col, yaw: yaw)                          // 額束
        m.box(top + FinaleV3(0, 0.1, 0), FinaleV3(span / 2 + 0.95, 0.16, 0.24), col, yaw: yaw)                 // 島木
        caps.box(top + FinaleV3(0, 0.36, 0), FinaleV3(span / 2 + 1.15, 0.13, 0.3), cap, yaw: yaw)             // 笠木
        for sgn in [Float(-1), 1] {
            let e = top + FinaleV3(lx * (span / 2 + 1.25) * sgn, 0.5, lz * (span / 2 + 1.25) * sgn)
            caps.box(e, FinaleV3(0.35, 0.1, 0.3), cap, yaw: yaw, roll: 0.3 * sgn)
        }
    }

    // MARK: The stone steps

    private func buildStairs() {
        var m = FinaleMesh(), rail = FinaleMesh()
        let sdx = stairB.x - stairT.x, sdz = stairB.y - stairT.y
        let L = sqrt(sdx * sdx + sdz * sdz)
        let dx = sdx / L, dz = sdz / L
        let lx = -dz, lz = dx
        let rise: Float = 0.18
        let n = Int(((topY - stairBY) / rise).rounded())
        let run = L / Float(n)
        let hw: Float = 1.35
        let stone = finaleLin(0x928E85)
        var rng = FinaleRng(5)
        for k in 0..<n {
            let s0 = Float(k) * run, s1 = s0 + run
            let y0 = topY - Float(k) * rise, y1 = y0 - rise
            let c0 = FinaleV3(stairT.x + dx * s0, 0, stairT.y + dz * s0), c1 = FinaleV3(stairT.x + dx * s1, 0, stairT.y + dz * s1)
            let side = FinaleV3(lx * hw, 0, lz * hw)
            let col = stone * rng.r(0.85, 1.08)
            // riser, then the tread below it
            m.quad(c0 - side + FinaleV3(0, y1, 0), c0 + side + FinaleV3(0, y1, 0), c0 + side + FinaleV3(0, y0, 0), c0 - side + FinaleV3(0, y0, 0), col * 0.8)
            m.quad(c0 - side + FinaleV3(0, y1, 0), c1 - side + FinaleV3(0, y1, 0), c1 + side + FinaleV3(0, y1, 0), c0 + side + FinaleV3(0, y1, 0), col)
        }
        // granite kerbs both sides, a handrail down the middle
        for sgn in [Float(-1), 1] {
            let o = FinaleV3(lx * (hw + 0.14) * sgn, 0, lz * (hw + 0.14) * sgn)
            let a = FinaleV3(stairT.x, topY + 0.18, stairT.y) + o, b = FinaleV3(stairB.x, stairBY + 0.18, stairB.y) + o
            m.tube(a, b, 0.17, 0.17, stone * 0.9, segs: 4)
        }
        let railC = finaleLin(0xA8382C)
        var s: Float = 0
        while s <= L {
            let p = FinaleV3(stairT.x + dx * s, topY - (topY - stairBY) * s / L, stairT.y + dz * s)
            rail.tube(p, p + FinaleV3(0, 0.9, 0), 0.03, 0.03, railC, segs: 4)
            s += 3.4
        }
        rail.tube(FinaleV3(stairT.x, topY + 0.9, stairT.y), FinaleV3(stairB.x, stairBY + 0.9, stairB.y), 0.035, 0.035, railC, segs: 4)
        world.addChildNode(m.node(vc(0.9)))
        world.addChildNode(rail.node(vc(0.5, snow: 0.3), shadow: false))
        // the stone torii at the foot
        var t = FinaleMesh(), tc = FinaleMesh()
        torii(&t, &tc, base: FinaleV3(stairB.x + dx * 1.5, stairBY - 0.1, stairB.y + dz * 1.5), dirX: dx, dirZ: dz, height: 4.1, span: 3.6, col: finaleLin(0x9C988E), cap: finaleLin(0x8E8A80))
        world.addChildNode(t.node(vc(0.9)))
        world.addChildNode(tc.node(vc(0.9)))
    }

    // MARK: Trees

    private func cedar(_ m: inout FinaleMesh, _ wood: inout FinaleMesh, _ b: FinaleV3, h: Float, seed: Float, col: FinaleV3? = nil) {
        let g = col ?? finaleLin(0x24331D) * (0.85 + 0.3 * noise.value(seed * 1.3, 2))
        wood.tube(b - FinaleV3(0, 0.5, 0), b + FinaleV3(0, h * 0.5, 0), h * 0.018, h * 0.012, finaleLin(0x4A3A2C), segs: 4)
        let r = h * 0.17
        m.cone(b + FinaleV3(0, h * 0.22, 0), r, h * 0.5, g, segs: 7)
        m.cone(b + FinaleV3(0, h * 0.45, 0), r * 0.8, h * 0.42, g * 1.08, segs: 7)
        m.cone(b + FinaleV3(0, h * 0.66, 0), r * 0.55, h * 0.36, g * 1.15, segs: 6)
    }

    private func broadleaf(_ m: inout FinaleMesh, _ wood: inout FinaleMesh, _ b: FinaleV3, h: Float, seed: Float, bareTree: Bool) {
        wood.tube(b - FinaleV3(0, 0.3, 0), b + FinaleV3(0, h * 0.55, 0), h * 0.03, h * 0.018, finaleLin(0x4E4438), segs: 4)
        let col = bareTree ? finaleLin(0x6A5E50) : finaleLin(0x34432A)
        m.blob(b + FinaleV3(0, h * 0.62, 0), FinaleV3(h * 0.32, h * 0.3, h * 0.32), col, noise, seed: seed, jitter: 0.3, rings: 4, segs: 7, under: 0.6, vary: 0.3)
    }

    /// The hill's own woods: cedars on the steep sides, low growth on the north slope under the
    /// precinct (so the view stays open), a few great cedars in the precinct.
    private func buildHillTrees() {
        // groups: north side by elevation band (fire), the firebreak band by sector, below the run-up
        // (stripped by the wave), the south side; each with a green and a burnt (or dead) version
        let bands: [Float] = [runup, breakLo, breakHi, 25.5, 40]
        var green = [FinaleMesh](repeating: FinaleMesh(), count: 4), burnt = [FinaleMesh](repeating: FinaleMesh(), count: 4)
        var gWood = [FinaleMesh](repeating: FinaleMesh(), count: 4)
        var brk = [FinaleMesh](repeating: FinaleMesh(), count: 8), brkBurnt = [FinaleMesh](repeating: FinaleMesh(), count: 8)
        var brkWood = [FinaleMesh](repeating: FinaleMesh(), count: 8)
        var low = FinaleMesh(), lowWood = FinaleMesh(), dead = FinaleMesh()
        var south = FinaleMesh(), southWood = FinaleMesh(), southBurnt = FinaleMesh()
        var rng = FinaleRng(23)
        let sdx = stairB.x - stairT.x, sdz = stairB.y - stairT.y
        let sl = sqrt(sdx * sdx + sdz * sdz)
        var x: Float = -100
        while x < 100 {
            var z: Float = -100
            while z < 100 {
                let px = x + rng.r(-2, 2), pz = z + rng.r(-2, 2)
                z += 5.0
                let r = sqrt(px * px + pz * pz)
                if r < plateauR + 2.5 || r > hillR + 4 { continue }
                let qx = px - stairT.x, qz = pz - stairT.y
                let t = (qx * sdx + qz * sdz) / (sl * sl)
                if t > -0.1 && t < 1.15 && abs(qx * sdz / sl - qz * sdx / sl) < 4.5 { continue }
                let b = gy(px, pz)
                if b < 1.8 { continue }
                // keep the view from the precinct down the steps to the street and the centre open
                let vx = px + 5.5, vz = pz - 13.7
                let bearing = atan2(vx, -vz) * 180 / .pi
                if bearing > 35 && bearing < 48 && vx * vx + vz * vz < 150 * 150 { continue }
                let seed = px * 0.37 + pz
                let north = pz < 12
                // the slope under the precinct facing the camera's view is kept low, so the view stays open
                let viewSide = pz < -6 && px > -34
                let maxH: Float = viewSide ? max(3, topY - 3 - b) : 40
                let isCedar = viewSide ? (rng.next() < 0.45 && b < topY - 14) : rng.next() < 0.78
                let h = isCedar ? min(maxH, rng.r(viewSide ? 9 : 16, viewSide ? 16 : 27)) : min(maxH, rng.r(viewSide ? 4 : 7, viewSide ? 9 : 12))
                let bareT = rng.next() < 0.55
                let p = FinaleV3(px, b, pz)
                if b < runup - 0.5 {
                    if isCedar { cedar(&low, &lowWood, p, h: h, seed: seed) } else { broadleaf(&low, &lowWood, p, h: h, seed: seed, bareTree: bareT) }
                    // what the wave left: snapped grey trunks, many pushed over, a few still with brown needles
                    let roll = rng.next()
                    if roll < 0.45 {
                        let lean = roll < 0.2 ? rng.r(1.1, 1.5) : rng.r(0, 0.25)
                        let a = rng.r(0, 6.28)
                        let hh = h * rng.r(0.2, 0.55)
                        let top = p + FinaleV3(sin(lean) * cos(a), cos(lean), sin(lean) * sin(a)) * hh
                        dead.tube(p - FinaleV3(0, 0.3, 0), top, h * 0.025, h * 0.016, finaleLin(0x6E6458) * rng.r(0.8, 1.1), segs: 5)
                        if roll > 0.36 { dead.cone(top - FinaleV3(0, hh * 0.3, 0), h * 0.09, hh * 0.45, finaleLin(0x6A4A2E), segs: 5) }
                    }
                    continue
                }
                if !north {
                    if isCedar { cedar(&south, &southWood, p, h: h, seed: seed) } else { broadleaf(&south, &southWood, p, h: h, seed: seed, bareTree: bareT) }
                    burntTree(&southBurnt, p, h: h)
                    continue
                }
                if b >= breakLo && b < breakHi {
                    let ang = atan2(pz, px)
                    let sec = max(0, min(7, Int((ang - breakA0) / (breakA1 - breakA0) * 8)))
                    if ang >= breakA0 && ang <= breakA1 {
                        if isCedar { cedar(&brk[sec], &brkWood[sec], p, h: h, seed: seed) } else { broadleaf(&brk[sec], &brkWood[sec], p, h: h, seed: seed, bareTree: bareT) }
                        burntTree(&brkBurnt[sec], p, h: h)
                        continue
                    }
                }
                var band = 0
                while band < 3 && b >= bands[band + 1] { band += 1 }
                if isCedar { cedar(&green[band], &gWood[band], p, h: h, seed: seed) } else { broadleaf(&green[band], &gWood[band], p, h: h, seed: seed, bareTree: bareT) }
                burntTree(&burnt[band], p, h: h)
            }
            x += 5.0
        }
        // great old cedars in the precinct (to the west and south, out of the view)
        for (px, pz, h) in [(Float(-21), Float(4), Float(30)), (-18.5, -15, 28), (-15, 17, 27), (22, 9, 26), (8, 22, 24), (-21.5, 11, 25)] {
            cedar(&south, &southWood, FinaleV3(px, topY - 0.2, pz), h: h, seed: px)
            burntTree(&southBurnt, FinaleV3(px, topY - 0.2, pz), h: h)
        }
        let crownMat = vc(0.95, snow: 0.8), woodMat = vc(0.95, snow: 0), burntMat = vc(0.95, snow: 0.6)
        func pair(_ g: FinaleMesh, _ w: FinaleMesh, _ b: FinaleMesh) -> (SCNNode, SCNNode) {
            let gn = SCNNode()
            gn.addChildNode(g.node(crownMat))
            if !w.idx.isEmpty { gn.addChildNode(w.node(woodMat)) }
            let bn = b.node(burntMat)
            bn.isHidden = true
            world.addChildNode(gn)
            world.addChildNode(bn)
            return (gn, bn)
        }
        for k in 0..<4 {
            let (g, b) = pair(green[k], gWood[k], burnt[k])
            hillBands.append((g, b, bands[k]))
        }
        for k in 0..<8 {
            let (g, b) = pair(brk[k], brkWood[k], brkBurnt[k])
            breakTrees.append((g, b))
        }
        let (lg, ld) = pair(low, lowWood, dead)
        lowTrees = (lg, ld)
        let (sg, sb) = pair(south, southWood, southBurnt)
        southTrees = (sg, sb)
    }

    private func burntTree(_ m: inout FinaleMesh, _ b: FinaleV3, h: Float) {
        let k = h * 0.72
        m.tube(b - FinaleV3(0, 0.4, 0), b + FinaleV3(0, k, 0), h * 0.022, h * 0.008, finaleLin(0x151311), segs: 4)
        let s = b.x * 3.1 + b.z
        for j in 0..<3 {
            let y = k * (0.45 + 0.17 * Float(j)), a = s + Float(j) * 2.2, l = h * (0.12 - 0.025 * Float(j))
            m.tube(b + FinaleV3(0, y, 0), b + FinaleV3(cos(a) * l, y + l * 0.35, sin(a) * l), h * 0.008, h * 0.004, finaleLin(0x1A1714), segs: 3)
        }
    }

    /// Cedar forest on the ridges and headlands, thinned with distance.
    private func buildRidgeTrees() {
        var m = FinaleMesh()
        var rng = FinaleRng(29)
        var placed = 0
        for _ in 0..<5200 {
            let x = rng.r(-900, 1100), z = rng.r(-1500, 650)
            let r = sqrt(x * x + z * z)
            if r < hillR + 10 { continue }
            let h = gy(x, z)
            if h < runup + 1 || h > 260 { continue }
            // only on slopes facing the town and the bay, sparser far away
            let d = sqrt((x - 40) * (x - 40) + (z + 300) * (z + 300))
            if rng.next() > 1.3 - d / 1200 { continue }
            let th = rng.r(10, 20)
            let g = finaleLin(0x25331E) * rng.r(0.75, 1.2)
            m.cone(FinaleV3(x, h - 1, z), th * 0.22, th, g, segs: 5)
            placed += 1
        }
        _ = placed
        world.addChildNode(m.node(vc(0.95, snow: 0.7), shadow: false))
    }

    // MARK: Town lots

    /// Every house plot of the town (same for the intact town and the foundations left after it).
    private func computeLots() {
        var rng = FinaleRng(17)
        var out: [FinaleLot] = []
        let wallCols: [UInt32] = [0xC9BEA8, 0xD8D5CC, 0xB8B5AC, 0xD3C6A4, 0x7A5E46, 0x9EA6AA, 0xC4B49A, 0xE0DCD2]
        let roofCols: [UInt32] = [0x454B53, 0x30333A, 0x3A4048, 0x7A3E2E, 0x8C4A36, 0x3E5A78, 0x8A3A30, 0x4E6A54, 0x5E4E40]
        for ia in 0..<56 {
            let a0 = Float(ia) * 11.5 + Float(ia / 4) * 6 + 6
            for ib in 0..<36 {
                let b0 = Float(ib) * 15 + Float(ib / 2) * 5.5 + 24
                if b0 > 122 && b0 < 146 { continue }                      // the national road
                if rng.next() < 0.16 { _ = rng.next(); continue }         // gardens, yards, car parks
                let c = townP(a0 + 5.75, b0 + 7.5)
                if !lotFree(c.x, c.y, margin: 9) { continue }
                let h = gy(c.x, c.y)
                if h > 6.5 || h < 0.2 { continue }
                let roll = rng.next()
                var lot = FinaleLot(x: c.x + rng.r(-0.8, 0.8), z: c.y + rng.r(-0.8, 0.8), y: h, yaw: townYaw + rng.r(-0.06, 0.06),
                                    L: rng.r(3.9, 5.3), W: rng.r(3.4, 4.9), H: rng.r(5.4, 6.2), rise: rng.r(1.5, 2.1),
                                    kind: roll < 0.55 ? 0 : (roll < 0.8 ? 1 : (roll < 0.9 ? 2 : 3)),
                                    wall: finaleLin(rng.pick(wallCols)) * rng.r(0.9, 1.04), roof: finaleLin(rng.pick(roofCols)) * rng.r(0.85, 1.1),
                                    seed: UInt64(ia * 100 + ib), big: false)
                if lot.kind == 2 { lot.H = 3.1; lot.rise = rng.r(1.8, 2.3); lot.L += 0.6 }
                if lot.kind == 3 { lot.H = rng.r(6.2, 7.4); lot.roof = finaleLin(0x8E8C86) }
                // fish-processing sheds and warehouses in the first rows behind the quay
                if b0 < 70 && rng.next() < 0.35 {
                    lot.kind = 4; lot.L = rng.r(9, 14); lot.W = rng.r(6.5, 8); lot.H = rng.r(6.5, 8.5); lot.rise = 1.0
                    lot.wall = finaleLin([0xC8CCCC, 0xDCDCD6, 0xA8B0B4][Int(rng.r(0, 2.99))]); lot.roof = finaleLin([0x8A9096, 0x6E7E8A, 0x9A4A3A][Int(rng.r(0, 2.99))])
                    lot.big = true
                }
                out.append(lot)
            }
        }
        // houses up the valley sides, above the run-up: these survive
        for _ in 0..<900 {
            let x = rng.r(-560, 300), z = rng.r(-700, 130)
            let h = gy(x, z)
            if h < runup + 1.5 || h > 38 { continue }
            let e: Float = 4
            let sx = gy(x + e, z) - gy(x - e, z), sz = gy(x, z + e) - gy(x, z - e)
            if sqrt(sx * sx + sz * sz) / (2 * e) > 0.42 { continue }
            if sqrt(x * x + z * z) < hillR + 12 { continue }
            if out.contains(where: { abs($0.x - x) < 13 && abs($0.z - z) < 13 }) { continue }
            let roll = rng.next()
            out.append(FinaleLot(x: x, z: z, y: h, yaw: atan2(sz, sx) + .pi / 2 + rng.r(-0.2, 0.2), L: rng.r(3.6, 4.8), W: rng.r(3.2, 4.2), H: rng.r(5.4, 6.0),
                                 rise: rng.r(1.5, 2.0), kind: roll < 0.6 ? 0 : 1, wall: finaleLin(rng.pick(wallCols)), roof: finaleLin(rng.pick(roofCols)) * rng.r(0.85, 1.1),
                                 seed: UInt64(5000 + out.count), big: false))
        }
        lots = out
    }

    /// Is (x, z) free for a building: on the valley floor, off the hill, the quay, the river, the school?
    private func lotFree(_ x: Float, _ z: Float, margin: Float) -> Bool {
        if x > shoreX(z) - 14 - margin * 0.3 { return false }
        if sqrt(x * x + z * z) < hillR + margin { return false }
        if abs(z - riverZ(x)) < 12 + margin * 0.5 { return false }
        let sx = x - schoolXZ.x, sz = z - schoolXZ.y
        let su = sx * townU.x + sz * townU.y, sv = sx * townV.x + sz * townV.y
        if abs(su) < 70 + margin && sv > -95 - margin && sv < 30 + margin { return false }
        let cx = x - centerXZ.x, cz = z - centerXZ.y
        if cx * cx + cz * cz < (34 + margin) * (34 + margin) { return false }
        let mx = x - marketXZ.x, mz = z - marketXZ.y
        if mx * mx + mz * mz < (48 + margin) * (48 + margin) { return false }
        let fx = x - stairB.x, fz = z - stairB.y
        if fx * fx + fz * fz < 16 * 16 { return false }
        for b in rcBuildings {
            let dx = x - b.x, dz = z - b.z
            let u = dx * townU.x + dz * townU.y, v = dx * townV.x + dz * townV.y
            if abs(u) < b.L + margin && abs(v) < b.W + margin { return false }
        }
        return true
    }

    // MARK: The intact town (built only while the wave has not come)

    private func buildLowTown() {
        guard townLow == nil else { return }
        let root = SCNNode()
        var walls = FinaleMesh(), roofs = FinaleMesh(), lit = FinaleMesh()
        walls.reserve(60000); roofs.reserve(30000)
        for lot in lots where lot.y < runup - 0.5 { addHouse(&walls, &roofs, &lit, lot) }
        root.addChildNode(walls.node(vc(0.85)))
        root.addChildNode(roofs.node(vc(0.6, snow: 1.2)))
        // windows lit in the evening, street lamps along the two main roads
        let wm = SK.mat(.white, roughness: 0.4)
        wm.emission.contents = SK.rgb(0xFFC27A)
        wm.emission.intensity = 0
        root.addChildNode(lit.node(wm, shadow: false))
        townWindowMat = wm
        var lamps = FinaleMesh()
        for b in [Float(12), 134] {
            var a: Float = 4
            while a < 640 {
                let c = townP(a, b - 4.5)
                a += 30
                if !lotFree(c.x, c.y, margin: -9) || gy(c.x, c.y) > 6 { continue }
                lamps.blob(FinaleV3(c.x, gy(c.x, c.y) + 6.5, c.y), FinaleV3(0.3, 0.2, 0.3), FinaleV3(1, 1, 1), noise, seed: 0, jitter: 0, rings: 3, segs: 5, under: 1, vary: 0)
            }
        }
        let lm = SK.mat(.black, roughness: 1)
        lm.emission.contents = SK.rgb(0xFFE6B0)
        lm.emission.intensity = 0
        root.addChildNode(lamps.node(lm, shadow: false))
        townLampMat = lm
        buildRoads(root)
        buildPoles(root)
        buildCars(root)
        buildGardens(root)
        world.addChildNode(root)
        townLow = root
    }

    private func buildHighTown() {
        let root = SCNNode()
        var walls = FinaleMesh(), roofs = FinaleMesh()
        for lot in lots where lot.y >= runup - 0.5 { addHouse(&walls, &roofs, lot) }
        // a temple on the slope across the valley, and its graveyard
        let tp = SIMD2<Float>(-120, -575)
        let ty = gy(tp.x, tp.y)
        walls.box(FinaleV3(tp.x, ty + 2.0, tp.y), FinaleV3(8, 3.2, 6), finaleLin(0x6A4E38), yaw: 0.2)
        roofs.hipRoof(FinaleV3(tp.x, ty + 5.2, tp.y), halfL: 8, halfW: 6, rise: 5.5, over: 2.2, yaw: 0.2, ridgeK: 0.55, finaleLin(0x2E3238))
        var rng = FinaleRng(71)
        for k in 0..<60 {
            let gx = tp.x + 16 + Float(k % 10) * 2.2 + rng.r(-0.3, 0.3), gz = tp.y + 6 + Float(k / 10) * 2.4
            let y = gy(gx, gz)
            walls.box(FinaleV3(gx, y + 0.5, gz), FinaleV3(0.25, 0.55, 0.18), finaleLin(0x8E8C88) * rng.r(0.8, 1.1), yaw: 0.2)
        }
        root.addChildNode(walls.node(vc(0.85)))
        root.addChildNode(roofs.node(vc(0.6, snow: 1.2)))
        world.addChildNode(root)
        townHigh = root
    }

    private func addHouse(_ walls: inout FinaleMesh, _ roofs: inout FinaleMesh, _ lot: FinaleLot) {
        var lit = FinaleMesh()
        addHouse(&walls, &roofs, &lit, lot)
        walls.append(lit)
    }

    private func addHouse(_ walls: inout FinaleMesh, _ roofs: inout FinaleMesh, _ lit: inout FinaleMesh, _ lot: FinaleLot) {
        let yaw = lot.yaw
        let c = FinaleV3(lot.x, lot.y, lot.z)
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yaw) }
        let L = lot.L, W = lot.W, H = lot.H
        let sink: Float = 1.4
        walls.box(P(0, (H - sink) / 2, 0), FinaleV3(L, (H + sink) / 2, W), lot.wall, yaw: yaw, bottom: false)
        let dark = finaleLin(0x262B31)
        switch lot.kind {
        case 0, 2:
            roofs.hipRoof(P(0, H, 0), halfL: L, halfW: W, rise: lot.rise, over: 0.55, yaw: yaw, ridgeK: 1, lot.roof)
        case 1:
            roofs.gableRoof(P(0, H, 0), halfL: L, halfW: W, rise: lot.rise, over: 0.5, yaw: yaw, lot.roof, gable: lot.wall, walls: &walls)
        case 3:
            walls.box(P(0, H + 0.35, 0), FinaleV3(L + 0.05, 0.35, W + 0.05), lot.wall * 0.92, yaw: yaw)
            roofs.quad(P(-L, H + 0.02, W), P(L, H + 0.02, W), P(L, H + 0.02, -W), P(-L, H + 0.02, -W), lot.roof)
        default:
            roofs.gableRoof(P(0, H, 0), halfL: L, halfW: W, rise: lot.rise, over: 0.3, yaw: yaw, lot.roof, gable: lot.wall, walls: &walls)
        }
        // windows on the long sides (and a pent roof over the ground floor on many houses)
        if lot.kind != 4 {
            let floors = H > 4 ? 2 : 1
            for f in 0..<floors {
                let y = 1.5 + Float(f) * 2.75
                for (j, u) in [Float(-0.45), 0.45].enumerated() {
                    let on = (lot.seed &* 2654435761 &+ UInt64(f * 2 + j)) % 5 < 2
                    if on {
                        lit.quad(P(u * L - 0.6, y - 0.55, W + 0.03), P(u * L + 0.6, y - 0.55, W + 0.03), P(u * L + 0.6, y + 0.55, W + 0.03), P(u * L - 0.6, y + 0.55, W + 0.03), dark)
                        lit.quad(P(u * L + 0.6, y - 0.55, -W - 0.03), P(u * L - 0.6, y - 0.55, -W - 0.03), P(u * L - 0.6, y + 0.55, -W - 0.03), P(u * L + 0.6, y + 0.55, -W - 0.03), dark)
                    } else {
                        walls.quad(P(u * L - 0.6, y - 0.55, W + 0.03), P(u * L + 0.6, y - 0.55, W + 0.03), P(u * L + 0.6, y + 0.55, W + 0.03), P(u * L - 0.6, y + 0.55, W + 0.03), dark)
                        walls.quad(P(u * L + 0.6, y - 0.55, -W - 0.03), P(u * L - 0.6, y - 0.55, -W - 0.03), P(u * L - 0.6, y + 0.55, -W - 0.03), P(u * L + 0.6, y + 0.55, -W - 0.03), dark)
                    }
                }
            }
            if floors == 2 && lot.seed % 5 < 2 {
                roofs.quad(P(-L - 0.2, 2.9, W + 0.75), P(L + 0.2, 2.9, W + 0.75), P(L + 0.2, 3.35, W), P(-L - 0.2, 3.35, W), lot.roof * 0.9)
            }
        } else {
            walls.quad(P(-L * 0.3, 0, W + 0.03), P(L * 0.3, 0, W + 0.03), P(L * 0.3, 4.2, W + 0.03), P(-L * 0.3, 4.2, W + 0.03), lot.wall * 0.7)
        }
    }

    private func buildRoads(_ root: SCNNode) {
        var m = FinaleMesh()
        let asphalt = finaleLin(0x4C4C4A), lane = finaleLin(0x5E5D58), white = finaleLin(0xCFCDC4)
        // a ribbon along a polyline of town-grid points, cut where it leaves the valley floor
        func ribbon(_ a0: Float, _ b0: Float, _ a1: Float, _ b1: Float, width: Float, _ col: FinaleV3, line: Bool = false) {
            let len = sqrt((a1 - a0) * (a1 - a0) + (b1 - b0) * (b1 - b0))
            let n = max(2, Int(len / 8))
            var prev: (FinaleV3, FinaleV3, Bool)? = nil
            let du = (a1 - a0) / len, dv = (b1 - b0) / len
            for k in 0...n {
                let t = Float(k) / Float(n)
                let a = a0 + (a1 - a0) * t, b = b0 + (b1 - b0) * t
                let c = townP(a, b)
                let side = townU * (-dv * width / 2) + townV * (du * width / 2)
                let p = FinaleV3(c.x - side.x, 0, c.y - side.y), q = FinaleV3(c.x + side.x, 0, c.y + side.y)
                let ok = lotFree(c.x, c.y, margin: -8) && gy(c.x, c.y) < 7
                let pp = FinaleV3(p.x, gy(p.x, p.z) + 0.07, p.z), qq = FinaleV3(q.x, gy(q.x, q.z) + 0.07, q.z)
                if let pr = prev, pr.2 && ok {
                    m.quad(pr.0, pp, qq, pr.1, col)
                    if line {
                        let mc0 = (pr.0 + pr.1) * 0.5, mc1 = (pp + qq) * 0.5
                        let off = FinaleV3(side.x, 0, side.y) * (0.06 / width)
                        m.quad(mc0 - off + FinaleV3(0, 0.01, 0), mc1 - off + FinaleV3(0, 0.01, 0), mc1 + off + FinaleV3(0, 0.01, 0), mc0 + off + FinaleV3(0, 0.01, 0), white)
                    }
                }
                prev = (pp, qq, ok)
            }
        }
        ribbon(-10, 14, 640, 14, width: 8, asphalt, line: true)            // the harbour road
        ribbon(-40, 134, 640, 134, width: 11, asphalt, line: true)         // the national road
        for k in 0..<15 { ribbon(Float(k) * 52 + 2, 8, Float(k) * 52 + 2, 560, width: 5, lane) }
        for k in 0..<14 where k != 3 && k != 4 {
            let b = Float(k) * 35.5 + 22
            ribbon(-10, b, 640, b, width: 4.5, lane)
        }
        // the street from the foot of the steps to the harbour road
        let sdx = stairB.x - stairT.x, sdz = stairB.y - stairT.y
        let sl = sqrt(sdx * sdx + sdz * sdz)
        var s = FinaleMesh()
        let a = FinaleV3(stairB.x + sdx / sl * 1.0, 0, stairB.y + sdz / sl * 1.0)
        for k in 0..<6 {
            let p0 = a + FinaleV3(sdx / sl, 0, sdz / sl) * Float(k) * 6, p1 = a + FinaleV3(sdx / sl, 0, sdz / sl) * Float(k + 1) * 6
            let side = FinaleV3(-sdz / sl, 0, sdx / sl) * 2.4
            s.quad(FinaleV3(p0.x - side.x, gy(p0.x - side.x, p0.z - side.z) + 0.07, p0.z - side.z), FinaleV3(p1.x - side.x, gy(p1.x - side.x, p1.z - side.z) + 0.07, p1.z - side.z),
                   FinaleV3(p1.x + side.x, gy(p1.x + side.x, p1.z + side.z) + 0.07, p1.z + side.z), FinaleV3(p0.x + side.x, gy(p0.x + side.x, p0.z + side.z) + 0.07, p0.z + side.z), lane)
        }
        m.append(s)
        root.addChildNode(m.node(vc(0.9, snow: 0.6), shadow: false))
    }

    private func buildPoles(_ root: SCNNode) {
        var m = FinaleMesh(), wires = FinaleMesh()
        let conc = finaleLin(0x9A968E), wireC = finaleLin(0x1E1E1E)
        for b in [Float(20), 128] {
            var prev: [FinaleV3] = []
            var a: Float = 0
            while a < 640 {
                let c = townP(a, b)
                a += 36
                if !lotFree(c.x, c.y, margin: -9) || gy(c.x, c.y) > 6 { prev = []; continue }
                let base = FinaleV3(c.x, gy(c.x, c.y) - 0.3, c.y)
                let top = base + FinaleV3(0, 11, 0)
                m.tube(base, top, 0.16, 0.11, conc, segs: 5)
                let across = FinaleV3(townV.x, 0, townV.y)
                m.box(top - FinaleV3(0, 0.6, 0), FinaleV3(0.05, 0.05, 0.9), finaleLin(0x3A3A38), yaw: townYaw)
                let pts = [top - FinaleV3(0, 0.45, 0) + across * 0.8, top - FinaleV3(0, 0.45, 0) - across * 0.8, top]
                if prev.count == 3 {
                    for k in 0..<3 { wires.rope(prev[k], pts[k], sag: 0.6, r: 0.02, wireC, segs: 5, sides: 3) }
                }
                prev = pts
            }
        }
        root.addChildNode(m.node(vc(0.85, snow: 0.3)))
        root.addChildNode(wires.node(vc(0.6, snow: 0), shadow: false))
    }

    private func buildCars(_ root: SCNNode) {
        var m = FinaleMesh()
        var rng = FinaleRng(41)
        let carCols: [UInt32] = [0xE8E8E4, 0xE8E8E4, 0xD8D8D4, 0xA8ACB0, 0x2A2C30, 0x2E3E66, 0x9A2A26, 0xD8C04A, 0x5A6E5A]
        var placed = 0
        while placed < 90 {
            let onMain = rng.next() < 0.45
            let a = rng.r(0, 600), b: Float = onMain ? 134 + (rng.next() < 0.5 ? -2.6 : 2.6) : Float(Int(rng.r(0, 14))) * 35.5 + 22
            let c = townP(a, b)
            if !lotFree(c.x, c.y, margin: -8) || gy(c.x, c.y) > 6 { placed += 1; continue }
            car(&m, FinaleV3(c.x, gy(c.x, c.y) + 0.07, c.y), yaw: townYaw + (rng.next() < 0.5 ? 0 : .pi), col: finaleLin(rng.pick(carCols)), seed: &rng)
            placed += 1
        }
        root.addChildNode(m.node(vc(0.4, snow: 0.8)))
    }

    private func car(_ m: inout FinaleMesh, _ p: FinaleV3, yaw: Float, pitch: Float = 0, roll: Float = 0, col: FinaleV3, seed: inout FinaleRng, upside: Bool = false) {
        let k: Float = seed.next() < 0.3 ? 0.82 : 1                       // kei cars
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { p + finaleRot(FinaleV3(x, upside ? 1.5 - y : y, z), yaw: yaw, pitch: pitch, roll: roll) }
        m.box(P(0, 0.62, 0), FinaleV3(2.15 * k, 0.32, 0.86), col, yaw: yaw, pitch: pitch, roll: roll)
        m.box(P(-0.15, 1.12, 0), FinaleV3(1.15 * k, 0.24, 0.78), finaleLin(0x22272C), yaw: yaw, pitch: pitch, roll: roll, top: col)
        for (x, z) in [(Float(1.35), Float(0.75)), (-1.35, 0.75), (1.35, -0.75), (-1.35, -0.75)] {
            m.box(P(x * k, 0.3, z), FinaleV3(0.32, 0.3, 0.12), finaleLin(0x151515), yaw: yaw, pitch: pitch, roll: roll)
        }
    }

    private func buildGardens(_ root: SCNNode) {
        var crowns = FinaleMesh(), wood = FinaleMesh()
        var rng = FinaleRng(53)
        for lot in lots where lot.y < runup - 0.5 && lot.kind != 4 {
            if rng.next() > 0.22 { continue }
            let p = SIMD2<Float>(lot.x, lot.z) + townU * rng.r(-6, 6) + townV * (lot.W + 2.5)
            let y = gy(p.x, p.y)
            if rng.next() < 0.45 {
                // black pines, clipped
                wood.tube(FinaleV3(p.x, y, p.y), FinaleV3(p.x + 0.4, y + 3.2, p.y), 0.14, 0.09, finaleLin(0x4A3A2C), segs: 4)
                crowns.blob(FinaleV3(p.x + 0.5, y + 3.6, p.y), FinaleV3(1.6, 0.9, 1.4), finaleLin(0x2C3E26), noise, seed: p.x, jitter: 0.3, rings: 4, segs: 7)
            } else {
                broadleaf(&crowns, &wood, FinaleV3(p.x, y, p.y), h: rng.r(3.5, 6), seed: p.y, bareTree: rng.next() < 0.55)
            }
        }
        // the row of black pines along the harbour road below the hill
        for k in 0..<16 {
            let a = -6 + Float(k) * 4.6
            let c = townP(a, 3)
            if sqrt(c.x * c.x + c.y * c.y) < hillR + 2 { continue }
            let y = gy(c.x, c.y)
            wood.tube(FinaleV3(c.x, y, c.y), FinaleV3(c.x + 0.6, y + 9, c.y + 0.3), 0.3, 0.18, finaleLin(0x4A3A2C), segs: 5)
            crowns.blob(FinaleV3(c.x + 0.8, y + 9.6, c.y + 0.4), FinaleV3(3.0, 1.5, 2.6), finaleLin(0x2A3C24), noise, seed: a, jitter: 0.35, rings: 4, segs: 8)
        }
        root.addChildNode(crowns.node(vc(0.95, snow: 0.8)))
        root.addChildNode(wood.node(vc(0.95, snow: 0)))
    }

    // MARK: The training centre (水产与防灾研修中心)

    private func buildCenter() {
        let c = FinaleV3(centerXZ.x, gy(centerXZ.x, centerXZ.y), centerXZ.y)
        let yaw = townYaw
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yaw) }
        let L: Float = 19, W: Float = 8.5, f2: Float = 4.6, roofT: Float = 9.6
        let concrete = finaleLin(0xC9C6BE), glassC = finaleLin(0x56707E)
        // intact: walls, ribbon windows, the stair tower, the sign
        var a = FinaleMesh()
        a.box(P(0, (roofT - 1) / 2, 0), FinaleV3(L, (roofT + 1) / 2, W), concrete, yaw: yaw, bottom: false)
        a.box(P(0, roofT + 0.5, 0), FinaleV3(L + 0.1, 0.5, W + 0.1), concrete * 0.95, yaw: yaw)
        a.box(P(L - 3.2, roofT + 1.9, -W + 2.6), FinaleV3(2.6, 1.9, 2.4), concrete, yaw: yaw)
        for (y0, y1) in [(Float(1.0), Float(3.6)), (f2 + 1.0, f2 + 3.7)] {
            for sgn in [Float(1), -1] {
                let z = (W + 0.03) * sgn
                if sgn > 0 { a.quad(P(-L + 1, y0, z), P(L - 1, y0, z), P(L - 1, y1, z), P(-L + 1, y1, z), glassC) }
                else { a.quad(P(L - 1, y0, z), P(-L + 1, y0, z), P(-L + 1, y1, z), P(L - 1, y1, z), glassC) }
            }
            a.quad(P(L + 0.03, y0, W - 1), P(L + 0.03, y0, -W + 1), P(L + 0.03, y1, -W + 1), P(L + 0.03, y1, W - 1), glassC)
        }
        for k in 0..<12 {
            let x = -L + 1 + Float(k) * (2 * L - 2) / 11
            for sgn in [Float(1), -1] { a.box(P(x, roofT / 2, (W + 0.08) * sgn), FinaleV3(0.2, roofT / 2, 0.08), concrete * 1.03, yaw: yaw) }
        }
        a.box(P(-6, 0.5, -W - 1.4), FinaleV3(3.2, 0.5, 1.4), concrete * 0.9, yaw: yaw)       // the entrance porch (inland side)
        a.box(P(-6, 3.5, -W - 1.4), FinaleV3(3.4, 0.15, 1.6), concrete, yaw: yaw)
        let intact = SCNNode()
        intact.addChildNode(a.node(vc(0.75, snow: 1.1)))
        let text = SCNText(string: "水産・防災研修センター", extrusionDepth: 0)
        text.font = NSFont(name: "HiraginoSans-W6", size: 10) ?? NSFont.boldSystemFont(ofSize: 10)
        text.flatness = 0.4
        text.firstMaterial = SK.mat(SK.rgb(0x2A4A7A), roughness: 0.8, doubleSided: true)
        let tn = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        let k: CGFloat = 0.11
        tn.scale = SCNVector3(k, k, k)
        let sp = P(-1, 8.6, -W - 0.06)
        tn.position = SCNVector3(CGFloat(sp.x), CGFloat(sp.y) - (mn.y + mx.y) / 2 * k, CGFloat(sp.z))
        tn.eulerAngles.y = CGFloat(yaw) + .pi
        tn.position.x -= (mn.x + mx.x) / 2 * k * CGFloat(cos(yaw + .pi))
        tn.position.z += (mn.x + mx.x) / 2 * k * CGFloat(sin(yaw + .pi))
        intact.addChildNode(tn)
        world.addChildNode(intact)
        centerIntact = intact

        // after the wave: the bare frame — columns, slabs, a few torn wall panels, wreckage inside
        var b = FinaleMesh()
        var rng = FinaleRng(61)
        for i in 0..<7 {
            let x = -L + 0.3 + Float(i) * (2 * L - 0.6) / 6
            for z in [-W + 0.3, Float(0), W - 0.3] { b.box(P(x, roofT / 2, z), FinaleV3(0.32, roofT / 2, 0.32), concrete * 0.92, yaw: yaw) }
        }
        b.box(P(0, f2, 0), FinaleV3(L, 0.2, W), concrete * 0.9, yaw: yaw)
        b.box(P(0, roofT, 0), FinaleV3(L + 0.1, 0.22, W + 0.1), concrete * 0.88, yaw: yaw)
        b.box(P(0, 0.12, 0), FinaleV3(L, 0.14, W), concrete * 0.7, yaw: yaw)
        for i in 0..<6 {
            let x = -L + 3.3 + Float(i) * 6.4
            for sgn in [Float(1), -1] {
                b.box(P(x, f2 - 0.45, (W - 0.3) * sgn), FinaleV3(3.0, 0.3, 0.2), concrete * 0.88, yaw: yaw)
                b.box(P(x, roofT - 0.45, (W - 0.3) * sgn), FinaleV3(3.0, 0.3, 0.2), concrete * 0.88, yaw: yaw)
            }
        }
        b.box(P(L - 3.2, roofT + 1.9, -W + 2.6), FinaleV3(2.6, 1.9, 2.4), concrete * 0.86, yaw: yaw)
        // remaining wall panels, hanging and cracked
        for (x, z, f) in [(Float(-16), Float(1), Float(0)), (Float(8), Float(-1), Float(1)), (Float(14.5), Float(1), Float(1))] {
            let y = f == 0 ? 2.3 : f2 + 2.3
            b.box(P(x, y, (W - 0.1) * z), FinaleV3(2.6, 1.9, 0.12), concrete * 0.95, yaw: yaw, roll: rng.r(-0.05, 0.05))
        }
        // the parapet, broken off along most of the seaward side
        b.box(P(-12, roofT + 0.5, -W), FinaleV3(7, 0.5, 0.1), concrete * 0.9, yaw: yaw)
        b.box(P(-L, roofT + 0.5, 0), FinaleV3(0.1, 0.5, W), concrete * 0.9, yaw: yaw)
        // wreckage jammed into both floors
        for f in [Float(0.26), f2 + 0.2] {
            for _ in 0..<26 {
                let x = rng.r(-L + 1, L - 1), z = rng.r(-W + 1, W - 1)
                b.box(P(x, f + rng.r(0.1, 0.9), z), FinaleV3(rng.r(0.6, 1.8), rng.r(0.05, 0.14), rng.r(0.1, 0.3)), finaleLin(rng.pick([0x6E5A44, 0x8A7458, 0x4E4438, 0x9A9488])),
                      yaw: yaw + rng.r(0, 3), pitch: rng.r(-0.5, 0.5), roll: rng.r(-0.5, 0.5))
            }
        }
        var junk = rng
        car(&b, P(6, 0.28, 2), yaw: yaw + 0.6, roll: 0.35, col: finaleLin(0xE6E6E2), seed: &junk)
        car(&b, P(-9, f2 + 0.2, -3), yaw: yaw + 2.0, pitch: 0.1, roll: -0.25, col: finaleLin(0x2E3E66), seed: &junk)
        let shell = SCNNode()
        shell.addChildNode(b.node(vc(0.85, snow: 1)))
        // the stern trawler that came to rest on its roof
        let boat = fishingBoat(length: 24, hull: finaleLin(0xE4E2DA), stripe: finaleLin(0x2C4F8A), seed: 3)
        let bp = P(-2, roofT + 0.3, 0.6)
        boat.position = SCNVector3(CGFloat(bp.x), CGFloat(bp.y), CGFloat(bp.z))
        boat.eulerAngles = SCNVector3(0.06, CGFloat(yaw) + 0.32, 0.16)
        shell.addChildNode(boat)
        shell.isHidden = true
        world.addChildNode(shell)
        centerShell = shell
        let mud = mudBand(P(0, 0, 0), halfL: L + 0.12, halfW: W + 0.12, yaw: yaw)
        shell.addChildNode(mud)
    }

    /// The stain the water left on a building, and the crisp line at its highest (both set in apply).
    private func mudBand(_ c: FinaleV3, halfL: Float, halfW: Float, yaw: Float) -> SCNNode {
        func ring(_ h: Float) -> FinaleMesh {
            var m = FinaleMesh()
            func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yaw) }
            let col = FinaleV3(1, 1, 1)
            m.quad(P(-halfL, 0, halfW), P(halfL, 0, halfW), P(halfL, h, halfW), P(-halfL, h, halfW), col)
            m.quad(P(halfL, 0, -halfW), P(-halfL, 0, -halfW), P(-halfL, h, -halfW), P(halfL, h, -halfW), col)
            m.quad(P(halfL, 0, halfW), P(halfL, 0, -halfW), P(halfL, h, -halfW), P(halfL, h, halfW), col)
            m.quad(P(-halfL, 0, -halfW), P(-halfL, 0, halfW), P(-halfL, h, halfW), P(-halfL, h, -halfW), col)
            return m
        }
        let mat = SK.mat(SK.rgb(0x4A3C2C), roughness: 0.9)
        mat.transparency = 0.38
        mat.writesToDepthBuffer = false
        let band = ring(1).node(mat, shadow: false)
        band.pivot = SCNMatrix4MakeTranslation(0, CGFloat(c.y), 0)
        band.position.y = CGFloat(c.y)
        let lm = SK.mat(SK.rgb(0x2A221A), roughness: 0.9)
        lm.transparency = 0.8
        lm.writesToDepthBuffer = false
        let line = ring(0.22).node(lm, shadow: false)
        line.pivot = SCNMatrix4MakeTranslation(0, CGFloat(c.y), 0)
        line.position.y = CGFloat(c.y)
        let holder = SCNNode()
        holder.addChildNode(band)
        holder.addChildNode(line)
        mudLines.append((band, line, CGFloat(c.y)))
        return holder
    }

    private func buildRCBuildings() {
        for b in rcBuildings {
            let c = FinaleV3(b.x, b.y, b.z)
            func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: b.yaw) }
            var m = FinaleMesh(), glass = FinaleMesh(), holes = FinaleMesh()
            let L = b.L, W = b.W, H = b.H
            m.box(P(0, (H - 1) / 2, 0), FinaleV3(L, (H + 1) / 2, W), b.wall, yaw: b.yaw, bottom: false)
            m.box(P(0, H + 0.45, 0), FinaleV3(L + 0.05, 0.45, W + 0.05), b.wall * 0.93, yaw: b.yaw)
            m.box(P(L * 0.6, H + 1.6, 0), FinaleV3(1.4, 1.2, 1.4), finaleLin(0xB8B8B0), yaw: b.yaw)
            for f in 0..<b.kind {
                let y0 = Float(f) * 3.4 + 1.0, y1 = y0 + 1.7
                m.box(P(0, Float(f + 1) * 3.4 + 0.1, W + 0.1), FinaleV3(L + 0.1, 0.12, 0.12), b.wall * 1.06, yaw: b.yaw)
                let n = Int(L / 2.6)
                for k in 0..<n {
                    let x = -L + 1.3 + Float(k) * (2 * L - 2.6) / Float(max(1, n - 1))
                    for sgn in [Float(1), -1] {
                        let z = (W + 0.03) * sgn
                        let q0 = P(x - 0.9, y0, z), q1 = P(x + 0.9, y0, z), q2 = P(x + 0.9, y1, z), q3 = P(x - 0.9, y1, z)
                        if sgn > 0 { glass.quad(q0, q1, q2, q3, finaleLin(0x52687A)); holes.quad(q0, q1, q2, q3, finaleLin(0x141618)) }
                        else { glass.quad(q1, q0, q3, q2, finaleLin(0x52687A)); holes.quad(q1, q0, q3, q2, finaleLin(0x141618)) }
                    }
                }
            }
            let root = SCNNode()
            root.addChildNode(m.node(vc(0.8, snow: 1.0)))
            let g = glass.node(vc(0.15, snow: 0, metal: 0.2))
            root.addChildNode(g)
            let h = holes.node(vc(0.9, snow: 0))
            h.isHidden = true
            root.addChildNode(h)
            root.addChildNode(mudBand(c, halfL: L + 0.1, halfW: W + 0.1, yaw: b.yaw))
            world.addChildNode(root)
            rcGlass.append(g)
            rcShell.append(h)
        }
    }

    // MARK: The school (潮见小学)

    private func buildSchool() {
        let c = FinaleV3(schoolXZ.x, gy(schoolXZ.x, schoolXZ.y), schoolXZ.y)
        let yaw = townYaw
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yaw) }
        let L: Float = 34, W: Float = 7.5, fh: Float = 3.8, top: Float = 3 * fh + 0.4
        let conc = finaleLin(0xD9D6CC), trim = finaleLin(0xB8B4AA)
        var m = FinaleMesh(), win = FinaleMesh(), shell = FinaleMesh()
        m.box(P(0, (top - 1) / 2, 0), FinaleV3(L, (top + 1) / 2, W), conc, yaw: yaw, bottom: false)
        m.box(P(0, top + 0.55, 0), FinaleV3(L + 0.05, 0.08, W + 0.05), trim, yaw: yaw)
        // the roof railing (fence) that people clung to
        for k in 0..<35 {
            let x = -L + Float(k) * (2 * L) / 34
            for sgn in [Float(1), -1] { m.tube(P(x, top, (W - 0.1) * sgn), P(x, top + 1.2, (W - 0.1) * sgn), 0.03, 0.03, trim, segs: 4) }
        }
        for sgn in [Float(1), -1] { m.tube(P(-L, top + 1.2, (W - 0.1) * sgn), P(L, top + 1.2, (W - 0.1) * sgn), 0.04, 0.04, trim, segs: 4) }
        m.box(P(L - 4, top + 1.6, 0), FinaleV3(3, 1.6, 3), conc, yaw: yaw)                 // stair head
        m.tube(P(L - 9, top, -2), P(L - 9, top + 3.2, -2), 0.6, 0.6, finaleLin(0xB8B8B0), segs: 8)   // water tank
        // the clock over the entrance, facing the schoolyard (seaward)
        m.tube(P(0, top - 1.4, W + 0.05), P(0, top - 1.4, W + 0.12), 0.7, 0.7, finaleLin(0xF0EEE6), segs: 12, cap: true)
        for f in 0..<3 {
            let y0 = Float(f) * fh + 0.95, y1 = y0 + 2.1
            for k in 0..<12 {
                let x = -L + 3 + Float(k) * (2 * L - 6) / 11
                for sgn in [Float(1), -1] {
                    let z = (W + 0.03) * sgn
                    let q0 = P(x - 1.7, y0, z), q1 = P(x + 1.7, y0, z), q2 = P(x + 1.7, y1, z), q3 = P(x - 1.7, y1, z)
                    if sgn > 0 { win.quad(q0, q1, q2, q3, finaleLin(0x5A7484)); shell.quad(q0, q1, q2, q3, finaleLin(0x24262A)) }
                    else { win.quad(q1, q0, q3, q2, finaleLin(0x5A7484)); shell.quad(q1, q0, q3, q2, finaleLin(0x24262A)) }
                }
            }
        }
        // the gym beside it, and the schoolyard with its track
        let gp = P(L + 22, 0, -4)
        m.box(gp + FinaleV3(0, 3.5, 0), FinaleV3(13, 4.5, 10), finaleLin(0xC8C2B4), yaw: yaw + .pi / 2, bottom: false)
        var vault = FinaleMesh()
        vault.sheet(nu: 10, nv: 2, finaleLin(0x6E7C84)) { u, v in
            let a = (u - 0.5) * 2.2
            return gp + finaleRot(FinaleV3(sin(a) * 10.6, 8.0 + cos(a) * 3.0 - 3.0 * cos(1.1), (v - 0.5) * 27), yaw: yaw + .pi / 2)
        }
        m.append(vault)
        var yard = FinaleMesh()
        let yc = P(0, 0, W + 34)
        yard.sheet(nu: 1, nv: 1, finaleLin(0x9A8A6E)) { u, v in
            let q = yc + finaleRot(FinaleV3((u - 0.5) * 70, 0, (v - 0.5) * 54), yaw: yaw)
            return FinaleV3(q.x, self.gy(q.x, q.z) + 0.05, q.z)
        }
        for k in 0..<40 {
            let a0 = Float(k) / 40 * 2 * .pi, a1 = Float(k + 1) / 40 * 2 * .pi
            func R(_ a: Float, _ r: Float) -> FinaleV3 {
                let q = yc + finaleRot(FinaleV3(cos(a) * r * 1.5, 0, sin(a) * r), yaw: yaw)
                return FinaleV3(q.x, self.gy(q.x, q.z) + 0.08, q.z)
            }
            yard.quad(R(a0, 18), R(a1, 18), R(a1, 18.4), R(a0, 18.4), finaleLin(0xE8E6DE))
        }
        // the pool
        let pc = P(-L - 12, 0, 8)
        yard.box(FinaleV3(pc.x, gy(pc.x, pc.z) + 0.4, pc.z), FinaleV3(12.5, 0.4, 6), finaleLin(0xB8B6AE), yaw: yaw)
        yard.box(FinaleV3(pc.x, gy(pc.x, pc.z) + 0.82, pc.z), FinaleV3(11.5, 0.02, 5), finaleLin(0x3E8AA8), yaw: yaw)
        let root = SCNNode()
        root.addChildNode(m.node(vc(0.8, snow: 1.1)))
        let ym = vc(0.9, snow: 0.9)
        root.addChildNode(yard.node(ym, shadow: false))
        yardMat = ym
        let g = win.node(vc(0.12, snow: 0, metal: 0.2))
        root.addChildNode(g)
        let sh = shell.node(vc(0.9, snow: 0))
        sh.isHidden = true
        root.addChildNode(sh)
        root.addChildNode(mudBand(P(0, 0, 0), halfL: L + 0.1, halfW: W + 0.1, yaw: yaw))
        world.addChildNode(root)
        schoolGlass = g
        schoolShell = sh
    }

    // MARK: The harbour

    private func buildHarbor() {
        var quay = FinaleMesh(), bw = FinaleMesh()
        let conc = finaleLin(0xA6A49C), darkC = finaleLin(0x6E6C66)
        // the quay wall along the coast (with a gap at the river mouth)
        var z: Float = -64
        while z > -600 {
            let z1 = z - 8
            let rz = riverZ(shoreX(z))
            z = z1
            if abs(z1 + 4 - rz) < 12 { continue }
            let x0 = shoreX(z1 + 8), x1 = shoreX(z1)
            let top: Float = 1.25
            quay.quad(FinaleV3(x0, -3.5, z1 + 8), FinaleV3(x1, -3.5, z1), FinaleV3(x1, top, z1), FinaleV3(x0, top, z1 + 8), darkC)
            quay.quad(FinaleV3(x0 - 12, top, z1 + 8), FinaleV3(x0, top, z1 + 8), FinaleV3(x1, top, z1), FinaleV3(x1 - 12, top, z1), conc)
            if Int(-z1) % 24 < 8 { quay.box(FinaleV3(x1 - 0.6, top + 0.25, z1 + 4), FinaleV3(0.2, 0.25, 0.2), finaleLin(0x2E2C2A)) }
        }
        // two breakwaters: caissons with a parapet, tetrapods along the sea side, lights at the heads
        func breakwater(_ a: SIMD2<Float>, _ b: SIMD2<Float>, light: FinaleV3) {
            let d = b - a
            let len = sqrt(d.x * d.x + d.y * d.y)
            let yaw = atan2(-d.y, d.x)
            let c = (a + b) * 0.5
            bw.box(FinaleV3(c.x, -1.5, c.y), FinaleV3(len / 2, 4.6, 4.5), conc, yaw: yaw)
            bw.box(FinaleV3(c.x, 3.6, c.y) + finaleRot(FinaleV3(0, 0, -3.6), yaw: yaw), FinaleV3(len / 2, 0.5, 0.9), conc * 0.95, yaw: yaw)
            var rng = FinaleRng(UInt64(a.x * 10))
            var s: Float = 0
            while s < len {
                for row in 0..<2 {
                    let p = a + d * (s / len)
                    let off = finaleRot(FinaleV3(0, 0, -6.2 - Float(row) * 2.2), yaw: yaw)
                    let q = FinaleV3(p.x + off.x, -0.2 + Float(1 - row) * 1.1, p.y + off.z)
                    bw.tetrapod(q, 1.25, conc * rng.r(0.85, 1.02), yaw: rng.r(0, 3), pitch: rng.r(-0.6, 0.6))
                }
                s += 2.4
            }
            let tip = FinaleV3(b.x, 3.1, b.y)
            bw.tube(tip, tip + FinaleV3(0, 7.5, 0), 0.9, 0.75, light, segs: 10)
            bw.box(tip + FinaleV3(0, 7.8, 0), FinaleV3(1.0, 0.3, 1.0), light * 0.9)
        }
        breakwater(SIMD2(302, -440), SIMD2(560, -330), light: finaleLin(0xC8302A))
        breakwater(SIMD2(245, 40), SIMD2(420, -110), light: finaleLin(0xE6E4DE))
        world.addChildNode(quay.node(vc(0.9, snow: 0.8)))
        world.addChildNode(bw.node(vc(0.9, snow: 0.8)))

        // intact: the fish market shed, oil tanks, boats at the quay
        let intact = SCNNode()
        var mk = FinaleMesh()
        let mp = FinaleV3(marketXZ.x, gy(marketXZ.x, marketXZ.y), marketXZ.y)
        let myaw = townYaw
        func M(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { mp + finaleRot(FinaleV3(x, y, z), yaw: myaw) }
        for i in 0..<9 {
            for sgn in [Float(1), -1] { mk.tube(M(-32 + Float(i) * 8, -0.5, 10 * sgn), M(-32 + Float(i) * 8, 7.5, 10 * sgn), 0.25, 0.25, finaleLin(0x7E8A90), segs: 5) }
        }
        var mkGable = FinaleMesh()
        mk.gableRoof(M(0, 7.5, 0), halfL: 33, halfW: 10, rise: 2.2, over: 1.0, yaw: myaw, finaleLin(0x7C8E9A), gable: finaleLin(0xB8BEC2), walls: &mkGable)
        mk.append(mkGable)
        mk.box(M(0, 2.0, -9.6), FinaleV3(32, 2.5, 0.15), finaleLin(0xC4C8C8), yaw: myaw)
        for k in 0..<3 {
            let tp = M(-10 + Float(k) * 12, 0, -30)
            mk.tube(tp, tp + FinaleV3(0, 9, 0), 5.2, 5.2, finaleLin(0xDAD8D0), segs: 16, cap: true)
            mk.tube(tp + FinaleV3(0, 9, 0), tp + FinaleV3(0, 9.6, 0), 5.2, 3.0, finaleLin(0xC8C6BE), segs: 16, cap: true)
        }
        intact.addChildNode(mk.node(vc(0.6, snow: 1.1)))
        var rng = FinaleRng(81)
        let berths: [Float] = [-120, -150, -178, -262, -292, -380, -405, -470, -500]
        for (i, bz) in berths.enumerated() {
            let len = rng.r(11, 19)
            let boat = fishingBoat(length: len, hull: finaleLin(i % 3 == 1 ? 0x2C4F8A : 0xE6E4DC), stripe: finaleLin(i % 3 == 1 ? 0xE6E4DC : (i % 2 == 0 ? 0x2C4F8A : 0xA8302A)), seed: UInt64(i))
            let x = shoreX(bz) + 3.4
            boat.position = SCNVector3(CGFloat(x), CGFloat(seaY), CGFloat(bz))
            boat.eulerAngles.y = CGFloat(townYaw) + (i % 2 == 0 ? 0 : .pi)
            intact.addChildNode(boat)
        }
        world.addChildNode(intact)
        harborIntact = intact
    }

    /// A Japanese coastal fishing boat: white FRP hull with a coloured stripe, wheelhouse aft, mast.
    private func fishingBoat(length: Float, hull: FinaleV3, stripe: FinaleV3, seed: UInt64) -> SCNNode {
        var m = FinaleMesh()
        let k = length / 16
        let st: [(Float, Float, Float, Float)] = [(-8, 1.9, 1.6, -0.9), (-5, 2.2, 1.6, -1.3), (0, 2.25, 1.7, -1.4), (4, 1.8, 1.95, -1.2), (6.6, 0.9, 2.3, -0.6), (8, 0.05, 2.6, 0.4)]
        let scaled = st.map { ($0.0 * k, $0.1 * k, $0.2 * k, $0.3 * k) }
        m.hull(scaled, hull, stripe: stripe, deck: finaleLin(0x8A8C88))
        let white = finaleLin(0xEEEDE8)
        m.box(FinaleV3(-3.6 * k, 2.9 * k, 0), FinaleV3(1.9 * k, 1.1 * k, 1.4 * k), white)
        m.box(FinaleV3(-3.6 * k, 3.6 * k, 0), FinaleV3(1.92 * k, 0.32 * k, 1.42 * k), finaleLin(0x1E2A34))
        m.box(FinaleV3(-3.6 * k, 4.05 * k, 0), FinaleV3(2.1 * k, 0.1 * k, 1.6 * k), white * 0.95)
        m.tube(FinaleV3(-2.6 * k, 4.1 * k, 0), FinaleV3(-2.6 * k, 8.5 * k, 0), 0.07 * k, 0.05 * k, white, segs: 4)
        m.tube(FinaleV3(-2.6 * k, 7.6 * k, -1.2 * k), FinaleV3(-2.6 * k, 7.6 * k, 1.2 * k), 0.04 * k, 0.04 * k, white, segs: 3)
        m.tube(FinaleV3(3.2 * k, 1.7 * k, 0), FinaleV3(3.4 * k, 5.6 * k, 0), 0.06 * k, 0.05 * k, white, segs: 4)
        m.box(FinaleV3(-6.5 * k, 2.1 * k, 0), FinaleV3(0.8 * k, 0.5 * k, 1.2 * k), finaleLin(0x3A6EA0))
        return m.node(vc(0.45, snow: 0.8, doubleSided: true))
    }

    // MARK: - After the wave: the rubble field (built once the wave has come)

    /// Land the wave went over: below the run-up, off the hill, the river, the quay.
    private func wreckable(_ x: Float, _ z: Float) -> Bool {
        if x > shoreX(z) - 2.5 { return false }
        let h = gy(x, z)
        if h > runup - 1.5 || h < -0.4 { return false }
        if abs(z - riverZ(x)) < 9 { return false }
        if x * x + z * z < 74 * 74 { return false }
        if inBuilding(x, z, margin: 1) { return false }
        return true
    }

    /// Footprints of the concrete buildings that stayed standing.
    private func inBuilding(_ x: Float, _ z: Float, margin: Float) -> Bool {
        for b in rcBuildings {
            let dx = x - b.x, dz = z - b.z
            let u = dx * townU.x + dz * townU.y, v = dx * townV.x + dz * townV.y
            if abs(u) < b.L + margin && abs(v) < b.W + margin { return true }
        }
        let cx = x - centerXZ.x, cz = z - centerXZ.y
        let cu = cx * townU.x + cz * townU.y, cv = cx * townV.x + cz * townV.y
        if abs(cu) < 20 + margin && abs(cv) < 9.5 + margin { return true }
        let sx = x - schoolXZ.x, sz = z - schoolXZ.y
        let su = sx * townU.x + sz * townU.y, sv = sx * townV.x + sz * townV.y
        if abs(su) < 35 + margin && abs(sv) < 8.5 + margin { return true }
        if abs(su - 56) < 11 + margin && abs(sv - 4) < 14 + margin { return true }
        return false
    }

    /// How much wreckage ends up where: heaped against the hill and the concrete buildings,
    /// dumped along the inland limit, thin on the waterfront the backwash scoured clean.
    private func debrisDensity(_ x: Float, _ z: Float) -> Float {
        var d: Float = 0.2 + 0.8 * noise.value(x / 70 + 9, z / 70 - 4)
        let r = sqrt(x * x + z * z)
        d += 1.0 * (1 - SK.smoothstep(92, 150, r))
        d += 0.7 * SK.smoothstep(runup - 7, runup - 2, gy(x, z))
        if inBuilding(x, z, margin: 14) { d += 0.8 }
        d *= 0.4 + 0.6 * SK.smoothstep(15, 110, shoreX(z) - x)
        return d
    }

    private func buildRubble() {
        guard rubble == nil else { return }
        let root = SCNNode()
        var found = FinaleMesh(), heap = FinaleMesh(), wood = FinaleMesh(), roofs = FinaleMesh(), cars = FinaleMesh(), steel = FinaleMesh()
        found.reserve(30000); heap.reserve(40000); wood.reserve(40000)
        var rng = FinaleRng(101)
        let woodCols: [UInt32] = [0x9A8060, 0xAE9472, 0x7A6248, 0xB4AA98, 0x8A867C, 0xC2B294, 0x6A5A48, 0xA09080]
        let junkCols: [UInt32] = [0xE0DCD0, 0x3E64A0, 0xB83A30, 0xD0C098, 0x5A7A5A, 0xE0C060, 0x9A9EA2, 0xEEECE6, 0x2E7A9A]
        let roofCols: [UInt32] = [0x454B53, 0x30333A, 0x7A3E2E, 0x8C4A36, 0x3E5A78, 0x8A3A30, 0x4E6A54]
        let concC = finaleLin(0x9A968C)

        // the foundations the houses were torn off, and the bent frames of the steel sheds
        for lot in lots where lot.y < runup - 0.5 {
            if !wreckable(lot.x, lot.z) { continue }
            if lot.big {
                frameRemains(&steel, lot, rng: &rng)
                continue
            }
            if rng.next() < 0.3 { continue }
            foundation(&found, lot, col: concC * rng.r(0.8, 1.05))
        }
        // heaps of broken timber, roofing, furniture and mud
        var piles = 0
        for _ in 0..<2600 {
            if piles >= 260 { break }
            let x = rng.r(-560, 330), z = rng.r(-640, 120)
            if !wreckable(x, z) { continue }
            if rng.next() > debrisDensity(x, z) * 0.55 { continue }
            let near = x * x + z * z < 135 * 135
            pile(&heap, &wood, FinaleV3(x, gy(x, z), z), radius: rng.r(3.5, near ? 10 : 14), height: rng.r(1.0, 3.4), boxes: near, rng: &rng,
                 woodCols: woodCols, junkCols: junkCols)
            piles += 1
        }
        // loose boards, beams, panels and sheets everywhere
        for _ in 0..<12000 {
            let x = rng.r(-560, 330), z = rng.r(-640, 120)
            if !wreckable(x, z) { continue }
            if rng.next() > debrisDensity(x, z) * 0.9 { continue }
            let y = gy(x, z)
            let col = rng.next() < 0.82 ? finaleLin(rng.pick(woodCols)) * rng.r(0.8, 1.15) : finaleLin(rng.pick(junkCols))
            let near = x * x + z * z < 170 * 170
            if near {
                wood.box(FinaleV3(x, y + 0.1, z), FinaleV3(rng.r(0.5, 2.0), rng.r(0.03, 0.1), rng.r(0.08, 0.3)), col, yaw: rng.r(0, 6.28), pitch: rng.r(-0.3, 0.3), roll: rng.r(-0.35, 0.35))
            } else {
                let l = rng.r(1, 4), w = rng.r(0.25, 1.4)
                let yaw = rng.r(0, 6.28), tilt = rng.r(-0.4, 0.4)
                let a = finaleRot(FinaleV3(-l, 0, -w), yaw: yaw, roll: tilt), b = finaleRot(FinaleV3(l, 0, -w), yaw: yaw, roll: tilt)
                let c = finaleRot(FinaleV3(l, 0, w), yaw: yaw, roll: tilt), d = finaleRot(FinaleV3(-l, 0, w), yaw: yaw, roll: tilt)
                let p = FinaleV3(x, y + 0.25, z)
                wood.quad(p + d, p + c, p + b, p + a, col)
            }
        }
        // roofs that came off whole, lying askew on the wreckage
        var roofN = 0
        for _ in 0..<900 {
            if roofN >= 230 { break }
            let x = rng.r(-560, 330), z = rng.r(-640, 120)
            if !wreckable(x, z) { continue }
            if rng.next() > debrisDensity(x, z) * 0.5 { continue }
            var piece = FinaleMesh()
            let L = rng.r(2.5, 5.5), W = rng.r(2.2, 4), rise = rng.r(1.0, 1.8)
            let col = finaleLin(rng.pick(roofCols)) * rng.r(0.8, 1.05)
            if rng.next() < 0.5 {
                piece.hipRoof(FinaleV3(0, 0, 0), halfL: L, halfW: W, rise: rise, over: 0.3, yaw: 0, ridgeK: 1, col)
            } else {
                piece.quad(FinaleV3(-L, 0, W), FinaleV3(L, 0, W), FinaleV3(L, rise, 0), FinaleV3(-L, rise, 0), col)
                piece.quad(FinaleV3(-L, 0, W), FinaleV3(-L, rise, 0), FinaleV3(L, rise, 0), FinaleV3(L, 0, W), col * 0.4)
            }
            roofs.append(piece, at: FinaleV3(x, gy(x, z) + rng.r(0.2, 1.8), z), yaw: rng.r(0, 6.28), pitch: rng.r(-0.35, 0.35), roll: rng.r(-0.45, 0.45))
            roofN += 1
        }
        // whole houses carried off their plots and dumped, tilted, against the hill and each other
        let lowLots = lots.filter { $0.y < runup - 0.5 && !$0.big }
        var houses = 0
        for _ in 0..<400 {
            if houses >= 34 || lowLots.isEmpty { break }
            let x = rng.r(-450, 200), z = rng.r(-600, 60)
            if !wreckable(x, z) || debrisDensity(x, z) < 0.75 { continue }
            var lot = lowLots[Int(rng.next() * Float(lowLots.count - 1))]
            lot.x = 0; lot.z = 0; lot.y = 0; lot.yaw = 0
            var w = FinaleMesh(), r = FinaleMesh()
            addHouse(&w, &r, lot)
            w.append(r)
            let lean = rng.next() < 0.3 ? rng.r(0.5, 1.2) : rng.r(-0.3, 0.3)
            heap.append(w, at: FinaleV3(x, gy(x, z) - rng.r(0.6, 1.8), z), yaw: rng.r(0, 6.28), pitch: rng.r(-0.25, 0.25), roll: lean)
            houses += 1
        }
        // cars, many upside down, some on top of the heaps
        var carN = 0
        for _ in 0..<1200 {
            if carN >= 95 { break }
            let x = rng.r(-560, 330), z = rng.r(-640, 120)
            if !wreckable(x, z) { continue }
            if rng.next() > debrisDensity(x, z) * 0.45 { continue }
            let up = rng.next() < 0.4
            let lift: Float = rng.next() < 0.25 ? rng.r(0.8, 2.2) : 0
            car(&cars, FinaleV3(x, gy(x, z) + lift, z), yaw: rng.r(0, 6.28), pitch: rng.r(-0.3, 0.3), roll: up ? rng.r(-0.3, 0.3) : rng.r(-0.6, 0.6),
                col: finaleLin(rng.pick([0xE8E8E4, 0xD8D8D4, 0xA8ACB0, 0x2A2C30, 0x2E3E66, 0x9A2A26, 0xD8C04A] as [UInt32])) * 0.9, seed: &rng, upside: up)
            carN += 1
        }
        // poles snapped or bent over
        var poleN = 0
        for _ in 0..<600 {
            if poleN >= 34 { break }
            let a = rng.r(0, 640), b: Float = rng.next() < 0.5 ? 20 : 128
            let c = townP(a, b)
            if !wreckable(c.x, c.y) { continue }
            let lean = rng.r(0.35, 1.45), dirA = rng.r(0, 6.28)
            let base = FinaleV3(c.x, gy(c.x, c.y) - 0.3, c.y)
            let len: Float = rng.next() < 0.4 ? rng.r(3, 6) : 11
            let top = base + FinaleV3(sin(lean) * cos(dirA), cos(lean), sin(lean) * sin(dirA)) * len
            steel.tube(base, top, 0.16, 0.12, finaleLin(0x9A968E), segs: 5)
            poleN += 1
        }
        // boats thrown inland
        let boatSpots: [(Float, Float, Float, Float)] = [(-40, -372, 0.7, 17), (44, -112, 2.1, 12), (-140, -300, 1.3, 15), (70, -262, 0.2, 19),
                                                         (165, -175, 2.6, 13), (-95, -205, 1.9, 11), (12, -470, 0.9, 14), (-210, -420, 2.4, 10)]
        for (i, b) in boatSpots.enumerated() {
            let boat = fishingBoat(length: b.3, hull: finaleLin(i % 3 == 1 ? 0x2C4F8A : 0xE6E4DC), stripe: finaleLin(i % 2 == 0 ? 0x2C4F8A : 0xA8302A), seed: UInt64(20 + i))
            let y = gy(b.0, b.1)
            boat.position = SCNVector3(CGFloat(b.0), CGFloat(y + 0.6), CGFloat(b.1))
            boat.eulerAngles = SCNVector3(CGFloat(rng.r(-0.15, 0.15)), CGFloat(b.2), CGFloat(rng.r(0.25, 0.6)))
            root.addChildNode(boat)
        }
        // the fish market's steel frame, its roof sheets torn away
        let mp = FinaleV3(marketXZ.x, gy(marketXZ.x, marketXZ.y), marketXZ.y)
        func M(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { mp + finaleRot(FinaleV3(x, y, z), yaw: townYaw) }
        for i in 0..<9 {
            for sgn in [Float(1), -1] {
                let lean: Float = (i * 7 + Int(sgn + 1)) % 5 == 0 ? 0.7 : 0
                steel.tube(M(-32 + Float(i) * 8, -0.5, 10 * sgn), M(-32 + Float(i) * 8 + lean * 3, 7.5 - lean * 2, 10 * sgn), 0.25, 0.25, finaleLin(0x6E6A64), segs: 5)
            }
            if i % 3 != 1 { steel.tube(M(-32 + Float(i) * 8, 7.5, -10), M(-32 + Float(i) * 8, 9.6, 0), 0.15, 0.15, finaleLin(0x6E6A64), segs: 4) }
        }
        steel.quad(M(-24, 7.6, -10.5), M(-8, 7.6, -10.5), M(-8, 9.5, -0.5), M(-24, 9.5, -0.5), finaleLin(0x6E7E8A))
        steel.tube(M(-32, 7.5, 10), M(32, 7.5, 10), 0.18, 0.18, finaleLin(0x6E6A64), segs: 4)
        // an oil tank from the harbour, rolled inland and crushed
        let tp = FinaleV3(150, gy(150, -150), -150)
        steel.tube(tp + FinaleV3(-4.5, 4.2, 0), tp + FinaleV3(4.5, 4.6, 1.5), 4.6, 4.2, finaleLin(0xD2CEC4), segs: 14, cap: true)
        steel.tube(tp + FinaleV3(-4.6, 4.2, 0), tp + FinaleV3(-2.8, 4.3, 0.3), 4.65, 4.65, finaleLin(0x3A2E26), segs: 14)
        // the one pine left standing of the row along the harbour road
        let pp = townP(28, 3)
        let py = gy(pp.x, pp.y)
        wood.tube(FinaleV3(pp.x, py - 0.5, pp.y), FinaleV3(pp.x + 0.5, py + 25, pp.y + 0.3), 0.4, 0.22, finaleLin(0x5A4636), segs: 6)
        heap.blob(FinaleV3(pp.x + 0.6, py + 25.5, pp.y + 0.3), FinaleV3(3.2, 1.8, 2.8), finaleLin(0x2A3C24), noise, seed: 4, jitter: 0.35, rings: 4, segs: 8)
        // carpets of splintered wood and scraps (a textured sheet laid on the ground)
        var carpet = FinaleMesh()
        carpet.withUV = true
        var cn = 0
        for _ in 0..<1600 {
            if cn >= 320 { break }
            let x = rng.r(-560, 330), z = rng.r(-640, 120)
            if !wreckable(x, z) { continue }
            if rng.next() > debrisDensity(x, z) * 0.7 { continue }
            let w = rng.r(8, 22), asp = rng.r(0.45, 0.95), yaw = rng.r(0, 6.28)
            let k = UInt32(carpet.pts.count)
            func put(_ px: Float, _ pz: Float) {
                carpet.pts.append(FinaleV3(px, gy(px, pz) + 0.35, pz)); carpet.cols.append(FinaleV3(1, 1, 1)); carpet.uvs.append(SIMD2(px / 12, pz / 12))
            }
            put(x, z)
            let segs = 12
            for j in 0..<segs {
                let a = Float(j) / Float(segs) * 2 * .pi
                let rr = w * (0.5 + 0.5 * noise.value(cos(a) * 1.7 + x * 0.02, sin(a) * 1.7 + z * 0.02))
                let q = finaleRot(FinaleV3(cos(a) * rr, 0, sin(a) * rr * asp), yaw: yaw)
                put(x + q.x, z + q.z)
            }
            for j in 0..<UInt32(segs) { carpet.idx += [k, k + 1 + (j + 1) % UInt32(segs), k + 1 + j] }
            cn += 1
        }
        let cm = SK.mat(.white, roughness: 0.95)
        let cimg = FinaleTex.wreckMat()
        cm.diffuse.contents = cimg
        cm.transparent.contents = cimg
        cm.transparencyMode = .aOne
        for pr in [cm.diffuse, cm.transparent] { pr.wrapS = .repeat; pr.wrapT = .repeat; pr.mipFilter = .linear; pr.maxAnisotropy = 8 }
        cm.writesToDepthBuffer = false
        cm.shaderModifiers = [.surface: finaleSnowShader]
        cm.setValue(NSNumber(value: 0.0), forKey: "snowAmt")
        snowMats.append((cm, 0.5))
        root.addChildNode(carpet.node(cm, shadow: false))
        root.addChildNode(found.node(vc(0.9, snow: 0.7)))
        root.addChildNode(heap.node(vc(0.95, snow: 0.55)))
        root.addChildNode(wood.node(vc(0.9, snow: 0.5, doubleSided: true)))
        root.addChildNode(roofs.node(vc(0.6, snow: 0.8, doubleSided: true)))
        root.addChildNode(cars.node(vc(0.5, snow: 0.6)))
        root.addChildNode(steel.node(vc(0.6, snow: 0.4)))
        world.addChildNode(root)
        rubble = root
    }

    private func foundation(_ m: inout FinaleMesh, _ lot: FinaleLot, col: FinaleV3) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { FinaleV3(lot.x, lot.y, lot.z) + finaleRot(FinaleV3(x, y, z), yaw: lot.yaw) }
        let L = lot.L, W = lot.W, t: Float = 0.09, h: Float = 0.42
        func wall(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
            let dx = x1 - x0, dz = z1 - z0
            let l = max(0.01, sqrt(dx * dx + dz * dz))
            let nx = -dz / l * t, nz = dx / l * t
            let a = P(x0 - nx, h, z0 - nz), b = P(x1 - nx, h, z1 - nz), c = P(x1 + nx, h, z1 + nz), d = P(x0 + nx, h, z0 + nz)
            m.quad(a, d, c, b, col)
            m.quad(P(x0 + nx, -0.2, z0 + nz), P(x1 + nx, -0.2, z1 + nz), c, d, col * 0.82)
            m.quad(P(x1 - nx, -0.2, z1 - nz), P(x0 - nx, -0.2, z0 - nz), a, b, col * 0.82)
        }
        wall(-L, -W, L, -W); wall(L, -W, L, W); wall(L, W, -L, W); wall(-L, W, -L, -W)
        wall(-L * 0.15, -W, -L * 0.15, W)
        if lot.seed % 3 == 0 { wall(-L * 0.15, W * 0.2, L, W * 0.2) }
    }

    private func frameRemains(_ m: inout FinaleMesh, _ lot: FinaleLot, rng: inout FinaleRng) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { FinaleV3(lot.x, lot.y, lot.z) + finaleRot(FinaleV3(x, y, z), yaw: lot.yaw) }
        let steelC = finaleLin(0x5E5650), L = lot.L, W = lot.W, H = lot.H
        let n = max(3, Int(L / 4))
        var tops: [FinaleV3] = []
        for i in 0...n {
            let x = -L + Float(i) * 2 * L / Float(n)
            for z in [-W, W] {
                if rng.next() < 0.2 { continue }
                let lean = rng.next() < 0.35 ? rng.r(0.15, 0.6) : rng.r(-0.04, 0.04)
                let a = P(x, -0.3, z)
                let top = a + finaleRot(FinaleV3(lean * H * 0.6, H, 0), yaw: lot.yaw + rng.r(0, 6.28) * 0)
                m.box((a + top) * 0.5, FinaleV3(0.16, H / 2, 0.16), steelC, yaw: lot.yaw, roll: lean)
                tops.append(top)
            }
        }
        // a few roof beams still in place, a sheet of cladding hanging off
        if tops.count > 3 {
            for k in stride(from: 0, to: tops.count - 2, by: 2) where rng.next() < 0.6 {
                m.tube(tops[k], tops[k + 2], 0.12, 0.12, steelC, segs: 4)
            }
        }
        m.quad(P(-L, H * 0.3, W + 0.1), P(-L + 4, H * 0.2, W + 0.6), P(-L + 4, H, W + 0.1), P(-L, H, W + 0.1), lot.wall * 0.85)
        foundation(&m, lot, col: finaleLin(0xA8A49A))
    }

    /// A heap of wreckage: boards, beams, panels and scraps jumbled over a dark core.
    private func pile(_ heap: inout FinaleMesh, _ wood: inout FinaleMesh, _ p: FinaleV3, radius: Float, height: Float, boxes: Bool, rng: inout FinaleRng,
                      woodCols: [UInt32], junkCols: [UInt32]) {
        let asp = rng.r(0.55, 1.0), yaw0 = rng.r(0, 6.28)
        heap.blob(p - FinaleV3(0, height * 0.3, 0), FinaleV3(radius * 0.85, height * 0.95, radius * 0.85 * asp), finaleLin(0x4A4036) * rng.r(0.8, 1.1), noise,
                  seed: p.x * 0.1 + p.z, jitter: 0.3, rings: 4, segs: 8, under: 0.7, vary: 0.4)
        let n = Int(radius * radius * (boxes ? 0.6 : 0.62)) + 6
        for _ in 0..<n {
            let a = rng.r(0, 6.28), d = sqrt(rng.next()) * radius
            let local = finaleRot(FinaleV3(cos(a) * d, 0, sin(a) * d * asp), yaw: yaw0)
            let top = height * max(0, 1 - (d * d) / (radius * radius))
            let q = p + local + FinaleV3(0, top * rng.r(0.55, 1.0), 0)
            let c = rng.next() < 0.8 ? finaleLin(rng.pick(woodCols)) * rng.r(0.75, 1.15) : finaleLin(rng.pick(junkCols)) * rng.r(0.8, 1.0)
            if boxes {
                wood.box(q, FinaleV3(rng.r(0.6, 2.4), rng.r(0.04, 0.14), rng.r(0.08, 0.4)), c, yaw: rng.r(0, 6.28), pitch: rng.r(-0.7, 0.7), roll: rng.r(-0.8, 0.8))
            } else {
                let l = rng.r(0.8, 2.6), w = rng.r(0.2, 1.0), yaw = rng.r(0, 6.28), tilt = rng.r(-0.9, 0.9), tilt2 = rng.r(-0.5, 0.5)
                let a1 = finaleRot(FinaleV3(-l, 0, -w), yaw: yaw, pitch: tilt2, roll: tilt), b1 = finaleRot(FinaleV3(l, 0, -w), yaw: yaw, pitch: tilt2, roll: tilt)
                let c1 = finaleRot(FinaleV3(l, 0, w), yaw: yaw, pitch: tilt2, roll: tilt), d1 = finaleRot(FinaleV3(-l, 0, w), yaw: yaw, pitch: tilt2, roll: tilt)
                wood.quad(q + d1, q + c1, q + b1, q + a1, c)
            }
        }
    }

    // MARK: Wreckage afloat (while the water is high)

    private func buildFloating() {
        guard floatHigh == nil else { return }
        var mats = FinaleMesh(), roofs = FinaleMesh(), junk = FinaleMesh()
        mats.withUV = true
        var rng = FinaleRng(131)
        let roofCols: [UInt32] = [0x454B53, 0x30333A, 0x7A3E2E, 0x8C4A36, 0x3E5A78, 0x8A3A30, 0x4E6A54, 0x5E4E40]
        let woodCols: [UInt32] = [0x7A6248, 0x8E7656, 0x5E4C3A, 0x9C9282, 0x6E6A62, 0xA89A7E]
        // rafts of matted wreckage (a textured sheet), thickest in the town, drifting out into the bay
        for _ in 0..<110 {
            let inTown = rng.next() < 0.7
            let x = inTown ? rng.r(-450, 170) : rng.r(150, 750), z = inTown ? rng.r(-620, 60) : rng.r(-650, 50)
            let w = rng.r(18, inTown ? 70 : 45), asp = rng.r(0.35, 0.9), yaw = rng.r(0, 6.28)
            let k = UInt32(mats.pts.count)
            mats.pts.append(FinaleV3(x, 0.06, z)); mats.cols.append(FinaleV3(1, 1, 1)); mats.uvs.append(SIMD2(x / 16, z / 16))
            let segs = 14
            for j in 0..<segs {
                let a = Float(j) / Float(segs) * 2 * .pi
                let rr = w * (0.55 + 0.45 * noise.value(cos(a) * 1.6 + x * 0.01, sin(a) * 1.6 + z * 0.01))
                let q = finaleRot(FinaleV3(cos(a) * rr, 0, sin(a) * rr * asp), yaw: yaw)
                mats.pts.append(FinaleV3(x + q.x, 0.06, z + q.z)); mats.cols.append(FinaleV3(1, 1, 1)); mats.uvs.append(SIMD2((x + q.x) / 16, (z + q.z) / 16))
            }
            for j in 0..<UInt32(segs) { mats.idx += [k, k + 1 + (j + 1) % UInt32(segs), k + 1 + j] }
        }
        // whole roofs and houses afloat, boards, cars, a capsized boat
        for _ in 0..<60 {
            let x = rng.r(-420, 200), z = rng.r(-600, 40)
            let L = rng.r(3.5, 5.5), W = rng.r(3, 4.5), rise = rng.r(1.4, 2.0)
            var piece = FinaleMesh()
            let col = finaleLin(rng.pick(roofCols)) * rng.r(0.85, 1.05)
            piece.hipRoof(FinaleV3(0, 0, 0), halfL: L, halfW: W, rise: rise, over: 0.4, yaw: 0, ridgeK: 1, col)
            if rng.next() < 0.3 { piece.box(FinaleV3(0, -1.2, 0), FinaleV3(L, 1.25, W), finaleLin(0xC9BEA8) * rng.r(0.8, 1.0)) }
            roofs.append(piece, at: FinaleV3(x, rng.r(-0.2, 0.4), z), yaw: rng.r(0, 6.28), pitch: rng.r(-0.15, 0.15), roll: rng.r(-0.2, 0.2))
        }
        for _ in 0..<2600 {
            let near = rng.next() < 0.5
            let a = rng.r(0, 6.28), d = rng.r(0, 1)
            let x = near ? sin(a) * (95 + d * 70) : rng.r(-450, 400), z = near ? cos(a) * (95 + d * 70) : rng.r(-620, 60)
            let l = rng.r(0.8, 3.5), w = rng.r(0.15, 0.8), yaw = rng.r(0, 6.28)
            let col = finaleLin(rng.pick(woodCols)) * rng.r(0.75, 1.1)
            let p = FinaleV3(x, 0.08, z)
            let q0 = finaleRot(FinaleV3(-l, 0, -w), yaw: yaw), q1 = finaleRot(FinaleV3(l, 0, -w), yaw: yaw), q2 = finaleRot(FinaleV3(l, 0, w), yaw: yaw), q3 = finaleRot(FinaleV3(-l, 0, w), yaw: yaw)
            junk.quad(p + q3, p + q2, p + q1, p + q0, col)
        }
        var crng = rng
        for _ in 0..<26 {
            let x = rng.r(-400, 220), z = rng.r(-600, 40)
            car(&junk, FinaleV3(x, -0.9, z), yaw: rng.r(0, 6.28), pitch: rng.r(-0.2, 0.2), roll: rng.r(-0.3, 0.3), col: finaleLin(rng.pick([0xE8E8E4, 0xA8ACB0, 0x2A2C30, 0x9A2A26] as [UInt32])), seed: &crng, upside: rng.next() < 0.3)
        }
        let mm = SK.mat(.white, roughness: 0.95, doubleSided: false)
        let img = FinaleTex.wreckMat()
        mm.diffuse.contents = img
        mm.transparent.contents = img
        mm.transparencyMode = .aOne
        for p in [mm.diffuse, mm.transparent] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8 }
        mm.writesToDepthBuffer = false
        let high = SCNNode()
        high.addChildNode(mats.node(mm, shadow: false))
        high.addChildNode(roofs.node(vc(0.6, snow: 0.8, doubleSided: true)))
        floatRoot.addChildNode(high)
        let mid = SCNNode()
        mid.addChildNode(junk.node(vc(0.85, snow: 0.4, doubleSided: true)))
        let capsized = fishingBoat(length: 15, hull: finaleLin(0xE6E4DC), stripe: finaleLin(0x2C4F8A), seed: 9)
        capsized.position = SCNVector3(250, 0.9, -330)
        capsized.eulerAngles = SCNVector3(0, 0.8, CGFloat.pi)
        mid.addChildNode(capsized)
        floatRoot.addChildNode(mid)
        floatHigh = high
        floatMid = mid
    }

    // MARK: - Fires: in the wreckage (town_fire) and climbing the hill (hill_fire)

    /// Where the wreckage burns, roughly in the order the fires appear (the harbour's fuel first).
    private let fireSpots: [(Float, Float, Float)] = [
        (182, -212, 2.6), (150, -152, 2.4), (118, -302, 2.0), (62, -182, 2.2), (-28, -252, 1.8), (96, -382, 2.0), (-112, -330, 1.6),
        (18, -128, 1.5), (-62, -470, 1.9), (196, -420, 1.7), (-172, -232, 1.6), (-18, -362, 2.1), (42, -300, 1.5), (-150, -482, 1.7),
        (112, -472, 1.6), (-232, -380, 1.5), (-82, -158, 1.4), (240, -330, 1.8), (-262, -290, 1.4), (22, -540, 1.6), (-205, -140, 1.3),
        (70, -560, 1.5)
    ]

    private func buildFires() {
        for (i, f) in fireSpots.enumerated() {
            let n = SCNNode()
            n.position = SCNVector3(CGFloat(f.0), CGFloat(gy(f.0, f.1)), CGFloat(f.1))
            let flame = bigFlame(f.2)
            let glowS = fireGlow(f.2)
            let smoke = bigSmoke(f.2, dark: true)
            let fn = SCNNode(); fn.position.y = 0.8; n.addChildNode(fn)
            fn.addParticleSystem(flame)
            fn.addParticleSystem(glowS)
            let sn = SCNNode(); sn.position.y = CGFloat(2 + f.2); n.addChildNode(sn)
            sn.addParticleSystem(smoke)
            var e = FinaleMesh()
            var rng = FinaleRng(UInt64(500 + i))
            for _ in 0..<5 {
                e.blob(FinaleV3(rng.r(-2, 2) * f.2, 0.1, rng.r(-2, 2) * f.2), FinaleV3(f.2 * 1.3, 0.35, f.2 * 1.0), FinaleV3(1, 1, 1), noise, seed: Float(i), jitter: 0.3, rings: 3, segs: 7, under: 1, vary: 0.4)
            }
            let ember = e.node(glow(SK.rgb(0xFF5A14), 1.6), shadow: false)
            n.addChildNode(ember)
            n.isHidden = true
            world.addChildNode(n)
            townFires.append(FinaleFireSite(node: n, flame: flame, glow: glowS, smoke: smoke, ember: ember, x: f.0, z: f.1, size: f.2))
        }
        // the fire's glow on its surroundings: a few big lights that follow the strongest fires
        for _ in 0..<4 {
            let l = SCNLight()
            l.type = .omni
            l.color = SK.rgb(0xFF8A3A)
            l.intensity = 0
            l.attenuationStartDistance = 0
            l.attenuationEndDistance = 120
            l.attenuationFalloffExponent = 1.6
            l.castsShadow = false
            let ln = SCNNode()
            ln.light = l
            ln.isHidden = true
            world.addChildNode(ln)
            fireLights.append(ln)
        }
        // a broad orange cast over everything facing the burning town
        let wide = SCNLight()
        wide.type = .omni
        wide.color = SK.rgb(0xFF7A30)
        wide.intensity = 0
        wide.attenuationStartDistance = 0
        wide.attenuationEndDistance = 900
        wide.attenuationFalloffExponent = 1.0
        wide.castsShadow = false
        let wn = SCNNode()
        wn.light = wide
        wn.position = SCNVector3(30, 60, -320)
        world.addChildNode(wn)
        townGlowLight = wn
        // the hill fire: a chain of fires along the north slope, moved up as the front climbs
        for k in 0..<10 {
            let n = SCNNode()
            let size: Float = 1.0 + Float(k % 3) * 0.25
            let flame = bigFlame(size)
            flame.particleColor = SK.rgb(0xFF8A30)
            let glowS = fireGlow(size)
            let smoke = bigSmoke(size * 0.8, dark: false)
            let fn = SCNNode(); fn.position.y = 1.2; n.addChildNode(fn)
            fn.addParticleSystem(flame)
            fn.addParticleSystem(glowS)
            let sn = SCNNode(); sn.position.y = 4; n.addChildNode(sn)
            sn.addParticleSystem(smoke)
            n.isHidden = true
            world.addChildNode(n)
            hillFires.append(FinaleFireSite(node: n, flame: flame, glow: glowS, smoke: smoke, ember: nil, x: 0, z: 0, size: size))
        }
    }

    private func bigFlame(_ size: Float) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(50 + 40 * size)
        p.particleLifeSpan = 1.2
        p.particleLifeSpanVariation = 0.4
        p.emitterShape = SCNBox(width: CGFloat(size * 3.2), height: 0.6, length: CGFloat(size * 2.4), chamferRadius: 0)
        p.birthLocation = .volume
        p.particleImage = SK.dotImage(size: 64, hardness: 0.25)
        p.particleSize = CGFloat(1.0 * size)
        p.particleSizeVariation = CGFloat(0.45 * size)
        p.particleColor = SK.rgb(0xFF7424)
        p.particleColorVariation = SCNVector4(0.04, 0.14, 0.1, 0)
        p.particleVelocity = CGFloat(2.4 + size * 0.7)
        p.particleVelocityVariation = 1.1
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 16
        p.blendMode = .additive
        p.isLightingEnabled = false
        p.warmupDuration = 2
        let fade = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0.15, 1, 0.55, 0] as [NSNumber]
            a.keyTimes = [0, 0.15, 0.6, 1] as [NSNumber]
            return a
        }())
        let shrink = SCNParticlePropertyController(animation: {
            let a = CABasicAnimation()
            a.fromValue = 1.0
            a.toValue = 0.35
            return a
        }())
        p.propertyControllers = [.opacity: fade, .size: shrink]
        return p
    }

    /// A soft orange haze above the flames (lights the smoke from below at night).
    private func fireGlow(_ size: Float) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(5 + 3 * size)
        p.particleLifeSpan = 3
        p.emitterShape = SCNSphere(radius: CGFloat(size * 1.5))
        p.particleImage = SK.dotImage(size: 64, hardness: 0.02)
        p.particleSize = CGFloat(3.6 * size)
        p.particleColor = SK.rgb(0xFF6A20).withAlphaComponent(0.09)
        p.particleVelocity = 2.5
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 25
        p.blendMode = .additive
        p.isLightingEnabled = false
        p.warmupDuration = 3
        let grow = SCNParticlePropertyController(animation: {
            let a = CABasicAnimation()
            a.fromValue = 0.8
            a.toValue = 2.2
            return a
        }())
        p.propertyControllers = [.size: grow]
        return p
    }

    /// A smoke column: thick and dark low down, spreading and paling as it climbs and leans downwind.
    private func bigSmoke(_ size: Float, dark: Bool) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = CGFloat(6 + size * 3)
        p.particleLifeSpan = 24
        p.particleLifeSpanVariation = 5
        p.emitterShape = SCNSphere(radius: CGFloat(size * 1.1))
        p.birthLocation = .volume
        p.particleImage = FinaleTex.puff()
        p.particleSize = CGFloat(3.0 + size * 1.5)
        p.particleSizeVariation = CGFloat(size * 0.8)
        p.particleColor = NSColor(white: 1, alpha: 1)
        p.particleColorVariation = SCNVector4(0, 0, 0.05, 0.08)
        p.particleVelocity = CGFloat(2.6 + size * 0.35)
        p.particleVelocityVariation = 1.2
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 6
        p.acceleration = SCNVector3(0.35, 0.02, 0.1)
        p.particleAngleVariation = 180
        p.particleAngularVelocityVariation = 12
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.warmupDuration = 25
        p.propertyControllers = smokeControllers(dark: dark, night: false)
        return p
    }

    /// Size, opacity and colour over a smoke particle's life (by night only the fire-lit underside shows).
    private func smokeControllers(dark: Bool, night: Bool) -> [SCNParticleSystem.ParticleProperty: SCNParticlePropertyController] {
        let grow = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0.7, 1.6, 3.0, 4.2] as [NSNumber]
            a.keyTimes = [0, 0.15, 0.6, 1] as [NSNumber]
            return a
        }())
        let fade = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0, 1, 0.6, 0] as [NSNumber]
            a.keyTimes = [0, 0.06, 0.5, 1] as [NSNumber]
            return a
        }())
        func c(_ hex: UInt32, _ a: CGFloat) -> NSColor { SK.rgb(hex).withAlphaComponent(a) }
        let cols: [NSColor]
        if night {
            cols = dark ? [c(0x8A4A26, 0.45), c(0x4A2A1C, 0.3), c(0x1E1612, 0.15), c(0x100E0C, 0.05)]
                        : [c(0x9A6A4A, 0.35), c(0x4A3A30, 0.2), c(0x201A16, 0.08), c(0x100E0C, 0.03)]
        } else {
            cols = dark ? [c(0x1E1A16, 0.5), c(0x34302C, 0.36), c(0x5E5A56, 0.16), c(0x8A8884, 0.05)]
                        : [c(0x8A8680, 0.36), c(0xA8A6A2, 0.26), c(0xBEBCB8, 0.14), c(0xC8C6C2, 0.04)]
        }
        let tint = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = cols
            a.keyTimes = [0, 0.2, 0.6, 1] as [NSNumber]
            return a
        }())
        return [.size: grow, .opacity: fade, .color: tint]
    }

    /// Radius on the hill's flank where its surface stands at height `y` (inverse of the smoothstep profile).
    private func hillRadius(atHeight y: Float) -> Float {
        let v = max(0, min(1, 1 - y / topY))
        var lo: Float = 0, hi: Float = 1
        for _ in 0..<18 {
            let t = (lo + hi) / 2
            if t * t * (3 - 2 * t) < v { lo = t } else { hi = t }
        }
        return plateauR + (hillR - plateauR) * (lo + hi) / 2
    }

    private func applyFires(_ s: SceneState, waterY: Float) {
        let hit = s.has("wave_hit")
        let tf = hit ? Float(max(0, min(100, s.v("town_fire", 0)))) : 0
        let night = Float(darkness) * (0.35 + 0.65 * nightK(s))
        let wind = Float(min(60, s.wind))
        let precip = Float(s.precip)
        let active = tf < 2 ? 0 : min(townFires.count, Int((Double(tf) / 100 * Double(townFires.count) + 1.5).rounded(.down)))
        let k = 0.55 + 0.45 * tf / 100
        var lit: [(FinaleFireSite, Float)] = []
        for (i, f) in townFires.enumerated() {
            let on = i < active
            f.node.isHidden = !on
            guard on else { continue }
            let g = gy(f.x, f.z)
            let y = max(g + 0.8, waterY + 0.3)
            f.node.position.y = CGFloat(y)
            f.ember?.isHidden = waterY > g + 0.5
            let sz = f.size * k * (1 - 0.25 * min(1, precip))
            f.flame.birthRate = CGFloat(50 + 40 * sz)
            f.flame.particleSize = CGFloat(1.0 * sz) * (0.8 + 0.4 * CGFloat(night))
            f.flame.particleColor = SK.rgb(0xFF7424).withAlphaComponent(CGFloat(0.45 + 0.55 * night))
            f.glow.birthRate = night > 0.4 ? CGFloat(5 + 3 * sz) : 0
            f.smoke.birthRate = i % 3 == 2 ? CGFloat(1.5 + sz) : CGFloat(5 + sz * 3)
            f.smoke.acceleration = SCNVector3(CGFloat(0.04 + wind * 0.02), 0.02, CGFloat(0.02 + wind * 0.005))
            f.smoke.propertyControllers = night > 0.5 ? smokeNightDark : smokeDayDark
            lit.append((f, sz))
        }
        lit.sort { $0.1 > $1.1 }
        for (i, l) in fireLights.enumerated() {
            if i < lit.count && night > 0.3 {
                let f = lit[i].0
                l.isHidden = false
                l.position = SCNVector3(f.node.position.x, f.node.position.y + 6, f.node.position.z)
                l.light?.intensity = CGFloat(1400 * lit[i].1 * night)
            } else {
                l.isHidden = true
            }
        }
        townGlowLight?.light?.intensity = CGFloat(tf / 100 * 900 * night)

        // the hill fire: a front climbing the north slope; burnt ground and trees below it
        let hf = Float(max(0, min(100, s.v("hill_fire", 0))))
        let fled = s.has("fled_fire")
        let front: Float = hf < 12 ? -100 : 2 + (topY - 3) * (hf - 12) / 88
        var burnt: Float = front
        if s.has("fire_close_sched") || s.happened("fire_close") { burnt = max(burnt, 2 + (topY - 3) * 43 / 88) }
        if fled { burnt = topY + 2 }
        terrainMat?.setValue(NSNumber(value: Double(burnt < 0 ? -100 : burnt)), forKey: "burnY")
        for b in hillBands {
            let isBurnt = burnt > b.2 + 1.5
            b.0.isHidden = isBurnt
            b.1.isHidden = !isBurnt
        }
        let cut = s.project("firebreak")
        for (i, b) in breakTrees.enumerated() {
            let isCut = Double(i) < cut * 8 - 0.01
            let isBurnt = burnt > breakLo + 1.5
            b.0.isHidden = isCut || isBurnt
            b.1.isHidden = isCut || !isBurnt
        }
        southTrees?.0.isHidden = fled
        southTrees?.1.isHidden = !fled
        lowTrees?.0.isHidden = hit
        lowTrees?.1.isHidden = !hit
        for (k, f) in hillFires.enumerated() {
            let on = front > 0 && Double(k) < 3 + Double(hf) / 100 * 7
            f.node.isHidden = !on
            guard on else { continue }
            let a = breakA0 + (breakA1 - breakA0) * (Float(k) + 0.5) / Float(hillFires.count)
            let yf = min(topY - 1.5, front + Float(k % 3) * 1.2)
            let r = hillRadius(atHeight: yf)
            let x = cos(a) * r, z = sin(a) * r
            f.node.position = SCNVector3(CGFloat(x), CGFloat(gy(x, z)), CGFloat(z))
            f.flame.particleColor = SK.rgb(0xFF8A30).withAlphaComponent(CGFloat(0.5 + 0.5 * night))
            f.glow.birthRate = night > 0.4 ? 8 : 0
            f.smoke.acceleration = SCNVector3(CGFloat(0.05 + wind * 0.02), 0.02, CGFloat(0.02 + wind * 0.006))
            f.smoke.propertyControllers = night > 0.5 ? smokeNightLight : smokeDayLight
        }
    }

    // MARK: - Weather: "snow" always falls as snow (the coast hovers around 0 °C), sleet is both

    private var sleetKey = ""

    override func updateWeather(_ s: SceneState) {
        var w = s
        if s.weather == "snow" || s.weather == "sleet" { w.temp = min(s.temp, -1) }
        if s.weather == "sleet" { w.precip = min(s.precip, 1.4) }
        super.updateWeather(w)
        let key = "\(s.weather)|\(Int(s.wind / 10))|\(Int(darkness * 3))"
        guard key != sleetKey else { return }
        sleetKey = key
        weatherNode.childNode(withName: "sleet", recursively: false)?.removeFromParentNode()
        if s.weather == "sleet" {
            let rain = SK.rain(intensity: 0.6, wind: s.wind, area: weatherArea)
            rain.particleColor = NSColor(white: CGFloat(0.85 - 0.45 * darkness), alpha: CGFloat(0.35 - 0.2 * darkness))
            let n = SCNNode()
            n.name = "sleet"
            n.addParticleSystem(rain)
            weatherNode.addChildNode(n)
        }
    }

    /// 0 in daylight … 1 at night, from the sun's height (not dimmed by overcast like `darkness`).
    private func nightK(_ s: SceneState) -> Float {
        SK.smoothstep(5, -5, Float(s.sunElevation(peak: sunPeak)))
    }

    // MARK: - The sky: the physical sea sky by day, our own night sky (stars, the glow of the fires)

    private var skyKey2 = ""
    private var skyImage2: Any?

    override func updateEnvironment(_ s: SceneState) {
        super.updateEnvironment(s)               // lights, fog and weather (skyStyle .none: no sky of its own)
        let elev = s.sunElevation(peak: sunPeak)
        let overcast = max(0, min(1, (1 - s.sun) * 1.15 + s.precip * 0.2))
        let tf = s.has("wave_hit") ? max(0, min(100, s.v("town_fire", 0))) : 0
        let hf = max(0, min(100, s.v("hill_fire", 0)))
        let fire = min(1, tf / 80 + hf / 200)
        let night = Double(nightK(s)) * darkness
        let k = (fire > 0.05 && night > 0.3) ? fire * min(1, (night - 0.3) / 0.4) : 0
        let ours = k > 0 || elev < -7
        let key = ours ? "n|\(Int(k * 8))|\(Int(overcast * 4))" : "d|\(Int((elev / 2).rounded()))|\(Int((overcast * 6).rounded()))"
        if key != skyKey2 || skyImage2 == nil {
            skyKey2 = key
            skyImage2 = ours ? finaleGlowSky(strength: k, overcast: overcast)
                             : SK.skyImage(style: .sea, sunElevationDeg: elev, overcast: overcast, azimuthDeg: sunAzimuth)
        }
        scene.background.contents = skyImage2
        scene.lightingEnvironment.contents = skyImage2
        if k > 0 {
            // the smoke and low cloud over the town glow: warm the fog
            let warm = SK.rgb(0x3A1C0E)
            scene.fogColor = nightColor.blended(withFraction: CGFloat(k) * (0.55 + 0.35 * CGFloat(overcast)), of: warm) ?? nightColor
        }
    }

    /// Night sky (equirectangular): deep blue to black, stars on clear nights, and the glow of the
    /// fires low over the town (toward the north-east). Small when overcast: no stars to resolve.
    private func finaleGlowSky(strength k: Double, overcast: Double) -> NSImage {
        let stars = overcast < 0.6
        let w = stars ? 2048 : 512, h = w / 2
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var s: UInt64 = 5
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        var glowRow = [Double](repeating: 0, count: w)
        for x in 0..<w {
            let lon = Double(x) / Double(w) * 2 * Double.pi            // longitude 0 at −z; the town is toward −z, +x
            let toTown = 0.5 + 0.5 * cos(lon - 0.55)
            glowRow[x] = 0.25 + 0.75 * toTown * toTown
        }
        let bandW = 0.07 + 0.1 * overcast
        px.withUnsafeMutableBufferPointer { pb in
            for y in 0..<h {
                let t = Double(y) / Double(h)                        // 0 zenith … 0.5 horizon … 1 nadir
                let up = max(0, 0.5 - t) * 2
                let br = 0.012 + 0.02 * (1 - up), bg = 0.014 + 0.018 * (1 - up), bb = 0.026 + 0.022 * (1 - up)
                let d = (t - 0.5) / bandW
                let rowGlow = k * (exp(-d * d) * (0.8 + 0.6 * overcast) + 0.25 * overcast * (1 - up))
                for x in 0..<w {
                    let gl = rowGlow * glowRow[x]
                    let i = (y * w + x) * 4
                    pb[i] = UInt8(min(255, (br + 0.55 * gl) * 255))
                    pb[i + 1] = UInt8(min(255, (bg + 0.2 * gl) * 255))
                    pb[i + 2] = UInt8(min(255, (bb + 0.06 * gl) * 255))
                }
            }
            if stars {
                for _ in 0..<4500 {
                    let x = Int(rnd() * Double(w)), y = Int(pow(rnd(), 1.15) * Double(h) * 0.48)
                    let haze = Double(y) / (Double(h) * 0.5)
                    let b = (50 + 190 * pow(rnd(), 3)) * (1 - 0.6 * haze) * (1 - 0.8 * k)
                    let i = (y * w + x) * 4
                    pb[i] = UInt8(min(255, Double(pb[i]) + b)); pb[i + 1] = UInt8(min(255, Double(pb[i + 1]) + b * 0.97)); pb[i + 2] = UInt8(min(255, Double(pb[i + 2]) + b))
                }
            }
        }
        return SK.image(from: px, size: w, height: h)
    }

    // MARK: - Signals: SOS, smoke and flag, radio antenna and torch

    /// Board centres along the strokes of S O S laid in front of the hall (letters 3.6 × 5.5 m,
    /// their tops toward the town so they read from the camera and from the air).
    private func sosStrokes() -> [(SIMD2<Float>, SIMD2<Float>)] {
        let w: Float = 4.0, h: Float = 6.4, gap: Float = 1.2, x0: Float = -5.6, zb: Float = -13.6
        func P(_ letter: Int, _ u: Float, _ v: Float) -> SIMD2<Float> { SIMD2(x0 + Float(letter) * (w + gap) + u, zb - v) }
        var out: [(SIMD2<Float>, SIMD2<Float>)] = []
        for (i, ch) in ["S", "O", "S"].enumerated() {
            if ch == "O" {
                out += [(P(i, 0, 0), P(i, w, 0)), (P(i, w, 0), P(i, w, h)), (P(i, w, h), P(i, 0, h)), (P(i, 0, h), P(i, 0, 0))]
            } else {
                out += [(P(i, w, h), P(i, 0, h)), (P(i, 0, h), P(i, 0, h / 2)), (P(i, 0, h / 2), P(i, w, h / 2)), (P(i, w, h / 2), P(i, w, 0)), (P(i, w, 0), P(i, 0, 0))]
            }
        }
        return out
    }

    private func buildSignals() {
        let T = topY
        var rng = FinaleRng(141)
        let whites: [UInt32] = [0xECEAE4, 0xE2E0D8, 0xF0EEE8, 0xD8DCE0, 0xE8E2D2]
        let boardMat = vc(0.8, snow: 1.3)
        var group = FinaleMesh()
        var swept = FinaleMesh()
        var count = 0
        for (a, b) in sosStrokes() {
            let d = b - a
            let len = sqrt(d.x * d.x + d.y * d.y)
            let n = max(2, Int((len / 1.05).rounded()))
            let yaw = atan2(d.x, d.y)
            for k in 0..<n {
                let t = (Float(k) + 0.5) / Float(n)
                let c = a + d * t
                group.box(FinaleV3(c.x + rng.r(-0.08, 0.08), T + 0.03, c.y + rng.r(-0.08, 0.08)), FinaleV3(0.6, 0.025, 0.6), finaleLin(rng.pick(whites)), yaw: yaw + rng.r(-0.12, 0.12))
                count += 1
                if count % 6 == 0 {
                    let node = group.node(boardMat, shadow: false)
                    world.addChildNode(node)
                    sosBoards.append(node)
                    group = FinaleMesh()
                }
            }
            // the same letter swept clear of snow: dark wet gravel
            let side = SIMD2<Float>(-d.y, d.x) / len * 0.75
            let e = d / len * 0.7
            let p0 = a - e - side, p1 = b + e - side, p2 = b + e + side, p3 = a - e + side
            swept.quad(FinaleV3(p0.x, T + 0.025, p0.y), FinaleV3(p3.x, T + 0.025, p3.y), FinaleV3(p2.x, T + 0.025, p2.y), FinaleV3(p1.x, T + 0.025, p1.y), finaleLin(0x3E3A34))
        }
        if !group.idx.isEmpty { let node = group.node(boardMat, shadow: false); world.addChildNode(node); sosBoards.append(node) }
        let sw = swept.node(vc(0.9, snow: 0), shadow: false)
        sw.isHidden = true
        world.addChildNode(sw)
        sosSwept = sw

        // signal 2: a tall bamboo pole with an orange cloth at the north-east edge, and a smoke fire
        var flag = FinaleMesh()
        let fp = FinaleV3(10.5, T, -20.5)
        flag.tube(fp, fp + FinaleV3(0.1, 8.5, 0), 0.06, 0.04, finaleLin(0xB7A56C), segs: 5)
        flag.sheet(nu: 8, nv: 4, finaleLin(0xE0521E)) { u, v in
            fp + FinaleV3(0.1 + u * 3.2, 8.3 - v * 2.0 - u * 0.25, 0.25 * sin(u * 5.2 + v) * u)
        }
        let fn = flag.node(vc(0.85, snow: 0, doubleSided: true))
        fn.isHidden = true
        world.addChildNode(fn)
        signalFlag = fn
        let sm = SCNNode()
        let sp = FinaleV3(-6.5, T, -20.8)
        sm.position = SCNVector3(CGFloat(sp.x), CGFloat(sp.y), CGFloat(sp.z))
        var pit = FinaleMesh()
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi
            pit.blob(FinaleV3(cos(a) * 0.6, 0.08, sin(a) * 0.6), FinaleV3(0.16, 0.12, 0.16), finaleLin(0x6A6A6A), noise, seed: Float(k), jitter: 0.2, rings: 3, segs: 5)
        }
        pit.tube(FinaleV3(-0.4, 0.15, -0.2), FinaleV3(0.5, 0.35, 0.25), 0.08, 0.08, finaleLin(0x3A2A1E), segs: 5)
        pit.tube(FinaleV3(0.3, 0.15, -0.5), FinaleV3(-0.3, 0.35, 0.4), 0.07, 0.07, finaleLin(0x3A2A1E), segs: 5)
        sm.addChildNode(pit.node(vc(0.9)))
        let smokeHolder = SCNNode(); smokeHolder.position.y = 1.2; sm.addChildNode(smokeHolder)
        let ws = bigSmoke(0.9, dark: false)
        ws.propertyControllers = smokeDayLight
        smokeHolder.addParticleSystem(ws)
        signalSmokePS = ws
        let flameHolder = SCNNode(); flameHolder.position.y = 0.3; sm.addChildNode(flameHolder)
        let fl = SK.fire(scale: 0.8)
        flameHolder.addParticleSystem(fl)
        sm.isHidden = true
        world.addChildNode(sm)
        signalSmoke = sm

        // signal 3: the radio antenna on the store, a red lamp on top; a torch flashed at night
        var ant = FinaleMesh()
        let base = FinaleV3(storeXZ.x + 0.6, T + 2.85, storeXZ.y - 1.0)
        let steelC = finaleLin(0xA8ACAE)
        ant.tube(base, base + FinaleV3(0, 7.5, 0), 0.06, 0.04, steelC, segs: 5)
        ant.tube(base + FinaleV3(0, 7.0, -1.4), base + FinaleV3(0, 7.0, 1.4), 0.025, 0.025, steelC, segs: 3)
        for k in 0..<6 {
            let z = -1.25 + Float(k) * 0.5, half = 0.75 - Float(k) * 0.08
            ant.tube(base + FinaleV3(-half, 7.0, z), base + FinaleV3(half, 7.0, z), 0.015, 0.015, steelC, segs: 3)
        }
        for (dx, dz) in [(Float(1.4), Float(2.0)), (-1.6, 2.0), (1.4, -1.4), (-1.6, -1.4)] {
            ant.tube(base + FinaleV3(0, 5.5, 0), base + FinaleV3(dx - 0.6, -0.05, dz + 1.0), 0.008, 0.008, finaleLin(0x2A2A2A), segs: 3)
        }
        ant.tube(base + FinaleV3(0.05, 0, 0.05), FinaleV3(storeXZ.x - 1.65, T + 1.5, storeXZ.y + 1.0), 0.02, 0.02, finaleLin(0x1A1A1A), segs: 3)
        let an = ant.node(vc(0.5, snow: 0.3))
        let lamp = SK.sphere(0.12, glow(SK.rgb(0xFF2A1A), 3), at: SCNVector3(CGFloat(base.x), CGFloat(base.y) + 7.65, CGFloat(base.z)), segments: 8)
        lamp.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.4), .fadeOpacity(to: 0.08, duration: 0.05), .wait(duration: 0.9)])))
        an.addChildNode(lamp)
        an.isHidden = true
        world.addChildNode(an)
        antenna = an
        antennaLamp = lamp
        var lying = FinaleMesh()
        lying.tube(base + FinaleV3(-1.2, 0.08, 1.8), base + FinaleV3(1.0, 0.1, -1.9), 0.06, 0.04, steelC, segs: 5)
        let ln = lying.node(vc(0.5, snow: 0.3))
        ln.isHidden = true
        world.addChildNode(ln)
        antennaDown = ln
        // the torch: a beam of light swung out over the town
        let beamM = SK.mat(.black, roughness: 1)
        beamM.emission.contents = FinaleTex.beam()
        beamM.emission.intensity = 0.6
        beamM.transparency = 1
        beamM.blendMode = SCNBlendMode.add
        beamM.writesToDepthBuffer = false
        beamM.isDoubleSided = true
        let cone = SCNCone(topRadius: 0.05, bottomRadius: 1.3, height: 34)
        cone.radialSegmentCount = 16
        cone.materials = [beamM]
        let beam = SCNNode(geometry: cone)
        beam.position = SCNVector3(0, -17, 0)
        let holder = SCNNode()
        holder.position = SCNVector3(4.5, CGFloat(T) + 1.45, -21.6)
        holder.addChildNode(beam)
        holder.eulerAngles = SCNVector3(-1.95, 0.35, 0)
        holder.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.6), .fadeOpacity(to: 0, duration: 0.1), .wait(duration: 0.5)])))
        holder.isHidden = true
        world.addChildNode(holder)
        torchBeam = holder
    }

    // MARK: - Projects: tarp shelter, firebreak, spring pipe, route markers

    private func buildProjects() {
        let T = topY
        let bamboo = finaleLin(0xB7A56C)
        // the blue tarp shelter against the office's north wall
        var poles = FinaleMesh()
        for (x, z, h) in [(Float(9.4), Float(1.6), Float(2.1)), (15.6, 1.6, 2.0), (12.5, 1.5, 2.15), (9.4, 6.8, 2.7), (15.6, 6.8, 2.7)] {
            poles.tube(FinaleV3(x, T, z), FinaleV3(x + 0.03, T + h, z), 0.045, 0.035, bamboo, segs: 5)
        }
        poles.tube(FinaleV3(9.3, T + 2.08, 1.6), FinaleV3(15.7, T + 2.0, 1.6), 0.035, 0.035, bamboo, segs: 4)
        let pn = poles.node(vc(0.8, snow: 0.3))
        pn.isHidden = true
        world.addChildNode(pn)
        tarpPoles = pn
        var sheet = FinaleMesh()
        sheet.sheet(nu: 8, nv: 6, finaleLin(0x2C5CA6)) { u, v in
            let x = 9.2 + 6.6 * u, z = 7.05 - 5.65 * v
            let y = T + 2.72 - 0.66 * v - 0.18 * sin(u * .pi) * sin(v * .pi) + 0.05 * sin(u * 9) * v
            return FinaleV3(x, y, z)
        }
        var under = FinaleMesh()
        var rng = FinaleRng(151)
        for _ in 0..<7 {
            under.box(FinaleV3(rng.r(9.8, 15.2), T + 0.03, rng.r(2.2, 6.4)), FinaleV3(rng.r(0.4, 0.8), 0.02, rng.r(0.3, 0.6)), finaleLin(rng.pick([0xA88A62, 0x9A7E58, 0xB89A6E] as [UInt32])), yaw: rng.r(0, 3))
        }
        for _ in 0..<5 {
            under.box(FinaleV3(rng.r(10, 15), T + 0.08, rng.r(3, 6.2)), FinaleV3(0.28, 0.06, 0.28), finaleLin(rng.pick([0x8A2A2E, 0x6A3A6A, 0x3A4A7A] as [UInt32])), yaw: rng.r(0, 3))
        }
        for (x, z) in [(Float(9.2), Float(1.4)), (15.8, 1.4)] { under.box(FinaleV3(x, T + 0.12, z), FinaleV3(0.35, 0.12, 0.18), finaleLin(0x6E5A44), yaw: 0.4) }
        let sh = SCNNode()
        sh.addChildNode(sheet.node(vc(0.6, snow: 0.35, doubleSided: true)))
        sh.addChildNode(under.node(vc(0.9, snow: 0)))
        sh.isHidden = true
        world.addChildNode(sh)
        tarpSheet = sh
        var roll = FinaleMesh()
        roll.tube(FinaleV3(10.2, T + 0.18, 4.0), FinaleV3(12.0, T + 0.18, 4.4), 0.18, 0.18, finaleLin(0x2C5CA6), segs: 8, cap: true)
        let rn = roll.node(vc(0.6, snow: 0.8))
        rn.isHidden = true
        world.addChildNode(rn)
        tarpRoll = rn

        // the firebreak: a band of cleared earth across the north slope, cut sector by sector
        for k in 0..<8 {
            var m = FinaleMesh()
            let a0 = breakA0 + (breakA1 - breakA0) * Float(k) / 8, a1 = breakA0 + (breakA1 - breakA0) * Float(k + 1) / 8
            let r0 = hillRadius(atHeight: breakHi), r1 = hillRadius(atHeight: breakLo)
            m.sheet(nu: 5, nv: 3, finaleLin(0xA8905E)) { u, v in
                let a = a0 + (a1 - a0) * u, r = r0 + (r1 - r0) * v
                let x = cos(a) * r, z = sin(a) * r
                return FinaleV3(x, self.gy(x, z) + 0.18, z)
            }
            // brush and logs dragged to the downhill edge
            for j in 0..<4 {
                let a = a0 + (a1 - a0) * (Float(j) + 0.5) / 4
                let r = r1 + 1.5
                let x = cos(a) * r, z = sin(a) * r
                m.blob(FinaleV3(x, gy(x, z) + 0.3, z), FinaleV3(1.3, 0.55, 0.9), finaleLin(0x4E4232), noise, seed: a * 7, jitter: 0.4, rings: 3, segs: 6)
            }
            let n = m.node(vc(0.95, snow: 0.6), shadow: false)
            n.isHidden = true
            world.addChildNode(n)
            firebreakStrip.append(n)
        }

        // the spring: bamboo pipe from the back hill along the east edge to the fountain
        let path: [FinaleV3] = [FinaleV3(4, gy(4, 70) + 0.4, 70), FinaleV3(6, gy(6, 46) + 0.4, 46), FinaleV3(9, gy(9, 30) + 0.4, 30), FinaleV3(17, T + 0.35, 17.5),
                           FinaleV3(21.5, T + 0.35, 4), FinaleV3(20.5, T + 0.35, -8.5), FinaleV3(fountainXZ.x + 1.6, T + 0.9, fountainXZ.y + 0.6), FinaleV3(fountainXZ.x - 0.5, T + 0.98, fountainXZ.y + 0.06)]
        for k in 0..<(path.count - 1) {
            var m = FinaleMesh()
            m.tube(path[k], path[k + 1], 0.06, 0.06, finaleLin(0x9AA060), segs: 5)
            let mid = (path[k] + path[k + 1]) * 0.5
            m.tube(FinaleV3(mid.x, mid.y - 0.45, mid.z), mid, 0.03, 0.03, bamboo, segs: 3)
            let n = m.node(vc(0.7, snow: 0.6))
            n.isHidden = true
            world.addChildNode(n)
            springPipe.append(n)
        }
        var wet = FinaleMesh()
        let fc = FinaleV3(fountainXZ.x, T, fountainXZ.y)
        let stream = SK.mat(SK.rgb(0xCFE4EE), roughness: 0.1)
        stream.transparency = 0.7
        wet.tube(fc + FinaleV3(-0.4, 0.95, 0.05), fc + FinaleV3(-0.32, 0.82, 0.05), 0.025, 0.02, FinaleV3(1, 1, 1), segs: 5)
        let wn = wet.node(stream, shadow: false)
        var buckets = FinaleMesh()
        for (i, c) in [UInt32(0x2E6DB4), 0xE6E4DC, 0xC0392B, 0x3C8F4F].enumerated() {
            let q = fc + FinaleV3(-1.6 + Float(i) * 0.75, 0, 1.3 + Float(i % 2) * 0.4)
            buckets.tube(q, q + FinaleV3(0, 0.34, 0), 0.15, 0.19, finaleLin(c), segs: 9, cap: false)
            buckets.tube(q + FinaleV3(0, 0.27, 0), q + FinaleV3(0, 0.28, 0), 0.17, 0.17, finaleLin(0x6A8A9A), segs: 9, cap: true)
        }
        let sp = SCNNode()
        sp.addChildNode(wn)
        sp.addChildNode(buckets.node(vc(0.4, snow: 0.5)))
        sp.isHidden = true
        world.addChildNode(sp)
        springWater = sp

        // the route over the back ridge: stakes with pink tape, a trodden path between them
        let route: [SIMD2<Float>] = [SIMD2(-12, 20), SIMD2(-20, 34), SIMD2(-34, 54), SIMD2(-52, 78), SIMD2(-66, 104), SIMD2(-82, 134), SIMD2(-98, 166),
                                     SIMD2(-112, 200), SIMD2(-126, 236), SIMD2(-138, 272)]
        for (i, q) in route.enumerated() {
            var m = FinaleMesh()
            let y = gy(q.x, q.y)
            m.tube(FinaleV3(q.x, y - 0.2, q.y), FinaleV3(q.x, y + 1.3, q.y), 0.03, 0.025, finaleLin(0x8A7A5A), segs: 4)
            m.sheet(nu: 3, nv: 1, finaleLin(0xF0508A)) { u, v in FinaleV3(q.x + u * 0.7, y + 1.22 - v * 0.12 - u * 0.25, q.y + 0.08 * sin(u * 6)) }
            if i > 0 {
                let p0 = route[i - 1]
                let d = q - p0
                let side = SIMD2<Float>(-d.y, d.x) / max(0.01, sqrt(d.x * d.x + d.y * d.y)) * 0.45
                let steps = 6
                for k in 0..<steps {
                    let t0 = Float(k) / Float(steps), t1 = Float(k + 1) / Float(steps)
                    let a = p0 + d * t0, b = p0 + d * t1
                    m.quad(FinaleV3(a.x - side.x, gy(a.x - side.x, a.y - side.y) + 0.05, a.y - side.y), FinaleV3(a.x + side.x, gy(a.x + side.x, a.y + side.y) + 0.05, a.y + side.y),
                           FinaleV3(b.x + side.x, gy(b.x + side.x, b.y + side.y) + 0.05, b.y + side.y), FinaleV3(b.x - side.x, gy(b.x - side.x, b.y - side.y) + 0.05, b.y - side.y), finaleLin(0x4A443A))
                }
            }
            let n = m.node(vc(0.8, snow: 0, doubleSided: true), shadow: false)
            n.isHidden = true
            world.addChildNode(n)
            routeMarkers.append(n)
        }

        // trampled slush in the precinct once snow lies: round the fire, the paths, the doors
        var tr = FinaleMesh()
        let spots: [(Float, Float, Float, Float)] = [(fireXZ.x, fireXZ.y, 4.2, 0.9), (-3, -4, 2.8, 0.6), (5.5, -10.0, 2.6, 0.45), (13, -11.5, 2.4, 0.5), (14.6, -3.5, 2.0, 0.8),
                                                     (-6, 5, 2.2, 0.8), (9, 9, 2.0, 0.9)]
        for (i, sp) in spots.enumerated() {
            tr.patch(FinaleV3(sp.0, T + 0.035, sp.1), sp.2, finaleLin(0x76726A), noise, seed: Float(i) * 3.1, aspect: sp.3, yaw: Float(i), segs: 14, rough: 0.35)
        }
        let trn = tr.node(vc(0.9, snow: 0.25), shadow: false)
        trn.isHidden = true
        world.addChildNode(trn)
        trampled = trn
    }

    // MARK: - Small things in the precinct

    private func buildDetails() {
        let T = topY
        let granite = finaleLin(0x7E7A72)
        // the old tsunami stone at the north edge (此処より下に家を建てるな)
        var st = FinaleMesh()
        let sp = FinaleV3(-6.8, T, -21.4)
        st.box(sp + FinaleV3(0, 0.2, 0), FinaleV3(0.85, 0.2, 0.55), granite * 0.9, yaw: 0.4)
        st.box(sp + FinaleV3(0, 1.45, 0), FinaleV3(0.55, 1.05, 0.16), granite, yaw: 0.4, roll: 0.03)
        st.blob(sp + FinaleV3(0, 2.5, 0), FinaleV3(0.5, 0.16, 0.16), granite, noise, seed: 4, jitter: 0.2, rings: 3, segs: 6)
        for k in 0..<4 { st.box(sp + finaleRot(FinaleV3(-0.3 + Float(k) * 0.2, 1.5, 0.17), yaw: 0.4), FinaleV3(0.025, 0.7, 0.01), finaleLin(0x3E3B36), yaw: 0.4) }
        world.addChildNode(st.node(vc(0.9)))
        // after the wave: the board of notes (who is safe, who is looking for whom) by the store
        var nb = FinaleMesh()
        let bp = FinaleV3(13.8, T, -10.6)
        let byaw: Float = 0.75
        func B(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { bp + finaleRot(FinaleV3(x, y, z), yaw: byaw) }
        nb.box(B(0, 1.25, 0), FinaleV3(1.1, 0.62, 0.03), finaleLin(0xB89A70), yaw: byaw)
        for x in [Float(-1.0), 1.0] { nb.box(B(x, 0.65, 0), FinaleV3(0.05, 0.65, 0.05), finaleLin(0x7A6248), yaw: byaw) }
        var rng = FinaleRng(181)
        for k in 0..<26 {
            let x = -0.95 + Float(k % 7) * 0.31 + rng.r(-0.04, 0.04), y = 0.75 + Float(k / 7) * 0.27 + rng.r(-0.03, 0.03)
            nb.box(B(x, y, 0.035), FinaleV3(rng.r(0.09, 0.13), rng.r(0.09, 0.12), 0.004), finaleLin(rng.pick([0xF4F2EC, 0xEDEBE0, 0xF6E8A0, 0xE8F0F4] as [UInt32])), yaw: byaw, roll: rng.r(-0.15, 0.15))
        }
        let nn = nb.node(vc(0.85, snow: 0.3))
        nn.isHidden = true
        world.addChildNode(nn)
        noticeBoard = nn
        // supplies stacked against the store: a few cartons at first, the drops and the army's later
        for g in 0..<2 {
            var sm = FinaleMesh()
            for k in 0..<(g == 0 ? 5 : 12) {
                let x = storeXZ.x - 2.3 - Float(k % 3) * 0.62 - Float(g) * 1.9, z = storeXZ.y + 1.4 - Float((k / 3) % 2) * 0.55
                let y = T + 0.2 + Float(k / 6) * 0.4
                let water = (k + g) % 3 == 0
                sm.box(FinaleV3(x, y, z), FinaleV3(0.29, 0.2, 0.24), water ? finaleLin(0x3E6EA8) : finaleLin(0xB8956A) * rng.r(0.9, 1.05), yaw: rng.r(-0.1, 0.1))
            }
            let n = sm.node(vc(0.8, snow: 0.4))
            n.isHidden = true
            world.addChildNode(n)
            supplies.append(n)
        }
    }

    // MARK: - The townspeople on the hill (var crowd): one merged mesh per group of four

    private func buildCrowd(_ layout: Int) -> [SCNNode] {
        var rng = FinaleRng(UInt64(161 + layout * 7))
        let clothes: [UInt32] = [0x2A3348, 0x222326, 0x5A5C60, 0x5E4A3A, 0x7A7258, 0x6A2A2A, 0x34443A, 0xB8AA90, 0x3A3A44, 0x4A5A6E, 0xB03A2E, 0xD86A2A]
        let blankets: [UInt32] = [0x8A8A86, 0x7A5E48, 0x4A6A9A, 0xC8909A, 0xC8B898, 0x5A7A5A, 0xC8CCD0, 0x9A3A3A]
        let T = topY
        var places: [(FinaleV3, Float, Int)] = []          // position, facing, pose (0 stand, 1 sit, 2 huddle, 3 bent, 4 lie)
        func hallP(_ x: Float, _ z: Float) -> FinaleV3 { FinaleV3(hallXZ.x, T, hallXZ.y) + finaleRot(FinaleV3(x, 0, z), yaw: hallYaw) }
        let hallFacing = hallYaw + .pi / 2
        switch layout {
        case 0:   // daytime: on the hall's veranda and steps, by the office, a queue at the store, along the north edge
            for k in 0..<8 { places.append((hallP(3.75, -3.6 + Float(k) * 1.0) + FinaleV3(0, 1.0, 0), hallFacing, 1)) }
            for k in 0..<4 { places.append((hallP(5.3 + Float(k % 2) * 0.8, -1.8 + Float(k) * 1.1), hallFacing + rng.r(-0.6, 0.6), k == 3 ? 3 : 0)) }
            for k in 0..<7 { places.append((FinaleV3(14.4 - Float(k) * 1.0, T, -6.8 - Float(k % 2) * 0.6), -.pi / 2 + rng.r(-0.3, 0.3), k % 3 == 2 ? 3 : 0)) }
            for k in 0..<9 {
                let a = Float(-2.05) + Float(k) * 0.14
                places.append((FinaleV3(sin(a) * (plateauR - 2.2), T, cos(a) * (plateauR - 2.2)), a + rng.r(-0.3, 0.3), k % 4 == 1 ? 3 : 0))
            }
            for k in 0..<6 { places.append((FinaleV3(9.6 + Float(k % 3) * 1.6, T, 8.0 + Float(k / 3) * 1.6), -.pi / 2 + rng.r(-0.5, 0.5), k % 2 == 0 ? 1 : 2)) }
            for k in 0..<6 { places.append((FinaleV3(-1.5 + Float(k) * 1.4, T, 5.5 + Float(k % 2) * 1.2), .pi + rng.r(-0.8, 0.8), k % 3 == 0 ? 3 : 0)) }
        case 1:   // night / bad weather: huddled under the hall's eaves, under the tarp, in a wide ring round the fire
            for k in 0..<10 { places.append((hallP(3.7 - Float(k % 2) * 0.7, -4.2 + Float(k / 2) * 2.0) + FinaleV3(0, 1.0, 0), hallFacing, 2)) }
            for k in 0..<6 { places.append((hallP(-4.2 + Float(k % 3) * 0.8, 4.6 + Float(k / 3) * 0.7), hallFacing - .pi / 2, k == 4 ? 4 : 2)) }
            for k in 0..<8 { places.append((FinaleV3(10.0 + Float(k % 4) * 1.5, T, 3.2 + Float(k / 4) * 2.2), .pi + rng.r(-0.4, 0.4), k % 3 == 1 ? 4 : 2)) }
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi + 0.2
                places.append((FinaleV3(fireXZ.x + sin(a) * 5.2, T, fireXZ.y + cos(a) * 5.2), a + .pi, k % 4 == 3 ? 1 : 2))
            }
            for k in 0..<4 { places.append((FinaleV3(14.0 + Float(k % 2) * 0.8, T, -2.5 + Float(k / 2) * 1.0), .pi / 2, 2)) }
        default:  // fled from the fire: crowded on the back slope behind the precinct
            for k in 0..<40 {
                let x = -16 + Float(k % 8) * 4.2 + rng.r(-1, 1), z = 30 + Float(k / 8) * 4.5 + rng.r(-1, 1)
                places.append((FinaleV3(x, gy(x, z), z), .pi + rng.r(-0.5, 0.5), k % 5 == 4 ? 4 : (k % 3 == 0 ? 0 : 2)))
            }
        }
        var nodes: [SCNNode] = []
        let mat = vc(0.9, snow: 0.35)
        for g in 0..<10 {
            var m = FinaleMesh()
            for k in 0..<4 {
                let i = g * 4 + k
                guard i < places.count else { break }
                let (p, f, pose) = places[i]
                crowdFigure(&m, p, yaw: f, pose: pose, col: finaleLin(rng.pick(clothes)), blanket: finaleLin(rng.pick(blankets)), rng: &rng)
            }
            let n = m.node(mat)
            n.isHidden = true
            world.addChildNode(n)
            nodes.append(n)
        }
        return nodes
    }

    private func crowdFigure(_ m: inout FinaleMesh, _ p: FinaleV3, yaw: Float, pose: Int, col: FinaleV3, blanket: FinaleV3, rng: inout FinaleRng) {
        var f = FinaleMesh()
        let skin = finaleLin(0xD2AE92), dark = col * 0.55, hair = finaleLin(rng.pick([0x1E1A18, 0x6A6662, 0xB8B4AE] as [UInt32]))
        switch pose {
        case 1:      // sitting, knees up
            f.box(FinaleV3(0, 0.42, -0.05), FinaleV3(0.2, 0.3, 0.13), col)
            f.box(FinaleV3(0, 0.15, 0.22), FinaleV3(0.17, 0.12, 0.25), dark)
            f.blob(FinaleV3(0, 0.88, -0.03), FinaleV3(0.11, 0.12, 0.11), skin, noise, seed: 1, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
            f.blob(FinaleV3(0, 0.95, -0.05), FinaleV3(0.115, 0.07, 0.115), hair, noise, seed: 2, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
        case 2:      // sitting hunched, a blanket over head and shoulders
            f.box(FinaleV3(0, 0.14, 0.2), FinaleV3(0.17, 0.12, 0.22), dark)
            f.cone(FinaleV3(0, 0, -0.02), 0.42, 0.86, blanket, segs: 8)
            f.blob(FinaleV3(0, 0.8, 0.07), FinaleV3(0.1, 0.115, 0.1), skin, noise, seed: 1, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
            f.blob(FinaleV3(0, 0.86, 0.02), FinaleV3(0.125, 0.09, 0.12), blanket * 0.8, noise, seed: 3, jitter: 0.05, rings: 3, segs: 6, under: 0.9, vary: 0)
        case 4:      // lying, wrapped
            f.box(FinaleV3(0, 0.14, 0), FinaleV3(0.28, 0.14, 0.85), blanket)
            f.blob(FinaleV3(0, 0.16, 0.95), FinaleV3(0.11, 0.1, 0.12), skin, noise, seed: 1, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
        default:     // standing (3: an old person, bent)
            let bend: Float = pose == 3 ? 0.35 : 0
            f.box(FinaleV3(0, 0.42, 0), FinaleV3(0.16, 0.42, 0.1), dark)
            f.box(FinaleV3(0, 1.1, 0.08 * bend * 3), FinaleV3(0.21, 0.3, 0.13), col, pitch: bend)
            f.box(FinaleV3(-0.26, 1.02, 0.1 * bend * 3), FinaleV3(0.06, 0.27, 0.07), col, pitch: bend)
            f.box(FinaleV3(0.26, 1.02, 0.1 * bend * 3), FinaleV3(0.06, 0.27, 0.07), col, pitch: bend)
            f.blob(FinaleV3(0, 1.55 - bend * 0.25, bend * 0.45), FinaleV3(0.11, 0.12, 0.11), skin, noise, seed: 1, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
            f.blob(FinaleV3(0, 1.62 - bend * 0.25, bend * 0.43), FinaleV3(0.115, 0.07, 0.115), hair, noise, seed: 2, jitter: 0, rings: 3, segs: 6, under: 0.9, vary: 0)
        }
        m.append(f, at: p, yaw: yaw)
    }

    // MARK: - Help from outside: ships, helicopters, the convoy, the road through the rubble

    /// The road that comes over the north ridge in switchbacks (the convoy comes down it).
    private let ridgeRoadXZ: [SIMD2<Float>] = [SIMD2(60, -884), SIMD2(185, -782), SIMD2(25, -724), SIMD2(165, -664), SIMD2(5, -614), SIMD2(92, -572)]

    private func roadPoint(_ d: Float) -> (FinaleV3, Float) {
        var left = d
        for i in 0..<(ridgeRoadXZ.count - 1) {
            let a = ridgeRoadXZ[i], b = ridgeRoadXZ[i + 1]
            let e = b - a
            let l = sqrt(e.x * e.x + e.y * e.y)
            if left <= l || i == ridgeRoadXZ.count - 2 {
                let t = min(1, left / l)
                let p = a + e * t
                return (FinaleV3(p.x, gy(p.x, p.y) + 0.35, p.y), atan2(-e.y, e.x))
            }
            left -= l
        }
        return (FinaleV3(0, 0, 0), 0)
    }

    /// A soft additive glow that faces the camera (headlights, torches seen from far away).
    private lazy var haloPlane: SCNPlane = {
        let p = SCNPlane(width: 4, height: 4)
        let m = SK.mat(.black, roughness: 1)
        m.emission.contents = SK.dotImage(size: 64, hardness: 0.05)
        m.emission.intensity = 1.2
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        p.materials = [m]
        return p
    }()

    private func buildRescue() {
        // the road cut across the ridge's face
        var road = FinaleMesh()
        for i in 0..<(ridgeRoadXZ.count - 1) {
            let a = ridgeRoadXZ[i], b = ridgeRoadXZ[i + 1]
            let e = b - a
            let l = sqrt(e.x * e.x + e.y * e.y)
            let side = SIMD2<Float>(-e.y, e.x) / l * 3.6
            let n = Int(l / 8)
            for k in 0..<n {
                let p0 = a + e * (Float(k) / Float(n)), p1 = a + e * (Float(k + 1) / Float(n))
                func Q(_ p: SIMD2<Float>, _ s: Float) -> FinaleV3 { let q = p + side * s; return FinaleV3(q.x, gy(q.x, q.y) + 0.25, q.y) }
                road.quad(Q(p0, -1), Q(p0, 1), Q(p1, 1), Q(p1, -1), finaleLin(0x6E6A62))
            }
        }
        world.addChildNode(road.node(vc(0.9, snow: 0.8), shadow: false))
        // the convoy: army trucks nose to tail down the switchbacks (headlights at night)
        var total: Float = 0
        for i in 0..<(ridgeRoadXZ.count - 1) { let e = ridgeRoadXZ[i + 1] - ridgeRoadXZ[i]; total += sqrt(e.x * e.x + e.y * e.y) }
        let lightM = glow(SK.rgb(0xFFF4D8), 4)
        for k in 0..<14 {
            let (p, yaw) = roadPoint(total - 40 - Float(k) * 42)
            var m = FinaleMesh()
            let olive = finaleLin(0x56603A)
            m.box(FinaleV3(-0.9, 1.6, 0), FinaleV3(2.4, 1.2, 1.2), olive)
            m.box(FinaleV3(2.5, 1.3, 0), FinaleV3(0.9, 1.0, 1.15), olive * 0.9)
            m.box(FinaleV3(-0.9, 2.95, 0), FinaleV3(2.45, 0.2, 1.25), finaleLin(0x6A7048))
            let n = m.node(vc(0.7, snow: 0.6))
            n.position = SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z))
            n.eulerAngles.y = CGFloat(yaw + .pi)
            var hm = FinaleMesh()
            for z in [Float(-0.8), 0.8] { hm.blob(FinaleV3(3.45, 1.0, z), FinaleV3(0.22, 0.22, 0.22), FinaleV3(1, 1, 1), noise, seed: 0, jitter: 0, rings: 3, segs: 6, under: 1, vary: 0) }
            let hl = hm.node(lightM, shadow: false)
            hl.name = "headlight"
            let halo = SCNNode(geometry: haloPlane)
            halo.position = SCNVector3(3.7, 1.0, 0)
            halo.constraints = [SCNBillboardConstraint()]
            hl.addChildNode(halo)
            n.addChildNode(hl)
            n.isHidden = true
            world.addChildNode(n)
            convoy.append(n)
        }
        // ships out in the bay: coast guard, a navy transport, a patrol boat
        let shipDefs: [(Float, Float, Float, UInt32, UInt32, Float)] = [(950, -620, 95, 0xE8E8E4, 0x2C5AA8, 0.4), (1300, -950, 130, 0x8A9096, 0x6A7076, 1.2), (700, -380, 45, 0xE8E8E4, 0x2C5AA8, 2.4)]
        for d in shipDefs {
            let n = ship(length: d.2, hull: finaleLin(d.3), stripe: finaleLin(d.4))
            n.position = SCNVector3(CGFloat(d.0), CGFloat(seaY), CGFloat(d.1))
            n.eulerAngles.y = CGFloat(d.5)
            n.isHidden = true
            world.addChildNode(n)
            ships.append(n)
        }
        // a helicopter far off over the bay, circling
        let far = helicopter(scale: 1)
        let pivot = SCNNode()
        pivot.position = SCNVector3(520, 150, -620)
        far.position = SCNVector3(280, 0, 0)
        far.eulerAngles.y = -.pi / 2
        pivot.addChildNode(far)
        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 70)))
        pivot.isHidden = true
        world.addChildNode(pivot)
        farHeli = pivot
        // the rescue helicopter hovering over the precinct, its downwash whipping up snow and dust
        let h = helicopter(scale: 1)
        h.position = SCNVector3(14, 44, -44)
        h.eulerAngles.y = 2.2
        h.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.5, z: 0, duration: 1.7), .moveBy(x: 0, y: -0.5, z: 0, duration: 1.7)])))
        h.isHidden = true
        world.addChildNode(h)
        heli = h
        let wash = SCNParticleSystem()
        wash.birthRate = 160
        wash.particleLifeSpan = 1.6
        wash.emitterShape = SCNTube(innerRadius: 2, outerRadius: 6, height: 0.3)
        wash.birthLocation = .volume
        wash.particleImage = SK.dotImage(size: 32, hardness: 0.1)
        wash.particleSize = 0.9
        wash.particleSizeVariation = 0.5
        wash.particleColor = NSColor(white: 0.9, alpha: 0.18)
        wash.particleVelocity = 5
        wash.emittingDirection = SCNVector3(0, 0.25, 0)
        wash.spreadingAngle = 80
        wash.blendMode = .alpha
        wash.isLightingEnabled = false
        wash.warmupDuration = 2
        let wn = SCNNode()
        wn.position = SCNVector3(12, CGFloat(topY) + 0.3, -21)
        wn.addParticleSystem(wash)
        wn.isHidden = true
        world.addChildNode(wn)
        heliWash = wn
        washPS = wash

        // the lane being cleared through the rubble from the ridge road to the foot of the steps
        let laneA = ridgeRoadXZ[ridgeRoadXZ.count - 1], laneB = SIMD2<Float>(stairB.x + 8, stairB.y - 10)
        let mids: [SIMD2<Float>] = [laneA, SIMD2(70, -470), SIMD2(64, -330), SIMD2(70, -200), SIMD2(66, -110), laneB]
        var pts: [SIMD2<Float>] = []
        for i in 0..<(mids.count - 1) {
            for k in 0..<4 { pts.append(mids[i] + (mids[i + 1] - mids[i]) * (Float(k) / 4)) }
        }
        pts.append(laneB)
        var rng = FinaleRng(171)
        for i in 0..<(pts.count - 1) {
            var m = FinaleMesh()
            let a = pts[i], b = pts[i + 1]
            let e = b - a
            let l = sqrt(e.x * e.x + e.y * e.y)
            let side = SIMD2<Float>(-e.y, e.x) / l
            let n = max(2, Int(l / 6))
            for k in 0..<n {
                let p0 = a + e * (Float(k) / Float(n)), p1 = a + e * (Float(k + 1) / Float(n))
                func Q(_ p: SIMD2<Float>, _ s: Float) -> FinaleV3 { let q = p + side * s; return FinaleV3(q.x, max(gy(q.x, q.y), 0.6) + 0.5, q.y) }
                m.quad(Q(p0, -4.5), Q(p0, 4.5), Q(p1, 4.5), Q(p1, -4.5), finaleLin(0x8E8A82))
                for t in [Float(-2.2), -1.0, 1.0, 2.2] {
                    let a0 = Q(p0, t - 0.25), a1 = Q(p0, t + 0.25), b0 = Q(p1, t - 0.25), b1 = Q(p1, t + 0.25)
                    m.quad(a0 + FinaleV3(0, 0.02, 0), a1 + FinaleV3(0, 0.02, 0), b1 + FinaleV3(0, 0.02, 0), b0 + FinaleV3(0, 0.02, 0), finaleLin(0x6A665E))
                }
            }
            for k in 0..<Int(l / 5) {
                let c = a + e * ((Float(k) + 0.5) / (l / 5))
                for sgn in [Float(-1), 1] {
                    let q = c + side * (5.6 * sgn + rng.r(-0.6, 0.6))
                    m.blob(FinaleV3(q.x, max(gy(q.x, q.y), 0.6) + 0.3, q.y), FinaleV3(rng.r(1.4, 2.4), rng.r(0.8, 1.5), rng.r(1.2, 2.0)),
                           finaleLin(rng.pick([0x7A6A56, 0x8E7C62, 0x6A6056] as [UInt32])), noise, seed: q.x, jitter: 0.35, rings: 3, segs: 7, under: 0.7, vary: 0.4)
                }
            }
            let node = m.node(vc(0.9, snow: 0.7), shadow: false)
            node.isHidden = true
            world.addChildNode(node)
            lane.append((node, b))
        }
        // the excavator at the head of the lane
        var dg = FinaleMesh()
        let yel = finaleLin(0xE0A81E)
        dg.box(FinaleV3(0, 0.55, 0), FinaleV3(2.2, 0.45, 1.5), finaleLin(0x2A2A28))
        dg.box(FinaleV3(-0.2, 1.6, 0), FinaleV3(1.6, 0.6, 1.3), yel)
        dg.box(FinaleV3(0.9, 2.5, -0.6), FinaleV3(0.55, 0.5, 0.55), finaleLin(0x2A3440))
        dg.tube(FinaleV3(1.2, 1.9, 0.4), FinaleV3(3.6, 4.2, 0.4), 0.22, 0.2, yel, segs: 5)
        dg.tube(FinaleV3(3.6, 4.2, 0.4), FinaleV3(5.0, 1.0, 0.4), 0.18, 0.16, yel, segs: 5)
        dg.box(FinaleV3(5.1, 0.7, 0.4), FinaleV3(0.45, 0.4, 0.55), finaleLin(0x3A3A36))
        let dn = dg.node(vc(0.5, snow: 0.6))
        dn.isHidden = true
        world.addChildNode(dn)
        digger = dn

        // the army's trucks and soldiers on the harbour road below the hill
        let camp = SCNNode()
        var tm = FinaleMesh()
        let olive = finaleLin(0x56603A)
        for k in 0..<3 {
            let c = townP(52 + Float(k) * 9.5, 12)
            let y = gy(c.x, c.y)
            var t = FinaleMesh()
            t.box(FinaleV3(-0.9, 1.6, 0), FinaleV3(2.4, 1.2, 1.2), olive)
            t.box(FinaleV3(2.5, 1.3, 0), FinaleV3(0.9, 1.0, 1.15), olive * 0.9)
            t.box(FinaleV3(-0.9, 2.95, 0), FinaleV3(2.45, 0.2, 1.25), finaleLin(0x6A7048))
            for (x, z) in [(Float(2.4), Float(1.15)), (-0.5, 1.15), (-2.3, 1.15), (2.4, -1.15), (-0.5, -1.15), (-2.3, -1.15)] {
                t.box(FinaleV3(x, 0.45, z), FinaleV3(0.45, 0.45, 0.15), finaleLin(0x151515))
            }
            tm.append(t, at: FinaleV3(c.x, max(y, 1.2) + 0.1, c.y), yaw: townYaw + 0.05)
        }
        let tc = townP(42, 22)
        var tentEnds = FinaleMesh()
        tm.gableRoof(FinaleV3(tc.x, max(gy(tc.x, tc.y), 1.2) + 2.2, tc.y), halfL: 3, halfW: 2.4, rise: 1.6, over: 0.1, yaw: townYaw, olive * 1.1, gable: olive, walls: &tentEnds)
        tm.append(tentEnds)
        tm.box(FinaleV3(tc.x, max(gy(tc.x, tc.y), 1.2) + 1.1, tc.y), FinaleV3(2.9, 1.1, 2.3), olive, yaw: townYaw)
        camp.addChildNode(tm.node(vc(0.7, snow: 0.6)))
        for k in 0..<9 {
            let c = townP(46 + Float(k) * 3.6, 16 + Float(k % 3) * 2.2)
            let soldier = SK.person(color: SK.rgb(0x4E5A36), pose: k % 4 == 1 ? .waving : .standing, seed: k)
            soldier.position = SCNVector3(CGFloat(c.x), CGFloat(max(gy(c.x, c.y), 1.2)), CGFloat(c.y))
            soldier.eulerAngles.y = CGFloat(townYaw) + CGFloat(k) * 0.7
            camp.addChildNode(soldier)
        }
        camp.isHidden = true
        world.addChildNode(camp)
        sdfCamp = camp

        // round 1 on the school: a torch blinking in a third-floor window (event r_tide)
        let sc = FinaleV3(schoolXZ.x, gy(schoolXZ.x, schoolXZ.y), schoolXZ.y) + finaleRot(FinaleV3(-10, 9.4, 7.8), yaw: townYaw)
        let tl = SK.sphere(0.35, glow(SK.rgb(0xFFF0C8), 6), at: SCNVector3(CGFloat(sc.x), CGFloat(sc.y), CGFloat(sc.z)), segments: 8)
        // its halo: a soft additive sprite that always faces the camera
        let halo = SCNPlane(width: 10, height: 10)
        let hm = SK.mat(.black, roughness: 1)
        hm.emission.contents = SK.dotImage(size: 64, hardness: 0.05)
        hm.emission.intensity = 1.4
        hm.blendMode = .add
        hm.writesToDepthBuffer = false
        hm.isDoubleSided = true
        halo.materials = [hm]
        let hn = SCNNode(geometry: halo)
        hn.constraints = [SCNBillboardConstraint()]
        hn.castsShadow = false
        tl.addChildNode(hn)
        tl.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.3), .fadeOpacity(to: 0, duration: 0.05), .wait(duration: 0.35),
                                               .fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.3), .fadeOpacity(to: 0, duration: 0.05), .wait(duration: 1.2)])))
        tl.isHidden = true
        world.addChildNode(tl)
        tideTorch = tl
    }

    private func ship(length: Float, hull: FinaleV3, stripe: FinaleV3) -> SCNNode {
        var m = FinaleMesh()
        let k = length / 100
        let st: [(Float, Float, Float, Float)] = [(-50, 6.5, 6, -4), (-30, 7.5, 6, -5), (20, 7.5, 6.5, -5), (38, 5, 7.5, -4), (50, 0.3, 8.5, -1)]
        m.hull(st.map { ($0.0 * k, $0.1 * k, $0.2 * k, $0.3 * k) }, hull, stripe: stripe, deck: finaleLin(0x8A8C88))
        m.box(FinaleV3(-12 * k, 10 * k, 0), FinaleV3(14 * k, 4 * k, 5.5 * k), finaleLin(0xEEEDE8))
        m.box(FinaleV3(-6 * k, 15.5 * k, 0), FinaleV3(6 * k, 1.8 * k, 4.5 * k), finaleLin(0xEEEDE8))
        m.box(FinaleV3(-1 * k, 15.5 * k, 0), FinaleV3(0.4 * k, 1.0 * k, 4.6 * k), finaleLin(0x1E2A34))
        m.tube(FinaleV3(-14 * k, 14 * k, 0), FinaleV3(-14 * k, 30 * k, 0), 0.6 * k, 0.4 * k, finaleLin(0xD8D8D4), segs: 5)
        m.box(FinaleV3(-24 * k, 15 * k, 0), FinaleV3(2.5 * k, 3 * k, 2.2 * k), stripe)
        return m.node(vc(0.5, snow: 0.4, doubleSided: true), shadow: false)
    }

    private func helicopter(scale s: Float) -> SCNNode {
        let n = SCNNode()
        var m = FinaleMesh()
        let olive = finaleLin(0x4E5838), dark = finaleLin(0x22261E)
        m.blob(FinaleV3(0, 0, 0), FinaleV3(4.0, 1.3, 1.3) * s, olive, noise, seed: 3, jitter: 0.02, rings: 7, segs: 10, under: 0.75, vary: 0.05)
        m.blob(FinaleV3(3.4, -0.1, 0) * s, FinaleV3(1.4, 1.0, 1.1) * s, olive, noise, seed: 4, jitter: 0.02, rings: 5, segs: 8, under: 0.75, vary: 0.05)
        m.blob(FinaleV3(4.0, 0.25, 0) * s, FinaleV3(0.85, 0.5, 0.95) * s, finaleLin(0x1C2A33), noise, seed: 5, jitter: 0.01, rings: 4, segs: 8, under: 0.9, vary: 0)
        m.tube(FinaleV3(-3.2, 0.35, 0) * s, FinaleV3(-10.2, 0.9, 0) * s, 0.55 * s, 0.22 * s, olive, segs: 7)
        m.box(FinaleV3(-10.0, 1.7, 0) * s, FinaleV3(0.6, 1.0, 0.07) * s, olive * 0.9)
        m.box(FinaleV3(0.2, 1.5, 0) * s, FinaleV3(1.6, 0.4, 0.75) * s, olive * 0.95)
        m.box(FinaleV3(0.6, -0.1, 1.31) * s, FinaleV3(0.8, 0.75, 0.02) * s, finaleLin(0x15161A))
        m.box(FinaleV3(-0.6, -0.1, 1.32) * s, FinaleV3(0.6, 0.35, 0.02) * s, finaleLin(0xD8D8D0))
        for z in [Float(0.9), -0.9] { m.tube(FinaleV3(1.6, -1.5, z) * s, FinaleV3(-1.6, -1.5, z) * s, 0.06 * s, 0.06 * s, dark, segs: 4) }
        for (x, z) in [(Float(1.0), Float(0.9)), (-1.0, 0.9), (1.0, -0.9), (-1.0, -0.9)] { m.tube(FinaleV3(x, -1.5, z) * s, FinaleV3(x * 0.8, -1.0, z * 0.7) * s, 0.05 * s, 0.05 * s, dark, segs: 4) }
        n.addChildNode(m.node(vc(0.6, snow: 0)))
        let rotor = SCNNode()
        rotor.position = SCNVector3(0.2 * CGFloat(s), 2.0 * CGFloat(s), 0)
        var r = FinaleMesh()
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            r.box(finaleRot(FinaleV3(4.1 * s, 0, 0), yaw: a), FinaleV3(4.0 * s, 0.03, 0.22 * s), dark, yaw: a)
        }
        rotor.addChildNode(r.node(vc(0.6, snow: 0), shadow: false))
        let disc = SCNNode(geometry: SCNCylinder(radius: 8.2 * CGFloat(s), height: 0.02))
        let dm = SK.mat(SK.rgb(0x6A6E66), roughness: 0.8)
        dm.transparency = 0.12
        dm.writesToDepthBuffer = false
        disc.geometry?.firstMaterial = dm
        disc.castsShadow = false
        rotor.addChildNode(disc)
        rotor.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.25)))
        n.addChildNode(rotor)
        let tail = SCNNode()
        tail.position = SCNVector3(-10.2 * CGFloat(s), 1.7 * CGFloat(s), 0.15 * CGFloat(s))
        var tr = FinaleMesh()
        tr.box(FinaleV3(0, 0, 0), FinaleV3(0.12, 1.2 * s, 0.02), dark)
        tail.addChildNode(tr.node(vc(0.6, snow: 0), shadow: false))
        tail.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 0.12)))
        n.addChildNode(tail)
        return n
    }

    private func applyRescue(_ s: SceneState) {
        let hit = s.has("wave_hit")
        let rescue = hit ? max(0, min(100, s.v("rescue", 0))) : 0
        let night = nightK(s) > 0.5
        let roadOpen = s.has("road_open")
        for (i, sh) in ships.enumerated() { sh.isHidden = rescue < [14.0, 38.0, 62.0][i] }
        let heliNow = s.has("heli")
        farHeli?.isHidden = !(rescue >= 40 && !heliNow && !night)
        heli?.isHidden = !heliNow
        heliWash?.isHidden = !heliNow
        let washDim = CGFloat(1 - 0.75 * nightK(s))
        washPS?.particleColor = s.has("snow_ground") ? NSColor(white: 0.92 * washDim, alpha: 0.22 * washDim) : SK.rgb(0x9A8E7A).withAlphaComponent(0.18 * washDim)
        // the convoy coming down the ridge road: a few trucks once help is on its way, a column later
        let trucks = roadOpen ? convoy.count : (rescue < 48 ? 0 : min(convoy.count, Int((rescue - 40) / 60 * Double(convoy.count))))
        for (i, t) in convoy.enumerated() {
            t.isHidden = i >= trucks
            for c in t.childNodes where c.name == "headlight" { c.isHidden = !night }
        }
        // the lane cleared through the wreckage, the excavator at its head
        let laneP = roadOpen ? 1.0 : max(0, (rescue - 62) / 38)
        let shown = Int((Double(lane.count) * laneP).rounded(.down))
        for (i, l) in lane.enumerated() { l.0.isHidden = i >= shown }
        if shown > 0 && shown < lane.count && !roadOpen {
            let head = lane[shown - 1].1
            digger?.isHidden = false
            digger?.position = SCNVector3(CGFloat(head.x), CGFloat(max(gy(head.x, head.y), 0.6) + 0.5), CGFloat(head.y))
            digger?.eulerAngles.y = 1.65
        } else {
            digger?.isHidden = true
        }
        sdfCamp?.isHidden = !s.has("sdf")
        tideTorch?.isHidden = !(s.now("r_tide") && nightK(s) > 0.4)
    }

    // MARK: - Apply

    override func apply(_ s: SceneState, old: SceneState?) {
        let hit = s.has("wave_hit")
        let flood = Float(max(0, min(12, s.v("flood", 0))))
        let waterY = hit ? max(seaY, flood) : seaY
        water?.position.y = CGFloat(waterY)
        floatRoot.position.y = CGFloat(waterY)
        let highWater = hit ? max(9.5, flood) : 0

        if !hit { buildLowTown() } else { buildRubble() }
        if hit && flood > 1.2 { buildFloating() }
        rubble?.isHidden = !hit
        floatHigh?.isHidden = !(hit && flood > 3.2)
        floatMid?.isHidden = !(hit && flood > 1.2)
        for n in rcGlass { n.isHidden = hit }
        for n in rcShell { n.isHidden = !hit }
        townLow?.isHidden = hit
        townWindowMat?.emission.intensity = nightK(s) > 0.4 ? 1.3 : 0
        townLampMat?.emission.intensity = nightK(s) > 0.4 ? 3.0 : 0
        harborIntact?.isHidden = hit
        centerIntact?.isHidden = hit
        centerShell?.isHidden = !hit
        schoolGlass?.isHidden = hit
        schoolShell?.isHidden = !hit
        for (band, line, base) in mudLines {
            band.isHidden = !hit
            line.isHidden = !hit
            band.scale.y = CGFloat(max(0.01, highWater))
            line.position.y = base + CGFloat(highWater) - 0.2
        }
        yardMat?.multiply.contents = hit ? SK.rgb(0x5A4E40) : NSColor.white
        terrainMat?.setValue(NSNumber(value: hit ? 1.0 : 0.0), forKey: "wreck")

        // the water: grey-green sea; black and full of silt while the flood is up; muddy puddles later
        let murk = hit ? Double(max(0, min(1, (flood - 1.0) / 2.5))) : 0
        waterMat?.setValue(NSNumber(value: murk), forKey: "murk")
        waterMat?.setValue(NSNumber(value: hit ? 1.0 : 0.0), forKey: "puddle")
        let amp = 0.04 + 0.002 * min(40, s.wind) + (hit && flood > 4 ? 0.08 : 0)
        waterMat?.setValue(NSNumber(value: amp), forKey: "amplitude")
        waterMat?.roughness.contents = NSNumber(value: 0.2 + 0.22 * murk)

        // snow on the ground and roofs
        let snowing = s.precip >= 1 && (s.temp < 1 || s.weather == "snow" || s.weather == "sleet")
        let snowNow: CGFloat = s.has("snow_ground") ? (s.precip >= 1 ? 0.9 : 0.75) : (snowing ? 0.35 : 0)
        for (m, k) in snowMats { m.setValue(NSNumber(value: Double(min(1, snowNow * k))), forKey: "snowAmt") }
        terrainMat?.setValue(NSNumber(value: Double(snowNow)), forKey: "snowAmt")
        terrainMat?.setValue(NSNumber(value: s.precip >= 1 ? 0.6 : 0.0), forKey: "wet")

        applyFires(s, waterY: waterY)
        applySignals(s)
        applyProjects(s)
        applyCrowd(s)
        applyRescue(s)

        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: bodySpots())
    }

    private func applySignals(_ s: SceneState) {
        let signal = s.v("signal", 0)
        let snowLies = s.has("snow_ground")
        let sosP = max(s.project("sos"), signal >= 1 ? 1 : 0)
        let shown = Int((Double(sosBoards.count) * sosP).rounded())
        let swept = snowLies && sosP >= 1 && (s.has("sos_swept") || signal >= 2)
        for (i, b) in sosBoards.enumerated() { b.isHidden = i >= shown || swept }
        sosSwept?.isHidden = !swept
        signalFlag?.isHidden = signal < 2
        signalSmoke?.isHidden = signal < 2
        signalSmokePS?.propertyControllers = nightK(s) > 0.5 ? smokeNightLight : smokeDayLight
        signalSmokePS?.acceleration = SCNVector3(CGFloat(0.05 + min(60, s.wind) * 0.02), 0.02, CGFloat(0.02 + min(60, s.wind) * 0.005))
        let radioP = s.project("radio")
        let contact = signal >= 3 || s.has("contact")
        antenna?.isHidden = !(radioP >= 1 || contact)
        antennaDown?.isHidden = !(radioP > 0.05 && radioP < 1 && !contact)
        antennaLamp?.isHidden = !contact
        torchBeam?.isHidden = !(signal >= 3 && nightK(s) > 0.6 && s.precip < 1.5)
    }

    private func applyProjects(_ s: SceneState) {
        let tarp = s.project("tarp")
        tarpPoles?.isHidden = tarp < 0.25
        tarpSheet?.isHidden = tarp < 1
        tarpRoll?.isHidden = !(tarp >= 0.05 && tarp < 1)
        let fb = s.project("firebreak")
        for (i, n) in firebreakStrip.enumerated() { n.isHidden = Double(i) >= fb * 8 - 0.01 }
        let sp = s.project("spring")
        for (i, n) in springPipe.enumerated() { n.isHidden = Double(i) >= sp * Double(springPipe.count) - 0.01 }
        springWater?.isHidden = sp < 1
        let rt = max(s.project("route"), s.has("route_known") ? 1 : 0)
        for (i, n) in routeMarkers.enumerated() { n.isHidden = Double(i) >= rt * Double(routeMarkers.count) - 0.01 }
        trampled?.isHidden = !s.has("snow_ground") || !s.has("wave_hit")
        noticeBoard?.isHidden = !s.has("wave_hit") || s.round < 3
        if supplies.count == 2 {
            supplies[0].isHidden = !s.has("wave_hit")
            supplies[1].isHidden = !(s.has("heli_ever") || s.has("heli") || s.has("sdf"))
        }
        // the shrine: torn roof when its integrity is low, scorched once the fire has been over the top
        haidenDamage?.isHidden = s.shelter >= 35
        haidenRoofNode?.geometry?.firstMaterial?.multiply.contents = s.has("fled_fire") ? NSColor(white: 0.32, alpha: 1) : NSColor.white
    }

    private func applyCrowd(_ s: SceneState) {
        let crowd = s.has("wave_hit") ? max(0, min(80, s.v("crowd", 0))) : 0
        let figures = min(40, Int((crowd / 2).rounded()))
        let storm = s.precip >= 1.5 || s.wind >= 45
        let layout = s.has("fled_fire") ? 2 : ((s.isNight || storm || nightK(s) > 0.6) ? 1 : 0)
        if figures > 0 && crowdLayouts[layout] == nil { crowdLayouts[layout] = buildCrowd(layout) }
        for (l, nodes) in crowdLayouts {
            for (g, n) in nodes.enumerated() { n.isHidden = l != layout || g * 4 >= figures }
        }
    }

    // MARK: - Where everyone is

    private func spots(for s: SceneState) -> [Spot] {
        let T = CGFloat(topY)
        let storm = s.precip >= 1.5 || s.wind >= 45
        if !s.has("wave_hit") {
            // the shaking has just stopped: everyone is out on the street by the training centre,
            // at the foot of the steps (seen from the precinct through the torii)
            let c = SIMD2<Float>(101.8, -107.6)
            return (0..<12).map { i in
                let p = c + SIMD2<Float>(0.75, 0.66) * (Float(i % 4) * 1.5 - 2.2) + SIMD2<Float>(0.66, -0.75) * (Float(i / 4) * 1.6 - 1.6)
                return Spot(CGFloat(p.x), ground(CGFloat(p.x), CGFloat(p.y)), CGFloat(p.y), facing: CGFloat(townYaw) + .pi / 2 + CGFloat(i % 3) * 0.5)
            }
        }
        if s.round <= 1 && (s.has("waited") || s.has("at_school")) {
            // the wave has just gone through: still on the roof they climbed (the centre's stair tower, the school)
            var out: [Spot] = []
            for i in 0..<12 {
                let fi = Float(i)
                if s.has("waited") {
                    let c = SIMD2<Float>(centerXZ.x, centerXZ.y)
                    let local = FinaleV3(19 - 3.2 + Float(i % 3) * 1.4 - 1.4, 9.6 + 3.8, -8.5 + 2.6 + Float(i / 3) * 1.1 - 1.6)
                    let w = FinaleV3(c.x, gy(c.x, c.y), c.y) + finaleRot(local, yaw: townYaw)
                    out.append(Spot(CGFloat(w.x), CGFloat(w.y), CGFloat(w.z), facing: CGFloat(townYaw) + CGFloat(fi), pose: .huddled))
                } else {
                    let c = SIMD2<Float>(schoolXZ.x, schoolXZ.y)
                    let local = FinaleV3(14 + Float(i % 6) * 1.6, 11.8 + 0.08, -3 + Float(i / 6) * 2.4)
                    let w = FinaleV3(c.x, gy(c.x, c.y), c.y) + finaleRot(local, yaw: townYaw)
                    out.append(Spot(CGFloat(w.x), CGFloat(w.y), CGFloat(w.z), facing: CGFloat(townYaw) + .pi / 2, pose: i % 2 == 0 ? .huddled : nil))
                }
            }
            return out
        }
        if s.has("fled_fire") {
            // driven off the top by the fire: on the back slope
            return (0..<12).map { i in
                let x = Float(-6) + Float(i % 4) * 2.6, z = Float(31) + Float(i / 4) * 2.4
                return Spot(CGFloat(x), CGFloat(gy(x, z)), CGFloat(z), facing: .pi, pose: storm || s.isNight ? .huddled : nil)
            }
        }
        if storm {
            // under the hall's eaves and the office's
            var out: [Spot] = []
            let tarpUp = s.project("tarp") >= 1
            for i in 0..<12 {
                if i < 7 {
                    let q = FinaleV3(hallXZ.x, topY + 1.03, hallXZ.y) + finaleRot(FinaleV3(3.55 - Float(i % 2) * 0.75, 0, -3.2 + Float(i / 2) * 2.1), yaw: hallYaw)
                    out.append(Spot(CGFloat(q.x), CGFloat(q.y), CGFloat(q.z), facing: CGFloat(hallYaw) + .pi / 2, pose: .huddled))
                } else if tarpUp {
                    out.append(Spot(10.4 + CGFloat(i - 7) * 1.2, T, 4.8 + CGFloat(i % 2) * 1.0, facing: .pi, pose: .huddled))
                } else {
                    out.append(Spot(9.8, T + 0.3, 7.8 + CGFloat(i - 7) * 1.3, facing: -.pi / 2, pose: .huddled))
                }
            }
            return out
        }
        // the badly hurt lie on blankets: under the tarp once it is up, otherwise by the fire on the hall side
        let tarpUp = s.project("tarp") >= 1
        var lying: [Spot] = []
        for k in 0..<12 {
            if tarpUp && k < 6 {
                lying.append(Spot(9.9 + CGFloat(k % 3) * 1.9, T + 0.05, 2.6 + CGFloat(k / 3) * 2.2, facing: 0))
            } else {
                let a = CGFloat(-1.15) - CGFloat(k) * 0.42
                lying.append(Spot(CGFloat(fireXZ.x) + sin(a) * 4.2, T + 0.05, CGFloat(fireXZ.y) + cos(a) * 4.2, facing: a + .pi / 2))
            }
        }
        let hurt = s.people.filter { $0.injured && !$0.animal }.count
        let others = s.people.count - hurt
        var normal: [Spot]
        if s.isNight || s.fireLit {
            normal = Spot.ring(SCNVector3(CGFloat(fireXZ.x), T, CGFloat(fireXZ.y)), radius: 2.4, count: max(6, others), start: 0.4, y: { _, _ in T })
        } else {
            let day: [(CGFloat, CGFloat, CGFloat)] = [
                (4.8, 1.8, -2.4), (0.8, 0.6, 2.0), (6.5, -17.5, 2.4), (2.0, -19.5, 3.0), (14.6, -3.0, 1.6),
                (13.4, -6.4, 1.2), (-4.5, -4.2, 2.2), (-1.5, -13.0, 0.4), (9.5, -10.0, 2.6), (12.0, -14.0, 2.4),
                (-7.5, 3.0, 2.0), (8.5, 3.0, -2.0)
            ]
            let wave = s.has("heli")
            normal = day.enumerated().map { i, d in Spot(d.0, T, d.1, facing: wave ? 2.6 : d.2, pose: wave && i % 2 == 0 ? .waving : nil) }
        }
        var out: [Spot] = []
        var ni = 0, li = 0
        for p in s.people {
            if p.injured && !p.animal {
                out.append(lying[li % lying.count]); li += 1
            } else {
                out.append(normal[ni % normal.count]); ni += 1
            }
        }
        return out
    }

    private func bodySpots() -> [Spot] {
        let T = CGFloat(topY)
        // a row of blankets along the north-west edge, beyond the SOS, heads to the precinct
        return (0..<12).map { i in
            let a = Float(-2.63) + Float(i) * 0.036
            let r: Float = plateauR - 2.6
            let x = sin(a) * r, z = cos(a) * r
            return Spot(CGFloat(x), T + 0.02, CGFloat(z), facing: CGFloat(a))
        }
    }
}

// MARK: - Finale helpers

fileprivate typealias FinaleV3 = SIMD3<Float>

fileprivate struct FinaleFireSite {
    let node: SCNNode
    let flame: SCNParticleSystem
    let glow: SCNParticleSystem
    let smoke: SCNParticleSystem
    let ember: SCNNode?
    let x: Float, z: Float
    let size: Float
}

fileprivate struct FinaleLot {
    var x: Float, z: Float, y: Float, yaw: Float
    var L: Float, W: Float, H: Float, rise: Float
    var kind: Int
    var wall: FinaleV3, roof: FinaleV3
    var seed: UInt64
    var big: Bool
}

/// sRGB hex → linear RGB (vertex colours are used as linear values).
fileprivate func finaleLin(_ hex: UInt32, _ k: Float = 1) -> FinaleV3 {
    func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return FinaleV3(f(Float((hex >> 16) & 0xFF) / 255), f(Float((hex >> 8) & 0xFF) / 255), f(Float(hex & 0xFF) / 255)) * k
}

/// Rotate roll (z) → pitch (x) → yaw (y), like SceneKit's euler angles.
fileprivate func finaleRot(_ p: FinaleV3, yaw: Float, pitch: Float = 0, roll: Float = 0) -> FinaleV3 {
    var q = p
    if roll != 0 { let c = cos(roll), s = sin(roll); q = FinaleV3(q.x * c - q.y * s, q.x * s + q.y * c, q.z) }
    if pitch != 0 { let c = cos(pitch), s = sin(pitch); q = FinaleV3(q.x, q.y * c - q.z * s, q.y * s + q.z * c) }
    if yaw != 0 { let c = cos(yaw), s = sin(yaw); q = FinaleV3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c) }
    return q
}

fileprivate struct FinaleRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x2545F491 }
    mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
    mutating func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    mutating func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(next() * Float(a.count)))] }
}

/// Packs a triangle mesh into SceneKit sources (normals from the faces unless given).
fileprivate func finaleGeometry(_ pts: [FinaleV3], _ cols: [FinaleV3], _ uvs: [SIMD2<Float>]?, _ idx: [UInt32], normals: [FinaleV3]? = nil) -> SCNGeometry {
    let n = pts.count
    var nrm = normals ?? [FinaleV3](repeating: .zero, count: n)
    if normals == nil {
        idx.withUnsafeBufferPointer { ib in
            pts.withUnsafeBufferPointer { pb in
                nrm.withUnsafeMutableBufferPointer { nb in
                    var t = 0
                    let cnt = ib.count
                    while t + 2 < cnt {
                        let a = Int(ib[t]), b = Int(ib[t + 1]), c = Int(ib[t + 2])
                        let e1 = pb[b] - pb[a], e2 = pb[c] - pb[a]
                        let fn = FinaleV3(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
                        nb[a] += fn; nb[b] += fn; nb[c] += fn
                        t += 3
                    }
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
        sources.append(SCNGeometrySource(data: tex.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                                         componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8))
    }
    let el = SCNGeometryElement(data: idx.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                                primitiveCount: idx.count / 3, bytesPerIndex: 4)
    return SCNGeometry(sources: sources, elements: [el])
}

/// Merged triangle mesh with vertex colours: many small parts, one node.
fileprivate struct FinaleMesh {
    var pts: [FinaleV3] = []
    var cols: [FinaleV3] = []
    var uvs: [SIMD2<Float>] = []
    var idx: [UInt32] = []
    var withUV = false

    mutating func reserve(_ v: Int) { pts.reserveCapacity(v); cols.reserveCapacity(v); idx.reserveCapacity(v * 3 / 2) }

    func node(_ m: SCNMaterial, shadow: Bool = true) -> SCNNode {
        guard !idx.isEmpty else { return SCNNode() }
        let g = finaleGeometry(pts, cols, withUV ? uvs : nil, idx)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.castsShadow = shadow
        return n
    }

    mutating func append(_ o: FinaleMesh) {
        let base = UInt32(pts.count)
        pts += o.pts
        cols += o.cols
        if withUV { uvs += o.withUV ? o.uvs : [SIMD2<Float>](repeating: .zero, count: o.pts.count) }
        idx += o.idx.map { $0 + base }
    }

    /// Appends another mesh rotated (roll → pitch → yaw) and moved to `p`.
    mutating func append(_ o: FinaleMesh, at p: FinaleV3, yaw: Float, pitch: Float = 0, roll: Float = 0) {
        let base = UInt32(pts.count)
        pts.reserveCapacity(pts.count + o.pts.count)
        for q in o.pts { pts.append(p + finaleRot(q, yaw: yaw, pitch: pitch, roll: roll)) }
        cols += o.cols
        if withUV { uvs += o.withUV ? o.uvs : [SIMD2<Float>](repeating: .zero, count: o.pts.count) }
        idx += o.idx.map { $0 + base }
    }

    private mutating func uv(_ u: Float, _ v: Float) { if withUV { uvs.append(SIMD2(u, v)) } }

    /// Counter-clockwise seen from the front.
    mutating func quad(_ a: FinaleV3, _ b: FinaleV3, _ c: FinaleV3, _ d: FinaleV3, _ col: FinaleV3) {
        let base = UInt32(pts.count)
        pts.append(a); pts.append(b); pts.append(c); pts.append(d)
        cols.append(col); cols.append(col); cols.append(col); cols.append(col)
        if withUV { uvs.append(SIMD2(0, 1)); uvs.append(SIMD2(1, 1)); uvs.append(SIMD2(1, 0)); uvs.append(SIMD2(0, 0)) }
        idx.append(base); idx.append(base + 1); idx.append(base + 2)
        idx.append(base); idx.append(base + 2); idx.append(base + 3)
    }

    mutating func tri(_ a: FinaleV3, _ b: FinaleV3, _ c: FinaleV3, _ col: FinaleV3) {
        let base = UInt32(pts.count)
        pts.append(a); pts.append(b); pts.append(c)
        cols.append(col); cols.append(col); cols.append(col)
        if withUV { uvs.append(SIMD2(0, 1)); uvs.append(SIMD2(1, 1)); uvs.append(SIMD2(0.5, 0)) }
        idx.append(base); idx.append(base + 1); idx.append(base + 2)
    }

    /// Flat-shaded box, half extents `h`, rotated roll → pitch → yaw about its centre.
    mutating func box(_ c: FinaleV3, _ h: FinaleV3, _ col: FinaleV3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, top: FinaleV3? = nil, bottom: Bool = true) {
        var P = [FinaleV3](repeating: .zero, count: 8)
        for i in 0..<8 {
            let sx: Float = (i & 1) == 0 ? -1 : 1, sy: Float = (i & 2) == 0 ? -1 : 1, sz: Float = (i & 4) == 0 ? -1 : 1
            P[i] = c + finaleRot(FinaleV3(sx * h.x, sy * h.y, sz * h.z), yaw: yaw, pitch: pitch, roll: roll)
        }
        // index = x + 2y + 4z
        quad(P[1], P[3], P[7], P[5], col)                 // +x
        quad(P[0], P[4], P[6], P[2], col)                 // −x
        quad(P[2], P[6], P[7], P[3], top ?? col)          // +y
        if bottom { quad(P[0], P[1], P[5], P[4], col) }   // −y
        quad(P[4], P[5], P[7], P[6], col)                 // +z
        quad(P[0], P[2], P[3], P[1], col)                 // −z
    }

    /// Tapered cylinder from `a` to `b`.
    mutating func tube(_ a: FinaleV3, _ b: FinaleV3, _ r0: Float, _ r1: Float, _ col: FinaleV3, segs: Int = 6, cap: Bool = false) {
        let axis = b - a
        let len = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        guard len > 1e-4 else { return }
        let w = axis / len
        let up: FinaleV3 = abs(w.y) < 0.95 ? FinaleV3(0, 1, 0) : FinaleV3(1, 0, 0)
        var u = FinaleV3(up.y * w.z - up.z * w.y, up.z * w.x - up.x * w.z, up.x * w.y - up.y * w.x)
        u /= sqrt(u.x * u.x + u.y * u.y + u.z * u.z)
        let v = FinaleV3(w.y * u.z - w.z * u.y, w.z * u.x - w.x * u.z, w.x * u.y - w.y * u.x)
        let base = UInt32(pts.count)
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            let d = u * cos(t) + v * sin(t)
            pts.append(a + d * r0); cols.append(col)
            pts.append(b + d * r1); cols.append(col)
            if withUV { uvs.append(SIMD2(Float(j) / Float(segs), 0)); uvs.append(SIMD2(Float(j) / Float(segs), len)) }
        }
        let S = UInt32(segs)
        for j in 0..<S {
            let p0 = base + j * 2, p1 = p0 + 1
            let q0 = base + ((j + 1) % S) * 2, q1 = q0 + 1
            idx += [p0, q0, p1, q0, q1, p1]
        }
        if cap {
            let c0 = UInt32(pts.count)
            pts.append(b); cols.append(col); uv(0, 0)
            for j in 0..<S { idx += [c0, base + j * 2 + 1, base + ((j + 1) % S) * 2 + 1] }
        }
    }

    /// A cone standing on `base` (tree crowns, roofs of turrets).
    mutating func cone(_ base: FinaleV3, _ r: Float, _ h: Float, _ col: FinaleV3, segs: Int = 6) {
        let b0 = UInt32(pts.count)
        pts.append(base + FinaleV3(0, h, 0)); cols.append(col * 1.12); uv(0.5, 0)
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            pts.append(base + FinaleV3(cos(t) * r, 0, sin(t) * r)); cols.append(col * 0.82); uv(Float(j) / Float(segs), 1)
        }
        let S = UInt32(segs)
        for j in 0..<S { idx += [b0, b0 + 1 + (j + 1) % S, b0 + 1 + j] }
    }

    /// Lumpy ellipsoid (tree crowns, statues, debris heaps): darker underneath.
    mutating func blob(_ c: FinaleV3, _ r: FinaleV3, _ col: FinaleV3, _ nz: SK.Noise, seed: Float, jitter: Float = 0.22, rings: Int = 5, segs: Int = 8, under: Float = 0.55, vary: Float = 0.25) {
        let base = UInt32(pts.count)
        for i in 0...rings {
            let v = Float(i) / Float(rings)
            let phi = v * .pi
            for j in 0..<segs {
                let th = Float(j) / Float(segs) * 2 * .pi
                let d = FinaleV3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                let n = nz.value(d.x * 1.7 + seed, d.z * 1.7 + d.y * 1.2 + seed * 0.37)
                let k = 1 + jitter * (2 * n - 1)
                pts.append(c + FinaleV3(d.x * r.x, d.y * r.y, d.z * r.z) * k)
                let shade = under + (1 - under) * (0.5 + 0.5 * d.y)
                cols.append(col * shade * (1 - vary * 0.5 + vary * n))
                uv(Float(j) / Float(segs), v)
            }
        }
        let S = UInt32(segs)
        for i in 0..<UInt32(rings) {
            for j in 0..<S {
                let a = base + i * S + j, b = base + i * S + (j + 1) % S
                let cc = a + S, d = b + S
                idx += [a, b, cc, b, d, cc]
            }
        }
    }

    /// Flat irregular patch lying in a horizontal plane.
    mutating func patch(_ c: FinaleV3, _ radius: Float, _ col: FinaleV3, _ nz: SK.Noise, seed: Float, aspect: Float = 1, yaw: Float = 0, segs: Int = 10, rough: Float = 0.35) {
        let base = UInt32(pts.count)
        pts.append(c); cols.append(col); uv(0.5, 0.5)
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            let n = nz.value(cos(t) * 1.3 + seed, sin(t) * 1.3 + seed * 0.7)
            let rr = radius * (1 - rough + 2 * rough * n)
            pts.append(c + finaleRot(FinaleV3(cos(t) * rr, 0, sin(t) * rr * aspect), yaw: yaw)); cols.append(col * 0.94)
            uv(0.5 + 0.5 * cos(t), 0.5 + 0.5 * sin(t))
        }
        let S = UInt32(segs)
        for j in 0..<S { idx += [base, base + 1 + (j + 1) % S, base + 1 + j] }
    }

    /// A sagging rope or wire from `a` to `b`.
    mutating func rope(_ a: FinaleV3, _ b: FinaleV3, sag: Float, r: Float, _ col: FinaleV3, segs: Int = 8, sides: Int = 5) {
        var prev = a
        for i in 1...segs {
            let t = Float(i) / Float(segs)
            let p = a + (b - a) * t - FinaleV3(0, sag * 4 * t * (1 - t), 0)
            tube(prev, p, r, r, col, segs: sides)
            prev = p
        }
    }

    /// Hip roof over an eave rectangle centred at `c` (ridge along local x, `ridgeK` of the way).
    mutating func hipRoof(_ c: FinaleV3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, ridgeK: Float, _ col: FinaleV3) {
        var L = halfL, W = halfW, yw = yaw
        if W > L { swap(&L, &W); yw += .pi / 2 }
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yw) }
        let Le = L + over, We = W + over
        let drop = over * rise / max(0.1, W)
        let R = max(0, L - W) + (L - max(0, L - W)) * (1 - ridgeK)
        quad(P(-Le, -drop, We), P(Le, -drop, We), P(R, rise, 0), P(-R, rise, 0), col)
        quad(P(Le, -drop, -We), P(-Le, -drop, -We), P(-R, rise, 0), P(R, rise, 0), col * 0.78)
        tri(P(Le, -drop, We), P(Le, -drop, -We), P(R, rise, 0), col * 0.9)
        tri(P(-Le, -drop, -We), P(-Le, -drop, We), P(-R, rise, 0), col * 0.86)
        // soffits so the eaves read from below
        quad(P(-Le, -drop, We), P(-Le, -drop, -We), P(Le, -drop, -We), P(Le, -drop, We), col * 0.4)
    }

    /// Gable roof (ridge along local x); the gable triangles go into `walls`.
    mutating func gableRoof(_ c: FinaleV3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ col: FinaleV3, gable: FinaleV3, walls: inout FinaleMesh) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> FinaleV3 { c + finaleRot(FinaleV3(x, y, z), yaw: yaw) }
        let Le = halfL + over * 0.6, We = halfW + over
        let drop = over * rise / max(0.1, halfW)
        quad(P(-Le, -drop, We), P(Le, -drop, We), P(Le, rise, 0), P(-Le, rise, 0), col)
        quad(P(Le, -drop, -We), P(-Le, -drop, -We), P(-Le, rise, 0), P(Le, rise, 0), col * 0.78)
        quad(P(-Le, -drop, We), P(-Le, rise, 0), P(Le, rise, 0), P(Le, -drop, We), col * 0.4)
        quad(P(Le, -drop, -We), P(Le, rise, 0), P(-Le, rise, 0), P(-Le, -drop, -We), col * 0.4)
        walls.tri(P(halfL, 0, halfW), P(halfL, 0, -halfW), P(halfL, rise, 0), gable)
        walls.tri(P(-halfL, 0, -halfW), P(-halfL, 0, halfW), P(-halfL, rise, 0), gable)
    }

    /// A grid sheet given by a position function over (u, v) ∈ [0, 1]².
    mutating func sheet(nu: Int, nv: Int, _ col: FinaleV3, _ p: (Float, Float) -> FinaleV3) {
        let base = UInt32(pts.count)
        for j in 0...nv {
            for i in 0...nu {
                let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                pts.append(p(u, v)); cols.append(col); uv(u, v)
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

    /// Lofted hull from stations (x, half-beam, gunwale height, keel depth), bow toward +x.
    mutating func hull(_ st: [(Float, Float, Float, Float)], _ col: FinaleV3, stripe: FinaleV3, deck: FinaleV3) {
        func sec(_ s: (Float, Float, Float, Float)) -> [FinaleV3] {
            let (x, b, gh, kd) = s
            return [FinaleV3(x, gh, b), FinaleV3(x, gh * 0.55 + kd * 0.45, b * 0.97), FinaleV3(x, kd * 0.5, b * 0.8), FinaleV3(x, kd, 0),
                    FinaleV3(x, kd * 0.5, -b * 0.8), FinaleV3(x, gh * 0.55 + kd * 0.45, -b * 0.97), FinaleV3(x, gh, -b)]
        }
        for i in 0..<(st.count - 1) {
            let a = sec(st[i]), b = sec(st[i + 1])
            for k in 0..<6 {
                let c = (k == 0 || k == 5) ? stripe : (k == 2 || k == 3 ? col * 0.85 : col)
                quad(a[k], b[k], b[k + 1], a[k + 1], c)
            }
            quad(FinaleV3(st[i].0, st[i].2 - 0.1, -st[i].1 * 0.96), FinaleV3(st[i + 1].0, st[i + 1].2 - 0.1, -st[i + 1].1 * 0.96),
                 FinaleV3(st[i + 1].0, st[i + 1].2 - 0.1, st[i + 1].1 * 0.96), FinaleV3(st[i].0, st[i].2 - 0.1, st[i].1 * 0.96), deck)
        }
        let s0 = sec(st[0])
        for k in 0..<6 { tri(s0[0], s0[k + 1 < 7 ? k + 1 : 6], s0[k], col * 0.9) }
    }

    /// A tetrapod (four concrete legs from a centre).
    mutating func tetrapod(_ c: FinaleV3, _ s: Float, _ col: FinaleV3, yaw: Float, pitch: Float) {
        let legs: [FinaleV3] = [FinaleV3(0, 1, 0), FinaleV3(0.943, -0.333, 0), FinaleV3(-0.471, -0.333, 0.816), FinaleV3(-0.471, -0.333, -0.816)]
        for l in legs {
            let d = finaleRot(l, yaw: yaw, pitch: pitch)
            tube(c, c + d * s, 0.36 * s, 0.22 * s, col, segs: 5, cap: true)
        }
    }
}

/// Snow settling on upward faces (shared by the vertex-coloured materials).
fileprivate let finaleSnowShader = """
#pragma arguments
float snowAmt;
#pragma declaration
float fs_hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }
float fs_noise(float2 p) {
    float2 i = floor(p); float2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(fs_hash(i), fs_hash(i + float2(1, 0)), f.x), mix(fs_hash(i + float2(0, 1)), fs_hash(i + float2(1, 1)), f.x), f.y);
}
#pragma body
if (snowAmt > 0.001) {
    float3 fsN = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 fsP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float2 fsQ = float2(fsP.x * 0.8 + fsP.z * 0.6, -fsP.x * 0.6 + fsP.z * 0.8);
    float fsH = fs_noise(fsQ * 0.7) * 0.5 + fs_noise(fsQ * 1.9 + 3.7) * 0.3 + fs_noise(fsQ * 5.3 + 1.1) * 0.2;
    float fsK = smoothstep(0.3, 0.85, fsN.y + (fsH - 0.5) * 0.5) * snowAmt;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.70, 0.72, 0.77), fsK);
}
"""

/// Ground: vertex colour broken up by noise; mud and wreckage below the run-up after the wave;
/// charred slopes under the hill fire; snow; wet darkening.
fileprivate let finaleTerrainShader = """
#pragma arguments
float wreck;
float runup;
float snowAmt;
float burnY;
float wet;
#pragma declaration
float ft_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float ft_noise(float3 x) {
    float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(ft_hash(i + float3(0,0,0)), ft_hash(i + float3(1,0,0)), f.x),
                   mix(ft_hash(i + float3(0,1,0)), ft_hash(i + float3(1,1,0)), f.x), f.y),
               mix(mix(ft_hash(i + float3(0,0,1)), ft_hash(i + float3(1,0,1)), f.x),
                   mix(ft_hash(i + float3(0,1,1)), ft_hash(i + float3(1,1,1)), f.x), f.y), f.z);
}
float ft_fbm(float3 p) { float a = 0.5; float s = 0.0; for (int k = 0; k < 4; k++) { s += a * ft_noise(p); p *= 2.07; a *= 0.5; } return s; }
#pragma body
float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
float3 c = _surface.diffuse.rgb;
float forest = 1.0 - smoothstep(0.06, 0.14, dot(c, float3(0.3, 0.59, 0.11)));
float3 q = wp * 0.11;
float fw = length(fwidth(q));
float n = mix(ft_fbm(q), 0.5, smoothstep(0.25, 0.9, fw));
float3 q2 = wp * 0.9;
float fw2 = length(fwidth(q2));
float fine = mix(ft_fbm(q2), 0.5, smoothstep(0.2, 0.8, fw2));
c *= 0.78 + 0.44 * n * (0.75 + 0.5 * fine);
if (forest > 0.01) {
    float3 q3 = wp * 0.32;
    float fw3 = length(fwidth(q3));
    float crown = mix(ft_noise(q3) * 0.65 + ft_noise(q3 * 2.3) * 0.35, 0.5, smoothstep(0.3, 1.0, fw3));
    c *= mix(1.0, 0.45 + 1.1 * smoothstep(0.25, 0.75, crown), forest);
}
float m = 0.0;
if (wreck > 0.5) {
    float edge = runup + (n - 0.5) * 4.0;
    m = (1.0 - smoothstep(edge - 1.2, edge + 0.4, wp.y)) * smoothstep(-1.6, -0.9, wp.y);
    float blot = ft_noise(wp * 0.045);
    float3 mud = mix(float3(0.065, 0.055, 0.045), float3(0.15, 0.125, 0.095), smoothstep(0.3, 0.75, blot));
    mud *= 0.75 + 0.5 * fine;
    float sp = ft_hash(floor(wp * 3.1));
    float spk = mix(step(0.94, sp), 0.06, smoothstep(0.15, 0.6, fw2 * 3.4));
    mud = mix(mud, float3(0.30, 0.25, 0.18), spk * 0.6);
    c = mix(c, mud, m);
}
if (burnY > -50.0) {
    float r = length(wp.xz);
    float b = (1.0 - smoothstep(burnY - 2.0, burnY + 1.5, wp.y + (n - 0.5) * 5.0)) * (1.0 - smoothstep(88.0, 100.0, r)) * smoothstep(-30.0, -5.0, -wp.z);
    b *= smoothstep(23.0, 27.0, r + (n - 0.5) * 6.0);      // the gravel of the precinct does not burn
    float ash = smoothstep(0.45, 0.8, ft_noise(wp * 0.6));
    c = mix(c, mix(float3(0.025, 0.023, 0.021), float3(0.16, 0.155, 0.15), ash * 0.7) * (0.7 + 0.6 * fine), b * (1.0 - m));
}
if (snowAmt > 0.001) {
    float s = smoothstep(0.42, 0.78, wn.y + (n - 0.5) * 0.5 + (fine - 0.5) * 0.25) * snowAmt * (1.0 - 0.55 * m);
    s *= mix(1.0, 0.12 + 0.3 * smoothstep(0.4, 0.75, fine), forest);
    c = mix(c, float3(0.68, 0.70, 0.75), s);
}
c *= 1.0 - 0.28 * wet;
_surface.diffuse.rgb = c;
"""

/// Gentle swell on the water sheet (vertex shader), as in `SK.water`.
fileprivate let finaleWaveShader = """
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
"""

/// Water colour: the sea, or black silt-laden flood water; muddy on the land side of the coast.
fileprivate let finaleWaterShader = """
#pragma arguments
float murk;
float puddle;
float4 seaCol;
float4 mudCol;
#pragma body
float3 fwP = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
float fwShore = 158.0 + max(0.0, -60.0 - fwP.z) * 0.33 + max(0.0, fwP.z + 60.0) * 0.45;
float fwLand = 1.0 - smoothstep(fwShore - 20.0, fwShore + 45.0, fwP.x);
float fwK = max(murk, puddle * fwLand);
float3 fwC = mix(seaCol.rgb, mudCol.rgb, fwK);
_surface.diffuse.rgb = fwC * (0.7 + 0.6 * _surface.diffuse.r);
_surface.roughness = mix(_surface.roughness, 0.55, fwLand * puddle);
"""

/// Small procedural textures.
fileprivate enum FinaleTex {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func hash(_ a: Int, _ b: Int, _ s: Int) -> Float {
        var h = UInt64(bitPattern: Int64((a &* 73856093) ^ (b &* 19349663) ^ (s &* 83492791)))
        h = (h ^ (h >> 33)) &* 0xff51afd7ed558ccd
        h = (h ^ (h >> 33)) &* 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    static func tnoise(_ x: Float, _ y: Float, _ p: Int, _ seed: Int) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        func h(_ a: Int, _ b: Int) -> Float { hash(((a % p) + p) % p, ((b % p) + p) % p, seed) }
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        return (h(xi, yi) * (1 - u) + h(xi + 1, yi) * u) * (1 - v) + (h(xi, yi + 1) * (1 - u) + h(xi + 1, yi + 1) * u) * v
    }

    static func image(_ key: String, _ w: Int, _ h: Int, _ f: (Int, Int) -> SIMD4<Float>) -> NSImage {
        lock.lock()
        let hit = cache[key]
        lock.unlock()
        if let hit { return hit }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let c = f(x, y)
                let a = max(0, min(1, c.w))
                let i = (y * w + x) * 4
                px[i] = UInt8(max(0, min(1, c.x)) * a * 255)
                px[i + 1] = UInt8(max(0, min(1, c.y)) * a * 255)
                px[i + 2] = UInt8(max(0, min(1, c.z)) * a * 255)
                px[i + 3] = UInt8(a * 255)
            }
        }
        let img = SK.image(from: px, size: w, height: h)
        lock.lock()
        cache[key] = img
        lock.unlock()
        return img
    }

    /// Matted floating wreckage: boards and scraps in browns and greys, gaps of open water (alpha).
    static func wreckMat() -> NSImage {
        let w = 128
        var px = [Float](repeating: 0, count: w * w * 4)
        var s: UInt64 = 77
        func rnd() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
        let cols: [SIMD3<Float>] = [SIMD3(0.42, 0.34, 0.25), SIMD3(0.50, 0.42, 0.31), SIMD3(0.33, 0.27, 0.21), SIMD3(0.55, 0.52, 0.46),
                                    SIMD3(0.40, 0.39, 0.36), SIMD3(0.62, 0.56, 0.44), SIMD3(0.78, 0.76, 0.70), SIMD3(0.25, 0.37, 0.55), SIMD3(0.60, 0.22, 0.18)]
        for _ in 0..<330 {
            let cx = rnd() * Float(w), cy = rnd() * Float(w)
            let len = 3 + rnd() * 13, wid = 1 + rnd() * 2.5
            let a = rnd() * 6.28
            let ca = cos(a), sa = sin(a)
            let c = cols[min(cols.count - 1, Int(rnd() * rnd() * Float(cols.count)))] * (0.8 + 0.3 * rnd())
            let r = Int(len) + 2
            for dy in -r...r {
                for dx in -r...r {
                    let u = Float(dx) * ca + Float(dy) * sa, v = -Float(dx) * sa + Float(dy) * ca
                    if abs(u) > len / 2 || abs(v) > wid / 2 { continue }
                    let x = ((Int(cx) + dx) % w + w) % w, y = ((Int(cy) + dy) % w + w) % w
                    let i = (y * w + x) * 4
                    px[i] = c.x; px[i + 1] = c.y; px[i + 2] = c.z; px[i + 3] = 1
                }
            }
        }
        return image("wreckmat", w, w) { x, y in
            let i = (y * w + x) * 4
            return SIMD4(px[i], px[i + 1], px[i + 2], px[i + 3])
        }
    }

    /// A ragged puff for smoke particles (white; tinted by the particle colour).
    static func puff() -> NSImage {
        image("puff", 64, 64) { x, y in
            let u = (Float(x) - 31.5) / 32, v = (Float(y) - 31.5) / 32
            let r = sqrt(u * u + v * v)
            let n = tnoise(Float(x) / 9, Float(y) / 9, 7, 11) * 0.6 + tnoise(Float(x) / 4, Float(y) / 4, 16, 12) * 0.4
            let a = max(0, 1 - r * (1.05 + 0.5 * n)) 
            return SIMD4(SIMD3(repeating: 0.85 + 0.15 * n), min(1, a * a * 1.6))
        }
    }

    /// Fading torch beam (emission along the cone: bright at the torch, gone at the far end).
    static func beam() -> NSImage {
        image("beam", 4, 64) { _, y in
            let t = Float(y) / 63
            let k = pow(1 - t, 2.2) * 0.35
            return SIMD4(SIMD3(1.0, 0.95, 0.82) * k, 1)
        }
    }

    /// Grey silt clouds for the water (multiplied by the water colour in the shader).
    static func silt() -> NSImage {
        image("silt", 128, 128) { x, y in
            let u = Float(x) / 16, v = Float(y) / 16
            let n = tnoise(u, v, 8, 3) * 0.6 + tnoise(u * 2, v * 2, 16, 4) * 0.4
            return SIMD4(SIMD3(repeating: 0.3 + 0.4 * n), 1)
        }
    }
}
