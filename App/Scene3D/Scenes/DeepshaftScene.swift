import SceneKit
import AppKit

/// 深井 — a flooded coal-mine drift, 450 m underground (福源煤业 1203 面 2 号上山).
///
/// Layout (metres, world axes): the air course runs along x. The drowned transport
/// roadway is at x ≈ +30, below the water line; the drift climbs ~8.5° toward −x, past
/// the men's refuge (a timber platform at x ≈ −2, where the water stops about 3 m below
/// their feet) and dead-ends at a brick seal wall on the old 1201 connection at x = −26.
/// Everything is lit by the men's own lamps and a few hanging cap lamps: there is no
/// sky and no sun (`indoor`), and beyond the pools of lamplight the coal is black.
///
/// Shown from state: the water level (var gap — it climbs the drift or falls away),
/// what is left of the lamps (res lamp, var darkdays), the breathing air (var o2 / co2 —
/// haze, and the gas monitor on the rib), the air pipe (project air_pipe, flag air_on /
/// pipe_broken), the guide rope (project rope), the dam (project dam), the scouted route
/// (var route), the seal wall and 赵存柱 (flag seal_open / seal_hole), the borehole and
/// drill rod (event borehole_breakthrough → flag lifeline), the collapse (event
/// roof_fall), the rescue boats' light in the drowned roadway (flag boats_coming), the
/// injured (贺小勇's broken leg), the dead under blankets, and the rat 灰子 on the cap beam.
final class DeepshaftScene: ScenarioScene {
    private let noise = SK.Noise(seed: 451)

    // geometry of the drift
    private let xDrown: CGFloat = 34           // the drowned end of the roadway
    private let xFace: CGFloat = -26           // the seal wall at the dead end
    private let halfW: CGFloat = 2.3           // half width of the roadway
    private let capY: CGFloat = 2.45           // height of the cap beams
    private let archH: CGFloat = 3.25          // floor → crown
    private let platformY: CGFloat = 1.25      // deck of the refuge, above the floor at x = 0

    // state-driven nodes
    private var water: SCNNode?
    private var waterSurface: CGFloat = 0
    private var capLamps: [SK.FlickerLight] = []       // hanging lamps, state-driven
    private var capLampBase: [CGFloat] = []
    private var fillLamps: [SK.FlickerLight] = []      // ambient fill, always on
    private var fillBase: [CGFloat] = []
    private var workLamp: SK.FlickerLight?
    private var routeMarks: [SCNNode] = []
    private var pipeMend: SCNNode?
    private var pipeBroken: SCNNode?
    private var dam: SCNNode?
    private var rope: SCNNode?
    private var sealWall: SCNNode?
    private var sealHole: SCNNode?
    private var sealOpen: SCNNode?
    private var borehole: SCNNode?
    private var drillRod: SCNNode?
    private var drillGlow: SK.FlickerLight?
    private var roofFall: SCNNode?
    private var blastScorch: SCNNode?
    private var blastFlash: SK.FlickerLight?
    private var rescueLight: SK.FlickerLight?
    private var rat: SCNNode?
    private var monitorLamps: [SCNNode] = []
    private var haze: SCNParticleSystem?

    // materials
    private var coalMat: SCNMaterial!
    private var woodMat: SCNMaterial!
    private var lagMat: SCNMaterial!
    private var steelMat: SCNMaterial!
    private var ductMat: SCNMaterial!
    private var brickMat: SCNMaterial!

    required init() {
        super.init()
        indoor = true
        indoorColor = SK.rgb(0x04050A)          // the dark down here is absolute
        indoorVisibility = 26
        ssao = 0.6                              // close-up gallery: SSAO is worth it
        exposure = -0.7
        // the camera stands under the arch a little uphill of the refuge, looking back
        // down the dip: the near ribs frame the shot, the men and the water are in it,
        // and the drowned roadway runs away into the dark
        // yaw 90° puts the camera out along +x, i.e. looking down the drift toward
        // the drowned roadway; the eye ends up ~1.5 m above the falling floor
        // eye ≈ (5.1, 1.72, 0): mid-drift, above the water line, under the cap beams,
        // in the clear space between two prop sets and clear of the hanging duct
        // the eye sits out over the drowned roadway, just above the water, looking back
        // up the dip at the refuge: water in the foreground, the men and the platform on
        // the rise, the drift climbing away behind them into the dark
        cameraTarget = SCNVector3(-2.0, 1.45, 0.0)
        cameraDistance = 8.56
        cameraYaw = 90
        cameraPitch = 3.6
        cameraFOV = 52
        minPitch = 2
    }

    // The default shot is expressed through the orbit parameters below, so the app's
    // drag-to-orbit (and the sandbox's --cam) work on top of it unchanged.

    // MARK: - Set-out lines

    /// Floor of the drift at x: 8.5° climbing toward −x (uphill is where the men are).
    /// The set-out line is exact — every prop, the camera and the water level are
    /// placed from it — so the unevenness of a hand-cut floor is left to the lagging
    /// and the rubble, not to the datum.
    private func floorY(_ x: CGFloat) -> CGFloat { 0.9 - x * 0.15 }
    private func ground(_ x: CGFloat, _ z: CGFloat) -> CGFloat { floorY(x) }

    /// Cross-section of the roadway: vertical ribs to the cap beam, then a flat arch.
    /// It must enclose the whole section — anything outside it is bare rock, and bare
    /// rock is black.
    private func profile(_ t: CGFloat) -> (CGFloat, CGFloat) {
        let z = -halfW + 2 * halfW * t
        let u = pow(abs(z) / halfW, 3.2)                    // 0 in the middle, 1 at the ribs
        return (z, u * capY + (1 - u) * archH)
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        makeMaterials()
        buildSurfaces()
        buildSupports()
        buildTrack()
        buildServices()
        buildSealWall()
        buildRefuge()
        buildLamps()
        buildWater()
        buildSmallProps()
        buildParticles()
    }

