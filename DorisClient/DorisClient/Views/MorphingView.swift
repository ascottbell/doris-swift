import SwiftUI
import SceneKit

/// A view that can morph between the OS1 twisted loop and a circle
/// Used for transitions between thinking and speaking states
struct MorphingView: View {
    let morphProgress: CGFloat  // 0 = twisted loop, 1 = circle
    let isRotating: Bool
    let audioPower: Double
    
    var body: some View {
        MorphingSceneView(morphProgress: morphProgress, isRotating: isRotating)
            .frame(width: 250, height: 250)
            .scaleEffect(1.0 + (audioPower * 0.15 * morphProgress))  // Pulse only when circle
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 8)
    }
}

struct MorphingSceneView: UIViewRepresentable {
    let morphProgress: CGFloat
    let isRotating: Bool
    
    // Soft warm white
    private let warmWhite = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0)
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.isPlaying = true
        
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scnView.scene = scene
        
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 80)
        scene.rootNode.addChildNode(cameraNode)
        
        // Create the morphable geometry node
        let shapeNode = SCNNode()
        shapeNode.name = "morphShape"
        scene.rootNode.addChildNode(shapeNode)
        
        // Initial geometry
        updateGeometry(node: shapeNode, progress: Float(morphProgress))
        
        // Start rotation
        if isRotating {
            let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
            shapeNode.runAction(.repeatForever(rotation), forKey: "rotation")
        }
        
        context.coordinator.scnView = scnView
        context.coordinator.shapeNode = shapeNode
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let shapeNode = context.coordinator.shapeNode else { return }
        
        // Update geometry based on morph progress
        updateGeometry(node: shapeNode, progress: Float(morphProgress))
        
        // Handle rotation
        if isRotating {
            if shapeNode.action(forKey: "rotation") == nil {
                let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
                shapeNode.runAction(.repeatForever(rotation), forKey: "rotation")
            }
        } else {
            shapeNode.removeAction(forKey: "rotation")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var scnView: SCNView?
        var shapeNode: SCNNode?
    }
    
    private func updateGeometry(node: SCNNode, progress: Float) {
        // progress: 0 = twisted loop, 1 = circle
        let geometry = createMorphedGeometry(progress: progress)
        
        let material = SCNMaterial()
        material.diffuse.contents = warmWhite
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        node.geometry = geometry
    }
    
    /// Creates geometry that morphs between twisted loop and circle
    private func createMorphedGeometry(progress: Float) -> SCNGeometry {
        let segments = 200
        let tubeRadius: Float = 1.2 + (progress * 2.0)  // Thicker as it becomes circle
        
        // Parameters that morph
        let length: Float = 30.0 * (1.0 - progress)  // Shrinks to 0 for circle
        let radius: Float = 5.6 * (1.0 - progress)   // Shrinks to 0 for circle
        let circleRadius: Float = 25.0 * progress    // Grows for circle
        
        var points: [SCNVector3] = []
        
        for i in 0..<segments {
            let p = Float(i) / Float(segments)
            
            // Twisted loop point
            let loopPoint = curvePoint(p: p, length: length, radius: radius)
            
            // Circle point (in XY plane)
            let angle = p * .pi * 2
            let circlePoint = SCNVector3(
                cos(angle) * circleRadius,
                sin(angle) * circleRadius,
                0
            )
            
            // Interpolate between them
            let morphedPoint = SCNVector3(
                loopPoint.x * (1 - progress) + circlePoint.x * progress,
                loopPoint.y * (1 - progress) + circlePoint.y * progress,
                loopPoint.z * (1 - progress) + circlePoint.z * progress
            )
            
            points.append(morphedPoint)
        }
        
        return buildTubeGeometry(path: points, radius: tubeRadius, radialSegments: 12)
    }
    
    private func curvePoint(p: Float, length: Float, radius: Float) -> SCNVector3 {
        let pi2 = Float.pi * 2
        
        let x = length * sin(pi2 * p)
        let y = radius * cos(pi2 * 3 * p)
        
        var t = p.truncatingRemainder(dividingBy: 0.25) / 0.25
        t = p.truncatingRemainder(dividingBy: 0.25) - (2 * (1 - t) * t * (-0.0185) + t * t * 0.25)
        
        let quarter = Int(p * 4) % 4
        if quarter == 0 || quarter == 2 {
            t = -t
        }
        
        let z = radius * sin(pi2 * 2 * (p - t))
        
        return SCNVector3(x, y, z)
    }
    
    private func buildTubeGeometry(path: [SCNVector3], radius: Float, radialSegments: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []
        
        let count = path.count
        
        for i in 0..<count {
            let prev = path[(i - 1 + count) % count]
            let curr = path[i]
            let next = path[(i + 1) % count]
            
            let tangent = normalize(next - prev)
            
            var up = SCNVector3(0, 0, 1)
            if abs(dot(tangent, up)) > 0.9 {
                up = SCNVector3(0, 1, 0)
            }
            let right = normalize(cross(tangent, up))
            let forward = normalize(cross(right, tangent))
            
            for j in 0..<radialSegments {
                let angle = Float(j) / Float(radialSegments) * .pi * 2
                let offset = right * cos(angle) * radius + forward * sin(angle) * radius
                
                vertices.append(curr + offset)
                normals.append(normalize(offset))
            }
        }
        
        for i in 0..<count {
            let nextRing = (i + 1) % count
            
            for j in 0..<radialSegments {
                let nextSeg = (j + 1) % radialSegments
                
                let a = UInt32(i * radialSegments + j)
                let b = UInt32(i * radialSegments + nextSeg)
                let c = UInt32(nextRing * radialSegments + j)
                let d = UInt32(nextRing * radialSegments + nextSeg)
                
                indices.append(contentsOf: [a, c, b])
                indices.append(contentsOf: [b, c, d])
            }
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
    
    private func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        return len > 0 ? SCNVector3(v.x / len, v.y / len, v.z / len) : v
    }
    
    private func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    
    private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }
}

private func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
}

private func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
}

private func * (v: SCNVector3, s: Float) -> SCNVector3 {
    SCNVector3(v.x * s, v.y * s, v.z * s)
}

#Preview {
    ZStack {
        Color(hex: "d1684e").ignoresSafeArea()
        
        VStack(spacing: 40) {
            MorphingView(morphProgress: 0.0, isRotating: true, audioPower: 0)
            MorphingView(morphProgress: 0.5, isRotating: false, audioPower: 0)
            MorphingView(morphProgress: 1.0, isRotating: false, audioPower: 0.5)
        }
    }
}
