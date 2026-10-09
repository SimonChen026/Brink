import SceneKit
import AppKit

/// 雪线 — a broken airliner in a glacial cirque at 4,100 m, western Sichuan, November.
///
/// Layout (meters): the fuselage lies along −x with its torn-open end at x ≈ 0 facing the camp;
/// the cirque headwall rises to the west, side walls north and south, the valley opens east.
/// State shown: SOS on the snow (var.signal), locator antenna (flag elt_on / done.elt),
/// dug-out cargo hold (done.cargo), avalanche debris (event avalanche), footprints toward the
/// east ridge (flag trek_started, var.route), search plane (event r_heli_pass), rescue helicopter
/// (events helicopter / heli_return), the dead under blankets.
final class SnowlineScene: ScenarioScene {
    private let noise = SK.Noise(seed: 2026)
    private var sos: [SCNNode] = []
    private var elt: SCNNode?
    private var cargo: SCNNode?
    private var avalancheDebris: SCNNode?
    private var footprints: [SCNNode] = []
    private var cairns: [SCNNode] = []
    private var helicopter: SCNNode?
    private var plane: SCNNode?

    required init() {
        super.init()
        skyStyle = .alpine
        sunPeak = 40                 // ~30°N in November
        sunAzimuth = 70              // late-morning sun over the valley mouth, lighting the headwall
        exposure = -0.45
        sunScale = 0.9
        hazeColor = SK.rgb(0xC7D3E0)
        stormColor = SK.rgb(0xA9B2BC)
        clearVisibility = 3200
        weatherArea = 90
        weatherCenter = SCNVector3(0, 24, 0)
        cameraTarget = SCNVector3(-3, 3.2, -1.5)
        cameraDistance = 23
        cameraYaw = 62
        cameraPitch = 7
        cameraFOV = 46
    }

    // MARK: Terrain

    /// Height of the snow surface at (x, z).
    func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { CGFloat(height(Float(x), Float(z))) }

    private func height(_ x: Float, _ z: Float) -> Float {
        // cirque bowl centered west of the camp, open to the east
        let cx: Float = -40, cz: Float = 0
        let dx = x - cx, dz = (z - cz) * 1.1
        let r = sqrt(dx * dx + dz * dz)
        let ang = atan2(dz, dx)                                  // 0 = east (the open side)
        let openEast = SK.smoothstep(0.5, 1.6, abs(ang))           // 0 toward the east, 1 elsewhere
        var h: Float = 0
        // floor: gentle rise to the west
        h += max(0, -x) * 0.04
        // walls: rise from the cirque floor to a crest ~190 m up (lower toward the open valley)
        let wallT = SK.smoothstep(85, 250, r)
        h += pow(wallT, 1.5) * 190 * (0.25 + 0.75 * openEast)
        // rock ribs and gullies on the walls
        let rib = noise.ridged(x / 60, z / 60, octaves: 4)
        let gully = noise.ridged(x / 22 + 7, z / 22, octaves: 3)
        h += (rib * 30 + gully * 9) * SK.smoothstep(90, 230, r)
        // beyond the crest: a high massif with distant peaks
        h += SK.smoothstep(270, 620, r) * (90 + noise.ridged(x / 170 + 3, z / 170, octaves: 4) * 380)
        // the valley drops away to the east
        h -= max(0, x - 70) * 0.18 * (1 - openEast)
        // wind-packed drifts against the fuselage (deep on the north side)
        if x > -19 && x < 1 {
            let along = SK.smoothstep(-19, -15, x) * (1 - SK.smoothstep(-2, 1, x))
            let north = exp(-pow((z + 5.0) / 1.6, 2)) * 1.5
            let south = exp(-pow((z - 0.6) / 1.1, 2)) * 0.45
            h += (north + south) * along
        }
        // small undulations everywhere, flattened at the camp
        let camp = SK.smoothstep(14, 34, sqrt((x + 5) * (x + 5) + (z + 2) * (z + 2)))
        h += (noise.fbm(x / 18, z / 18, octaves: 4) - 0.5) * 2.2 * camp
        return h - 0.15
    }