    private func makeMaterials() {
        coalMat = SK.noiseMat(SK.rgb(0x1A1918), SK.rgb(0x2E2C29), scale: 5, roughness: 0.9, seed: 31)
        SK.addGrain(coalMat, scale: 14, strength: 3, intensity: 0.5, seed: 32)
        woodMat = SK.noiseMat(SK.rgb(0x1B140D), SK.rgb(0x2A1F10), scale: 6, roughness: 0.95, seed: 51)
        lagMat = SK.noiseMat(SK.rgb(0x191309), SK.rgb(0x261C0F), scale: 5, roughness: 0.95, seed: 71)
        steelMat = SK.mat(SK.rgb(0x33343A), roughness: 0.5, metalness: 0.7)
        ductMat = SK.noiseMat(SK.rgb(0x5E5B54), SK.rgb(0x46443F), scale: 4, roughness: 0.85, seed: 81)
        brickMat = SK.noiseMat(SK.rgb(0x5E4436), SK.rgb(0x7A5C46), scale: 9, roughness: 0.9, seed: 61)
    }

    /// Plain boxes rather than hand-built meshes: long slabs for the floor, the two
    /// ribs and the arch, all following the climb and overlapping, so the drift
    /// encloses the camera completely and no seam or void can ever show.
    private func buildSurfaces() {
        // Floor: its top face is the floor line everything else is set out from. One
        // long slab is safe — it sits two metres below the camera, and the sleepers,
        // which do follow the floor function exactly, rest on top of it.
        let floorSlab = SK.box(xDrown - xFace + 2, 1.0, 5.2, coalMat, chamfer: 0.0)
        floorSlab.position = SCNVector3((xDrown + xFace) / 2, floorY((xDrown + xFace) / 2) - 0.55, 0)
        floorSlab.eulerAngles.z = -atan(0.15)
        floorSlab.castsShadow = false
        world.addChildNode(floorSlab)

        // Ribs and arch are tiled every 3 m so they follow the floor's relief, not
        // just its slope: one long slab would drift into the camera down the drift.
        let seg: CGFloat = 3.0
        var x = xFace - 1
        while x < xDrown + 1 {
            let cx = x + seg / 2
            let fy = floorY(cx)
            for side in [CGFloat(-1), CGFloat(1)] {         // the two ribs
                let rib = SK.box(seg * 1.08, 2.9, 0.9, coalMat, chamfer: 0.0)
                rib.position = SCNVector3(cx, fy + 1.22, side * 2.75)
                rib.eulerAngles.z = -atan(0.15)
                rib.castsShadow = false
                world.addChildNode(rib)
            }
            for j in 0..<5 {                                // the arch, five strips
                let zt = -1.0 + CGFloat(j) * 0.5
                let u = pow(abs(zt), 3.2)
                let yTop = u * capY + (1 - u) * archH
                let strip = SK.box(seg * 1.08, 0.5, 1.15, coalMat, chamfer: 0.0)
                strip.position = SCNVector3(cx, fy + yTop - 0.24, zt * halfW)
                strip.eulerAngles.z = -atan(0.15)
                strip.castsShadow = false
                world.addChildNode(strip)
            }
            x += seg
        }
        for ex in [xFace - 0.6, xDrown + 0.6] {             // both ends walled off
            let cap = SK.box(0.8, 5.0, 7.0, coalMat, chamfer: 0.0)
            cap.position = SCNVector3(ex, floorY(ex) + 1.9, 0)
            cap.castsShadow = false
            world.addChildNode(cap)
        }
    }

    /// Timber props: two legs, a cap beam and lagging over the top, every 1.7 m along
    /// the dip, plus a steel arch rib every fourth set.
    private func buildSupports() {
        var i = 0
        var x: CGFloat = xFace + 1.5
        while x < xDrown - 1 {
            let g = SCNNode()
            for side in [CGFloat(-1), CGFloat(1)] {
                let h = capY + 0.22
                g.addChildNode(SK.cylinder(0.13, h, woodMat, at: SCNVector3(0, h / 2 - 0.1, side * 1.82)))
            }
            let cap = SK.cylinder(0.15, 4.5, woodMat)
            cap.eulerAngles.x = .pi / 2                      // across the roadway, resting on both legs
            cap.position = SCNVector3(0, capY + 0.15, 0)
            g.addChildNode(cap)
            for k in 0..<5 {                                 // lagging over the cap
                let b = SK.box(0.7, 0.07, 5.4, lagMat, chamfer: 0.0,
                               at: SCNVector3(-0.85 + CGFloat(k) * 0.42, capY + 0.25, 0))
                b.eulerAngles.x = CGFloat(noise.value(Float(k) + Float(i) * 3, 2) - 0.5) * 0.1
                g.addChildNode(b)
            }
            for side in [CGFloat(-1), CGFloat(1)] {          // side lagging behind the ribs
                for k in 0..<2 {
                    let b = SK.box(0.9, 1.0, 0.07, lagMat, chamfer: 0.0,
                                   at: SCNVector3(0, 0.7 + CGFloat(k) * 1.1, side * 2.27))
                    b.eulerAngles.z = CGFloat(noise.value(Float(i) * 2 + Float(k), 9) - 0.5) * 0.12
                    g.addChildNode(b)
                }
            }
            if i % 4 == 0 {                                  // a brace, leaning along the dip
                let br = SK.cylinder(0.07, 2.6, woodMat)
                br.position = SCNVector3(0.5, 1.5, 2.05)
                br.eulerAngles = SCNVector3(-0.5, 0, 0.3)
                g.addChildNode(br)
            }
            g.position = SCNVector3(x, floorY(x), 0)
            g.castsShadow = true
            world.addChildNode(g)
            i += 1
            x += 1.7
        }

        // a steel arch rib every fourth set, following the same profile
        let ribMat = SK.mat(SK.rgb(0x33343A), roughness: 0.6, metalness: 0.7)
        for j in 0..<7 {
            let ax = xFace + 3.0 + CGFloat(j) * 8.2
            let g = SCNNode()
            let segs = 12
            let path: [(CGFloat, CGFloat)] = (0...segs).map { k in
                let t = CGFloat(k) / CGFloat(segs)
                let z = -halfW + 2 * halfW * t
                let u = pow(abs(z) / halfW, 3.2)
                return (z, u * capY + (1 - u) * archH)
            }
            for k in 0..<segs {
                let a = path[k], b = path[k + 1]
                let dz = b.0 - a.0, dy = b.1 - a.1
                let len = sqrt(dz * dz + dy * dy)
                let band = SK.box(0.17, len + 0.06, 0.15, ribMat, chamfer: 0.0)
                band.position = SCNVector3(0, (a.1 + b.1) / 2, (a.0 + b.0) / 2)
                band.eulerAngles.x = atan2(dz, dy)
                g.addChildNode(band)
            }
            g.position = SCNVector3(ax, floorY(ax), 0)
            g.castsShadow = true
            world.addChildNode(g)
        }
    }

