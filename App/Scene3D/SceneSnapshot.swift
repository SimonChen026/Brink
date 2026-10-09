import SceneKit
import AppKit
import Metal

/// Offscreen rendering of a scene (thumbnails, automated checks).
enum SceneSnapshot {
    static func image(_ s: ScenarioScene, size: CGSize, time: TimeInterval = 4) -> NSImage {
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = s.scene
        r.pointOfView = s.cameraNode
        r.autoenablesDefaultLighting = false
        return r.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
    }

    static func writePNG(_ img: NSImage, to url: URL) throws {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SceneSnapshot", code: 1)
        }
        try png.write(to: url)
    }
}
