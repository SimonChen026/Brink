import SwiftUI
import SceneKit
import BrinkCore

/// Which 3D scene renders which scenario. User scenarios fall back to a generic camp.
enum SceneRegistry {
    static let scenes: [String: ScenarioScene.Type] = [
        "snowline": SnowlineScene.self,
        "adrift": AdriftScene.self,
        "deepshaft": DeepshaftScene.self,
        "sandsea": SandseaScene.self,
        "castaway": CastawayScene.self,
        "polarnight": PolarnightScene.self,
        "flood": FloodScene.self,
        "rubble": RubbleScene.self,
        "finale": FinaleScene.self,
        "tutorial": TutorialScene.self,
        "icebound": IceboundScene.self,
        "fogforest": FogforestScene.self
    ]

    static func make(_ scenarioId: String) -> ScenarioScene {
        (scenes[scenarioId] ?? GenericScene.self).init()
    }
}

/// A live SceneKit view of a scenario. Drag to orbit, scroll/pinch to zoom.
struct ScenarioSceneView: NSViewRepresentable {
    let state: SceneState
    var interactive = true
    /// Bump to put the camera back where the scene wants it.
    var resetToken = 0

    final class Coordinator {
        var scene: ScenarioScene?
        var scenarioId = ""
        var last: SceneState?
        var resetToken = 0
        /// Identifies the scene being built in the background (a newer build wins).
        var buildToken = UUID()
        /// The latest state that arrived while the scene was still being built.
        var pending: SceneState?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.backgroundColor = .black
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.isPlaying = true
        v.loops = true
        v.allowsCameraControl = interactive
        v.showsStatistics = false
        install(in: v, context: context)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        if c.scenarioId != state.scenario {
            install(in: v, context: context)
            return
        }
        guard let sc = c.scene else {
            // still building: apply this state once the scene is ready
            c.pending = state
            return
        }
        if c.resetToken != resetToken {
            c.resetToken = resetToken
            sc.placeCamera()
            v.pointOfView = sc.cameraNode
        }
        guard c.last != state else { return }
        c.last = state
        sc.update(state)
    }

    /// Builds the scene off the main thread (terrain and textures take a few hundred ms), then shows it.
    private func install(in v: SCNView, context: Context) {
        let c = context.coordinator
        let st = state
        let token = UUID()
        c.buildToken = token
        c.scene = nil
        c.scenarioId = st.scenario
        c.last = st
        c.pending = nil
        c.resetToken = resetToken
        DispatchQueue.global(qos: .userInitiated).async {
            let sc = SceneRegistry.make(st.scenario)
            sc.update(st, animated: false)
            DispatchQueue.main.async {
                guard c.buildToken == token else { return }
                c.scene = sc
                v.scene = sc.scene
                v.pointOfView = sc.cameraNode
                let ctl = v.defaultCameraController
                ctl.interactionMode = .orbitTurntable
                ctl.target = sc.cameraTarget
                ctl.inertiaEnabled = true
                ctl.minimumVerticalAngle = Float(sc.minPitch)
                ctl.maximumVerticalAngle = 75
                if let p = c.pending, p != c.last {
                    c.last = p
                    sc.update(p)
                }
                c.pending = nil
            }
        }
    }
}

/// A scenario scene for SwiftUI: the live SceneKit view, or — when rendering screenshots offscreen,
/// where a live Metal view can't be captured — a still frame of the same scene.
struct SceneDisplay: View {
    /// Set by the screenshot tool.
    nonisolated(unsafe) static var stills = false
    let state: SceneState
    var resetToken = 0

    var body: some View {
        if SceneDisplay.stills {
            GeometryReader { g in
                let scene = SceneRegistry.make(state.scenario)
                let _ = scene.update(state, animated: false)
                Image(nsImage: SceneSnapshot.image(scene, size: CGSize(width: max(64, g.size.width) * 2, height: max(64, g.size.height) * 2)))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }
        } else {
            ScenarioSceneView(state: state, resetToken: resetToken)
        }
    }
}

/// The scene at the very start of a scenario (for the setup page).
extension SceneState {
    static func preview(_ s: Scenario) -> SceneState {
        let engine = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 1, controllers: [:]))
        return SceneState(engine: engine)
    }
}