    /// Narrow-gauge track on the ballast, and the tram left half in the water.
    private func buildTrack() {
        let ballast = SK.box(xDrown - xFace, 0.34, 3.1, SK.mat(SK.rgb(0x2E2B27), roughness: 0.6),
                             chamfer: 0.0)
        ballast.position = SCNVector3((xDrown + xFace) / 2, floorY(0) + 0.17, 0)
        ballast.castsShadow = false
        world.addChildNode(ballast)

        for dz in [CGFloat(-0.45), CGFloat(0.45)] {
            let rail = SK.box(xDrown - xFace - 2, 0.12, 0.11, steelMat, chamfer: 0.0)
            rail.position = SCNVector3((xDrown + xFace) / 2, floorY(0) + 0.42, dz)
            rail.eulerAngles.z = -atan(0.15)
            rail.castsShadow = false
            world.addChildNode(rail)
        }
        for i in 0..<40 {                                    // sleepers
            let sx = xFace + 2 + CGFloat(i) * 1.5
            let s = SK.box(0.24, 0.14, 1.55, woodMat, chamfer: 0.0,
                           at: SCNVector3(sx, floorY(sx) + 0.33, 0))
            s.eulerAngles.y = CGFloat(noise.value(Float(i) * 1.7, 3) - 0.5) * 0.08
            s.castsShadow = false
            world.addChildNode(s)
        }

        // an overturned tram on the track, downhill of the refuge
        let c = SCNNode()
        let body = SK.box(1.35, 0.9, 1.15, SK.mat(SK.rgb(0x45464A), roughness: 0.7, metalness: 0.3), chamfer: 0.03)
        body.position.y = 0.45
        c.addChildNode(body)
        c.addChildNode(SK.box(1.5, 0.1, 1.3, steelMat, chamfer: 0.02, at: SCNVector3(0, 0.93, 0)))
        c.addChildNode(SK.box(1.2, 0.22, 1.0, coalMat, chamfer: 0.05, at: SCNVector3(0, 0.98, 0)))
        c.position = SCNVector3(11.0, floorY(11.0) + 0.28, 0.35)
        c.eulerAngles = SCNVector3(0.3, 0.2, 0.12)
        c.castsShadow = true
        world.addChildNode(c)
    }

    /// Compressed-air line, ventilation duct, cable, and the gas monitor on the rib.
    private func buildServices() {
        let pipeMat = SK.mat(SK.rgb(0x3C4247), roughness: 0.5, metalness: 0.6)
        let pipe = SK.cylinder(0.085, xDrown - xFace - 6, pipeMat)      // one piece of pipe
        pipe.eulerAngles = SCNVector3(0, -atan(0.15), .pi / 2)
        pipe.position = SCNVector3((xDrown + xFace) / 2, floorY(0) + 1.45, -2.02)
        pipe.castsShadow = false
        world.addChildNode(pipe)

        // the crushed valve and the pipe end that lies in the water downhill
        let elbow = SK.cylinder(0.11, 0.7, pipeMat)
        elbow.eulerAngles.x = .pi / 2
        elbow.position = SCNVector3(2.4, floorY(2.4) + 1.4, -2.02)
        world.addChildNode(elbow)
        pipeMend = elbow
        let stub = SK.cylinder(0.085, 3.4, pipeMat)
        stub.eulerAngles = SCNVector3(0, 0.2, .pi / 2 - 0.55)
        stub.position = SCNVector3(5.6, floorY(5.6) + 1.1, -1.9)
        world.addChildNode(stub)
        pipeBroken = stub

        // the flexible duct, hooked along the other rib a little below the roof
        let duct = SK.cylinder(0.26, xDrown - xFace - 8, ductMat)
        duct.eulerAngles = SCNVector3(0, -atan(0.15), .pi / 2)
        duct.position = SCNVector3((xDrown + xFace) / 2 + 1, floorY(0) + 2.52, 2.05)
        duct.castsShadow = false
        world.addChildNode(duct)
        for j in 0..<8 {                                    // its hooks into the roof
            let hx = xFace + 4 + CGFloat(j) * 6.5
            world.addChildNode(SK.box(0.05, 0.3, 0.05, steelMat, chamfer: 0.0,
                                      at: SCNVector3(hx, floorY(hx) + 2.80, 2.05)))
        }
        let rag = SCNNode(geometry: SCNCone(topRadius: 0.32, bottomRadius: 0.18, height: 1.0))
        rag.geometry?.materials = [ductMat]
        rag.eulerAngles.z = .pi / 2
        rag.position = SCNVector3(xFace + 5.4, floorY(xFace + 5.4) + 2.62, 1.72)
        world.addChildNode(rag)

        let cable = SK.cylinder(0.045, xDrown - xFace - 4, SK.mat(SK.rgb(0x121214), roughness: 0.9))
        cable.eulerAngles = SCNVector3(0, atan(0.15), .pi / 2)
        cable.position = SCNVector3((xDrown + xFace) / 2, floorY(0) + 1.95, 2.06)
        cable.castsShadow = false
        world.addChildNode(cable)

        // 贺小勇's gas monitor, hung on the rib: the men watch this instead of the roof
        let m = SCNNode()
        m.addChildNode(SK.box(0.34, 0.5, 0.12, SK.mat(SK.rgb(0xC8A32A), roughness: 0.6), chamfer: 0.02))
        for k in 0..<5 {
            let dot = SK.sphere(0.036, SK.mat(.black, roughness: 0.4, emission: SK.rgb(0x35FF66)),
                                at: SCNVector3(0, 0.17 - CGFloat(k) * 0.085, 0.075), segments: 10)
            dot.geometry?.firstMaterial?.emission.intensity = 0.2
            m.addChildNode(dot)
            monitorLamps.append(dot)
        }
        m.position = SCNVector3(-12.4, floorY(-12.4) + 1.5, 2.06)
        world.addChildNode(m)
    }

