import SceneKit
import AppKit

/// 洪水 — 1998 年 8 月，湖北江汉平原永丰垸溃垸以后，陈家的两层砖混小楼。
///
/// 布局（米）：y = 0 是宅基地地面，也就是 `var.level`（屋外水深）的零点，水面就在 y = level。
/// 小楼 10.2 × 8 m，正面朝南（+z）：一楼层高 3.2 m，二楼地面 3.3 m（正中挑出一个阳台，
/// 下面两根柱子），平顶晒台 6.4 m，四周水泥宝瓶栏杆，东北角是楼梯间（顶 9 m）。
/// 南面是红砖外墙配白瓷砖门脸；东墙是迎水面，漂来的房梁撞的、裂缝出现的都是这面墙。
/// 门前左边一棵大樟树，东北 33 m 是隔壁周家的平房（屋脊上站着周家爷孙），
/// 北面约 250 m 是大堤（真实距离两公里，为了看得清拉近了），堤上有帐篷、红旗、人和卡车。
///
/// 随局面变化：
/// - `var.level` → 水面高度、墙上的湿痕和退水后的泥痕；水没上二楼时人在阳台和屋顶，
///   上了二楼（`flag.on_roof` 或 level ≥ 3.3）全在屋顶；奶奶的竹床跟着搬。
/// - `var.signal` → 晾衣竿上的红被面（≥12）、石灰写的 SOS（≥25，下雨变淡）、
///   写着“救命”的白床单（≥50）、电视天线上的红布（≥75）。
/// - 工程 `awning`（竹竿 → 彩条布凉棚）、`raft`（屋顶上拆门板、绑塑料桶 → 窗下漂着的筏子，
///   `coffin_used` 时绑的是奶奶的寿材，`raft_gone` 时不见了）。
/// - `cracks` / `collapse_coming` / 低完好度 → 东墙裂缝、渗泥水；`collapsed` → 房子歪倒下沉。
/// - 冲锋舟：`spotted` 远处开过来，事件 boat / boat_return / dehou_alone 靠在屋前（船上坐着
///   9 + `var.seats` 个人），r_full_boat 擦身而过，r_boat_far 远处树梢间，救援结局三条船，
///   `var.search` 越大远处搜救的船越多；r_fisherman / wan_go 渔民的小划子；r_airdrop 直升机；
///   swim_pick / soldier_go 水里游向大堤的人。
/// - `var.filth` → 水上的污物和水色；`basins` 盆盆罐罐、`wok` 大铁锅、`plastic` 农膜、
///   `hygiene` 马桶和草帘、`pig_roof` 屋顶上的猪、res.wetwood 摊开晒的湿柴、res.fuel 干柴；
///   r_dead_pig 窗下的死猪、r_debris 撞墙的房梁；r_neighbor / neighbor_fate 隔壁屋脊上的人。
/// - 雨：屋顶水泥变湿变暗、晾的衣服收了、浪大；夜里：火盆、马灯、手电、二楼窗里的灯、堤上的灯。
final class FloodScene: ScenarioScene {
    private let noise = SK.Noise(seed: 1998)
    private let roofY: CGFloat = 6.4
    private let floor2: CGFloat = 3.3
    private let brazier = (x: CGFloat(-0.2), z: CGFloat(-1.0))

    // MARK: Nodes the game changes

    private var water: SCNNode?
    private var waterMat: SCNMaterial?
    private let floatRoot = SCNNode()          // everything that floats: y = water level
    private var foamMat: SCNMaterial?
    private let house = SCNNode()
    private var concreteMat: SCNMaterial?
    private var glassMat: SCNMaterial?
    private var wetBand: SCNNode?
    private var mudBand: SCNNode?
    private var mudLine: SCNNode?
    private var crackA: SCNNode?
    private var crackB: SCNNode?
    private var rubble: SCNNode?
    private var laundry: SCNNode?
    private var bed: SCNNode?
    private var quiltFlag: SCNNode?
    private var sos: SCNNode?
    private var sosMat: SCNMaterial?
    private var helpSheet: SCNNode?
    private var antennaRag: SCNNode?
    private var awningPoles: SCNNode?
    private var awningSheet: SCNNode?
    private var raftWork: SCNNode?
    private var raftWorkLate: SCNNode?
    private var raft: SCNNode?
    private var raftCoffin: SCNNode?
    private var raftRope: SCNNode?
    private var basins: SCNNode?
    private var wok: SCNNode?
    private var latrine: SCNNode?
    private var filmSpread: SCNNode?
    private var filmRoll: SCNNode?
    private var woodSpread: SCNNode?
    private var fuelStack: [SCNNode] = []
    private var roofPig: SCNNode?
    private var scum: [SCNNode] = []
    private var pigNear: SCNNode?
    private var pigFar: SCNNode?
    private var beam: SCNNode?
    private var boats: [SCNNode] = []          // three assault boats
    private var boatCrowd: [[SCNNode]] = []    // passengers per boat
    private var boatWakes: [SCNNode] = []
    private var boatLight: SCNNode?
    private var sampan: SCNNode?
    private var fisherman: SCNNode?
    private var heli: SCNNode?
    private var swimmer: SCNNode?
    private var swimBarrel: SCNNode?
    private var swimVest: SCNNode?
    private var zhouGrandpa: SCNNode?
    private var zhouGrandpaSit: SCNNode?
    private var zhouKid: SCNNode?
    private var strawHat: SCNNode?
    private var lampLight: SCNNode?
    private var lampMat: SCNMaterial?
    private var torch: SCNNode?
    private var dikeLights: SCNNode?
    private var farFires: SCNNode?
    private var highWater: CGFloat = 0

    required init() {
        super.init()
        skyStyle = .desert                // hazy, whitish summer sky over the plain
        sunPeak = 74                    // 30°N in early August
        sunAzimuth = 72                 // morning sun from the east-south-east: front and east wall lit
        exposure = -0.1
        sunScale = 0.92
        iblScale = 1.0
        hazeColor = SK.rgb(0xC5C3B5)    // humid summer haze over the water
        stormColor = SK.rgb(0x80868A)
        nightColor = SK.rgb(0x0A0D12)
        clearVisibility = 1400
        precipKind = .rain
        weatherArea = 110
        weatherCenter = SCNVector3(2, 24, 6)
        cameraTarget = SCNVector3(0.4, 4.7, 0.8)
        cameraDistance = 27
        cameraYaw = 28
        cameraPitch = 10
        cameraFOV = 46
        minPitch = 2
    }

    // MARK: Sky

    private var hazeKey = ""
    private var hazeSky: NSImage?

    /// Clear days on the flooded plain are hazy and whitish, not the deep blue of a physical sky:
    /// replace the daylight sky (and the light it gives) with a humid haze gradient.
    override func updateEnvironment(_ s: SceneState) {
        super.updateEnvironment(s)
        let elev = s.sunElevation(peak: sunPeak)
        let overcast = max(0, min(1, (1 - s.sun) * 1.15 + s.precip * 0.2))
        if elev > -7 && elev < 14 {
            let k = CGFloat(max(0.12, min(1, (elev + 2) / 16)))
            sunNode.light?.shadowColor = NSColor(white: 0, alpha: CGFloat(0.6 * (1 - overcast)) * k)
        }
        guard elev > -7, overcast <= 0.6 else { hazeKey = ""; return }
        let key = "\(Int((elev / 3).rounded()))|\(Int(overcast * 8))"
        if key != hazeKey || hazeSky == nil {
            hazeKey = key
            let low = CGFloat(max(0, min(1, 1 - elev / 22)))          // warm haze when the sun is low
            let dim = CGFloat(max(0, min(1, (4 - elev) / 11)))          // twilight darkening
            var top = SK.rgb(0x86A6C6).blended(withFraction: CGFloat(overcast) * 0.8, of: SK.rgb(0xA9B2BA)) ?? .gray
            var hor = SK.rgb(0xDEDDD3).blended(withFraction: low * 0.6, of: SK.rgb(0xEDBF8E)) ?? .gray
            top = top.blended(withFraction: dim * 0.85, of: SK.rgb(0x101828)) ?? top
            hor = hor.blended(withFraction: dim * 0.55, of: SK.rgb(0x5A3A3A)) ?? hor
            hazeSky = SK.gradientSky(top: top, horizon: hor)
        }
        scene.background.contents = hazeSky
        scene.lightingEnvironment.contents = hazeSky
    }

    // MARK: Build

    override func build(_ s: SceneState) {
        world.addChildNode(house)
        world.addChildNode(floatRoot)
        buildGround()
        buildWater()
        buildHouse()
        buildRoof()
        buildSignals()
        buildProjects()
        buildVillage()
        buildPoles()
        buildDike()
        buildFarland()
        buildDebris()
        buildBoats()
        buildLights()
        // 火盆: an old iron basin on the roof (the fire is also a night signal)
        addFire(at: SCNVector3(brazier.x, roofY + 0.16, brazier.z), scale: 0.4, style: .campfire)
    }

    private func vcMat(_ roughness: CGFloat = 0.85, doubleSided: Bool = false) -> SCNMaterial {
        SK.mat(.white, roughness: roughness, doubleSided: doubleSided)
    }

    /// Clay roof tiles in rows (tinted grey or red by the vertex colour).
    private func roofMat() -> SCNMaterial {
        FloodTex.material(FloodTex.roofTiles(), normal: FloodTex.roofTilesNormal(), roughness: 0.85, tile: 1)
    }

    private func groundH(_ x: Float, _ z: Float) -> Float {
        // the homestead plot (宅基地) is the zero of `level`; the paddies around lie ~0.8 m lower
        let r = sqrt(x * x + z * z)
        var h: Float = -0.8 + 0.8 * (1 - SK.smoothstep(13, 19, r))
        h += (noise.value(x / 37, z / 37) - 0.5) * 0.4 * SK.smoothstep(19, 40, r)
        return h
    }

    private func buildGround() {
        let t = SK.terrain(size: 1400, segments: 90, height: { x, z in self.groundH(x, z) }, color: { x, _, z, _ in
            SK.mix(floodLin(0x4A3F2E), floodLin(0x62553A), self.noise.value(x / 9, z / 9))
        }, material: vcMat(1), uvRepeat: 40)
        t.castsShadow = false
        world.addChildNode(t)
    }

