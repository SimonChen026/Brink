import SceneKit
import AppKit
import simd

/// 废墟 — the void under a fallen floor slab: 锦华大厦, 3rd floor, east meeting room.
///
/// A section through the pancaked building, as if the half nearest the camera had been
/// lifted away. World axes: x → east, y ↑, z → south (toward the default camera); the cut
/// is the plane z = `zCut`. The room's floor is y = 0. The 4th-floor slab broke and came
/// down: its west part lies on the floor, its east part is propped 1.15 m up on a steel
/// filing cabinet and the conference table knocked over on its side — the 4.5 m triangular
/// void the six survivors, 老刘 and the dog are in. Above it the rest of the floors lie
/// stacked like plates, with rubble between; on top, the rescue crews. East of the room
/// stands the concrete stair core: its walls held, its flights hang broken, and grey light
/// comes down it from the open top.
///
/// The void is lit only by what the people have (phone screens and torches) and by a thin
/// beam of grey daylight through the crack in the east wall. The cut faces and the pile are
/// lit by the outside world (light category 2), so the void stays dark however the section
/// is lit.
///
/// Shown from state: the rescue shaft cut down through the slabs (var tunnel), the breach
/// and the searchlight (flag breakthrough), the crews, floodlights, flags and the tripod
/// (flag teams_here, var heard, flag found), the water tube through the crack (found);
/// cement dust in the air (var dust) and pouring from the cracks in an aftershock (flag
/// aftershock / strong_shock, low shelter); the water barrel under the toppled cabinet
/// (project bucket); the hole through the east wall into the stairwell (project stairwell,
/// flag stair_open, stair_vent); 老刘 pinned under the slab (flag pinned, slab_shored,
/// liu_freed); the phones (res battery, flags light_work / standby, var network); the
/// child in the gap above (flag kid_above); the dog's hole (flag hole_vent); rain seeping
/// through (weather); the extraction (flag rescued) and the climb out (flag self_rescue).
final class RubbleScene: ScenarioScene {

    // MARK: - Set-out (metres)

    private let zCut: CGFloat = 1.3          // the section plane
    private let zBack: CGFloat = -1.62       // crushed back of the void
    private let xHinge: CGFloat = -2.65      // where the fallen slab meets the floor
    private let slope: CGFloat = 0.2495      // its rise per metre (≈ 14°)
    private let xCore: CGFloat = 2.6         // west face of the stair core (east wall of the room)
    private let xCoreIn: CGFloat = 2.85      // inner face of that wall
    private let xCoreE: CGFloat = 5.4        // inner face of the core's east wall
    private let zCoreBack: CGFloat = -3.2
    private let coreTop: CGFloat = 6.1
    private let streetY: CGFloat = -2.2
    private let shaftX0: CGFloat = 0.62, shaftX1: CGFloat = 1.32
    private let shaftZ0: CGFloat = 0.3       // back of the rescue shaft
    private let holeX0: CGFloat = 0.72, holeX1: CGFloat = 1.24
    private let notchZ0: CGFloat = 0.62      // the hole through the east wall: z from here to the cut
    private let notchY1: CGFloat = 0.8
    private let pocketX0: CGFloat = -0.74, pocketX1: CGFloat = 0.4
    private let pocketZ0: CGFloat = 0.2

    /// Underside of the fallen slab over the void.
    private func hU(_ x: CGFloat) -> CGFloat { max(0, (x - xHinge) * slope) }
    private func l4Top(_ x: CGFloat) -> CGFloat { hU(x) + 0.22 }
    private func l5Under(_ x: CGFloat) -> CGFloat { 0.95 + (x + 2.9) * 0.25 }
    /// The section's outline: top of the pile along the cut.
    private func topY(_ x: CGFloat) -> CGFloat {
        if x <= -11.2 { return streetY }
        if x < -8.6 { return streetY + (2.25 - streetY) * CGFloat(SK.smoothstep(-11.2, -8.6, Float(x))) }
        if x <= 5.65 { return 2.25 + (min(x, 2.6) + 8.6) / 11.2 * 1.2 }
        if x < 9.8 { return streetY + (3.45 - streetY) * (1 - CGFloat(SK.smoothstep(5.65, 9.8, Float(x)))) }
        return streetY
    }
    /// Surface of the pile (z ≤ the cut); falls away to the street behind.
    private func surfY(_ x: CGFloat, _ z: CGFloat) -> CGFloat {
        let n = CGFloat(noise.fbm(Float(x) * 0.55 + 3, Float(z) * 0.55 - 7, octaves: 3)) - 0.5
        let back = CGFloat(SK.smoothstep(-9.5, -4.2, Float(z)))
        let t = topY(x) + n * 0.45 * back
        return streetY + (t - streetY) * back
    }

    // MARK: - Nodes

    private let noise = SK.Noise(seed: 1441)
    private let outside = SCNNode()          // section, pile, core, crews: lit by the outside world
    private let inside = SCNNode()           // the void: lit by what the trapped people have

    // materials
    private var concrete: SCNMaterial!
    private var rubbleVC: SCNMaterial!
    private var rebarMat: SCNMaterial!
    private var carpet: SCNMaterial!
    private var steel: SCNMaterial!
    private var oak: SCNMaterial!
    private var chrome: SCNMaterial!
    private var blackPlastic: SCNMaterial!
    private var paperVC: SCNMaterial!
    private var glass: SCNMaterial!
    private var timber: SCNMaterial!
    private var orange: SCNMaterial!

    // state-driven
    private var shaftPlugs: [(node: SCNNode, bottom: CGFloat)] = []
    private var skinPlug: SCNNode?
    private var holePlug: SCNNode?
    private var notchSlices: [SCNNode] = []
    private var crackLines: SCNNode?
    private var digRubble: [SCNNode] = []
    private var stairLight: SCNNode?
    private var bricks: [SCNNode] = []
    private var bucketBuried: SCNNode?
    private var bucketFree: SCNNode?
    private var bucketWater: SCNNode?
    private var cabinetDown: SCNNode?
    private var cabinetPried: SCNNode?
    private var shoreCabinet: SCNNode?
    private var lever: SCNNode?
    private var tableLegLever: SCNNode?
    private var shockDebris: SCNNode?
    private var cracks: [SCNNode] = []
    private var puddle: SCNNode?
    private var umbrellaOpen: SCNNode?
    private var umbrellaShut: SCNNode?
    private var tube: SCNNode?
    private var phoneUp: SCNNode?
    private var phoneStandby: SCNNode?
    private var standbyScreen: SCNMaterial?
    private var signalBars: [SCNNode] = []
    private var torch: SCNNode?

    private var crewTop: [SCNNode] = []
    private var listener: SCNNode?
    private var shaftCrew: SCNNode?
    private var breachCrew: SCNNode?
    private var tripod: SCNNode?
    private var rope: SCNNode?
    private var flags: [SCNNode] = []
    private var marker: SCNNode?
    private var floodTower: SCNNode?
    private var floodLamps: [SCNNode] = []
    private var floodBeams: [SCNNode] = []
    private var floodHeads: [SCNMaterial] = []
    private var beacon: SCNNode?
    private var generator: SCNNode?
    private var stretcher: SCNNode?
    private var blankets: [SCNNode] = []

    // lights
    private let fillNode = SCNNode()
    private let coreSky = SCNNode()
    private let crackSpot = SCNNode()
    private var crackBeam: SCNNode?
    private var stairBeam: SCNNode?
    private let ventSpot = SCNNode()
    private var ventBeam: SCNNode?
    private let phoneSpot = SCNNode()
    private let phoneBounce = SCNNode()
    private let standbyGlow = SCNNode()
    private let workSpot = SCNNode()
    private let shaftLamp = SCNNode()
    private var shaftLampBody: SCNNode?
    private let breachSpot = SCNNode()
    private var breachBeam: SCNNode?

    // particles
    private var hazeAll: SCNParticleSystem?
    private var hazePhone: SCNParticleSystem?
    private var motesPhone: SCNParticleSystem?
    private var hazeBeam: SCNParticleSystem?
    private var motesBeam: SCNParticleSystem?
    private var hazeBreach: SCNParticleSystem?
    private var motesBreach: SCNParticleSystem?
    private var dustFalls: [SCNParticleSystem] = []
    private var gravel: SCNParticleSystem?
    private var drips: SCNParticleSystem?
    private var rain: SCNParticleSystem?
    private var shaftDust: SCNParticleSystem?
    private var shockPuff: SCNParticleSystem?
    private var plumes: SCNParticleSystem?
    private let pocketGlow = SCNNode()

    private var dustedPeople: Set<ObjectIdentifier> = []
    /// Particle systems are attached on the first apply, once their rates are known, so their warm-up fills the air.
    private var pendingParticles: [(SCNNode, SCNParticleSystem)] = []
    private var particlesAttached = false
    private var skyKey = ""
    private var skyImage: NSImage?
    private var skyFog: NSColor = SK.rgb(0x0C1016)

    required init() {
        super.init()
        indoor = true
        indoorColor = SK.rgb(0x07090D)
        indoorVisibility = 140
        ssao = 0.5
        exposure = 0.35
        cameraTarget = SCNVector3(0.5, 1.45, 0.35)
        cameraDistance = 7.8
        cameraYaw = 7
        cameraPitch = 13
        cameraFOV = 36
        minPitch = 0
        cameraNode.camera?.vignettingIntensity = 0.75
        cameraNode.camera?.vignettingPower = 1.3
    }

    // MARK: - Build

    override func build(_ s: SceneState) {
        world.addChildNode(outside)
        world.addChildNode(inside)
        makeMaterials()
        buildGround()
        buildSlabs()
        buildSection()
        buildPileTop()
        buildCore()
        buildRoom()
        buildRescue()
        buildLights()
        buildParticles()
    }

    private func makeMaterials() {
        concrete = rbMat(SK.rgb(0x8F8D87), rough: 0.93, grain: 0.32, scale: 3.2, bump: 0.014, dust: 0.45)
        rubbleVC = rbMat(.white, rough: 0.95, grain: 0.35, scale: 6, bump: 0.02, dust: 0.3)
        rebarMat = rbMat(SK.rgb(0x5C4535), rough: 0.6, metal: 0.6, grain: 0.4, scale: 30, bump: 0, dust: 0.15)
        carpet = rbMat(SK.rgb(0x505965), rough: 1, grain: 0.35, scale: 22, bump: 0.003, dust: 0.62)
        steel = rbMat(SK.rgb(0xA6A497), rough: 0.42, metal: 0.55, grain: 0.12, scale: 4, bump: 0.002, dust: 0.4)
        oak = rbMat(SK.rgb(0x7B573B), rough: 0.5, grain: 0.3, scale: 9, bump: 0.001, dust: 0.35)
        chrome = rbMat(SK.rgb(0xB9BDC2), rough: 0.3, metal: 0.9, grain: 0.05, scale: 8, bump: 0, dust: 0.25)
        blackPlastic = rbMat(SK.rgb(0x222326), rough: 0.6, grain: 0.15, scale: 12, bump: 0.002, dust: 0.45)
        paperVC = rbMat(.white, rough: 0.95, grain: 0.1, scale: 10, bump: 0, dust: 0.3, doubleSided: true)
        glass = SK.mat(SK.rgb(0xA8C8D4), roughness: 0.04, metalness: 0.1, doubleSided: true)
        glass.transparency = 0.35
        glass.transparencyMode = .dualLayer
        timber = rbMat(SK.rgb(0xB08A5A), rough: 0.85, grain: 0.35, scale: 7, bump: 0.003, dust: 0.25)
        orange = rbMat(SK.rgb(0xE2621B), rough: 0.8, grain: 0.15, scale: 9, bump: 0, dust: 0.15)
    }

    // MARK: Street

    private func buildGround() {
        let asphalt = rbMat(SK.rgb(0x46474A), rough: 0.95, grain: 0.35, scale: 1.6, bump: 0.004, dust: 0.55)
        let g = SK.box(90, 0.4, 90, asphalt, chamfer: 0)
        g.position = SCNVector3(0, streetY - 0.2, 0)
        g.castsShadow = false
        outside.addChildNode(g)
        // a kerb and lane line on the street in front, so the cut reads as a building on a street
        let kerb = SK.box(60, 0.15, 0.3, concrete, chamfer: 0.01)
        kerb.position = SCNVector3(0, streetY + 0.07, 6.2)
        outside.addChildNode(kerb)
        let paint = rbMat(SK.rgb(0xCFCBBF), rough: 0.9, grain: 0.3, scale: 3, bump: 0, dust: 0.5)
        for i in 0..<8 {
            let l = SK.box(2.0, 0.01, 0.12, paint, chamfer: 0)
            l.position = SCNVector3(-14 + CGFloat(i) * 4, streetY + 0.005, 10.5)
            outside.addChildNode(l)
        }
        // debris spilled at the foot of the pile and of the cut
        var m = RBMesh()
        var rng = RBRand(77)
        for _ in 0..<260 {
            var x = rng.f(-12.5, 11.5)
            var z = rng.f(-11, Float(zCut) + 1.6)
            if z < Float(zCut) - 0.2 && x > -10.4 && x < 9.2 && z > -8.6 {
                // under the pile: push it out to the edge
                if rng.next() < 0.5 { x = rng.next() < 0.5 ? rng.f(-12.5, -10.6) : rng.f(9.2, 11.5) } else { z = rng.f(Float(zCut), Float(zCut) + 1.6) }
            }
            let sz = rng.f(0.08, 0.5)
            m.box(V3(x, Float(streetY) + sz * 0.25, z), V3(sz, sz * rng.f(0.35, 0.8), sz * rng.f(0.6, 1.3)),
                  rbQ(rng.f(0, 6.3), rng.f(-0.4, 0.4), rng.f(-0.4, 0.4)), jitter: 0.25, col: rbPalette(&rng), rng: &rng)
        }
        outside.addChildNode(m.node(rubbleVC))
    }

    // MARK: Slabs

    /// One straight run of slab: underside from (x0, y0) to (x1, y1), thickness t, z from za to zb.
    @discardableResult
    private func slab(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, t: CGFloat = 0.22,
                      za: CGFloat = -6, zb: CGFloat? = nil, parent: SCNNode? = nil) -> SCNNode {
        let dx = x1 - x0, dy = y1 - y0
        let len = sqrt(dx * dx + dy * dy)
        let ang = atan2(dy, dx)
        let z1 = zb ?? zCut
        let b = SK.box(len, t, z1 - za, concrete, chamfer: 0.012)
        b.position = SCNVector3((x0 + x1) / 2 - sin(ang) * t / 2, (y0 + y1) / 2 + cos(ang) * t / 2, (za + z1) / 2)
        b.eulerAngles.z = ang
        (parent ?? outside).addChildNode(b)
        return b
    }

    /// A piece of the run (x0,y0)→(x1,y1) between xa and xb.
    @discardableResult
    private func slabPart(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, from xa: CGFloat, to xb: CGFloat,
                          t: CGFloat = 0.22, za: CGFloat = -6, zb: CGFloat? = nil) -> SCNNode {
        let k = (y1 - y0) / (x1 - x0)
        return slab(xa, y0 + (xa - x0) * k, xb, y0 + (xb - x0) * k, t: t, za: za, zb: zb)
    }

    /// The slab lines in section (underside), with the runs that the rescue shaft cuts through.
    private struct Run { var x0, y0, x1, y1: CGFloat; var t: CGFloat; var shaft: Bool; var finish: Int = 0 }
    private var runs: [Run] {
        [
            Run(x0: -9.6, y0: -1.30, x1: 2.6, y1: -1.27, t: 0.22, shaft: false, finish: 2),   // 2nd floor (sunk onto the 1st)
            Run(x0: -9.6, y0: -0.25, x1: 2.6, y1: -0.25, t: 0.25, shaft: false, finish: 1),   // 3rd floor: the room's floor
            Run(x0: -9.0, y0: 0.30, x1: -2.74, y1: 0.02, t: 0.22, shaft: false, finish: 3),   // 4th floor (the day-care), west half
            Run(x0: -9.0, y0: 0.72, x1: -2.95, y1: 0.75, t: 0.2, shaft: false, finish: 1),    // 5th
            Run(x0: -2.9, y0: 0.95, x1: 2.5, y1: 2.3, t: 0.2, shaft: true, finish: 1),
            Run(x0: -9.0, y0: 1.18, x1: -3.25, y1: 1.24, t: 0.2, shaft: false, finish: 2),    // 6th
            Run(x0: -3.2, y0: 1.47, x1: 2.55, y1: 2.86, t: 0.2, shaft: true, finish: 2),
            Run(x0: -8.6, y0: 1.66, x1: -3.45, y1: 1.76, t: 0.2, shaft: false, finish: 4),    // 7th
            Run(x0: -3.4, y0: 1.95, x1: 2.55, y1: 3.2, t: 0.2, shaft: true, finish: 4),
            Run(x0: 5.65, y0: -0.25, x1: 7.9, y1: -0.3, t: 0.22, shaft: false, finish: 1),    // beyond the core: what's left of the east bay
            Run(x0: 5.65, y0: 0.62, x1: 7.4, y1: 0.35, t: 0.2, shaft: false, finish: 2),
            Run(x0: 5.65, y0: 1.5, x1: 6.9, y1: 1.05, t: 0.2, shaft: false),
        ]
    }