    /// The brick stopping on the old 1201 connection, at the dead end of the drift.
    private func buildSealWall() {
        let wall = SK.box(0.7, 3.6, 5.0, brickMat, chamfer: 0.0)
        wall.position = SCNVector3(xFace + 0.4, floorY(xFace) + 1.5, 0)
        wall.castsShadow = true
        world.addChildNode(wall)
        sealWall = wall

        // the fist-sized hole 赵存柱 was passed water through
        let hole = SK.cylinder(0.17, 0.9, SK.mat(.black, roughness: 1))
        hole.eulerAngles.z = .pi / 2
        hole.position = SCNVector3(xFace + 0.4, floorY(xFace) + 0.7, 0.9)
        hole.isHidden = true
        world.addChildNode(hole)
        sealHole = hole

        // the wall torn open: a way through, and a heap of broken bricks in front of it
        let breach = SCNNode()
        for i in 0..<18 {
            let b = SK.box(0.22, 0.12, 0.15, brickMat, chamfer: 0.0)
            b.position = SCNVector3(xFace + 0.3 + CGFloat(noise.value(Float(i) * 3.1, 5)) * 2.4,
                                    floorY(xFace) + 0.15 + CGFloat(i % 6) * 0.22,
                                    -1.2 + CGFloat(i % 4) * 0.7 + CGFloat(noise.value(Float(i), 8)) * 0.5)
            b.eulerAngles = SCNVector3(CGFloat(i) * 0.4, CGFloat(i) * 0.7, 0.2)
            breach.addChildNode(b)
        }
        breach.addChildNode(SK.box(0.9, 2.0, 1.3, SK.mat(.black, roughness: 1),
                                   at: SCNVector3(xFace + 0.4, floorY(xFace) + 1.0, 0.1)))
        breach.isHidden = true
        world.addChildNode(breach)
        sealOpen = breach
    }

    /// The timber refuge the men built — post legs, stringers, a plank deck — and the
    /// board their pooled rations sit on.
    private func buildRefuge() {
        let p = SCNNode()
        for dx in [CGFloat(-2.3), CGFloat(2.3)] {
            for dz in [CGFloat(-2.05), CGFloat(2.05)] {
                let h = platformY + 0.5
                p.addChildNode(SK.cylinder(0.12, h, woodMat,
                                           at: SCNVector3(dx, platformY - h / 2, dz)))
            }
        }
        for dz in [CGFloat(-2.0), CGFloat(2.0)] {            // stringers along the dip
            let beam = SK.cylinder(0.14, 4.9, woodMat)
            beam.eulerAngles.x = .pi / 2
            beam.position = SCNVector3(-2.3, platformY - 0.2, dz)
            p.addChildNode(beam)
        }
        for k in 0..<7 {                                     // the plank deck
            let b = SK.box(4.9, 0.08, 0.6, lagMat, chamfer: 0.0,
                           at: SCNVector3(-2.3, platformY - 0.06, -1.8 + CGFloat(k) * 0.6))
            b.eulerAngles.y = CGFloat(noise.value(Float(k), 3) - 0.5) * 0.03
            p.addChildNode(b)
        }
        p.position = SCNVector3(0, floorY(0), 0)
        p.castsShadow = true
        world.addChildNode(p)

        // the board with the lunch boxes, the biscuits and a flask
        let board = SCNNode()
        board.addChildNode(SK.box(1.6, 0.06, 0.75, lagMat, chamfer: 0.0))
        board.addChildNode(SK.box(0.34, 0.16, 0.28, SK.mat(SK.rgb(0xA8A292), roughness: 0.7),
                                  chamfer: 0.02, at: SCNVector3(-0.35, 0.12, 0)))
        board.addChildNode(SK.box(0.3, 0.14, 0.24, SK.mat(SK.rgb(0xC8B080), roughness: 0.9),
                                  chamfer: 0.02, at: SCNVector3(0.12, 0.11, 0.06)))
        board.addChildNode(SK.cylinder(0.07, 0.22, SK.mat(SK.rgb(0x35624A), roughness: 0.6, metalness: 0.4),
                                       at: SCNVector3(0.5, 0.15, -0.16)))
        board.position = SCNVector3(-0.6, floorY(0) + platformY + 0.04, -1.5)
        board.eulerAngles.y = 0.35
        world.addChildNode(board)

        // the highest cap beam of all, over the refuge — the rat's perch
        let big = SK.cylinder(0.19, 5.2, woodMat)
        big.eulerAngles.z = .pi / 2
        big.position = SCNVector3(0.6, floorY(0) + capY + 0.15, 0)
        world.addChildNode(big)
        for dz in [CGFloat(-2.2), CGFloat(2.2)] {
            world.addChildNode(SK.cylinder(0.13, capY + 0.15, woodMat,
                                           at: SCNVector3(0.6, floorY(0) + (capY + 0.15) / 2, dz)))
        }

        // 灰子 the rat, on the beam, where everyone can watch it breathe
        let ratNode = SK.animal(weight: 15, color: SK.rgb(0x6E6A66), lying: false, seed: 3)
        ratNode.scale = SCNVector3(0.42, 0.42, 0.42)
        ratNode.position = SCNVector3(0.55, floorY(0) + capY + 0.30, 0.2)
        ratNode.eulerAngles.y = -1.1
        world.addChildNode(ratNode)
        rat = ratNode
    }

