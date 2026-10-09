import SceneKit
import AppKit

/// Fallback for scenarios without a hand-built scene (e.g. user scenarios):
/// a camp on snow, sand or grass depending on the climate.
final class GenericScene: ScenarioScene {
    private var height: (CGFloat, CGFloat) -> CGFloat = { _, _ in 0 }

    override func build(_ s: SceneState) {
        let cold = s.temp < 2, hot = s.temp > 28
        skyStyle = cold ? .alpine : (hot ? .desert : .overcast)
        if hot { precipKind = .dust; hazeColor = SK.rgb(0xE2CDB0) }
        let noise = SK.Noise(seed: 42)
        let h: (Float, Float) -> Float = { x, z in
            let d = sqrt(x * x + z * z)
            let flat = SK.smoothstep(8, 30, d)
            return (noise.fbm(x / 40, z / 40) - 0.45) * 9 * flat + flat * flat * 4
        }
        height = { x, z in CGFloat(h(Float(x), Float(z))) }
        let low: SIMD3<Float> = cold ? [0.92, 0.94, 0.97] : (hot ? [0.82, 0.66, 0.46] : [0.36, 0.45, 0.26])
        let high: SIMD3<Float> = cold ? [0.55, 0.57, 0.6] : (hot ? [0.72, 0.52, 0.34] : [0.42, 0.38, 0.30])
        let ground = SK.terrain(size: 260, segments: 180, height: h, color: { _, _, _, slope in
            SK.mix(low, high, slope * 1.6)
        }, material: SK.mat(.white, roughness: cold ? 0.7 : 0.95))
        world.addChildNode(ground)

        // tent
        let canvas = SK.mat(SK.rgb(0xD0763A), roughness: 0.85, doubleSided: true)
        let tent = SCNNode(geometry: SCNPyramid(width: 3.2, height: 2, length: 3.6))
        tent.geometry?.materials = [canvas]
        tent.position = SCNVector3(-4, height(-4, -3), -3)
        tent.eulerAngles.y = 0.4
        world.addChildNode(tent)
        // a few rocks
        let stone = SK.noiseMat(SK.rgb(0x77736E), SK.rgb(0x4B4845), scale: 4, seed: 3)
        for i in 0..<8 {
            let r = SK.rock(Float(0.4 + Double(i % 3) * 0.3), stone, seed: UInt64(i + 5))
            let a = CGFloat(i) * 0.8, d: CGFloat = 9 + CGFloat(i % 4) * 2.5
            r.position = SCNVector3(sin(a) * d, height(sin(a) * d, cos(a) * d), cos(a) * d)
            world.addChildNode(r)
        }
        addFire(at: SCNVector3(0, height(0, 0), 0))
        cameraTarget = SCNVector3(0, 1, 0)
        cameraDistance = 17
        cameraPitch = 18
    }

    override func apply(_ s: SceneState, old: SceneState?) {
        showPeople(s, spots: Spot.ring(SCNVector3(0, 0, 0), radius: 2.2, count: max(1, s.people.count), start: 0.3, y: height))
        showBodies(s.dead, spots: Spot.line(from: SCNVector3(6, 0, -6), to: SCNVector3(9, 0, -3), count: 6, facing: 0.6, y: height))
    }
}