    private func buildSlabs() {
        var edge = RBMesh(), bars = RBMesh(), finish = RBMesh()
        var rng = RBRand(4)
        for r in runs {
            if r.shaft {
                slabPart(r.x0, r.y0, r.x1, r.y1, from: r.x0, to: shaftX0, t: r.t)
                slabPart(r.x0, r.y0, r.x1, r.y1, from: shaftX1, to: r.x1, t: r.t)
                slabPart(r.x0, r.y0, r.x1, r.y1, from: shaftX0, to: shaftX1, t: r.t, za: -6, zb: shaftZ0)
                let plug = slabPart(r.x0, r.y0, r.x1, r.y1, from: shaftX0, to: shaftX1, t: r.t, za: shaftZ0, zb: zCut)
                let k = (r.y1 - r.y0) / (r.x1 - r.x0)
                shaftPlugs.append((plug, r.y0 + ((shaftX0 + shaftX1) / 2 - r.x0) * k))
            } else {
                slab(r.x0, r.y0, r.x1, r.y1, t: r.t)
            }
            slabEdge(r.x0, r.y0, r.x1, r.y1, t: r.t, edge: &edge, bars: &bars, rng: &rng)
            finishLayer(r.x0, r.y0 + r.t, r.x1, r.y1 + r.t, kind: r.finish, mesh: &finish, rng: &rng)
        }
        // the fallen slab over the void, with the place the rescuers will cut through
        let y0: CGFloat = 0, y1 = hU(2.52)
        slabPart(xHinge, y0, 2.52, y1, from: xHinge, to: holeX0)
        slabPart(xHinge, y0, 2.52, y1, from: holeX1, to: 2.52)
        slabPart(xHinge, y0, 2.52, y1, from: holeX0, to: holeX1, za: -6, zb: 0.35)
        slabPart(xHinge, y0, 2.52, y1, from: holeX0, to: holeX1, za: 1.0, zb: zCut)
        holePlug = slabPart(xHinge, y0, 2.52, y1, from: holeX0, to: holeX1, za: 0.35, zb: 1.0)
        slabEdge(xHinge, y0, 2.52, y1, t: 0.22, edge: &edge, bars: &bars, rng: &rng)
        finishLayer(xHinge, y0 + 0.22, 2.52, y1 + 0.22, kind: 3, mesh: &finish, rng: &rng)
        // the hinge: crushed concrete where the slab broke over the floor
        for i in 0..<14 {
            let z = Float(zBack) - 0.3 + Float(i) * 0.24
            edge.box(V3(Float(xHinge) - 0.06, 0.12, z), V3(0.3, 0.2, 0.26), rbQ(rng.f(0, 3), rng.f(-0.5, 0.5), rng.f(-0.5, 0.5)),
                     jitter: 0.3, col: rbLin(0.55, 0.54, 0.51), rng: &rng)
        }
        outside.addChildNode(edge.node(rubbleVC))
        outside.addChildNode(bars.node(rebarMat))
        outside.addChildNode(finish.node(paperVC))
        crushedContents()
    }

    /// Floor finish on top of a run: 1 carpet, 2 tiles, 3 the day-care's foam mats, 4 laminate.
    private func finishLayer(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, kind: Int, mesh: inout RBMesh, rng: inout RBRand) {
        guard kind > 0 else { return }
        let k = Float((y1 - y0) / (x1 - x0))
        let ang = atan(k)
        let step: Float = kind == 3 ? 0.5 : 0.6
        var x = Float(x0) + 0.02
        var i = 0
        let mats: [V3] = [rbLin(0.74, 0.32, 0.28), rbLin(0.86, 0.72, 0.3), rbLin(0.32, 0.55, 0.74), rbLin(0.42, 0.66, 0.4)]
        while x < Float(x1) - 0.05 {
            let w = min(step, Float(x1) - 0.03 - x)
            let cx = x + w / 2
            defer { x += step; i += 1 }
            if cx > Float(shaftX0) - 0.1 && cx < Float(shaftX1) + 0.1 && Float(y0) > 0.5 { continue }
            if kind == 1 && Float(y0) < 0.05 && cx > Float(xHinge) - 0.35 { continue }      // the room itself has its own carpet
            let col: V3
            switch kind {
            case 1: col = rbLin(0.36, 0.4, 0.45) * rng.f(0.9, 1.05)
            case 2: col = rbLin(0.8, 0.76, 0.66) * rng.f(0.92, 1.05)
            case 3: col = mats[i % 4]
            default: col = rbLin(0.62, 0.48, 0.34) * rng.f(0.9, 1.05)
            }
            let cy = Float(y0) + (cx - Float(x0)) * k
            let th: Float = kind == 3 ? 0.035 : 0.02
            mesh.box(V3(cx, cy + th / 2 + 0.002, Float(zCut) - 1.2), V3(w / cos(ang) - 0.01, th, 2.42), rbQ(0, 0, ang), col: col, rng: &rng)
        }
    }

    /// Underside of each run at x (nil where the run doesn't reach).
    private func runBands(_ x: CGFloat) -> [(CGFloat, CGFloat)] {
        var lines: [(CGFloat, CGFloat)] = []          // (underside, top)
        var all = runs
        all.append(Run(x0: xHinge, y0: 0, x1: 2.52, y1: hU(2.52), t: 0.22, shaft: false))
        for r in all where x >= r.x0 && x <= r.x1 {
            let y = r.y0 + (x - r.x0) * (r.y1 - r.y0) / (r.x1 - r.x0)
            lines.append((y, y + r.t))
        }
        lines.sort { $0.0 < $1.0 }
        var bands: [(CGFloat, CGFloat)] = []
        for i in 0..<max(0, lines.count - 1) where lines[i + 1].0 - lines[i].1 > 0.12 {
            bands.append((lines[i].1, lines[i + 1].0))
        }
        if let last = lines.last { bands.append((last.1, surfY(x, zCut))) }
        return bands
    }

    /// What the floors were furnished with, flattened between the slabs: desks, cabinets,
    /// screens, chairs, binders, pipes — and the day-care's toys on the 4th.
    private func crushedContents() {
        var m = RBMesh(), pipes = RBMesh()
        var rng = RBRand(611)
        var n = 0
        while n < 95 {
            let x = rng.f(-10.6, 9.4)
            let bands = runBands(CGFloat(x))
            guard !bands.isEmpty else { continue }
            let b = bands[Int(rng.next() * Float(bands.count)) % bands.count]
            let gap = Float(b.1 - b.0)
            guard gap > 0.12 else { continue }
            let y = Float(b.0) + gap * rng.f(0.05, 0.55)
            guard !isOpen(x, y), !isOpen(x + 0.4, y), !isOpen(x - 0.4, y) else { continue }
            if x > Float(shaftX0) - 0.75 && x < Float(shaftX1) + 0.75 && y > 1.0 { continue }
            n += 1
            let z = Float(zCut) - rng.f(0.0, 0.1)
            let kind = rng.next()
            let tilt = rng.f(-0.12, 0.12)
            if kind < 0.3 {
                let col = rng.next() < 0.5 ? rbLin(0.84, 0.83, 0.8) : rbLin(0.72, 0.62, 0.48)
                m.box(V3(x, y + 0.02, z - 0.25), V3(rng.f(0.9, 1.5), 0.03, 0.7), rbQ(rng.f(-0.15, 0.15), 0, tilt), col: col, rng: &rng)
            } else if kind < 0.45 {
                m.box(V3(x, y + 0.06, z - 0.25), V3(rng.f(0.45, 0.9), min(gap * 0.5, rng.f(0.08, 0.2)), 0.6), rbQ(rng.f(-0.2, 0.2), 0, tilt),
                      jitter: 0.06, col: rbLin(0.66, 0.65, 0.6), rng: &rng)
            } else if kind < 0.57 {
                m.box(V3(x, y + 0.04, z - 0.1), V3(0.52, 0.04, 0.32), rbQ(rng.f(-0.4, 0.4), 0, tilt * 2), col: rbLin(0.07, 0.07, 0.08), rng: &rng)
            } else if kind < 0.7 {
                for j in 0..<Int(rng.f(2, 6)) {
                    let c: V3 = [rbLin(0.22, 0.36, 0.6), rbLin(0.62, 0.2, 0.18), rbLin(0.86, 0.85, 0.82), rbLin(0.2, 0.2, 0.22)][j % 4]
                    m.box(V3(x + Float(j) * 0.065, y + 0.05, z - 0.12), V3(0.055, 0.1, 0.28), rbQ(0, 0, rng.f(-0.9, 0.9)), col: c, rng: &rng)
                }
            } else if kind < 0.8 {
                m.box(V3(x, y + 0.04, z - 0.2), V3(0.5, 0.06, 0.48), rbQ(rng.f(0, 3), 0, tilt), col: rbLin(0.12, 0.12, 0.13), rng: &rng)
                pipes.rod([V3(x, y + 0.07, z - 0.2), V3(x + rng.f(-0.1, 0.1), y + min(0.3, gap * 0.6), z - 0.15)], r: 0.022, sides: 6, col: rbLin(0.6, 0.6, 0.62))
            } else if kind < 0.9 {
                let l = rng.f(0.8, 2.2)
                pipes.rod([V3(x - l / 2, y + 0.06, z - rng.f(0, 0.2)), V3(x + l / 2, y + 0.06 + rng.f(-0.05, 0.05), z - rng.f(0, 0.2))], r: rng.f(0.02, 0.05), sides: 7,
                          col: rng.next() < 0.5 ? rbLin(0.88, 0.88, 0.86) : rbLin(0.5, 0.5, 0.5))
            } else if y > 0.3 && y < 1.9 {
                // toys and little chairs from the day-care
                for j in 0..<4 {
                    let c: V3 = [rbLin(0.85, 0.3, 0.25), rbLin(0.95, 0.78, 0.25), rbLin(0.3, 0.55, 0.85), rbLin(0.4, 0.72, 0.4)][(j + n) % 4]
                    let s = rng.f(0.05, 0.1)
                    m.box(V3(x + Float(j) * 0.11, y + s / 2, z - rng.f(0, 0.1)), V3(s, s, s), rbQ(rng.f(0, 3), 0, rng.f(-0.5, 0.5)), col: c, rng: &rng)
                }
            }
        }
        outside.addChildNode(m.node(rubbleVC))
        outside.addChildNode(pipes.node(chrome))
    }

    /// Broken front edge and rebar ends along a slab run at the cut.
    private func slabEdge(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, t: CGFloat,
                          edge: inout RBMesh, bars: inout RBMesh, rng: inout RBRand) {
        let k = Float((y1 - y0) / (x1 - x0))
        let zc = Float(zCut)
        var x = Float(x0) + 0.1
        while x < Float(x1) - 0.05 {
            let yb = Float(y0) + (x - Float(x0)) * k
            let inShaft = x > Float(shaftX0) - 0.05 && x < Float(shaftX1) + 0.05 && yb > 0.5
            if !inShaft {
                if rng.next() < 0.3 {
                    let w = rng.f(0.1, 0.26)
                    edge.box(V3(x, yb + Float(t) * rng.f(0.35, 0.65), zc + rng.f(-0.04, 0.03)),
                             V3(w, Float(t) * rng.f(0.6, 1.05), rng.f(0.08, 0.16)),
                             rbQ(rng.f(-0.2, 0.2), rng.f(-0.3, 0.3), atan(k) + rng.f(-0.25, 0.25)),
                             jitter: 0.22, col: rbLin(0.58, 0.57, 0.54) * rng.f(0.85, 1.12), rng: &rng)
                }
                for layer in 0..<2 where rng.next() < 0.38 {
                    let yy = yb + (layer == 0 ? 0.045 : Float(t) - 0.045)
                    let len = rng.f(0.05, 0.42)
                    let droop = rng.f(0, 0.25) * len
                    let p0 = V3(x + rng.f(-0.05, 0.05), yy, zc - 0.06)
                    let p1 = V3(p0.x + rng.f(-0.06, 0.06), yy - droop * 0.3, zc + len * 0.55)
                    let p2 = V3(p1.x + rng.f(-0.08, 0.08), yy - droop, zc + len)
                    bars.rod([p0, p1, p2], r: 0.009, sides: 4, col: V3(1, 1, 1))
                }
            }
            x += rng.f(0.16, 0.3)
        }
    }

    // MARK: The cut face

    /// Is this point of the cut open (the void, the child's pocket, the shaft, inside the core)?
    private func isOpen(_ x: Float, _ y: Float) -> Bool {
        let cx = CGFloat(x), cy = CGFloat(y)
        if cx > xHinge && cx < xCore && cy > -0.02 && cy < hU(cx) + 0.02 { return true }
        if cx > pocketX0 && cx < pocketX1 {
            let mid = (pocketX0 + pocketX1) / 2, hw = (pocketX1 - pocketX0) / 2
            let u = (cx - mid) / hw
            let lo = l4Top(cx) - 0.02
            let top = min(l5Under(cx) - 0.05, lo + 0.66 * sqrt(max(0, 1 - u * u)) + 0.04 * sin(cx * 23))
            if cy > lo && cy < top { return true }
        }
        if cx > shaftX0 && cx < shaftX1 && cy > l4Top(cx) - 0.04 { return true }
        if cx > xCore && cx < xCoreE + 0.25 && cy > streetY { return true }
        return false
    }

    private func faceDepth(_ x: Float, _ y: Float) -> Float {
        Float(zCut) - 0.1 + (noise.fbm(x * 1.4 + 20, y * 1.4 - 4, octaves: 3) - 0.5) * 0.22
    }

