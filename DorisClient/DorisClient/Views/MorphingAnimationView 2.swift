import SwiftUI
import SceneKit

/// Animation state for the morphing view
enum AnimationState {
    case loop      // Twisted DNA-like infinity loop
    case circle    // Simple ring outline
}

/// Her OS1-inspired morphing animation using SceneKit
/// Smoothly transitions between a twisted loop (thinking) and circle (speaking)
struct MorphingAnimationView: View {
    let state: AnimationState
    let audioPower: Double // 0-1, for pulsing the circle when speaking

    var body: some View {
        MorphingSceneView(state: state, audioPower: audioPower)
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
    }
}

struct MorphingSceneView: UIViewRepresentable {
    let state: AnimationState
    let audioPower: Double

    // Soft warm white matching the original views
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

        // Create the morphing tube node
        let tubeNode = context.coordinator.createMorphingTube()
        scene.rootNode.addChildNode(tubeNode)

        // Start the continuous rotation for loop state
        let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
        tubeNode.runAction(.repeatForever(rotation), forKey: "rotation")

        // Store references
        context.coordinator.scnView = scnView
        context.coordinator.tubeNode = tubeNode

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateState(state, audioPower: audioPower)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(warmWhite: warmWhite)
    }

    class Coordinator {
        let warmWhite: UIColor
        var scnView: SCNView?
        var tubeNode: SCNNode?

        private var currentProgress: Float = 0.0 // 0 = loop, 1 = circle
        private var targetProgress: Float = 0.0
        private var currentAudioPower: Float = 0.0

        // Geometry parameters
        private let length: Float = 30.0
        private let radius: Float = 5.6
        private let segments = 200
        private let tubeRadius: Float = 1.2
        private let radialSegments = 12
        private let circleRadius: Float = 28.0 // Visual size to match loop

        init(warmWhite: UIColor) {
            self.warmWhite = warmWhite
        }

        func createMorphingTube() -> SCNNode {
            // Start with the loop geometry
            let points = generateMorphedPath(progress: 0.0, audioPower: 0.0)
            let geometry = buildTubeGeometry(path: points, radius: tubeRadius, radialSegments: radialSegments)

            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]

            return SCNNode(geometry: geometry)
        }

        func updateState(_ state: AnimationState, audioPower: Double) {
            targetProgress = state == .circle ? 1.0 : 0.0
            currentAudioPower = Float(audioPower)

            // Only animate if there's a change
            guard let tubeNode = tubeNode else { return }

            // Remove any existing morph animation
            tubeNode.removeAction(forKey: "morph")

            let startProgress = currentProgress
            let duration: TimeInterval = 0.5

            // Create smooth morphing animation
            let morphAction = SCNAction.customAction(duration: duration) { [weak self] node, elapsedTime in
                guard let self = self else { return }

                let t = Float(elapsedTime / duration)
                // Ease in-out for smooth transition
                let eased = self.easeInOutCubic(t)

                let newProgress = startProgress + (self.targetProgress - startProgress) * eased
                self.currentProgress = newProgress

                // Regenerate geometry
                let points = self.generateMorphedPath(progress: newProgress, audioPower: Double(self.currentAudioPower))
                let newGeometry = self.buildTubeGeometry(path: points, radius: self.tubeRadius, radialSegments: self.radialSegments)

                let material = SCNMaterial()
                material.diffuse.contents = self.warmWhite
                material.lightingModel = .constant
                material.isDoubleSided = true
                newGeometry.materials = [material]

                node.geometry = newGeometry
            }

            tubeNode.runAction(morphAction, forKey: "morph") {
                // After morph completes, continue updating if in circle mode for audio pulsing
                if state == .circle {
                    self.startAudioPulseUpdates()
                }
            }

            // Handle rotation based on state
            if state == .loop {
                // Resume rotation if not already running
                if tubeNode.action(forKey: "rotation") == nil {
                    let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
                    tubeNode.runAction(.repeatForever(rotation), forKey: "rotation")
                }
            } else {
                // Stop rotation when in circle mode
                tubeNode.removeAction(forKey: "rotation")
            }
        }

        private func startAudioPulseUpdates() {
            guard let tubeNode = tubeNode else { return }

            // Remove any existing pulse animation
            tubeNode.removeAction(forKey: "audioPulse")

            // Create a repeating action that updates geometry based on audio power
            let pulseAction = SCNAction.customAction(duration: 0.1) { [weak self] node, _ in
                guard let self = self, self.currentProgress > 0.99 else { return }

                let points = self.generateMorphedPath(progress: self.currentProgress, audioPower: Double(self.currentAudioPower))
                let newGeometry = self.buildTubeGeometry(path: points, radius: self.tubeRadius, radialSegments: self.radialSegments)

                let material = SCNMaterial()
                material.diffuse.contents = self.warmWhite
                material.lightingModel = .constant
                material.isDoubleSided = true
                newGeometry.materials = [material]

                node.geometry = newGeometry
            }

            tubeNode.runAction(.repeatForever(pulseAction), forKey: "audioPulse")
        }

        /// Generate the morphed path by interpolating between loop and circle
        private func generateMorphedPath(progress: Float, audioPower: Double) -> [SCNVector3] {
            var points: [SCNVector3] = []

            for i in 0..<segments {
                let p = Float(i) / Float(segments)

                // Loop curve point
                let loopPoint = curvePoint(p: p, length: length, radius: radius)

                // Circle point (in XY plane)
                let angle = p * .pi * 2
                let pulseAmount = Float(audioPower) * 3.0 // Amplify the pulse effect
                let currentRadius = circleRadius + pulseAmount
                let circlePoint = SCNVector3(
                    currentRadius * cos(angle),
                    currentRadius * sin(angle),
                    0
                )

                // Lerp between loop and circle
                let morphedPoint = SCNVector3(
                    loopPoint.x + (circlePoint.x - loopPoint.x) * progress,
                    loopPoint.y + (circlePoint.y - loopPoint.y) * progress,
                    loopPoint.z + (circlePoint.z - loopPoint.z) * progress
                )

                points.append(morphedPoint)
            }

            return points
        }

        /// The parametric curve function for the twisted loop
        private func curvePoint(p: Float, length: Float, radius: Float) -> SCNVector3 {
            let pi2 = Float.pi * 2

            // X: horizontal figure-8
            let x = length * sin(pi2 * p)

            // Y: vertical oscillation (3x frequency)
            let y = radius * cos(pi2 * 3 * p)

            // Z: the weaving (over/under)
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

        // MARK: - Math utilities

        private func easeInOutCubic(_ t: Float) -> Float {
            if t < 0.5 {
                return 4 * t * t * t
            } else {
                let f = 2 * t - 2
                return 1 + f * f * f / 2
            }
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
}

// MARK: - Vector operators

private func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
}

private func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
}

private func * (v: SCNVector3, s: Float) -> SCNVector3 {
    SCNVector3(v.x * s, v.y * s, v.z * s)
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "d1684e")
            .ignoresSafeArea()

        VStack(spacing: 60) {
            Text("Loop State (Thinking)")
                .foregroundColor(.white)
            MorphingAnimationView(state: .loop, audioPower: 0.0)

            Text("Circle State (Speaking - Low)")
                .foregroundColor(.white)
            MorphingAnimationView(state: .circle, audioPower: 0.3)

            Text("Circle State (Speaking - High)")
                .foregroundColor(.white)
            MorphingAnimationView(state: .circle, audioPower: 1.0)
        }
    }
}