    /// Hanging cap lamps, the work lamp on the deck, a lamp that travels with the
    /// camera, and two directional fills standing in for light bouncing off the wet
    /// floor. Without the fills the coal is dead black wherever a lamp does not point.
    private func buildLamps() {
        for (i, lx) in [CGFloat(-20.0), -13.5, -6.0, 1.0, 7.5, 14.0, 21.0, 28.0].enumerated() {
            let lamp = SK.fireLight(intensity: 62, color: SK.rgb(0xFFE2B0), range: 12)
            lamp.position = SCNVector3(lx, floorY(lx) + 2.55, 0.0)
            let bulb = SK.sphere(0.07, SK.mat(SK.rgb(0xFFF0CC), roughness: 0.3, emission: SK.rgb(0xFFD9A0)),
                                 segments: 12)
            bulb.name = "bulb"
            lamp.addChildNode(bulb)
            let shade = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.17, height: 0.16))
            shade.geometry?.materials = [steelMat]
            shade.position.y = 0.1
            lamp.addChildNode(shade)
            world.addChildNode(lamp)
            capLamps.append(lamp)
            capLampBase.append(i == 2 ? 96 : 62)            // the one over the refuge burns brighter
        }

        // the work lamp on the deck: the one shadow-casting light of the scene
        let work = SK.fireLight(intensity: 82, color: SK.rgb(0xFFD9A0), range: 13)
        work.position = SCNVector3(-3.4, floorY(0) + platformY + 1.35, 1.2)
        work.light?.castsShadow = true
        work.light?.shadowMode = .deferred
        work.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        work.light?.shadowRadius = 3
        work.light?.shadowSampleCount = 4
        work.light?.shadowColor = NSColor(white: 0, alpha: 0.7)
        let shade = SCNNode(geometry: SCNCone(topRadius: 0.06, bottomRadius: 0.3, height: 0.3))
        shade.geometry?.materials = [SK.mat(SK.rgb(0x4A4E53), roughness: 0.5, metalness: 0.6)]
        shade.position.y = 0.08
        work.addChildNode(shade)
        work.addChildNode(SK.cylinder(0.035, 1.5, steelMat, at: SCNVector3(0, -0.75, 0)))
        work.addChildNode(SK.sphere(0.09, SK.mat(SK.rgb(0xFFF3D8), roughness: 0.3, emission: SK.rgb(0xFFCF88)),
                                    segments: 12))
        world.addChildNode(work)
        workLamp = work

        // a lamp travelling with the camera: the coal a few metres around the viewer is
        // never pure black, and the drift is never flooded with light either
        let carry = SK.fireLight(intensity: 40, color: SK.rgb(0xA8B6C8), range: 13)
        carry.light?.castsShadow = false
        carry.position = SCNVector3(0, 0.2, -4.5)      // 4.5 m ahead of the camera
        cameraNode.addChildNode(carry)
        addFill(carry, 40)

        let key = SCNLight()
        key.type = .directional
        key.color = SK.rgb(0xB6A98C)
        key.intensity = 34
        key.castsShadow = false
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(60, 90, 30)
        keyNode.look(at: SCNVector3Zero)
        world.addChildNode(keyNode)

        let back = SCNLight()
        back.type = .directional
        back.color = SK.rgb(0x7C90AC)
        back.intensity = 26
        back.castsShadow = false
        let backNode = SCNNode()
        backNode.light = back
        backNode.position = SCNVector3(-70, 40, -40)
        backNode.look(at: SCNVector3Zero)
        world.addChildNode(backNode)
    }

    private func addFill(_ n: SK.FlickerLight, _ base: CGFloat) {
        fillLamps.append(n)
        fillBase.append(base)
    }

    /// The drowned roadway. A narrow ribbon down the middle of the drift only: the
    /// surface must never climb past the water line or it cuts across the camera.
    private func buildWater() {
        let w = SCNNode()
        w.name = "water"
        let p = SK.water(size: 4.3, color: SK.rgb(0x131A20), amplitude: 0.05, choppiness: 0.7,
                         transparency: 0.86, roughness: 0.05, segments: 40)
        p.scale = SCNVector3(1, 34.0 / 4.3, 1)               // the flooded roadway
        if let m = p.geometry?.firstMaterial {
            // a wet sheen on black water: without it the surface is simply not there
            m.emission.contents = SK.rgb(0x4A5765)
            m.emission.intensity = 1.0
        }
        p.position = SCNVector3(17, 0, 0)
        w.addChildNode(p)
        w.position = SCNVector3(0, waterSurface, 0)
        world.addChildNode(w)
        water = w

        // what is floating on it: pit props, coal, and a lost helmet
        for i in 0..<10 {
            let n: SCNNode
            switch i % 3 {
            case 0:
                n = SK.cylinder(0.09, 1.4, woodMat)
                n.eulerAngles.z = .pi / 2
            case 1:
                n = SK.rock(0.17, coalMat, seed: UInt64(200 + i), flatten: 0.5)
            default:
                n = SK.sphere(0.14, SK.mat(SK.rgb(0xB4A032), roughness: 0.4), segments: 12)
                n.scale = SCNVector3(1, 0.7, 1)
            }
            let bx = 6 + CGFloat(i) * 1.7 + CGFloat(noise.value(Float(i) * 2.3, 1)) * 1.4
            n.position = SCNVector3(bx, 0.02, CGFloat(noise.value(Float(i) * 1.9, 6) - 0.5) * 3.4)
            n.eulerAngles = SCNVector3(0, CGFloat(i) * 0.9, CGFloat(noise.value(Float(i) * 4, 2) - 0.5) * 0.3)
            n.castsShadow = false
            w.addChildNode(n)
        }
    }

    /// The borehole, the fallen set, the dam, the guide rope, the blast scorch, the
    /// rescue boats' light and the reflective tape of the scouted route.
    private func buildSmallProps() {
        let bhx: CGFloat = -17.0
        let bh = SK.sphere(0.3, SK.mat(.black, roughness: 1), at: SCNVector3(0, 0, 0), segments: 12)
        bh.scale = SCNVector3(1, 0.5, 1)
        bh.position = SCNVector3(bhx, floorY(bhx) + archH - 0.06, -1.2)
        bh.isHidden = true
        world.addChildNode(bh)
        borehole = bh

        let rod = SCNNode()
        rod.addChildNode(SK.cylinder(0.055, 2.2, SK.mat(SK.rgb(0x6E6E72), roughness: 0.35, metalness: 0.8)))
        rod.addChildNode(SK.cylinder(0.16, 0.3, SK.mat(SK.rgb(0x8A8A90), roughness: 0.3, metalness: 0.8),
                                     at: SCNVector3(0, -1.1, 0)))
        rod.position = SCNVector3(bhx, floorY(bhx) + archH - 1.15, -1.2)
        rod.eulerAngles = SCNVector3(0.12, 0, 0.08)
        rod.isHidden = true
        world.addChildNode(rod)
        drillRod = rod

        let glow = SK.fireLight(intensity: 600, color: SK.rgb(0xFFF2D0), range: 9)
        glow.position = SCNVector3(bhx, floorY(bhx) + archH - 0.8, -1.2)
        glow.isHidden = true
        world.addChildNode(glow)
        drillGlow = glow

        // a fallen set: a snapped cap beam and the coal that came down with it
        let f = SCNNode()
        let brokenBeam = SK.cylinder(0.16, 2.6, woodMat)
        brokenBeam.position = SCNVector3(0, 0.75, 1.1)
        brokenBeam.eulerAngles = SCNVector3(0.9, 0.5, 0.4)
        f.addChildNode(brokenBeam)
        for i in 0..<16 {
            let r = SK.rock(0.14 + Float(noise.value(Float(i), 2)) * 0.26, coalMat,
                            seed: UInt64(400 + i), flatten: 0.7)
            r.position = SCNVector3(-1.6 + CGFloat(noise.value(Float(i) * 2.7, 3)) * 3.2,
                                    0.12 + CGFloat(noise.value(Float(i), 5)) * 0.5,
                                    0.8 + CGFloat(noise.value(Float(i) * 1.3, 7)) * 1.5)
            r.eulerAngles = SCNVector3(CGFloat(i), CGFloat(i) * 1.3, 0)
            f.addChildNode(r)
        }
        f.position = SCNVector3(-6.0, floorY(-6.0), 0)
        f.isHidden = true
        world.addChildNode(f)
        roofFall = f

        // the dam: woven bags of coal mudded over, on the dip side of the refuge
        let d = SCNNode()
        let bagMat = SK.noiseMat(SK.rgb(0x2E2A24), SK.rgb(0x453F36), scale: 6, roughness: 0.95, seed: 97)
        for row in 0..<4 {
            for k in 0..<6 {
                let b = SK.box(0.72, 0.26, 0.5, bagMat, chamfer: 0.06)
                b.position = SCNVector3(0, 0.14 + CGFloat(row) * 0.27,
                                        -1.55 + CGFloat(k) * 0.62 + (row % 2 == 0 ? 0.14 : 0))
                b.eulerAngles = SCNVector3(CGFloat(noise.value(Float(row * 7 + k), 3) - 0.5) * 0.2, 0, 0)
                d.addChildNode(b)
            }
        }
        d.addChildNode(SK.box(4.0, 0.5, 1.2, bagMat, chamfer: 0.1, at: SCNVector3(0, 0.2, 0)))
        d.position = SCNVector3(3.2, floorY(3.2), 0)
        d.isHidden = true
        world.addChildNode(d)
        dam = d

        // the guide rope, coiled on the deck (project rope)
        let r = SCNNode()
        let ropeMat = SK.mat(SK.rgb(0x7A6C50), roughness: 0.95)
        for k in 0..<6 {
            let loop = SCNNode(geometry: SCNTorus(ringRadius: 0.26 - CGFloat(k) * 0.02, pipeRadius: 0.035))
            loop.geometry?.materials = [ropeMat]
            loop.position.y = CGFloat(k) * 0.055
            loop.eulerAngles = SCNVector3(.pi / 2, 0, CGFloat(k) * 0.3)
            r.addChildNode(loop)
        }
        r.position = SCNVector3(-1.2, floorY(0) + platformY + 0.06, 1.5)
        r.isHidden = true
        world.addChildNode(r)
        rope = r

        // scorch and blast debris after a firedamp explosion
        let sc = SCNNode()
        for i in 0..<20 {
            let rr = SK.rock(0.08 + Float(noise.value(Float(i), 4)) * 0.2, coalMat,
                             seed: UInt64(600 + i), flatten: 0.8)
            rr.position = SCNVector3(-14 + CGFloat(noise.value(Float(i) * 3.3, 1)) * 20,
                                     0.1 + CGFloat(noise.value(Float(i), 9)) * 0.2,
                                     -2 + CGFloat(noise.value(Float(i) * 1.7, 5)) * 4)
            sc.addChildNode(rr)
        }
        sc.isHidden = true
        world.addChildNode(sc)
        blastScorch = sc

        let flash = SK.fireLight(intensity: 2400, color: SK.rgb(0xFF8A3A), range: 22)
        flash.position = SCNVector3(-4.0, floorY(-4.0) + 1.6, 0)
        flash.isHidden = true
        world.addChildNode(flash)
        blastFlash = flash

        // the rescue boats' light, far down the drowned roadway
        let rl = SK.fireLight(intensity: 2200, color: SK.rgb(0xCFE6FF), range: 26)
        rl.position = SCNVector3(26, 1.2, 0)
        rl.isHidden = true
        world.addChildNode(rl)
        rescueLight = rl

        // reflective tape marking the scouted route into the water
        let tapeMat = SK.mat(SK.rgb(0xC0C0C0), roughness: 0.4, emission: SK.rgb(0x333333))
        for k in 0..<24 {
            let j = CGFloat(k) / 23
            let x = 2 - j * 15
            let m = SK.box(0.06, 0.24, 0.09, tapeMat, chamfer: 0.0)
            m.position = SCNVector3(x, floorY(x) + (j < 0.4 ? 1.9 - j * 3.2 : 0.9), 2.04)
            m.isHidden = true
            world.addChildNode(m)
            routeMarks.append(m)
        }
    }

    /// Two particle systems only: water off the roof, and the thick air itself.
    private func buildParticles() {
        for (i, dx) in [CGFloat(-18), -9, 0, 9, 18].enumerated() {
            let em = SCNNode()
            em.position = SCNVector3(dx, floorY(dx) + archH - 0.2, CGFloat(i % 2 == 0 ? -1.3 : 1.5))
            world.addChildNode(em)
            let p = SCNParticleSystem()
            p.particleImage = SK.dotImage(size: 32, hardness: 0.5)
            p.birthRate = 5
            p.emissionDuration = 1
            p.loops = true
            p.birthDirection = .constant
            p.emittingDirection = SCNVector3(0, -1, 0)
            p.spreadingAngle = 4
            p.particleLifeSpan = 1.7
            p.particleLifeSpanVariation = 0.5
            p.particleVelocity = 2.4
            p.particleVelocityVariation = 0.6
            p.acceleration = SCNVector3(0, -6, 0)
            p.particleSize = 0.04
            p.particleSizeVariation = 0.015
            p.particleColor = SK.rgb(0xBFD4E2).withAlphaComponent(0.35)
            p.isAffectedByGravity = false
            p.blendMode = .additive
            p.isLightingEnabled = false
            em.addParticleSystem(p)
        }

        let hazeNode = SCNNode()
        hazeNode.position = SCNVector3(0, floorY(0) + 1.5, 0)
        world.addChildNode(hazeNode)
        let h = SCNParticleSystem()
        h.particleImage = SK.dotImage(size: 64, hardness: 0.05)
        h.birthRate = 26
        h.emissionDuration = 1
        h.loops = true
        h.birthDirection = .random
        h.spreadingAngle = 180
        h.emitterShape = SCNBox(width: 56, height: 2.6, length: 4.4, chamferRadius: 0)
        h.particleLifeSpan = 8
        h.particleLifeSpanVariation = 4
        h.particleVelocity = 0.06
        h.particleVelocityVariation = 0.06
        h.acceleration = SCNVector3(0, 0.03, 0)
        h.particleSize = 1.5
        h.particleSizeVariation = 0.7
        h.particleColor = SK.rgb(0x6E7886).withAlphaComponent(0.05)
        h.blendMode = .alpha
        h.isLightingEnabled = false
        h.sortingMode = .distance
        hazeNode.addParticleSystem(h)
        haze = h
    }

    // MARK: - Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        let gap = s.v("gap", 3.3)
        let o2 = s.v("o2", 20.3)
        let co2 = s.v("co2", 0.4)
        let ch4 = s.v("ch4", 0.6)
        let drill = s.v("drill", 0)
        let route = s.v("route", 0)
        let lamp = s.res("lamp")
        let dark = s.v("darkdays", 0) > 0.5 || (lamp < 1.5 && s.round > 2)

        // ---- water: it climbs the dip, and everything below it is gone
        waterSurface = floorY(0) + 0.12 - CGFloat(gap)
        water?.position.y = waterSurface

        // ---- bad air: more CO₂, murkier the beam of a lamp
        let murk = CGFloat(min(1, max(0, (co2 - 0.5) / 5.5)))
        scene.fogEndDistance = indoorVisibility * (1 - 0.4 * murk)
        haze?.birthRate = 22 + murk * 80
        haze?.particleColor = SK.rgb(0x6E7886).withAlphaComponent(CGFloat(0.03 + 0.08 * murk))
        ambientNode.light?.intensity = CGFloat(24 + 11 * (1 - murk))

        // ---- lamps: what is left of the batteries decides how much is lit
        let power: CGFloat = dark ? 0 : min(1, CGFloat(lamp) / 30)
        for (i, l) in capLamps.enumerated() {
            let alive = power > 0.08 && (i < 4 || power > 0.4)
            l.isHidden = !alive
            l.childNode(withName: "bulb", recursively: false)?.isHidden = !alive
            l.base = alive ? capLampBase[i] * max(0.4, power) : 0
        }
        let workOn = !dark && (lamp > 8 || s.round > 1)
        workLamp?.isHidden = !workOn
        workLamp?.base = workOn ? 82 : 0
        for (i, f) in fillLamps.enumerated() { f.base = dark ? fillBase[i] * 0.35 : fillBase[i] }

        // ---- the gas monitor: green while it is breathable, amber at 1 %, red above
        for (k, dot) in monitorLamps.enumerated() {
            let m = dot.geometry?.firstMaterial
            if ch4 >= 1.5 {
                m?.emission.contents = SK.rgb(0xFF2A18)
                m?.emission.intensity = k < 4 ? 1.6 : 0.4
            } else if ch4 >= 1.0 || co2 >= 3 {
                m?.emission.contents = SK.rgb(0xFFB020)
                m?.emission.intensity = k < 3 ? 1.2 : 0.25
            } else {
                m?.emission.contents = SK.rgb(0x35FF66)
                m?.emission.intensity = k < 2 ? 1.0 : 0.2
            }
        }

        // ---- the air pipe: mended and coupled, or still hanging in the water
        let mended = s.project("air_pipe") >= 0.999 || s.has("air_on")
        pipeMend?.isHidden = !mended
        pipeBroken?.isHidden = mended

        // ---- the guide rope, the dam, and the scouted route into the water
        rope?.isHidden = !(s.project("rope") >= 0.999 || s.has("guide_rope"))
        let damProg = CGFloat(s.project("dam"))
        dam?.isHidden = !(damProg > 0.2 || s.has("dam_built"))

        let shown = Int(CGFloat(routeMarks.count) * CGFloat(min(1, route / 100)))
        for (i, m) in routeMarks.enumerated() { m.isHidden = i >= shown }

        // ---- the seal wall, and 赵存柱 behind it
        sealHole?.isHidden = !s.has("seal_hole")
        let open = s.has("seal_open")
        sealWall?.isHidden = open
        sealOpen?.isHidden = !open

        // ---- the borehole: a drill rod through the roof, then food and letters
        let hit = s.has("lifeline") || s.has("hole_through") || s.happened("borehole_breakthrough")
        borehole?.isHidden = !hit
        drillRod?.isHidden = !hit
        if hit {
            drillGlow?.isHidden = false
            drillGlow?.base = s.happened("first_food") ? 1000 : 600
        } else if drill > 0 {
            drillGlow?.isHidden = false                  // still drilling: a knock overhead
            drillGlow?.base = 200
        } else {
            drillGlow?.isHidden = true
        }

        // ---- collapse, blast, rescue
        roofFall?.isHidden = !(s.happened("roof_fall") || s.has("roof_coming"))
        blastScorch?.isHidden = !s.happened("blast_after")
        blastFlash?.isHidden = !s.now("blast_after")
        rescueLight?.isHidden = !(s.has("boats_coming") || s.has("rescued") || s.ended)
        rescueLight?.base = s.has("rescued") ? 3200 : 2200

        // ---- 灰子 leaves when the air goes bad (老辈人的话：耗子先跑)
        rat?.isHidden = s.happened("rat_flees") || (o2 < 15 && co2 > 4.5)

        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: bodySpots())
    }

    // MARK: - Where everyone is

    /// The men keep to the dry rib and the deck; nobody stands in the lamp beams.
    private func spots(for s: SceneState) -> [Spot] {
        let deck = floorY(0) + platformY
        let crouch = s.v("gap", 3.3) < 1.2
        var out: [Spot] = []
        for p in s.people {
            switch p.id {
            case "he":                               // 贺小勇: the broken leg, on the deck
                out.append(Spot(-3.9, deck, 0.8, facing: -1.5, pose: .lying))
            case "wei":                              // 韦德贵: sitting with the injured man
                out.append(Spot(-4.5, deck, -0.2, facing: 0.6, pose: .sitting))
            case "wang":                             // 王福山: on the deck edge, watching the water
                out.append(Spot(-1.0, deck, 1.6, facing: 0.3, pose: .sitting))
            case "hao":                              // 郝建军: standing at the water line
                out.append(Spot(-3.2, floorY(-3.2) + 0.05, 1.55, facing: 0.2 + .pi, pose: .standing))
            case "shi":                              // 石磊: sitting on the sleeper ends, spent
                out.append(Spot(-11.6, floorY(-11.6) + 0.05, -1.6, facing: 1.3, pose: .sitting))
            case "tian":                             // 田立新: at the pipe with the tools out
                out.append(Spot(-5.0, floorY(-5.0) + 0.05, -1.6, facing: 1.4, pose: .sitting))
            case "xiaoman":                          // 罗小满: on the deck, making rope
                out.append(Spot(-0.4, deck, -1.0, facing: -0.7, pose: .sitting))
            case "zhao":                             // 赵存柱: just out of the breach
                out.append(Spot(-22.4, floorY(-22.4) + 0.05, -1.7, facing: 1.5, pose: .huddled))
            case "qiao":                             // 乔卫东: in his gear at the water's edge
                out.append(Spot(-9.2, floorY(-9.2) + 0.05, -1.9, facing: 0.3 + .pi, pose: .standing))
            case "rat":
                out.append(Spot(0.55, floorY(0) + capY + 0.30, 0.2, facing: -1.1, pose: .sitting))
            default:
                out.append(Spot(-2.0 - CGFloat(out.count) * 0.9, deck, 1.2, facing: 0.7,
                                pose: crouch ? .sitting : .standing))
            }
        }
        return out
    }

    /// The dead are laid out along the dry rib, above the water line, under blankets.
    private func bodySpots() -> [Spot] {
        let deck = floorY(0) + platformY
        var out: [Spot] = [Spot(-2.6, deck, 1.5, facing: 1.5)]
        for i in 1..<9 {
            let bx = -11.0 - CGFloat(i) * 1.6
            out.append(Spot(bx, floorY(bx) + 0.05, -1.85 + CGFloat(i % 2) * 0.25,
                            facing: i % 2 == 0 ? 1.55 : -1.55))
        }
        return out
    }
}