    private func buildSection() {
        // the rubble between the slabs: one rough face over the whole cut
        let x0: Float = -11.3, x1: Float = 9.9
        let y0 = Float(streetY) - 0.02, y1: Float = 4.4
        var face = RBMesh()
        face.grid(176, 56, pos: { u, v in
            let x = x0 + (x1 - x0) * u
            var y = y0 + (y1 - y0) * v
            y = min(y, Float(self.surfY(CGFloat(x), self.zCut)) + 0.05)
            return V3(x, y, self.faceDepth(x, y))
        }, keep: { u, v in
            let x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * v
            return !self.isOpen(x, y) && y < Float(self.surfY(CGFloat(x), self.zCut)) + 0.12
        }, col: { p in self.rubbleColor(p) })
        outside.addChildNode(face.node(rubbleVC))

        // plugs of the same face over the shaft, removed as the rescuers dig down
        let sx0 = Float(shaftX0), sx1 = Float(shaftX1)
        let qx0 = sx0 - 0.06, qx1 = sx1 + 0.06
        let bottom = Float(l4Top((shaftX0 + shaftX1) / 2)) - 0.03
        let top = Float(surfY((shaftX0 + shaftX1) / 2, zCut)) + 0.08
        let bands = 9
        for b in 0..<bands {
            let ya = bottom + (top - bottom) * Float(b) / Float(bands)
            let yb = bottom + (top - bottom) * Float(b + 1) / Float(bands)
            var m = RBMesh()
            m.grid(6, 3, pos: { u, v in
                let x = qx0 + (qx1 - qx0) * u, y = ya + (yb - ya) * v
                return V3(x, y, self.faceDepth(x, y))
            }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) })
            let n = m.node(rubbleVC)
            outside.addChildNode(n)
            shaftPlugs.append((n, CGFloat(ya)))
        }

        // protruding rubble in the bands: broken blocks, ceiling tile, files, chair parts
        var bits = RBMesh()
        var rng = RBRand(19)
        var placed = 0
        while placed < 170 {
            let x = rng.f(x0 + 0.2, x1 - 0.2), y = rng.f(y0 + 0.1, 4.0)
            guard !isOpen(x, y), y < Float(surfY(CGFloat(x), zCut)) - 0.05 else { continue }
            if x > Float(shaftX0) - 0.1 && x < Float(shaftX1) + 0.1 && y > 1.0 { continue }
            placed += 1
            let sz = rng.f(0.03, 0.16)
            bits.box(V3(x, y, faceDepth(x, y) + rng.f(0.0, 0.08)), V3(sz * rng.f(0.8, 1.8), sz * rng.f(0.4, 1.0), sz * rng.f(0.6, 1.2)),
                     rbQ(rng.f(0, 6.3), rng.f(-0.6, 0.6), rng.f(-0.6, 0.6)), jitter: 0.25, col: rbPalette(&rng), rng: &rng)
        }
        // the edges of the child's pocket and of the void's west tip
        for _ in 0..<40 {
            let x = rng.f(Float(pocketX0), Float(pocketX1))
            let y = Float(l5Under(CGFloat(x))) - rng.f(0.0, 0.08)
            bits.box(V3(x, y, Float(zCut) - rng.f(0.0, 0.5)), V3(rng.f(0.06, 0.18), rng.f(0.04, 0.1), rng.f(0.06, 0.2)),
                     rbQ(rng.f(0, 6), rng.f(-0.5, 0.5), rng.f(-0.5, 0.5)), jitter: 0.3, col: rbPalette(&rng), rng: &rng)
        }
        outside.addChildNode(bits.node(rubbleVC))

        // the child's pocket: a closed little cave behind the opening
        var pk = RBMesh()
        let px0 = Float(pocketX0) - 0.08, px1 = Float(pocketX1) + 0.08
        let pz0 = Float(pocketZ0), pz1 = Float(zCut) - 0.16
        func pLo(_ x: Float) -> Float { Float(self.l4Top(CGFloat(x))) - 0.04 }
        pk.grid(14, 6, pos: { u, v in                                  // back
            let x = px0 + (px1 - px0) * u
            let y = pLo(x) + 0.78 * v
            return V3(x, y, pz0 + (self.noise.value(x * 5, y * 5) - 0.5) * 0.1)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) * 0.7 })
        pk.grid(14, 6, pos: { u, v in                                  // ceiling, facing down
            let x = px0 + (px1 - px0) * u
            let z = pz0 + (pz1 - pz0) * v
            return V3(x, pLo(x) + 0.72 + (self.noise.value(x * 5, z * 5) - 0.5) * 0.1, z)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) * 0.7 })
        for (side, flip) in [(px0 + 0.02, Float(1)), (px1 - 0.02, Float(-1))] {
            pk.grid(6, 5, pos: { u, v in
                let z = pz0 + (pz1 - pz0) * (flip > 0 ? u : 1 - u)
                let y = pLo(side) + 0.76 * v
                return V3(side + (self.noise.value(z * 4, y * 4) - 0.5) * 0.08, y, z)
            }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) * 0.7 })
        }
        // what the day-care left in it: a little chair, a satchel, crumbs of ceiling
        for _ in 0..<12 {
            let x = rng.f(px0 + 0.1, px1 - 0.1), z = rng.f(pz0 + 0.05, pz1)
            let sz = rng.f(0.04, 0.1)
            pk.box(V3(x, pLo(x) + 0.06 + sz * 0.3, z), V3(sz * 1.3, sz * 0.6, sz), rbQ(rng.f(0, 6), rng.f(-0.4, 0.4), rng.f(-0.4, 0.4)),
                   jitter: 0.3, col: rbPalette(&rng), rng: &rng)
        }
        pk.box(V3(0.18, pLo(0.18) + 0.2, 0.42), V3(0.28, 0.03, 0.28), rbQ(0.4, 0, 0.25), col: rbLin(0.9, 0.55, 0.2), rng: &rng)
        pk.box(V3(0.06, pLo(0.06) + 0.33, 0.36), V3(0.28, 0.22, 0.03), rbQ(0.4, 0, 0.25), col: rbLin(0.9, 0.55, 0.2), rng: &rng)
        pk.box(V3(-0.5, pLo(-0.5) + 0.13, 0.5), V3(0.3, 0.16, 0.12), rbQ(-0.3, 0, 0.1), jitter: 0.1, col: rbLin(0.62, 0.22, 0.24), rng: &rng)
        let pocketMat = rbMat(.white, rough: 0.95, grain: 0.3, scale: 6, bump: 0.015, dust: 0.08)
        outside.addChildNode(pk.node(pocketMat))

        // the shaft's walls and cribbing (seen once the plugs in front of them are dug out)
        var sw = RBMesh()
        let sb = Float(l4Top(shaftX0)) - 0.05, stp = top + 0.05
        sw.grid(7, 26, pos: { u, v in
            let x = sx0 + (sx1 - sx0) * u, y = sb + (stp - sb) * v
            return V3(x, y, Float(self.shaftZ0) + (self.noise.value(x * 6, y * 6) - 0.5) * 0.06)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) * 0.85 })
        for (side, dir) in [(sx0, Float(1)), (sx1, Float(-1))] {
            sw.grid(8, 26, pos: { u, v in
                let z = Float(self.shaftZ0) + (Float(self.zCut) - 0.12 - Float(self.shaftZ0)) * (dir > 0 ? u : 1 - u)
                let y = sb + (stp - sb) * v
                return V3(side + (self.noise.value(z * 6 + 3, y * 6) - 0.5) * 0.06, y, z)
            }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) * 0.85 })
        }
        outside.addChildNode(sw.node(rubbleVC))
        var crib = RBMesh()
        var y = Double(sb) + 0.35
        while y < Double(stp) - 0.1 {
            let yy = Float(y)
            crib.box(V3((sx0 + sx1) / 2, yy, Float(shaftZ0) + 0.05), V3(sx1 - sx0 - 0.02, 0.09, 0.07), rbQ(0, 0, 0), col: V3(1, 1, 1), rng: &rng)
            for sx in [sx0 + 0.04, sx1 - 0.04] {
                crib.box(V3(sx, yy, (Float(shaftZ0) + Float(zCut)) / 2 - 0.05), V3(0.07, 0.09, Float(zCut - shaftZ0) - 0.15), rbQ(0, 0, 0), col: V3(1, 1, 1), rng: &rng)
            }
            y += 0.55
        }
        let cribNode = crib.node(timber)
        outside.addChildNode(cribNode)
    }

    private func rubbleColor(_ p: V3) -> V3 {
        let a = noise.value(p.x * 1.9 + 11, p.y * 1.9 + p.z * 0.7)
        let b = noise.value(p.x * 4.7 - 5, p.y * 4.7 + 3)
        let c = noise.value(p.x * 9.1 + 2, p.y * 9.1 - 8)
        if b > 0.86 { return rbLin(0.46, 0.32, 0.26) * (0.8 + 0.3 * c) }     // brick
        if b < 0.12 { return rbLin(0.14, 0.135, 0.13) }                      // voids
        if a > 0.86 { return rbLin(0.66, 0.64, 0.6) }                        // plaster, ceiling tile
        return rbLin(0.44, 0.43, 0.41) * (0.7 + 0.45 * a) * (0.85 + 0.3 * c)
    }

    // MARK: Pile top

    private func buildPileTop() {
        var skin = RBMesh()
        let x0: Float = -11.8, x1: Float = 10.4, z0: Float = -10.5, z1 = Float(zCut) - 0.08
        skin.grid(118, 62, pos: { u, v in
            let x = x0 + (x1 - x0) * u
            let z = z1 - (z1 - z0) * v
            return V3(x, Float(self.surfY(CGFloat(x), CGFloat(z))), z)
        }, keep: { u, v in
            let x = CGFloat(x0 + (x1 - x0) * u), z = CGFloat(z1 - (z1 - z0) * v)
            if x > self.xCore + 0.05 && x < self.xCoreE + 0.2 && z > self.zCoreBack + 0.05 { return false }
            if x > self.shaftX0 && x < self.shaftX1 && z > self.shaftZ0 { return false }
            return true
        }, col: { p in self.rubbleColor(p) * 1.05 })
        outside.addChildNode(skin.node(rubbleVC))

        // the skin over the shaft, until the crews start cutting
        var sp = RBMesh()
        sp.grid(6, 8, pos: { u, v in
            let x = Float(self.shaftX0) - 0.04 + (Float(self.shaftX1 - self.shaftX0) + 0.08) * u
            let z = z1 - (z1 - Float(self.shaftZ0) + 0.06) * v
            return V3(x, Float(self.surfY(CGFloat(x), CGFloat(z))) + 0.01, z)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) })
        let spn = sp.node(rubbleVC)
        outside.addChildNode(spn)
        skinPlug = spn

        // broken slabs, blocks, rebar and window frames lying on top
        var top = RBMesh(), bars = RBMesh(), frames = RBMesh()
        var rng = RBRand(23)
        var n = 0
        while n < 420 {
            let x = rng.f(-10.8, 9.6), z = rng.f(-8.5, Float(zCut) - 0.15)
            let cx = CGFloat(x), cz = CGFloat(z)
            if cx > xCore - 0.1 && cx < xCoreE + 0.35 && cz > zCoreBack - 0.1 { continue }
            if cx > shaftX0 - 0.25 && cx < shaftX1 + 0.25 && cz > shaftZ0 - 0.25 { continue }
            n += 1
            let y = Float(surfY(cx, cz))
            if rng.next() < 0.07 {
                // a slab fragment
                let w = rng.f(0.7, 1.8), d = rng.f(0.5, 1.3)
                top.box(V3(x, y + 0.08, z), V3(w, 0.18, d), rbQ(rng.f(0, 6.3), rng.f(-0.35, 0.35), rng.f(-0.35, 0.35)),
                        jitter: 0.08, col: rbLin(0.6, 0.59, 0.56) * rng.f(0.85, 1.1), rng: &rng)
                if rng.next() < 0.7 {
                    for _ in 0..<Int(rng.f(2, 6)) {
                        let px = x + rng.f(-w / 2, w / 2), pz = z + rng.f(-d / 2, d / 2)
                        let len = rng.f(0.3, 1.1)
                        bars.rod([V3(px, y + 0.1, pz), V3(px + rng.f(-0.2, 0.2), y + 0.1 + len * 0.6, pz + rng.f(-0.2, 0.2)),
                                  V3(px + rng.f(-0.4, 0.4), y + 0.1 + len * rng.f(0.6, 1.0), pz + rng.f(-0.4, 0.4))], r: 0.011, sides: 4, col: V3(1, 1, 1))
                    }
                }
            } else {
                let sz = rng.f(0.06, 0.42)
                top.box(V3(x, y + sz * 0.2, z), V3(sz * rng.f(0.8, 1.6), sz * rng.f(0.4, 0.9), sz * rng.f(0.7, 1.3)),
                        rbQ(rng.f(0, 6.3), rng.f(-0.5, 0.5), rng.f(-0.5, 0.5)), jitter: 0.25, col: rbPalette(&rng), rng: &rng)
            }
        }
        // aluminium window frames off the façade, bent
        for i in 0..<5 {
            let x = rng.f(-9, 0.0) + Float(i) * 1.6, z = rng.f(-6, -1.5)
            let y = Float(surfY(CGFloat(x), CGFloat(z))) + 0.05
            let a = rng.f(0, 3.1), w: Float = 1.3, h: Float = 1.0
            let q = rbQ(a, rng.f(-0.25, 0.25), rng.f(-1.3, -0.9))
            let pts = [V3(-w / 2, 0, 0), V3(w / 2, 0, 0), V3(w / 2, h, 0.1), V3(-w / 2, h, 0.05), V3(-w / 2, 0, 0)].map { q.act($0) + V3(x, y + 0.4, z) }
            frames.rod(pts, r: 0.025, sides: 4, col: V3(1, 1, 1))
        }
        outside.addChildNode(top.node(rubbleVC))
        outside.addChildNode(bars.node(rebarMat))
        outside.addChildNode(frames.node(chrome))
    }

    // MARK: Stair core

    private func buildCore() {
        let y0 = streetY - 0.3
        func wall(_ xa: CGFloat, _ xb: CGFloat, _ ya: CGFloat, _ yb: CGFloat, _ za: CGFloat, _ zb: CGFloat) -> SCNNode {
            let b = SK.box(xb - xa, yb - ya, zb - za, concrete, chamfer: 0)
            b.position = SCNVector3((xa + xb) / 2, (ya + yb) / 2, (za + zb) / 2)
            outside.addChildNode(b)
            return b
        }
        // west wall (the room's east wall), with the hole the survivors dig at the cut
        _ = wall(xCore, xCoreIn, y0, coreTop, zCoreBack, notchZ0)
        _ = wall(xCore, xCoreIn, y0, 0, notchZ0, zCut)
        _ = wall(xCore, xCoreIn, notchY1, coreTop - 0.4, notchZ0, zCut)
        let sliceW = (xCoreIn - xCore) / 4
        for i in 0..<4 {
            notchSlices.append(wall(xCore + CGFloat(i) * sliceW, xCore + CGFloat(i + 1) * sliceW, 0, notchY1, notchZ0, zCut))
        }
        // east and back walls; the east one broke off lower
        _ = wall(xCoreE, xCoreE + 0.25, y0, coreTop - 0.7, zCoreBack, zCut)
        _ = wall(xCore, xCoreE + 0.25, y0, coreTop + 0.3, zCoreBack, zCoreBack + 0.25)

        var m = RBMesh(), bars = RBMesh()
        var rng = RBRand(31)
        // jagged tops
        for (xa, xb, yt, za, zb) in [(xCore, xCoreIn, coreTop, zCoreBack, notchZ0), (xCore, xCoreIn, coreTop - 0.4, notchZ0, zCut),
                                     (xCoreE, xCoreE + 0.25, coreTop - 0.7, zCoreBack, zCut), (xCore, xCoreE + 0.25, coreTop + 0.3, zCoreBack, zCoreBack + 0.25)] {
            let horizontal = (xb - xa) > (zb - za)
            let len = Float(horizontal ? xb - xa : zb - za)
            var t: Float = 0.05
            while t < len {
                let px = horizontal ? Float(xa) + t : Float(xa + xb) / 2
                let pz = horizontal ? Float(za + zb) / 2 : Float(za) + t
                m.box(V3(px, Float(yt) + rng.f(-0.05, 0.12), pz), V3(horizontal ? rng.f(0.15, 0.35) : 0.28, rng.f(0.12, 0.4), horizontal ? 0.28 : rng.f(0.15, 0.35)),
                      rbQ(rng.f(-0.3, 0.3), rng.f(-0.3, 0.3), rng.f(-0.3, 0.3)), jitter: 0.25, col: rbLin(0.58, 0.57, 0.54), rng: &rng)
                if rng.next() < 0.6 {
                    let p0 = V3(px + rng.f(-0.08, 0.08), Float(yt), pz + rng.f(-0.08, 0.08))
                    bars.rod([p0, p0 + V3(rng.f(-0.1, 0.1), rng.f(0.2, 0.5), rng.f(-0.1, 0.1)), p0 + V3(rng.f(-0.35, 0.35), rng.f(0.4, 0.9), rng.f(-0.35, 0.35))],
                             r: 0.011, sides: 4, col: V3(1, 1, 1))
                }
                t += rng.f(0.18, 0.32)
            }
        }
        // the broken edges of the hole through the wall
        for i in 0..<16 {
            let t = Float(i) / 15
            let onTop = i < 8
            let p = onTop ? V3(Float(xCore) + 0.03 + t * 2 * 0.22, Float(notchY1) + rng.f(-0.02, 0.06), Float(zCut) - rng.f(0.02, 0.6))
                          : V3(Float(xCore) + rng.f(0.0, 0.25), (t - 0.5) * 2 * Float(notchY1), Float(notchZ0) + rng.f(-0.04, 0.04))
            m.box(p, V3(rng.f(0.06, 0.14), rng.f(0.05, 0.12), rng.f(0.06, 0.14)), rbQ(rng.f(0, 6), rng.f(-0.6, 0.6), rng.f(-0.6, 0.6)),
                  jitter: 0.3, col: rbLin(0.6, 0.59, 0.56), rng: &rng)
        }

        // inside the core: the debris mound at the bottom, reaching up to the hole
        let mx0 = Float(xCoreIn), mx1 = Float(xCoreE), mz0 = Float(zCoreBack) + 0.25, mz1 = Float(zCut) - 0.03
        func mound(_ x: Float, _ z: Float) -> Float {
            let d = sqrt((x - mx0) * (x - mx0) * 0.8 + (z - Float(zCut)) * (z - Float(zCut)) * 0.35)
            return -0.06 - 1.55 * SK.smoothstep(0.2, 2.3, d) + (noise.value(x * 3, z * 3) - 0.5) * 0.18
        }
        m.grid(26, 40, pos: { u, v in
            let x = mx0 + (mx1 - mx0) * u, z = mz1 - (mz1 - mz0) * v
            return V3(x, mound(x, z), z)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) })
        m.grid(26, 8, pos: { u, v in
            let x = mx0 + (mx1 - mx0) * u
            let yt = mound(x, mz1)
            let y = Float(self.streetY) + (yt - Float(self.streetY)) * v
            return V3(x, y, Float(self.zCut) - 0.03 + (self.noise.value(x * 5, y * 5) - 0.5) * 0.08)
        }, keep: { _, _ in true }, col: { p in self.rubbleColor(p) })
        for _ in 0..<90 {
            let x = rng.f(mx0 + 0.1, mx1 - 0.1), z = rng.f(mz0 + 0.1, mz1 - 0.05)
            let sz = rng.f(0.06, 0.4)
            m.box(V3(x, mound(x, z) + sz * 0.15, z), V3(sz * rng.f(0.8, 1.6), sz * rng.f(0.3, 0.8), sz), rbQ(rng.f(0, 6), rng.f(-0.5, 0.5), rng.f(-0.5, 0.5)),
                  jitter: 0.25, col: rbPalette(&rng), rng: &rng)
        }

        // the flights: up toward the back, landing, broken flight back to the front, landing, up again
        let laneW: Float = 2.42 / 2 - 0.08
        let wX = Float(xCoreIn) + 0.06 + laneW / 2, eX = Float(xCoreE) - 0.06 - laneW / 2
        func flight(_ m: inout RBMesh, x: Float, zA: Float, yA: Float, zB: Float, yB: Float, from s0: Int = 0, to s1: Int = 10) {
            let n = 10
            for s in s0..<s1 {
                let t0 = Float(s) / Float(n), t1 = Float(s + 1) / Float(n)
                let za = zA + (zB - zA) * t0, zb = zA + (zB - zA) * t1
                let ytop = yA + (yB - yA) * t1
                m.box(V3(x, ytop - 0.09, (za + zb) / 2), V3(laneW, 0.18, abs(zb - za) + 0.01), rbQ(0, 0, 0), col: rbLin(0.62, 0.61, 0.58), rng: &rng)
            }
            // the waist under the steps
            let ta = Float(s0) / Float(n), tb = Float(s1) / Float(n)
            let pa = V3(x, yA + (yB - yA) * ta - 0.2, zA + (zB - zA) * ta), pb = V3(x, yA + (yB - yA) * tb - 0.2, zA + (zB - zA) * tb)
            let mid = (pa + pb) / 2
            let d = pb - pa
            let ang = atan2(d.y, -d.z * (zB < zA ? 1 : -1))
            m.box(mid, V3(laneW, 0.14, simd_length(d)), rbQ(0, zB < zA ? ang : -ang, 0), col: rbLin(0.55, 0.54, 0.51), rng: &rng)
        }
        var st = RBMesh()
        let zF: Float = 0.9, zR: Float = -1.55
        flight(&st, x: wX, zA: zF, yA: 0.0, zB: zR, yB: 1.62)
        st.box(V3((Float(xCoreIn) + Float(xCoreE)) / 2, 1.53, (Float(zCoreBack) + 0.25 + zR) / 2), V3(Float(xCoreE - xCoreIn), 0.18, zR - Float(zCoreBack) - 0.25),
               rbQ(0, 0.03, -0.035), col: rbLin(0.6, 0.59, 0.56), rng: &rng)
        flight(&st, x: eX, zA: zR, yA: 1.62, zB: zF, yB: 3.24, from: 0, to: 4)
        st.box(V3((Float(xCoreIn) + Float(xCoreE)) / 2, 3.15, (zF + Float(zCut)) / 2), V3(Float(xCoreE - xCoreIn), 0.18, Float(zCut) - zF),
               rbQ(0, -0.02, 0.03), col: rbLin(0.6, 0.59, 0.56), rng: &rng)
        flight(&st, x: wX, zA: zF, yA: 3.24, zB: zR, yB: 4.86)
        st.box(V3((Float(xCoreIn) + Float(xCoreE)) / 2, 4.77, (Float(zCoreBack) + 0.25 + zR) / 2), V3(Float(xCoreE - xCoreIn), 0.18, zR - Float(zCoreBack) - 0.25),
               rbQ(0, 0.02, 0.04), col: rbLin(0.6, 0.59, 0.56), rng: &rng)
        let stairs = st.node(rubbleVC)
        stairs.eulerAngles = SCNVector3(0.0, 0.0, -0.035)          // the whole core has a lean
        outside.addChildNode(stairs)
        // the upper half of the broken flight hangs from the front landing
        var hang = RBMesh()
        flight(&hang, x: 0, zA: -1.25, yA: -1.62 * 0.5, zB: 0, yB: 0, from: 5, to: 10)
        let hangNode = hang.node(rubbleVC)
        hangNode.position = SCNVector3(CGFloat(eX), 3.24, CGFloat(zF))
        hangNode.eulerAngles.x = 0.55
        outside.addChildNode(hangNode)
        // rebar like tangled wire where the flight tore, handrails bent
        for _ in 0..<26 {
            let p0 = V3(eX + rng.f(-0.5, 0.5), rng.f(1.55, 1.75), zR + rng.f(0.2, 0.9))
            bars.rod([p0, p0 + V3(rng.f(-0.3, 0.3), rng.f(0.1, 0.5), rng.f(0.1, 0.6)), p0 + V3(rng.f(-0.5, 0.5), rng.f(-0.2, 0.7), rng.f(0.2, 1.2))],
                     r: 0.01, sides: 4, col: V3(1, 1, 1))
        }
        for _ in 0..<14 {
            let p0 = V3(eX + rng.f(-0.5, 0.5), 2.9, zF - rng.f(0.2, 0.9))
            bars.rod([p0, p0 + V3(rng.f(-0.2, 0.2), rng.f(-0.5, -0.1), rng.f(-0.2, 0.2)), p0 + V3(rng.f(-0.4, 0.4), rng.f(-1.0, -0.4), rng.f(-0.4, 0.4))],
                     r: 0.01, sides: 4, col: V3(1, 1, 1))
        }
        let railX = Float(xCoreIn + xCoreE) / 2
        bars.rod([V3(railX, 0.9, zF), V3(railX + 0.03, 1.7, -0.3), V3(railX - 0.05, 2.45, zR), V3(railX + 0.1, 2.5, zR - 0.6)], r: 0.018, sides: 5, col: V3(1, 1, 1))
        bars.rod([V3(railX, 4.15, zF), V3(railX, 4.9, -0.4), V3(railX + 0.04, 5.6, zR)], r: 0.018, sides: 5, col: V3(1, 1, 1))
        outside.addChildNode(m.node(rubbleVC))
        outside.addChildNode(bars.node(rebarMat))

        // the crack through the wall before anyone digs (dark zigzag on the cut face)
        var cr = RBMesh()
        let cz = Float(zCut) + 0.004
        let crackPts: [V3] = [V3(2.62, 0.08, cz), V3(2.7, 0.3, cz), V3(2.66, 0.52, cz), V3(2.75, 0.71, cz), V3(2.71, 0.98, cz), V3(2.8, 1.25, cz), V3(2.77, 1.5, cz)]
        cr.rod(crackPts, r: 0.012, sides: 4, col: V3(0.02, 0.02, 0.02))
        let crack = cr.node(SK.mat(.black, roughness: 1))
        outside.addChildNode(crack)
        crackLines = crack

        // dug-out rubble by the hole, growing as the hole does
        for i in 0..<3 {
            var d = RBMesh()
            var r2 = RBRand(UInt64(40 + i))
            for _ in 0..<(12 + i * 6) {
                let x = r2.f(2.05, 2.52), z = r2.f(Float(notchZ0) - 0.1, Float(zCut) - 0.05)
                let sz = r2.f(0.05, 0.16)
                d.box(V3(x, sz * 0.3 + Float(i) * 0.05, z), V3(sz * 1.3, sz * 0.7, sz), rbQ(r2.f(0, 6), r2.f(-0.5, 0.5), r2.f(-0.5, 0.5)),
                      jitter: 0.25, col: r2.next() < 0.4 ? rbLin(0.55, 0.34, 0.26) : rbLin(0.6, 0.59, 0.56), rng: &r2)
            }
            let dn = d.node(rubbleVC)
            dn.isHidden = true
            inside.addChildNode(dn)
            digRubble.append(dn)
        }
    }

    // MARK: The room

    private func buildRoom() {
        // carpet tiles
        let c = SK.box(xCore - xHinge + 0.6, 0.012, zCut - zBack + 0.3, carpet, chamfer: 0)
        c.position = SCNVector3((xCore + xHinge) / 2 - 0.3, 0.006, (zCut + zBack) / 2 - 0.15)
        inside.addChildNode(c)

        // the crushed back of the void, with the dog's hole in the north-west corner
        var back = RBMesh()
        let bx0 = Float(xHinge) - 0.1, bx1 = Float(xCore)
        back.grid(48, 12, pos: { u, v in
            let x = bx0 + (bx1 - bx0) * u
            let y = (Float(self.hU(CGFloat(x))) + 0.06) * v - 0.01
            return V3(x, y, Float(self.zBack) + (self.noise.value(x * 4 + 9, y * 4) - 0.5) * 0.14)
        }, keep: { u, v in
            let x = bx0 + (bx1 - bx0) * u
            let y = (Float(self.hU(CGFloat(x))) + 0.06) * v
            let dx = (x + 1.3) / 0.17, dy = (y - 0.13) / 0.12
            return dx * dx + dy * dy > 1
        }, col: { p in self.rubbleColor(p) * 0.9 })
        var rng = RBRand(57)
        for _ in 0..<80 {
            let x = rng.f(bx0 + 0.2, bx1 - 0.05)
            if abs(x + 1.3) < 0.25 { continue }
            let h = Float(hU(CGFloat(x)))
            let sz = min(rng.f(0.05, 0.22), max(0.05, h * 0.6))
            back.box(V3(x, sz * 0.35, Float(zBack) + rng.f(0.0, 0.25)), V3(sz * 1.4, sz * 0.7, sz), rbQ(rng.f(0, 6), rng.f(-0.4, 0.4), rng.f(-0.4, 0.4)),
                     jitter: 0.25, col: rbPalette(&rng), rng: &rng)
        }
        inside.addChildNode(back.node(rubbleVC))

        // the conference table knocked over on its side: the top is the void's east wall
        let table = SCNNode()
        let top = SK.box(0.045, 1.15, 1.37, oak, chamfer: 0.01)
        top.position = SCNVector3(0, 0.575, 0)
        table.addChildNode(top)
        let apronMat = blackPlastic!
        for (yy, zz, h, l) in [(0.09, 0.0, 0.08, 1.2), (1.06, 0.0, 0.08, 1.2)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let a = SK.box(0.08, h, l, apronMat, chamfer: 0.005)
            a.position = SCNVector3(0.06, yy, zz)
            table.addChildNode(a)
        }
        var legs: [SCNNode] = []
        for (yy, zz) in [(0.12, -0.6), (1.03, -0.6), (0.12, 0.6), (1.03, 0.6)] as [(CGFloat, CGFloat)] {
            let leg = SK.box(0.56, 0.05, 0.05, chrome, chamfer: 0.01)
            leg.position = SCNVector3(0.3, yy, zz)
            table.addChildNode(leg)
            legs.append(leg)
        }
        tableLegLever = legs[2]
        table.position = SCNVector3(1.975, 0, -0.235)
        table.eulerAngles.y = 0.02
        inside.addChildNode(table)

        // the upright cabinet the slab rests on; the one that fell on the water barrel
        let upright = cabinet()
        upright.eulerAngles.y = -.pi / 2
        upright.position = SCNVector3(2.24, 0, -1.28)
        upright.eulerAngles.z = -0.02
        inside.addChildNode(upright)

        let down = cabinet()
        down.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2 - 0.15)
        down.position = SCNVector3(1.78, 0.235, -1.3)
        inside.addChildNode(down)
        cabinetDown = down
        let pried = cabinet()
        pried.eulerAngles = SCNVector3(0, 0.3, CGFloat.pi / 2)
        pried.position = SCNVector3(1.82, 0.235, -1.36)
        pried.isHidden = true
        inside.addChildNode(pried)
        cabinetPried = pried
        let shore = cabinet()
        shore.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        shore.position = SCNVector3(0.43, 0.235, -1.24)
        shore.isHidden = true
        inside.addChildNode(shore)
        shoreCabinet = shore

        // the 18.9 L barrel: buried under the cabinet and the bricks, or out and upright
        let buried = barrel(fill: 1)
        buried.node.eulerAngles = SCNVector3(0, 0.5, CGFloat.pi / 2)
        buried.node.position = SCNVector3(0.98, 0.135, -1.18)
        inside.addChildNode(buried.node)
        bucketBuried = buried.node
        let free = barrel(fill: 1)
        free.node.position = SCNVector3(-0.2, 0, 1.1)
        free.node.isHidden = true
        inside.addChildNode(free.node)
        bucketFree = free.node
        bucketWater = free.water

        for g in 0..<4 {
            var b = RBMesh()
            var r2 = RBRand(UInt64(90 + g))
            for _ in 0..<14 {
                let x = r2.f(0.55, 1.75) , z = r2.f(-1.05, -0.78) + Float(g) * 0.02
                let y = r2.f(0.0, 0.18) + Float(3 - g) * 0.06
                b.box(V3(x, y + 0.03, z), V3(r2.f(0.12, 0.24), 0.055, r2.f(0.1, 0.115)), rbQ(r2.f(0, 6), r2.f(-0.5, 0.5), r2.f(-0.5, 0.5)),
                      jitter: 0.12, col: r2.next() < 0.7 ? rbLin(0.58, 0.32, 0.24) * r2.f(0.8, 1.1) : rbLin(0.62, 0.61, 0.58), rng: &r2)
            }
            let bn = b.node(rubbleVC)
            inside.addChildNode(bn)
            bricks.append(bn)
        }

        // the lever they made of a table leg, under the slab by 老刘
        var lv = RBMesh()
        lv.rod([V3(-1.95, 0.05, 0.62), V3(-1.4, 0.13, 0.7), V3(-0.85, 0.32, 0.8)], r: 0.026, sides: 5, col: V3(1, 1, 1))
        let lvn = lv.node(chrome)
        lvn.isHidden = true
        inside.addChildNode(lvn)
        lever = lvn

        // office chairs
        let ch2 = chair()
        ch2.scale = SCNVector3(1, 0.42, 1)
        ch2.eulerAngles = SCNVector3(0.1, 2.2, 0.15)
        ch2.position = SCNVector3(-2.0, 0.0, -0.75)
        inside.addChildNode(ch2)

        // the ceiling that came down with the slab: tiles, T-bar, a light panel on its wires
        var tiles = RBMesh(), keel = RBMesh()
        for _ in 0..<22 {
            let x = rng.f(-2.1, 1.85), z = rng.f(Float(zBack) + 0.2, Float(zCut) - 0.1)
            let s = rng.f(0.25, 0.6)
            let lift = rng.next() < 0.25 ? rng.f(0.05, 0.3) : 0
            let h = Float(hU(CGFloat(x)))
            tiles.box(V3(x, 0.02 + min(lift, h * 0.4), z), V3(s, 0.014, s * rng.f(0.5, 1.0)), rbQ(rng.f(0, 6), rng.f(-0.3, 0.3) * (lift > 0 ? 1 : 0.1), rng.f(-0.5, 0.5) * (lift > 0 ? 1 : 0.1)),
                      jitter: 0.04, col: rbLin(0.86, 0.85, 0.81) * rng.f(0.85, 1.0), rng: &rng)
        }
        for i in 0..<9 {
            let x = -1.4 + Float(i) * 0.4 + rng.f(-0.1, 0.1)
            let z = rng.f(Float(zBack) + 0.3, Float(zCut) - 0.2)
            let h = Float(hU(CGFloat(x)))
            guard h > 0.35 else { continue }
            let p0 = V3(x, h - 0.01, z)
            keel.rod([p0, p0 + V3(rng.f(-0.15, 0.15), -h * rng.f(0.2, 0.45), rng.f(-0.2, 0.2)), p0 + V3(rng.f(-0.4, 0.4), -h * rng.f(0.5, 0.9), rng.f(-0.4, 0.4))],
                     r: 0.009, sides: 4, col: V3(1, 1, 1))
        }
        inside.addChildNode(tiles.node(paperVC))
        inside.addChildNode(keel.node(chrome))
        let panel = SK.box(0.6, 0.03, 0.6, rbMat(SK.rgb(0xE4E2DC), rough: 0.5, grain: 0.05, scale: 5, bump: 0, dust: 0.4), chamfer: 0.005)
        panel.position = SCNVector3(1.42, 0.62, -1.15)
        panel.eulerAngles = SCNVector3(0.5, 0.3, 0.75)
        inside.addChildNode(panel)

        // papers, glass from the partition, office odds and ends
        var paper = RBMesh(), shards = RBMesh()
        for _ in 0..<34 {
            let x = rng.f(-2.0, 1.9), z = rng.f(Float(zBack) + 0.15, Float(zCut) - 0.05)
            paper.box(V3(x, 0.016 + rng.f(0, 0.01), z), V3(0.21, 0.002, 0.297), rbQ(rng.f(0, 6), rng.f(-0.06, 0.06), rng.f(-0.06, 0.06)),
                      col: rng.next() < 0.85 ? rbLin(0.9, 0.9, 0.88) : rbLin(0.85, 0.75, 0.5), rng: &rng)
        }
        for _ in 0..<70 {
            let x = rng.f(-1.8, 2.4), z = rng.f(0.3, Float(zCut) - 0.02)
            let a = V3(x, 0.018, z)
            let s = rng.f(0.03, 0.12)
            shards.tri(a, a + V3(rng.f(-s, s), rng.f(0, 0.01), rng.f(0.3, 1) * s), a + V3(rng.f(0.3, 1) * s, rng.f(0, 0.01), rng.f(-s, s)), V3(1, 1, 1))
        }
        inside.addChildNode(paper.node(paperVC))
        let sh = shards.node(glass)
        sh.castsShadow = false
        inside.addChildNode(sh)

        // the rider's yellow insulated box and helmet, a first-aid kit, a laptop, bottles
        let yellow = rbMat(SK.rgb(0xE3B321), rough: 0.6, grain: 0.1, scale: 6, bump: 0, dust: 0.35)
        let box = SK.box(0.42, 0.36, 0.38, yellow, chamfer: 0.03)
        box.position = SCNVector3(-0.98, 0.18, -1.3)
        box.eulerAngles = SCNVector3(0, 0.3, 0.06)
        inside.addChildNode(box)
        let helmet = SK.sphere(0.15, yellow, segments: 16)
        helmet.scale = SCNVector3(1, 0.75, 1.15)
        helmet.position = SCNVector3(-0.48, 0.06, -1.25)
        inside.addChildNode(helmet)
        let kit = SK.box(0.3, 0.12, 0.2, rbMat(SK.rgb(0xE8E6E0), rough: 0.5, grain: 0.05, scale: 6, bump: 0, dust: 0.3), chamfer: 0.015)
        kit.position = SCNVector3(1.12, 0.06, 1.0)
        kit.eulerAngles.y = 0.4
        let crossMat = SK.mat(SK.rgb(0xC8241E), roughness: 0.6)
        let c1 = SK.box(0.12, 0.004, 0.035, crossMat, chamfer: 0); c1.position.y = 0.061
        let c2 = SK.box(0.035, 0.004, 0.12, crossMat, chamfer: 0); c2.position.y = 0.061
        kit.addChildNode(c1); kit.addChildNode(c2)
        inside.addChildNode(kit)
        let laptop = SK.box(0.32, 0.02, 0.22, chrome, chamfer: 0.008)
        laptop.position = SCNVector3(0.6, 0.02, -0.95)
        laptop.eulerAngles.y = -0.5
        inside.addChildNode(laptop)
        let bottleMat = SK.mat(SK.rgb(0xCFE3EE), roughness: 0.08, doubleSided: false)
        bottleMat.transparency = 0.5
        for (i, p) in [(0.95, 0.75), (1.3, 0.62)].enumerated() {
            let b = SK.cylinder(0.032, 0.21, bottleMat)
            b.position = SCNVector3(p.0, 0.035, p.1)
            b.eulerAngles = SCNVector3(0, 0, i == 0 ? CGFloat.pi / 2 : 0)
            if i == 1 { b.position.y = 0.105 }
            inside.addChildNode(b)
        }

        // the long umbrella: folded on the floor, or opened upside down under the leak
        let umbrella = SCNNode()
        let shaftN = SK.cylinder(0.008, 0.95, chrome)
        shaftN.eulerAngles.z = .pi / 2
        umbrella.addChildNode(shaftN)
        let fold = SCNNode(geometry: SCNCone(topRadius: 0.01, bottomRadius: 0.05, height: 0.62))
        fold.geometry?.materials = [blackPlastic]
        fold.eulerAngles.z = .pi / 2
        fold.position.x = 0.1
        umbrella.addChildNode(fold)
        umbrella.position = SCNVector3(1.05, 0.03, 1.22)
        umbrella.eulerAngles.y = 0.15
        inside.addChildNode(umbrella)
        umbrellaShut = umbrella
        let openU = SCNNode()
        let canopy = SCNNode(geometry: SCNCone(topRadius: 0.46, bottomRadius: 0.03, height: 0.26))
        canopy.geometry?.materials = [rbMat(SK.rgb(0x1C1D21), rough: 0.5, grain: 0.1, scale: 8, bump: 0, dust: 0.15, doubleSided: true)]
        canopy.position.y = 0.15
        openU.addChildNode(canopy)
        let water = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.01))
        let wm = SK.mat(SK.rgb(0x6F7E86), roughness: 0.05)
        wm.transparency = 0.7
        water.geometry?.materials = [wm]
        water.position.y = 0.16
        openU.addChildNode(water)
        let handle = SK.cylinder(0.008, 0.5, chrome)
        handle.position.y = 0.2
        handle.eulerAngles.z = 0.25
        openU.addChildNode(handle)
        openU.position = SCNVector3(-0.62, 0, 1.02)
        openU.isHidden = true
        inside.addChildNode(openU)
        umbrellaOpen = openU

        // a puddle on the carpet when heavy rain comes through
        let pud = SCNNode(geometry: SCNCylinder(radius: 1, height: 0.004))
        let pm = SK.mat(SK.rgb(0x2C3338), roughness: 0.05, metalness: 0.2)
        pm.transparency = 0.8
        pud.geometry?.materials = [pm]
        pud.scale = SCNVector3(1.0, 1, 0.55)
        pud.position = SCNVector3(-0.85, 0.016, 0.82)
        pud.isHidden = true
        inside.addChildNode(pud)
        puddle = pud

        // phones: one face down lighting the slab, one standing by the crack for signal
        let phoneMat = SK.mat(SK.rgb(0x111214), roughness: 0.3, metalness: 0.5)
        let up = SK.box(0.075, 0.009, 0.155, phoneMat, chamfer: 0.004)
        up.position = SCNVector3(0.9, 0.017, 0.58)
        up.eulerAngles.y = 0.6
        let led = SK.sphere(0.006, SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xFFF6E8)), segments: 8)
        led.position = SCNVector3(0.02, 0.006, -0.06)
        up.addChildNode(led)
        inside.addChildNode(up)
        phoneUp = up
        let sb = SCNNode()
        let body = SK.box(0.075, 0.155, 0.009, phoneMat, chamfer: 0.004)
        body.position.y = 0.078
        sb.addChildNode(body)
        let scr = SK.mat(.black, roughness: 0.2, emission: SK.rgb(0x9CC4FF))
        let screen = SK.box(0.066, 0.138, 0.002, scr, chamfer: 0)
        screen.position = SCNVector3(0, 0.078, 0.006)
        sb.addChildNode(screen)
        standbyScreen = scr
        for i in 0..<4 {
            let bar = SK.box(0.006, 0.006 + CGFloat(i) * 0.004, 0.002, SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xFFFFFF)), chamfer: 0)
            bar.position = SCNVector3(0.012 + CGFloat(i) * 0.009, 0.135 + CGFloat(i) * 0.002, 0.0075)
            sb.addChildNode(bar)
            signalBars.append(bar)
        }
        sb.position = SCNVector3(2.4, 0.22, 1.05)
        sb.eulerAngles = SCNVector3(-0.12, -1.25, 0)
        sb.isHidden = true
        inside.addChildNode(sb)
        phoneStandby = sb
        // a second phone in someone's hand, used as a torch at the work face
        let t = SK.box(0.075, 0.155, 0.009, phoneMat, chamfer: 0.004)
        t.position = SCNVector3(0.55, 0.28, -0.5)
        t.eulerAngles = SCNVector3(-0.9, 0.4, 0)
        t.isHidden = true
        inside.addChildNode(t)
        torch = t

        // the water tube the rescuers push in through the crack
        var tb = RBMesh()
        let tx: Float = 0.22, tz: Float = 0.35
        let ty = Float(hU(CGFloat(tx)))
        tb.rod([V3(tx, ty + 0.25, tz), V3(tx, ty - 0.05, tz), V3(tx + 0.05, ty - 0.35, tz + 0.04), V3(tx + 0.12, 0.08, tz + 0.1), V3(tx + 0.35, 0.03, tz + 0.2), V3(tx + 0.55, 0.03, tz + 0.12)],
               r: 0.009, sides: 6, col: V3(1, 1, 1))
        let tm = SK.mat(SK.rgb(0xDDEBF0), roughness: 0.15)
        tm.transparency = 0.75
        let tn = tb.node(tm)
        tn.isHidden = true
        inside.addChildNode(tn)
        tube = tn

        // cracks in the slab's underside, opening as the void is shaken apart
        for g in 0..<3 {
            var cm = RBMesh()
            var r2 = RBRand(UInt64(200 + g))
            for _ in 0..<3 {
                var x = r2.f(-1.2, 1.8)
                var z = r2.f(Float(zBack) + 0.2, Float(zCut) - 0.3)
                var pts: [V3] = []
                for _ in 0..<7 {
                    pts.append(V3(x, Float(hU(CGFloat(x))) - 0.004, z))
                    x += r2.f(-0.2, 0.25); z += r2.f(0.08, 0.2)
                    if z > Float(zCut) - 0.05 { break }
                }
                if pts.count > 1 { cm.rod(pts, r: 0.008, sides: 3, col: V3(0.02, 0.02, 0.02)) }
            }
            let cn = cm.node(SK.mat(.black, roughness: 1))
            cn.isHidden = true
            inside.addChildNode(cn)
            cracks.append(cn)
        }

        // fresh fall from a strong aftershock
        var fd = RBMesh()
        for _ in 0..<40 {
            let x = rng.f(-1.5, 1.8), z = rng.f(Float(zBack) + 0.2, Float(zCut) - 0.1)
            let sz = rng.f(0.04, 0.16)
            fd.box(V3(x, sz * 0.3, z), V3(sz * 1.4, sz * 0.6, sz), rbQ(rng.f(0, 6), rng.f(-0.5, 0.5), rng.f(-0.5, 0.5)), jitter: 0.3,
                   col: rbLin(0.62, 0.6, 0.57) * rng.f(0.85, 1.1), rng: &rng)
        }
        let fdn = fd.node(rubbleVC)
        fdn.isHidden = true
        inside.addChildNode(fdn)
        shockDebris = fdn
    }

    /// A four-drawer steel filing cabinet, drawers facing +z, origin at the floor centre.
    private func cabinet() -> SCNNode {
        let n = SCNNode()
        let body = SK.box(0.47, 1.18, 0.6, steel, chamfer: 0.008)
        body.position.y = 0.59
        n.addChildNode(body)
        for i in 0..<4 {
            let d = SK.box(0.43, 0.25, 0.012, steel, chamfer: 0.004)
            d.position = SCNVector3(0, 0.17 + CGFloat(i) * 0.285, 0.302)
            n.addChildNode(d)
            let h = SK.box(0.11, 0.022, 0.02, chrome, chamfer: 0.004)
            h.position = SCNVector3(0, 0.24 + CGFloat(i) * 0.285, 0.315)
            n.addChildNode(h)
        }
        return n
    }

    /// An 18.9 L (5-gallon) PET water barrel, standing on its base, with its water.
    private func barrel(fill: CGFloat) -> (node: SCNNode, water: SCNNode) {
        let n = SCNNode()
        let pet = SK.mat(SK.rgb(0x6FB2EE), roughness: 0.1, metalness: 0.0)
        pet.transparency = 0.5
        pet.transparencyMode = .dualLayer
        let body = SK.cylinder(0.135, 0.4, pet)
        body.position.y = 0.2
        n.addChildNode(body)
        let shoulder = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.135, height: 0.08))
        shoulder.geometry?.materials = [pet]
        shoulder.position.y = 0.44
        n.addChildNode(shoulder)
        let cap = SK.cylinder(0.032, 0.05, SK.mat(SK.rgb(0x1F5FB8), roughness: 0.5))
        cap.position.y = 0.5
        n.addChildNode(cap)
        let wm = SK.mat(SK.rgb(0x3A86D0), roughness: 0.05)
        wm.transparency = 0.55
        let w = SK.cylinder(0.126, 0.38 * fill, wm)
        w.position.y = 0.01 + 0.19 * fill
        n.addChildNode(w)
        return (n, w)
    }

    /// Black mesh office chair.
    private func chair() -> SCNNode {
        let n = SCNNode()
        let seat = SK.box(0.48, 0.07, 0.46, blackPlastic, chamfer: 0.02)
        seat.position.y = 0.46
        n.addChildNode(seat)
        let back = SK.box(0.46, 0.5, 0.05, blackPlastic, chamfer: 0.02)
        back.position = SCNVector3(0, 0.76, -0.22)
        back.eulerAngles.x = -0.12
        n.addChildNode(back)
        let post = SK.cylinder(0.025, 0.36, chrome)
        post.position.y = 0.25
        n.addChildNode(post)
        for i in 0..<5 {
            let a = CGFloat(i) / 5 * 2 * .pi
            let arm = SK.box(0.33, 0.03, 0.04, blackPlastic, chamfer: 0.008)
            arm.position = SCNVector3(cos(a) * 0.16, 0.06, sin(a) * 0.16)
            arm.eulerAngles.y = -a
            n.addChildNode(arm)
        }
        return n
    }

    // MARK: Rescue

    private func rescuer(_ pose: SK.Pose) -> SCNNode {
        let p = SK.person(color: SK.rgb(0xE2621B), pose: pose, seed: 0)
        p.eulerAngles.y = 0
        // the dark cap becomes a white helmet with a lamp
        if let body = p.childNodes.first, body.childNodes.count > 2 {
            let hat = body.childNodes[2]
            hat.geometry?.materials = [SK.mat(SK.rgb(0xF1EEE6), roughness: 0.4)]
            hat.scale = SCNVector3(1.3, 0.8, 1.3)
            let lamp = SK.sphere(0.03, SK.mat(.black, roughness: 0.2, emission: SK.rgb(0xFFF4DC)), segments: 8)
            lamp.position = SCNVector3(0, 0.02, 0.15)
            hat.addChildNode(lamp)
            // reflective bands
            let band = SK.mat(SK.rgb(0xDADAD2), roughness: 0.3, metalness: 0.3)
            if body.childNodes.count > 0 {
                let torso = body.childNodes[0]
                let r = SCNNode(geometry: SCNTorus(ringRadius: 0.19, pipeRadius: 0.02))
                r.geometry?.materials = [band]
                r.position.y = -0.08
                torso.addChildNode(r)
            }
        }
        return p
    }

    private func buildRescue() {
        let sx = (shaftX0 + shaftX1) / 2
        // crew on the pile
        // one flat on the rubble at the lip of the shaft, one kneeling across from him, one further back
        let spotsTop: [(CGFloat, CGFloat, CGFloat, SK.Pose)] = [(-0.25, 0.98, .pi, .lying), (2.05, 0.75, -1.75, .huddled), (-2.6, -1.6, 0.99, .standing)]
        for (x, z, f, pose) in spotsTop {
            let r = rescuer(pose)
            r.position = SCNVector3(x, surfY(x, z) - 0.03, z)
            r.eulerAngles.y = f
            r.isHidden = true
            outside.addChildNode(r)
            crewTop.append(r)
        }
        let l = rescuer(.huddled)
        l.position = SCNVector3(-1.75, surfY(-1.75, 0.85) - 0.05, 0.85)
        l.eulerAngles.y = 1.4
        l.isHidden = true
        outside.addChildNode(l)
        listener = l

        // the one working down the shaft, and the one at the breach
        let sc = rescuer(.huddled)
        sc.isHidden = true
        outside.addChildNode(sc)
        shaftCrew = sc
        let bc = rescuer(.standing)
        bc.position = SCNVector3(sx, l4Top(sx) + 0.0, 0.52)
        bc.isHidden = true
        outside.addChildNode(bc)
        breachCrew = bc

        // tripod and rope over the shaft
        let tri = SCNNode()
        let apex = SCNVector3(sx, surfY(sx, 0.8) + 2.0, 0.75)
        var tm = RBMesh()
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi + 0.3
            let fx = Float(sx) + sin(a) * 1.05, fz = 0.75 + cos(a) * 0.95
            let fy = Float(surfY(CGFloat(fx), CGFloat(min(fz, Float(zCut) - 0.1))))
            tm.rod([V3(Float(apex.x), Float(apex.y), Float(apex.z)), V3(fx, fy, min(fz, Float(zCut) - 0.1))], r: 0.03, sides: 6, col: V3(1, 1, 1))
        }
        tri.addChildNode(tm.node(rbMat(SK.rgb(0xD9A520), rough: 0.5, metal: 0.4, grain: 0.1, scale: 6, bump: 0, dust: 0.2)))
        let pulley = SK.cylinder(0.08, 0.04, chrome)
        pulley.eulerAngles.x = .pi / 2
        pulley.position = SCNVector3(apex.x, apex.y - 0.12, apex.z)
        tri.addChildNode(pulley)
        tri.isHidden = true
        outside.addChildNode(tri)
        tripod = tri
        let rp = SK.cylinder(0.012, 1, rbMat(SK.rgb(0xE4D24A), rough: 0.8, grain: 0.2, scale: 20, bump: 0, dust: 0.1))
        rp.pivot = SCNMatrix4MakeTranslation(0, 0.5, 0)        // hangs down from its top
        rp.position = SCNVector3(apex.x, apex.y - 0.15, apex.z)
        rp.isHidden = true
        outside.addChildNode(rp)
        rope = rp

        // marker flags and the painted search mark
        let flagMat = rbMat(SK.rgb(0xF2551C), rough: 0.7, grain: 0.1, scale: 6, bump: 0, dust: 0.05, doubleSided: true)
        for (x, z) in [(-0.6, 0.95), (1.85, 0.8)] as [(CGFloat, CGFloat)] {
            let f = SCNNode()
            let pole = SK.cylinder(0.012, 0.9, chrome)
            pole.position.y = 0.45
            f.addChildNode(pole)
            let cloth = SK.box(0.28, 0.18, 0.004, flagMat, chamfer: 0)
            cloth.position = SCNVector3(0.14, 0.8, 0)
            f.addChildNode(cloth)
            f.position = SCNVector3(x, surfY(x, z) - 0.05, z)
            f.eulerAngles.y = 0.3
            f.isHidden = true
            outside.addChildNode(f)
            flags.append(f)
        }
        let mk = SCNNode()
        let paint = SK.mat(SK.rgb(0xFF6A1E), roughness: 0.8)
        for a in [0.75, -0.75] as [CGFloat] {
            let s = SK.box(0.7, 0.012, 0.07, paint, chamfer: 0)
            s.eulerAngles.y = a
            mk.addChildNode(s)
        }
        mk.position = SCNVector3(-1.05, surfY(-1.05, 0.95) + 0.06, 0.95)
        mk.eulerAngles.x = 0.08
        mk.isHidden = true
        outside.addChildNode(mk)
        marker = mk

        // the floodlight mast and its generator
        let tower = SCNNode()
        let bx: CGFloat = -3.6, bz: CGFloat = -1.7
        let by = surfY(bx, bz)
        let mast = SK.cylinder(0.05, 3.3, rbMat(SK.rgb(0xC9C9C2), rough: 0.5, metal: 0.6, grain: 0.1, scale: 6, bump: 0, dust: 0.2))
        mast.position = SCNVector3(bx, by + 1.65, bz)
        tower.addChildNode(mast)
        let gen = SK.box(1.1, 0.65, 0.65, rbMat(SK.rgb(0xE2B21E), rough: 0.6, grain: 0.1, scale: 6, bump: 0, dust: 0.3), chamfer: 0.04)
        gen.position = SCNVector3(bx - 0.9, surfY(bx - 0.9, bz - 0.8) + 0.3, bz - 0.8)
        gen.eulerAngles.y = 0.3
        tower.addChildNode(gen)
        generator = gen
        let target = SCNVector3(sx, surfY(sx, 0.7) - 0.2, 0.7)
        for k in 0..<2 {
            let head = SCNNode()
            let hm = SK.mat(SK.rgb(0x222222), roughness: 0.4, emission: .black)
            let housing = SK.box(0.34, 0.24, 0.12, SK.mat(SK.rgb(0x3A3B3E), roughness: 0.5, metalness: 0.5), chamfer: 0.01)
            head.addChildNode(housing)
            let face = SK.box(0.3, 0.2, 0.01, hm, chamfer: 0)
            face.position.z = -0.065
            head.addChildNode(face)
            floodHeads.append(hm)
            head.position = SCNVector3(bx + (k == 0 ? -0.2 : 0.2), by + 3.3, bz)
            head.look(at: target)
            tower.addChildNode(head)
            let spot = SCNLight()
            spot.type = .spot
            spot.color = SK.rgb(0xF4F1E8)
            spot.intensity = 0
            spot.spotInnerAngle = 8
            spot.spotOuterAngle = 20
            spot.attenuationStartDistance = 0
            spot.attenuationEndDistance = 16
            spot.attenuationFalloffExponent = 2
            let ln = SCNNode()
            ln.light = spot
            ln.position = head.position
            ln.look(at: target)
            tower.addChildNode(ln)
            floodLamps.append(ln)
            let beam = rbBeam(from: head.position, to: SCNVector3(target.x + (k == 0 ? -0.6 : 0.5), target.y, target.z), r0: 0.12, r1: 1.0,
                              color: SK.rgb(0xBFC4C8))
            beam.isHidden = true
            tower.addChildNode(beam)
            floodBeams.append(beam)
        }
        let bcn = SCNNode()
        let bl = SCNLight()
        bl.type = .omni
        bl.color = SK.rgb(0xFF8A1A)
        bl.intensity = 0
        bl.attenuationEndDistance = 5
        bcn.light = bl
        bcn.position = SCNVector3(gen.position.x, gen.position.y + 0.5, gen.position.z)
        let bulb = SK.sphere(0.06, SK.mat(.black, roughness: 0.3, emission: SK.rgb(0xFF7A10)), segments: 10)
        bcn.addChildNode(bulb)
        bcn.runAction(.repeatForever(.sequence([.customAction(duration: 0.5) { n, t in
            let on = Int(t * 6) % 2 == 0
            n.light?.intensity = on ? 120 : 0
            n.childNodes.first?.geometry?.firstMaterial?.emission.intensity = on ? 1.5 : 0.1
        }])))
        tower.addChildNode(bcn)
        beacon = bcn
        tower.isHidden = true
        outside.addChildNode(tower)
        floodTower = tower

        // a rescue stretcher waiting by the shaft at the end
        let st = SK.box(0.55, 0.06, 1.9, orange, chamfer: 0.03)
        st.position = SCNVector3(2.05, surfY(2.05, -0.4) + 0.06, -0.4)
        st.eulerAngles = SCNVector3(0.05, 0.35, 0.08)
        st.isHidden = true
        outside.addChildNode(st)
        stretcher = st

        // the silver blanket round whoever goes up first
        let foil = SK.mat(SK.rgb(0xE6E9EC), roughness: 0.3, metalness: 0.35)
        for _ in 0..<1 {
            let b = SCNNode(geometry: SCNCone(topRadius: 0.13, bottomRadius: 0.4, height: 0.82))
            b.geometry?.materials = [foil]
            b.isHidden = true
            outside.addChildNode(b)
            blankets.append(b)
        }
    }

    // MARK: Lights

    private func buildLights() {

        let fill = SCNLight()
        fill.type = .directional
        fill.color = SK.rgb(0xC7CFD8)
        fill.castsShadow = true
        fill.shadowMode = .deferred
        fill.shadowMapSize = CGSize(width: 4096, height: 4096)
        fill.shadowSampleCount = 8
        fill.shadowRadius = 2.5
        fill.shadowColor = NSColor(white: 0, alpha: 0.6)
        fill.automaticallyAdjustsShadowProjection = true
        fill.maximumShadowDistance = 30
        fillNode.light = fill
        fillNode.position = SCNVector3(6, 6.5, 9)
        fillNode.look(at: SCNVector3(0.5, 1, 0))
        world.addChildNode(fillNode)



        // daylight from the open top: the sun light of the framework, from above and behind
        sunNode.position = SCNVector3(-30, 80, -38)
        sunNode.look(at: SCNVector3Zero)
        sunNode.light?.maximumShadowDistance = 40
        sunNode.light?.shadowMapSize = CGSize(width: 2048, height: 2048)

        let cs = SCNLight()
        cs.type = .omni
        cs.color = SK.rgb(0xD2DCE6)
        cs.attenuationStartDistance = 0
        cs.attenuationEndDistance = 8
        cs.attenuationFalloffExponent = 1.6
        coreSky.light = cs
        coreSky.position = SCNVector3(4.1, 5.6, -0.8)
        world.addChildNode(coreSky)

        // grey daylight through the crack in the east wall
        let cr = SCNLight()
        cr.type = .spot
        cr.color = SK.rgb(0xDCE3EA)
        cr.spotInnerAngle = 4
        cr.spotOuterAngle = 20
        cr.attenuationStartDistance = 0
        cr.attenuationEndDistance = 5
        cr.attenuationFalloffExponent = 1.4
        cr.castsShadow = true
        cr.shadowMode = .forward
        cr.shadowMapSize = CGSize(width: 1024, height: 1024)
        cr.shadowRadius = 2
        cr.shadowColor = NSColor(white: 0, alpha: 0.75)
        crackSpot.light = cr
        let crackFrom = SCNVector3(2.56, 0.93, 1.02), crackTo = SCNVector3(0.85, 0.0, 0.98)
        crackSpot.position = crackFrom
        crackSpot.look(at: crackTo)
        world.addChildNode(crackSpot)
        let beam = rbBeam(from: SCNVector3(2.6, 0.93, 1.02), to: SCNVector3(0.95, 0.04, 1.0), r0: 0.06, r1: 0.42, color: SK.rgb(0xDCE4EC))
        inside.addChildNode(beam)
        crackBeam = beam
        let sbm = rbBeam(from: SCNVector3(2.75, 0.5, 0.98), to: SCNVector3(0.6, 0.0, 0.75), r0: 0.3, r1: 0.7, color: SK.rgb(0xB4BCC4))
        sbm.isHidden = true
        inside.addChildNode(sbm)
        stairBeam = sbm

        // a little light and air through the dog's hole
        let vl = SCNLight()
        vl.type = .spot
        vl.color = SK.rgb(0xCBD6E2)
        vl.spotInnerAngle = 10
        vl.spotOuterAngle = 40
        vl.attenuationEndDistance = 3
        ventSpot.light = vl
        ventSpot.position = SCNVector3(-1.3, 0.14, -1.85)
        ventSpot.look(at: SCNVector3(-1.0, 0.0, -0.4))
        world.addChildNode(ventSpot)
        let vb = rbBeam(from: SCNVector3(-1.3, 0.14, -1.7), to: SCNVector3(-1.05, 0.0, -0.6), r0: 0.07, r1: 0.25, color: SK.rgb(0x7E8790))
        vb.isHidden = true
        inside.addChildNode(vb)
        ventBeam = vb

        // the phone face down on the carpet: its LED on the slab, and the light bouncing back
        let ps = SCNLight()
        ps.type = .spot
        ps.color = SK.rgb(0xF4F0EA)
        ps.spotInnerAngle = 25
        ps.spotOuterAngle = 95
        ps.attenuationStartDistance = 0
        ps.attenuationEndDistance = 3.2
        ps.attenuationFalloffExponent = 2
        ps.castsShadow = true
        ps.shadowMode = .forward
        ps.shadowMapSize = CGSize(width: 1024, height: 1024)
        ps.shadowRadius = 3
        ps.shadowColor = NSColor(white: 0, alpha: 0.6)
        phoneSpot.light = ps
        phoneSpot.position = SCNVector3(0.92, 0.04, 0.56)
        phoneSpot.eulerAngles.x = .pi / 2
        world.addChildNode(phoneSpot)
        // the patch of slab it lights becomes the lamp of the void: a wide spot shining down
        // from the ceiling (an omni here would light the cut through the slabs)
        let pb = SCNLight()
        pb.type = .spot
        pb.color = SK.rgb(0xE9E2D6)
        pb.spotInnerAngle = 40
        pb.spotOuterAngle = 140
        pb.attenuationStartDistance = 0
        pb.attenuationEndDistance = 4.6
        pb.attenuationFalloffExponent = 1.4
        pb.castsShadow = true
        pb.shadowMode = .forward
        pb.shadowMapSize = CGSize(width: 1024, height: 1024)
        pb.shadowRadius = 4
        pb.shadowSampleCount = 4
        pb.shadowColor = NSColor(white: 0, alpha: 0.55)
        phoneBounce.light = pb
        phoneBounce.position = SCNVector3(0.9, hU(0.9) - 0.03, 0.56)
        phoneBounce.eulerAngles.x = -.pi / 2
        world.addChildNode(phoneBounce)

        let pg = SCNLight()
        pg.type = .omni
        pg.color = SK.rgb(0xF0DEC4)
        pg.intensity = 2.2
        pg.attenuationEndDistance = 1.6
        pg.attenuationFalloffExponent = 1.5
        pocketGlow.light = pg
        pocketGlow.position = SCNVector3(-0.05, l4Top(-0.05) + 0.55, 0.45)
        world.addChildNode(pocketGlow)

        let sg = SCNLight()
        sg.type = .omni
        sg.color = SK.rgb(0xA9C8FF)
        sg.attenuationEndDistance = 1.6
        sg.attenuationFalloffExponent = 2
        standbyGlow.light = sg
        standbyGlow.position = SCNVector3(2.3, 0.35, 1.0)
        world.addChildNode(standbyGlow)

        let ws = SCNLight()
        ws.type = .spot
        ws.color = SK.rgb(0xF6F2EC)
        ws.spotInnerAngle = 12
        ws.spotOuterAngle = 48
        ws.attenuationEndDistance = 3.5
        ws.attenuationFalloffExponent = 2
        workSpot.light = ws
        workSpot.position = SCNVector3(0.55, 0.3, -0.48)
        workSpot.look(at: SCNVector3(1.1, 0.1, -1.1))
        world.addChildNode(workSpot)

        // the rescuers' work lamp in the shaft
        let sl = SCNLight()
        sl.type = .spot
        sl.color = SK.rgb(0xFFF1D6)
        sl.spotInnerAngle = 30
        sl.spotOuterAngle = 95
        sl.attenuationEndDistance = 4.5
        sl.attenuationFalloffExponent = 1.8
        shaftLamp.light = sl
        shaftLamp.eulerAngles.x = -.pi / 2
        let lampBody = SK.box(0.14, 0.08, 0.1, SK.mat(SK.rgb(0x222222), roughness: 0.4, emission: SK.rgb(0xFFE6B8)), chamfer: 0.01)
        shaftLamp.addChildNode(lampBody)
        shaftLampBody = lampBody
        outside.addChildNode(shaftLamp)

        // the searchlight through the breach
        let bs = SCNLight()
        bs.type = .spot
        bs.color = SK.rgb(0xF6F8FF)
        bs.spotInnerAngle = 18
        bs.spotOuterAngle = 55
        bs.attenuationStartDistance = 0
        bs.attenuationEndDistance = 7
        bs.attenuationFalloffExponent = 1.4
        bs.castsShadow = true
        bs.shadowMode = .forward
        bs.shadowMapSize = CGSize(width: 1024, height: 1024)
        bs.shadowRadius = 2
        breachSpot.light = bs
        let hx = (holeX0 + holeX1) / 2
        breachSpot.position = SCNVector3(hx, l4Top(hx) + 0.9, 0.68)
        breachSpot.look(at: SCNVector3(hx - 0.15, 0, 0.75), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        world.addChildNode(breachSpot)
        let bb = rbBeam(from: SCNVector3(hx, l4Top(hx) + 0.3, 0.68), to: SCNVector3(hx - 0.15, 0.0, 0.78), r0: 0.24, r1: 0.6, color: SK.rgb(0xC6CBD4))
        bb.isHidden = true
        inside.addChildNode(bb)
        breachBeam = bb
    }

    // MARK: Particles

    private func buildParticles() {
        // cement dust hanging in the void. Particles are unlit, so the dust that a light
        // catches is an emitter of its own around that light; a dim haze fills the rest.
        hazeAll = dustCloud(at: SCNVector3(-0.1, 0.3, -0.15), shape: SCNBox(width: 3.6, height: 0.42, length: 2.6, chamferRadius: 0), size: 0.6)
        hazePhone = dustCloud(at: SCNVector3(0.85, 0.45, 0.5), shape: SCNSphere(radius: 0.85), size: 0.45)
        motesPhone = dustCloud(at: SCNVector3(0.85, 0.45, 0.5), shape: SCNSphere(radius: 0.9), size: 0.012, motes: true)
        let a = SCNVector3(2.5, 0.86, 1.01), b = SCNVector3(0.95, 0.06, 1.0)
        let mid = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        let len = sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z))
        hazeBeam = dustCloud(at: mid, look: b, shape: SCNBox(width: 0.26, height: 0.26, length: len, chamferRadius: 0), size: 0.3)
        motesBeam = dustCloud(at: mid, look: b, shape: SCNBox(width: 0.3, height: 0.3, length: len, chamferRadius: 0), size: 0.012, motes: true)
        let hx = (holeX0 + holeX1) / 2
        hazeBreach = dustCloud(at: SCNVector3(hx - 0.08, 0.55, 0.72), shape: SCNCylinder(radius: 0.35, height: 1.0), size: 0.4)
        motesBreach = dustCloud(at: SCNVector3(hx - 0.08, 0.55, 0.72), shape: SCNCylinder(radius: 0.4, height: 1.1), size: 0.014, motes: true)

        // dust pouring from the cracks (a trickle, a torrent in an aftershock)
        for p in [SCNVector3(0.25, hU(0.25) - 0.02, 0.3), SCNVector3(2.45, 1.2, -0.3), SCNVector3(-1.1, hU(-1.1) - 0.02, -0.9), SCNVector3(1.5, hU(1.5) - 0.02, 0.85)] {
            let n = SCNNode()
            n.position = p
            inside.addChildNode(n)
            let f = SCNParticleSystem()
            f.particleImage = SK.dotImage(size: 16, hardness: 0.6)
            f.emitterShape = SCNBox(width: 0.4, height: 0.01, length: 0.12, chamferRadius: 0)
            f.birthLocation = .volume
            f.birthRate = 6
            f.particleLifeSpan = 1.2
            f.particleVelocity = 0.2
            f.particleVelocityVariation = 0.1
            f.emittingDirection = SCNVector3(0, -1, 0)
            f.spreadingAngle = 8
            f.acceleration = SCNVector3(0, -1.6, 0)
            f.particleSize = 0.018
            f.particleSizeVariation = 0.01
            f.particleColor = SK.rgb(0xD8D0C2).withAlphaComponent(0.9)
            f.isLightingEnabled = false
            f.blendMode = .alpha
            f.warmupDuration = 2
            pendingParticles.append((n, f))
            dustFalls.append(f)
        }
        // gravel shaken loose in an aftershock
        let gn = SCNNode()
        gn.position = SCNVector3(0.0, 0.9, -0.2)
        inside.addChildNode(gn)
        let g = SCNParticleSystem()
        g.particleImage = SK.dotImage(size: 16, hardness: 0.9)
        g.emitterShape = SCNBox(width: 3.0, height: 0.1, length: 2.2, chamferRadius: 0)
        g.birthLocation = .volume
        g.birthRate = 0
        g.particleLifeSpan = 0.45
        g.particleVelocity = 0.4
        g.emittingDirection = SCNVector3(0, -1, 0)
        g.acceleration = SCNVector3(0, -9.8, 0)
        g.particleSize = 0.025
        g.particleSizeVariation = 0.012
        g.particleColor = SK.rgb(0x4A4743)
        g.isLightingEnabled = false
        g.blendMode = .alpha
        g.warmupDuration = 1
        pendingParticles.append((gn, g))
        gravel = g

        // rain seeping through the crack
        let dn = SCNNode()
        dn.position = SCNVector3(-0.62, hU(-0.62) - 0.02, 1.02)
        inside.addChildNode(dn)
        let d = SCNParticleSystem()
        d.particleImage = SK.dotImage(size: 16, hardness: 0.8)
        d.emitterShape = SCNBox(width: 0.1, height: 0.01, length: 0.1, chamferRadius: 0)
        d.birthLocation = .volume
        d.birthRate = 0
        d.particleLifeSpan = 0.45
        d.particleVelocity = 0.5
        d.emittingDirection = SCNVector3(0, -1, 0)
        d.acceleration = SCNVector3(0, -9.8, 0)
        d.particleSize = 0.012
        d.stretchFactor = 0.04
        d.particleColor = SK.rgb(0xCFE2F0).withAlphaComponent(0.8)
        d.isLightingEnabled = false
        d.blendMode = .additive
        d.warmupDuration = 1
        pendingParticles.append((dn, d))
        drips = d

        // rain on the pile (dies on its surface)
        let rn = SCNNode()
        rn.position = SCNVector3(-0.8, 9.5, -3.6)
        outside.addChildNode(rn)
        let r = SCNParticleSystem()
        r.particleImage = SK.dotImage(size: 16, hardness: 0.8)
        r.emitterShape = SCNBox(width: 20, height: 0.5, length: 9.6, chamferRadius: 0)
        r.birthLocation = .volume
        r.birthRate = 0
        r.particleLifeSpan = 0.62
        r.particleVelocity = 11
        r.emittingDirection = SCNVector3(0.05, -1, 0)
        r.particleSize = 0.02
        r.stretchFactor = 0.06
        r.particleColor = NSColor(white: 0.85, alpha: 0.4)
        r.isLightingEnabled = false
        r.blendMode = .alpha
        r.warmupDuration = 1
        pendingParticles.append((rn, r))
        rain = r

        // an aftershock: dust billowing out of the void, and off the top of the pile
        let pn = SCNNode()
        pn.position = SCNVector3(0.3, 0.35, 0.9)
        inside.addChildNode(pn)
        let pf = SCNParticleSystem()
        pf.particleImage = SK.dotImage(size: 64, hardness: 0.02)
        pf.emitterShape = SCNBox(width: 3.4, height: 0.5, length: 0.8, chamferRadius: 0)
        pf.birthLocation = .volume
        pf.birthRate = 0
        pf.particleLifeSpan = 4
        pf.particleLifeSpanVariation = 1.5
        pf.particleVelocity = 0.25
        pf.particleVelocityVariation = 0.15
        pf.emittingDirection = SCNVector3(0, 0.3, 1)
        pf.spreadingAngle = 50
        pf.particleSize = 0.7
        pf.particleSizeVariation = 0.3
        pf.particleColor = NSColor(white: 0.6, alpha: 0.1)
        pf.isLightingEnabled = false
        pf.blendMode = .alpha
        pf.sortingMode = .distance
        pf.warmupDuration = 4
        let grow = SCNParticlePropertyController(animation: {
            let a = CABasicAnimation()
            a.fromValue = 0.5
            a.toValue = 1.8
            return a
        }())
        pf.propertyControllers = [.size: grow]
        pendingParticles.append((pn, pf))
        shockPuff = pf
        let on = SCNNode()
        on.position = SCNVector3(-0.5, surfY(-0.5, -0.5) + 0.2, -0.8)
        outside.addChildNode(on)
        let pl = SCNParticleSystem()
        pl.particleImage = SK.dotImage(size: 64, hardness: 0.02)
        pl.emitterShape = SCNBox(width: 9, height: 0.4, length: 3.5, chamferRadius: 0)
        pl.birthLocation = .volume
        pl.birthRate = 0
        pl.particleLifeSpan = 5
        pl.particleVelocity = 0.5
        pl.emittingDirection = SCNVector3(0.1, 1, 0)
        pl.spreadingAngle = 30
        pl.particleSize = 1.2
        pl.particleSizeVariation = 0.5
        pl.particleColor = SK.rgb(0xBDB6AA).withAlphaComponent(0.12)
        pl.isLightingEnabled = false
        pl.blendMode = .alpha
        pl.sortingMode = .distance
        pl.warmupDuration = 5
        pl.propertyControllers = [.size: grow]
        pendingParticles.append((on, pl))
        plumes = pl

        // dust thrown up at the bottom of the shaft while they cut
        let sn = SCNNode()
        outside.addChildNode(sn)
        let sd = SCNParticleSystem()
        sd.particleImage = SK.dotImage(size: 64, hardness: 0.05)
        sd.emitterShape = SCNBox(width: 0.6, height: 0.2, length: 0.6, chamferRadius: 0)
        sd.birthLocation = .volume
        sd.birthRate = 0
        sd.particleLifeSpan = 3
        sd.particleVelocity = 0.25
        sd.emittingDirection = SCNVector3(0, 1, 0)
        sd.spreadingAngle = 40
        sd.particleSize = 0.35
        sd.particleSizeVariation = 0.15
        sd.particleColor = SK.rgb(0xCFC8BC).withAlphaComponent(0.12)
        sd.isLightingEnabled = false
        sd.blendMode = .alpha
        sd.warmupDuration = 3
        pendingParticles.append((sn, sd))
        shaftDust = sd
        sn.name = "shaftDust"
    }

    /// An unlit dust emitter (soft haze sprites, or fine additive motes).
    private func dustCloud(at p: SCNVector3, look: SCNVector3? = nil, shape: SCNGeometry, size: CGFloat, motes: Bool = false) -> SCNParticleSystem {
        let n = SCNNode()
        n.position = p
        if let t = look { n.look(at: t) }
        inside.addChildNode(n)
        let s = SCNParticleSystem()
        s.particleImage = motes ? SK.dotImage(size: 16, hardness: 0.55) : SK.dotImage(size: 64, hardness: 0.02)
        s.emitterShape = shape
        s.birthLocation = .volume
        s.birthRate = 0
        s.particleLifeSpan = motes ? 5 : 7
        s.particleLifeSpanVariation = 2
        s.particleVelocity = motes ? 0.03 : 0.012
        s.particleVelocityVariation = motes ? 0.03 : 0.01
        s.birthDirection = .random
        s.particleSize = size
        s.particleSizeVariation = size * 0.4
        s.isLightingEnabled = false
        s.blendMode = motes ? .additive : .alpha
        if !motes { s.sortingMode = .distance }
        s.warmupDuration = 7
        s.particleColor = NSColor(white: 0.6, alpha: 0.05)
        pendingParticles.append((n, s))
        return s
    }

    // MARK: - Apply state

    override func apply(_ s: SceneState, old: SceneState?) {
        let dayK = CGFloat(min(SK.smoothstep(5.4, 7.0, Float(s.hour)), 1 - SK.smoothstep(18.4, 19.9, Float(s.hour))))
        let sunK = CGFloat(s.sun)
        let dusk = CGFloat(max(0, 1 - abs(s.hour - 18.6) / 1.4)) * dayK
        let dust = CGFloat(min(100, max(0, s.v("dust", 70)))) / 100
        let tunnel = CGFloat(min(100, max(0, s.v("tunnel")))) / 100
        let heard = s.v("heard")
        let battery = s.res("battery")
        let rescued = s.has("rescued")
        let crawled = s.has("self_rescue")
        let breach = s.has("breakthrough") || tunnel >= 0.999 || rescued
        let found = s.has("found") || breach
        let teams = s.has("teams_here") || found
        let shock = s.has("aftershock")
        let strong = s.has("strong_shock")
        let stairP = CGFloat(s.project("stairwell"))
        let stairOpen = s.has("stair_open") || s.done.contains("stairwell") || crawled
        let bucketP = CGFloat(s.project("bucket"))
        let bucketOut = s.done.contains("bucket") || s.has("bucket_free")
        let night = dayK < 0.3

        // ---- the outside world: sky, daylight, fill on the cut
        let key = "\(Int(dayK * 8))|\(Int(sunK * 4))|\(Int(s.precip))|\(Int(dusk * 4))"
        if key != skyKey {
            skyKey = key
            let dayTop = SK.rgb(0x8E99A5).blended(withFraction: 1 - sunK, of: SK.rgb(0x6F757C)) ?? .gray
            let dayHor = SK.rgb(0xC9CDD0).blended(withFraction: 1 - sunK, of: SK.rgb(0x9CA0A4)) ?? .gray
            let warmHor = dayHor.blended(withFraction: dusk * 0.6, of: SK.rgb(0xD9A27A)) ?? dayHor
            let t = SK.rgb(0x06080C).blended(withFraction: dayK, of: dayTop) ?? dayTop
            let hz = SK.rgb(0x0C1016).blended(withFraction: dayK, of: warmHor) ?? warmHor
            skyImage = SK.gradientSky(top: t, horizon: hz)
            skyFog = hz
        }
        // (the base class resets both to the indoor colour on every update)
        scene.background.contents = skyImage
        scene.fogColor = skyFog
        scene.fogStartDistance = 16
        scene.fogEndDistance = 90 - 30 * dust - CGFloat(s.precip) * 12
        scene.fogDensityExponent = 1.2

        sunNode.light?.intensity = dayK * (140 + 420 * sunK)
        sunNode.light?.color = SK.rgb(0xFFF4E6).blended(withFraction: dusk * 0.7, of: SK.rgb(0xFFB070)) ?? .white
        sunNode.light?.shadowColor = NSColor(white: 0, alpha: 0.35 + 0.35 * sunK)
        // the cut is lit from the open side: daylight, or a little moonlight and the glow of the city
        fillNode.light?.intensity = 95 + dayK * (290 + 260 * sunK)
        fillNode.light?.color = (night ? SK.rgb(0x7A88A4) : SK.rgb(0xD5DADF)).blended(withFraction: dusk * 0.5, of: SK.rgb(0xE0A878)) ?? .white
        ambientNode.light?.intensity = 9 + dayK * (45 + 30 * sunK)
        ambientNode.light?.color = night ? SK.rgb(0x46546C) : SK.rgb(0xC9D0D8)
        coreSky.light?.intensity = dayK * (35 + 70 * sunK)

        // ---- light through the east wall: a crack, then the hole into the stairwell
        let dayIn = dayK * (0.3 + 0.7 * sunK)
        crackSpot.isHidden = dayIn < 0.03
        crackSpot.light?.intensity = dayIn * (stairOpen ? 520 : 300)
        crackSpot.light?.spotOuterAngle = stairOpen ? 52 : 20
        crackBeam?.isHidden = dayIn < 0.03 || stairOpen
        crackBeam?.opacity = min(1, dayIn * (1.0 + 0.5 * dust))
        stairBeam?.isHidden = !(stairOpen && dayIn > 0.03)
        stairBeam?.opacity = min(1, dayIn * (0.45 + 0.5 * dust))

        // ---- the hole through the east wall
        let dug = stairOpen ? 4 : Int((stairP * 4).rounded(.down))
        for (i, n) in notchSlices.enumerated() { n.isHidden = i < dug }
        crackLines?.isHidden = dug >= 2
        for (i, n) in digRubble.enumerated() { n.isHidden = !(stairP > 0.05 + CGFloat(i) * 0.3 || stairOpen) }

        // ---- the dog's hole
        let vent = s.has("hole_vent")
        ventSpot.isHidden = !(vent && dayIn > 0.03)
        ventSpot.light?.intensity = dayIn * 160
        ventBeam?.isHidden = !(vent && dayIn > 0.03)
        ventBeam?.opacity = dayIn * 0.7

        // ---- the phones
        let power = battery >= 2
        let decided = s.happened("phone_plan")
        let workLight = power && (s.has("light_work") || (found && battery > 40))
        let standby = power && s.has("standby")
        let campLight = power && (!decided || workLight || (night && battery > 60 && !standby))
        phoneSpot.isHidden = !campLight
        phoneBounce.isHidden = !campLight
        let torchK: CGFloat = found && s.has("light_work") ? 1.6 : 1
        phoneSpot.light?.intensity = 170 * torchK
        phoneBounce.light?.intensity = 120 * torchK
        if let led = phoneUp?.childNodes.first?.geometry?.firstMaterial {
            led.emission.intensity = campLight ? 3 : 0
        }
        phoneStandby?.isHidden = !standby
        standbyGlow.isHidden = !standby
        standbyGlow.light?.intensity = 9
        let net = s.v("network")
        let bars = net >= 75 ? 4 : net >= 50 ? 3 : net >= 25 ? 2 : net >= 8 ? 1 : 0
        for (i, b) in signalBars.enumerated() {
            b.geometry?.firstMaterial?.emission.intensity = i < bars ? 1.2 : 0.08
        }
        standbyScreen?.emission.intensity = standby ? (s.has("sms_out") ? 1.2 : 0.8) : 0
        let working = workLight && !bucketOut && bucketP > 0 || workLight && stairP > 0 && !stairOpen
        workSpot.isHidden = !working
        workSpot.light?.intensity = 160 * torchK
        torch?.isHidden = !working
        if stairP > 0 && !stairOpen && !(bucketP > 0 && !bucketOut) {
            workSpot.position = SCNVector3(1.4, 0.35, 0.95)
            workSpot.look(at: SCNVector3(2.55, 0.35, 1.0))
        } else {
            workSpot.position = SCNVector3(0.55, 0.3, -0.48)
            workSpot.look(at: SCNVector3(1.1, 0.1, -1.1))
        }

        // ---- the water barrel
        let gone = bucketOut ? 4 : Int((bucketP * 4.6).rounded(.down))
        for (i, b) in bricks.enumerated() { b.isHidden = i < min(4, gone) }
        bucketBuried?.isHidden = bucketOut
        bucketFree?.isHidden = !bucketOut
        cabinetDown?.isHidden = bucketOut
        cabinetPried?.isHidden = !bucketOut
        if let w = bucketWater {
            let fill = CGFloat(min(1, max(0.02, s.res("water") / 18.9)))
            w.scale = SCNVector3(1, fill, 1)
            w.position.y = 0.01 + 0.19 * fill
            w.isHidden = s.res("water") < 0.2
        }

        // ---- 老刘 and the slab
        shoreCabinet?.isHidden = !s.has("slab_shored")
        let leverUsed = s.has("liu_freed") || s.has("pinned") && (s.fired["slab"] != nil) && !s.has("slab_shored") && s.round > 1
        lever?.isHidden = !leverUsed
        tableLegLever?.isHidden = leverUsed

        // ---- the structure being shaken apart
        let worn = CGFloat(s.shelter)
        for (i, c) in cracks.enumerated() { c.isHidden = !(worn < 52 - CGFloat(i) * 14 || (strong && i == 0)) }
        shockDebris?.isHidden = !(strong || worn < 30)

        // ---- dust
        let phoneOn = !phoneSpot.isHidden
        let beamOn = !(crackBeam?.isHidden ?? true) || !(stairBeam?.isHidden ?? true)
        let lightLevel = max(phoneOn ? 0.5 : 0, dayIn * 0.5, breach ? 0.75 : 0, standby ? 0.12 : 0, 0.07)
        let thick = dust + (shock ? 0.35 : 0)
        hazeAll?.birthRate = 6 + 34 * thick
        hazeAll?.particleColor = NSColor(white: 0.62 * lightLevel, alpha: min(0.32, 0.05 + 0.16 * thick))
        hazePhone?.birthRate = phoneOn ? 3 + 20 * thick : 0
        hazePhone?.particleColor = SK.color(0.86, 0.82, 0.76, min(0.3, 0.035 + 0.09 * thick))
        motesPhone?.birthRate = phoneOn ? 25 + 170 * thick : 0
        motesPhone?.particleColor = SK.color(0.9, 0.86, 0.78, 0.55)
        hazeBeam?.birthRate = beamOn ? 3 + 16 * thick : 0
        hazeBeam?.particleColor = SK.color(0.78 * dayIn, 0.82 * dayIn, 0.88 * dayIn, min(0.3, 0.04 + 0.1 * thick))
        motesBeam?.birthRate = beamOn ? 20 + 140 * thick : 0
        motesBeam?.particleColor = SK.color(0.85, 0.9, 0.95, 0.6 * dayIn)
        hazeBreach?.birthRate = breach ? 4 + 18 * thick : 0
        hazeBreach?.particleColor = SK.color(0.88, 0.9, 0.95, min(0.3, 0.05 + 0.1 * thick))
        motesBreach?.birthRate = breach ? 40 + 160 * thick : 0
        motesBreach?.particleColor = SK.color(0.95, 0.95, 1.0, 0.65)
        for (i, f) in dustFalls.enumerated() {
            f.birthRate = shock ? (i == 0 ? 320 : 200) : (i < 2 ? 4 + 10 * dust : 0)
            f.particleColor = NSColor(white: 0.35 + 0.6 * lightLevel, alpha: 0.85)
        }
        gravel?.birthRate = shock ? (strong ? 70 : 30) : 0
        shockPuff?.birthRate = shock ? (strong ? 14 : 8) : 0
        shockPuff?.particleColor = NSColor(white: 0.25 + 0.5 * lightLevel, alpha: 0.11)
        plumes?.birthRate = shock ? (strong ? 10 : 5) : 0
        plumes?.particleColor = SK.rgb(0xBDB6AA).blended(withFraction: 1 - dayK, of: SK.rgb(0x2A2C30))?.withAlphaComponent(0.12) ?? .gray
        pocketGlow.isHidden = !(s.has("kid_above") && (lightLevel > 0.1))

        // ---- rain
        let wet = s.precip >= 0.5
        drips?.birthRate = wet ? CGFloat(6 + 14 * s.precip) : 0
        rain?.birthRate = CGFloat(max(0, s.precip)) * 2600
        // rain only shows where light catches it: faint at night
        rain?.particleColor = NSColor(white: 0.3 + 0.55 * dayK, alpha: 0.16 + 0.24 * dayK)
        umbrellaOpen?.isHidden = !wet
        umbrellaShut?.isHidden = wet
        puddle?.isHidden = !(s.precip >= 1.5 || (wet && worn < 60))

        // ---- the rescue
        let sx = (shaftX0 + shaftX1) / 2
        let top = surfY(sx, zCut) + 0.02
        let floorY = l4Top(sx)
        let digging = tunnel > 0.001 || breach
        let bottom = breach ? floorY : top - (top - floorY) * min(1, tunnel * 1.02)
        for p in shaftPlugs { p.node.isHidden = digging && bottom <= p.bottom + 0.04 }
        skinPlug?.isHidden = digging
        holePlug?.isHidden = !breach

        for (i, c) in crewTop.enumerated() { c.isHidden = !(teams && (i < 2 || found)) }
        listener?.isHidden = !(teams && (heard >= 45 || found) && !breach)
        for (i, f) in flags.enumerated() { f.isHidden = !(teams && (heard >= 50 + Double(i) * 20 || found)) }
        marker?.isHidden = !(found || (teams && heard >= 75))
        tripod?.isHidden = !(found && digging)
        rope?.isHidden = !(found && digging)
        if let rp = rope {
            let ry = rp.position.y
            rp.scale = SCNVector3(1, max(0.2, ry - bottom - 0.3), 1)
        }
        let depth = top - bottom
        if let sc = shaftCrew {
            sc.isHidden = !(digging && !breach && tunnel > 0.08)
            sc.position = SCNVector3(sx, depth > 1.0 ? bottom : top, depth > 1.0 ? 0.62 : 0.85)
            sc.eulerAngles.y = depth > 1.0 ? 0.0 : 0.4
        }
        breachCrew?.isHidden = !breach || rescued
        stretcher?.isHidden = !(breach || rescued)
        shaftLamp.isHidden = !(digging && !breach) || tunnel < 0.04
        shaftLamp.position = SCNVector3(sx - 0.18, bottom + min(1.5, max(0.5, depth * 0.7)), 0.45)
        shaftLamp.light?.intensity = 260
        if let sn = shaftDust?.emitterShape { _ = sn }
        if let dn = scene.rootNode.childNode(withName: "shaftDust", recursively: true) {
            dn.position = SCNVector3(sx, bottom + 0.15, 0.75)
        }
        shaftDust?.birthRate = (digging && !breach && tunnel > 0.04) ? 3 : 0

        breachSpot.isHidden = !breach
        breachSpot.light?.intensity = 950
        breachBeam?.isHidden = !breach
        breachBeam?.opacity = 0.6 + 0.4 * dust
        tube?.isHidden = !(found && !breach)

        // floodlights work at night once the crews are here
        let floods = teams && (night || sunK < 0.15)
        floodTower?.isHidden = !teams
        for (i, l) in floodLamps.enumerated() {
            l.light?.intensity = floods ? 650 : 0
            floodBeams[i].isHidden = !floods
            floodBeams[i].opacity = 0.45 + 0.3 * CGFloat(min(1, s.precip))
            floodHeads[i].emission.contents = floods ? SK.rgb(0xFFF6E0) : NSColor.black
            floodHeads[i].emission.intensity = floods ? 2.5 : 0
        }
        beacon?.isHidden = !(teams && night)
        _ = generator

        if !particlesAttached {
            particlesAttached = true
            for (n, p) in pendingParticles { n.addParticleSystem(p) }
        }

        // ---- people
        showPeople(s, spots: spots(for: s))
        showBodies(s.dead, spots: bodySpots())
        dustPeople()
        for (i, b) in blankets.enumerated() {
            if rescued, i == 0, let p = s.people.first, !p.animal, !p.injured {
                let sx = (shaftX0 + shaftX1) / 2
                b.isHidden = false
                b.position = SCNVector3(sx, l4Top(sx) + 0.32 + (p.child ? 0.5 : 0.95), 0.7)
                b.scale = p.child ? SCNVector3(0.65, 0.65, 0.65) : SCNVector3(1, 1.1, 1)
            } else {
                b.isHidden = true
            }
        }
    }

    // MARK: - Where everyone is

    /// Inside the void, best-seen places first. Huddled where the slab is highest (by the
    /// table and cabinet), lying head-up-slope where it is low.
    private var voidSpots: [Spot] {
        [
            Spot(1.62, -0.07, 0.62, facing: -1.35, pose: .huddled),
            Spot(0.45, 0, 0.22, facing: .pi, pose: .lying),
            Spot(1.64, -0.07, -0.28, facing: -1.6, pose: .huddled),
            Spot(0.82, 0, 0.98, facing: .pi, pose: .lying),
            Spot(0.35, 0, -0.5, facing: .pi, pose: .lying),
            Spot(1.62, -0.07, 1.2, facing: -1.0, pose: .huddled),
            Spot(-0.5, 0, 0.25, facing: .pi, pose: .lying),
            Spot(-0.9, 0, -0.42, facing: .pi, pose: .lying),
            Spot(1.15, -0.12, -0.62, facing: -2.2, pose: .huddled),
            Spot(-0.15, 0, 0.62, facing: .pi, pose: .lying),
            Spot(-1.0, 0, -0.95, facing: .pi, pose: .lying),
            Spot(0.95, 0, 0.6, facing: .pi, pose: .lying),
        ]
    }

    /// Climbing out up the stairwell.
    private var climbSpots: [Spot] {
        [Spot(3.45, 0.6, 0.0, facing: .pi, pose: .standing), Spot(3.5, 1.2, -0.95, facing: .pi, pose: .standing),
         Spot(3.4, 3.24, 1.08, facing: -.pi / 2, pose: .standing), Spot(3.45, 3.95, -0.1, facing: .pi, pose: .standing),
         Spot(4.2, 1.62, -2.2, facing: .pi / 2, pose: .standing), Spot(3.5, 4.5, -1.05, facing: .pi, pose: .standing)]
    }

    private func spots(for s: SceneState) -> [Spot] {
        let rescued = s.has("rescued")
        let crawled = s.has("self_rescue")
        let pinned = s.has("pinned")
        let kidAbove = s.has("kid_above")
        let vs = voidSpots, cs = climbSpots
        var out: [Spot] = []
        var vi = 0, ci = 0, dogs = 0
        for (i, p) in s.people.enumerated() {
            if rescued && i == 0 && !p.animal {
                let sx = (shaftX0 + shaftX1) / 2
                out.append(Spot(sx, l4Top(sx) + 0.32, 0.7, facing: 0.2, pose: .standing))
                continue
            }
            if crawled && !p.injured && !p.animal && !(p.id == "liu" && pinned) && ci < cs.count {
                out.append(cs[ci]); ci += 1
                continue
            }
            if p.id == "liu" && pinned {
                out.append(Spot(-1.2, 0, 0.82, facing: .pi, pose: .lying))       // shins under the slab
                continue
            }
            if p.animal {
                out.append(dogs == 0 ? Spot(0.05, 0, 0.62, facing: -1.2, pose: .lying) : Spot(1.3, 0, -0.75, facing: 2.0, pose: .lying))
                dogs += 1
                continue
            }
            if p.child && kidAbove {
                let x: CGFloat = -0.2
                out.append(Spot(x, l4Top(x) - 0.04, 0.82, facing: 0.5, pose: .huddled))
                continue
            }
            if vi < vs.count {
                out.append(vs[vi]); vi += 1
            } else {
                let k = CGFloat(vi - vs.count)
                out.append(Spot(-0.2 + k * 0.35, 0, 1.15 - k * 0.1, facing: .pi, pose: .lying)); vi += 1
            }
        }
        return out
    }

    private func bodySpots() -> [Spot] {
        [Spot(-1.25, 0, -1.22, facing: .pi / 2), Spot(-1.1, 0, -0.62, facing: .pi / 2), Spot(-1.05, 0, 0.05, facing: .pi / 2),
         Spot(-1.3, 0, 1.12, facing: .pi / 2)]
    }

    /// The survivors are as grey with cement dust as everything else.
    private func dustPeople() {
        for n in peopleNode.childNodes {
            let id = ObjectIdentifier(n)
            guard !dustedPeople.contains(id) else { continue }
            dustedPeople.insert(id)
            n.enumerateChildNodes { c, _ in
                for m in c.geometry?.materials ?? [] where m.shaderModifiers == nil {
                    rbDust(m, amount: 0.38)
                }
            }
        }
    }
}

