import SceneKit
import AppKit

/// 怒海 · 救生筏漂流 — an eight-person life raft adrift in the middle of the South China Sea,
/// August. No land anywhere; only swell, haze and whatever swims past.
///
/// Layout (metres, raft-local, y = 0 is the water line): the raft floats with its long axis along
/// x, a canopy awning over the aft half and the open foredeck turned toward the camera. `raft`
/// rides the swell, `tilt` rolls, and every piece of gear and every person hangs off `tilt`, so
/// nothing floats free of the raft. The floor sits just above the water line; the sea is an
/// `SK.water` surface with a flat deep layer underneath.
///
/// State shown: sea state and water colour (wind / weather), the awning pulled over in a squall,
/// bilge water and a sagging, deflated raft (`shelter`, `var.leak`), the sail (`project sail`),
/// the hand pump (`project desal`), flares / smoke / SART (`res.*`, `var.sartOn`), water and food
/// stores, the fishing line (`res.hooks`), the fish school and the sharks (`var.fish`, `var.shark`),
/// a booby / turtle / flying fish (events), the night watch and the lamp, the dead under covers,
/// and a ship, plane, bangka, basket boat or rescue ship on the horizon (events + flags).
final class AdriftScene: ScenarioScene {
    // MARK: - Raft shape (metres)

    private let tubeR: CGFloat = 1.24           // buoyancy tube centre-line radius
    private let tubeSX: CGFloat = 1.08          // the ring is an oval: 3.2 m x 2.6 m outside
    private let tubeSZ: CGFloat = 0.86
    private let tubePipe: CGFloat = 0.25
    private let tubeLowY: CGFloat = -0.06       // lower tube sits half in the water
    private let tubeUpY: CGFloat = 0.72         // upper tube
    private let tubeTop: CGFloat = 0.97         // top of the upper tube (0.72 + pipe)
    private let deckY: CGFloat = 0.16           // floor, just above the water line
    private let seatDrop: CGFloat = 0.40        // SK's sitting pose has its seat 0.40 above the root

    // MARK: - World

    private let noise = SK.Noise(seed: 8081)
    private let raft = SCNNode()                // rides the swell
    private let tilt = SCNNode()                // rolls and pitches
    private var seaMat: SCNMaterial?
    private var deepSea: SCNNode?
    private var surfaceAmp: Float = 0.16
    private var foam: SCNNode?

    // raft parts whose look follows the state
    private var tubeNodes: [SCNNode] = []
    private var canopyNode: SCNNode?
    private var bilgeNode: SCNNode?
    private var canopyCover: CGFloat = -1

    // gear
    private var sailNode: SCNNode?
    private var sailCloth: SCNNode?
    private var pumpNode: SCNNode?
    private var desalBottles: SCNNode?
    private var flareBox: SCNNode?
    private var smokeCans: SCNNode?
    private var sartNode: SCNNode?
    private var fishLine: SCNNode?
    private var waterCans: SCNNode?
    private var catchFish: SCNNode?
    private var lampLight: SK.FlickerLight?
    private var mastLight: SCNNode?
    private var lampBulb: SCNNode?

    // life
    private var sharkFin: SCNNode?
    private var sharks: [SCNNode] = []
    private var fishSchool: SCNNode?
    private var flyingFish: SCNNode?
    private var booby: SCNNode?
    private var turtle: SCNNode?
    private var gulls: SCNNode?

    // far away
    private var shipNode: SCNNode?
    private var planeNode: SCNNode?
    private var bangkaNode: SCNNode?
    private var basketNode: SCNNode?
    private var rigNode: SCNNode?
    private var flareNode: SCNNode?

    required init() {
        super.init()
        skyStyle = .sea
        sunPeak = 84                        // 15°N in August: the sun stands almost overhead at noon
        sunAzimuth = 150                    // light comes from behind the camera: the raft is lit
        exposure = -0.45                    // a tropical sea is blindingly bright
        sunScale = 0.95
        hazeColor = SK.rgb(0xA7BEC6)        // marine haze: distant water pales into it
        stormColor = SK.rgb(0x8B979C)
        nightColor = SK.rgb(0x060B12)
        clearVisibility = 950               // hazy horizon, but the raft still looks alone
        weatherArea = 150
        weatherCenter = SCNVector3(0, 26, 0)
        precipKind = .rain                  // it never snows here
        cameraTarget = SCNVector3(0, 1.0, 0)
        cameraDistance = 13.0
        cameraYaw = 26
        cameraPitch = 12
        cameraFOV = 44
        minPitch = 2
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        buildSea()
        buildRaft()
        buildGear()
        buildLife()
        buildDistant()
    }

    /// The open sea: a wavy surface the raft floats on, and a flat deep layer below it that
    /// shows through the surface and carries on past its edge into the haze. Never any land.
    private func buildSea() {
        let deep = SK.water(size: 6000, color: SK.rgb(0x0E3440), amplitude: 0.05, choppiness: 0.15,
                            transparency: 1, roughness: 0.28, segments: 8)
        deep.position.y = -0.7
        world.addChildNode(deep)
        deepSea = deep

        let surf = SK.water(size: 1200, color: SK.rgb(0x2E7079), amplitude: surfaceAmp, choppiness: 0.42,
                            transparency: 0.94, roughness: 0.1, segments: 200)
        surf.name = "sea"
        seaMat = surf.geometry?.firstMaterial
        world.addChildNode(surf)
    }