    /// The flood: an opaque sheet of yellow-brown water to the horizon, plus foam streaks
    /// drawn out by the current around the house.
    private func buildWater() {
        let w = SK.water(size: 2600, color: .white, amplitude: 0.04, choppiness: 0.45, transparency: 1, roughness: 0.14, segments: 150)
        if let m = w.geometry?.firstMaterial {
            m.diffuse.contents = FloodTex.water()
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(2600 / 52, 2600 / 52, 1)
            m.metalness.contents = 0.0
            m.normal.intensity = 0.7
            waterMat = m
        }
        w.name = "flood"
        world.addChildNode(w)
        water = w

        let size: CGFloat = 240
        let plane = SCNPlane(width: size, height: size)
        let fm = SK.mat(SK.rgb(0xD8CDB0), roughness: 0.9)
        let img = FloodTex.streaks()
        fm.diffuse.contents = img
        fm.transparent.contents = img
        fm.transparencyMode = .aOne
        for p in [fm.diffuse, fm.transparent] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.contentsTransform = SCNMatrix4MakeScale(size / 46, size / 11, 1)    // long streaks along x (the current)
        }
        fm.writesToDepthBuffer = false
        plane.materials = [fm]
        let fnode = SCNNode(geometry: plane)
        fnode.eulerAngles.x = -.pi / 2
        fnode.position = SCNVector3(0, 0.07, 0)
        fnode.castsShadow = false
        floatRoot.addChildNode(fnode)
        foamMat = fm
    }

    // MARK: House

    private func buildHouse() {
        let brickM = FloodTex.material(FloodTex.brick(), normal: FloodTex.brickNormal(), roughness: 0.92, tile: 1)
        let tileM = FloodTex.material(FloodTex.tile(), roughness: 0.38, tile: 1)
        let concM = FloodTex.material(FloodTex.concrete(), roughness: 0.92, tile: 2)
        concreteMat = concM
        let frameM = SK.mat(SK.rgb(0x4D7C72), roughness: 0.5, metalness: 0.3)
        let glassM = SK.mat(SK.rgb(0x1B2329), roughness: 0.06, metalness: 0)
        glassMat = glassM

        var brick = FloodMesh(), tile = FloodMesh(), conc = FloodMesh(), frame = FloodMesh(), glass = FloodMesh(), misc = FloodMesh()
        let W: Float = 5.1, D: Float = 4.0, top: Float = 6.1, bot: Float = -1.2
        let one = V3(1, 1, 1)
        // walls: exposed red brick on the sides and back, white tiles on the front (门脸)
        tile.wall(.pz, at: D, u0: -W, u1: W, y0: bot, y1: top, one)
        brick.wall(.nz, at: -D, u0: -W, u1: W, y0: bot, y1: top, one)
        brick.wall(.px, at: W, u0: -D, u1: D, y0: bot, y1: top, one)
        brick.wall(.nx, at: -W, u0: -D, u1: D, y0: bot, y1: top, one)
        // floor band (腰线) and the roof slab with its cornice; the slab top is the roof (6.4)
        tile.box(V3(0, 3.28, 0), V3(W + 0.08, 0.15, D + 0.08), one)
        conc.box(V3(0, 6.25, 0), V3(W + 0.16, 0.15, D + 0.16), one)
        // roof railing: kerb, vase balusters, top rail; corner piers
        let R = Float(roofY)
        railing(&conc, V3(-5.08, 0, 4.02), V3(5.08, 0, 4.02), base: R)
        railing(&conc, V3(-5.08, 0, -4.0), V3(-5.08, 0, 4.02), base: R)
        railing(&conc, V3(5.08, 0, -0.62), V3(5.08, 0, 4.02), base: R)
        railing(&conc, V3(-5.08, 0, -4.02), V3(1.75, 0, -4.02), base: R)
        for (x, z) in [(Float(-5.08), Float(4.02)), (5.08, 4.02), (-5.08, -4.02), (0, 4.02), (-5.08, 0)] {
            conc.box(V3(x, R + 0.5, z), V3(0.17, 0.5, 0.17), one)
        }
        // stair head (楼梯间) in the north-east corner
        let sx0: Float = 1.75, sx1: Float = 5.1, sz0: Float = -4.0, sz1: Float = -0.65, sTop: Float = 8.85
        tile.wall(.pz, at: sz1, u0: sx0, u1: sx1, y0: R, y1: sTop, one)
        brick.wall(.nx, at: sx0, u0: sz0, u1: sz1, y0: R, y1: sTop, one)
        brick.wall(.px, at: sx1, u0: sz0, u1: sz1, y0: R, y1: sTop, one)
        brick.wall(.nz, at: sz0, u0: sx0, u1: sx1, y0: R, y1: sTop, one)
        conc.box(V3((sx0 + sx1) / 2, sTop + 0.09, (sz0 + sz1) / 2), V3((sx1 - sx0) / 2 + 0.15, 0.1, (sz1 - sz0) / 2 + 0.15), one)
        // its door: a dark opening, the leaf swung open against the wall
        misc.box(V3(2.75, R + 1.05, sz1 + 0.012), V3(0.46, 1.05, 0.015), floodLin(0x15130F))
        misc.box(V3(2.24, R + 1.05, sz1 + 0.47), V3(0.03, 1.02, 0.45), floodLin(0x7A3B2A))
        window(&frame, &glass, &misc, V3(sx1, 7.9, -2.3), .px, 0.7, 0.6)

        // the balcony on the south front, carried by two columns
        tile.box(V3(0, 3.18, 4.72), V3(2.05, 0.12, 0.72), one)
        railing(&conc, V3(-2.0, 0, 5.34), V3(2.0, 0, 5.34), base: Float(floor2))
        railing(&conc, V3(-1.95, 0, 4.05), V3(-1.95, 0, 5.34), base: Float(floor2))
        railing(&conc, V3(1.95, 0, 4.05), V3(1.95, 0, 5.34), base: Float(floor2))
        for x in [Float(-1.78), 1.78] {
            tile.box(V3(x, (bot + 3.06) / 2, 5.18), V3(0.17, (3.06 - bot) / 2, 0.17), one)
        }

        // windows and doors (steel frames painted green, as everywhere in the 90s)
        for x in [Float(-3.4), 3.4] {
            window(&frame, &glass, &misc, V3(x, 4.95, D), .pz, 1.5, 1.5)
            window(&frame, &glass, &misc, V3(x, 1.65, D), .pz, 1.5, 1.5)
            window(&frame, &glass, &misc, V3(x * 0.76, 5.0, -D), .nz, 1.2, 1.4)
            window(&frame, &glass, &misc, V3(x * 0.76, 1.7, -D), .nz, 1.2, 1.4)
        }
        window(&frame, &glass, &misc, V3(0, 4.45, D), .pz, 1.4, 2.3, door: true)
        for (f, x) in [(FloodFace.px, W), (FloodFace.nx, -W)] {
            window(&frame, &glass, &misc, V3(x, 5.0, -1.0), f, 1.2, 1.4)
            window(&frame, &glass, &misc, V3(x, 1.7, -1.0), f, 1.2, 1.4)
            window(&frame, &glass, &misc, V3(x, 5.2, 2.3), f, 0.6, 0.8)
        }
        // the double front door of the main room (堂屋), red-brown, and its lintel
        misc.box(V3(0, 1.4, D + 0.012), V3(0.95, 1.4, 0.015), floodLin(0x1A1612))
        for x in [Float(-0.42), 0.42] { misc.box(V3(x, 1.38, D + 0.04), V3(0.4, 1.28, 0.03), floodLin(0x6A2A20)) }
        tile.box(V3(0, 2.86, D + 0.06), V3(1.1, 0.1, 0.07), one)
        // PVC downpipes on the front corners
        for x in [Float(-4.98), 4.98] { misc.tube(V3(x, bot, D + 0.1), V3(x, 6.3, D + 0.1), 0.05, 0.05, floodLin(0xBDBCB2)) }

        house.addChildNode(brick.node(brickM))
        house.addChildNode(tile.node(tileM))
        house.addChildNode(conc.node(concM))
        house.addChildNode(frame.node(frameM))
        house.addChildNode(glass.node(glassM))
        house.addChildNode(misc.node(vcMat(0.7)))

        // wet band just above the water, and the mud line left behind when it falls
        func sleeve(_ col: NSColor, _ alpha: CGFloat) -> SCNNode {
            var m = FloodMesh()
            let e: Float = 0.025
            m.wall(.pz, at: D + e, u0: -W - e, u1: W + e, y0: 0, y1: 1, one)
            m.wall(.nz, at: -D - e, u0: -W - e, u1: W + e, y0: 0, y1: 1, one)
            m.wall(.px, at: W + e, u0: -D - e, u1: D + e, y0: 0, y1: 1, one)
            m.wall(.nx, at: -W - e, u0: -D - e, u1: D + e, y0: 0, y1: 1, one)
            let mat = SK.mat(col, roughness: 0.7)
            mat.transparency = alpha
            mat.writesToDepthBuffer = false
            let n = m.node(mat, shadow: false)
            house.addChildNode(n)
            return n
        }
        wetBand = sleeve(SK.rgb(0x221C14), 0.5)
        mudBand = sleeve(SK.rgb(0x5E4A30), 0.72)
        mudLine = sleeve(SK.rgb(0x2E2418), 0.85)

        // the crack in the east wall (from the corner of the upstairs window), and its widening
        let crackM = SK.mat(SK.rgb(0x16120D), roughness: 1, doubleSided: true)
        var ca = FloodMesh()
        crack(&ca, [(-0.38, 4.28), (-0.2, 3.9), (-0.32, 3.55), (-0.05, 3.2), (0.1, 2.8), (-0.05, 2.3)], width: 0.08, x: W + 0.03)
        crack(&ca, [(-0.2, 3.9), (0.25, 3.75), (0.45, 3.45)], width: 0.03, x: W + 0.03)
        var caEdge = FloodMesh()
        crack(&caEdge, [(-0.38, 4.28), (-0.2, 3.9), (-0.32, 3.55), (-0.05, 3.2), (0.1, 2.8), (-0.05, 2.3)], width: 0.16, x: W + 0.02)
        let edgeM = SK.mat(SK.rgb(0xB9A88E), roughness: 1, doubleSided: true)
        let caNode = ca.node(crackM, shadow: false)
        caNode.addChildNode(caEdge.node(edgeM, shadow: false))
        house.addChildNode(caNode)
        crackA = caNode
        var cb = FloodMesh()
        crack(&cb, [(-0.38, 4.28), (-0.15, 3.85), (-0.3, 3.5), (0.0, 3.15), (0.15, 2.75), (0.02, 2.2)], width: 0.13, x: W + 0.035)
        crack(&cb, [(-1.62, 5.72), (-1.9, 6.0)], width: 0.06, x: W + 0.035)
        crack(&cb, [(0.62, 4.3), (0.9, 3.9), (1.25, 3.7), (1.6, 3.2)], width: 0.07, x: W + 0.035)
        // mud seeping out of the crack (泥水往外渗)
        cb.quad(V3(W + 0.04, 2.2, -0.25), V3(W + 0.04, 2.2, 0.25), V3(W + 0.04, 3.6, 0.05), V3(W + 0.04, 3.6, -0.15), floodLin(0x5A4630))
        let cbNode = cb.node(crackM, shadow: false)
        house.addChildNode(cbNode)
        crackB = cbNode

        var rb = FloodMesh()
        var rr = FloodRng(91)
        for _ in 0..<40 {
            let x = rr.r(5.6, 9.5), z = rr.r(-4.5, 4.5)
            rb.box(V3(x, rr.r(-0.05, 0.12), z), V3(rr.r(0.12, 0.5), rr.r(0.05, 0.14), rr.r(0.1, 0.3)), yaw: rr.r(0, 3), pitch: rr.r(-0.4, 0.4), roll: rr.r(-0.4, 0.4),
                   rr.next() < 0.7 ? floodLin(0x9A5238) * rr.r(0.8, 1.1) : floodLin(0xB5B0A4))
        }
        for k in 0..<4 {
            rb.box(V3(6.3 + Float(k) * 0.7, 0.08, -2.5 + Float(k) * 1.6), V3(0.9, 0.08, 0.5), yaw: Float(k) * 0.7, roll: 0.2, floodLin(0xA7A398))
        }
        let rbNode = rb.node(vcMat(0.9))
        floatRoot.addChildNode(rbNode)
        rubble = rbNode
    }

    /// A roof/balcony railing from `a` to `b`: kerb, cast-concrete vase balusters, top rail.
    private func railing(_ m: inout FloodMesh, _ a: V3, _ b: V3, base: Float) {
        let d = b - a
        let len = sqrt(d.x * d.x + d.z * d.z)
        let yaw = atan2(-d.z, d.x)
        let mid = (a + b) * 0.5
        let one = V3(1, 1, 1)
        m.box(V3(mid.x, base + 0.13, mid.z), V3(len / 2, 0.13, 0.1), yaw: yaw, one)
        m.box(V3(mid.x, base + 0.93, mid.z), V3(len / 2 + 0.04, 0.05, 0.11), yaw: yaw, one)
        let n = max(1, Int(len / 0.25))
        for i in 0..<n {
            let t = (Float(i) + 0.5) / Float(n)
            let p = a + d * t
            m.lathe(V3(p.x, base + 0.26, p.z), [(0, 0.045), (0.06, 0.05), (0.2, 0.072), (0.38, 0.032), (0.5, 0.04), (0.62, 0.05)], segs: 6, one)
        }
    }

    /// A steel window (or glass door) on a wall facing `f`, centred at `c`.
    private func window(_ fr: inout FloodMesh, _ gl: inout FloodMesh, _ dk: inout FloodMesh, _ c: V3, _ f: FloodFace, _ w: Float, _ h: Float, door: Bool = false) {
        let n = f.normal
        let r = V3(n.z, 0, -n.x)
        let yaw: Float = abs(n.x) > 0.5 ? .pi / 2 : 0
        func at(_ u: Float, _ v: Float, _ d: Float) -> V3 { c + r * u + V3(0, v, 0) + n * d }
        let one = V3(1, 1, 1)
        dk.box(at(0, 0, 0.012), V3(w / 2 + 0.07, h / 2 + 0.07, 0.016), yaw: yaw, floodLin(0x1C1B19))
        gl.box(at(0, 0, 0.03), V3(w / 2, h / 2, 0.006), yaw: yaw, one)
        let t: Float = 0.04
        fr.box(at(0, h / 2 - t, 0.05), V3(w / 2, t, 0.022), yaw: yaw, one)
        fr.box(at(0, -h / 2 + t, 0.05), V3(w / 2, t, 0.022), yaw: yaw, one)
        fr.box(at(-w / 2 + t, 0, 0.05), V3(t, h / 2, 0.022), yaw: yaw, one)
        fr.box(at(w / 2 - t, 0, 0.05), V3(t, h / 2, 0.022), yaw: yaw, one)
        fr.box(at(0, 0, 0.05), V3(t * 0.7, h / 2, 0.02), yaw: yaw, one)
        fr.box(at(0, door ? -h * 0.15 : h * 0.22, 0.05), V3(w / 2, t * 0.7, 0.02), yaw: yaw, one)
        if !door {
            dk.box(at(0, -h / 2 - 0.06, 0.06), V3(w / 2 + 0.1, 0.05, 0.08), yaw: yaw, floodLin(0xCFCABC))
        }
    }

    /// A crack drawn as a strip on the east wall plane; points are (z, y).
    private func crack(_ m: inout FloodMesh, _ p: [(Float, Float)], width: Float, x: Float) {
        guard p.count > 1 else { return }
        let col = floodLin(0x16120D)
        for i in 0..<(p.count - 1) {
            let (z0, y0) = p[i], (z1, y1) = p[i + 1]
            let dz = z1 - z0, dy = y1 - y0
            let l = max(0.001, sqrt(dz * dz + dy * dy))
            let w0 = width * (1 - 0.35 * Float(i) / Float(p.count)), w1 = width * (1 - 0.35 * Float(i + 1) / Float(p.count))
            let pz = -dy / l, py = dz / l
            m.quad(V3(x, y0 + py * w0 / 2, z0 + pz * w0 / 2), V3(x, y0 - py * w0 / 2, z0 - pz * w0 / 2),
                   V3(x, y1 - py * w1 / 2, z1 - pz * w1 / 2), V3(x, y1 + py * w1 / 2, z1 + pz * w1 / 2), col)
        }
    }

    // MARK: Roof life

    private func buildRoof() {
        let R = Float(roofY)
        var m = FloodMesh()
        let iron = floodLin(0x2C2926), bamboo = floodLin(0xB7A56C)
        // the brazier basin under the fire
        m.lathe(V3(Float(brazier.x), R, Float(brazier.z)), [(0, 0.3), (0.06, 0.4), (0.22, 0.47), (0.24, 0.45)], segs: 10, iron)
        m.patch(V3(Float(brazier.x), R + 0.17, Float(brazier.z)), 0.4, floodLin(0x3A332C), noise, seed: 2, rough: 0.05)
        // firewood stacked against the stair head, rice sacks, the big wooden tub, thermos flasks, kettle
        var rng = FloodRng(11)
        for i in 0..<16 {
            let y = R + 0.06 + Float(i / 4) * 0.12
            let z = -0.45 + Float(i % 4) * 0.1
            m.tube(V3(3.45 + rng.r(-0.1, 0.1), y, z), V3(4.85 + rng.r(-0.1, 0.1), y + rng.r(-0.03, 0.03), z + rng.r(-0.05, 0.05)), 0.05, 0.045, floodLin(0x5E4A36) * rng.r(0.8, 1.15), segs: 5)
        }
        for i in 0..<2 {
            m.blob(V3(-1.2 + Float(i) * 0.75, R + 0.26, -3.55), V3(0.36, 0.26, 0.24), floodLin(0xD9D5C8), noise, seed: Float(i) * 3, jitter: 0.08, rings: 5, segs: 8, under: 0.7, vary: 0.1)
        }
        m.lathe(V3(-2.3, R, -3.35), [(0, 0.48), (0.3, 0.56), (0.3, 0.5), (0.06, 0.44)], segs: 12, floodLin(0x8A6A45))
        for (i, c) in [UInt32(0xB3302B), 0x3E7A4A].enumerated() {
            m.tube(V3(-4.55 + Float(i) * 0.2, R, -1.35), V3(-4.55 + Float(i) * 0.2, R + 0.38, -1.35), 0.075, 0.075, floodLin(c), segs: 8, cap: true)
            m.tube(V3(-4.55 + Float(i) * 0.2, R + 0.38, -1.35), V3(-4.55 + Float(i) * 0.2, R + 0.44, -1.35), 0.035, 0.03, floodLin(0xC9B48A), segs: 6, cap: true)
        }
        m.blob(V3(Float(brazier.x) + 0.55, R + 0.12, Float(brazier.z) + 0.45), V3(0.16, 0.12, 0.16), floodLin(0xB8B8B2), noise, seed: 5, jitter: 0.02, rings: 4, segs: 8, under: 0.8, vary: 0)
        // enamel washbasin used as a gong, the long bamboo pole for pushing off debris
        m.lathe(V3(-0.6, R + 0.0, 3.45), [(0, 0.12), (0.08, 0.2), (0.09, 0.21)], segs: 10, floodLin(0xE8E6DE))
        m.tube(V3(-4.7, R, 3.1), V3(-3.6, R + 4.4, 3.95), 0.04, 0.03, bamboo, segs: 5)
        // the clothes-drying pole (晾衣竿) in the front-right corner — the red quilt flies from it —
        // and the short pole by the stair head; the line between them
        m.tube(V3(4.92, R, 3.88), V3(4.95, R + 4.7, 3.92), 0.045, 0.035, bamboo, segs: 6)
        m.tube(V3(4.9, R, -0.45), V3(4.9, R + 2.25, -0.45), 0.04, 0.035, bamboo, segs: 6)
        m.tube(V3(4.9, R + 2.15, -0.45), V3(4.93, R + 2.15, 3.9), 0.01, 0.01, floodLin(0x8A8A86), segs: 3)
        // TV antenna on the stair head: a bamboo mast and a fishbone aerial
        let mast = V3(4.6, Float(8.95), -3.6)
        m.tube(mast, mast + V3(0, 3.6, 0), 0.04, 0.03, bamboo, segs: 5)
        let alu = floodLin(0xA9AAA6)
        m.tube(mast + V3(0, 3.5, -0.8), mast + V3(0, 3.5, 0.8), 0.015, 0.015, alu, segs: 3)
        for k in 0..<8 {
            let z = -0.75 + Float(k) * 0.2, half = 0.34 - Float(k) * 0.025
            m.tube(mast + V3(-half, 3.5, z), mast + V3(half, 3.5, z), 0.008, 0.008, alu, segs: 3)
        }
        let props = m.node(vcMat(0.8))
        house.addChildNode(props)

        // laundry on the line (taken in when it rains)
        var l = FloodMesh()
        let clothes: [(Float, Float, Float, UInt32)] = [(0.3, 0.5, 0.65, 0xE4E2D8), (0.95, 0.36, 0.95, 0x2E3E66), (1.5, 0.28, 0.55, 0xB8352B),
                                                       (2.0, 0.46, 0.6, 0x86A9CC), (2.55, 0.3, 0.42, 0xD98FA0), (3.05, 0.34, 0.9, 0x55603F), (3.5, 0.24, 0.5, 0xE8E0B8)]
        for (z, hw, h, c) in clothes {
            l.box(V3(4.92, R + 2.15 - h / 2, z), V3(0.012, h / 2, hw), floodLin(c))
        }
        let ln = l.node(vcMat(0.95, doubleSided: true))
        house.addChildNode(ln)
        laundry = ln

        // grandma's bamboo bed (竹床): built along x; moved between the balcony and the roof
        var b = FloodMesh()
        b.box(V3(0, 0.42, 0), V3(0.95, 0.025, 0.45), floodLin(0xCDB57C))
        for i in 0..<9 { b.box(V3(-0.88 + Float(i) * 0.22, 0.448, 0), V3(0.07, 0.006, 0.44), floodLin(0xBFA66C)) }
        for (x, z) in [(Float(-0.88), Float(-0.4)), (0.88, -0.4), (-0.88, 0.4), (0.88, 0.4)] {
            b.box(V3(x, 0.2, z), V3(0.03, 0.2, 0.03), floodLin(0xA88F58))
        }
        b.box(V3(-0.75, 0.5, 0), V3(0.14, 0.05, 0.22), floodLin(0xE6E2D6))
        b.box(V3(0.62, 0.48, 0), V3(0.28, 0.035, 0.43), floodLin(0xC2667A))
        let bedNode = b.node(vcMat(0.8))
        world.addChildNode(bedNode)
        bed = bedNode

        // things that come and go with flags and resources
        var bs = FloodMesh()
        let containers: [(Float, Float, Float, Float, UInt32)] = [
            (-4.5, 3.4, 0.3, 0.12, 0xC0392B), (-3.7, 3.55, 0.22, 0.28, 0x2E6DB4), (-2.6, 3.5, 0.34, 0.1, 0xE8E6DE),
            (-4.55, 2.4, 0.3, 0.55, 0x5A3A22), (-4.6, 1.3, 0.24, 0.12, 0x3C8F4F), (1.0, 3.5, 0.26, 0.3, 0xD9A63A),
            (2.9, 3.55, 0.32, 0.12, 0x2E6DB4), (3.9, 3.4, 0.18, 0.26, 0xB8B8B2)]
        for (x, z, r, h, c) in containers {
            bs.lathe(V3(x, R, z), [(0, r * 0.75), (h, r), (h, r * 0.9)], segs: 10, floodLin(c))
            bs.patch(V3(x, R + h * 0.7, z), r * 0.85, floodLin(0x6B7F86), noise, seed: x, rough: 0.02)
        }
        let bn = bs.node(vcMat(0.4))
        house.addChildNode(bn)
        basins = bn

        var wk = FloodMesh()
        wk.lathe(V3(Float(brazier.x) - 0.95, R + 0.02, Float(brazier.z) + 0.55), [(0, 0.06), (0.06, 0.3), (0.16, 0.46), (0.17, 0.48)], segs: 12, floodLin(0x24221F))
        let wkn = wk.node(SK.mat(.white, roughness: 0.45, metalness: 0.5, doubleSided: true))
        house.addChildNode(wkn)
        wok = wkn

        var lt = FloodMesh()
        lt.lathe(V3(-4.55, R, -3.45), [(0, 0.17), (0.38, 0.2), (0.4, 0.19)], segs: 10, floodLin(0xB33A2E))
        lt.box(V3(-4.55, R + 0.42, -3.45), V3(0.24, 0.015, 0.22), floodLin(0x8C6E48))
        lt.box(V3(-4.0, R + 0.55, -3.1), V3(0.03, 0.55, 0.62), floodLin(0xB49A62), top: nil)
        let ltn = lt.node(vcMat(0.9))
        house.addChildNode(ltn)
        latrine = ltn

        let film = SK.mat(SK.rgb(0xE6EEF0), roughness: 0.18, doubleSided: true)
        film.transparency = 0.55
        var fs = FloodMesh()
        fs.sheet(nu: 8, nv: 6, V3(1, 1, 1)) { u, v in
            let sag = sin(u * .pi) * sin(v * .pi) * 0.32
            return V3(-4.7 + 2.4 * u, R + 0.65 - sag, 1.4 + 1.9 * v)
        }
        let fsn = fs.node(film, shadow: false)
        house.addChildNode(fsn)
        filmSpread = fsn
        var fr = FloodMesh()
        fr.tube(V3(0.2, R + 0.13, -3.55), V3(1.3, R + 0.13, -3.55), 0.13, 0.13, V3(1, 1, 1), segs: 10, cap: true)
        let frn = fr.node(film)
        house.addChildNode(frn)
        filmRoll = frn

        var ws = FloodMesh()
        var wr = FloodRng(21)
        for _ in 0..<46 {
            let x = wr.r(1.2, 4.4), z = wr.r(1.3, 3.5), a = wr.r(0, .pi), l = wr.r(0.5, 1.2)
            let d = V3(cos(a), 0, sin(a)) * (l / 2)
            ws.tube(V3(x, R + 0.04, z) - d, V3(x, R + 0.04, z) + d, wr.r(0.02, 0.04), 0.02, floodLin(0x5C4A36) * wr.r(0.75, 1.2), segs: 4)
        }
        let wsn = ws.node(vcMat(0.95))
        house.addChildNode(wsn)
        woodSpread = wsn

        for i in 0..<4 {
            var f = FloodMesh()
            let x = Float(brazier.x) - 1.1 - Float(i % 2) * 0.5, z = Float(brazier.z) - 0.9 - Float(i / 2) * 0.35
            for k in 0..<7 {
                let y = R + 0.06 + Float(k / 3) * 0.1, dz = Float(k % 3) * 0.09 - 0.09
                f.tube(V3(x - 0.3, y, z + dz), V3(x + 0.3, y, z + dz), 0.045, 0.04, floodLin(0x8A6A48) * (0.85 + 0.05 * Float(k)), segs: 5)
            }
            f.tube(V3(x, R + 0.02, z - 0.16), V3(x, R + 0.02, z + 0.16), 0.13, 0.13, floodLin(0xC2A35A), segs: 6)
            let fnode = f.node(vcMat(0.9))
            house.addChildNode(fnode)
            fuelStack.append(fnode)
        }

        // the family pig, hauled up onto the roof (flag pig_roof), tied to the railing
        let pig = SK.animal(weight: 75, color: SK.rgb(0xE2BBA8), lying: false, seed: 0)
        pig.position = SCNVector3(0.75, roofY, -3.3)
        pig.eulerAngles.y = .pi / 2
        house.addChildNode(pig)
        roofPig = pig
    }

    // MARK: Signals

    private func buildSignals() {
        let R = Float(roofY)
        // the red satin quilt cover (红被面) flying from the clothes pole
        let qm = SK.mat(.white, roughness: 0.55, doubleSided: true)
        qm.diffuse.contents = FloodTex.quilt()
        var q = FloodMesh()
        q.sheet(nu: 10, nv: 6, V3(1, 1, 1)) { u, v in
            let wave = sin(u * 5.5 + v * 1.2) * 0.13 * u
            return V3(4.95 - 1.75 * u, R + 4.6 - 1.35 * v - 0.12 * u * u, 3.92 + wave)
        }
        let qn = q.node(qm)
        house.addChildNode(qn)
        quiltFlag = qn

        // SOS painted with slaked lime on the roof, readable from the south (from the boats)
        let paint = SK.mat(SK.rgb(0xEAE7DD), roughness: 0.95)
        sosMat = paint
        var p = FloodMesh()
        let w: Float = 0.92, h: Float = 1.3, t: Float = 0.2
        func bar(_ cx: Float, _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float) {
            // letter-local box from (u0, v0) to (u1, v1); u along +x, v "up" = −z
            let x0 = cx + u0, x1 = cx + u1, z0 = 2.62 - v0, z1 = 2.62 - v1
            p.box(V3((x0 + x1) / 2, R + 0.006, (z0 + z1) / 2), V3(abs(x1 - x0) / 2, 0.006, abs(z1 - z0) / 2), V3(1, 1, 1))
        }
        for (i, ch) in ["S", "O", "S"].enumerated() {
            let cx = -1.5 + Float(i) * 1.18
            if ch == "O" {
                bar(cx, 0, 0, w, t); bar(cx, 0, h - t, w, h); bar(cx, 0, 0, t, h); bar(cx, w - t, 0, w, h)
            } else {
                bar(cx, 0, 0, w, t); bar(cx, 0, (h - t) / 2, w, (h + t) / 2); bar(cx, 0, h - t, w, h)
                bar(cx, 0, (h - t) / 2, t, h); bar(cx, w - t, 0, w, (h + t) / 2)
            }
        }
        let sn = p.node(paint, shadow: false)
        house.addChildNode(sn)
        sos = sn

        // a white bedsheet with 救命 hung over the front railing
        let sheet = SCNNode()
        let cloth = SK.mat(SK.rgb(0xE9E7E0), roughness: 0.9, doubleSided: true)
        var c = FloodMesh()
        c.sheet(nu: 6, nv: 4, V3(1, 1, 1)) { u, v in
            V3(-4.55 + 2.3 * u, R + 1.0 - 1.35 * v, 4.17 + 0.04 * sin(u * 9) + 0.06 * v)
        }
        c.box(V3(-3.4, R + 1.0, 4.08), V3(1.17, 0.012, 0.1), V3(1, 1, 1))
        sheet.addChildNode(c.node(cloth))
        let text = SCNText(string: "救命", extrusionDepth: 0)
        text.font = NSFont(name: "PingFangSC-Semibold", size: 10) ?? NSFont.boldSystemFont(ofSize: 10)
        text.flatness = 0.25
        text.firstMaterial = SK.mat(SK.rgb(0xB0181B), roughness: 0.9, doubleSided: true)
        let tn = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        let k: CGFloat = 0.083
        tn.scale = SCNVector3(k, k, k)
        tn.position = SCNVector3(-3.4 - (mn.x + mx.x) / 2 * k, roofY + 0.32 - (mn.y + mx.y) / 2 * k, 4.29)
        sheet.addChildNode(tn)
        house.addChildNode(sheet)
        helpSheet = sheet

        // a strip of red cloth tied to the TV antenna
        var rag = FloodMesh()
        rag.sheet(nu: 5, nv: 2, V3(1, 1, 1)) { u, v in
            V3(4.6 - 0.95 * u, 12.5 - 0.35 * v - 0.25 * u, -3.6 + 0.12 * sin(u * 6))
        }
        let rn = rag.node(SK.mat(SK.rgb(0xC0221E), roughness: 0.9, doubleSided: true))
        house.addChildNode(rn)
        antennaRag = rn
    }

    // MARK: Projects

    private func buildProjects() {
        let R = Float(roofY)
        let bamboo = floodLin(0xB7A56C)
        // the awning (凉棚): bamboo poles, then a red-white-blue striped tarp (彩条布), a bit askew
        var poles = FloodMesh()
        let corners: [(Float, Float, Float)] = [(-4.95, -3.85, 2.45), (-2.95, -3.85, 2.35), (-1.0, -3.85, 2.4), (-4.95, 1.25, 2.05), (-2.95, 1.25, 2.12), (-1.0, 1.25, 2.0)]
        for (x, z, h) in corners { poles.tube(V3(x, R, z), V3(x + 0.04, R + h, z + 0.03), 0.04, 0.032, bamboo, segs: 5) }
        poles.tube(V3(-4.95, R + 2.42, -3.85), V3(-1.0, R + 2.38, -3.85), 0.03, 0.03, bamboo, segs: 4)
        poles.tube(V3(-4.95, R + 2.03, 1.25), V3(-1.0, R + 1.98, 1.25), 0.03, 0.03, bamboo, segs: 4)
        let pn = poles.node(vcMat(0.8))
        house.addChildNode(pn)
        awningPoles = pn
        let tarp = SK.mat(.white, roughness: 0.6, doubleSided: true)
        tarp.diffuse.contents = FloodTex.stripes()
        tarp.diffuse.wrapS = .repeat
        tarp.diffuse.wrapT = .repeat
        var sh = FloodMesh()
        sh.sheet(nu: 10, nv: 10, V3(1, 1, 1), uvScale: (7, 1)) { u, v in
            let x = -5.05 + 4.15 * u, z = -3.95 + 5.3 * v
            let y = R + 2.45 - 0.42 * v - 0.06 * u - 0.22 * sin(u * .pi) * sin(v * .pi) + 0.06 * u * v
            return V3(x, y, z)
        }
        let sn = sh.node(tarp)
        house.addChildNode(sn)
        awningSheet = sn

        // the raft taking shape on the roof: a door off its hinges, plastic drums, nylon rope
        let door = floodLin(0x6E2C20), drum = floodLin(0x2A5CA0), rope = floodLin(0xD9A63A)
        var rw = FloodMesh()
        rw.box(V3(3.25, R + 0.05, 0.8), V3(1.0, 0.03, 0.46), yaw: 0.05, door)
        rw.tube(V3(2.4, R + 0.28, -0.05), V3(3.3, R + 0.28, -0.12), 0.28, 0.28, drum, segs: 10, cap: true)
        rw.lathe(V3(1.75, R, 1.6), [(0, 0.12), (0.12, 0.2), (0.2, 0.22)], segs: 10, rope)
        let rwn = rw.node(vcMat(0.6))
        house.addChildNode(rwn)
        raftWork = rwn
        var rl = FloodMesh()
        rl.tube(V3(3.0, R + 0.28, 1.75), V3(3.9, R + 0.28, 1.68), 0.28, 0.28, floodLin(0xE6E4DC), segs: 10, cap: true)
        rl.tube(V3(4.25, R + 0.28, 0.15), V3(4.25, R + 0.28, 1.05), 0.28, 0.28, drum, segs: 10, cap: true)
        for z in [Float(0.5), 1.1] { rl.box(V3(3.25, R + 0.085, z), V3(1.02, 0.012, 0.025), yaw: 0.05, rope) }
        let rln = rl.node(vcMat(0.6))
        house.addChildNode(rln)
        raftWorkLate = rln

        // the finished raft, floating under the balcony
        let rf = SCNNode()
        var r = FloodMesh()
        for (x, z) in [(Float(-0.62), Float(-0.3)), (0.62, -0.3), (-0.62, 0.3), (0.62, 0.3)] {
            r.tube(V3(x - 0.42, 0.02, z), V3(x + 0.42, 0.02, z), 0.27, 0.27, z < 0 ? drum : floodLin(0xE6E4DC), segs: 10, cap: true)
        }
        r.box(V3(0, 0.33, 0), V3(1.02, 0.03, 0.47), door)
        r.box(V3(0, 0.37, 0), V3(0.05, 0.01, 0.47), floodLin(0x3A1A12))
        for x in [Float(-0.7), 0, 0.7] { r.box(V3(x, 0.34, 0), V3(0.025, 0.035, 0.5), rope) }
        r.box(V3(0.85, 0.32, 0.55), V3(0.3, 0.09, 0.14), floodLin(0xE9E7DF))
        rf.addChildNode(r.node(vcMat(0.55)))
        // the coffin (寿材), three coats of tung oil, lashed alongside when it was used
        var cf = FloodMesh()
        cf.box(V3(0, 0.45, -0.98), V3(1.05, 0.25, 0.33), floodLin(0x2B1A12))
        cf.box(V3(0.12, 0.74, -0.98), V3(1.15, 0.05, 0.38), floodLin(0x24150E))
        cf.box(V3(1.08, 0.5, -0.98), V3(0.06, 0.32, 0.4), floodLin(0x2B1A12))
        let cfn = cf.node(SK.mat(.white, roughness: 0.22))
        rf.addChildNode(cfn)
        raftCoffin = cfn
        rf.position = SCNVector3(-0.7, 0, 6.85)
        rf.eulerAngles.y = 0.06
        floatRoot.addChildNode(rf)
        raft = rf
        // its mooring line up to the balcony column (re-laid in apply as the water moves)
        let line = SCNNode(geometry: SCNCylinder(radius: 0.015, height: 1))
        line.geometry?.firstMaterial = SK.mat(SK.rgb(0xD9A63A), roughness: 0.9)
        world.addChildNode(line)
        raftRope = line
    }

    // MARK: Village, trees, poles

    private func buildVillage() {
        var walls = FloodMesh(), roofs = FloodMesh(), crowns = FloodMesh(), wood = FloodMesh()
        // the great camphor tree by the front door (门口那棵大樟树)
        tree(&crowns, &wood, kind: 0, x: -10.5, z: 9.5, base: 0, s: 1.0, seed: 3)
        // trees about the homestead
        tree(&crowns, &wood, kind: 4, x: -11, z: -9, base: 0, s: 0.9, seed: 5)
        tree(&crowns, &wood, kind: 1, x: -17, z: -15, base: -0.4, s: 0.95, seed: 7)
        tree(&crowns, &wood, kind: 1, x: -21, z: -9, base: -0.6, s: 0.85, seed: 8)
        tree(&crowns, &wood, kind: 3, x: 26, z: 10, base: -0.6, s: 0.9, seed: 9)
        tree(&crowns, &wood, kind: 5, x: -16, z: 0, base: -0.3, s: 1.0, seed: 10)
        tree(&crowns, &wood, kind: 0, x: 22, z: -40, base: -0.6, s: 0.7, seed: 11)
        tree(&crowns, &wood, kind: 3, x: 31, z: -6, base: -0.8, s: 0.8, seed: 13)

        // the family's own kitchen shed behind the house: only the ridge shows
        villageHouse(&walls, &roofs, -9.5, -10.5, yaw: 0.04, kind: 3, seed: 4)
        // 周家 next door: a single-storey house, the water nearly over its eaves
        villageHouse(&walls, &roofs, 14, -30, yaw: 0.12, kind: 0, seed: 12)
        let houses: [(Float, Float, Float, Int)] = [
            (-30, -26, 0.2, 0), (-47, -41, 0.15, 2), (-66, -47, 0.22, 0), (-88, -60, 0.25, 1), (-111, -66, 0.2, 0), (-136, -79, 0.3, 0),
            (40, -53, -0.1, 0), (58, -68, -0.15, 1), (81, -59, -0.1, 0), (104, -82, 0.0, 2), (131, -75, -0.2, 0),
            (62, -12, 0.5, 3), (76, 16, 0.4, 0), (99, 40, 0.3, 2), (-24, 52, 0.1, 0), (8, 72, 0.0, 1), (40, 58, -0.1, 0),
            (-56, 72, 0.2, 2), (-60, 8, 1.45, 0), (-80, 31, 1.5, 0), (-150, 10, 1.3, 1), (150, -20, 1.6, 0), (-40, -95, 0.1, 0),
            (-6, -92, 0.08, 1), (10, -66, 0.15, 0), (24, -88, 0.1, 0), (-22, -62, 0.25, 3)]
        for (i, h) in houses.enumerated() {
            villageHouse(&walls, &roofs, h.0, h.1, yaw: h.2, kind: h.3, seed: UInt64(20 + i))
        }
        tree(&crowns, &wood, kind: 3, x: 2, z: -77, base: -0.8, s: 0.85, seed: 41)
        tree(&crowns, &wood, kind: 3, x: 17, z: -101, base: -0.8, s: 0.9, seed: 42)
        tree(&crowns, &wood, kind: 5, x: -14, z: -84, base: -0.8, s: 1.1, seed: 43)
        // another family waiting on the roof of their two-storey house
        for (i, c) in [SK.rgb(0x8DA4C0), SK.rgb(0xB8402F), SK.rgb(0xD8D6CE)].enumerated() {
            let f = SK.person(color: c, pose: i == 1 ? .waving : .standing, child: i == 2, seed: 0)
            f.position = SCNVector3(-7.5 + CGFloat(i) * 1.1, 6.3, -89.5)
            f.eulerAngles.y = 0.3
            world.addChildNode(f)
        }
        // trees in and around the village, and rows of dawn redwoods (水杉) along the canals
        var rng = FloodRng(31)
        for (i, h) in houses.enumerated() where i % 2 == 0 || i < 6 {
            for k in 0..<3 {
                let a = rng.r(0, 2 * .pi), d = rng.r(8, 14)
                tree(&crowns, &wood, kind: [1, 3, 4, 5, 0][(i + k) % 5], x: h.0 + cos(a) * d, z: h.1 + sin(a) * d, base: -0.6, s: rng.r(0.7, 1.0), seed: Float(i * 7 + k))
            }
        }
        for i in 0..<26 {
            let z = 120 - Float(i) * 13
            if i % 7 == 3 { continue }
            tree(&crowns, &wood, kind: 2, x: 168 + rng.r(-1, 1) + Float(i) * 0.6, z: z, base: -0.8, s: rng.r(0.85, 1.05), seed: Float(100 + i))
        }
        for i in 0..<22 {
            let x = -40 - Float(i) * 11
            if i % 6 == 2 { continue }
            tree(&crowns, &wood, kind: 1, x: x, z: 40 + Float(i) * 1.5 + rng.r(-1, 1), base: -0.8, s: rng.r(0.85, 1.05), seed: Float(200 + i))
        }
        world.addChildNode(walls.node(vcMat(0.9)))
        world.addChildNode(roofs.node(roofMat()))
        let cm = vcMat(0.95)
        cm.normal.contents = SK.normalNoiseImage(size: 256, scale: 8, strength: 3, seed: 99)   // shared with the water: free
        cm.normal.wrapS = .repeat
        cm.normal.wrapT = .repeat
        cm.normal.intensity = 0.8
        world.addChildNode(crowns.node(cm))
        world.addChildNode(wood.node(vcMat(0.95)))

        // 周家爷孙 on their ridge, and the TV antenna on it
        let ridgeY: CGFloat = 3.2 + 1.75
        let zx: CGFloat = 14, zz: CGFloat = -30
        let gp = SK.person(color: SK.rgb(0x5D6874), pose: .standing, seed: 0)
        gp.position = SCNVector3(zx - 0.7, ridgeY, zz + 0.1)
        gp.eulerAngles.y = 0.5
        world.addChildNode(gp)
        zhouGrandpa = gp
        let gs = SK.person(color: SK.rgb(0x5D6874), pose: .sitting, seed: 0)
        gs.position = SCNVector3(zx - 0.7, ridgeY - 0.05, zz + 0.1)
        gs.eulerAngles.y = 0.5
        world.addChildNode(gs)
        zhouGrandpaSit = gs
        let kid = SK.person(color: SK.rgb(0xB8402F), pose: .waving, child: true, seed: 0)
        kid.position = SCNVector3(zx + 0.2, ridgeY, zz + 0.05)
        kid.eulerAngles.y = 0.6
        world.addChildNode(kid)
        zhouKid = kid
        var ant = FloodMesh()
        let base = V3(Float(zx) + 3.6, Float(ridgeY), Float(zz) + 0.4)
        ant.tube(base, base + V3(0, 2.6, 0), 0.035, 0.03, floodLin(0xB7A56C), segs: 5)
        ant.tube(base + V3(0, 2.5, -0.6), base + V3(0, 2.5, 0.6), 0.012, 0.012, floodLin(0xA9AAA6), segs: 3)
        for k in 0..<6 {
            let z = -0.5 + Float(k) * 0.2
            ant.tube(base + V3(-0.28, 2.5, z), base + V3(0.28, 2.5, z), 0.008, 0.008, floodLin(0xA9AAA6), segs: 3)
        }
        world.addChildNode(ant.node(vcMat(0.6)))
        let hat = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.3, height: 0.15))
        hat.geometry?.firstMaterial = SK.mat(SK.rgb(0xC9A961), roughness: 0.95)
        hat.position = SCNVector3(CGFloat(base.x) + 0.15, CGFloat(base.y) + 2.25, CGFloat(base.z))
        hat.eulerAngles.z = 0.5
        world.addChildNode(hat)
        strawHat = hat
    }

    /// A neighbour's house: walls up to the eaves (the flood hides the rest) and the roof.
    private func villageHouse(_ m: inout FloodMesh, _ roof: inout FloodMesh, _ x: Float, _ z: Float, yaw: Float, kind: Int, seed: UInt64) {
        var r = FloodRng(seed)
        let wallCols: [UInt32] = [0xD7D2C4, 0xCDC6B4, 0x9C5C42, 0xB8A88C, 0xDCD8CE, 0xA8664A]
        let roofCols: [UInt32] = [0x6A6E72, 0x7A7D7E, 0x9A5440, 0x5E6266, 0x86604C]
        let wc = floodLin(r.pick(wallCols)) * r.r(0.9, 1.05), rc = floodLin(r.pick(roofCols)) * r.r(0.85, 1.1)
        let dark = floodLin(0x1E1D1B)
        let base: Float = -0.8
        func at(_ dx: Float, _ dy: Float, _ dz: Float) -> V3 { V3(x, 0, z) + floodRot(V3(dx, dy, dz), yaw: yaw) }
        switch kind {
        case 0:   // single storey, pitched tile roof
            let L = r.r(4.3, 5.4), W = r.r(3.0, 3.6), eave: Float = 3.2
            let rise = r.r(1.55, 1.85)
            m.box(at(0, (base + eave) / 2, 0), V3(L, (eave - base) / 2, W), yaw: yaw, wc)
            roof.roofSlopes(at(0, eave, 0), halfL: L, halfW: W, rise: rise, over: 0.35, yaw: yaw, rc, ridge: rc * 0.75)
            m.roofEnds(at(0, eave, 0), halfL: L, halfW: W, rise: rise, over: 0.35, yaw: yaw, wc, fascia: rc * 0.5)
        case 1:   // two storeys, flat roof and parapet
            let L = r.r(4.2, 5.0), W = r.r(3.6, 4.2), top: Float = 6.3
            m.box(at(0, (base + top) / 2, 0), V3(L, (top - base) / 2, W), yaw: yaw, wc)
            m.box(at(0, top + 0.35, W - 0.08), V3(L, 0.35, 0.08), yaw: yaw, wc * 0.92)
            m.box(at(0, top + 0.35, -W + 0.08), V3(L, 0.35, 0.08), yaw: yaw, wc * 0.92)
            m.box(at(L - 0.08, top + 0.35, 0), V3(0.08, 0.35, W), yaw: yaw, wc * 0.92)
            m.box(at(-L + 0.08, top + 0.35, 0), V3(0.08, 0.35, W), yaw: yaw, wc * 0.92)
            for k in [Float(-0.5), 0.5] {
                m.box(at(k * L, 4.9, W + 0.02), V3(0.7, 0.7, 0.03), yaw: yaw, dark)
                m.box(at(k * L, 4.9, -W - 0.02), V3(0.6, 0.6, 0.03), yaw: yaw, dark)
            }
        case 2:   // two storeys with a pitched roof
            let L = r.r(4.2, 5.0), W = r.r(3.4, 3.9), eave: Float = 6.2
            let rise = r.r(1.7, 2.1)
            m.box(at(0, (base + eave) / 2, 0), V3(L, (eave - base) / 2, W), yaw: yaw, wc)
            roof.roofSlopes(at(0, eave, 0), halfL: L, halfW: W, rise: rise, over: 0.4, yaw: yaw, rc, ridge: rc * 0.75)
            m.roofEnds(at(0, eave, 0), halfL: L, halfW: W, rise: rise, over: 0.4, yaw: yaw, wc, fascia: rc * 0.5)
            for k in [Float(-0.55), 0, 0.55] { m.box(at(k * L, 4.8, W + 0.02), V3(0.55, 0.65, 0.03), yaw: yaw, dark) }
        default:  // a shed (灶屋 / 猪圈)
            let L = r.r(2.2, 3.0), W = r.r(1.6, 2.0), eave: Float = 2.3
            m.box(at(0, (base + eave) / 2, 0), V3(L, (eave - base) / 2, W), yaw: yaw, wc)
            roof.roofSlopes(at(0, eave, 0), halfL: L, halfW: W, rise: 1.1, over: 0.25, yaw: yaw, rc, ridge: rc * 0.75)
            m.roofEnds(at(0, eave, 0), halfL: L, halfW: W, rise: 1.1, over: 0.25, yaw: yaw, wc, fascia: rc * 0.5)
        }
    }

    /// Trees as merged meshes: crowns (vertex-coloured blobs) and wood (trunks, branches).
    private func tree(_ crown: inout FloodMesh, _ wood: inout FloodMesh, kind: Int, x: Float, z: Float, base: Float, s: Float, seed: Float, lowRes: Bool = false) {
        let rings = lowRes ? 4 : 8, segs = lowRes ? 7 : 12
        let bark = floodLin(0x4A4035)
        let b = V3(x, base, z)
        switch kind {
        case 0:   // camphor: thick trunk, huge dense rounded crown
            wood.tube(b, b + V3(0.25, 4.4, 0) * s, 0.55 * s, 0.36 * s, bark, segs: 8)
            for k in 0..<4 {
                let a = Float(k) * 1.7 + seed
                wood.tube(b + V3(0.25, 4.0, 0) * s, b + V3(cos(a) * 3.0, 6.6, sin(a) * 3.0) * s, 0.26 * s, 0.12 * s, bark, segs: 5)
            }
            let g = floodLin(0x3F6130)
            crown.blob(b + V3(0, 8.2, 0) * s, V3(5.0, 3.0, 5.0) * s, g, noise, seed: seed, rings: rings, segs: segs + 2)
            for k in 0..<9 {
                let a = Float(k) / 9 * 2 * .pi + seed
                let rr: Float = k % 2 == 0 ? 3.9 : 3.2
                crown.blob(b + V3(cos(a) * rr, 6.7 + 0.7 * sin(a * 3) + Float(k % 3) * 0.5, sin(a) * rr) * s, V3(2.5, 2.0, 2.5) * s, g * (0.85 + 0.07 * Float(k % 3)), noise, seed: seed + Float(k), jitter: 0.3, rings: rings, segs: segs)
            }
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + seed + 0.6
                crown.blob(b + V3(cos(a) * 2.2, 9.6 + 0.4 * Float(k % 2), sin(a) * 2.2) * s, V3(2.0, 1.6, 2.0) * s, g * 1.08, noise, seed: seed + 20 + Float(k), jitter: 0.3, rings: rings, segs: segs)
            }
            crown.blob(b + V3(0.6, 10.5, -0.4) * s, V3(3.3, 2.1, 3.3) * s, g * 1.1, noise, seed: seed + 9, rings: rings, segs: segs)
        case 1:   // poplar (杨树)
            wood.tube(b, b + V3(0, 15.5, 0) * s, 0.24 * s, 0.07 * s, floodLin(0x7A766A), segs: 5)
            let g = floodLin(0x55703F)
            for k in 0..<4 {
                let t = Float(k)
                let off = V3(sin(seed + t * 2.1) * 0.5, 0, cos(seed + t * 1.7) * 0.5)
                crown.blob(b + (V3(0, 7.6 + t * 2.4, 0) + off) * s, V3(1.9 - t * 0.25, 1.9, 1.9 - t * 0.25) * s, g * (0.86 + 0.07 * t), noise, seed: seed + t, jitter: 0.32, rings: rings, segs: segs)
            }
        case 2:   // dawn redwood (水杉): a slim green cone
            wood.tube(b, b + V3(0, 17.5, 0) * s, 0.3 * s, 0.05 * s, floodLin(0x6A4A36), segs: 5)
            let g = floodLin(0x47683A)
            for k in 0..<5 {
                let t = Float(k) / 4
                crown.blob(b + V3(0, 5.8 + 10.4 * t, 0) * s, V3(2.7 - 2.0 * t, 2.3 - 0.6 * t, 2.7 - 2.0 * t) * s, g * (0.9 + 0.15 * t), noise, seed: seed + Float(k), rings: rings, segs: segs)
            }
        case 3:   // willow: leaning trunk, a soft crown reaching down to the water
            wood.tube(b, b + V3(1.0, 4.6, 0.4) * s, 0.34 * s, 0.2 * s, bark, segs: 6)
            let g = floodLin(0x7B8D48)
            crown.blob(b + V3(1.0, 6.3, 0.4) * s, V3(4.2, 2.6, 4.2) * s, g, noise, seed: seed, rings: rings, segs: segs + 2)
            crown.blob(b + V3(1.0, 4.5, 0.4) * s, V3(4.6, 1.7, 4.6) * s, g * 0.86, noise, seed: seed + 1, rings: rings, segs: segs + 2)
        case 4:   // bamboo clump (竹园)
            let g = floodLin(0x6D903E)
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + seed
                crown.blob(b + V3(cos(a) * 1.4, 6.4 + Float(k % 2) * 1.4, sin(a) * 1.4) * s, V3(1.5, 4.2, 1.5) * s, g * (0.9 + 0.05 * Float(k)), noise, seed: seed + Float(k), rings: rings, segs: segs)
            }
        default:  // a young tree
            wood.tube(b, b + V3(0, 4.2, 0) * s, 0.14 * s, 0.06 * s, bark, segs: 5)
            crown.blob(b + V3(0, 4.9, 0) * s, V3(2.1, 1.8, 2.1) * s, floodLin(0x4F6E38), noise, seed: seed, rings: rings, segs: segs)
        }
    }

    /// Concrete electricity poles with sagging wires; one line runs behind the house (its
    /// service wire goes to the roof), another toward the dike, one pole leaning into the water.
    private func buildPoles() {
        var m = FloodMesh(), wires = FloodMesh()
        let conc = floodLin(0x9F9B92), steel = floodLin(0x3E3E3C), wireC = floodLin(0x1E1E1E)
        func pole(_ x: Float, _ z: Float, lineYaw: Float, lean: Float = 0, leanYaw: Float = 0) -> [V3] {
            let base = V3(x, -0.8, z)
            let h: Float = 10.4
            let dir = floodRot(V3(sin(lean), cos(lean), 0), yaw: leanYaw)
            let top = base + dir * h
            m.tube(base, top, 0.17, 0.11, conc, segs: 6)
            let armC = base + dir * (h - 0.45)
            let across = floodRot(V3(0, 0, 1), yaw: lineYaw)
            m.box(armC, V3(0.05, 0.05, 0.95), yaw: lineYaw, steel)
            var pts: [V3] = []
            for k in [Float(-0.8), 0.8] {
                let p = armC + across * k
                m.box(p + V3(0, 0.1, 0), V3(0.04, 0.08, 0.04), floodLin(0xD9D4C6))
                pts.append(p + V3(0, 0.18, 0))
            }
            pts.append(top + V3(0, 0.05, 0))
            return pts
        }
        func span(_ a: V3, _ b: V3, sag: Float) {
            var prev = a
            for i in 1...6 {
                let t = Float(i) / 6
                let p = a + (b - a) * t - V3(0, sag * 4 * t * (1 - t), 0)
                wires.tube(prev, p, 0.022, 0.022, wireC, segs: 3)
                prev = p
            }
        }
        // line A behind the house, west → east
        var prev: [V3] = []
        for i in 0..<13 {
            let x = -250 + Float(i) * 42
            let z = -17 + 0.08 * x + 5 * sin(x / 90)
            let p = pole(x, z, lineYaw: -0.08)
            if !prev.isEmpty { for k in 0..<3 { span(prev[k], p[k], sag: 0.7) } }
            prev = p
            if i == 6 {
                // the service wire to the house (落户线)
                span(p[2], V3(-4.9, 6.15, -4.1), sag: 0.5)
            }
        }
        // line B toward the dike; its fourth pole leans over, wires drooping into the water
        prev = []
        for i in 0..<7 {
            let z = 150 - Float(i) * 45
            let x = 120 - Float(i) * 5
            let leaning = i == 4
            let p = pole(x, z, lineYaw: .pi / 2, lean: leaning ? 0.42 : 0, leanYaw: 0.4)
            if !prev.isEmpty { for k in 0..<3 { span(prev[k], p[k], sag: leaning || i == 5 ? 6.5 : 0.8) } }
            prev = p
        }
        world.addChildNode(m.node(vcMat(0.85)))
        world.addChildNode(wires.node(vcMat(0.6), shadow: false))
    }

    // MARK: The dike

    private func dikeZ(_ x: Float) -> Float { -168 + 12 * sin(x / 260 + 0.6) }

    /// The main dike (大堤) along the northern horizon: grassy slopes, a muddy waterline, the crest
    /// road with a wall of white sandbags (子堤), tents, red flags, people and army trucks, and a row
    /// of poplars at its foot. At night a string of work lights.
    private func buildDike() {
        var body = FloodMesh(), stuff = FloodMesh(), crowns = FloodMesh(), wood = FloodMesh(), lights = FloodMesh()
        let prof: [(Float, Float, UInt32)] = [(-34, -1.6, 0x4E4232), (-23, 2.4, 0x5E4E38), (-17, 4.6, 0x6A7444), (-6.0, 9.35, 0x748048),
                                               (-4.6, 9.6, 0xA08D6A), (4.6, 9.6, 0x9A8866), (6.0, 9.35, 0x6C7742), (32, -1.6, 0x5B6A3E)]
        let step: Float = 12
        var rows: [[V3]] = []
        var xs: [Float] = []
        var x: Float = -1500
        while x <= 1500 { xs.append(x); x += step }
        for x in xs {
            let zc = dikeZ(x)
            let dz = (dikeZ(x + 1) - dikeZ(x - 1)) / 2
            let l = sqrt(1 + dz * dz)
            let across = V3(dz / l, 0, -1 / l)          // toward the river (north)
            rows.append(prof.map { V3(x, $0.1, zc) + across * $0.0 })
        }
        var rng = FloodRng(41)
        for i in 0..<(rows.count - 1) {
            let shade = 0.92 + 0.12 * noise.value(Float(i) * 0.37, 3)
            for k in 0..<(prof.count - 1) {
                body.quad(rows[i][k], rows[i + 1][k], rows[i + 1][k + 1], rows[i][k + 1], floodLin(prof[k].2) * shade)
            }
        }
        // the sandbag wall on the river edge of the crest, and the crest details
        for (i, x) in xs.enumerated() where i < xs.count - 1 {
            let zc = dikeZ(x + step / 2)
            let dz = (dikeZ(x + step / 2 + 1) - dikeZ(x + step / 2 - 1)) / 2
            let yaw = atan2(-dz, 1)
            let l = sqrt(1 + dz * dz)
            let across = V3(dz / l, 0, -1 / l)
            let c = V3(x + step / 2, 9.6, zc)
            stuff.box(c + across * 3.7 + V3(0, 0.42, 0), V3(step / 2, 0.42, 0.55), yaw: yaw, floodLin(0xD3CEC0) * rng.r(0.9, 1.05))
            guard abs(x) < 620 else { continue }
            // tents of plastic sheeting along the land side of the crest
            if rng.next() < 0.62 {
                let cols: [UInt32] = [0x2C5EA8, 0x2C5EA8, 0xD8D8D2, 0xD8702E, 0x3E6E9E, 0xB8B4A8]
                let tc = floodLin(rng.pick(cols))
                stuff.gable(c + across * -2.6 + V3(rng.r(-3, 3), 0, 0), halfL: rng.r(1.6, 2.6), halfW: 1.2, rise: rng.r(1.7, 2.1), over: 0.1, yaw: yaw, tc, gableCol: tc * 0.85)
            }
            // people: soldiers in green, orange life vests, villagers in white and blue
            let n = abs(x) < 300 ? Int(rng.r(1, 6)) : Int(rng.r(0, 3))
            for _ in 0..<n {
                let p = c + across * rng.r(-3.8, 2.6) + V3(rng.r(-5, 5), 0, 0)
                let pc: [UInt32] = [0x4F5C38, 0x4F5C38, 0xD9652B, 0xDAD6CA, 0x3A5590, 0x6E6A62]
                stuff.box(p + V3(0, 0.62, 0), V3(0.2, 0.62, 0.14), floodLin(rng.pick(pc)))
                stuff.box(p + V3(0, 1.38, 0), V3(0.12, 0.13, 0.12), floodLin(0xC9A285))
            }
            // red flags (抗洪抢险突击队)
            if i % 4 == 0 && abs(x) < 420 {
                let p = c + across * 1.6
                stuff.tube(p, p + V3(0, 6.5, 0), 0.05, 0.04, floodLin(0x8E8E88), segs: 4)
                stuff.box(p + V3(0.8, 6.0, 0), V3(0.8, 0.5, 0.02), yaw: yaw, floodLin(0xC8201E))
            }
            // army trucks parked on the crest road
            if [24, 112, 141, 160].contains(i) {
                let p = c + across * 0.3
                stuff.box(p + V3(0, 1.4, 0), V3(3.3, 1.0, 1.2), yaw: yaw, floodLin(0x55603A))
                stuff.box(p + floodRot(V3(3.9, 1.1, 0), yaw: yaw), V3(0.75, 0.95, 1.15), yaw: yaw, floodLin(0x4C5634))
                stuff.box(p + V3(0, 2.55, 0), V3(3.3, 0.35, 1.2), yaw: yaw, floodLin(0x6E7448))
            }
        }
        // poplars at the land-side foot of the dike, with gaps
        for (i, x) in xs.enumerated() where i % 2 == 0 {
            for k in 0..<2 {
                let tx = x + Float(k) * 6 + rng.r(-1.5, 1.5)
                if noise.value(tx / 60, 7) < 0.33 { continue }
                tree(&crowns, &wood, kind: rng.next() < 0.75 ? 1 : 3, x: tx, z: dikeZ(tx) + 25 + rng.r(-2, 2), base: -0.6, s: rng.r(0.8, 1.05), seed: tx, lowRes: true)
            }
        }
        // night: work lights on poles along the crest
        for x in stride(from: Float(-1000), through: 1000, by: 15) {
            let p = V3(x, 12.2, dikeZ(x) + 1.0)
            lights.blob(p, V3(0.32, 0.32, 0.32), V3(1, 1, 1), noise, seed: 0, jitter: 0, rings: 3, segs: 4, under: 1, vary: 0)
        }
        let dikeNode = body.node(vcMat(0.95), shadow: false)
        world.addChildNode(dikeNode)
        world.addChildNode(stuff.node(vcMat(0.85), shadow: false))
        world.addChildNode(crowns.node(vcMat(0.95), shadow: false))
        world.addChildNode(wood.node(vcMat(0.95), shadow: false))
        let lm = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFFE0A6))
        lm.emission.intensity = 2.5
        let ln = lights.node(lm, shadow: false)
        world.addChildNode(ln)
        dikeLights = ln
    }

    /// Farmsteads in the distance: tree clumps with a roof or two above the water.
    private func buildFarland() {
        var crowns = FloodMesh(), roofs = FloodMesh(), walls = FloodMesh(), wood = FloodMesh(), fires = FloodMesh()
        var rng = FloodRng(57)
        var placed = 0
        for _ in 0..<120 {
            if placed >= 64 { break }
            let a = rng.r(0, 2 * .pi), d = rng.r(160, 720)
            let x = sin(a) * d, z = cos(a) * d
            if z < dikeZ(x) + 60 { continue }
            placed += 1
            let n = Int(rng.r(4, 11))
            for k in 0..<n {
                let tx = x + rng.r(-18, 18), tz = z + rng.r(-10, 10)
                let kind = [0, 1, 1, 3, 4, 2, 5][Int(rng.r(0, 6.99))]
                tree(&crowns, &wood, kind: kind, x: tx, z: tz, base: -0.8, s: rng.r(0.7, 1.05), seed: Float(k) + x, lowRes: true)
            }
            for k in 0..<Int(rng.r(0, 3)) {
                villageHouse(&walls, &roofs, x + rng.r(-14, 14), z + rng.r(-6, 6), yaw: rng.r(-0.3, 0.3), kind: Int(rng.r(0, 2.99)), seed: UInt64(900 + placed * 3 + k))
            }
            if placed % 9 == 4 {
                fires.blob(V3(x + 3, 7.0, z), V3(0.5, 0.4, 0.5), V3(1, 1, 1), noise, seed: 0, jitter: 0, rings: 3, segs: 5, under: 1, vary: 0)
            }
        }
        world.addChildNode(crowns.node(vcMat(0.95), shadow: false))
        world.addChildNode(roofs.node(roofMat(), shadow: false))
        world.addChildNode(walls.node(vcMat(0.9), shadow: false))
        world.addChildNode(wood.node(vcMat(0.95), shadow: false))
        let fm = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF9A40))
        fm.emission.intensity = 2.2
        let fn = fires.node(fm, shadow: false)
        world.addChildNode(fn)
        farFires = fn
    }

    // MARK: Things floating in the water

    private func buildDebris() {
        var straw = FloodMesh(), junk = FloodMesh(), plastic = FloodMesh(), scumA = FloodMesh(), scumB = FloodMesh()
        var rng = FloodRng(77)
        let strawC = [floodLin(0x9C8C60), floodLin(0x8C7C52), floodLin(0x7C6C48), floodLin(0xAA9A6C)]
        func free(_ x: Float, _ z: Float) -> Bool { !(abs(x) < 6.2 && z > -5 && z < 8.6) }
        // straw and rubbish piled against the upstream (east) wall, around trunks and poles,
        // and strung out in lines by the current
        for i in 0..<9 {
            straw.patch(V3(6.0 + rng.r(0, 2.5), 0.03, -3.6 + Float(i) * 0.95), rng.r(0.7, 1.4), rng.pick(strawC), noise, seed: Float(i), aspect: 0.7, yaw: rng.r(0, 3))
        }
        for _ in 0..<70 {
            let x = rng.r(-120, 120), z = rng.r(-100, 80)
            let line = sin(z / 7 + x / 60)
            if line < 0.2 || !free(x, z) { continue }
            straw.patch(V3(x, 0.03, z), rng.r(0.6, 2.6), rng.pick(strawC), noise, seed: x, aspect: rng.r(0.3, 0.7), yaw: rng.r(-0.3, 0.3))
        }
        straw.patch(V3(-9.6, 0.03, 9.3), 1.6, strawC[1], noise, seed: 4, aspect: 0.8)
        // planks, beams, a wardrobe, a chair, branches
        let woodC = [floodLin(0xA08058), floodLin(0x9C9482), floodLin(0x7E6346), floodLin(0xB49C78)]
        for _ in 0..<64 {
            var x = rng.r(-60, 70), z = rng.r(-60, 45)
            if rng.next() < 0.45 { x = rng.r(-16, 22); z = rng.r(-12, 24) }
            if !free(x, z) { continue }
            let kind = rng.next()
            let yaw = rng.r(-0.6, 0.6) + (rng.next() < 0.3 ? 1.57 : 0)
            if kind < 0.5 {
                junk.box(V3(x, 0.03, z), V3(rng.r(0.8, 1.6), 0.03, rng.r(0.08, 0.16)), yaw: yaw, rng.pick(woodC))
            } else if kind < 0.7 {
                let d = floodRot(V3(rng.r(1, 2.2), 0, 0), yaw: yaw)
                junk.tube(V3(x, 0.04, z) - d, V3(x, 0.04, z) + d, rng.r(0.07, 0.13), 0.08, floodLin(0x5E5040), segs: 5)
            } else if kind < 0.8 {
                junk.box(V3(x, 0.12, z), V3(0.9, 0.25, 0.32), yaw: yaw, pitch: 0, roll: 0.25, floodLin(0x6A3424))
            } else if kind < 0.9 {
                junk.box(V3(x, 0.09, z), V3(0.3, 0.09, 0.22), yaw: yaw, floodLin(0xE9E7DF))     // foam blocks
            } else {
                for k in 0..<4 {
                    let d = floodRot(V3(rng.r(0.5, 1.1), 0, 0), yaw: yaw + Float(k) * 1.4)
                    junk.tube(V3(x, 0.04, z), V3(x, 0.12, z) + d, 0.04, 0.015, floodLin(0x4A3B2C), segs: 4)
                }
            }
        }
        // plastic basins, buckets and drums, watermelons
        let plasticC: [UInt32] = [0xC0392B, 0x2E6DB4, 0x3C8F4F, 0xD97A9A, 0xD9A63A, 0xE6E4DC]
        for _ in 0..<40 {
            var x = rng.r(-50, 60), z = rng.r(-45, 40)
            if rng.next() < 0.5 { x = rng.r(-14, 20); z = rng.r(-10, 22) }
            if !free(x, z) { continue }
            let c = floodLin(rng.pick(plasticC))
            if rng.next() < 0.65 {
                let r = rng.r(0.22, 0.36)
                plastic.lathe(V3(x, -0.04, z), [(0, r * 0.75), (0.14, r), (0.15, r * 0.94)], segs: 10, c)
                plastic.patch(V3(x, 0.07, z), r * 0.8, c * 0.6, noise, seed: x, rough: 0.02)
            } else {
                let yaw = rng.r(0, 3)
                let d = floodRot(V3(0.4, 0, 0), yaw: yaw)
                plastic.tube(V3(x, 0.05, z) - d, V3(x, 0.05, z) + d, 0.25, 0.25, c, segs: 10, cap: true)
            }
        }
        for k in 0..<7 {
            let x = rng.r(2, 14), z = rng.r(6, 16)
            plastic.blob(V3(x, 0.02, z), V3(0.17, 0.15, 0.16), floodLin(0x2F5A2A), noise, seed: Float(k), jitter: 0.03, rings: 5, segs: 8, under: 0.7, vary: 0.2)
        }
        // close to the front: a door off its hinges, a straw mat, a basin and a stool
        junk.box(V3(8.8, 0.05, 12.2), V3(1.0, 0.04, 0.45), yaw: 0.5, floodLin(0x7A3B2A))
        junk.box(V3(8.8, 0.1, 12.2), V3(0.95, 0.01, 0.03), yaw: 0.5, floodLin(0x4A2418))
        straw.patch(V3(-1.5, 0.03, 16.5), 0.9, strawC[0], noise, seed: 31, aspect: 0.45, yaw: 0.2, rough: 0.5)
        straw.patch(V3(-0.2, 0.03, 15.8), 0.6, strawC[1], noise, seed: 34, aspect: 0.5, yaw: 0.5, rough: 0.5)
        straw.patch(V3(10.5, 0.03, 9.5), 1.0, strawC[2], noise, seed: 32, aspect: 0.6, yaw: -0.3)
        plastic.lathe(V3(3.2, -0.04, 18.5), [(0, 0.24), (0.14, 0.32), (0.15, 0.3)], segs: 10, floodLin(0xC0392B))
        plastic.patch(V3(3.2, 0.07, 18.5), 0.26, floodLin(0xC0392B) * 0.6, noise, seed: 33, rough: 0.02)
        junk.box(V3(-4.5, 0.12, 12.8), V3(0.22, 0.12, 0.16), yaw: 0.8, roll: 1.2, floodLin(0x8B6B47))
        floatRoot.addChildNode(straw.node(vcMat(0.95), shadow: false))
        floatRoot.addChildNode(junk.node(vcMat(0.85)))
        floatRoot.addChildNode(plastic.node(vcMat(0.45)))

        // scum: grey foam and rubbish collecting as the water gets fouler (var.filth)
        for i in 0..<12 {
            let x = rng.r(-14, -6), z = rng.r(-6, 9)
            scumA.patch(V3(x, 0.035, z), rng.r(0.6, 1.5), floodLin(0x8E8A78), noise, seed: Float(i), aspect: 0.6, yaw: rng.r(-0.3, 0.3))
        }
        for i in 0..<14 {
            let x = rng.r(-22, 24), z = rng.r(-14, 22)
            if !free(x, z) { continue }
            scumB.patch(V3(x, 0.035, z), rng.r(0.5, 1.3), floodLin(0x7E7A68), noise, seed: Float(i) + 50, aspect: 0.5, yaw: rng.r(-0.3, 0.3))
        }
        let sm = vcMat(0.9)
        let sa = scumA.node(sm, shadow: false), sb = scumB.node(sm, shadow: false)
        floatRoot.addChildNode(sa)
        floatRoot.addChildNode(sb)
        scum = [sa, sb]

        // dead pigs: one out in the flood, one that drifts under the window (event r_dead_pig)
        func deadPig() -> SCNNode {
            var p = FloodMesh()
            let skin = floodLin(0xC9A493)
            p.blob(V3(0, 0.12, 0), V3(0.75, 0.38, 0.45), skin, noise, seed: 3, jitter: 0.05, rings: 6, segs: 10, under: 0.7, vary: 0.15)
            p.blob(V3(0.82, 0.08, 0.05), V3(0.3, 0.22, 0.24), skin * 0.95, noise, seed: 4, jitter: 0.05, rings: 5, segs: 8)
            for (lx, lz) in [(Float(0.4), Float(0.25)), (0.45, -0.2), (-0.45, 0.22), (-0.4, -0.25)] {
                p.tube(V3(lx, 0.25, lz), V3(lx + 0.05, 0.55, lz * 1.6), 0.06, 0.045, skin * 0.85, segs: 5)
            }
            return p.node(vcMat(0.7))
        }
        let pf = deadPig()
        pf.position = SCNVector3(9, 0, -12)
        pf.eulerAngles.y = 0.7
        floatRoot.addChildNode(pf)
        pigFar = pf
        let pn = deadPig()
        pn.position = SCNVector3(6.5, 0, 1.4)
        pn.eulerAngles.y = 1.4
        floatRoot.addChildNode(pn)
        pigNear = pn
        // a roof beam (房梁) that the current keeps knocking against the east wall (event r_debris)
        var bm = FloodMesh()
        bm.tube(V3(-3.0, 0.08, 0), V3(3.0, 0.08, 0), 0.15, 0.13, floodLin(0x4E3E2C), segs: 7)
        bm.box(V3(1.6, 0.18, 0), V3(0.5, 0.06, 0.07), floodLin(0x6E5338))
        let bn = bm.node(vcMat(0.9))
        floatRoot.addChildNode(bn)
        beam = bn
    }

    // MARK: Boats, helicopter, swimmer

    private func buildBoats() {
        let crew = SK.rgb(0xE0702A)
        let others: [NSColor] = [SK.rgb(0x8DA4C0), SK.rgb(0xD8D6CE), SK.rgb(0x5D6874), SK.rgb(0xB8402F), SK.rgb(0x6E8A55), SK.rgb(0xC9A27C), SK.rgb(0x3A4E7A)]
        for b in 0..<3 {
            let (node, crowd, wake) = assaultBoat(crew: crew, others: others, seed: b)
            node.isHidden = true
            floatRoot.addChildNode(node)
            boats.append(node)
            boatCrowd.append(crowd)
            boatWakes.append(wake)
        }
        let spot = SCNLight()
        spot.type = .spot
        spot.color = SK.rgb(0xFFF2D8)
        spot.intensity = 1600
        spot.spotInnerAngle = 6
        spot.spotOuterAngle = 20
        spot.attenuationStartDistance = 0
        spot.attenuationEndDistance = 70
        spot.castsShadow = false
        let sl = SCNNode()
        sl.light = spot
        sl.position = SCNVector3(2.3, 1.3, 0)
        boats[0].addChildNode(sl)
        boatLight = sl

        // the fisherman's little rowing boat (小划子)
        let sp = SCNNode()
        var h = FloodMesh()
        let wood = floodLin(0x5E4630)
        let st: [(Float, Float, Float, Float)] = [(-2.0, 0.42, 0.32, -0.16), (-0.8, 0.5, 0.3, -0.2), (0.6, 0.48, 0.3, -0.2), (1.6, 0.3, 0.36, -0.12), (2.15, 0.03, 0.45, 0.1)]
        hull(&h, st, wood, floor: floodLin(0x4A3726))
        sp.addChildNode(h.node(vcMat(0.85, doubleSided: true)))
        let man = SK.person(color: SK.rgb(0x4E5A66), pose: .sitting, seed: 0)
        man.position = SCNVector3(-1.3, -0.12, 0)
        man.eulerAngles.y = .pi / 2
        let hat = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.3, height: 0.16))
        hat.geometry?.firstMaterial = SK.mat(SK.rgb(0xC9A961), roughness: 0.95)
        hat.position = SCNVector3(0, 1.36, 0)
        man.addChildNode(hat)
        sp.addChildNode(man)
        fisherman = man
        var oar = FloodMesh()
        oar.tube(V3(-1.0, 0.75, 0.2), V3(-2.6, -0.3, 0.9), 0.025, 0.025, floodLin(0x8A6A45), segs: 4)
        oar.box(V3(-2.5, -0.2, 0.86), V3(0.25, 0.02, 0.09), yaw: -0.4, floodLin(0x8A6A45))
        sp.addChildNode(oar.node(vcMat(0.8)))
        sp.isHidden = true
        floatRoot.addChildNode(sp)
        sampan = sp

        // the army helicopter dropping supplies (event r_airdrop)
        let hn = SCNNode()
        var hm = FloodMesh()
        let olive = floodLin(0x56603E), dark = floodLin(0x24271F)
        hm.blob(V3(0, 0, 0), V3(4.3, 1.35, 1.3), olive, noise, seed: 3, jitter: 0.02, rings: 8, segs: 12, under: 0.75, vary: 0.05)
        hm.blob(V3(3.6, -0.15, 0), V3(1.5, 1.05, 1.1), olive, noise, seed: 4, jitter: 0.02, rings: 6, segs: 10, under: 0.75, vary: 0.05)
        hm.blob(V3(4.2, 0.25, 0), V3(0.9, 0.55, 0.95), floodLin(0x1C2A33), noise, seed: 5, jitter: 0.01, rings: 5, segs: 8, under: 0.9, vary: 0)
        hm.tube(V3(-3.4, 0.35, 0), V3(-10.6, 0.85, 0), 0.55, 0.22, olive, segs: 8)
        hm.box(V3(-10.4, 1.7, 0), V3(0.6, 1.0, 0.06), olive * 0.9)
        hm.box(V3(0.2, 1.55, 0), V3(1.6, 0.4, 0.75), olive * 0.95)
        hm.tube(V3(0.2, 1.9, 0), V3(0.2, 2.35, 0), 0.12, 0.12, dark, segs: 6)
        for k in 0..<5 {
            let a = Float(k) / 5 * 2 * .pi
            hm.box(V3(0.2, 2.36, 0) + floodRot(V3(4.3, 0, 0), yaw: a), V3(4.1, 0.03, 0.22), yaw: a, dark)
        }
        hm.box(V3(-10.6, 0.9, 0.35), V3(0.9, 0.08, 0.02), dark)
        hm.box(V3(0.6, -0.1, 1.31), V3(0.8, 0.75, 0.02), floodLin(0x15161A))          // the open door
        for k in 0..<4 { hm.box(V3(-1.8 + Float(k) * 0.75, 0.35, 1.29), V3(0.22, 0.2, 0.02), floodLin(0x1C2A33)) }
        hm.tube(V3(1.6, -1.55, 0.9), V3(-1.6, -1.55, 0.9), 0.06, 0.06, dark, segs: 5)
        hm.tube(V3(1.6, -1.55, -0.9), V3(-1.6, -1.55, -0.9), 0.06, 0.06, dark, segs: 5)
        for (x, z) in [(Float(1.0), Float(0.9)), (-1.0, 0.9), (1.0, -0.9), (-1.0, -0.9)] { hm.tube(V3(x, -1.55, z), V3(x * 0.8, -1.0, z * 0.7), 0.05, 0.05, dark, segs: 4) }
        hn.addChildNode(hm.node(vcMat(0.6)))
        let disc = SCNNode(geometry: SCNCylinder(radius: 8.4, height: 0.02))
        let dm = SK.mat(SK.rgb(0x8A8E86), roughness: 0.8)
        dm.transparency = 0.07
        dm.writesToDepthBuffer = false
        disc.geometry?.firstMaterial = dm
        disc.position = SCNVector3(0.2, 2.38, 0)
        disc.castsShadow = false
        hn.addChildNode(disc)
        // a woven sack falling from the door
        let sack = SK.box(0.5, 0.7, 0.35, SK.mat(SK.rgb(0xDCD8CA), roughness: 0.9), chamfer: 0.08, at: SCNVector3(0.8, -4.5, 2.4))
        sack.eulerAngles = SCNVector3(0.4, 0.3, 0.6)
        hn.addChildNode(sack)
        hn.position = SCNVector3(-24, 19, -32)
        hn.eulerAngles = SCNVector3(0, -0.75, 0.06)
        hn.isHidden = true
        world.addChildNode(hn)
        heli = hn

        // someone swimming to the dike: a head, an arm, a float or a life vest, a little wake
        let sw = SCNNode()
        var s = FloodMesh()
        s.blob(V3(0, 0.1, 0), V3(0.11, 0.13, 0.12), floodLin(0xC9A285), noise, seed: 1, jitter: 0.02, rings: 5, segs: 8, under: 0.8, vary: 0)
        s.blob(V3(0, 0.17, 0.02), V3(0.12, 0.08, 0.12), floodLin(0x1A1612), noise, seed: 2, jitter: 0.02, rings: 4, segs: 8)
        s.tube(V3(0.1, 0.02, 0.1), V3(0.75, 0.12, 0.25), 0.05, 0.045, floodLin(0xC9A285), segs: 5)
        s.patch(V3(-0.6, 0.02, 0), 0.9, floodLin(0xD6CDB6), noise, seed: 3, aspect: 0.35, rough: 0.2)
        sw.addChildNode(s.node(vcMat(0.7)))
        var bar = FloodMesh()
        bar.tube(V3(-0.5, 0.05, -0.35), V3(-0.5, 0.05, 0.35), 0.2, 0.2, floodLin(0xE6E4DC), segs: 10, cap: true)
        let barN = bar.node(vcMat(0.4))
        sw.addChildNode(barN)
        swimBarrel = barN
        var vest = FloodMesh()
        vest.blob(V3(-0.25, 0.03, 0), V3(0.35, 0.12, 0.26), floodLin(0xE0662A), noise, seed: 4, jitter: 0.04, rings: 4, segs: 8)
        let vestN = vest.node(vcMat(0.6))
        sw.addChildNode(vestN)
        swimVest = vestN
        sw.position = SCNVector3(-16, 0, -52)
        sw.eulerAngles.y = 1.9
        sw.isHidden = true
        floatRoot.addChildNode(sw)
        swimmer = sw
    }

    /// Lofted hull from stations (x, half-beam, gunwale height, keel depth), bow toward +x.
    private func hull(_ m: inout FloodMesh, _ st: [(Float, Float, Float, Float)], _ col: V3, floor: V3) {
        func sec(_ s: (Float, Float, Float, Float)) -> [V3] {
            let (x, b, gh, kd) = s
            return [V3(x, gh, b), V3(x, kd * 0.45 + 0.02, b * 0.86), V3(x, kd, 0), V3(x, kd * 0.45 + 0.02, -b * 0.86), V3(x, gh, -b)]
        }
        for i in 0..<(st.count - 1) {
            let a = sec(st[i]), b = sec(st[i + 1])
            for k in 0..<4 { m.quad(a[k], a[k + 1], b[k + 1], b[k], col * (k == 1 || k == 2 ? 0.8 : 1)) }
            // the floor boards inside
            let fa = st[i].1 * 0.8, fb = st[i + 1].1 * 0.8
            let y = st[i].3 * 0.3
            m.quad(V3(st[i].0, y, -fa), V3(st[i].0, y, fa), V3(st[i + 1].0, y, fb), V3(st[i + 1].0, y, -fb), floor)
        }
        let s0 = sec(st[0])
        m.tri(s0[0], s0[2], s0[1], col * 0.85)
        m.tri(s0[0], s0[4], s0[2], col * 0.85)
        m.tri(s0[4], s0[3], s0[2], col * 0.85)
        // rubbing strakes along the gunwales
        for i in 0..<(st.count - 1) {
            for sgn in [Float(1), -1] {
                m.tube(V3(st[i].0, st[i].2, st[i].1 * sgn), V3(st[i + 1].0, st[i + 1].2, st[i + 1].1 * sgn), 0.05, 0.05, floodLin(0x22231F), segs: 4)
            }
        }
    }

    /// A PLA assault boat (冲锋舟): camouflaged hull, outboard, red flag, two soldiers in orange
    /// life vests and up to twelve passengers; returns the passengers and the wake to toggle.
    private func assaultBoat(crew: NSColor, others: [NSColor], seed: Int) -> (SCNNode, [SCNNode], SCNNode) {
        let root = SCNNode()
        var h = FloodMesh()
        let st: [(Float, Float, Float, Float)] = [(-2.7, 0.92, 0.42, -0.3), (-1.4, 0.95, 0.42, -0.34), (0.2, 0.93, 0.45, -0.34), (1.4, 0.78, 0.52, -0.26), (2.2, 0.48, 0.62, -0.1), (2.75, 0.04, 0.74, 0.3)]
        hull(&h, st, V3(1, 1, 1), floor: floodLin(0x6A6A5E))
        let camo = SK.mat(.white, roughness: 0.7, doubleSided: true)
        camo.diffuse.contents = FloodTex.camo()
        camo.diffuse.wrapS = .repeat
        camo.diffuse.wrapT = .repeat
        camo.diffuse.contentsTransform = SCNMatrix4MakeScale(0.45, 0.45, 1)
        root.addChildNode(h.node(camo))
        var e = FloodMesh()
        e.box(V3(-2.95, 0.62, 0), V3(0.24, 0.34, 0.2), floodLin(0x2B2D30))
        e.box(V3(-2.95, 0.98, 0), V3(0.26, 0.06, 0.22), floodLin(0xD8D8D2))
        e.tube(V3(-2.98, 0.3, 0), V3(-2.98, -0.55, 0), 0.06, 0.06, floodLin(0x2B2D30), segs: 5)
        for x in [Float(-1.6), -0.2, 1.0] { e.box(V3(x, 0.08, 0), V3(0.14, 0.035, 0.78), floodLin(0x5E5E52)) }
        e.tube(V3(2.35, 0.6, 0), V3(2.35, 2.1, 0), 0.025, 0.02, floodLin(0x8E8E88), segs: 4)
        e.box(V3(2.0, 1.85, 0), V3(0.35, 0.22, 0.012), floodLin(0xC8201E))
        root.addChildNode(e.node(vcMat(0.6)))
        let helm = SK.person(color: crew, pose: .sitting, seed: 0)
        helm.position = SCNVector3(-2.35, -0.05, 0)
        helm.eulerAngles.y = .pi / 2
        root.addChildNode(helm)
        let bow = SK.person(color: crew, pose: .standing, seed: 0)
        bow.position = SCNVector3(1.55, -0.12, 0.15)
        bow.eulerAngles.y = .pi / 2 + 0.4
        root.addChildNode(bow)
        var crowd: [SCNNode] = []
        let seatsXZ: [(CGFloat, CGFloat)] = [(-1.5, -0.42), (-1.5, 0.42), (-0.75, -0.45), (-0.75, 0.45), (0.0, -0.45), (0.0, 0.45),
                                             (0.75, -0.4), (0.75, 0.4), (-1.12, 0), (-0.38, 0), (0.38, 0), (1.1, 0)]
        for (i, p) in seatsXZ.enumerated() {
            let c = others[(i * 3 + seed) % others.count]
            let n = SK.person(color: c, pose: .sitting, child: i == 9, seed: 0)
            n.position = SCNVector3(p.0, -0.08, p.1)
            n.eulerAngles.y = p.1 < 0 ? .pi * 0.9 : (p.1 > 0 ? 0.1 : .pi / 2)
            root.addChildNode(n)
            crowd.append(n)
        }
        // wake: white water behind the stern, spreading in a V
        var w = FloodMesh()
        let foam = floodLin(0xE4DDCB)
        // the churned trail behind the outboard, widening and thinning out
        for k in 0..<12 {
            let t = Float(k)
            w.patch(V3(-3.3 - t * 0.85, 0.06, 0.12 * sin(t * 1.7)), 0.55 + t * 0.07, foam * (1 - t * 0.045), noise, seed: t, aspect: 0.55 - t * 0.02, rough: 0.45)
        }
        // the bow wave folding off both sides
        for sgn in [Float(1), -1] {
            w.patch(V3(2.0, 0.06, sgn * 0.95), 0.75, foam * 0.85, noise, seed: 7 * sgn, aspect: 0.3, yaw: sgn * 0.5, rough: 0.4)
        }
        let wm = vcMat(0.9, doubleSided: true)
        wm.transparency = 0.42
        wm.writesToDepthBuffer = false
        let wn = w.node(wm, shadow: false)
        root.addChildNode(wn)
        return (root, crowd, wn)
    }

    // MARK: Lights

    private func buildLights() {
        // the hurricane lamp (马灯) hung by the stair-head door
        let lamp = SCNNode()
        let glassM = SK.mat(SK.rgb(0xFFE6B0), roughness: 0.2, emission: SK.rgb(0x000000))
        lampMat = glassM
        let g = SK.sphere(0.07, glassM, segments: 10)
        lamp.addChildNode(g)
        let cap = SK.cylinder(0.06, 0.05, SK.mat(SK.rgb(0x3A3A36), roughness: 0.5, metalness: 0.6), at: SCNVector3(0, 0.1, 0))
        lamp.addChildNode(cap)
        let stool = SK.box(0.36, 0.5, 0.3, SK.mat(SK.rgb(0x6E5236), roughness: 0.9), chamfer: 0.01, at: SCNVector3(0, -0.33, 0))
        lamp.addChildNode(stool)
        let light = SCNLight()
        light.type = .omni
        light.color = SK.rgb(0xFFC27A)
        light.intensity = 60
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 9
        light.attenuationFalloffExponent = 2
        light.castsShadow = false
        let ln = SCNNode()
        ln.light = light
        lamp.addChildNode(ln)
        lamp.position = SCNVector3(1.55, roofY + 0.62, 0.35)
        house.addChildNode(lamp)
        lampLight = ln

        // a torch sweeping the water in front of the house at night
        let t = SCNLight()
        t.type = .spot
        t.color = SK.rgb(0xFFF1D6)
        t.intensity = 900
        t.spotInnerAngle = 7
        t.spotOuterAngle = 22
        t.attenuationStartDistance = 0
        t.attenuationEndDistance = 45
        t.castsShadow = false
        let tn = SCNNode()
        tn.light = t
        tn.position = SCNVector3(1.4, roofY + 1.3, 3.7)
        world.addChildNode(tn)
        torch = tn
    }

    // MARK: Apply

    override func apply(_ s: SceneState, old: SceneState?) {
        let lv = CGFloat(max(0, min(7.5, s.v("level", 2.8))))
        if old == nil { highWater = lv }
        highWater = max(highWater, lv)
        if s.has("was_on_roof") { highWater = max(highWater, 3.42) }
        let collapsed = s.has("collapsed")
        let rain = s.precip
        let onRoof = collapsed || s.has("on_roof") || lv >= floor2 - 0.02
        let night = darkness > 0.6
        let someone = !s.people.isEmpty

        // the water, the current, the dirt
        water?.position.y = lv
        floatRoot.position.y = lv
        let amp = 0.03 + 0.0035 * min(60, s.wind) + 0.02 * rain
        waterMat?.setValue(NSNumber(value: amp), forKey: "amplitude")
        waterMat?.setValue(NSNumber(value: 0.45 + 0.035 * min(60, s.wind)), forKey: "choppiness")
        waterMat?.normal.intensity = CGFloat(0.62 + 0.25 * rain + 0.006 * s.wind)
        let filth = max(0, min(100, s.v("filth", 30)))
        waterMat?.multiply.contents = NSColor(calibratedRed: CGFloat(1 - filth * 0.0016), green: CGFloat(1 - filth * 0.0014), blue: CGFloat(1 - filth * 0.0022), alpha: 1)
        foamMat?.transparency = CGFloat(min(1, 0.4 + 0.013 * s.wind + 0.12 * rain))
        scum[0].isHidden = filth < 45
        scum[1].isHidden = filth < 70

        // the house: wet and muddy bands, cracks, the collapse
        let cracks = s.has("cracks") || s.shelter < 45
        let worse = s.has("collapse_coming") || s.shelter < 30
        crackA?.isHidden = !cracks
        crackB?.isHidden = !worse || collapsed
        house.eulerAngles.z = collapsed ? -0.12 : 0
        house.position = collapsed ? SCNVector3(0.5, -1.1, 0) : SCNVector3Zero
        rubble?.isHidden = !collapsed
        wetBand?.isHidden = collapsed || lv < 0.05 || lv > 6.05
        wetBand?.position.y = lv
        wetBand?.scale.y = 0.3
        let mud = highWater - lv
        mudBand?.isHidden = collapsed || mud < 0.06
        mudBand?.position.y = lv
        mudBand?.scale.y = max(0.02, mud)
        mudLine?.isHidden = collapsed || mud < 0.06
        mudLine?.position.y = highWater - 0.03
        mudLine?.scale.y = 0.06
        let wet = rain >= 1
        concreteMat?.multiply.contents = wet ? NSColor(white: 0.66, alpha: 1) : NSColor.white
        concreteMat?.roughness.contents = wet ? 0.4 : 0.92
        laundry?.isHidden = wet || s.wind >= 35 || collapsed

        // grandma's bamboo bed: on the balcony while the second floor is dry, then on the roof
        if onRoof {
            bed?.position = SCNVector3(-3.9, roofY, -0.1)
            bed?.eulerAngles.y = .pi / 2
        } else {
            bed?.position = SCNVector3(-0.95, floor2, 4.72)
            bed?.eulerAngles.y = 0
        }
        bed?.isHidden = collapsed

        // signals
        let signal = s.v("signal", 4)
        quiltFlag?.isHidden = !(signal >= 12 || s.has("dehou_stayed"))
        sos?.isHidden = signal < 25
        sosMat?.transparency = CGFloat(max(0.3, 1 - 0.3 * rain))
        helpSheet?.isHidden = signal < 50
        antennaRag?.isHidden = signal < 75

        // projects
        let aw = s.project("awning")
        awningPoles?.isHidden = aw < 0.25
        awningSheet?.isHidden = aw < 0.999
        let rf = s.project("raft")
        let raftGone = s.has("raft_gone")
        raftWork?.isHidden = !(rf >= 0.12 && rf < 0.999)
        raftWorkLate?.isHidden = !(rf >= 0.55 && rf < 0.999)
        let raftUp = rf >= 0.999 && !raftGone
        raft?.isHidden = !raftUp
        raftCoffin?.isHidden = !s.has("coffin_used")
        raft?.position = collapsed ? SCNVector3(-7.5, 0, 9.5) : SCNVector3(-0.7, 0, 6.85)
        if let rope = raftRope {
            let a = SCNVector3(0.25, lv + 0.35, 6.45), b = SCNVector3(1.78, min(lv + 3.0, 3.05), 5.3)
            layRope(rope, a, b)
            rope.isHidden = !raftUp || collapsed || lv > 3.0
        }

        // things on the roof that come with flags and supplies
        basins?.isHidden = !s.has("basins")
        wok?.isHidden = !s.has("wok")
        latrine?.isHidden = !s.has("hygiene")
        let plastic = s.has("plastic")
        filmSpread?.isHidden = !(plastic && wet)
        filmRoll?.isHidden = !(plastic && !wet)
        woodSpread?.isHidden = !(s.res("wetwood") >= 1 && !s.isNight && !wet) || collapsed
        let fuel = Int(max(0, min(4, s.res("fuel").rounded(.up))))
        for (i, n) in fuelStack.enumerated() { n.isHidden = i >= fuel }
        let pigNPC = s.people.contains { $0.animal && $0.weight > 45 }
        var pigUp = s.has("pig_roof") && !pigNPC
        if let tr = s.fired["to_roof"], let ph = s.fired["r_pig_hungry"], ph > tr { pigUp = false }
        roofPig?.isHidden = !pigUp || collapsed

        // floating things tied to events
        pigNear?.isHidden = !s.now("r_dead_pig")
        pigFar?.isHidden = s.round < 2 || s.now("r_dead_pig")
        if s.now("r_debris") {
            beam?.position = SCNVector3(5.95, 0, 0.5)
            beam?.eulerAngles.y = 1.35
        } else {
            beam?.position = SCNVector3(30, 0, 9)
            beam?.eulerAngles.y = 0.15
        }
        let neighborGone = s.happened("neighbor_fate") || lv > 4.9
        let kidSaved = s.people.contains { $0.id == "xiaojun" }
        zhouGrandpa?.isHidden = neighborGone || kidSaved || s.isNight
        zhouGrandpaSit?.isHidden = neighborGone || !(kidSaved || s.isNight)
        zhouKid?.isHidden = neighborGone || kidSaved
        strawHat?.isHidden = !s.happened("neighbor_fate")

        applyBoats(s, lv: lv, collapsed: collapsed, night: night)

        // night lights
        let dark = darkness
        lampLight?.isHidden = !(dark > 0.5 && someone && !collapsed)
        lampMat?.emission.contents = (dark > 0.5 && someone && !collapsed) ? SK.rgb(0xFFC77A) : NSColor.black
        lampMat?.emission.intensity = 1.6
        torch?.isHidden = !(night && someone && !collapsed && rain < 1.5)
        torch?.position = SCNVector3(1.4, (onRoof ? roofY : floor2) + 1.3, onRoof ? 3.7 : 5.0)
        torch?.look(at: SCNVector3(7, lv, 17))
        dikeLights?.isHidden = dark < 0.55
        farFires?.isHidden = dark < 0.6
        glassMat?.emission.contents = (night && !onRoof && someone) ? SK.rgb(0x3A2410) : NSColor.black

        // people
        let boatNear = s.now("boat") || s.now("boat_return") || s.now("r_full_boat") || s.now("r_boat_far") || s.now("dehou_alone") || (s.has("spotted") && !s.has("rescued")) || s.now("r_airdrop")
        showPeople(s, spots: peopleSpots(s, onRoof: onRoof, collapsed: collapsed, lv: lv, wave: boatNear && !s.isNight))
        showBodies(s.dead, spots: bodySpots(collapsed: collapsed))
    }

    private func layRope(_ n: SCNNode, _ a: SCNVector3, _ b: SCNVector3) {
        let d = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
        let len = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
        n.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        n.scale = SCNVector3(1, max(0.01, len), 1)
        // rotate the cylinder's y axis onto d
        let up = SCNVector3(0, 1, 0)
        let axis = SCNVector3(up.y * d.z - up.z * d.y, up.z * d.x - up.x * d.z, up.x * d.y - up.y * d.x)
        let al = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        if al > 1e-5 && len > 1e-5 {
            let ang = acos(max(-1, min(1, d.y / len)))
            n.rotation = SCNVector4(axis.x / al, axis.y / al, axis.z / al, ang)
        }
    }

    /// Yaw that points a boat (bow = local +x) from (x0, z0) toward (x1, z1).
    private func heading(_ x0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ z1: CGFloat) -> CGFloat { atan2(-(z1 - z0), x1 - x0) }

    private func applyBoats(_ s: SceneState, lv: CGFloat, collapsed: Bool, night: Bool) {
        func place(_ i: Int, _ x: CGFloat, _ z: CGFloat, heading: CGFloat, crowd: Int, moving: Bool) {
            let b = boats[i]
            b.isHidden = false
            b.position = SCNVector3(x, 0, z)
            b.eulerAngles.y = heading
            for (k, p) in boatCrowd[i].enumerated() { p.isHidden = k >= crowd }
            boatWakes[i].isHidden = !moving
        }
        for b in boats { b.isHidden = true }
        let seats = Int(max(0, min(5, s.v("seats", 0))))
        let atHouse = !collapsed && (s.now("boat") || s.now("boat_return") || s.now("dehou_alone") || (s.ended && s.has("rescued") && !s.people.isEmpty))
        let leaving = !atHouse && !collapsed && s.ended && s.people.isEmpty && (s.has("rescued") || s.happened("boat_return"))
        let approaching = !atHouse && !leaving && s.has("spotted") && !s.has("rescued") && !s.ended
        let convoy = s.ended && (s.has("soldier_success") || s.has("swim_success"))
        var used = 0
        if atHouse {
            let crowd = s.now("boat") ? min(12, 9 + seats) : (s.now("dehou_alone") ? 2 : (convoy ? 1 : 3))
            place(0, 4.6, 7.0, heading: 0.04, crowd: crowd, moving: false)
            used = 1
        } else if leaving {
            place(0, -10, -36, heading: heading(-4, -10, -40, -120), crowd: 10, moving: true)
            used = 1
        } else if approaching {
            place(0, 6, -52, heading: heading(6, -52, 2, 0), crowd: 5, moving: true)
            used = 1
        } else if s.now("r_full_boat") {
            place(0, 1, 13.5, heading: .pi + 0.06, crowd: 12, moving: true)
            used = 1
        } else if s.now("r_boat_far") {
            place(0, -150, -150, heading: 0.1, crowd: 8, moving: true)
            used = 1
        }
        boatLight?.isHidden = !(used == 1 && night)
        if used == 1 {
            let moored = atHouse
            boatLight?.light?.intensity = moored ? 260 : 1600
            boatLight?.look(at: moored ? SCNVector3(-6, lv, 14) : SCNVector3(0, roofY, 0))
        }
        if convoy {
            place(1, 17, -3, heading: heading(17, -3, 6, 5), crowd: 0, moving: true)
            place(2, 9, -26, heading: heading(9, -26, 4, -6), crowd: 0, moving: true)
        } else if !s.ended {
            let search = s.v("search", 10)
            if search >= 35 { place(1, -10, -140, heading: .pi + 0.1, crowd: 6, moving: true) }
            if search >= 65 { place(2, 25, -115, heading: 0.1, crowd: 8, moving: true) }
        }
        _ = used

        // the fisherman's boat moored at the window, until he has ferried people off
        let wanBoat = !collapsed && (s.now("r_fisherman") || s.now("wan_go") || (s.happened("r_fisherman") && !s.has("wan_ferried") && !s.ended))
        sampan?.isHidden = !wanBoat
        sampan?.position = SCNVector3(-3.7, 0, 6.05)
        sampan?.eulerAngles.y = 0.05
        fisherman?.isHidden = s.people.contains { $0.id == "wan" }

        heli?.isHidden = !s.now("r_airdrop")
        let swimming = !s.ended && (s.fired["swim_pick"] == s.round || s.fired["soldier_go"] == s.round)
        swimmer?.isHidden = !swimming
        swimBarrel?.isHidden = s.fired["swim_pick"] != s.round
        swimVest?.isHidden = s.fired["soldier_go"] != s.round
    }

    private func bodySpots(collapsed: Bool) -> [Spot] {
        let R = roofY, top: CGFloat = 9.04
        return [Spot(-3.7, R, -3.3, facing: .pi / 2), Spot(-1.3, R, -3.3, facing: .pi / 2),
                Spot(3.35, top, -3.15, facing: .pi / 2), Spot(3.35, top, -2.4, facing: .pi / 2), Spot(3.35, top, -1.65, facing: .pi / 2)]
            .map { sp in
                guard collapsed else { return sp }
                let p = house.convertPosition(sp.pos, to: nil)
                return Spot(p.x, p.y, p.z, facing: sp.facing)
            }
    }

    /// Where everyone is: the second-floor balcony while the floor is dry, otherwise the roof;
    /// grandma on her bamboo bed; the hurt lying down; animals by the stair head; at night
    /// around the brazier; after the collapse on the raft and on what is left of the roof.
    private func peopleSpots(_ s: SceneState, onRoof: Bool, collapsed: Bool, lv: CGFloat, wave: Bool) -> [Spot] {
        let R = roofY, F = floor2
        let night = s.isNight
        let roofDay: [(CGFloat, CGFloat, CGFloat)] = [(-1.5, 3.35, 0.15), (0.35, 3.3, -0.1), (2.2, 3.4, -0.35), (-3.4, 3.2, 0.3), (4.15, 2.4, 1.3),
                                                      (3.3, 0.35, 1.0), (-0.5, 1.9, 0.05), (-4.35, 1.6, -1.4), (1.2, -0.25, 2.6), (-2.1, -0.4, 0.8),
                                                      (-0.4, -3.1, 3.0), (-2.6, -3.0, 2.8), (0.9, 1.2, 0.3), (-1.4, 0.4, 0.5)]
        let balcony: [(CGFloat, CGFloat, CGFloat)] = [(0.6, 4.95, 0.0), (1.45, 4.72, -0.25)]
        let lying: [(CGFloat, CGFloat)] = [(-2.3, -2.0), (-2.3, -0.7), (1.0, 0.95), (-0.9, 2.5), (2.5, 2.5), (-3.3, 2.7), (0.6, -2.7)]
        let humans = s.people.filter { !$0.animal }
        let roofPeople = humans.filter { !$0.injured && $0.id != "nainai" }.count - (onRoof ? 0 : balcony.count)
        let ring = Spot.ring(SCNVector3(brazier.x, R, brazier.z), radius: max(1.3, CGFloat(max(1, roofPeople)) * 0.24), count: max(1, roofPeople), start: 0.3)
        var out: [Spot] = []
        var r = 0, b = 0, lie = 0, an = 0
        if collapsed {
            // on the raft (if there is one), the rest clinging to the tilted stair head
            let raftUp = s.project("raft") >= 0.999 && !s.has("raft_gone")
            var k = 0
            for p in s.people {
                if raftUp && k < 4 {
                    let x = -7.5 + CGFloat(k % 2) * 0.9 - 0.45, z = 9.5 + CGFloat(k / 2) * 0.5 - 0.25
                    out.append(Spot(x, lv + 0.37, z, facing: 0.3, pose: p.animal ? nil : .huddled))
                } else {
                    let local = SCNVector3(2.6 + CGFloat(k % 3) * 0.8, 9.04, -2.9 + CGFloat(k / 3) * 0.8)
                    let w = house.convertPosition(local, to: nil)
                    out.append(Spot(w.x, w.y, w.z, facing: 0.4, pose: p.animal ? nil : .huddled))
                }
                k += 1
            }
            return out
        }
        if lv > roofY - 0.3 {
            // the roof itself is under water: everyone crowds onto the stair head (9 m)
            let top: CGFloat = 9.04
            return s.people.enumerated().map { i, p in
                let gx = CGFloat(i % 3), gz = CGFloat((i / 3) % 4)
                return Spot(2.45 + gx * 0.95, top, -3.5 + gz * 0.85, facing: 0.3, pose: p.injured ? nil : .huddled)
            }
        }
        for p in s.people {
            if p.animal {
                let big = p.weight > 45
                if big { out.append(Spot(0.75, R, -3.3, facing: .pi / 2)) }
                else if onRoof { out.append(Spot(2.4 + CGFloat(an) * 0.7, R, 0.55, facing: 2.2)) }
                else { out.append(Spot(1.05 + CGFloat(an) * 0.5, F, 4.3, facing: 1.2)) }
                an += 1
                continue
            }
            if p.id == "nainai" {
                // paralysed: on her bamboo bed
                out.append(onRoof ? Spot(-3.9, R + 0.45, -0.03, facing: .pi / 2, pose: .lying) : Spot(-1.02, F + 0.45, 4.72, facing: 0, pose: .lying))
                continue
            }
            if p.injured {
                let l = lying[lie % lying.count]
                out.append(Spot(l.0, R, l.1, facing: 0))
                lie += 1
                continue
            }
            if !onRoof && b < balcony.count {
                let q = balcony[b]
                out.append(Spot(q.0, F, q.1, facing: q.2, pose: wave ? .waving : nil))
                b += 1
                continue
            }
            if night {
                out.append(ring[min(r, ring.count - 1)])
            } else {
                let q = roofDay[r % roofDay.count]
                out.append(Spot(q.0, R, q.1, facing: q.2, pose: wave && r < 4 ? .waving : nil))
            }
            r += 1
        }
        return out
    }
}

