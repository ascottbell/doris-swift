import SwiftUI
import SceneKit

/// Her OS1-inspired thinking animation using SceneKit
/// A twisted tube geometry that rotates continuously
struct ThinkingView: View {
    var body: some View {
        OS1SceneView()
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
    }
}

struct OS1SceneView: UIViewRepresentable {
    
    // Soft warm white matching IdleView
    private let warmWhite = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0) // FFF8F0
    
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
        
        // Camera - positioned to see the full shape
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 80)
        scene.rootNode.addChildNode(cameraNode)
        
        // Create the twisted tube
        let tubeNode = createTwistedTube()
        scene.rootNode.addChildNode(tubeNode)
        
        // Rotate around X axis like the original
        let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
        tubeNode.runAction(.repeatForever(rotation))
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
    
    /// Creates the OS1 twisted infinity loop
    /// Based on https://codepen.io/psyonline/pen/yayYWg
    private func createTwistedTube() -> SCNNode {
        // Parameters from the CodePen
        let length: Float = 30.0
        let radius: Float = 5.6
        let segments = 200
        let tubeRadius: Float = 1.2
        
        // Generate path points using the parametric curve
        var points: [SCNVector3] = []
        
        for i in 0..<segments {
            let p = Float(i) / Float(segments)
            let point = curvePoint(p: p, length: length, radius: radius)
            points.append(point)
        }
        
        // Build tube geometry along the path
        let geometry = buildTubeGeometry(path: points, radius: tubeRadius, radialSegments: 12)
        
        // Warm white, unlit material
        let material = SCNMaterial()
        material.diffuse.contents = warmWhite
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return SCNNode(geometry: geometry)
    }
    
    /// The parametric curve function from the CodePen
    /// Creates a figure-8 that weaves over and under itself
    private func curvePoint(p: Float, length: Float, radius: Float) -> SCNVector3 {
        let pi2 = Float.pi * 2
        
        // X: horizontal figure-8
        let x = length * sin(pi2 * p)
        
        // Y: vertical oscillation (3x frequency)
        let y = radius * cos(pi2 * 3 * p)
        
        // Z: the weaving (over/under) - this is the tricky part from the CodePen
        var t = p.truncatingRemainder(dividingBy: 0.25) / 0.25
        t = p.truncatingRemainder(dividingBy: 0.25) - (2 * (1 - t) * t * (-0.0185) + t * t * 0.25)
        
        let quarter = Int(p * 4) % 4
        if quarter == 0 || quarter == 2 {
            t = -t
        }
        
        let z = radius * sin(pi2 * 2 * (p - t))
        
        return SCNVector3(x, y, z)
    }
    
    /// Build a tube mesh that follows a path
    private func buildTubeGeometry(path: [SCNVector3], radius: Float, radialSegments: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []
        
        let count = path.count
        
        for i in 0..<count {
            // Get tangent from neighboring points
            let prev = path[(i - 1 + count) % count]
            let curr = path[i]
            let next = path[(i + 1) % count]
            
            let tangent = normalize(next - prev)
            
            // Build a perpendicular frame
            var up = SCNVector3(0, 1, 0)
            if abs(dot(tangent, up)) > 0.9 {
                up = SCNVector3(1, 0, 0)
            }
            let right = normalize(cross(tangent, up))
            let forward = normalize(cross(right, tangent))
            
            // Create ring of vertices
            for j in 0..<radialSegments {
                let angle = Float(j) / Float(radialSegments) * .pi * 2
                let offset = right * cos(angle) * radius + forward * sin(angle) * radius
                
                vertices.append(curr + offset)
                normals.append(normalize(offset))
            }
        }
        
        // Create triangles connecting rings
        for i in 0..<count {
            let nextRing = (i + 1) % count
            
            for j in 0..<radialSegments {
                let nextSeg = (j + 1) % radialSegments
                
                let a = UInt32(i * radialSegments + j)
                let b = UInt32(i * radialSegments + nextSeg)
                let c = UInt32(nextRing * radialSegments + j)
                let d = UInt32(nextRing * radialSegments + nextSeg)
                
                // Two triangles per quad
                indices.append(contentsOf: [a, c, b])
                indices.append(contentsOf: [b, c, d])
            }
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
    
    // MARK: - Vector math
    
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

// Vector operators
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
        Color(hex: "d1684e")
            .ignoresSafeArea()
        
        ThinkingView()
    }
}