    /// Two buoyancy tubes, the fabric wall between them, the floor, the bilge, the awning on its
    /// hoop, grab ropes, reflective tape, a collar of foam and the two oars.
    private func buildRaft() {
        raft.position = SCNVector3(0, 0.02, 0)
        raft.eulerAngles.y = -0.50                  // the awning opening turned toward the camera
        raft.addChildNode(tilt)
        world.addChildNode(raft)

        // slow ride on the swell; the roll lives on `tilt` so both can run at once
        let bob = SCNAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.13, z: 0, duration: 2.6),
            .moveBy(x: 0, y: -0.13, z: 0, duration: 2.6)]))
        bob.timingMode = .easeInEaseOut
        raft.runAction(bob)
        let roll = SCNAction.repeatForever(.sequence([
            .rotateBy(x: 0.02, y: 0, z: 0.05, duration: 3.4),
            .rotateBy(x: -0.02, y: 0, z: -0.05, duration: 3.4)]))
        roll.timingMode = .easeInEaseOut
        tilt.runAction(roll)

        // --- buoyancy tubes (orange-red rubberised fabric, like the real thing)
        let buoy = SK.noiseMat(SK.rgb(0xE0521F), SK.rgb(0xC4441A), scale: 3, roughness: 0.6, seed: 9)
        let wallMat = SK.mat(SK.rgb(0xB8401A), roughness: 0.78)
        for y in [tubeLowY, tubeUpY] {
            let n = SCNNode(geometry: SCNTorus(ringRadius: tubeR, pipeRadius: tubePipe))
            n.geometry?.materials = [buoy]
            n.scale = SCNVector3(tubeSX, 1, tubeSZ)
            n.position.y = y
            tilt.addChildNode(n)
            tubeNodes.append(n)
        }
        // the fabric wall between the tubes (the inside of the raft)
        let wall = SCNNode(geometry: SCNTube(innerRadius: tubeR - 0.06, outerRadius: tubeR + 0.01, height: 0.34))
        wall.geometry?.materials = [wallMat, wallMat, wallMat, wallMat]
        wall.scale = SCNVector3(tubeSX, 1, tubeSZ)
        wall.position.y = 0.33
        tilt.addChildNode(wall)

        // --- floor, seen from above through the open foredeck and the awning mouth
        let deck = SK.cylinder(tubeR - 0.03, 0.06, SK.mat(SK.rgb(0x4B525A), roughness: 0.9))
        deck.scale = SCNVector3(tubeSX, 1, tubeSZ)
        deck.position.y = deckY - 0.03
        tilt.addChildNode(deck)

        // --- bilge water sloshing on the floor (rises with the leak and the weather)
        let bilgeMat = SK.mat(SK.rgb(0x27565F), roughness: 0.06)
        bilgeMat.transparency = 0.6
        let bilge = SK.cylinder(tubeR - 0.12, 0.012, bilgeMat)
        bilge.scale = SCNVector3(tubeSX, 1, tubeSZ)
        bilge.position.y = deckY + 0.006
        tilt.addChildNode(bilge)
        bilgeNode = bilge

        // --- grab rope round the lower tube, with four handles
        let rope = SCNNode(geometry: SCNTorus(ringRadius: tubeR + tubePipe - 0.015, pipeRadius: 0.016))
        rope.geometry?.materials = [SK.mat(SK.rgb(0xD9D2BE), roughness: 0.95)]
        rope.scale = SCNVector3(tubeSX, 1, tubeSZ)
        rope.position.y = tubeLowY
        tilt.addChildNode(rope)
        for i in 0..<4 {
            let t = CGFloat(i) * .pi / 2 + 0.5
            let p = ring(t)
            tilt.addChildNode(SK.sphere(0.075, SK.mat(SK.rgb(0xCFC7B2), roughness: 0.9),
                                        at: SCNVector3(p.x, tubeLowY, p.z)))
        }
        // reflective tape on top of the upper tube (a life raft is meant to be seen from the air)
        let tape = SK.mat(SK.rgb(0xE8EDF2), roughness: 0.25, metalness: 0.6)
        for t in [CGFloat(0.6), 1.8, 3.2, 4.6] {
            let p = ring(t)
            let patch = SK.box(0.36, 0.02, 0.16, tape, chamfer: 0.01, at: SCNVector3(p.x, tubeUpY + 0.24, p.z))
            patch.eulerAngles.y = t
            tilt.addChildNode(patch)
        }
        // --- a collar of foam where the raft works at the surface
        let collar = SCNNode(geometry: SCNTorus(ringRadius: tubeR + tubePipe + 0.06, pipeRadius: 0.035))
        collar.geometry?.materials = [SK.mat(SK.rgb(0xEAF3F5), roughness: 0.9)]
        collar.scale = SCNVector3(tubeSX, 0.35, tubeSZ)
        collar.position.y = 0.0
        collar.geometry?.firstMaterial?.transparency = 0.10
        collar.castsShadow = false
        tilt.addChildNode(collar)
        foam = collar

        // --- awning: a half-shell over the aft half, open toward the bow. The pivot stretches
        //     along x (furled back in fine weather, pulled right over the raft when it blows).
        let cloth = SK.noiseMat(SK.rgb(0xF07A2A), SK.rgb(0xD25F1E), scale: 2.5, roughness: 0.88, seed: 31)
        let shell = SCNNode(geometry: SCNTube(innerRadius: 0.96, outerRadius: 1.0, height: 1.0))
        shell.geometry?.materials = [cloth, cloth, cloth, cloth]
        shell.eulerAngles.z = .pi / 2
        shell.scale = SCNVector3(0.80, 1, 0.94)     // world: 0.80 m tall, 0.94 m to each side
        let pivot = SCNNode()
        pivot.addChildNode(shell)
        pivot.position = SCNVector3(0, 0.55, 0)
        tilt.addChildNode(pivot)
        canopyNode = pivot
        // a hoop rib showing through the cloth, and the lashing at the mouth
        let rib = SCNNode(geometry: SCNTorus(ringRadius: 1.0, pipeRadius: 0.03))
        rib.geometry?.materials = [SK.mat(SK.rgb(0x8E4A22), roughness: 0.8)]
        rib.eulerAngles.z = .pi / 2
        rib.scale = SCNVector3(0.80, 1, 0.94)
        pivot.addChildNode(rib)
        setCanopy(cover: 0)                         // furled back over the aft half to begin with

        // --- two oars lying along the tube tops (they become the mast when a sail is rigged)
        let wood = SK.mat(SK.rgb(0xC7A672), roughness: 0.8)
        for (z, flip) in [(1.12, CGFloat(1)), (-1.12, CGFloat(-1))] {
            let oar = SCNNode()
            let shaft = SK.cylinder(0.035, 1.9, wood)
            shaft.eulerAngles.z = .pi / 2
            oar.addChildNode(shaft)
            oar.addChildNode(SK.box(0.30, 0.02, 0.13, wood, chamfer: 0.01, at: SCNVector3(-1.0, 0, 0)))
            oar.position = SCNVector3(-0.15, tubeTop + 0.05, z)
            oar.eulerAngles = SCNVector3(0, 0.06 * flip, 0.04 * flip)
            tilt.addChildNode(oar)
        }

        // --- sea anchor: a rope trailing off the stern with a couple of floats
        let lineMat = SK.mat(SK.rgb(0xCFC7B2), roughness: 0.95)
        let rode = SK.cylinder(0.014, 6.4, lineMat)
        rode.eulerAngles = SCNVector3(0, -0.12, .pi / 2)
        rode.position = SCNVector3(-4.6, 0.10, 0.45)
        tilt.addChildNode(rode)
        for (x, r) in [(-6.2, 0.19), (-7.6, 0.15)] as [(CGFloat, CGFloat)] {
            tilt.addChildNode(SK.sphere(r, SK.mat(SK.rgb(0xE2621F), roughness: 0.5), at: SCNVector3(x, 0.04, 0.5)))
        }
    }

    /// A point on the buoyancy tube's centre-line, `t` radians round the ring.
    private func ring(_ t: CGFloat) -> (x: CGFloat, z: CGFloat) {
        (tubeR * tubeSX * cos(t), tubeR * tubeSZ * sin(t))
    }

    // MARK: - Gear

    private func buildGear() {
        let metal = SK.mat(SK.rgb(0x9AA2AA), roughness: 0.35, metalness: 0.7)
        let plastic = SK.mat(SK.rgb(0xE8E2D2), roughness: 0.5)
        let blue = SK.mat(SK.rgb(0x2E6FA8), roughness: 0.45)

        // water: two jerry cans and the bag that hangs from the ridge
        let cans = SCNNode()
        for (x, z, rot) in [(0.05, -0.72, 0.2), (-0.32, -0.78, -0.3)] as [(CGFloat, CGFloat, CGFloat)] {
            let can = SK.box(0.28, 0.38, 0.19, blue, chamfer: 0.03)
            can.position = SCNVector3(x, deckY + 0.19, z)
            can.eulerAngles.y = rot
            cans.addChildNode(can)
            cans.addChildNode(SK.cylinder(0.04, 0.06, plastic, at: SCNVector3(x + 0.07, deckY + 0.41, z)))
        }
        tilt.addChildNode(cans)
        waterCans = cans

        let bag = SCNNode()
        let sack = SK.sphere(0.16, SK.mat(SK.rgb(0xD8E2E6), roughness: 0.35))
        sack.scale = SCNVector3(1, 1.3, 0.7)
        sack.position = SCNVector3(-0.15, 0.98, -0.40)
        bag.addChildNode(sack)
        bag.addChildNode(SK.cylinder(0.008, 0.30, SK.mat(SK.rgb(0x8A8577), roughness: 0.9),
                                     at: SCNVector3(-0.15, 1.16, -0.40)))
        bag.addChildNode(SK.cylinder(0.02, 0.12, plastic, at: SCNVector3(-0.15, 0.76, -0.40)))
        tilt.addChildNode(bag)

        // food crate with a few cans and a signal mirror
        let crate = SK.box(0.46, 0.30, 0.34, SK.mat(SK.rgb(0xB99A6B), roughness: 0.85), chamfer: 0.02)
        crate.position = SCNVector3(-0.72, deckY + 0.15, -0.62)
        crate.eulerAngles.y = 0.35
        tilt.addChildNode(crate)
        for i in 0..<3 {
            let can = SK.cylinder(0.07, 0.19, i == 1 ? SK.mat(SK.rgb(0xC0C4C8), roughness: 0.3, metalness: 0.6) : metal)
            can.position = SCNVector3(-0.44 + CGFloat(i) * 0.17, deckY + 0.1, -0.72)
            tilt.addChildNode(can)
        }
        let mirror = SK.box(0.13, 0.09, 0.01, SK.mat(SK.rgb(0xE8ECEF), roughness: 0.05, metalness: 1.0),
                            at: SCNVector3(-0.72, deckY + 0.31, -0.62))
        mirror.eulerAngles = SCNVector3(0, 0.5, 0.2)
        tilt.addChildNode(mirror)

        // bailer
        let bailer = SK.cylinder(0.10, 0.22, plastic)
        bailer.position = SCNVector3(-0.10, deckY + 0.11, 0.72)
        tilt.addChildNode(bailer)
        tilt.addChildNode(SK.box(0.22, 0.02, 0.03, plastic, at: SCNVector3(-0.10, deckY + 0.24, 0.72)))

        // flares + smoke, in an open box on the port side
        let box = SK.box(0.34, 0.15, 0.24, SK.mat(SK.rgb(0xD9D3C4), roughness: 0.6), chamfer: 0.02)
        box.position = SCNVector3(-1.0, deckY + 0.08, 0.30)
        box.eulerAngles.y = -0.2
        tilt.addChildNode(box)
        flareBox = box
        let flares = SCNNode()
        for i in 0..<4 {
            let f = SK.cylinder(0.026, 0.28, SK.mat(SK.rgb(0xC0392B), roughness: 0.5))
            f.position = SCNVector3(-1.08 + CGFloat(i % 2) * 0.10, deckY + 0.27, 0.30 + CGFloat(i / 2) * 0.09)
            f.eulerAngles.z = 0.1 * CGFloat(i % 3)
            flares.addChildNode(f)
        }
        tilt.addChildNode(flares)
        let smoke = SCNNode()
        for i in 0..<2 {
            let c = SK.cylinder(0.045, 0.20, SK.mat(SK.rgb(0xE08A2A), roughness: 0.6))
            c.position = SCNVector3(-0.98 + CGFloat(i) * 0.12, deckY + 0.10, 0.52)
            smoke.addChildNode(c)
        }
        tilt.addChildNode(smoke)
        smokeCans = smoke

        // hand pump for the desalinator (only out once somebody starts on it)
        let pump = SCNNode()
        pump.addChildNode(SK.box(0.40, 0.17, 0.24, SK.mat(SK.rgb(0x37474F), roughness: 0.4, metalness: 0.3),
                                 at: SCNVector3(-0.25, deckY + 0.09, -0.30)))
        let lever = SK.box(0.46, 0.03, 0.05, metal, at: SCNVector3(-0.25, deckY + 0.28, -0.16))
        lever.eulerAngles = SCNVector3(0, 0, 0.32)
        pump.addChildNode(lever)
        let hose = SK.cylinder(0.022, 0.44, plastic, at: SCNVector3(-0.03, deckY + 0.05, -0.42))
        hose.eulerAngles.x = 0.7
        pump.addChildNode(hose)
        pump.addChildNode(SK.cylinder(0.05, 0.17, SK.mat(SK.rgb(0xCFE3EA), roughness: 0.2),
                                      at: SCNVector3(0.10, deckY + 0.09, -0.42)))
        let bottles = SCNNode()                                  // fresh water, once the filter runs
        for i in 0..<3 {
            bottles.addChildNode(SK.cylinder(0.048, 0.19, SK.mat(SK.rgb(0xD6E8EE), roughness: 0.15),
                                             at: SCNVector3(0.34 + CGFloat(i % 2) * 0.12, deckY + 0.1,
                                                            -0.30 - CGFloat(i / 2) * 0.13)))
        }
        bottles.isHidden = true
        pump.addChildNode(bottles)
        desalBottles = bottles
        pump.isHidden = true
        tilt.addChildNode(pump)
        pumpNode = pump

        // SART on a short pole at the port quarter (the battery only lasts a few days)
        let sart = SCNNode()
        sart.addChildNode(SK.cylinder(0.018, 0.9, metal, at: SCNVector3(-1.32, 0.75, -0.98)))
        sart.addChildNode(SK.cylinder(0.05, 0.32, SK.mat(SK.rgb(0xE8C33A), roughness: 0.4),
                                      at: SCNVector3(-1.32, 1.30, -0.98)))
        let blip = SK.sphere(0.03, SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xFF3B1E)),
                             at: SCNVector3(-1.32, 1.49, -0.98))
        blip.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05), .wait(duration: 0.5),
                                                 .fadeOpacity(to: 0.1, duration: 0.05), .wait(duration: 1.2)])))
        sart.addChildNode(blip)
        sart.isHidden = true
        tilt.addChildNode(sart)
        sartNode = sart

        // fishing: a bamboo rod over the starboard bow with a line into the water
        let rod = SCNNode()
        let bamboo = SK.cylinder(0.022, 2.4, SK.mat(SK.rgb(0xC9B27A), roughness: 0.85))
        bamboo.eulerAngles = SCNVector3(1.05, 0, 0)
        bamboo.position = SCNVector3(1.05, 1.05, 1.35)
        rod.addChildNode(bamboo)
        rod.addChildNode(SK.cylinder(0.006, 1.5, SK.mat(SK.rgb(0xE4E8EA), roughness: 0.4),
                                     at: SCNVector3(1.05, 0.75, 2.45)))
        rod.addChildNode(SK.sphere(0.055, SK.mat(SK.rgb(0xE04A28), roughness: 0.4), at: SCNVector3(1.05, 0.03, 2.45)))
        tilt.addChildNode(rod)
        fishLine = rod

        // what the line brought in: a couple of fish on the deck, fillets drying on a line
        let gear = SCNNode()
        for i in 0..<3 {
            let f = fishBody(length: 0.40, girth: 0.10, color: SK.rgb(0x9FB0BC))
            f.position = SCNVector3(0.80 - CGFloat(i) * 0.15, deckY + 0.06, 0.62 + CGFloat(i % 2) * 0.13)
            f.eulerAngles.y = 0.4 * CGFloat(i) - 0.3
            gear.addChildNode(f)
        }
        let strip = SK.cylinder(0.006, 1.3, SK.mat(SK.rgb(0xD8D2BE), roughness: 0.95))
        strip.eulerAngles.z = .pi / 2
        strip.position = SCNVector3(-0.45, 1.30, 0.62)
        gear.addChildNode(strip)
        for i in 0..<3 {
            let fillet = SK.box(0.08, 0.20, 0.02, SK.mat(SK.rgb(0xC98A4B), roughness: 0.7),
                                at: SCNVector3(-0.85 + CGFloat(i) * 0.40, 1.20, 0.62))
            fillet.eulerAngles.x = 0.1
            gear.addChildNode(fillet)
        }
        gear.isHidden = true
        tilt.addChildNode(gear)
        catchFish = gear

        // sail: two spars and a tarpaulin, once the crew has cut one out of the awning
        let sail = SCNNode()
        let sparMat = SK.mat(SK.rgb(0xC7A672), roughness: 0.8)
        for (x, z, rot) in [(-0.95, 0.72, 0.0), (-1.00, -0.72, 0.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let spar = SK.cylinder(0.045, 2.5, sparMat)
            spar.position = SCNVector3(x, 1.25, z)
            spar.eulerAngles = SCNVector3(0.05, rot, 0.06)
            sail.addChildNode(spar)
        }
        let sheet = SCNNode()
        sheet.addChildNode(SK.box(1.42, 1.30, 0.02, SK.mat(SK.rgb(0xFBF3E2), roughness: 0.7, doubleSided: true)))
        sheet.position = SCNVector3(-0.60, 1.45, 0.0)
        sheet.eulerAngles = SCNVector3(0.06, 1.35, -0.05)
        sail.addChildNode(sheet)
        sail.isHidden = true
        tilt.addChildNode(sail)
        sailNode = sail
        sailCloth = sheet

        // an all-round white light on a short mast at the stern: how a raft is seen at night
        let mast = SCNNode()
        mast.addChildNode(SK.cylinder(0.02, 1.15, metal, at: SCNVector3(-1.30, 1.30, -0.75)))
        let lampMat = SK.mat(.black, roughness: 0.25, emission: SK.rgb(0xEAF2FF))
        lampMat.emission.intensity = 2.5
        let allRound = SK.sphere(0.055, lampMat, at: SCNVector3(-1.30, 1.92, -0.75))
        mast.addChildNode(allRound)
        mast.isHidden = true
        tilt.addChildNode(mast)
        mastLight = mast

        // lamp under the awning: the only light at night
        let bulb = SK.sphere(0.05, SK.mat(SK.rgb(0xFFF0CF), roughness: 0.2, emission: SK.rgb(0xFFC46A)),
                             at: SCNVector3(-0.3, 1.34, 0.15))
        tilt.addChildNode(bulb)
        lampBulb = bulb
        let light = SK.fireLight(intensity: 65, color: SK.rgb(0xFFC077), range: 4.2)
        light.position = SCNVector3(-0.3, 1.28, 0.15)
        light.isHidden = true
        tilt.addChildNode(light)
        lampLight = light
    }

    // MARK: - Life

    /// A shark fin, with the dark shape of its back just under the surface.
    private func finNode() -> SCNNode {
        let n = SCNNode()
        let g = SK.mesh([SIMD3(0, 0, -0.22), SIMD3(0, 0, 0.17), SIMD3(0, 0.40, 0.09)], [0, 2, 1])
        let fin = SCNNode(geometry: g)
        fin.geometry?.materials = [SK.mat(SK.rgb(0x1B2226), roughness: 0.85, doubleSided: true)]
        n.addChildNode(fin)
        return n
    }

    private func fishBody(length: CGFloat, girth: CGFloat, color: NSColor) -> SCNNode {
        let n = SCNNode()
        let body = SK.sphere(girth, SK.mat(color, roughness: 0.35, metalness: 0.25))
        body.scale = SCNVector3(0.55, 0.8, length / girth)
        n.addChildNode(body)
        let tail = SK.mesh([SIMD3(0, 0.05, 0.45), SIMD3(0, 0.13, 0.88), SIMD3(0, -0.06, 0.88)], [0, 1, 2])
        let t = SCNNode(geometry: tail)
        t.geometry?.materials = [SK.mat(color, roughness: 0.5, doubleSided: true)]
        n.addChildNode(t)
        return n
    }

    private func buildLife() {
        // the sharks themselves are added and removed in `apply`, one fin each
        sharkFin = finNode()

        // fish school just under the raft, and a few flying fish skimming past
        let school = SCNNode()
        for i in 0..<14 {
            let t = CGFloat(i) / 14 * 2 * .pi
            let r = 1.1 + CGFloat(noise.value(Float(i) * 1.7, 3.1)) * 1.1
            let f = fishBody(length: 0.30, girth: 0.07, color: SK.rgb(0x3C5A66))
            f.position = SCNVector3(cos(t) * r, -0.75 - CGFloat(i % 3) * 0.1, sin(t) * r * 0.85)
            f.eulerAngles.y = -t
            school.addChildNode(f)
        }
        school.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 26)))
        school.isHidden = true
        world.addChildNode(school)
        fishSchool = school

        let flying = SCNNode()
        for i in 0..<3 {
            let f = fishBody(length: 0.34, girth: 0.06, color: SK.rgb(0x93A8B6))
            for s in [-1, 1] as [CGFloat] {
                let wing = SK.box(0.28, 0.01, 0.09, SK.mat(SK.rgb(0xB8C8D4), roughness: 0.4, doubleSided: true),
                                  at: SCNVector3(s * 0.16, 0.02, -0.02))
                wing.eulerAngles.y = s * 0.3
                f.addChildNode(wing)
            }
            f.position = SCNVector3(3.6 + CGFloat(i) * 1.2, 1.05 + CGFloat(i % 2) * 0.45, -4.4 - CGFloat(i) * 1.1)
            f.eulerAngles = SCNVector3(0, -1.2, -0.35)
            flying.addChildNode(f)
        }
        flying.isHidden = true
        world.addChildNode(flying)
        flyingFish = flying

        // a booby that lands on the awning, and a turtle bumping the tube
        let bird = SCNNode()
        let body = SK.sphere(0.13, SK.mat(SK.rgb(0xE6E1D4), roughness: 0.8))
        body.scale = SCNVector3(0.75, 0.85, 1.5)
        body.position = SCNVector3(0, 0.13, 0)
        bird.addChildNode(body)
        bird.addChildNode(SK.sphere(0.08, SK.mat(SK.rgb(0xEDE8DC), roughness: 0.8), at: SCNVector3(0, 0.28, 0.16)))
        let beak = SK.node(SCNCone(topRadius: 0.005, bottomRadius: 0.022, height: 0.12),
                           SK.mat(SK.rgb(0x2A2C2E), roughness: 0.5))
        beak.position = SCNVector3(0, 0.27, 0.27)
        beak.eulerAngles.x = .pi / 2
        bird.addChildNode(beak)
        for s in [-1, 1] as [CGFloat] {
            let wing = SK.box(0.1, 0.02, 0.34, SK.mat(SK.rgb(0x3B3F44), roughness: 0.8, doubleSided: true),
                              at: SCNVector3(s * 0.12, 0.14, -0.02))
            wing.eulerAngles.z = s * 0.2
            bird.addChildNode(wing)
        }
        bird.position = SCNVector3(-0.55, 1.62, 0.12)
        bird.eulerAngles.y = 0.5
        bird.isHidden = true
        tilt.addChildNode(bird)
        booby = bird

        let tur = SCNNode()
        let shell = SK.sphere(0.40, SK.mat(SK.rgb(0x4E5A46), roughness: 0.85))
        shell.scale = SCNVector3(1, 0.45, 1.1)
        shell.position = SCNVector3(0, 0.05, 0)
        tur.addChildNode(shell)
        tur.addChildNode(SK.sphere(0.11, SK.mat(SK.rgb(0x6B7458), roughness: 0.8), at: SCNVector3(0, 0.06, 0.44)))
        tur.position = SCNVector3(2.5, -0.06, 0.9)
        tur.isHidden = true
        world.addChildNode(tur)
        turtle = tur

        // two seabirds working the far water
        let g = SCNNode()
        for i in 0..<3 {
            let b = SCNNode()
            for s in [-1, 1] as [CGFloat] {
                let w = SK.box(0.9, 0.02, 0.16, SK.mat(SK.rgb(0x50565C), roughness: 0.8, doubleSided: true),
                               at: SCNVector3(s * 0.5, 0, 0))
                w.eulerAngles.z = s * 0.25
                b.addChildNode(w)
            }
            b.position = SCNVector3(-40 - CGFloat(i) * 25, 18 + CGFloat(i) * 6, -70 - CGFloat(i) * 32)
            b.eulerAngles.y = CGFloat(i) * 1.1
            g.addChildNode(b)
        }
        g.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)))
        world.addChildNode(g)
        gulls = g
    }

    // MARK: - Far away

    /// A cargo ship (also stands in for the rescue ship — same hull, brought close).
    private func makeShip(scale k: CGFloat, rescue: Bool) -> SCNNode {
        let n = SCNNode()
        let hullMat = SK.mat(rescue ? SK.rgb(0x6A7681) : SK.rgb(0x2E3A44), roughness: 0.6)
        let deckMat = SK.mat(rescue ? SK.rgb(0x59646E) : SK.rgb(0x3A4A55), roughness: 0.7)
        let white = SK.mat(rescue ? SK.rgb(0xAFB8BE) : SK.rgb(0x8E979D), roughness: 0.5)
        let hull = SK.box(6, 3.2, 46 * k, hullMat, chamfer: 0.3)
        hull.position = SCNVector3(0, 0.4, 0)
        n.addChildNode(hull)
        let bow = SK.node(SCNCone(topRadius: 0.2, bottomRadius: 3, height: 5), hullMat)
        bow.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        bow.position = SCNVector3(0, 0.4, -23 * k)
        bow.scale = SCNVector3(2, 1, 1)
        n.addChildNode(bow)
        n.addChildNode(SK.box(6.2, 0.4, 44 * k, deckMat, at: SCNVector3(0, 2.2, 0)))
        for i in 0..<5 {                                  // container stacks
            let c = SK.box(2.4, 1.6, 4.5 * k, i % 2 == 0 ? SK.mat(SK.rgb(0x8A4B3A), roughness: 0.8)
                                                          : SK.mat(SK.rgb(0x3F6B7A), roughness: 0.8),
                           chamfer: 0.05)
            c.position = SCNVector3(CGFloat(i % 2) * 3 - 1.5, 3.2, CGFloat(i) * 7 * k - 12 * k)
            c.eulerAngles.y = 0.02 * CGFloat(i)
            n.addChildNode(c)
        }
        let house = SK.box(5, 7, 6 * k, white, chamfer: 0.1)
        house.position = SCNVector3(0, 5.6, 18 * k)
        n.addChildNode(house)
        n.addChildNode(SK.box(6.4, 1.2, 5 * k, white, at: SCNVector3(0, 9.4, 18 * k)))
        n.addChildNode(SK.cylinder(0.9, 4, SK.mat(SK.rgb(0x24303A), roughness: 0.6), at: SCNVector3(0, 11, 21 * k)))
        n.addChildNode(SK.cylinder(0.15, 8, white, at: SCNVector3(0, 12, 10 * k)))
        n.addChildNode(SK.box(3, 0.15, 0.15, white, at: SCNVector3(0, 13.5, 10 * k)))
        return n
    }

    private func shipLights(_ y: CGFloat) -> SCNNode {
        let g = SCNNode()
        func lamp(_ p: SCNVector3, _ c: NSColor) {
            let m = SK.mat(.black, roughness: 0.2, emission: c)
            m.emission.intensity = 3
            g.addChildNode(SK.sphere(0.55, m, at: p))
        }
        lamp(SCNVector3(0, y + 3, 0), SK.rgb(0xFFF3D8))          // masthead
        lamp(SCNVector3(-2.6, y - 1.4, 0), SK.rgb(0xFF4A3A))     // port
        lamp(SCNVector3(2.6, y - 1.4, 0), SK.rgb(0x5BE07A))      // starboard
        for i in 0..<5 {                                        // deck lights along the length
            lamp(SCNVector3(0, y - 1.2, CGFloat(i) * 9 - 18), SK.rgb(0xFFE9BE))
        }
        return g
    }

    private func buildDistant() {
        // a ship passing well outside the raft: on the horizon, hazed, never coming closer
        let ship = makeShip(scale: 1.25, rescue: false)
        ship.position = SCNVector3(-360, 0, -430)
        ship.eulerAngles.y = 1.1
        ship.addChildNode(shipLights(6))
        ship.isHidden = true
        world.addChildNode(ship)
        shipNode = ship

        // a search aircraft, high and far
        let plane = SCNNode()
        let body = SK.node(SCNCapsule(capRadius: 0.9, height: 9), SK.mat(SK.rgb(0xC9CFD4), roughness: 0.5))
        body.eulerAngles.x = .pi / 2
        plane.addChildNode(body)
        plane.addChildNode(SK.box(17, 0.25, 2.4, SK.mat(SK.rgb(0xD6DBDF), roughness: 0.5)))
        plane.addChildNode(SK.box(1.2, 0.2, 4, SK.mat(SK.rgb(0xD6DBDF), roughness: 0.5), at: SCNVector3(0, 0.4, -4.6)))
        plane.addChildNode(SK.box(0.3, 2.4, 1.6, SK.mat(SK.rgb(0xD6DBDF), roughness: 0.5), at: SCNVector3(0, 1.2, -4.6)))
        for x in [-5.5, 5.5] as [CGFloat] {
            plane.addChildNode(SK.cylinder(0.9, 3, SK.mat(SK.rgb(0x9BA2A8), roughness: 0.4), at: SCNVector3(x, -0.4, 1.4)))
        }
        plane.position = SCNVector3(-330, 240, -520)
        plane.eulerAngles = SCNVector3(0.1, 0.8, 0.15)
        plane.isHidden = true
        world.addChildNode(plane)
        planeNode = plane

        // a Philippine bangka: a narrow hull on bamboo outriggers
        let bangka = SCNNode()
        let hull = SK.box(1.6, 0.9, 9, SK.mat(SK.rgb(0x2F5D7A), roughness: 0.7), chamfer: 0.25)
        hull.position.y = 0.25
        bangka.addChildNode(hull)
        bangka.addChildNode(SK.box(1.3, 0.5, 2.6, SK.mat(SK.rgb(0xD8D2C0), roughness: 0.8), at: SCNVector3(0, 1.0, 1.6)))
        for s in [-1, 1] as [CGFloat] {
            for z in [-2.6, 1.2] as [CGFloat] {
                let arm = SK.box(2.4, 0.1, 0.1, SK.mat(SK.rgb(0x8A6B45), roughness: 0.9), at: SCNVector3(s * 1.8, 0.75, z))
                arm.eulerAngles.z = s * -0.12
                bangka.addChildNode(arm)
            }
            let float = SK.cylinder(0.16, 6.5, SK.mat(SK.rgb(0xC9A86B), roughness: 0.9))
            float.eulerAngles.x = .pi / 2
            float.position = SCNVector3(s * 3.0, 0.05, -0.6)
            bangka.addChildNode(float)
        }
        bangka.position = SCNVector3(26, 0, -30)
        bangka.eulerAngles.y = 0.7
        bangka.isHidden = true
        world.addChildNode(bangka)
        bangkaNode = bangka

        // a Vietnamese basket boat, drifting just off the bow
        let basket = SCNNode()
        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.85, pipeRadius: 0.12))
        rim.geometry?.materials = [SK.mat(SK.rgb(0xB08A52), roughness: 0.9)]
        basket.addChildNode(rim)
        let bowl = SK.sphere(0.85, SK.mat(SK.rgb(0xC7A26B), roughness: 0.9))
        bowl.scale = SCNVector3(1, 0.45, 1)
        bowl.position.y = -0.30
        basket.addChildNode(bowl)
        basket.position = SCNVector3(-7.5, 0.12, -9.5)
        basket.isHidden = true
        world.addChildNode(basket)
        basketNode = basket

        // squid boats working the horizon: a whole city of lights that never comes closer
        let rig = SCNNode()
        for i in 0..<26 {
            let a = CGFloat(noise.value(Float(i) * 3.3, 7.7))
            let b = CGFloat(noise.value(Float(i) * 1.9, 2.2))
            let m = SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xFFF6DF))
            m.emission.intensity = 4
            rig.addChildNode(SK.sphere(0.9, m, at: SCNVector3(-180 + a * 130, 1.2 + b * 3, -420 - b * 90)))
        }
        rig.isHidden = true
        world.addChildNode(rig)
        rigNode = rig

        // a rocket parachute flare, climbing away from the raft
        let flare = SCNNode()
        let m = SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xFF2A12))
        m.emission.intensity = 6
        let star = SK.sphere(0.85, m)
        star.castsShadow = false
        flare.addChildNode(star)
        flare.addChildNode(SK.fireLight(intensity: 900, color: SK.rgb(0xFF3A1A), range: 60))
        let smokeMat = SK.mat(SK.rgb(0xF1F3F4), roughness: 1)
        smokeMat.transparency = 0.16
        for i in 0..<7 {                                    // the smoke trail it leaves behind
            let k = CGFloat(i)
            let puff = SK.sphere(0.40 + k * 0.16, smokeMat, at: SCNVector3(k * 1.6 - 2.0, -4 - k * 3.2, k * 0.9))
            puff.castsShadow = false
            flare.addChildNode(puff)
        }
        flare.castsShadow = false
        flare.position = SCNVector3(-30, 15, -95)
        flare.isHidden = true
        world.addChildNode(flare)
        flareNode = flare
    }

    // MARK: - Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        updateSea(s)
        updateRaftBody(s)
        updateGear(s)
        updateLife(s)
        updateDistant(s)

        showPeople(s, spots: spots(for: s), parent: tilt)
        showBodies(s.dead, spots: bodySpots, parent: tilt)
    }

    /// Sea state and colour follow the wind and the light; the deep layer stays below the troughs.
    private func updateSea(_ s: SceneState) {
        guard let m = seaMat else { return }
        let storm = CGFloat(max(0, min(1, (s.wind - 10) / 55)))
        let amp = Float(0.16 + 0.95 * storm)
        surfaceAmp = amp
        m.setValue(NSNumber(value: amp), forKey: "amplitude")
        m.setValue(NSNumber(value: 0.42 + 0.55 * storm), forKey: "choppiness")
        m.roughness.contents = 0.08 + 0.4 * storm
        // clear tropical water is green-turquoise; a storm turns it lead grey; night kills it
        let day = s.sun > 0.6 ? SK.rgb(0x2E7079) : (s.sun > 0.25 ? SK.rgb(0x34666E) : SK.rgb(0x3C5A5E))
        let lit = day.blended(withFraction: CGFloat(1 - s.sun) * 0.5, of: SK.rgb(0x5C6668)) ?? day
        let dark = lit.blended(withFraction: CGFloat(darkness), of: SK.rgb(0x08151C)) ?? lit
        m.diffuse.contents = dark
        m.specular.contents = NSColor(white: CGFloat(1 - darkness * 0.85), alpha: 1)
        if let dm = deepSea?.geometry?.firstMaterial {
            dm.diffuse.contents = dark.blended(withFraction: 0.45, of: SK.rgb(0x061A24)) ?? dark
        }
        deepSea?.position.y = CGFloat(-amp) - 0.4
        // the collar of foam only shows while the raft is working in a sea
        foam?.geometry?.firstMaterial?.transparency = CGFloat(0.08 + 0.22 * Double(storm) + darkness * 0.04)
    }

    /// Deflation, bilge water and the awning: the raft itself changes with the state.
    private func updateRaftBody(_ s: SceneState) {
        // how flat the tubes are: a leak, plus a broken shelter
        let leak = CGFloat(max(0, min(1, (s.v("leak", 2) - 1) / 4)))
        let wreck = CGFloat(max(0, min(1, (45 - s.shelter) / 40)))
        let flat = max(leak * 0.45, wreck * 0.85)
        for (i, t) in tubeNodes.enumerated() {
            t.scale.y = 1 - flat * 0.42
            t.position.y = (i == 0 ? tubeLowY : tubeUpY) * (1 - flat * 0.35)
        }
        canopyNode?.scale.y = 1 - flat * 0.3
        canopyNode?.scale.z = 1 - flat * 0.12
        raft.position.y = 0.02 - flat * 0.14

        // bilge: a little water always, a lot when it blows or the raft is failing
        let bilge = CGFloat(max(0, min(1, s.precip / 2))) * 0.55 + wreck * 0.45 + (s.shelter < 60 ? 0.2 : 0)
        bilgeNode?.position.y = deckY + 0.006 + min(0.10, bilge * 0.11)

        // awning: furled back over the foredeck in fine weather, pulled right over when it rains
        let want = CGFloat(max(0, min(1, max(s.precip / 1.5, (45 - s.shelter) / 35))))
        if abs(want - canopyCover) > 0.01 {
            canopyCover = want
            setCanopy(cover: want)
        }
    }

    /// `cover` 0 = furled back over the aft half, 1 = pulled right over the whole raft.
    private func setCanopy(cover: CGFloat) {
        let length = 1.77 + 1.10 * cover
        canopyNode?.scale.x = length
        canopyNode?.position = SCNVector3(-1.42 + length / 2, 0.55, 0)
    }

    private func updateGear(_ s: SceneState) {
        // food and water: whatever is left, is on the deck
        waterCans?.isHidden = s.res("water") < 0.3
        catchFish?.isHidden = !(s.v("fish") >= 12 || s.happened("r_dorado")) || s.res("food") > 12000
        fishLine?.isHidden = s.res("hooks") < 1 || s.precip >= 1.5

        flareBox?.isHidden = s.res("flares") < 1 && s.res("smoke") < 1
        smokeCans?.isHidden = s.res("smoke") < 1
        sartNode?.isHidden = !(s.v("sartOn") > 0 || s.has("sart_used") || s.has("sart_saved"))

        // projects
        let sail = CGFloat(s.project("sail"))
        sailNode?.isHidden = sail < 0.05
        let hoist = max(0.15, min(1, sail))
        sailCloth?.scale.y = hoist
        sailCloth?.position = SCNVector3(-0.60, 0.80 + 0.65 * hoist, 0.0)
        pumpNode?.isHidden = !(s.project("desal") > 0.05)
        desalBottles?.isHidden = s.v("filter") < 20

        // the lamp: only when it is genuinely dark in there
        let lampOn = s.isNight || (darkness > 0.7 && s.precip >= 1.9)
        lampLight?.isHidden = !lampOn
        lampBulb?.geometry?.firstMaterial?.emission.contents = lampOn ? SK.rgb(0xFFC46A) : NSColor.black
        mastLight?.isHidden = !s.isNight
        lampLight?.base = 65 * CGFloat(0.35 + 0.65 * darkness)
    }

    private func updateLife(_ s: SceneState) {
        // sharks: one fin per twenty points of `var.shark`, circling the raft
        let shark = s.v("shark", 20)
        var want = shark < 12 ? 0 : (shark < 30 ? 1 : (shark < 50 ? 2 : (shark < 70 ? 3 : 4)))
        if s.now("r_shark_bump") || s.now("r_shark_pan") { want = max(want, 3) }
        while sharks.count > want { sharks.removeLast().removeFromParentNode() }
        while sharks.count < want, let proto = sharkFin {
            let i = sharks.count
            let orbit = SCNNode()
            let fin = proto.clone()
            fin.position = SCNVector3(4.0 + CGFloat(i) * 1.5, 0.24 + CGFloat(i % 2) * 0.04, 0)
            fin.eulerAngles.y = 0.1 * CGFloat(i)
            orbit.addChildNode(fin)
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 17 + Double(i) * 4)))
            world.addChildNode(orbit)
            sharks.append(orbit)
        }

        // the school under the raft, and flying fish skimming past — never in the dark or a squall
        let bright = !s.isNight && s.precip < 1.5 && s.visibility > 0.3
        fishSchool?.isHidden = s.v("fish") < 12 || !bright
        flyingFish?.isHidden = s.v("fish") < 8 || !bright
        turtle?.isHidden = !s.now("r_turtle")
        booby?.isHidden = !(s.now("r_bird") || s.happened("r_bird"))
        gulls?.isHidden = s.precip >= 1.5 || s.isNight
    }

    private func updateDistant(_ s: SceneState) {
        // rescue: whatever the ending says came for them
        let rescue = s.now("rescue") || s.has("rescued") || (s.ended && !s.has("drifted"))
        let spottedShip = s.now("ship_day") || s.now("ship_night")
        let seen = (spottedShip && s.visibility > 0.45) || (rescue && s.visibility > 0.25)
        if let ship = shipNode {
            ship.isHidden = !seen
            ship.position = rescue ? SCNVector3(-140, 0, -210) : SCNVector3(-360, 0, -430)
        }
        bangkaNode?.isHidden = !(s.has("by_bangka") || s.has("by_fisher") || s.now("bangka") || s.has("bangka_met"))
        basketNode?.isHidden = !(s.has("by_viet") || s.now("hung_float"))
        planeNode?.isHidden = !(s.now("plane") || s.has("by_plane"))
        rigNode?.isHidden = !s.now("r_rig")

        // a flare on its parachute, only while there is a ship to see and a flare left to burn
        flareNode?.isHidden = !(seen && s.res("flares") >= 1)
    }

    // MARK: - People

    /// Only sitting or lying in a raft — nobody stands up on a life raft.
    /// SK's sitting pose has its seat 0.40 m above the root, so sitting spots sit 0.40 m low.
    private func spots(for s: SceneState) -> [Spot] {
        let storm = s.precip >= 1.5 || s.wind >= 45 || s.shelter < 32
        var sit = storm ? stormSitting : (s.isNight ? nightSitting : daySitting)
        var lie = lyingSpots
        var out: [Spot] = []
        for p in s.people {
            if p.injured || p.animal {
                out.append(lie.isEmpty ? (sit.isEmpty ? deckSpot(0, 0) : sit.removeFirst()) : lie.removeFirst())
            } else if sit.isEmpty {
                out.append(deckSpot(CGFloat(out.count % 3) * 0.6 - 0.6, 0.3))
            } else {
                out.append(sit.removeFirst())
            }
        }
        return out
    }

    private func deckSpot(_ x: CGFloat, _ z: CGFloat) -> Spot {
        Spot(x, deckY - seatDrop, z, facing: 0, pose: .sitting)
    }

    /// Daytime: two perched on the tube tops, the rest working the open foredeck and the shade.
    private var daySitting: [Spot] {
        [Spot(0.78, deckY - seatDrop, 0.50, facing: 0.1, pose: .sitting),
         Spot(1.02, deckY - seatDrop, -0.18, facing: -0.7, pose: .sitting),
         Spot(0.52, deckY - seatDrop, -0.62, facing: -0.3, pose: .sitting),
         Spot(0.44, deckY - seatDrop, 0.60, facing: 0.4, pose: .sitting),
         Spot(1.18, tubeTop - seatDrop, 0.45, facing: 0.5, pose: .sitting),
         Spot(1.22, tubeTop - seatDrop, -0.36, facing: -0.5, pose: .sitting),
         Spot(0.05, deckY - seatDrop, 0.35, facing: -0.2, pose: .sitting),
         Spot(-0.35, deckY - seatDrop, -0.45, facing: 0.3, pose: .sitting),
         Spot(-0.78, deckY - seatDrop, 0.42, facing: 0.8, pose: .sitting)]
    }

    /// Night: one on watch in the awning mouth, everyone else in under the cloth.
    private var nightSitting: [Spot] {
        [Spot(0.28, deckY - seatDrop, 0.45, facing: 0.1, pose: .sitting),
         Spot(-0.18, deckY - seatDrop, 0.32, facing: -0.4, pose: .sitting),
         Spot(-0.18, deckY - seatDrop, -0.34, facing: 0.4, pose: .sitting),
         Spot(-0.72, deckY - seatDrop, 0.42, facing: 0.9, pose: .sitting),
         Spot(-0.72, deckY - seatDrop, -0.44, facing: -0.9, pose: .sitting),
         Spot(-1.10, deckY - seatDrop, 0.05, facing: 0.6, pose: .sitting),
         Spot(0.05, deckY - seatDrop, 0.00, facing: 0.0, pose: .sitting)]
    }

    /// Storm: crammed in under the awning, backs to the wind.
    private var stormSitting: [Spot] {
        [Spot(0.22, deckY - seatDrop, 0.45, facing: -0.3, pose: .huddled),
         Spot(0.22, deckY - seatDrop, -0.48, facing: 0.3, pose: .huddled),
         Spot(-0.30, deckY - seatDrop, 0.50, facing: 0.5, pose: .huddled),
         Spot(-0.30, deckY - seatDrop, -0.52, facing: -0.5, pose: .huddled),
         Spot(-0.82, deckY - seatDrop, 0.38, facing: 1.0, pose: .huddled),
         Spot(-0.82, deckY - seatDrop, -0.40, facing: -1.0, pose: .huddled),
         Spot(-1.10, deckY - seatDrop, 0.05, facing: 0.0, pose: .huddled),
         Spot(0.05, deckY - seatDrop, 0.05, facing: 0.0, pose: .huddled)]
    }

    /// Anyone badly hurt lies down inside; the dog lies at the mouth of the awning.
    /// A lying figure stretches 1.8 m along its facing, so it has to lie down the raft's length.
    private var lyingSpots: [Spot] {
        [Spot(0.0, deckY, -0.46, facing: 0.0, pose: .lying),
         Spot(0.0, deckY, 0.46, facing: 0.0, pose: .lying),
         Spot(0.58, deckY, 0.18, facing: 0.4, pose: .lying),
         Spot(0.30, deckY, 0.0, facing: .pi / 2, pose: .lying)]
    }

    /// The dead: laid out on the floor, then let go over the side.
    /// (SK.shroud lies along +z, so a body down the raft's length faces 90°.)
    private var bodySpots: [Spot] {
        [Spot(0.0, deckY, -0.50, facing: .pi / 2),
         Spot(0.0, deckY, 0.50, facing: .pi / 2),
         Spot(0.10, tubeTop + 0.20, 1.05, facing: .pi / 2),
         Spot(-0.10, tubeTop + 0.20, -1.05, facing: .pi / 2),
         Spot(1.95, -0.03, 0.30, facing: .pi / 2),
         Spot(-2.05, -0.03, 0.30, facing: .pi / 2)]
    }
}