// MARK: - File-private toolkit

fileprivate typealias V3 = SIMD3<Float>

fileprivate func rbLin(_ r: Float, _ g: Float, _ b: Float) -> V3 { V3(pow(r, 2.2), pow(g, 2.2), pow(b, 2.2)) }

fileprivate func rbQ(_ yaw: Float, _ pitch: Float, _ roll: Float) -> simd_quatf {
    simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0)) * simd_quatf(angle: roll, axis: V3(0, 0, 1))
}

fileprivate struct RBRand {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x632BE59BD9B4E019 }
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(s >> 40) / 16_777_216
    }
    mutating func f(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
}

/// Broken-building colours: mostly concrete, some brick, plaster, carpet, files, timber.
fileprivate func rbPalette(_ r: inout RBRand) -> V3 {
    let k = r.next()
    let v = r.f(0.85, 1.12)
    if k < 0.66 { return rbLin(0.58, 0.57, 0.54) * v }
    if k < 0.75 { return rbLin(0.5, 0.33, 0.26) * v }
    if k < 0.83 { return rbLin(0.78, 0.76, 0.72) * v }
    if k < 0.9 { return rbLin(0.22, 0.22, 0.23) * v }
    if k < 0.94 { return rbLin(0.42, 0.32, 0.23) * v }
    if k < 0.97 { return rbLin(0.36, 0.39, 0.44) * v }
    if k < 0.985 { return rbLin(0.3, 0.4, 0.55) * v }
    return rbLin(0.66, 0.58, 0.3) * v
}

