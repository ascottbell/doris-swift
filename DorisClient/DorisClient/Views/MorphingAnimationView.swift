import SwiftUI
import SceneKit

/// Animation state for the morphing view
enum AnimationState: Equatable {
    case loop      // Twisted DNA-like infinity loop
    case circle    // Simple ring outline
}

/// Her OS1-inspired morphing animation using SceneKit
/// Smoothly transitions between a twisted loop (thinking) and circle (speaking)
struct MorphingAnimationView: View {
    let state: AnimationState
    let audioPower: Double

    var body: some View {
        MorphingSceneView(state: state, audioPower: audioPower)
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
    }
}

struct MorphingSceneView: UIViewRepresentable {
    let state: AnimationState
    let audioPower: Double

    private let warmWhite = UIColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0)

    func makeUIView(context: Context) -> SCNView {
        print("MorphingSceneView: makeUIView called")
        
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
        let tubeNode = context.coordinator.createInitialGeometry()
        scene.rootNode.addChildNode(tubeNode)
        
        // Store references
        context.coordinator.tubeNode = tubeNode
        
        // Apply initial state
        context.coordinator.applyState(state, animated: false)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update audio power (always)
        context.coordinator.currentAudioPower = Float(audioPower)
        
        // Only trigger morph if state actually changed
        if context.coordinator.lastState != state {
            print("MorphingSceneView: State changed from \(String(describing: context.coordinator.lastState)) to \(state)")
            context.coordinator.applyState(state, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(warmWhite: warmWhite)
    }

    class Coordinator {
        let warmWhite: UIColor
        var tubeNode: SCNNode?
        var lastState: AnimationState?
        
        var currentProgress: Float = 0.0
        var currentAudioPower: Float = 0.0
        private var displayLink: CADisplayLink?

        // Geometry parameters
        private let length: Float = 30.0
        private let radius: Float = 5.6
        private let segments = 200
        private let tubeRadius: Float = 1.2
        private let radialSegments = 12
        private let circleRadius: Float = 28.0

        init(warmWhite: UIColor) {
            self.warmWhite = warmWhite
        }
        
        deinit {
            displayLink?.invalidate()
        }

        func createInitialGeometry() -> SCNNode {
            let points = generatePath(progress: 0.0, audioPower: 0.0)
            let geometry = buildTubeGeometry(path: points, radius: tubeRadius)
            
            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            
            // Start rotating
            let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
            node.runAction(.repeatForever(rotation), forKey: "rotation")
            
            return node
        }

        func applyState(_ state: AnimationState, animated: Bool) {
            lastState = state
            
            guard let tubeNode = tubeNode else { 
                print("Coordinator: No tubeNode!")
                return 
            }
            
            let targetProgress: Float = (state == .circle) ? 1.0 : 0.0
            
            if !animated {
                currentProgress = targetProgress
                updateGeometry()
                updateRotation(for: state)
                if state == .circle {
                    startPulseUpdates()
                } else {
                    stopPulseUpdates()
                }
                return
            }
            
            // Stop any existing morph
            tubeNode.removeAction(forKey: "morph")
            stopPulseUpdates()
            
            let startProgress = currentProgress
            let duration: TimeInterval = 0.5
            
            print("Coordinator: Morphing from \(startProgress) to \(targetProgress)")
            
            let morphAction = SCNAction.customAction(duration: duration) { [weak self] node, elapsedTime in
                guard let self = self else { return }
                
                let t = Float(elapsedTime / duration)
                let eased = self.easeInOutCubic(t)
                self.currentProgress = startProgress + (targetProgress - startProgress) * eased
                self.updateGeometry()
            }
            
            tubeNode.runAction(morphAction, forKey: "morph") { [weak self] in
                guard let self = self else { return }
                print("Coordinator: Morph complete, progress = \(self.currentProgress)")
                self.updateRotation(for: state)
                if state == .circle {
                    self.startPulseUpdates()
                }
            }
        }
        
        private func updateRotation(for state: AnimationState) {
            guard let tubeNode = tubeNode else { return }
            
            if state == .loop {
                if tubeNode.action(forKey: "rotation") == nil {
                    let rotation = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 2.5)
                    tubeNode.runAction(.repeatForever(rotation), forKey: "rotation")
                }
            } else {
                tubeNode.removeAction(forKey: "rotation")
            }
        }
        
        private func startPulseUpdates() {
            stopPulseUpdates()
            
            displayLink = CADisplayLink(target: self, selector: #selector(pulseUpdate))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
            displayLink?.add(to: .main, forMode: .common)
        }
        
        private func stopPulseUpdates() {
            displayLink?.invalidate()
            displayLink = nil
        }
        
        @objc private func pulseUpdate() {
            guard currentProgress > 0.9 else { return }
            updateGeometry()
        }
        
        private func updateGeometry() {
            guard let tubeNode = tubeNode else { return }
            
            let points = generatePath(progress: currentProgress, audioPower: Double(currentAudioPower))
            let geometry = buildTubeGeometry(path: points, radius: tubeRadius)
            
            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]
            
            tubeNode.geometry = geometry
        }

        private func generatePath(progress: Float, audioPower: Double) -> [SCNVector3] {
            var points: [SCNVector3] = []

            for i in 0..<segments {
                let p = Float(i) / Float(segments)

                // Loop point
                let loopPoint = loopCurvePoint(p: p)

                // Circle point
                let angle = p * .pi * 2
                let pulseAmount = Float(audioPower) * 5.0
                let r = circleRadius + pulseAmount
                let circlePoint = SCNVector3(r * cos(angle), r * sin(angle), 0)

                // Lerp
                let x = loopPoint.x + (circlePoint.x - loopPoint.x) * progress
                let y = loopPoint.y + (circlePoint.y - loopPoint.y) * progress
                let z = loopPoint.z + (circlePoint.z - loopPoint.z) * progress

                points.append(SCNVector3(x, y, z))
            }

            return points
        }

        private func loopCurvePoint(p: Float) -> SCNVector3 {
            let pi2 = Float.pi * 2
            let x = length * sin(pi2 * p)
            let y = radius * cos(pi2 * 3 * p)

            var t = p.truncatingRemainder(dividingBy: 0.25) / 0.25
            t = p.truncatingRemainder(dividingBy: 0.25) - (2 * (1 - t) * t * (-0.0185) + t * t * 0.25)

            let quarter = Int(p * 4) % 4
            if quarter == 0 || quarter == 2 { t = -t }

            let z = radius * sin(pi2 * 2 * (p - t))
            return SCNVector3(x, y, z)
        }

        private func buildTubeGeometry(path: [SCNVector3], radius: Float) -> SCNGeometry {
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [UInt32] = []
            let count = path.count

            for i in 0..<count {
                let prev = path[(i - 1 + count) % count]
                let curr = path[i]
                let next = path[(i + 1) % count]

                let tangent = normalize(next - prev)
                var up = SCNVector3(0, 1, 0)
                if abs(dot(tangent, up)) > 0.9 { up = SCNVector3(1, 0, 0) }
                
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
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }

            return SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
        }

        private func easeInOutCubic(_ t: Float) -> Float {
            t < 0.5 ? 4 * t * t * t : 1 + pow(2 * t - 2, 3) / 2
        }

        private func normalize(_ v: SCNVector3) -> SCNVector3 {
            let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            return len > 0 ? SCNVector3(v.x / len, v.y / len, v.z / len) : v
        }

        private func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
            a.x * b.x + a.y * b.y + a.z * b.z
        }

        private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }
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
        MorphingAnimationView(state: .loop, audioPower: 0.0)
    }
}
