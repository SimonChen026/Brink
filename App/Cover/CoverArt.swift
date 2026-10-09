import SwiftUI
import SceneKit
import BrinkCore

/// Key art for the home screen: each scenario's 3D scene at its most telling hour, as a slowly
/// drifting live view (the hero) and as stills (the scenario cards, the endless-mode card).
enum CoverPreset {
    /// The scene state a scenario is shown in on the cover.
    static func state(_ s: Scenario) -> SceneState {
        var st = SceneState.preview(s)
        func weather(_ id: String) {
            guard let w = s.climate.weather[id] else { return }
            st.weather = id
            st.precip = w.precip ?? 0
            st.wind = w.wind ?? 10
            st.visibility = w.visibility ?? 1
            st.sun = w.sun ?? 1
        }
        switch s.id {
        case "snowline": st.hour = 18.3; weather("clear"); st.fireLit = true
        case "adrift": st.hour = 17.6; weather("clear")
        case "deepshaft": st.hour = 12; weather("drip")
        case "rubble": st.hour = 15; weather("rain")
        case "sandsea": st.hour = 18.2; weather("clear"); st.fireLit = true
        case "castaway": st.hour = 18.2; weather("clear"); st.fireLit = true
        case "polarnight": st.hour = 23; weather("calm"); st.fireLit = true
        case "flood": st.hour = 18.0; weather("cloudy"); st.fireLit = true
        case "icebound":
            // dusk in freezing rain: the oil-drum fire behind the lorry, hazard lights up the hill
            st.hour = 18.3; weather("freezing_rain"); st.fireLit = true
            st.done.insert("fire_barrel"); st.flags.insert("bonfire")
        case "fogforest": st.hour = 17.4; weather("fog"); st.fireLit = true
        case "finale":
            st.hour = 22.5
            weather("snow")
            st.flags.insert("wave_hit")
            st.vars["flood"] = 3.5
            st.vars["town_fire"] = 70
            st.vars["crowd"] = 40
            st.vars["signal"] = 1
            st.fireLit = true
        default:
            st.hour = 18.4
            st.fireLit = s.shelter.fire != nil
        }
        return st
    }

    /// A framing made for the cover, where a scene's own default view isn't the best poster
    /// (the title sits on the left, so the subject goes right of centre).
    static func camera(_ id: String) -> (target: SCNVector3, yaw: CGFloat, pitch: CGFloat, distance: CGFloat)? {
        switch id {
        case "snowline": return (SCNVector3(-3, 2.5, -1.5), 40, 18, 24)     // from above: no foggy cliff tops in frame
        case "adrift": return (SCNVector3(-1.2, 0.8, 0), 8, 9, 9.5)        // close to the raft
        case "icebound": return (SCNVector3(0, 2.5, 8.5), -118, 11, 27)   // the drum and the group right of centre, the queue climbing left
        case "fogforest": return (SCNVector3(-0.4, 1.4, -2.6), 16, 6, 11) // the camp under the oak, a tree fern on the title side
        default: return nil
        }
    }

    /// The cover scene of a scenario, built and framed (call off the main thread for the live view).
    static func makeScene(_ id: String, state: SceneState) -> ScenarioScene {
        let sc = SceneRegistry.make(id)
        sc.update(state, animated: false)
        if let c = camera(id) {
            sc.cameraTarget = c.target
            sc.cameraYaw = c.yaw
            sc.cameraPitch = c.pitch
            sc.cameraDistance = c.distance
            sc.placeCamera()
        }
        return sc
    }
}

/// Stills of every scenario's cover scene, rendered once in the background.
@MainActor
@Observable
final class CoverArt {
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var states: [String: SceneState] = [:]

    func image(_ id: String) -> NSImage? { images[id] }

    /// The cover state of a scenario (built once: it runs the engine's setup).
    func state(_ s: Scenario) -> SceneState {
        if let st = states[s.id] { return st }
        let st = CoverPreset.state(s)
        states[s.id] = st
        return st
    }

    /// Screenshots: render every still right now, on this thread.
    func loadNow(_ scenarios: [Scenario]) {
        started = true
        for s in scenarios where images[s.id] == nil {
            let scene = CoverPreset.makeScene(s.id, state: state(s))
            images[s.id] = SceneSnapshot.image(scene, size: s.id == EndlessRun.finaleId ? CGSize(width: 1600, height: 720) : CGSize(width: 960, height: 540))
        }
    }

    /// Renders the stills one after another (finale first: it's the endless-mode card).
    func load(_ scenarios: [Scenario]) {
        guard !started else { return }
        started = true
        let order = scenarios.sorted { a, b in (a.id == EndlessRun.finaleId ? 0 : 1) < (b.id == EndlessRun.finaleId ? 0 : 1) }
        let jobs = order.map { ($0.id, CoverPreset.state($0)) }
        Task.detached(priority: .utility) {
            for (id, st) in jobs {
                let scene = CoverPreset.makeScene(id, state: st)
                let size = id == EndlessRun.finaleId ? CGSize(width: 1600, height: 720) : CGSize(width: 960, height: 540)
                let img = SceneSnapshot.image(scene, size: size)
                await MainActor.run { self.images[id] = img }
            }
        }
    }
}

/// The live hero scene: no interaction, the camera drifts slowly back and forth around the scene's
/// own best view. Transparent until the scene is built, so the still behind it shows through.
struct CoverSceneView: NSViewRepresentable {
    let state: SceneState

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var scene: ScenarioScene?
        var baseYaw: CGFloat = 0
        var baseDistance: CGFloat = 0
        var start = CACurrentMediaTime()

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let sc = scene else { return }
            let t = CACurrentMediaTime() - start
            sc.cameraYaw = baseYaw + CGFloat(sin(t * 0.09)) * 11
            sc.cameraDistance = baseDistance * (1 - 0.05 * CGFloat(sin(t * 0.06)))
            sc.placeCamera()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.isPlaying = true
        v.loops = true
        v.allowsCameraControl = false
        v.delegate = context.coordinator
        let c = context.coordinator
        let st = state
        DispatchQueue.global(qos: .userInitiated).async {
            let sc = CoverPreset.makeScene(st.scenario, state: st)
            DispatchQueue.main.async {
                c.baseYaw = sc.cameraYaw
                c.baseDistance = sc.cameraDistance
                c.start = CACurrentMediaTime()
                c.scene = sc
                v.scene = sc.scene
                v.pointOfView = sc.cameraNode
            }
        }
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {}

    /// The hero must not swallow scroll gestures meant for the page.
    static func dismantleNSView(_ v: SCNView, coordinator: Coordinator) {
        v.isPlaying = false
        v.scene = nil
    }
}

/// Screenshots: the hero as a full-resolution still, framed like the live cover.
struct CoverStill: View {
    let state: SceneState

    var body: some View {
        GeometryReader { g in
            let scene = CoverPreset.makeScene(state.scenario, state: state)
            Image(nsImage: SceneSnapshot.image(scene, size: CGSize(width: max(64, g.size.width) * 2, height: max(64, g.size.height) * 2)))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
        }
    }
}