/// Accumulates flat-shaded pieces (boxes, rods) and smooth grids into one mesh.
fileprivate struct RBMesh {
    var pts: [V3] = []
    var idx: [UInt32] = []
    var cols: [V3] = []

    mutating func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V3) {
        let n = UInt32(pts.count)
        pts += [a, b, c, d]
        cols += [col, col, col, col]
        idx += [n, n + 1, n + 2, n, n + 2, n + 3]
    }

    mutating func tri(_ a: V3, _ b: V3, _ c: V3, _ col: V3) {
        let n = UInt32(pts.count)
        pts += [a, b, c]
        cols += [col, col, col]
        idx += [n, n + 1, n + 2, n, n + 2, n + 1]      // both sides
    }

    mutating func box(_ c: V3, _ size: V3, _ q: simd_quatf, jitter: Float = 0, col: V3, rng: inout RBRand) {
        var k: [V3] = []
        k.reserveCapacity(8)
        for i in 0..<8 {
            var p = V3((i & 1) == 0 ? -0.5 : 0.5, (i & 2) == 0 ? -0.5 : 0.5, (i & 4) == 0 ? -0.5 : 0.5) * size
            if jitter > 0 { p += V3(rng.f(-1, 1), rng.f(-1, 1), rng.f(-1, 1)) * size * jitter }
            k.append(q.act(p) + c)
        }
        quad(k[1], k[3], k[7], k[5], col)
        quad(k[0], k[4], k[6], k[2], col)
        quad(k[2], k[6], k[7], k[3], col)
        quad(k[0], k[1], k[5], k[4], col)
        quad(k[4], k[5], k[7], k[6], col)
        quad(k[0], k[2], k[3], k[1], col)
    }

    /// A thin tube along a polyline.
    mutating func rod(_ path: [V3], r: Float, sides: Int = 5, col: V3) {
        guard path.count > 1 else { return }
        for s in 0..<(path.count - 1) {
            let a = path[s], b = path[s + 1]
            let len = simd_length(b - a)
            guard len > 1e-5 else { continue }
            let d = (b - a) / len
            let ref: V3 = abs(d.y) < 0.9 ? V3(0, 1, 0) : V3(1, 0, 0)
            let u = simd_normalize(simd_cross(d, ref)), v = simd_cross(d, u)
            for k in 0..<sides {
                let a0 = Float(k) / Float(sides) * 2 * .pi, a1 = Float(k + 1) / Float(sides) * 2 * .pi
                let o0 = (u * cos(a0) + v * sin(a0)) * r, o1 = (u * cos(a1) + v * sin(a1)) * r
                quad(a + o0, a + o1, b + o1, b + o0, col)
            }
        }
    }

    /// Regular grid with shared vertices (smooth shading). The front is the side of
    /// ∂pos/∂u × ∂pos/∂v. `keep` is tested at each cell's centre.
    mutating func grid(_ nu: Int, _ nv: Int, pos: (Float, Float) -> V3, keep: (Float, Float) -> Bool, col: (V3) -> V3) {
        let base = UInt32(pts.count)
        for j in 0...nv {
            for i in 0...nu {
                let p = pos(Float(i) / Float(nu), Float(j) / Float(nv))
                pts.append(p)
                cols.append(col(p))
            }
        }
        let row = UInt32(nu + 1)
        for j in 0..<nv {
            for i in 0..<nu where keep((Float(i) + 0.5) / Float(nu), (Float(j) + 0.5) / Float(nv)) {
                let a = base + UInt32(j) * row + UInt32(i)
                idx += [a, a + 1, a + row + 1, a, a + row + 1, a + row]
            }
        }
    }

    func node(_ m: SCNMaterial) -> SCNNode {
        let g = SK.mesh(pts, idx, colors: cols)
        g.materials = [m]
        return SCNNode(geometry: g)
    }
}

