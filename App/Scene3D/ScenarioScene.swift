import SceneKit
import AppKit

/// A place where someone can be shown in a scene.
struct Spot {
    var pos: SCNVector3
    /// Facing direction in radians around the vertical axis (0 = facing +z).
    var facing: CGFloat
    /// Forced pose; nil = decided by the moment (hurt → lying, night → sitting, storm → huddled, day → standing).
    var pose: SK.Pose?

    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, facing: CGFloat = 0, pose: SK.Pose? = nil) {
        pos = SCNVector3(x, y, z)
        self.facing = facing
        self.pose = pose
    }

    /// Spots on a circle around a center, everyone facing the middle (e.g. around a fire).
    static func ring(_ center: SCNVector3, radius: CGFloat, count: Int, start: CGFloat = 0, y: ((CGFloat, CGFloat) -> CGFloat)? = nil) -> [Spot] {
        (0..<count).map { i in
            let a = start + CGFloat(i) / CGFloat(max(1, count)) * 2 * .pi
            let x = center.x + sin(a) * radius, z = center.z + cos(a) * radius
            return Spot(x, y?(x, z) ?? center.y, z, facing: a + .pi)
        }
    }

    /// Spots along a line from `a` to `b`, all facing `facing`.
    static func line(from a: SCNVector3, to b: SCNVector3, count: Int, facing: CGFloat, y: ((CGFloat, CGFloat) -> CGFloat)? = nil) -> [Spot] {
        (0..<count).map { i in
            let t = count <= 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
            let x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t
            return Spot(x, y?(x, z) ?? (a.y + (b.y - a.y) * t), z, facing: facing)
        }
    }
}

/// Base class for a scenario's living 3D diorama.
///
/// Subclasses set their configuration in `init()`, build the static world once in `build(_:)`
/// (terrain, wreck, house …) and react to the game in `apply(_:old:)` (water level, signals,
/// rescue helicopter, damage …). Sky, sun/moon, fog, precipitation, the fire and the people
/// are handled here — call `showPeople` / `showBodies` from `apply`.
class ScenarioScene {
    let scene = SCNScene()
    /// All scenario content goes under this node.
    let world = SCNNode()
    let cameraNode = SCNNode()
    let sunNode = SCNNode()
    let ambientNode = SCNNode()
    let weatherNode = SCNNode()
    let peopleNode = SCNNode()

    // MARK: Configuration (set in the subclass init)

    /// Sky look (turbidity, aurora at night …).
    var skyStyle: SK.SkyStyle = .alpine
    /// Highest sun elevation at noon, degrees (high in the tropics, low in polar winter).
    var sunPeak: Double = 55
    /// Direction the sunlight comes from, degrees clockwise from +z when seen from above.
    var sunAzimuth: Double = 150
    /// Fog end distance in perfectly clear weather (m). Low visibility shrinks it.
    var clearVisibility: CGFloat = 900
    /// Horizon haze color in clear daylight (fog color).
    var hazeColor: NSColor = SK.rgb(0xBFCCD9)
    /// Fog color in overcast/storm daylight.
    var stormColor: NSColor = SK.rgb(0x9AA3AD)
    /// Fog color at night.
    var nightColor: NSColor = SK.rgb(0x0A0F18)
    /// Precipitation emitter: a box of this width centered above `weatherCenter`.
    var weatherArea: CGFloat = 70
    var weatherCenter = SCNVector3(0, 22, 0)
    /// What falls from the sky. `.auto` = snow below +1 °C, otherwise rain.
    var precipKind: PrecipKind = .auto
    enum PrecipKind { case auto, snow, rain, dust, none }
    /// Blowing dust/sand color for `.dust`.
    var dustColor: NSColor = SK.rgb(0xC9A57A)
    /// Indoors / underground: no sky, no sun, no weather; light comes from lamps you add.
    var indoor = false
    /// Background and fog color when `indoor`.
    var indoorColor: NSColor = SK.rgb(0x07080A)
    /// Indoor fog end distance (dust, smoke).
    var indoorVisibility: CGFloat = 40
    /// Camera exposure offset (EV). Snow scenes look better around −0.5.
    var exposure: CGFloat = 0
    /// Screen-space ambient occlusion strength (0 = off). Speckles distant terrain, so only
    /// worth turning on for close-up interiors (a mine gallery, a collapsed room).
    var ssao: CGFloat = 0 { didSet { cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = ssao } }
    /// Multipliers for sunlight and sky light (bright snow/sand: < 1; dark forest: > 1).
    var sunScale: CGFloat = 1
    var iblScale: CGFloat = 1

