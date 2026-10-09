import SceneKit
import AppKit

/// 极夜 — 南极内陆冰盖，雪岭站，6 月 13 日火灾之后的第一个越冬夜。
///
/// 布局（米，原点在废墟和应急舱之间，相机默认在 +z 一侧往 −z 看）：
/// - 主楼废墟在 (−17, 0, −5)：22 × 9 的架空钢架楼，二层楼板塌了一半，只剩焦黑的柱、墙根和梁。
/// - 应急舱在 (6, 0, 4.4)：保温集装箱，暖风机是画面里唯一的暖光源；伤员躺在舱壁和雪砖墙中间。
/// - 天线杆两根 (−6, 0, −15) / (4, 0, −17)，偶极天线按工程进度一点点拉长。
/// - 油料区和风塔在东边 (18, 0, 13)；车库雪堆和雪地车在 (18, 0, −0.5) / (12.6, 0, 1.6)。
/// - 跑道（标志杆、压平的雪面和燃烧罐）从 (24, 16) 斜着退到 (−8, −120) 的黑暗里。
///
/// 状态：s.fireLit（暖风机 = 舱内灯 + 窗光 + 排气口的雪堆）、var.exhaust（排气管积雪）、
/// var.skiway / var.alarm / flag.spotted / flag.plane_coming（跑道燃烧罐和信号火）、
/// project("garage"/"antenna"/"radio")、flag garage_open / snowcat / contact / cores_saved /
/// relief / burzhuika / sat_phone / yang_found、事件 fire_night / overflight / plane / airdrop、dead。
final class PolarnightScene: ScenarioScene {
    private let noise = SK.Noise(seed: 613)

    // MARK: 会被状态改动的部件

    private var panes: [SCNMaterial] = []          // 舱里透出来的暖光（窗、门缝、门口小灯）
    private var embers: [SCNMaterial] = []         // 废墟里的余烬
    private var ruinLight: SK.FlickerLight?
    private var ruinFlame: SCNNode?                // 只有火灾那一晚还看得见明火
    private var workLamp: SCNNode?                 // 废墟边的作业灯（冷白）
    private var antennaWire: SCNNode?              // 偶极天线（按工程进度拉长）
    private var antennaLegs: [SCNNode] = []
    private var beacon: SCNNode?                   // 天线杆顶的红色航空灯
    private var radioGlow: SCNNode?
    private var barrels: [SCNNode] = []            // 跑道边的燃烧罐
    private var stripPieces: [SCNNode] = []
    private var doorPivot: SCNNode?
    private var garageDrift: SCNNode?
    private var catGlow: [SCNMaterial] = []
    private var catLight: SCNLight?
    private var exhaustDrift: SCNNode?
    private var exhaustPipe: SCNNode?
    private var cores: SCNNode?
    private var relief: SCNNode?
    private var bundles: SCNNode?
    private var overflight: SCNNode?
    private var plane: SCNNode?
    private var bonfire: SCNNode?
    private var bonfireLight: SK.FlickerLight?
    private var bonfireFlame: SCNNode?
    private var stove: SCNNode?                    // 柴油桶改的炉子（flag.burzhuika）
    private var stoveGlow: SCNMaterial?
    private var stoveLight: SK.FlickerLight?
    private var yangBody: SCNNode?
    private var rotor: SCNNode?
    private var hutLamp: SCNLight?                 // 暖风机的光（画面里唯一的暖光源）

    required init() {
        super.init()
        skyStyle = .polar
        sunPeak = -14                 // 太阳整个冬天都不升起
        sunAzimuth = 55               // 月亮挂在东北方，从相机的右前方照过来
        exposure = 0.30
        hazeColor = SK.rgb(0x2A3442)
        stormColor = SK.rgb(0x39424E)
        nightColor = SK.rgb(0x090D14)
        clearVisibility = 900
        weatherArea = 130
        weatherCenter = SCNVector3(0, 18, 0)
        cameraTarget = SCNVector3(-4.0, 3.0, 0.5)
        cameraDistance = 31
        cameraYaw = 16
        cameraPitch = 7
        cameraFOV = 47
    }

    // MARK: 冰盖

    /// 冰盖基本是平的：只有风刮出来的雪脊（sastrugi）和极缓的起伏。
    private func height(_ x: Float, _ z: Float) -> Float {
        let r = sqrt(x * x + z * z)
        let camp = SK.smoothstep(16, 74, r)                     // 站区被风扫平了
        var h: Float = (noise.fbm(x / 120, z / 46, octaves: 4) - 0.5) * 1.6 * camp
        h += (noise.fbm(x / 58 + 7, z / 58, octaves: 3) - 0.5) * 0.5
        h += SK.smoothstep(180, 900, r) * 3.0
        return h
    }

    private func g(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(height(Float(x), Float(z))) }

    /// 风吹起来的雪堆。
    private func snowDrift(_ r: Float, seed: UInt64, flatten: Float = 0.34, at p: SCNVector3) -> SCNNode {
        let d = SK.rock(r, snowMat, seed: seed, rings: 10, segments: 16, flatten: flatten)
        d.position = p
        return d
    }

    private let snowMat = SK.mat(SK.rgb(0xDFE6F1), roughness: 0.76)
    private let steel = SK.mat(SK.rgb(0x767C84), roughness: 0.45, metalness: 0.75)
    private let darkSteel = SK.mat(SK.rgb(0x2A2D31), roughness: 0.5, metalness: 0.65)
    private let charred = SK.noiseMat(SK.rgb(0x191A1C), SK.rgb(0x34302C), scale: 5, roughness: 0.62, metalness: 0.4, seed: 41)
    private let charredWood = SK.noiseMat(SK.rgb(0x231F1C), SK.rgb(0x40382F), scale: 7, roughness: 0.95, seed: 55)
    /// 主楼的外墙板：还剩一点蓝漆，其余都烧成了焦壳
    private let clad = SK.noiseMat(SK.rgb(0x24405F), SK.rgb(0x16181C), scale: 4, roughness: 0.75, metalness: 0.15, seed: 61)

    // MARK: 天空（极夜星空 + 低空极光）

    private static var skyCache: [String: NSImage] = [:]

    /// SK.nightSky 的极光带在 36° 仰角上，相机稍微低头就看不见了；极光本来也多半
    /// 贴着地平线。所以这里自己画一张 equirect：满天星 + 一条 2°…17° 的绿色光幕。
    /// 天顶到地平线的底色是从黑到深蓝的渐变，地平线上留一条很淡的冰盖反照。
    private static func polarSky(aurora: Float) -> NSImage {
        let key = "polarnight|\(aurora)"
        if let img = skyCache[key] { return img }
        let w = 3072, h = 1536
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let nz = SK.Noise(seed: 613)
        var s: UInt64 = 20200
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }

        // 极光光幕：每一列有自己的亮度和高度（竖着的帘子），先在一条粗线上算再插值
        let cw = 1024
        var colA = [Float](repeating: 0, count: cw)      // 这一列多亮
        var colH = [Float](repeating: 0, count: cw)      // 这一列多高
        for i in 0..<cw {
            let u = Float(i) / Float(cw)
            let fine = nz.fbm(u * 150, 3.5, octaves: 3)
            let broad = nz.fbm(u * 26 + 11, 1.5, octaves: 3)
            colA[i] = max(0, fine * (0.40 + 1.05 * broad) - 0.14)
            colH[i] = 0.42 + 0.72 * abs(nz.fbm(u * 78 + 4, 7.5, octaves: 3))
        }
        let bandBottom = 0.489, bandHeight = 0.070       // 下缘仰角 2°，帘子最高到 ~18°
        for y in 0..<h {
            let t = Double(y) / Double(h)                // 0 天顶 · 0.5 地平线 · 1 天底
            let glow = max(0, 1 - abs(t - 0.5) * 2.6)    // 地平线附近亮一点（冰盖反照）
            let r0 = 0.011 + 0.024 * glow * glow
            let g0 = 0.015 + 0.030 * glow * glow
            let b0 = 0.036 + 0.054 * glow * glow
            let up = Float((bandBottom - t) / bandHeight)   // 0 在下缘，往上变大
            let inBand = aurora > 0 && up > 0 && up < 1.4
            for x in 0..<w {
                var r = r0, g = g0, b = b0
                if inBand {
                    let fx = Float(x) / Float(w) * Float(cw - 1)
                    let i0 = Int(fx), i1 = min(cw - 1, i0 + 1), tx = fx - Float(i0)
                    let a = colA[i0] * (1 - tx) + colA[i1] * tx
                    let top = colH[i0] * (1 - tx) + colH[i1] * tx
                    if up < top {
                        let v = up / top
                        let k = Double(a) * exp(-Double(v) * 3.0) * (1 - Double(v) * Double(v)) * 1.3 * Double(aurora)
                        r += 0.24 * k + 0.34 * k * Double(v)          // 下缘偏绿、上缘偏红紫
                        g += 0.92 * k
                        b += 0.34 * k + 0.85 * k * Double(v)
                    }
                }
                let i = (y * w + x) * 4
                px[i] = UInt8(min(255, r * 255)); px[i + 1] = UInt8(min(255, g * 255)); px[i + 2] = UInt8(min(255, b * 255))
            }
        }
        // 星星：大部分很暗，少数很亮；靠近地平线的被大气吃掉一些
        for _ in 0..<7000 {
            let x = Int(rnd() * Double(w))
            let y = Int(pow(rnd(), 1.15) * Double(h) * 0.495)
            let haze = Double(y) / (Double(h) * 0.5)
            let m = pow(rnd(), 3)
            let bright = (70 + 185 * m) * (1 - 0.55 * haze)
            let tint = rnd()
            let i = (y * w + x) * 4
            px[i] = UInt8(min(255, bright * (tint < 0.25 ? 1.0 : 0.9)))
            px[i + 1] = UInt8(min(255, bright * 0.95))
            px[i + 2] = UInt8(min(255, bright * (tint > 0.75 ? 1.0 : 0.88) + 12))
        }
        let img = SK.image(from: px, size: w, height: h)
        skyCache[key] = img
        return img
    }

    /// 这个场景所有天气的 `sun` 都是 0，基类把「没有太阳」一律当成厚阴天，
    /// 天空就永远是一块灰渐变——星星和极光全没了。这里只重写天空和月光，
    /// 雾、天气粒子、`darkness`（暖风机的灯靠它）还是走基类。
    override func updateEnvironment(_ s: SceneState) {
        super.updateEnvironment(s)
        let overcast = min(1, max(0, (1 - s.sun) * 1.15 + s.precip * 0.2))
        // 阴天和暴风雪看不见星星（"云压得很低，看不见星星"）；吹雪天没有云，星空还在
        let cloudy = s.weather == "overcast" || s.weather == "blizzard" || s.precip >= 1.8
        let blowing = s.precip >= 0.5
        let bright = s.happened("aurora") || s.weather == "calm" || s.weather == "window"
        let sky: Any? = cloudy ? SK.gradientSky(top: SK.rgb(0x0A0E15), horizon: SK.rgb(0x181E27))
                               : PolarnightScene.polarSky(aurora: bright ? 1.0 : 0.62)
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = 0.25
        scene.fogColor = blowing ? SK.rgb(0x1B222C) : nightColor

        // 月亮：钉在东北方 42°，冷、暗，但足够把雪地和废墟的轮廓拉出来
        let az = sunAzimuth * .pi / 180, el = 42.0 * .pi / 180
        let dir = SCNVector3(CGFloat(sin(az) * cos(el)), CGFloat(sin(el)), CGFloat(cos(az) * cos(el)))
        sunNode.position = SCNVector3(dir.x * 100, dir.y * 100, dir.z * 100)
        sunNode.look(at: SCNVector3Zero)
        sunNode.light?.color = SK.color(0.70, 0.79, 1.0)
        sunNode.light?.intensity = CGFloat(330 * (1 - 0.72 * overcast))
        sunNode.light?.shadowColor = NSColor(white: 0, alpha: 0.5)
        ambientNode.light?.intensity = CGFloat(44 * (1 - 0.55 * overcast))
        ambientNode.light?.color = SK.color(0.54, 0.65, 0.96)
    }

    // MARK: 建场

    override func build(_ s: SceneState) {
        let groundMat = SK.terrainMaterial(flat: SK.rgb(0xEDF2F9), steep: SK.rgb(0xCFD8E6),
                                           from: 0.38, to: 0.62, grain: 0.09, noiseScale: 0.02, roughness: 0.6)
        SK.addGrain(groundMat, scale: 22, strength: 2.0, intensity: 0.22)
        let terrain = SK.terrain(size: 1800, segments: 200, height: height, color: { x, _, z, slope in
            let n = self.noise.fbm(x / 260, z / 260, octaves: 3)
            let k = 0.93 + 0.12 * n - 0.09 * SK.smoothstep(0.2, 0.7, slope)
            return SIMD3(k, k * 0.995, k * 0.99)
        }, material: groundMat, uvRepeat: 120)
        terrain.castsShadow = false
        world.addChildNode(terrain)

        buildStation()
        buildHut()
        buildMasts()
        buildDepot()
        buildGarage()
        buildSkiway()
        buildGuideLine()
        buildYard()
        buildSled()
    }

    // MARK: 主楼废墟

    private func buildStation() {
        let ruin = SCNNode()
        ruin.position = SCNVector3(-17, g(-17, -5), -5)
        world.addChildNode(ruin)

        // 架在钢腿上的楼板：南极的房子都是架空的
        ruin.addChildNode(SK.box(20, 0.55, 9, charred, chamfer: 0.04, at: SCNVector3(0, 0.55, 0)))
        for i in 0..<8 {
            let lx = CGFloat(i % 4) * 6.2 - 9.3
            ruin.addChildNode(SK.cylinder(0.11, 1.0, darkSteel, at: SCNVector3(lx, 0.1, i < 4 ? -4.2 : 4.2)))
        }
        // 楼板底下灌满了吹进去的雪
        for i in 0..<6 {
            ruin.addChildNode(snowDrift(1.6, seed: UInt64(70 + i), flatten: 0.10, at: SCNVector3(CGFloat(i) * 3.6 - 9.0, 0.90, 3.3)))
        }

        // 烧剩的墙：北墙（背对相机）还立着大半，南墙只剩墙根——
        // 于是能一眼看进去，看见塌下来的屋面和烧空的内部。
        let north: [(CGFloat, CGFloat, Bool)] = [(-8.6, 3.0, true), (-5.6, 3.0, false), (-2.6, 3.0, true),
                                                 (0.4, 3.0, false), (3.9, 3.6, false), (7.5, 3.6, false)]
        for (x, w, painted) in north {
            let tall: CGFloat = x < 2 ? 7.2 : 4.6
            ruin.addChildNode(SK.box(w, tall, 0.24, painted ? clad : charred, chamfer: 0.05, at: SCNVector3(x, 0.8 + tall / 2, -4.4)))
        }
        for (z, w, h) in [(-2.2, 4.4, 7.2), (2.4, 4.2, 7.2)] as [(CGFloat, CGFloat, CGFloat)] {
            ruin.addChildNode(SK.box(0.24, h, w, clad, chamfer: 0.05, at: SCNVector3(-9.8, 0.8 + h / 2, z)))
        }
        // 二层的楼板塌了一半，另一头还挂在梁上
        let deck = SK.box(5.6, 0.2, 8.4, charred, chamfer: 0.03, at: SCNVector3(-6.4, 3.9, 0))
        deck.eulerAngles.z = 0.1
        ruin.addChildNode(deck)
        // 烧剩的通风管／烟囱，歪在屋面上
        let stack = SK.cylinder(0.55, 5.0, charred, at: SCNVector3(6.0, 3.6, -3.2))
        stack.eulerAngles.z = 0.13
        ruin.addChildNode(stack)
        // 南墙的残根：越高越早被烧掉
        for (x, h, tilt) in [(-9.0, 2.6, 0.0), (-5.6, 3.4, 0.06), (-1.6, 1.9, -0.04), (4.4, 1.5, 0.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let w = SK.box(2.3, h, 0.2, charred, chamfer: 0.04, at: SCNVector3(x, 0.8 + h / 2, 4.4))
            w.eulerAngles.z = tilt
            ruin.addChildNode(w)
        }
        // 东头（机房和通信室，火就是从这儿起来的）：只剩柱子和一根过梁
        for z in [-4.4, 4.4] as [CGFloat] {
            ruin.addChildNode(SK.box(0.24, 4.2, 0.24, charred, at: SCNVector3(9.6, 2.9, z)))
        }
        ruin.addChildNode(SK.box(0.3, 0.3, 9, charred, at: SCNVector3(9.6, 4.9, 0)))

        // 钢柱：有几根已经歪了，一根倒在外面的雪里
        for x in [-9.8, -5.6, -1.4, 2.8] as [CGFloat] {
            for z in [-4.4, 4.4] as [CGFloat] {
                let c = SK.box(0.3, 7.2, 0.3, charred, chamfer: 0.02, at: SCNVector3(x, 4.4, z))
                c.eulerAngles.z = CGFloat(noise.value(Float(x) * 0.3 + Float(z), 3) - 0.5) * 0.14
                ruin.addChildNode(c)
            }
        }
        let fallen = SK.box(0.26, 6.0, 0.26, charred, at: SCNVector3(-1.0, 0.35, 6.8))
        fallen.eulerAngles = SCNVector3(.pi / 2 - 0.1, 0.7, 0)
        ruin.addChildNode(fallen)

        // 塌下来的屋面：几块大板斜插在废墟里，一块滑到了南边的雪地上
        for (p, e) in [(SCNVector3(-5.6, 3.6, -1.4), SCNVector3(0.62, 0.05, 0.10)),
                       (SCNVector3(-0.6, 1.9, 0.8), SCNVector3(0.24, -0.32, 0.12)),
                       (SCNVector3(6.6, 1.5, 1.6), SCNVector3(0.30, 0.50, -0.18)),
                       (SCNVector3(2.0, 0.55, 6.4), SCNVector3(0.06, 0.22, -0.08))] as [(SCNVector3, SCNVector3)] {
            let p2 = SK.box(6.2, 0.22, 3.4, charred, chamfer: 0.03, at: p)
            p2.eulerAngles = e
            ruin.addChildNode(p2)
        }
        // 剩下的桁架：几根横在墙头上，几根弯在里面
        for i in 0..<6 {
            let t = SK.box(0.16, 0.16, 8.8, charred, at: SCNVector3(CGFloat(i) * 3.4 - 8.6, 7.7 + CGFloat(i % 2) * 0.12, 0))
            t.eulerAngles.z = CGFloat(i % 3) * 0.04 - 0.04
            ruin.addChildNode(t)
        }
        for i in 0..<4 {
            let t = SK.box(0.14, 0.14, 7.0, charred, at: SCNVector3(CGFloat(i) * 2.6 - 4.0, 2.4 + CGFloat(i) * 0.5, CGFloat(i % 2) * 1.6 - 0.8))
            t.eulerAngles = SCNVector3(0.2 * CGFloat(i), 1.1, 0.5)
            ruin.addChildNode(t)
        }

        // 烧空的内部：倒下来的柜子、烧成一团的机柜、2 号发电机
        for (x, z, hh, r) in [(-6.0, -2.0, 1.8, 0.3), (-3.0, -1.0, 1.4, -0.8), (5.0, -2.4, 2.2, 0.4), (7.6, -1.0, 1.6, 1.2)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let b = SK.box(1.1, hh, 0.7, charredWood, chamfer: 0.02, at: SCNVector3(x, 0.8 + hh / 2, z))
            b.eulerAngles = SCNVector3(0, r, 0.12)
            ruin.addChildNode(b)
        }
        let gen = SK.cylinder(0.85, 2.4, charred, at: SCNVector3(6.2, 1.9, 1.4))
        gen.eulerAngles = SCNVector3(0, 0.3, .pi / 2)
        ruin.addChildNode(gen)
        ruin.addChildNode(SK.box(2.6, 0.3, 1.4, darkSteel, at: SCNVector3(6.2, 0.95, 1.4)))
        let cab = SK.box(1.4, 2.0, 0.8, charred, at: SCNVector3(-8.6, 1.6, 5.6))
        cab.eulerAngles = SCNVector3(0.1, -0.4, 0.35)
        ruin.addChildNode(cab)
        // 烧化了的站牌：一块还剩半个字的蓝牌子
        let sign = SK.box(2.6, 0.6, 0.06, SK.mat(SK.rgb(0x2C4A72), roughness: 0.6, metalness: 0.2), at: SCNVector3(-7.4, 5.6, -4.2))
        sign.eulerAngles.z = 0.08
        ruin.addChildNode(sign)

        // 余烬：火灭了，底下还在红
        for i in 0..<7 {
            let m = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF5E14))
            m.emission.intensity = 0.9
            embers.append(m)
            let e = SK.box(0.36 + CGFloat(i % 3) * 0.16, 0.1, 0.3, m, chamfer: 0.02,
                           at: SCNVector3(3.0 + CGFloat(i) * 1.1, 0.95, 1.6 - CGFloat(i % 3) * 1.3))
            e.eulerAngles.y = CGFloat(i) * 0.7
            ruin.addChildNode(e)
        }
        let rl = SK.fireLight(intensity: 90, color: SK.rgb(0xFF6A22), range: 8)
        rl.position = SCNVector3(5.0, 1.6, 0.4)
        ruin.addChildNode(rl)
        ruinLight = rl
        let flame = SCNNode()
        flame.position = SCNVector3(4.6, 1.1, 0.4)
        flame.addParticleSystem(SK.fire(scale: 0.9))
        ruin.addChildNode(flame)
        ruinFlame = flame

        // 雪一直往废墟里灌
        // 楼里灌进来的雪：旧雪，灰扑扑的
        let oldSnow = SK.mat(SK.rgb(0xBFC9D8), roughness: 0.8)
        for i in 0..<4 {
            let d = SK.rock(1.3 + Float(i % 2) * 0.5, oldSnow, seed: UInt64(120 + i), rings: 9, segments: 14, flatten: 0.2)
            d.position = SCNVector3(CGFloat(i) * 5.0 - 8.0, 0.95, 3.2)
            ruin.addChildNode(d)
        }
    }

    // MARK: 应急舱

    private func buildHut() {
        let hut = SCNNode()
        hut.position = SCNVector3(6.0, g(6, 4.4), 4.4)
        world.addChildNode(hut)

        let skin = SK.noiseMat(SK.rgb(0xA8412C), SK.rgb(0x76321F), scale: 6, roughness: 0.72, metalness: 0.15, seed: 3)
        // 滑木 + 箱体（6.1 × 2.5 × 2.5 的保温集装箱）
        for dz in [-1.0, 1.0] as [CGFloat] {
            hut.addChildNode(SK.box(6.3, 0.3, 0.3, darkSteel, at: SCNVector3(0, 0.3, dz)))
        }
        hut.addChildNode(SK.box(6.1, 2.5, 2.5, skin, chamfer: 0.05, at: SCNVector3(0, 1.7, 0)))
        for i in 0..<13 {                                     // 波纹钢板
            hut.addChildNode(SK.box(0.07, 2.3, 0.06, skin, at: SCNVector3(CGFloat(i) * 0.47 - 2.82, 1.7, 1.28)))
        }
        hut.addChildNode(SK.box(6.3, 0.1, 2.7, SK.mat(SK.rgb(0x4A5058), roughness: 0.6, metalness: 0.5), at: SCNVector3(0, 2.98, 0)))
        let cap = snowDrift(2.6, seed: 9, flatten: 0.07, at: SCNVector3(0, 3.02, 0))
        cap.scale = SCNVector3(1.15, 1, 0.52)
        hut.addChildNode(cap)

        // 暖风机的排气管：矮矮地伸在舱外，吹雪会把它埋掉
        let pipe = SK.cylinder(0.09, 0.9, darkSteel, at: SCNVector3(-3.15, 1.15, 0.9))
        hut.addChildNode(pipe)
        hut.addChildNode(SK.cylinder(0.16, 0.12, darkSteel, at: SCNVector3(-3.32, 1.6, 0.9)))
        exhaustPipe = pipe
        let ed = SCNNode()
        hut.addChildNode(ed)
        exhaustDrift = ed

        // 门（−x 端）开着一条缝，暖光就从这儿漏出来
        hut.addChildNode(SK.box(0.12, 1.9, 1.0, SK.mat(SK.rgb(0x0E1013), roughness: 1), at: SCNVector3(-3.06, 1.75, 0)))
        let door = SK.box(0.08, 1.85, 0.94, SK.mat(SK.rgb(0xB8563A), roughness: 0.7, metalness: 0.2), at: SCNVector3(-3.24, 1.75, -0.55))
        door.eulerAngles.y = -0.5
        hut.addChildNode(door)
        let glow = SK.box(0.03, 1.7, 0.5, warmPane(), at: SCNVector3(-3.14, 1.7, 0.3))
        glow.eulerAngles.y = 0.4
        hut.addChildNode(glow)

        // 窗：一面对着相机，一个小圆窗在另一头
        let frame = SK.mat(SK.rgb(0x2C2F33), roughness: 0.5, metalness: 0.5)
        for (px, py) in [(-1.9, 2.1), (2.0, 2.15)] as [(CGFloat, CGFloat)] {
            let big = px < 0
            hut.addChildNode(SK.box(big ? 0.78 : 0.5, big ? 0.6 : 0.46, 0.04, frame, at: SCNVector3(px, py, 1.26)))
            hut.addChildNode(SK.box(big ? 0.7 : 0.44, big ? 0.52 : 0.4, 0.06, warmPane(), at: SCNVector3(px, py, 1.28)))
            hut.addChildNode(SK.box(big ? 0.76 : 0.48, 0.05, 0.03, frame, at: SCNVector3(px, py, 1.25)))
            hut.addChildNode(SK.box(0.05, big ? 0.58 : 0.44, 0.03, frame, at: SCNVector3(px, py, 1.25)))
        }
        // 门口：踏板、一盏小灯、一桶柴油、挡风的雪砖
        hut.addChildNode(SK.box(1.0, 0.16, 1.2, charredWood, at: SCNVector3(-3.7, 0.5, 0)))
        let porch = warmPane()
        hut.addChildNode(SK.sphere(0.09, porch, at: SCNVector3(-3.2, 2.75, 0.35)))
        hut.addChildNode(SK.cylinder(0.3, 0.9, SK.noiseMat(SK.rgb(0x2E4E6E), SK.rgb(0x6B5A48), scale: 5, roughness: 0.7, metalness: 0.4, seed: 12),
                                     at: SCNVector3(-2.4, 0.45, 2.6)))

        // 舱里的暖风机 = 画面里唯一的暖光源（自己拿一盏灯，方便和月光配比例）
        let lamp = SCNLight()
        lamp.type = .omni
        lamp.color = SK.rgb(0xFFC078)
        lamp.intensity = 0
        lamp.attenuationStartDistance = 0.4
        lamp.attenuationEndDistance = 11
        lamp.attenuationFalloffExponent = 2.0
        lamp.castsShadow = false
        let lampNode = SCNNode()
        lampNode.light = lamp
        lampNode.position = SCNVector3(5.7, 1.35, 4.2)
        world.addChildNode(lampNode)
        hutLamp = lamp
        // 电台的指示灯（修好了才亮）
        let rg = SK.mat(.black, roughness: 0.4, emission: SK.rgb(0x3CE0A0))
        rg.emission.intensity = 1.6
        let rgn = SK.node(SCNBox(width: 0.22, height: 0.1, length: 0.04, chamferRadius: 0), rg, at: SCNVector3(1.95, 1.8, 1.3))
        rgn.isHidden = true
        hut.addChildNode(rgn)
        radioGlow = rgn

        // 挡风的雪砖墙：伤员就躺在舱壁和这堵墙中间（只有一层，别把人挡住）
        for i in 0..<6 {
            let stack = (i == 0 || i == 5) ? 1 : 0
            let b = SK.box(1.0, 0.45, 0.36, snowMat, chamfer: 0.03,
                           at: SCNVector3(3.6 + CGFloat(i) * 1.05, 0.24 + CGFloat(stack) * 0.44, 7.5))
            b.eulerAngles.y = CGFloat(noise.value(Float(i) * 2.3, 1.0) - 0.5) * 0.2
            world.addChildNode(b)
        }
        for x in [4.7, 6.4] as [CGFloat] {                     // 伤员身下的垫子
            world.addChildNode(SK.box(1.9, 0.12, 0.85, SK.mat(SK.rgb(0x3B4450), roughness: 0.95), at: SCNVector3(x, g(x, 6.2) + 0.06, 6.2)))
        }
        world.addChildNode(SK.box(0.5, 0.32, 0.34, SK.mat(SK.rgb(0xC0392B), roughness: 0.7, metalness: 0.1), at: SCNVector3(8.9, g(8.9, 6.4) + 0.16, 6.4)))
        // 门口的两道雪墙（windscoop）
        for (x, z, hh) in [(2.2, 3.4, 0.7), (2.2, 5.4, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
            world.addChildNode(SK.box(2.4, hh, 0.5, snowMat, chamfer: 0.06, at: SCNVector3(x, g(x, z) + hh / 2 - 0.1, z)))
        }
    }

    private func warmPane() -> SCNMaterial {
        let m = SK.mat(.black, roughness: 0.5, emission: SK.rgb(0xFFB765))
        m.emission.intensity = 1.5
        panes.append(m)
        return m
    }

    // MARK: 天线杆

    private func buildMasts() {
        let a = SCNVector3(-6, 0, -15), b = SCNVector3(4, 0, -17)
        for (i, p) in [a, b].enumerated() {
            let m = SCNNode()
            m.position = SCNVector3(p.x, g(p.x, p.z), p.z)
            world.addChildNode(m)
            m.addChildNode(SK.cylinder(0.1, 11, steel, at: SCNVector3(0, 5.5, 0)))
            m.addChildNode(SK.box(0.08, 0.08, 2.4, steel, at: SCNVector3(0, 10.2, 0)))
            m.addChildNode(SK.box(2.4, 0.08, 0.08, steel, at: SCNVector3(0, 9.4, 0)))
            for k in 0..<3 {                                   // 三根拉线
                let ang = CGFloat(k) * 2.1 + CGFloat(i)
                let w = SK.cylinder(0.02, 8.2, darkSteel)
                w.position = SCNVector3(sin(ang) * 1.6, 4.2, cos(ang) * 1.6)
                w.eulerAngles = SCNVector3(cos(ang) * 0.36, 0, -sin(ang) * 0.36)
                m.addChildNode(w)
            }
            if i == 0 {                                        // 杆顶的红色航空灯
                let lamp = SK.sphere(0.1, SK.mat(.black, roughness: 0.4, emission: SK.rgb(0xFF2A18)), at: SCNVector3(0, 11.2, 0))
                lamp.runAction(.repeatForever(.sequence([
                    .fadeOpacity(to: 1, duration: 0.08), .wait(duration: 0.5),
                    .fadeOpacity(to: 0.05, duration: 0.08), .wait(duration: 1.6)])))
                lamp.isHidden = true
                m.addChildNode(lamp)
                beacon = lamp
            }
        }
        // 被烧断的旧天线垂在杆子上
        let old = SK.cylinder(0.02, 5.0, darkSteel)
        old.position = SCNVector3(-5.2, 9.6, -15.4)
        old.eulerAngles = SCNVector3(0.2, 0, 1.1)
        world.addChildNode(old)

        // 新的偶极天线：从中间往两根杆子拉，按工程进度一点点变长
        let mid = SCNVector3((a.x + b.x) / 2, 9.6, (a.z + b.z) / 2)
        let holder = SCNNode()
        holder.position = SCNVector3(mid.x, g(mid.x, mid.z) + mid.y, mid.z)
        // 让 holder 的局部 +z 指向 b 杆
        holder.eulerAngles.y = atan2(b.x - a.x, b.z - a.z)
        holder.isHidden = true
        world.addChildNode(holder)
        antennaWire = holder
        let wireMat = SK.mat(SK.rgb(0xAEB6C0), roughness: 0.4, metalness: 0.8)
        for dir in [-1.0, 1.0] as [CGFloat] {
            let leg = SK.cylinder(0.04, 1.0, wireMat)
            leg.eulerAngles.x = .pi / 2                          // 圆柱轴 → 局部 +z
            leg.position = SCNVector3(0, 0, dir * 2.45)
            leg.scale = SCNVector3(1, 4.9, 1)
            holder.addChildNode(leg)
            antennaLegs.append(leg)
        }
        // 馈线：从天线中间垂到地面
        holder.addChildNode(SK.cylinder(0.02, 9.6, darkSteel, at: SCNVector3(0, -4.8, 0)))
    }

    // MARK: 油料区 / 风塔

    private func buildDepot() {
        let depot = SCNNode()
        depot.position = SCNVector3(18, g(18, 13), 13)
        world.addChildNode(depot)
        let drums = [SK.noiseMat(SK.rgb(0x2E4E6E), SK.rgb(0x6B5A48), scale: 5, roughness: 0.7, metalness: 0.45, seed: 12),
                     SK.noiseMat(SK.rgb(0x8A3B24), SK.rgb(0x5C4038), scale: 5, roughness: 0.8, metalness: 0.35, seed: 18),
                     SK.noiseMat(SK.rgb(0xB08A2A), SK.rgb(0x6B5A48), scale: 6, roughness: 0.8, metalness: 0.3, seed: 24)]
        depot.addChildNode(SK.box(5.4, 0.14, 3.4, charredWood, at: SCNVector3(0, 0.1, 0)))
        for i in 0..<9 {
            let x = CGFloat(i % 5) * 1.15 - 2.3, z = CGFloat(i / 5) * 1.35 - 0.7
            let d = SK.cylinder(0.3, 0.9, drums[i % 3], at: SCNVector3(x, 0.6, z))
            if i == 7 {
                d.eulerAngles.z = .pi / 2
                d.position = SCNVector3(1.5, 0.32, 1.9)
            }
            depot.addChildNode(d)
            if i % 4 != 3 {
                depot.addChildNode(SK.sphere(0.3, snowMat, at: SCNVector3(d.position.x, d.position.y + 0.46, d.position.z), segments: 12))
            }
        }
        // 泵房
        depot.addChildNode(SK.box(2.2, 2.1, 2.0, SK.noiseMat(SK.rgb(0x4A5058), SK.rgb(0x2A2E33), scale: 5, roughness: 0.7, metalness: 0.4, seed: 31),
                                  chamfer: 0.04, at: SCNVector3(3.7, 1.05, 0.4)))
        depot.addChildNode(SK.box(0.9, 1.7, 0.1, charredWood, at: SCNVector3(2.62, 0.85, 0.4)))
        // 风塔：一台小风机，风越大转得越快
        let tower = SCNNode()
        tower.position = SCNVector3(6.6, 0, 2.6)
        depot.addChildNode(tower)
        tower.addChildNode(SK.cylinder(0.1, 9.4, steel, at: SCNVector3(0, 4.7, 0)))
        for y in [2.4, 4.8, 7.2] as [CGFloat] {
            tower.addChildNode(SK.box(0.5, 0.05, 0.05, steel, at: SCNVector3(0, y, 0)))
            tower.addChildNode(SK.box(0.05, 0.05, 0.5, steel, at: SCNVector3(0, y, 0)))
        }
        tower.addChildNode(SK.box(0.5, 0.5, 1.7, SK.mat(SK.rgb(0xD8DCE0), roughness: 0.5, metalness: 0.2), at: SCNVector3(0, 9.6, -0.3)))
        let r = SCNNode()
        r.position = SCNVector3(0, 9.6, 0.55)
        for i in 0..<3 {
            let arm = SCNNode()
            arm.eulerAngles.z = CGFloat(i) * 2 * .pi / 3
            arm.addChildNode(SK.box(0.16, 3.2, 0.05, SK.mat(SK.rgb(0xE2E6EA), roughness: 0.5), at: SCNVector3(0, 1.6, 0)))
            r.addChildNode(arm)
        }
        r.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: -2 * .pi, duration: 6)))
        tower.addChildNode(r)
        rotor = r
    }

    // MARK: 车库 / 雪地车

    private func buildGarage() {
        let g0 = SCNNode()
        g0.position = SCNVector3(18.0, g(18.0, -0.5), -0.5)
        world.addChildNode(g0)
        g0.addChildNode(snowDrift(5.0, seed: 61, flatten: 0.34, at: SCNVector3(0, 0, 0)))
        // 半扇被雪埋住的钢门，挖开车库以后会转开
        let pivot = SCNNode()
        pivot.position = SCNVector3(-2.2, 0, 1.45)
        g0.addChildNode(pivot)
        doorPivot = pivot
        pivot.addChildNode(SK.box(4.4, 3.0, 0.16, SK.noiseMat(SK.rgb(0x585E66), SK.rgb(0x2E3238), scale: 4, roughness: 0.6, metalness: 0.5, seed: 44),
                                  chamfer: 0.03, at: SCNVector3(2.2, 1.5, 0)))
        let gd = snowDrift(2.2, seed: 66, flatten: 0.4, at: SCNVector3(0, 0.3, 2.3))
        g0.addChildNode(gd)
        garageDrift = gd
        g0.addChildNode(SK.cylinder(0.03, 1.3, steel, at: SCNVector3(-2.4, 0.65, 2.5)))
        g0.addChildNode(SK.box(0.3, 0.22, 0.06, steel, at: SCNVector3(-2.4, 0.12, 2.6)))

        // 雪地车：停在车库前面，履带已经埋了一半
        let cat = SCNNode()
        cat.position = SCNVector3(12.6, g(12.6, 1.6), 1.6)
        cat.eulerAngles.y = -1.15
        world.addChildNode(cat)
        let hull = SK.noiseMat(SK.rgb(0xC2761F), SK.rgb(0x7A4A18), scale: 5, roughness: 0.75, metalness: 0.3, seed: 77)
        cat.addChildNode(SK.box(4.3, 1.0, 2.2, hull, chamfer: 0.06, at: SCNVector3(0, 1.15, 0)))
        cat.addChildNode(SK.box(1.7, 1.0, 2.0, hull, chamfer: 0.05, at: SCNVector3(-0.5, 2.1, 0)))
        for dz in [-1.15, 1.15] as [CGFloat] {
            cat.addChildNode(SK.box(4.6, 0.6, 0.62, SK.mat(SK.rgb(0x1C1E22), roughness: 0.9), at: SCNVector3(0, 0.3, dz)))
            for i in 0..<4 {
                let wheel = SK.cylinder(0.2, 0.2, darkSteel, at: SCNVector3(CGFloat(i) * 1.15 - 1.7, 0.3, dz))
                wheel.eulerAngles.z = .pi / 2
                cat.addChildNode(wheel)
            }
        }
        // 驾驶室的玻璃和车头大灯：发动起来才亮
        let glass = SK.mat(.black, roughness: 0.25, metalness: 0.3, emission: SK.rgb(0xFFD9A0))
        glass.emission.intensity = 0
        catGlow.append(glass)
        cat.addChildNode(SK.box(1.6, 0.66, 0.06, glass, at: SCNVector3(-0.5, 2.24, 1.02)))
        cat.addChildNode(SK.box(0.06, 0.66, 1.6, glass, at: SCNVector3(0.36, 2.24, 0)))
        let beam = SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xFFF0D0))
        beam.emission.intensity = 0
        catGlow.append(beam)
        for dz in [0.7, -0.7] as [CGFloat] {
            cat.addChildNode(SK.box(0.06, 0.22, 0.28, beam, at: SCNVector3(-2.16, 1.35, dz)))
        }
        let head = SCNLight()
        head.type = .omni
        head.color = SK.rgb(0xFFEFC8)
        head.intensity = 0
        head.attenuationEndDistance = 20
        head.attenuationFalloffExponent = 2
        let hn = SCNNode()
        hn.light = head
        hn.position = SCNVector3(-2.6, 1.4, 0)
        cat.addChildNode(hn)
        catLight = head
        let plow = SK.box(0.16, 1.5, 3.4, SK.mat(SK.rgb(0x9AA0A6), roughness: 0.5, metalness: 0.6), at: SCNVector3(-2.7, 0.85, 0))
        plow.eulerAngles.z = -0.35
        cat.addChildNode(plow)
        for i in 0..<3 {                                          // 埋在车上的雪
            cat.addChildNode(snowDrift(1.5, seed: UInt64(90 + i), flatten: 0.13,
                                       at: SCNVector3(CGFloat(i) * 1.7 - 1.7, 0.5, CGFloat(i % 2) * 2.2 - 1.1)))
        }
    }

    // MARK: 跑道

    private func buildSkiway() {
        // 跑道从营地东南斜着伸到西北的黑暗里——默认机位就能看见那一串标志杆和燃烧罐
        let a = CGPoint(x: 24, y: 16), b = CGPoint(x: -8, y: -120)
        let dx = b.x - a.x, dz = b.y - a.y
        let len = sqrt(dx * dx + dz * dz)
        let yaw = atan2(-dz, dx)                                  // 长方形长边（局部 x）对准跑道
        let stripMat = SK.mat(SK.rgb(0xBFC9D6), roughness: 0.55)
        for i in 0..<16 {
            let t = (CGFloat(i) + 0.5) / 16
            let x = a.x + dx * t, z = a.y + dz * t
            let seg = SK.box(len / 16 + 0.3, 0.05, 12, stripMat, at: SCNVector3(x, g(x, z) + 0.05, z))
            seg.eulerAngles.y = yaw
            seg.isHidden = true
            world.addChildNode(seg)
            stripPieces.append(seg)
        }
        let poleMat = SK.mat(SK.rgb(0xD8DCE0), roughness: 0.6)
        let flagMat = SK.mat(SK.rgb(0xE2621F), roughness: 0.8)
        for i in 0..<14 {
            let t = CGFloat(i) / 13
            let x = a.x + dx * t + 4.6, z = a.y + dz * t + 1.1
            let pole = SCNNode()
            pole.position = SCNVector3(x, g(x, z), z)
            pole.addChildNode(SK.cylinder(0.035, 1.7, poleMat, at: SCNVector3(0, 0.85, 0)))
            let f = SK.box(0.34, 0.24, 0.03, flagMat, at: SCNVector3(0.18, 1.55, 0))
            f.eulerAngles.y = CGFloat(i) * 0.4
            pole.addChildNode(f)
            world.addChildNode(pole)
        }
        // 燃烧罐：跑道的进度越高，点着的越多
        let barrelMat = SK.noiseMat(SK.rgb(0x4A4E54), SK.rgb(0x2A2C30), scale: 4, roughness: 0.7, metalness: 0.5, seed: 88)
        for i in 0..<6 {
            let t = CGFloat(i) / 5
            let x = a.x + dx * t - 3.4, z = a.y + dz * t - 0.8
            let b2 = SCNNode()
            b2.position = SCNVector3(x, g(x, z), z)
            b2.addChildNode(SK.cylinder(0.34, 0.75, barrelMat, at: SCNVector3(0, 0.38, 0)))
            let fire = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF7A1E))
            fire.emission.intensity = 1.8
            b2.addChildNode(SK.cylinder(0.3, 0.06, fire, at: SCNVector3(0, 0.76, 0)))
            if i == 0 {                                          // 只给最近的一个真光，其余靠泛光
                let l = SK.fireLight(intensity: 260, color: SK.rgb(0xFF8A2A), range: 20)
                l.position = SCNVector3(0, 0.9, 0)
                b2.addChildNode(l)
            }
            b2.isHidden = true
            world.addChildNode(b2)
            barrels.append(b2)
        }
    }

    // MARK: 旗线 / 脚印

    private func buildGuideLine() {
        let poleMat = SK.mat(SK.rgb(0x6B5A3A), roughness: 0.9)
        let flagMat = SK.mat(SK.rgb(0xE2621F), roughness: 0.85)
        let ropeMat = SK.mat(SK.rgb(0x8A8F96), roughness: 0.8)
        func line(_ pts: [CGPoint]) {
            for (i, p) in pts.enumerated() {
                let pole = SCNNode()
                pole.position = SCNVector3(p.x, g(p.x, p.y), p.y)
                pole.addChildNode(SK.cylinder(0.035, 1.25, poleMat, at: SCNVector3(0, 0.62, 0)))
                let f = SK.box(0.26, 0.18, 0.02, flagMat, at: SCNVector3(0.14, 1.18, 0))
                f.eulerAngles.y = CGFloat(i) * 0.8
                pole.addChildNode(f)
                world.addChildNode(pole)
                guard i > 0 else { continue }
                let a = pts[i - 1]
                let dx = p.x - a.x, dz = p.y - a.y
                let len = sqrt(dx * dx + dz * dz)
                let holder = SCNNode()
                holder.position = SCNVector3((p.x + a.x) / 2, g(p.x, p.y) + 0.95, (p.y + a.y) / 2)
                holder.eulerAngles.y = atan2(dx, dz)
                let rope = SK.cylinder(0.015, 1.0, ropeMat)
                rope.eulerAngles.x = .pi / 2
                rope.scale = SCNVector3(1, len, 1)
                holder.addChildNode(rope)
                world.addChildNode(holder)
            }
        }
        line([CGPoint(x: 3.0, y: 4.0), CGPoint(x: -1.5, y: 1.0), CGPoint(x: -6.5, y: 0.2),
              CGPoint(x: -11.0, y: 1.2), CGPoint(x: -14.0, y: 3.6)])
        line([CGPoint(x: 8.6, y: 3.0), CGPoint(x: 12.0, y: 6.5), CGPoint(x: 15.5, y: 9.5), CGPoint(x: 18.0, y: 12.0)])
        // 往跑道去的一串标志杆，正好从相机前面穿过去，给前景一点纵深
        line([CGPoint(x: 8.0, y: 6.4), CGPoint(x: 6.6, y: 11.0), CGPoint(x: 5.0, y: 15.5), CGPoint(x: 3.4, y: 20.0),
              CGPoint(x: 2.2, y: 24.5), CGPoint(x: 1.6, y: 28.0)])
        line([CGPoint(x: 9.6, y: 6.6), CGPoint(x: 12.0, y: 4.4), CGPoint(x: 14.6, y: 2.2), CGPoint(x: 16.6, y: 0.6)])

        // 雪地上的脚印
        func prints(_ a: CGPoint, _ b: CGPoint, _ n: Int, wobble: CGFloat = 0.35) {
            let m = SK.mat(SK.rgb(0xA9B3C2), roughness: 0.9)
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(max(1, n - 1))
                let x = a.x + (b.x - a.x) * t + (i % 2 == 0 ? wobble : -wobble) * 0.4
                let z = a.y + (b.y - a.y) * t + (i % 2 == 0 ? -wobble : wobble)
                let fp = SK.box(0.15, 0.03, 0.32, m, chamfer: 0.05)
                fp.position = SCNVector3(x, g(x, z) + 0.02, z)
                fp.eulerAngles.y = atan2(b.x - a.x, b.y - a.y) + (i % 2 == 0 ? 0.12 : -0.12)
                world.addChildNode(fp)
            }
        }
        prints(CGPoint(x: 2.4, y: 4.3), CGPoint(x: -8.5, y: 1.4), 34)
        prints(CGPoint(x: 9.0, y: 3.6), CGPoint(x: 16.5, y: 11.0), 26)
        prints(CGPoint(x: 9.6, y: 6.6), CGPoint(x: 14.0, y: 5.0), 18)
        prints(CGPoint(x: 14.0, y: 5.0), CGPoint(x: 16.5, y: 1.6), 12)
        // 巴特尔在吹雪里走丢的那一串，往东北去了
        prints(CGPoint(x: 14.0, y: 10.0), CGPoint(x: 30.0, y: 20.0), 20, wobble: 1.1)
    }

    // MARK: 营地杂物

    private func buildYard() {
        let crateMat = SK.noiseMat(SK.rgb(0xB08A5A), SK.rgb(0x7A5C38), scale: 6, roughness: 0.9, seed: 101)
        for i in 0..<4 {                                        // 从冷库拖出来的箱子
            let c = SK.box(0.85, 0.55, 0.6, crateMat, chamfer: 0.03,
                           at: SCNVector3(10.2 + CGFloat(i % 2) * 0.9, g(10.2, 6.6) + 0.3 + CGFloat(i / 2) * 0.56, 6.6))
            c.eulerAngles.y = CGFloat(i) * 0.3
            world.addChildNode(c)
        }
        // 半埋在雪里的空油桶和一只冻住的木箱（近景）
        for (x, z, r) in [(0.2, 16.0, 0.5), (-2.4, 19.5, -0.9), (1.6, 22.5, 0.3)] as [(CGFloat, CGFloat, CGFloat)] {
            let d = SK.cylinder(0.3, 0.95, SK.noiseMat(SK.rgb(0x2E4E6E), SK.rgb(0x6B5A48), scale: 5, roughness: 0.7, metalness: 0.4, seed: 12),
                                at: SCNVector3(x, g(x, z) + 0.22, z))
            d.eulerAngles = SCNVector3(r, 0, 1.5)
            world.addChildNode(d)
        }
        world.addChildNode(SK.box(0.9, 0.6, 0.7, SK.noiseMat(SK.rgb(0xB08A5A), SK.rgb(0x7A5C38), scale: 6, roughness: 0.9, seed: 101),
                                  chamfer: 0.03, at: SCNVector3(5.4, g(5.4, 18.0) + 0.25, 18.0)))

        for i in 0..<3 {                                        // 舱门口的一摞油桶
            world.addChildNode(SK.cylinder(0.3, 0.9, SK.noiseMat(SK.rgb(0x2E4E6E), SK.rgb(0x6B5A48), scale: 5, roughness: 0.7, metalness: 0.4, seed: 12),
                                           at: SCNVector3(-0.6 + CGFloat(i) * 0.75, g(-0.6, 3.0) + 0.46, 3.0)))
        }

        // 冰芯箱：唐悦的样品，埋在舱边的雪坑里（flag.cores_saved）
        let core = SCNNode()
        core.position = SCNVector3(11.6, g(11.6, 2.0), 2.0)
        let boxMat = SK.noiseMat(SK.rgb(0xCFE3F0), SK.rgb(0x8FB4CC), scale: 5, roughness: 0.6, seed: 111)
        for i in 0..<3 {
            core.addChildNode(SK.box(0.95, 0.42, 0.5, boxMat, chamfer: 0.03, at: SCNVector3(CGFloat(i % 2) * 1.0, 0.22 + CGFloat(i / 2) * 0.44, 0)))
        }
        core.addChildNode(snowDrift(1.7, seed: 112, flatten: 0.16, at: SCNVector3(0.6, 0.22, 0.5)))
        core.isHidden = true
        world.addChildNode(core)
        cores = core

        // 空投的包裹和降落伞（event airdrop）
        let bn = SCNNode()
        for i in 0..<3 {
            let x = 26 + CGFloat(i) * 7, z = -7 - CGFloat(i) * 5
            let b = SCNNode()
            b.position = SCNVector3(x, g(x, z), z)
            let par = SK.node(SCNSphere(radius: 2.2), SK.mat(SK.rgb(0xD8DCE0), roughness: 0.9, doubleSided: true))
            par.scale = SCNVector3(1, 0.42, 1)
            par.position = SCNVector3(0, 0.95, 0)
            b.addChildNode(par)
            b.addChildNode(SK.box(0.9, 0.7, 0.7, crateMat, chamfer: 0.04, at: SCNVector3(0, 0.35, 0)))
            bn.addChildNode(b)
        }
        bn.isHidden = true
        world.addChildNode(bn)
        bundles = bn

        // 救援物资（flag.relief）
        let rf = SCNNode()
        for i in 0..<5 {
            rf.addChildNode(SK.box(0.8, 0.5, 0.6, crateMat, chamfer: 0.03,
                                   at: SCNVector3(CGFloat(i % 3) * 0.9, 0.28 + CGFloat(i / 3) * 0.52, CGFloat(i / 3) * 0.1)))
        }
        rf.position = SCNVector3(9.8, g(9.8, 8.6), 8.6)
        rf.isHidden = true
        world.addChildNode(rf)
        relief = rf

        // 柴油桶改的炉子（flag.burzhuika）
        let st = SCNNode()
        st.position = SCNVector3(1.2, g(1.2, 6.6), 6.6)
        st.addChildNode(SK.cylinder(0.42, 1.0, charred, at: SCNVector3(0, 0.5, 0)))
        st.addChildNode(SK.cylinder(0.09, 2.6, darkSteel, at: SCNVector3(0, 2.1, 0.2)))
        let sglow = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF7A22))
        sglow.emission.intensity = 0
        stoveGlow = sglow
        st.addChildNode(SK.box(0.4, 0.3, 0.05, sglow, at: SCNVector3(0, 0.45, 0.42)))
        st.addChildNode(SK.box(0.6, 0.1, 0.5, charredWood, at: SCNVector3(0, 0.02, 0)))
        let sl = SK.fireLight(intensity: 40, color: SK.rgb(0xFF8A32), range: 7)
        sl.position = SCNVector3(0, 0.6, 0)
        st.addChildNode(sl)
        stoveLight = sl
        st.isHidden = true
        world.addChildNode(st)
        stove = st

        // 油桶点着的信号火（event overflight / var.alarm）
        let bf = SCNNode()
        bf.position = SCNVector3(-1.5, g(-1.5, 8.0), 8.0)
        bf.addChildNode(SK.cylinder(0.42, 0.95, charred, at: SCNVector3(0, 0.48, 0)))
        let bfFire = SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF6A12))
        bfFire.emission.intensity = 1.6
        bf.addChildNode(SK.cylinder(0.4, 0.08, bfFire, at: SCNVector3(0, 0.96, 0)))
        let bl = SK.fireLight(intensity: 420, color: SK.rgb(0xFF7A28), range: 22)
        bl.position = SCNVector3(0, 1.4, 0)
        bf.addChildNode(bl)
        bonfireLight = bl
        let bfl = SCNNode()
        bfl.position = SCNVector3(0, 1.0, 0)
        bf.addChildNode(bfl)
        bonfireFlame = bfl
        bf.isHidden = true
        world.addChildNode(bf)
        bonfire = bf

        // 杨师傅：倒在厨房那头的废墟边（flag.yang_found）
        let yb = SK.shroud(color: SK.rgb(0x4A5058), seed: 5)
        yb.position = SCNVector3(-9.5, g(-9.5, 4.6) + 0.05, 4.6)
        yb.eulerAngles.y = 1.2
        yb.isHidden = true
        world.addChildNode(yb)
        yangBody = yb

        // 废墟边的作业灯：有人在那儿刨东西
        let wl = SCNNode()
        wl.position = SCNVector3(-3.5, g(-3.5, 3.5), 3.5)
        for i in 0..<3 {
            let leg = SK.cylinder(0.03, 1.9, darkSteel)
            let a = CGFloat(i) * 2.1
            leg.position = SCNVector3(sin(a) * 0.3, 0.95, cos(a) * 0.3)
            leg.eulerAngles = SCNVector3(cos(a) * 0.24, 0, -sin(a) * 0.24)
            wl.addChildNode(leg)
        }
        let head = SK.box(0.5, 0.22, 0.3, SK.mat(.black, roughness: 0.6, emission: SK.rgb(0xDCE8FF)), at: SCNVector3(0, 1.95, 0))
        head.eulerAngles.x = 0.5
        wl.addChildNode(head)
        let wlLight = SCNLight()
        wlLight.type = .omni
        wlLight.color = SK.rgb(0xC9DCFF)
        wlLight.intensity = 26
        wlLight.attenuationEndDistance = 15
        wlLight.attenuationFalloffExponent = 2
        let wln = SCNNode()
        wln.light = wlLight
        wln.position = SCNVector3(0, 1.9, 0.6)
        wl.addChildNode(wln)
        wl.isHidden = true
        world.addChildNode(wl)
        workLamp = wl
    }

    // MARK: 雪橇

    private func buildSled() {
        let sled = SCNNode()
        sled.position = SCNVector3(3.0, g(3.0, -1.0), -1.0)
        sled.eulerAngles.y = -0.4
        world.addChildNode(sled)
        let wood = SK.noiseMat(SK.rgb(0x8A6A44), SK.rgb(0x5C4227), scale: 5, roughness: 0.9, seed: 131)
        for dz in [-0.5, 0.5] as [CGFloat] {
            sled.addChildNode(SK.box(3.4, 0.08, 0.12, wood, at: SCNVector3(0, 0.14, dz)))
            sled.addChildNode(SK.box(3.0, 0.1, 0.08, wood, at: SCNVector3(0, 0.34, dz)))
            for i in 0..<4 {
                sled.addChildNode(SK.box(0.08, 0.22, 0.08, wood, at: SCNVector3(CGFloat(i) * 0.9 - 1.35, 0.24, dz)))
            }
        }
        for i in 0..<5 {
            sled.addChildNode(SK.box(0.12, 0.05, 1.15, wood, at: SCNVector3(CGFloat(i) * 0.7 - 1.4, 0.4, 0)))
        }
        sled.addChildNode(SK.box(0.9, 0.7, 0.8, SK.noiseMat(SK.rgb(0xB08A5A), SK.rgb(0x7A5C38), scale: 6, roughness: 0.9, seed: 101),
                                chamfer: 0.04, at: SCNVector3(-0.5, 0.78, 0)))
        sled.addChildNode(SK.cylinder(0.3, 0.9, SK.noiseMat(SK.rgb(0x8A3B24), SK.rgb(0x5C4038), scale: 5, roughness: 0.8, metalness: 0.35, seed: 18),
                                      at: SCNVector3(0.9, 0.86, 0)))
        for i in 0..<3 {
            sled.addChildNode(snowDrift(1.1, seed: UInt64(140 + i), flatten: 0.15,
                                        at: SCNVector3(CGFloat(i) * 1.2 - 1.2, 0.1, CGFloat(i % 2) * 1.6 - 0.8)))
        }
    }

    // MARK: 按状态开关

    override func apply(_ s: SceneState, old: SceneState?) {
        applyStation(s)
        applyHut(s)
        applyWork(s)
        applyYard(s)
        applyRescue(s)

        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: Spot.line(from: SCNVector3(-8.0, 0, 6.6), to: SCNVector3(-3.5, 0, 7.8), count: 6, facing: 1.5, y: g))
    }

    /// 废墟：火灾那一晚还在烧，之后只剩余烬和灌进去的雪；天线按进度拉长。
    private func applyStation(_ s: SceneState) {
        let burning = s.round <= 1 || s.now("fire_night")
        ruinFlame?.isHidden = !burning
        ruinLight?.base = burning ? 300 : 55
        for m in embers { m.emission.intensity = burning ? 1.7 : 0.85 }

        let ant = s.done.contains("antenna") ? 1 : max(0, min(1, s.project("antenna")))
        antennaWire?.isHidden = ant <= 0.1
        for leg in antennaLegs { leg.scale = SCNVector3(1, max(0.02, CGFloat(ant) * 4.9), 1) }
        beacon?.isHidden = !(s.has("contact") || s.done.contains("radio"))
        radioGlow?.isHidden = !(s.done.contains("radio") || s.has("contact"))

        if let r = rotor {                                        // 风越大转得越快
            r.removeAllActions()
            r.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: -2 * .pi, duration: max(0.5, 7.0 - s.wind / 11))))
        }
    }

    /// 应急舱：暖风机一停，画面里就只剩月光；排气管口的雪堆跟着 var.exhaust 长。
    private func applyHut(_ s: SceneState) {
        let lit = s.fireLit
        for m in panes { m.emission.intensity = lit ? 1.5 : 0.5 }
        hutLamp?.intensity = lit ? 72 : 22
        let ex = max(0, min(1, s.v("exhaust") / 100))
        if let holder = exhaustDrift {
            holder.childNodes.forEach { $0.removeFromParentNode() }
            if ex > 0.04 {
                holder.addChildNode(snowDrift(Float(0.45 + ex * 0.6), seed: 151, flatten: 0.42,
                                              at: SCNVector3(-3.35, -0.16 + CGFloat(ex) * 0.5, 0.9)))
            }
        }
        exhaustPipe?.isHidden = ex > 0.93
    }

    /// 工程：挖车库、架天线、修电台。
    private func applyWork(_ s: SceneState) {
        let garage = s.done.contains("garage") ? 1 : max(0, min(1, s.project("garage")))
        doorPivot?.eulerAngles.y = CGFloat(-1.15 * garage)
        garageDrift?.isHidden = garage > 0.55
        let busy = s.project("antenna") > 0.05 || s.project("radio") > 0.05 || s.project("garage") > 0.05
            || s.done.contains("antenna") || s.done.contains("radio") || s.done.contains("garage")
        workLamp?.isHidden = !busy
        let catOn = s.has("snowcat")
        for m in catGlow { m.emission.intensity = catOn ? 1.7 : 0 }
        catLight?.intensity = catOn ? 260 : 0
    }

    /// 营地：冰芯、物资、炉子、信号火、杨师傅。
    private func applyYard(_ s: SceneState) {
        cores?.isHidden = !s.has("cores_saved")
        relief?.isHidden = !(s.has("relief") || s.has("rescued"))
        bundles?.isHidden = !s.happened("airdrop")
        yangBody?.isHidden = !s.has("yang_found")
        stove?.isHidden = !s.has("burzhuika")
        let stoveOn = s.has("burzhuika")
        stoveGlow?.emission.intensity = stoveOn ? 1.2 : 0
        stoveLight?.base = stoveOn ? 40 : 0
        stoveLight?.isHidden = !stoveOn

        let lit = s.now("overflight") || s.has("spotted") || s.has("plane_coming")
        bonfire?.isHidden = !lit
        bonfireLight?.base = s.now("overflight") ? 420 : 150
        // 明火粒子同时只留一套（基类的天气粒子另算）：废墟还烧着的时候，信号火就不再吐火苗
        if let f = bonfireFlame {
            let want = lit && s.now("overflight") && (ruinFlame?.isHidden ?? true)
            let has = !(f.particleSystems ?? []).isEmpty
            if want && !has { f.addParticleSystem(SK.fire(scale: 1.9)) }
            if !want && has { f.removeAllParticleSystems() }
        }
    }

    /// 跑道、空投、飞过头顶的飞机和落地的飞机。
    private func applyRescue(_ s: SceneState) {
        let ready = max(min(1, s.v("skiway") / 100), s.has("plane_coming") ? 1 : 0)
        let n = Int((Double(barrels.count) * ready).rounded())
        for (i, b) in barrels.enumerated() { b.isHidden = i >= n }
        for p in stripPieces { p.isHidden = ready < 0.12 }

        if s.now("overflight") && overflight == nil {
            let p = SCNNode()
            let dark = SK.mat(SK.rgb(0x22262C), roughness: 0.7)
            p.addChildNode(SK.box(1.0, 0.5, 3.4, dark))
            p.addChildNode(SK.box(5.0, 0.12, 0.9, dark, at: SCNVector3(0, 0.1, 0)))
            let red = SK.sphere(0.4, SK.mat(.black, roughness: 0.4, emission: SK.rgb(0xFF2010)), at: SCNVector3(0, -0.3, 0))
            red.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.7),
                                                    .fadeOpacity(to: 0.05, duration: 0.1), .wait(duration: 0.7)])))
            p.addChildNode(red)
            p.position = SCNVector3(90, 190, -240)
            p.runAction(.repeatForever(.sequence([.moveBy(x: -240, y: 12, z: -60, duration: 70),
                                                  .moveBy(x: 240, y: -12, z: 60, duration: 70)])))
            world.addChildNode(p)
            overflight = p
        }
        overflight?.isHidden = !s.now("overflight")

        let landing = s.now("plane") || (s.ended && s.has("rescued"))
        if landing && plane == nil {
            let p = SCNNode()
            let alu = SK.mat(SK.rgb(0xC8CDD3), roughness: 0.45, metalness: 0.5)
            p.addChildNode(SK.box(1.5, 1.3, 9.0, alu, chamfer: 0.2, at: SCNVector3(0, 1.5, 0)))
            p.addChildNode(SK.box(0.5, 0.9, 3.0, alu, chamfer: 0.15, at: SCNVector3(0, 2.5, -4.0)))
            p.addChildNode(SK.box(0.2, 1.6, 1.0, alu, at: SCNVector3(0, 3.4, -5.2)))
            p.addChildNode(SK.box(19, 0.3, 2.4, alu, at: SCNVector3(0, 1.9, -0.4)))
            for dx in [-4.2, 4.2] as [CGFloat] {
                let e = SK.cylinder(0.55, 2.2, SK.mat(SK.rgb(0x9AA0A6), roughness: 0.5, metalness: 0.6), at: SCNVector3(dx, 1.5, -0.4))
                e.eulerAngles.x = .pi / 2
                p.addChildNode(e)
                let spin = SCNNode()
                spin.position = SCNVector3(dx, 1.5, 1.2)
                let disc = SCNNode(geometry: SCNCylinder(radius: 1.5, height: 0.02))
                disc.geometry?.firstMaterial = SK.mat(NSColor(white: 0.6, alpha: 0.16), roughness: 1)
                disc.geometry?.firstMaterial?.transparency = 0.16
                disc.eulerAngles.x = .pi / 2
                spin.addChildNode(disc)
                for i in 0..<4 {
                    let arm = SCNNode()
                    arm.eulerAngles.y = CGFloat(i) * .pi / 2
                    arm.addChildNode(SK.box(0.22, 0.03, 2.9, SK.mat(SK.rgb(0x2A2E33), roughness: 0.6), at: SCNVector3(0, 0, 1.5)))
                    spin.addChildNode(arm)
                }
                spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.16)))
                p.addChildNode(spin)
            }
            // 着陆灯：黑暗里最亮的一点
            let l = SK.fireLight(intensity: 1600, color: SK.rgb(0xFFF6E2), range: 90)
            l.position = SCNVector3(0, 1.6, -5.6)
            p.addChildNode(l)
            p.addChildNode(SK.sphere(0.24, SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xFFFDF2)), at: SCNVector3(0, 1.6, -5.6)))
            p.position = SCNVector3(86, g(86, 12) + 0.9, 12)
            p.eulerAngles.y = 1.42
            world.addChildNode(p)
            plane = p
        }
        plane?.isHidden = !landing
    }

    // MARK: 人

    /// 伤员躺在舱壁和雪砖墙中间；夜里有人守夜；工作时段其余的人在废墟、
    /// 天线杆、车库和跑道干活——位置跟着工程进度走。
    private func spots(for s: SceneState) -> [Spot] {
        var out: [Spot] = []
        // 受伤的人一定会躺下，所以先把舱壁下这两个铺位放在最前面
        out.append(Spot(4.7, g(4.7, 6.2) + 0.12, 6.2, facing: 1.45, pose: .lying))
        out.append(Spot(6.4, g(6.4, 6.2) + 0.12, 6.2, facing: 1.45, pose: .lying))
        if s.precip >= 1.5 || s.wind >= 45 {                       // 暴风雪：都缩到舱的背风面
            for i in 0..<10 {
                let x = 3.2 + CGFloat(i % 5) * 1.35
                let z = 7.9 + CGFloat(i / 5) * 0.8
                out.append(Spot(x, g(x, z), z, facing: -1.4, pose: .huddled))
            }
            return out
        }
        out.append(Spot(2.4, g(2.4, 3.2), 3.2, facing: -1.5))      // 守夜的人，站在门口
        // 废墟前面清东西的人——这是画面正中，先占上
        out.append(Spot(-6.0, g(-6, 2.2), 2.2, facing: -0.3))
        out.append(Spot(-9.8, g(-9.8, 3.0), 3.0, facing: 0.2))
        out.append(Spot(-3.2, g(-3.2, 4.4), 4.4, facing: -0.6))
        out.append(Spot(-13.6, g(-13.6, 5.6), 5.6, facing: 0.9, pose: .sitting))
        // 有工程的时候，人被拉到工地上
        if s.project("antenna") > 0.05 || s.project("radio") > 0.05 || s.done.contains("antenna") {
            out.append(Spot(-3.0, g(-3, -13.5), -13.5, facing: 3.0))
        }
        if s.project("garage") > 0.05 || s.done.contains("garage") {
            out.append(Spot(16.0, g(16.0, -2.2), -2.2, facing: 2.8))
        }
        if s.v("skiway") > 5 || s.has("plane_coming") {
            out.append(Spot(22.0, g(22, 3.0), 3.0, facing: 1.5))
        }
        // 剩下的：舱门口挤着的人、脚印上的两个人（离相机近，画面才有活气）
        let tail: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.6, 8.4, 2.6), (1.6, 9.6, -2.6), (0.4, 12.6, -2.9), (-1.4, 15.0, 2.8),
            (1.4, 5.6, 0.4), (-5.0, 6.0, 1.2)
        ]
        for t in tail where out.count < 12 {
            out.append(Spot(t.0, g(t.0, t.1), t.1, facing: t.2))
        }
        return out
    }
}