fileprivate let rbDustColor = SK.rgb(0xB9B3A8)

/// World-space procedural surface: fbm grain, a derivative bump (no textures, no UV
/// stretching) and cement dust settled on whatever faces up.
fileprivate let rbSurfaceShader = """
#pragma arguments
float rbGrain;
float rbScale;
float rbBump;
float rbDust;
float4 rbDustCol;

#pragma declaration
float rb_hash(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float rb_noise(float3 x) {
    float3 i = floor(x); float3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(rb_hash(i + float3(0,0,0)), rb_hash(i + float3(1,0,0)), f.x),
                   mix(rb_hash(i + float3(0,1,0)), rb_hash(i + float3(1,1,0)), f.x), f.y),
               mix(mix(rb_hash(i + float3(0,0,1)), rb_hash(i + float3(1,0,1)), f.x),
                   mix(rb_hash(i + float3(0,1,1)), rb_hash(i + float3(1,1,1)), f.x), f.y), f.z);
}
float rb_fbm(float3 p) { float a = 0.5; float s = 0.0; for (int k = 0; k < 4; k++) { s += a * rb_noise(p); p = p * 2.13 + 1.7; a *= 0.5; } return s / 0.9375; }

#pragma body
float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
float3 q = wp * rbScale;
float fw = length(fwidth(q));
float h = mix(rb_fbm(q), 0.5, smoothstep(0.35, 1.0, fw));
if (rbBump > 0.0) {
    float3 dpx = dfdx(_surface.position);
    float3 dpy = dfdy(_surface.position);
    float dhx = dfdx(h) * rbBump;
    float dhy = dfdy(h) * rbBump;
    float3 N = _surface.normal;
    float3 r1 = cross(dpy, N);
    float3 r2 = cross(N, dpx);
    float det = dot(dpx, r1);
    float3 g = sign(det) * (dhx * r1 + dhy * r2);
    float3 nb = abs(det) * N - g;
    if (dot(nb, nb) > 1e-20) { _surface.normal = normalize(nb); }
}
float3 c = _surface.diffuse.rgb * (1.0 - rbGrain * 0.5 + rbGrain * h);
float d = rb_noise(wp * 2.7 + 3.1) * 0.6 + rb_noise(wp * 9.0) * 0.4;
float up = smoothstep(0.05, 0.8, wn.y);
float k = clamp(rbDust * (0.22 + 0.78 * up) * (0.45 + 1.0 * d), 0.0, 0.93);
_surface.diffuse.rgb = mix(c, rbDustCol.rgb, k);
_surface.roughness = mix(_surface.roughness, 1.0, k);
"""