    // MARK: Build

    override func build(_ s: SceneState) {
        // snow on gentle ground, dark rock on the steep walls (per pixel); vertex colors add strata
        // only the steepest faces shed their snow; weathered grey-brown rock, not black
        let groundMat = SK.terrainMaterial(flat: SK.rgb(0xF1F4F8), steep: SK.rgb(0x6A635C), from: 0.52, to: 0.6,
                                        grain: 0.12, noiseScale: 0.035, roughness: 0.6)
        SK.addGrain(groundMat, scale: 10, strength: 2.5, intensity: 0.3)
        let terrain = SK.terrain(size: 1300, segments: 360, height: height, color: { x, y, z, _ in
            // faint strata and a cooler tint up high
            let strata = self.noise.value(y / 6, x / 280 + z / 280)
            let k = 1 - 0.18 * SK.smoothstep(0.6, 0.8, strata) * SK.smoothstep(25, 70, y)
            return SIMD3(k, k, k * 1.01)
        }, material: groundMat, uvRepeat: 200)
        terrain.castsShadow = false
        world.addChildNode(terrain)

        buildFuselage()
        buildWing()
        buildTail()
        buildDebris()
        buildSOS()
        addFire(at: SCNVector3(3.6, ground(3.6, 0.6), 0.6), scale: 0.9)
    }