// MARK: - Flood-scene helpers

fileprivate typealias V3 = SIMD3<Float>

/// sRGB hex → linear RGB (vertex colours are used as linear values).
fileprivate func floodLin(_ hex: UInt32, _ k: Float = 1) -> V3 {
    func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return V3(f(Float((hex >> 16) & 0xFF) / 255), f(Float((hex >> 8) & 0xFF) / 255), f(Float(hex & 0xFF) / 255)) * k
}

/// Rotate roll (z) → pitch (x) → yaw (y), right-handed like SceneKit's euler angles.
fileprivate func floodRot(_ p: V3, yaw: Float, pitch: Float = 0, roll: Float = 0) -> V3 {
    var q = p
    if roll != 0 { let c = cos(roll), s = sin(roll); q = V3(q.x * c - q.y * s, q.x * s + q.y * c, q.z) }
    if pitch != 0 { let c = cos(pitch), s = sin(pitch); q = V3(q.x, q.y * c - q.z * s, q.y * s + q.z * c) }
    if yaw != 0 { let c = cos(yaw), s = sin(yaw); q = V3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c) }
    return q
}

fileprivate func floodLen(_ v: V3) -> Float { sqrt(v.x * v.x + v.y * v.y + v.z * v.z) }
fileprivate func floodCross(_ a: V3, _ b: V3) -> V3 { V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }

fileprivate struct FloodRng {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
    mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float(s >> 40) / Float(1 << 24) }
    mutating func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
    mutating func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(next() * Float(a.count)))] }
}

fileprivate enum FloodFace {
    case px, nx, pz, nz
    var normal: V3 {
        switch self {
        case .px: return V3(1, 0, 0)
        case .nx: return V3(-1, 0, 0)
        case .pz: return V3(0, 0, 1)
        case .nz: return V3(0, 0, -1)
        }
    }
}

/// Merged triangle mesh with vertex colours and metre UVs: many small parts, one node.
fileprivate struct FloodMesh {
    var pts: [V3] = []
    var cols: [V3] = []
    var uvs: [CGPoint] = []
    var idx: [UInt32] = []

    func node(_ m: SCNMaterial, shadow: Bool = true) -> SCNNode {
        guard !idx.isEmpty else { return SCNNode() }
        let g = SK.mesh(pts, idx, colors: cols, uvs: uvs)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.castsShadow = shadow
        return n
    }

    private static func uv(_ u: Float, _ v: Float) -> CGPoint { CGPoint(x: CGFloat(u), y: CGFloat(-v)) }

    mutating func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V3, uv: [CGPoint]? = nil) {
        let base = UInt32(pts.count)
        pts += [a, b, c, d]
        cols += [col, col, col, col]
        uvs += uv ?? [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    mutating func tri(_ a: V3, _ b: V3, _ c: V3, _ col: V3) {
        let base = UInt32(pts.count)
        pts += [a, b, c]
        cols += [col, col, col]
        uvs += [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0)]
        idx += [base, base + 1, base + 2]
    }

    /// Axis-aligned wall rectangle facing `f` at distance `d`; u runs along the wall.
    mutating func wall(_ f: FloodFace, at d: Float, u0: Float, u1: Float, y0: Float, y1: Float, _ col: V3) {
        let U = FloodMesh.uv
        switch f {
        case .pz: quad(V3(u0, y0, d), V3(u1, y0, d), V3(u1, y1, d), V3(u0, y1, d), col, uv: [U(u0, y0), U(u1, y0), U(u1, y1), U(u0, y1)])
        case .nz: quad(V3(u1, y0, d), V3(u0, y0, d), V3(u0, y1, d), V3(u1, y1, d), col, uv: [U(-u1, y0), U(-u0, y0), U(-u0, y1), U(-u1, y1)])
        case .px: quad(V3(d, y0, u1), V3(d, y0, u0), V3(d, y1, u0), V3(d, y1, u1), col, uv: [U(-u1, y0), U(-u0, y0), U(-u0, y1), U(-u1, y1)])
        case .nx: quad(V3(d, y0, u0), V3(d, y0, u1), V3(d, y1, u1), V3(d, y1, u0), col, uv: [U(u0, y0), U(u1, y0), U(u1, y1), U(u0, y1)])
        }
    }

    /// Flat-shaded box, half extents `h`, rotated roll → pitch → yaw about its centre.
    mutating func box(_ c: V3, _ h: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, _ col: V3, top: V3? = nil) {
        func P(_ sx: Float, _ sy: Float, _ sz: Float) -> V3 { c + floodRot(V3(sx * h.x, sy * h.y, sz * h.z), yaw: yaw, pitch: pitch, roll: roll) }
        let U = FloodMesh.uv
        let x = h.x, y = h.y, z = h.z
        quad(P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1), col, uv: [U(z, -y), U(z, y), U(-z, y), U(-z, -y)])
        quad(P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1), col, uv: [U(-z, -y), U(z, -y), U(z, y), U(-z, y)])
        quad(P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), top ?? col, uv: [U(-x, -z), U(-x, z), U(x, z), U(x, -z)])
        quad(P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1), col, uv: [U(-x, -z), U(x, -z), U(x, z), U(-x, z)])
        quad(P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1), col, uv: [U(-x, -y), U(x, -y), U(x, y), U(-x, y)])
        quad(P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), col, uv: [U(x, -y), U(x, y), U(-x, y), U(-x, -y)])
    }

    /// Tapered cylinder from `a` to `b` (smooth sides, optional cap at `b`).
    mutating func tube(_ a: V3, _ b: V3, _ r0: Float, _ r1: Float, _ col: V3, segs: Int = 6, top: V3? = nil, cap: Bool = false) {
        let axis = b - a
        let len = floodLen(axis)
        guard len > 1e-4 else { return }
        let w = axis / len
        let up: V3 = abs(w.y) < 0.95 ? V3(0, 1, 0) : V3(1, 0, 0)
        var u = floodCross(up, w)
        u /= floodLen(u)
        let v = floodCross(w, u)
        let base = UInt32(pts.count)
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            let d = u * cos(t) + v * sin(t)
            pts.append(a + d * r0); cols.append(col); uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs)), y: 0))
            pts.append(b + d * r1); cols.append(top ?? col); uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs)), y: CGFloat(-len)))
        }
        let S = UInt32(segs)
        for j in 0..<S {
            let p0 = base + j * 2, p1 = p0 + 1
            let q0 = base + ((j + 1) % S) * 2, q1 = q0 + 1
            idx += [p0, q0, p1, q0, q1, p1]
        }
        if cap {
            let c0 = UInt32(pts.count)
            pts.append(b); cols.append(top ?? col); uvs.append(.zero)
            for j in 0..<S { idx += [c0, base + j * 2 + 1, base + ((j + 1) % S) * 2 + 1] }
            let c1 = UInt32(pts.count)
            pts.append(a); cols.append(col); uvs.append(.zero)
            for j in 0..<S { idx += [c1, base + ((j + 1) % S) * 2, base + j * 2] }
        }
    }

    /// Lumpy ellipsoid (tree crowns, bodies): darker underneath, noise-varied colour.
    mutating func blob(_ c: V3, _ r: V3, _ col: V3, _ nz: SK.Noise, seed: Float, jitter: Float = 0.22, rings: Int = 6, segs: Int = 9, under: Float = 0.5, vary: Float = 0.25) {
        let base = UInt32(pts.count)
        for i in 0...rings {
            let v = Float(i) / Float(rings)
            let phi = v * .pi
            for j in 0..<segs {
                let th = Float(j) / Float(segs) * 2 * .pi
                let d = V3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
                let n = nz.value(d.x * 1.7 + seed, d.z * 1.7 + d.y * 1.2 + seed * 0.37)
                let k = 1 + jitter * (2 * n - 1)
                pts.append(c + V3(d.x * r.x, d.y * r.y, d.z * r.z) * k)
                let shade = under + (1 - under) * (0.5 + 0.5 * d.y)
                cols.append(col * shade * (1 - vary * 0.5 + vary * n))
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs) * 3), y: CGFloat(v * 2)))
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

    /// Surface of revolution around a vertical axis at `c`: profile = (height, radius).
    mutating func lathe(_ c: V3, _ profile: [(Float, Float)], segs: Int, _ col: V3) {
        let base = UInt32(pts.count)
        for (h, r) in profile {
            for j in 0..<segs {
                let t = Float(j) / Float(segs) * 2 * .pi
                pts.append(c + V3(cos(t) * r, h, sin(t) * r))
                cols.append(col)
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segs)), y: CGFloat(-h)))
            }
        }
        let S = UInt32(segs)
        for i in 0..<UInt32(profile.count - 1) {
            for j in 0..<S {
                let a = base + i * S + j, b = base + i * S + (j + 1) % S
                let c2 = a + S, d = b + S
                idx += [a, c2, b, b, c2, d]
            }
        }
    }

    /// Flat irregular patch (straw mat, foam, scum) lying in a horizontal plane.
    mutating func patch(_ c: V3, _ radius: Float, _ col: V3, _ nz: SK.Noise, seed: Float, aspect: Float = 1, yaw: Float = 0, segs: Int = 10, rough: Float = 0.35) {
        let base = UInt32(pts.count)
        pts.append(c); cols.append(col); uvs.append(CGPoint(x: 0.5, y: 0.5))
        for j in 0..<segs {
            let t = Float(j) / Float(segs) * 2 * .pi
            let n = nz.value(cos(t) * 1.3 + seed, sin(t) * 1.3 + seed * 0.7)
            let rr = radius * (1 - rough + 2 * rough * n)
            pts.append(c + floodRot(V3(cos(t) * rr, 0, sin(t) * rr * aspect), yaw: yaw))
            cols.append(col * 0.92)
            uvs.append(CGPoint(x: CGFloat(0.5 + 0.5 * cos(t)), y: CGFloat(0.5 + 0.5 * sin(t))))
        }
        let S = UInt32(segs)
        for j in 0..<S { idx += [base, base + 1 + (j + 1) % S, base + 1 + j] }
    }

    /// Pitched roof with gables and fascia; `c` is the centre at eave height, ridge along local x.
    mutating func gable(_ c: V3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ col: V3, gableCol: V3, ridgeCol: V3? = nil) {
        roofSlopes(c, halfL: halfL, halfW: halfW, rise: rise, over: over, yaw: yaw, col, ridge: ridgeCol)
        roofEnds(c, halfL: halfL, halfW: halfW, rise: rise, over: over, yaw: yaw, gableCol, fascia: col * 0.55)
    }

    /// The two slopes of a pitched roof (metre UVs: u along the ridge, v down the slope) and its ridge.
    mutating func roofSlopes(_ c: V3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ col: V3, ridge: V3? = nil) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> V3 { c + floodRot(V3(x, y, z), yaw: yaw) }
        let L = halfL + over, W = halfW + over
        let drop = over * rise / max(0.1, halfW)
        let sl = sqrt(W * W + (rise + drop) * (rise + drop))
        let U = FloodMesh.uv
        quad(P(-L, -drop, W), P(L, -drop, W), P(L, rise, 0), P(-L, rise, 0), col, uv: [U(-L, 0), U(L, 0), U(L, sl), U(-L, sl)])
        quad(P(L, -drop, -W), P(-L, -drop, -W), P(-L, rise, 0), P(L, rise, 0), col * 0.72, uv: [U(L, 0), U(-L, 0), U(-L, sl), U(L, sl)])
        if let rc = ridge { box(P(0, rise + 0.05, 0), V3(L, 0.08, 0.13), yaw: yaw, rc) }
    }

    /// Gable-end triangles and the fascia boards under the eaves.
    mutating func roofEnds(_ c: V3, halfL: Float, halfW: Float, rise: Float, over: Float, yaw: Float, _ gableCol: V3, fascia: V3) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> V3 { c + floodRot(V3(x, y, z), yaw: yaw) }
        let L = halfL + over, W = halfW + over
        let drop = over * rise / max(0.1, halfW)
        tri(P(halfL, 0, -halfW), P(halfL, rise, 0), P(halfL, 0, halfW), gableCol)
        tri(P(-halfL, 0, halfW), P(-halfL, rise, 0), P(-halfL, 0, -halfW), gableCol)
        quad(P(-L, -drop - 0.12, W), P(L, -drop - 0.12, W), P(L, -drop, W), P(-L, -drop, W), fascia)
        quad(P(L, -drop - 0.12, -W), P(-L, -drop - 0.12, -W), P(-L, -drop, -W), P(L, -drop, -W), fascia)
    }

    /// A grid sheet (flags, tarps, film) given by a position function over (u, v) ∈ [0, 1]².
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