fileprivate func rbDust(_ m: SCNMaterial, amount: CGFloat, grain: CGFloat = 0.12, scale: CGFloat = 9, bump: CGFloat = 0) {
    m.shaderModifiers = [.surface: rbSurfaceShader]
    m.setValue(NSNumber(value: Double(grain)), forKey: "rbGrain")
    m.setValue(NSNumber(value: Double(scale)), forKey: "rbScale")
    m.setValue(NSNumber(value: Double(bump)), forKey: "rbBump")
    m.setValue(NSNumber(value: Double(amount)), forKey: "rbDust")
    m.setValue(NSValue(scnVector4: SK.linear(rbDustColor)), forKey: "rbDustCol")
}

fileprivate func rbMat(_ color: NSColor, rough: CGFloat = 0.9, metal: CGFloat = 0, grain: CGFloat = 0.3, scale: CGFloat = 5,
                       bump: CGFloat = 0.01, dust: CGFloat = 0.3, doubleSided: Bool = false) -> SCNMaterial {
    let m = SK.mat(color, roughness: rough, metalness: metal, doubleSided: doubleSided)
    rbDust(m, amount: dust, grain: grain, scale: scale, bump: bump)
    return m
}

// Scenes may be built on a background thread: the little gradient cache is locked.
fileprivate var rbBeamCache: [String: NSImage] = [:]
fileprivate let rbBeamLock = NSLock()