    private func buildFuselage() {
        let paint = SK.mat(SK.rgb(0xE8EBEE), roughness: 0.38, metalness: 0.45)
        let inside = SK.mat(SK.rgb(0x2A2E35), roughness: 0.9)
        let edge = SK.mat(SK.rgb(0x9DA3AA), roughness: 0.5, metalness: 0.8)
        let stripe = SK.mat(SK.rgb(0x1D4E89), roughness: 0.4, metalness: 0.3)
        let glass = SK.mat(SK.rgb(0x101418), roughness: 0.15, metalness: 0.2)

        let body = SCNNode()
        body.position = SCNVector3(-8.4, ground(-8.4, -3) + 0.85, -3)
        body.eulerAngles = SCNVector3(0, 0.05, 0.1)          // settled crooked in the snow
        world.addChildNode(body)

        let tube = SCNTube(innerRadius: 1.62, outerRadius: 1.74, height: 16.5)
        tube.radialSegmentCount = 48
        tube.materials = [paint, inside, edge, edge]
        let t = SCNNode(geometry: tube)
        t.eulerAngles.z = .pi / 2
        body.addChildNode(t)
        // floor inside the cabin
        let floor = SK.box(16, 0.08, 2.6, SK.mat(SK.rgb(0x3B3F46), roughness: 0.9), at: SCNVector3(0, -0.85, 0))
        body.addChildNode(floor)
        // cheatline and windows on the visible (+z) side
        body.addChildNode(SK.box(15.6, 0.16, 0.04, stripe, at: SCNVector3(0.2, -0.05, 1.735)))
        for i in 0..<15 {
            let w = SK.box(0.26, 0.36, 0.03, glass, chamfer: 0.08, at: SCNVector3(-6.6 + CGFloat(i) * 0.95, 0.42, 1.715))
            body.addChildNode(w)
        }
        // crushed nose to the west
        let nose = SCNNode(geometry: SCNCone(topRadius: 0.5, bottomRadius: 1.74, height: 3.4))
        nose.geometry?.materials = [paint, paint, paint]
        nose.eulerAngles.z = .pi / 2
        nose.position = SCNVector3(-9.9, -0.15, 0)
        nose.scale = SCNVector3(1, 1, 0.9)
        body.addChildNode(nose)
        for dz in [-0.45, 0.45] as [CGFloat] {
            let cw = SK.box(0.5, 0.32, 0.04, glass, chamfer: 0.05, at: SCNVector3(-9.6, 0.55, 1.15 * (dz > 0 ? 1 : -1)))
            cw.eulerAngles.y = dz > 0 ? -0.6 : 0.6
            body.addChildNode(cw)
        }
        // torn metal around the open end (east)
        for i in 0..<14 {
            let a = CGFloat(i) / 14 * 2 * .pi
            let shard = SK.box(0.9 + CGFloat(i % 3) * 0.35, 0.05, 0.55, edge, chamfer: 0.0)
            shard.position = SCNVector3(8.4 + CGFloat(i % 4) * 0.12, sin(a) * 1.7, cos(a) * 1.7)
            shard.eulerAngles = SCNVector3(a, CGFloat(i % 5) * 0.2 - 0.4, CGFloat(i % 3) * 0.3)
            body.addChildNode(shard)
        }
        // (drifts along the sides are part of the terrain; see `height`)

        // locator antenna (shown once the ELT works)
        let pole = SK.cylinder(0.025, 2.2, edge)
        pole.position = SCNVector3(-3, 2.7, 0)
        let lamp = SK.sphere(0.07, SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xFF2A1A)), at: SCNVector3(0, 1.1, 0))
        let blink = SCNAction.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.15),
                                                       .fadeOpacity(to: 0.1, duration: 0.05), .wait(duration: 1.0)]))
        lamp.runAction(blink)
        pole.addChildNode(lamp)
        pole.isHidden = true
        body.addChildNode(pole)
        elt = pole

        // cargo hold dug out on the south side: a pit with boxes and sacks
        let pit = SCNNode()
        pit.position = SCNVector3(-10, ground(-10, -0.2), 0.6)
        let hatch = SK.box(1.6, 1.1, 0.06, SK.mat(SK.rgb(0x15181C), roughness: 1), at: SCNVector3(0, 0.15, -0.95))
        pit.addChildNode(hatch)
        let card = SK.noiseMat(SK.rgb(0xA27C52), SK.rgb(0x7E5E3C), scale: 6, seed: 17)
        let sack = SK.mat(SK.rgb(0xCDBF9E), roughness: 1)
        for i in 0..<6 {
            let b = i % 3 == 2 ? SK.node(SCNCapsule(capRadius: 0.22, height: 0.8), sack) : SK.box(0.55, 0.4, 0.45, card, chamfer: 0.02)
            b.position = SCNVector3(CGFloat(i % 3) * 0.7 - 0.6, 0.2 + CGFloat(i / 3) * 0.42, 0.25 + CGFloat(i % 2) * 0.3)
            b.eulerAngles.y = CGFloat(i) * 0.4
            if i % 3 == 2 { b.eulerAngles.z = .pi / 2 }
            pit.addChildNode(b)
        }
        pit.isHidden = true
        world.addChildNode(pit)
        cargo = pit
    }

    private func buildWing() {
        let paint = SK.mat(SK.rgb(0xDADDE1), roughness: 0.4, metalness: 0.5)
        let wing = SK.box(11, 0.28, 2.6, paint, chamfer: 0.08)
        wing.position = SCNVector3(-7, ground(-7, 7.5) + 0.25, 7.5)
        wing.eulerAngles = SCNVector3(0.05, -0.35, -0.06)
        let engine = SK.cylinder(0.75, 2.6, SK.mat(SK.rgb(0xB9BEC4), roughness: 0.35, metalness: 0.6))
        engine.eulerAngles.x = .pi / 2
        engine.position = SCNVector3(-1.5, -0.55, 0.6)
        wing.addChildNode(engine)
        let intake = SK.cylinder(0.6, 0.05, SK.mat(SK.rgb(0x111111), roughness: 0.6))
        intake.eulerAngles.x = .pi / 2
        intake.position = SCNVector3(-1.5, -0.55, 1.92)
        wing.addChildNode(intake)
        world.addChildNode(wing)
    }

    private func buildTail() {
        // the tail section came to rest up-slope to the north-west
        let paint = SK.mat(SK.rgb(0xE3E6EA), roughness: 0.4, metalness: 0.45)
        let tailPos = SCNVector3(-58, ground(-58, -46), -46)
        let tail = SCNNode()
        tail.position = tailPos
        tail.eulerAngles = SCNVector3(0.1, 0.9, 0.18)
        let piece = SCNNode(geometry: SCNTube(innerRadius: 1.4, outerRadius: 1.55, height: 5))
        piece.geometry?.materials = [paint, SK.mat(SK.rgb(0x22262C), roughness: 0.9), paint, paint]
        piece.eulerAngles.z = .pi / 2
        piece.position.y = 0.9
        tail.addChildNode(piece)
        let fin = SK.box(2.6, 3.6, 0.22, SK.mat(SK.rgb(0x1D4E89), roughness: 0.4, metalness: 0.3), chamfer: 0.05)
        fin.position = SCNVector3(-1.2, 3.4, 0)
        fin.eulerAngles.z = 0.35
        tail.addChildNode(fin)
        world.addChildNode(tail)
    }

    private func buildDebris() {
        // a debris trail from the tail toward the fuselage
        let colors = [0x2F4F7F, 0xB03A2E, 0x1E1E1E, 0x6C5B7B, 0xD4A017, 0x3D7A5A, 0x8B4513].map { SK.rgb(UInt32($0)) }
        let metal = SK.mat(SK.rgb(0xA8AEB5), roughness: 0.45, metalness: 0.7)
        for i in 0..<34 {
            let t = CGFloat(i) / 34
            let jitter = CGFloat(noise.value(Float(i) * 1.7, 3.3) - 0.5)
            let x = -50 + t * 44 + jitter * 10
            let z = -40 + t * 34 + CGFloat(noise.value(Float(i) * 2.1, 9.1) - 0.5) * 16
            let n: SCNNode
            if i % 3 == 0 {
                n = SK.box(0.9 + jitter, 0.06, 0.6, metal, chamfer: 0)
                n.eulerAngles = SCNVector3(jitter, CGFloat(i), 0.3)
            } else {
                // a suitcase
                n = SK.box(0.5, 0.25, 0.7, SK.mat(colors[i % colors.count], roughness: 0.6), chamfer: 0.04)
                n.eulerAngles = SCNVector3(jitter * 0.6, CGFloat(i) * 0.7, 0)
            }
            n.position = SCNVector3(x, ground(x, z) + 0.08, z)
            world.addChildNode(n)
        }
    }

    // MARK: SOS

    private func buildSOS() {
        // three letters laid out with seat cushions and dark luggage, 5 m tall, on open snow beyond the wing
        let mat = SK.mat(SK.rgb(0x1B1F26), roughness: 0.9)
        let origin = SCNVector3(-27, 0, 15)
        func stroke(_ x0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ z1: CGFloat) {
            let n = 5
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n - 1)
                let x = origin.x + x0 + (x1 - x0) * t, z = origin.z + z0 + (z1 - z0) * t
                let b = SK.box(0.55, 0.14, 0.75, mat, chamfer: 0.05)
                b.position = SCNVector3(x, ground(x, z) + 0.05, z)
                b.eulerAngles.y = atan2(x1 - x0, z1 - z0) + CGFloat(k % 2) * 0.2
                b.isHidden = true
                world.addChildNode(b)
                sos.append(b)
            }
        }
        // letters run along +x; "up" in the letters is −z (readable from the air)
        // S
        stroke(0, -2.5, 2.5, -2.5); stroke(0, -2.5, 0, 0); stroke(0, 0, 2.5, 0); stroke(2.5, 0, 2.5, 2.5); stroke(2.5, 2.5, 0, 2.5)
        // O
        stroke(4, -2.5, 6.5, -2.5); stroke(6.5, -2.5, 6.5, 2.5); stroke(6.5, 2.5, 4, 2.5); stroke(4, 2.5, 4, -2.5)
        // S
        stroke(8, -2.5, 10.5, -2.5); stroke(8, -2.5, 8, 0); stroke(8, 0, 10.5, 0); stroke(10.5, 0, 10.5, 2.5); stroke(10.5, 2.5, 8, 2.5)
    }

    // MARK: Rescue aircraft

    private func makeHelicopter() -> SCNNode {
        let orange = SK.mat(SK.rgb(0xE8601C), roughness: 0.45, metalness: 0.2)
        let dark = SK.mat(SK.rgb(0x1A1C20), roughness: 0.5)
        let glass = SK.mat(SK.rgb(0x2A3A48), roughness: 0.1, metalness: 0.3)
        let h = SCNNode()
        let body = SK.sphere(1.3, orange); body.scale = SCNVector3(1.0, 0.85, 1.7)
        h.addChildNode(body)
        let canopy = SK.sphere(0.9, glass, at: SCNVector3(0, 0.25, 1.35)); canopy.scale = SCNVector3(1, 0.8, 0.9)
        h.addChildNode(canopy)
        let boom = SK.cylinder(0.22, 5.2, orange); boom.eulerAngles.x = .pi / 2; boom.position = SCNVector3(0, 0.35, -3.6)
        h.addChildNode(boom)
        let fin = SK.box(0.12, 1.2, 0.8, orange, at: SCNVector3(0, 0.9, -6.1))
        h.addChildNode(fin)
        for dx in [-0.75, 0.75] as [CGFloat] {
            h.addChildNode(SK.box(0.08, 0.08, 2.6, dark, at: SCNVector3(dx, -1.35, 0.1)))
        }
        let mast = SK.cylinder(0.1, 0.5, dark, at: SCNVector3(0, 1.25, 0))
        h.addChildNode(mast)
        let rotor = SCNNode()
        rotor.position = SCNVector3(0, 1.5, 0)
        for i in 0..<4 {
            let blade = SK.box(0.28, 0.03, 5.4, dark, at: SCNVector3(0, 0, 2.7))
            let arm = SCNNode(); arm.eulerAngles.y = CGFloat(i) * .pi / 2; arm.addChildNode(blade)
            rotor.addChildNode(arm)
        }
        // motion blur disc
        let disc = SCNNode(geometry: SCNCylinder(radius: 5.4, height: 0.01))
        disc.geometry?.materials = [SK.mat(NSColor(white: 0.1, alpha: 0.18), roughness: 1)]
        disc.geometry?.firstMaterial?.transparency = 0.18
        rotor.addChildNode(disc)
        rotor.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.18)))
        h.addChildNode(rotor)
        let beacon = SK.fireLight(intensity: 600, color: SK.rgb(0xFFF4E0), range: 40)
        beacon.position = SCNVector3(0, -1.6, 1.2)
        beacon.name = "searchlight"
        h.addChildNode(beacon)
        h.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.6, z: 0, duration: 1.6), .moveBy(x: 0, y: -0.6, z: 0, duration: 1.6)])))
        return h
    }

    private func makePlane() -> SCNNode {
        let p = SCNNode()
        let m = SK.mat(SK.rgb(0x6D7680), roughness: 0.5, metalness: 0.4)
        p.addChildNode(SK.node(SCNCapsule(capRadius: 0.6, height: 9), m))
        p.childNodes[0].eulerAngles.x = .pi / 2
        p.addChildNode(SK.box(14, 0.15, 1.6, m))
        p.addChildNode(SK.box(4, 0.12, 1.0, m, at: SCNVector3(0, 0, -3.8)))
        // circles high over the far side of the valley
        let orbit = SCNNode()
        orbit.position = SCNVector3(120, 260, -60)
        p.position = SCNVector3(160, 0, 0)
        p.eulerAngles.y = 0
        orbit.addChildNode(p)
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 70)))
        return orbit
    }

    // MARK: Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        // SOS: more of it is laid out as the signal grows; fresh snow hides it again
        let signal = s.v("signal", 5)
        let shown = Int((Double(sos.count) * max(0, min(1, (signal - 4) / 45))).rounded())
        for (i, b) in sos.enumerated() { b.isHidden = i >= shown }

        elt?.isHidden = !(s.has("elt_on") || s.done.contains("elt"))
        cargo?.isHidden = !(s.has("cargo_open") || s.done.contains("cargo"))

        if s.happened("avalanche") && avalancheDebris == nil {
            let blocks = SCNNode()
            let m = SK.mat(SK.rgb(0xE9EEF4), roughness: 0.75)
            for i in 0..<40 {
                let x = -16 + CGFloat(noise.value(Float(i) * 3.1, 1) * 18)
                let z = -16 + CGFloat(noise.value(Float(i) * 1.3, 7) * 11)
                let b = SK.rock(Float(0.4 + noise.value(Float(i), 2) * 0.9), m, seed: UInt64(100 + i))
                b.position = SCNVector3(x, ground(x, z) + 0.2, z)
                blocks.addChildNode(b)
            }
            world.addChildNode(blocks)
            avalancheDebris = blocks
        }

        // footprints toward the east ridge once someone sets out; cairns mark the explored route
        let route = s.v("route", 0)
        if (s.has("trek_started") || route > 0) && footprints.isEmpty {
            let m = SK.mat(SK.rgb(0xB9C4D2), roughness: 0.9)
            for i in 0..<70 {
                let t = CGFloat(i) / 70
                let x = 6 + t * 120, z = 2 + sin(t * 5) * 6 + CGFloat(i % 2) * 0.35
                let fp = SK.box(0.14, 0.02, 0.3, m, chamfer: 0.04)
                fp.position = SCNVector3(x, ground(x, z) + 0.01, z)
                fp.eulerAngles.y = .pi / 2
                world.addChildNode(fp)
                footprints.append(fp)
            }
            let stone = SK.noiseMat(SK.rgb(0x5E5B57), SK.rgb(0x3A3836), scale: 3, seed: 21)
            for i in 0..<6 {
                let x = 30 + CGFloat(i) * 22, z = 2 + sin(CGFloat(i) * 22 / 120 * 5) * 6
                let c = SCNNode()
                for k in 0..<3 {
                    let r = SK.rock(Float(0.35 - Double(k) * 0.08), stone, seed: UInt64(60 + i * 3 + k))
                    r.position.y = CGFloat(k) * 0.3
                    c.addChildNode(r)
                }
                c.position = SCNVector3(x, ground(x, z), z)
                world.addChildNode(c)
                cairns.append(c)
            }
        }
        for (i, c) in cairns.enumerated() { c.isHidden = Double(i) >= route / 100 * Double(cairns.count) }

        // a search plane far off; the rescue helicopter over the camp
        let planeNow = s.now("r_heli_pass")
        if planeNow && plane == nil { let p = makePlane(); world.addChildNode(p); plane = p }
        plane?.isHidden = !planeNow
        let heliNow = s.now("helicopter") || s.now("heli_return") || (s.ended && s.has("rescued"))
        if heliNow && helicopter == nil {
            let h = makeHelicopter()
            h.position = SCNVector3(-4, ground(-4, -16) + 9, -16)
            h.eulerAngles.y = 0.9
            world.addChildNode(h)
            helicopter = h
        }
        helicopter?.isHidden = !heliNow
        helicopter?.childNode(withName: "searchlight", recursively: true)?.isHidden = !s.isNight

        // people
        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: Spot.line(from: SCNVector3(7, 0, -5.5), to: SCNVector3(12, 0, -7.5), count: 9, facing: 1.2, y: ground))
    }

    private func spots(for s: SceneState) -> [Spot] {
        let storm = s.precip >= 1.5 || s.wind >= 45
        if storm {
            // sheltering in the open end of the fuselage
            return (0..<12).map { i in
                Spot(-0.6 - CGFloat(i / 3) * 1.1, ground(-0.6, -3) + 0.35, -3.9 + CGFloat(i % 3) * 0.85, facing: .pi / 2, pose: .huddled)
            }
        }
        if s.isNight || s.fireLit {
            return Spot.ring(SCNVector3(3.6, 0, 0.6), radius: 2.1, count: max(6, s.people.count), start: 0.6, y: ground)
        }
        // daytime: working around the wreck, the SOS, the snow-melting sheets
        let day: [(CGFloat, CGFloat, CGFloat)] = [
            (4.2, 2.0, 0.3), (2.0, -0.6, 1.9), (6.5, 3.8, 2.6), (-3.8, 1.6, 0.2),
            (0.6, 2.8, -0.6), (8.0, -0.8, -1.2), (3.2, 4.4, 2.8), (-7.5, 2.0, 1.0), (5.6, 0.6, -2.0)
        ]
        return day.map { Spot($0.0, ground($0.0, $0.1), $0.1, facing: $0.2) }
    }
}