/// Small procedural textures for the flood scene (cheap: no fractal noise per pixel beyond a few octaves).
fileprivate enum FloodTex {
    private static var cache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func srgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * max(0, min(1, t)) }

    static func hash(_ a: Int, _ b: Int, _ s: Int) -> Float {
        var h = UInt64(bitPattern: Int64((a &* 73856093) ^ (b &* 19349663) ^ (s &* 83492791)))
        h = (h ^ (h >> 33)) &* 0xff51afd7ed558ccd
        h = (h ^ (h >> 33)) &* 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    /// Tileable value noise (the lattice wraps every px × py cells).
    static func tnoise(_ x: Float, _ y: Float, _ px: Int, _ py: Int, _ seed: Int) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        func h(_ a: Int, _ b: Int) -> Float { hash(((a % px) + px) % px, ((b % py) + py) % py, seed) }
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
    }

    static func tfbm(_ x: Float, _ y: Float, _ px: Int, _ py: Int, _ seed: Int, _ oct: Int = 3) -> Float {
        var s: Float = 0, a: Float = 0.5, n: Float = 0, f: Float = 1, m = 1
        for o in 0..<oct {
            s += a * tnoise(x * f, y * f, px * m, py * m, seed + o * 17)
            n += a
            a *= 0.5
            f *= 2
            m *= 2
        }
        return s / n
    }

    static func image(_ key: String, _ w: Int, _ h: Int, _ f: (Int, Int) -> SIMD4<Float>) -> NSImage {
        cacheLock.lock()
        let hit = cache[key]
        cacheLock.unlock()
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
        cacheLock.lock()
        cache[key] = img
        cacheLock.unlock()
        return img
    }

    static func material(_ img: NSImage, normal: NSImage? = nil, roughness: CGFloat, tile: CGFloat) -> SCNMaterial {
        let m = SK.mat(.white, roughness: roughness)
        m.diffuse.contents = img
        var props: [SCNMaterialProperty] = [m.diffuse]
        if let normal {
            m.normal.contents = normal
            m.normal.intensity = 0.7
            props.append(m.normal)
        }
        for p in props {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
            p.contentsTransform = SCNMatrix4MakeScale(1 / tile, 1 / tile, 1)
        }
        return m
    }

    /// Red brick in stretcher bond, 1 m × 1 m (16 courses).
    static func brick() -> NSImage {
        image("brick", 256, 256) { x, y in
            let row = y / 16
            let xx = x + (row % 2) * 32
            if y % 16 < 2 || xx % 64 < 2 { return SIMD4(srgb(0xA39B8C) * (0.92 + 0.08 * hash(x, y, 3)), 1) }
            let col = xx / 64
            var c = lerp(srgb(0x974E34), srgb(0xB4694A), hash(col, row, 1))
            let k = hash(col, row, 2)
            if k < 0.12 { c = srgb(0x6E3A2A) } else if k > 0.93 { c = srgb(0xC0835E) }
            return SIMD4(c * (0.9 + 0.14 * hash(x, y, 5)), 1)
        }
    }

    static func brickNormal() -> NSImage {
        image("brickN", 256, 256) { x, y in
            func m(_ x: Int, _ y: Int) -> Float {
                let xx = (x + 256) % 256, yy = (y + 256) % 256
                let x2 = xx + ((yy / 16) % 2) * 32
                return (yy % 16 < 2 || x2 % 64 < 2) ? 0 : 1
            }
            let dx = (m(x + 1, y) - m(x - 1, y)) * 0.9, dy = (m(x, y + 1) - m(x, y - 1)) * 0.9
            let l = sqrt(dx * dx + dy * dy + 1)
            return SIMD4(-dx / l * 0.5 + 0.5, -dy / l * 0.5 + 0.5, 1 / l * 0.5 + 0.5, 1)
        }
    }

    /// White glazed wall tiles, 12.5 cm.
    static func tile() -> NSImage {
        image("tile", 256, 256) { x, y in
            if x % 32 < 2 || y % 32 < 2 { return SIMD4(srgb(0xA9A497), 1) }
            let v = hash(x / 32, y / 32, 7)
            return SIMD4(lerp(srgb(0xE2DED2), srgb(0xD3CEBF), v) * (0.98 + 0.03 * hash(x, y, 9)), 1)
        }
    }

    static func concrete() -> NSImage {
        image("concrete", 128, 128) { x, y in
            let n = tfbm(Float(x) / 16, Float(y) / 16, 8, 8, 51, 3)
            var c = srgb(0xA6A297) * (0.8 + 0.36 * n)
            if hash(x, y, 52) > 0.975 { c *= 0.78 }
            return SIMD4(c, 1)
        }
    }

    /// Muddy flood water: silt clouds in two browns.
    static func water() -> NSImage {
        image("water", 128, 128) { x, y in
            let n = tfbm(Float(x) / 32, Float(y) / 32, 4, 4, 21, 3)
            return SIMD4(lerp(srgb(0x4E3C24), srgb(0x6E5634), SK.smoothstep(0.3, 0.72, n)), 1)
        }
    }

    /// Foam streaks (alpha), stretched along the current by the material transform.
    static func streaks() -> NSImage {
        image("streaks", 256, 256) { x, y in
            let n = tfbm(Float(x) / 32, Float(y) / 32, 8, 8, 31, 3)
            var a = SK.smoothstep(0.64, 0.82, n) * 0.42
            if hash(x, y, 41) > 0.992 { a = max(a, 0.35) }
            return SIMD4(srgb(0xD8CDB2), a)
        }
    }

    /// The red satin quilt cover (被面): peonies, leaves and a gold border.
    static func quilt() -> NSImage {
        let flowers: [(Float, Float, Float)] = [(0.5, 0.5, 0.2), (0.2, 0.22, 0.12), (0.8, 0.22, 0.12), (0.2, 0.78, 0.12), (0.8, 0.78, 0.12),
                                                (0.5, 0.13, 0.07), (0.5, 0.87, 0.07), (0.12, 0.5, 0.07), (0.88, 0.5, 0.07)]
        return image("quilt", 128, 128) { x, y in
            let u = Float(x) / 128, v = Float(y) / 128
            var c = srgb(0xB0202A) * (0.9 + 0.15 * tnoise(u * 16, v * 16, 16, 16, 3))
            let edge = min(min(u, 1 - u), min(v, 1 - v))
            if edge < 0.035 { c = srgb(0xD8A640) } else if edge < 0.05 { c = srgb(0x7A1218) }
            for (fx, fy, fr) in flowers {
                let dx = u - fx, dy = v - fy
                let d = sqrt(dx * dx + dy * dy) / fr
                guard d < 1.25 else { continue }
                let a = atan2(dy, dx)
                let petal = 0.75 + 0.25 * cos(a * 6)
                if d < petal {
                    c = d < 0.22 ? srgb(0xE8C04A) : lerp(srgb(0xF2808E), srgb(0xC22E3C), d / petal)
                } else if d < 1.25 && cos(a * 3 + 1) > 0.55 {
                    c = srgb(0x2E7A44)
                }
            }
            return SIMD4(c, 1)
        }
    }

    /// Rows of curved clay tiles: u across the rows (0.25 m), v down the slope (0.25 m courses).
    static func roofTiles() -> NSImage {
        image("rooftiles", 128, 128) { x, y in
            let fx = Float(x % 32) / 32, fy = Float(y % 32) / 32
            var k = 0.72 + 0.28 * sin(fx * .pi)
            if fy > 0.86 { k *= 0.6 }
            k *= 0.9 + 0.16 * hash(x / 32, y / 32, 61)
            return SIMD4(SIMD3(repeating: k), 1)
        }
    }

    static func roofTilesNormal() -> NSImage {
        image("rooftilesN", 128, 128) { x, y in
            let fx = Float(x % 32) / 32, fy = Float(y % 32) / 32
            let dx = -cos(fx * .pi) * 0.7
            let dy: Float = fy > 0.84 && fy < 0.9 ? 0.8 : 0
            let l = sqrt(dx * dx + dy * dy + 1)
            return SIMD4(-dx / l * 0.5 + 0.5, -dy / l * 0.5 + 0.5, 1 / l * 0.5 + 0.5, 1)
        }
    }

    /// Red-white-blue striped tarpaulin (彩条布).
    static func stripes() -> NSImage {
        image("stripes", 56, 4) { x, _ in
            let p = x % 28
            let hex: UInt32 = p < 12 ? 0x2D5DA8 : (p < 15 ? 0xE6E6E0 : (p < 23 ? 0xC23A2E : (p < 25 ? 0xE6E6E0 : 0x3C8F4F)))
            return SIMD4(srgb(hex), 1)
        }
    }

    /// Woodland camouflage for the assault boats.
    static func camo() -> NSImage {
        image("camo", 64, 64) { x, y in
            let u = Float(x) / 16, v = Float(y) / 16
            let n1 = tfbm(u, v, 4, 4, 5, 2), n2 = tfbm(u + 2.3, v + 1.1, 4, 4, 9, 2)
            var c = srgb(0x5D6A3C)
            if n1 > 0.58 { c = srgb(0x343D24) } else if n2 > 0.6 { c = srgb(0x7A6A45) } else if n1 < 0.36 { c = srgb(0x8C8A5E) }
            return SIMD4(c, 1)
        }
    }
}