    /// Default camera: orbit around `cameraTarget`.
    var cameraTarget = SCNVector3(0, 1, 0)
    var cameraDistance: CGFloat = 26
    /// Degrees around the target (0 = camera on the +z side looking toward −z).
    var cameraYaw: CGFloat = 25
    /// Degrees above the horizon.
    var cameraPitch: CGFloat = 16
    var cameraFOV: CGFloat = 42
    /// Lowest camera angle allowed when the player drags the view (degrees).
    var minPitch: CGFloat = 3

    // MARK: State

    private(set) var current: SceneState?
    private(set) var fireNode: SCNNode?
    private var fireLight: SK.FlickerLight?
    private var fireBase: CGFloat = 900
    /// 0 bright day … 1 dark night (indoors: 1).
    private(set) var darkness: Double = 0
    /// Fire particle systems and the nodes they attach to while the fire burns.
    private var fireEmitters: [(SCNParticleSystem, SCNNode)] = []
    private var skyKey = ""
    private var weatherKey = ""
    private var personNodes: [String: (node: SCNNode, key: String)] = [:]
    private var bodyNodes: [SCNNode] = []

    required init() {
        scene.rootNode.addChildNode(world)
        scene.rootNode.addChildNode(peopleNode)
        scene.rootNode.addChildNode(weatherNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowColor = NSColor(white: 0, alpha: 0.55)
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 120
        sun.shadowCascadeCount = 2
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 60
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)

        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 4000
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 0.5
        cam.bloomThreshold = 1.0
        cam.bloomBlurRadius = 10
        cam.vignettingIntensity = 0.35
        cam.vignettingPower = 1.1
        cam.contrast = 0.12
        cam.saturation = 1.06
        // subtle contact shadows only; strong SSAO speckles distant terrain
        cam.screenSpaceAmbientOcclusionIntensity = ssao
        cam.screenSpaceAmbientOcclusionRadius = 0.35
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.5
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.08
        cameraNode.camera = cam
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: Subclass hooks

    /// Build the static world (called once, before the first `apply`).
    func build(_ s: SceneState) {}

    /// React to the game state. `old` is nil on the first call.
    func apply(_ s: SceneState, old: SceneState?) {}

    // MARK: Driving the scene

    /// Bring the scene to a game state. Cheap when little changed; safe to call often.
    final func update(_ s: SceneState, animated: Bool = true) {
        let old = current
        if old == nil {
            build(s)
            placeCamera()
            cameraNode.camera?.fieldOfView = cameraFOV
            cameraNode.camera?.exposureOffset = exposure
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = (animated && old != nil) ? 1.2 : 0
        updateEnvironment(s)
        updateFire(s)
        apply(s, old: old)
        SCNTransaction.commit()
        current = s
    }

    /// Puts the camera at its default orbit position.
    func placeCamera() {
        let yaw = cameraYaw * .pi / 180, pitch = cameraPitch * .pi / 180
        let d = cameraDistance
        cameraNode.position = SCNVector3(cameraTarget.x + sin(yaw) * cos(pitch) * d,
                                         cameraTarget.y + sin(pitch) * d,
                                         cameraTarget.z + cos(yaw) * cos(pitch) * d)
        cameraNode.look(at: cameraTarget)
    }

    // MARK: Environment

    private func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { max(a, min(b, x)) }

    func updateEnvironment(_ s: SceneState) {
        let elev = s.sunElevation(peak: sunPeak)
        let day = Double(SK.smoothstep(-7, 6, Float(elev)))            // 0 night … 1 day
        let overcast = clamp((1 - s.sun) * 1.15 + s.precip * 0.2)
        let vis = clamp(s.visibility, 0.03, 1)
        darkness = indoor ? 1 : clamp(1 - day * (1 - 0.6 * overcast))

        if indoor {
            scene.background.contents = indoorColor
            scene.lightingEnvironment.contents = nil
            sunNode.light?.intensity = 0
            ambientNode.light?.intensity = 25
            ambientNode.light?.color = NSColor(calibratedRed: 0.75, green: 0.8, blue: 0.9, alpha: 1)
            scene.fogColor = indoorColor
            scene.fogStartDistance = indoorVisibility * 0.15
            scene.fogEndDistance = indoorVisibility
            scene.fogDensityExponent = 1.3
            return
        }

        // Sky (also the image-based lighting). Regenerated only when it visibly changes.
        let key = "\(Int((elev / 2).rounded()))|\(Int((overcast * 6).rounded()))|\(skyStyle)"
        if key != skyKey {
            skyKey = key
            let sky = SK.skyImage(style: skyStyle, sunElevationDeg: elev, overcast: overcast, azimuthDeg: sunAzimuth)
            scene.background.contents = sky
            scene.lightingEnvironment.contents = sky
        }
        scene.lightingEnvironment.intensity = CGFloat(0.06 + 0.7 * day * (1 - 0.3 * overcast)) * iblScale

        // Sun by day, moon by night (same light).
        let az = sunAzimuth * .pi / 180
        let el = (day > 0.02 ? max(elev, 3) : 35) * .pi / 180
        let dir = SCNVector3(CGFloat(sin(az) * cos(el)), CGFloat(sin(el)), CGFloat(cos(az) * cos(el)))
        sunNode.position = SCNVector3(dir.x * 100, dir.y * 100, dir.z * 100)
        sunNode.look(at: SCNVector3Zero)
        let warm = clamp(1 - elev / 25)                                  // low sun → warm
        let sunColor = SK.color(1, CGFloat(0.97 - 0.30 * warm), CGFloat(0.92 - 0.55 * warm))
        let moonColor = SK.color(0.62, 0.72, 0.95)
        if day > 0.02 {
            sunNode.light?.color = sunColor
            sunNode.light?.intensity = CGFloat(1150 * day * (1 - 0.8 * overcast)) * sunScale
            sunNode.light?.shadowColor = NSColor(white: 0, alpha: CGFloat(0.6 * (1 - overcast)))
        } else {
            sunNode.light?.color = moonColor
            sunNode.light?.intensity = CGFloat(110 * (1 - 0.7 * overcast))
            sunNode.light?.shadowColor = NSColor(white: 0, alpha: 0.35)
        }
        ambientNode.light?.intensity = CGFloat(18 + 90 * day)
        ambientNode.light?.color = day > 0.3 ? NSColor.white : moonColor

        // Fog follows visibility; its color follows the sky.
        let base = overcast > 0.5 ? stormColor : hazeColor
        let dayFog = base.blended(withFraction: CGFloat(warm * 0.25), of: SK.rgb(0xE8A06A)) ?? base
        let fogCol = nightColor.blended(withFraction: CGFloat(day), of: dayFog) ?? dayFog
        scene.fogColor = fogCol
        let far = clearVisibility * CGFloat(0.035 + 0.965 * pow(vis, 1.6))
        scene.fogStartDistance = far * 0.04
        scene.fogEndDistance = far
        scene.fogDensityExponent = 1.25

        updateWeather(s)
    }

    func updateWeather(_ s: SceneState) {
        var kind = precipKind
        if kind == .auto { kind = s.temp < 1 ? .snow : .rain }
        let intensity = clamp(s.precip / 2)
        let blowing = kind == .snow && s.wind > 35 && s.temp < -3
        let sandstorm = kind == .dust && s.wind > 25
        let key = "\(kind)|\(Int(intensity * 4))|\(Int(min(s.wind, 120) / 15))|\(blowing)|\(sandstorm)|\(Int(darkness * 3))"
        guard key != weatherKey else { return }
        weatherKey = key
        weatherNode.removeAllParticleSystems()
        weatherNode.position = weatherCenter
        let area = weatherArea
        if s.precip > 0.05 || blowing || sandstorm {
            switch kind {
            case .snow:
                weatherNode.addParticleSystem(SK.snow(intensity: max(intensity, blowing ? 0.6 : 0), wind: s.wind, area: area))
            case .rain:
                let rain = SK.rain(intensity: intensity, wind: s.wind, area: area)
                // rain only shows where light catches it: faint at night
                rain.particleColor = NSColor(white: CGFloat(0.85 - 0.45 * darkness), alpha: CGFloat(0.42 - 0.24 * darkness))
                weatherNode.addParticleSystem(rain)
            case .dust:
                weatherNode.addParticleSystem(SK.dust(intensity: clamp((s.wind - 20) / 50), wind: s.wind, color: dustColor, area: area))
            default: break
            }
        }
    }

    // MARK: Fire

    enum FireStyle { case campfire, stove, lamp }

    /// Adds the shelter fire (lit when `SceneState.fireLit`). Returns the node so you can move it.
    @discardableResult
    func addFire(at p: SCNVector3, scale: CGFloat = 1, style: FireStyle = .campfire, parent: SCNNode? = nil) -> SCNNode {
        let n = SCNNode()
        n.position = p
        var emitters: [(SCNParticleSystem, SCNNode)] = []
        switch style {
        case .campfire:
            let stone = SK.noiseMat(SK.rgb(0x6B6B6B), SK.rgb(0x3E3E40), scale: 3, seed: 11)
            for i in 0..<9 {
                let a = CGFloat(i) / 9 * 2 * .pi
                let r = SK.rock(Float(0.13 * scale), stone, seed: UInt64(30 + i))
                r.position = SCNVector3(sin(a) * 0.55 * scale, 0.05 * scale, cos(a) * 0.55 * scale)
                n.addChildNode(r)
            }
            let wood = SK.mat(SK.rgb(0x3A2A1E), roughness: 0.95)
            for i in 0..<4 {
                let log = SK.cylinder(0.06 * scale, 0.75 * scale, wood)
                log.eulerAngles = SCNVector3(CGFloat.pi / 2 - 0.35, CGFloat(i) * .pi / 2, 0)
                log.position = SCNVector3(0, 0.16 * scale, 0)
                let holder = SCNNode()
                holder.eulerAngles.y = CGFloat(i) * .pi / 2 + 0.4
                holder.addChildNode(log)
                n.addChildNode(holder)
            }
            let ember = SK.mat(SK.rgb(0x1A1410), roughness: 1, emission: SK.rgb(0x000000))
            let bed = SK.cylinder(0.32 * scale, 0.04 * scale, ember)
            bed.position.y = 0.02
            bed.name = "embers"
            n.addChildNode(bed)
            let f = SK.fire(scale: scale)
            let smoke = SK.smoke(scale: scale)
            let fn = SCNNode(); fn.position.y = 0.2 * scale; n.addChildNode(fn)
            let sn = SCNNode(); sn.position.y = 1.0 * scale; n.addChildNode(sn)
            emitters = [(f, fn), (smoke, sn)]
        case .stove:
            let iron = SK.mat(SK.rgb(0x2B2B2D), roughness: 0.6, metalness: 0.7)
            let body = SK.cylinder(0.3 * scale, 0.7 * scale, iron)
            body.position.y = 0.35 * scale
            n.addChildNode(body)
            let pipe = SK.cylinder(0.06 * scale, 1.6 * scale, iron)
            pipe.position.y = 1.5 * scale
            n.addChildNode(pipe)
            let glow = SK.box(0.22 * scale, 0.14 * scale, 0.02, SK.mat(.black, roughness: 1, emission: SK.rgb(0xFF7A2A)))
            glow.position = SCNVector3(0, 0.3 * scale, 0.3 * scale)
            glow.name = "embers"
            n.addChildNode(glow)
        case .lamp:
            let glass = SK.mat(SK.rgb(0xFFF2D0), roughness: 0.2, emission: SK.rgb(0xFFD88A))
            let bulb = SK.sphere(0.06 * scale, glass)
            bulb.name = "embers"
            n.addChildNode(bulb)
        }
        let light = SK.fireLight(intensity: style == .lamp ? 380 * scale : 950 * scale,
                                 color: style == .lamp ? SK.rgb(0xFFD9A0) : SK.rgb(0xFF9442),
                                 range: (style == .lamp ? 9 : 15) * scale)
        light.position.y = style == .campfire ? 0.6 * scale : 0.4 * scale
        n.addChildNode(light)
        (parent ?? world).addChildNode(n)
        fireNode = n
        fireLight = light
        fireBase = light.base
        fireEmitters = emitters
        return n
    }

    private func updateFire(_ s: SceneState) {
        guard let n = fireNode else { return }
        let lit = s.fireLit
        for (p, holder) in fireEmitters {
            let attached = holder.particleSystems?.contains(p) ?? false
            if lit && !attached { holder.addParticleSystem(p) }
            if !lit && attached { holder.removeParticleSystem(p) }
        }
        // a fire hardly lights anything in full daylight
        fireLight?.base = fireBase * CGFloat(0.12 + 0.88 * darkness)
        fireLight?.isHidden = !lit
        if let f = fireEmitters.first?.0 {
            f.particleColor = SK.rgb(0xFF8A2A).withAlphaComponent(CGFloat(0.35 + 0.65 * darkness))
        }
        if fireEmitters.count > 1 {
            // smoke: pale against a daylight sky, barely visible at night
            fireEmitters[1].0.particleColor = NSColor(white: CGFloat(0.82 - 0.62 * darkness), alpha: CGFloat(0.22 - 0.1 * darkness))
        }
        if let e = n.childNode(withName: "embers", recursively: true) {
            e.geometry?.firstMaterial?.emission.contents = lit ? SK.rgb(0xFF6A1A) : NSColor.black
            e.geometry?.firstMaterial?.emission.intensity = lit ? 1.4 : 0
        }
    }

    // MARK: People

    /// Shows the people at the given spots (in order; extra people are not shown).
    /// Nodes are reused, so the same person stays put between updates.
    func showPeople(_ s: SceneState, spots: [Spot], parent: SCNNode? = nil) {
        let par = parent ?? peopleNode
        let storm = s.precip >= 1.5 || s.wind >= 45
        var seen: Set<String> = []
        for (i, p) in s.people.enumerated() {
            guard i < spots.count else { break }
            let spot = spots[i]
            seen.insert(p.id)
            var pose: SK.Pose
            if p.injured {
                pose = .lying
            } else if let forced = spot.pose {
                pose = forced
            } else if storm || (s.isNight && s.temp < 0) {
                pose = .huddled
            } else if s.isNight || s.fireLit && s.hour >= 17 {
                pose = .sitting
            } else {
                pose = (i % 3 == 2) ? .sitting : .standing
            }
            let key = "\(pose)|\(p.child)|\(p.colorIndex)|\(p.animal)|\(Int(p.weight))"
            var node: SCNNode
            if let existing = personNodes[p.id], existing.key == key, existing.node.parent === par {
                node = existing.node
            } else {
                personNodes[p.id]?.node.removeFromParentNode()
                if p.animal {
                    node = SK.animal(weight: p.weight, color: animalColor(p), lying: p.injured || pose == .lying || pose == .huddled, seed: 0)
                } else {
                    node = SK.person(color: SK.clothing[p.colorIndex % SK.clothing.count], pose: pose, child: p.child, seed: 0)
                }
                node.name = "person:\(p.id)"
                // inner yaw from SK is replaced by the spot's facing
                node.eulerAngles.y = 0
                par.addChildNode(node)
                personNodes[p.id] = (node, key)
            }
            node.position = spot.pos
            node.eulerAngles.y = spot.facing
        }
        for (id, entry) in personNodes where !seen.contains(id) {
            entry.node.removeFromParentNode()
            personNodes[id] = nil
        }
    }

    func animalColor(_ p: ScenePerson) -> NSColor {
        let palette = [SK.rgb(0x8A6A4A), SK.rgb(0xC9A27C), SK.rgb(0x4A4038), SK.rgb(0xD9C7A8), SK.rgb(0x6E5A48)]
        return palette[p.colorIndex % palette.count]
    }

    /// Shows covered bodies for the dead at the given spots.
    func showBodies(_ count: Int, spots: [Spot], parent: SCNNode? = nil) {
        let n = min(count, spots.count)
        while bodyNodes.count > n { bodyNodes.removeLast().removeFromParentNode() }
        while bodyNodes.count < n {
            let i = bodyNodes.count
            let b = SK.shroud(seed: i * 37)
            b.position = spots[i].pos
            b.eulerAngles.y = spots[i].facing
            (parent ?? peopleNode).addChildNode(b)
            bodyNodes.append(b)
        }
    }
}
