import SwiftUI
import SceneKit

/// All possible states for the Doris animation
enum DorisAnimationState: Equatable {
    case idle
    case listening(power: Double)
    case thinking
    case speaking(power: Double)
    
    static func == (lhs: DorisAnimationState, rhs: DorisAnimationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.listening, .listening): return true
        case (.thinking, .thinking): return true
        case (.speaking, .speaking): return true
        default: return false
        }
    }
    
    var isCircle: Bool {
        switch self {
        case .idle, .listening, .speaking: return true
        case .thinking: return false
        }
    }
    
    var power: Double {
        switch self {
        case .idle: return 0
        case .listening(let p), .speaking(let p): return p
        case .thinking: return 0
        }
    }
}

struct DorisAnimationView: View {
    let state: DorisAnimationState

    var body: some View {
        DorisSceneView(state: state)
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
    }
}

struct DorisSceneView: UIViewRepresentable {
    let state: DorisAnimationState

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

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 80)
        scene.rootNode.addChildNode(cameraNode)

        let tubeNode = context.coordinator.createInitialGeometry()
        scene.rootNode.addChildNode(tubeNode)
        context.coordinator.tubeNode = tubeNode
        
        context.coordinator.startDisplayLink()
        context.coordinator.applyState(state, animated: false)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let coord = context.coordinator
        coord.targetPower = state.power
        coord.isIdle = (state == .idle)
        
        if coord.lastIsCircle != state.isCircle {
            coord.applyState(state, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(warmWhite: warmWhite)
    }

    class Coordinator {
        let warmWhite: UIColor
        var tubeNode: SCNNode?
        
        var lastIsCircle: Bool = true
        var currentProgress: Float = 1.0
        var targetProgress: Float = 1.0
        var currentPower: Float = 0.0
        var targetPower: Double = 0.0
        var isIdle: Bool = true
        var breathePhase: Float = 0.0
        
        // Rotation state - animate this ourselves instead of using SCNAction
        var currentRotationX: Float = 0.0
        var targetRotationX: Float = 0.0
        var isSpinning: Bool = false
        
        private var displayLink: CADisplayLink?
        private var morphStartTime: CFTimeInterval = 0
        private var morphStartProgress: Float = 0
        private var isMorphing: Bool = false
        private let morphDuration: CFTimeInterval = 0.6

        private let length: Float = 30.0
        private let radius: Float = 5.6
        private let segments = 200
        private let tubeRadius: Float = 1.5
        private let radialSegments = 12
        private let circleRadius: Float = 30.0

        init(warmWhite: UIColor) {
            self.warmWhite = warmWhite
        }
        
        deinit {
            displayLink?.invalidate()
        }

        func createInitialGeometry() -> SCNNode {
            let points = generatePath(progress: 1.0, power: 0, breathe: 0)
            let geometry = buildTubeGeometry(path: points)
            
            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.eulerAngles = SCNVector3(0, 0, 0)
            return node
        }
        
        func startDisplayLink() {
            displayLink = CADisplayLink(target: self, selector: #selector(update))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
            displayLink?.add(to: .main, forMode: .common)
        }

        func applyState(_ state: DorisAnimationState, animated: Bool) {
            let newIsCircle = state.isCircle
            let newTargetProgress: Float = newIsCircle ? 1.0 : 0.0
            
            lastIsCircle = newIsCircle
            targetProgress = newTargetProgress
            
            if animated && abs(currentProgress - targetProgress) > 0.01 {
                isMorphing = true
                morphStartTime = CACurrentMediaTime()
                morphStartProgress = currentProgress
            } else if !animated {
                currentProgress = targetProgress
                isMorphing = false
            }
            
            // Handle rotation state
            if newIsCircle {
                // Stop spinning - we'll animate back to 0 in the update loop
                isSpinning = false
                targetRotationX = 0
            } else {
                // Start spinning
                isSpinning = true
            }
        }
        
        @objc private func update() {
            guard let tubeNode = tubeNode else { return }
            
            currentPower += (Float(targetPower) - currentPower) * 0.25
            
            if isIdle {
                breathePhase += 0.015
                if breathePhase > .pi * 2 { breathePhase -= .pi * 2 }
            }
            
            if isMorphing {
                let elapsed = CACurrentMediaTime() - morphStartTime
                let t = min(Float(elapsed / morphDuration), 1.0)
                let eased = easeInOutCubic(t)
                currentProgress = morphStartProgress + (targetProgress - morphStartProgress) * eased
                
                if t >= 1.0 {
                    isMorphing = false
                    currentProgress = targetProgress
                }
            }
            
            // Handle rotation
            if isSpinning {
                // Continuous rotation while thinking
                currentRotationX += 0.04  // Adjust speed here
                if currentRotationX > .pi * 2 {
                    currentRotationX -= .pi * 2
                }
            } else {
                // Animate back to 0 when not spinning
                if abs(currentRotationX) > 0.001 {
                    // Find shortest path to 0
                    if currentRotationX > .pi {
                        currentRotationX += 0.08  // Go forward to 2π
                        if currentRotationX >= .pi * 2 {
                            currentRotationX = 0
                        }
                    } else {
                        currentRotationX *= 0.85  // Ease back to 0
                        if abs(currentRotationX) < 0.01 {
                            currentRotationX = 0
                        }
                    }
                }
            }
            
            // Apply rotation directly to node
            tubeNode.eulerAngles = SCNVector3(currentRotationX, 0, 0)
            
            updateGeometry()
        }
        
        private func updateGeometry() {
            guard let tubeNode = tubeNode else { return }
            
            let breathe = isIdle ? sin(breathePhase) * 0.08 : 0
            let points = generatePath(progress: currentProgress, power: Double(currentPower), breathe: breathe)
            let geometry = buildTubeGeometry(path: points)
            
            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]
            
            tubeNode.geometry = geometry
        }

        private func generatePath(progress: Float, power: Double, breathe: Float) -> [SCNVector3] {
            var points: [SCNVector3] = []
            
            // Use segments + 1 to ensure the path closes properly
            // The last point will be at the same position as the first
            for i in 0...segments {
                let p = Float(i) / Float(segments)
                let loopPoint = loopCurvePoint(p: p)

                let angle = p * .pi * 2
                let pulseAmount = Float(power) * 8.0
                let breatheAmount = breathe * circleRadius
                let r = circleRadius + pulseAmount + breatheAmount
                let circlePoint = SCNVector3(r * cos(angle), r * sin(angle), 0)

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

        private func buildTubeGeometry(path: [SCNVector3]) -> SCNGeometry {
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [UInt32] = []
            let count = path.count

            // Build vertex rings along the path
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
                    let offset = right * cos(angle) * tubeRadius + forward * sin(angle) * tubeRadius
                    vertices.append(curr + offset)
                    normals.append(normalize(offset))
                }
            }

            // Build triangle indices - connect each ring to the next
            // For a closed loop, we connect ring (count-1) back to ring 0
            for i in 0..<(count - 1) {
                let currentRing = i
                let nextRing = i + 1
                
                for j in 0..<radialSegments {
                    let nextSeg = (j + 1) % radialSegments
                    let a = UInt32(currentRing * radialSegments + j)
                    let b = UInt32(currentRing * radialSegments + nextSeg)
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
        DorisAnimationView(state: .idle)
    }
}