/// Soft gradient for a shaft of light: bright along the axis, fading sideways and away from the source.
fileprivate func rbBeamImage(_ col: NSColor) -> NSImage {
    let c = col.usingColorSpace(.deviceRGB) ?? col
    let key = "\(c.redComponent)|\(c.greenComponent)|\(c.blueComponent)"
    rbBeamLock.lock()
    let cached = rbBeamCache[key]
    rbBeamLock.unlock()
    if let im = cached { return im }
    let w = 32, h = 128
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h {
        let v = Float(y) / Float(h - 1)
        let along = min(1, v / 0.08) * pow(1 - v, 1.2)
        for x in 0..<w {
            let u = abs(Float(x) / Float(w - 1) * 2 - 1)
            let across = pow(max(0, 1 - u * u), 2.2)
            let k = along * across
            let i = (y * w + x) * 4
            px[i] = UInt8(255 * min(1, Float(c.redComponent) * k))
            px[i + 1] = UInt8(255 * min(1, Float(c.greenComponent) * k))
            px[i + 2] = UInt8(255 * min(1, Float(c.blueComponent) * k))
        }
    }
    let im = SK.image(from: px, size: w, height: h)
    rbBeamLock.lock()
    rbBeamCache[key] = im
    rbBeamLock.unlock()
    return im
}

/// A visible shaft of light from `a` to `b`: three crossed quads, additive.
fileprivate func rbBeam(from a: SCNVector3, to b: SCNVector3, r0: CGFloat, r1: CGFloat, color: NSColor) -> SCNNode {
    let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
    let len = Float(sqrt(dx * dx + dy * dy + dz * dz))
    var pts: [V3] = []
    var uvs: [CGPoint] = []
    var idx: [UInt32] = []
    for k in 0..<3 {
        let phi = Float(k) / 3 * .pi
        let e = V3(cos(phi), sin(phi), 0)
        let n = UInt32(pts.count)
        pts += [e * -Float(r0), e * Float(r0), e * Float(r1) + V3(0, 0, -len), e * -Float(r1) + V3(0, 0, -len)]
        uvs += [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        idx += [n, n + 1, n + 2, n, n + 2, n + 3]
    }
    let g = SK.mesh(pts, idx, uvs: uvs)
    let m = SK.mat(.black, roughness: 1)
    m.lightingModel = .constant
    m.diffuse.contents = rbBeamImage(color)
    m.blendMode = .add
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    g.materials = [m]
    let node = SCNNode(geometry: g)
    node.castsShadow = false
    node.position = a
    let steep = abs(dy) > 0.9 * sqrt(dx * dx + dy * dy + dz * dz)
    node.look(at: b, up: steep ? SCNVector3(0, 0, 1) : SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    return node
}
