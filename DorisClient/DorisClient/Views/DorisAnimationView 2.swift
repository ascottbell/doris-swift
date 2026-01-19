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
        context.coordinator.setState(state, animated: false)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let coord = context.coordinator
        coord.targetPower = state.power
        coord.isIdle = (state == .idle)
        
        if coord.lastIsCircle != state.isCircle {
            coord.setState(state, animated: true)
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
        
        // Manual rotation control
        var currentRotationX: Float = 0.0
        var isSpinning: Bool = false
        
        private var displayLink: CADisplayLink?
        private var morphStartTime: CFTimeInterval = 0
        private var morphStartProgress: Float = 0
        private var isMorphing: Bool = false
        private let morphDuration: CFTimeInterval = 0.5

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

        func setState(_ state: DorisAnimationState, animated: Bool) {
            lastIsCircle = state.isCircle
            targetProgress = state.isCircle ? 1.0 : 0.0
            
            if animated && currentProgress != targetProgress {
                isMorphing = true
                morphStartTime = CACurrentMediaTime()
                morphStartProgress = currentProgress
            } else {
                currentProgress = targetProgress
                isMorphing = false
            }
            
            // Control rotation state - no SCNActions
            isSpinning = !state.isCircle
        }
        
        @objc private func update() {
            guard let tubeNode = tubeNode else { return }
            
            // Smooth power interpolation
            currentPower += (Float(targetPower) - currentPower) * 0.3
            
            // Breathing for idle
            if isIdle {
                breathePhase += 0.02
                if breathePhase > .pi * 2 { breathePhase -= .pi * 2 }
            }
            
            // Morphing animation
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
            
            // Handle rotation manually
            if isSpinning {
                currentRotationX += 0.04
                if currentRotationX > .pi * 2 {
                    currentRotationX -= .pi * 2
                }
            } else {
                // Animate back to flat (0 rotation)
                if abs(currentRotationX) > 0.01 {
                    // Find shortest path to 0
                    if currentRotationX > .pi {
                        // Closer to go forward to 2π (which is 0)
                        currentRotationX += 0.1
                        if currentRotationX >= .pi * 2 {
                            currentRotationX = 0
                        }
                    } else {
                        // Ease back toward 0
                        currentRotationX *= 0.88
                    }
                } else {
                    currentRotationX = 0
                }
            }
            
            // Apply rotation
            tubeNode.eulerAngles = SCNVector3(currentRotationX, 0, 0)
            
            updateGeometry()
        }
        
        private func updateGeometry() {
            guard let tubeNode = tubeNode else { return }
            
            let breathe = isIdle ? sin(breathePhase) * 0.1 : 0
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

            for i in 0..<segments {
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

            // Use parallel transport to get consistent frames around the loop
            var frames: [(normal: SCNVector3, binormal: SCNVector3)] = []
            
            // Compute tangents
            var tangents: [SCNVector3] = []
            for i in 0..<count {
                let prev = path[(i - 1 + count) % count]
                let next = path[(i + 1) % count]
                tangents.append(normalize(next - prev))
            }
            
            // Initialize first frame
            let t0 = tangents[0]
            var up = SCNVector3(0, 1, 0)
            if abs(dot(t0, up)) > 0.9 { up = SCNVector3(1, 0, 0) }
            var normal = normalize(cross(t0, up))
            var binormal = normalize(cross(t0, normal))
            frames.append((normal, binormal))
            
            // Parallel transport the frame along the curve
            for i in 1..<count {
                let t1 = tangents[i - 1]
                let t2 = tangents[i]
                
                // Rotate the frame to align with new tangent
                let axis = cross(t1, t2)
                let axisLen = sqrt(dot(axis, axis))
                
                if axisLen > 0.0001 {
                    let normalizedAxis = axis * (1.0 / axisLen)
                    let angle = acos(max(-1, min(1, dot(t1, t2))))
                    
                    // Rodrigues rotation
                    normal = rotateVector(normal, axis: normalizedAxis, angle: angle)
                    binormal = rotateVector(binormal, axis: normalizedAxis, angle: angle)
                }
                
                // Re-orthogonalize to prevent drift
                normal = normalize(cross(binormal, t2))
                binormal = normalize(cross(t2, normal))
                
                frames.append((normal, binormal))
            }
            
            // Fix the seam: compute twist between last and first frame
            let firstNormal = frames[0].normal
            let lastNormal = frames[count - 1].normal
            let lastTangent = tangents[count - 1]
            
            // Project both normals onto the plane perpendicular to the tangent at the seam
            let projFirst = normalize(firstNormal - lastTangent * dot(firstNormal, lastTangent))
            let projLast = normalize(lastNormal - lastTangent * dot(lastNormal, lastTangent))
            
            // Calculate twist angle
            var twistAngle = acos(max(-1, min(1, dot(projFirst, projLast))))
            let crossProd = cross(projLast, projFirst)
            if dot(crossProd, lastTangent) < 0 {
                twistAngle = -twistAngle
            }
            
            // Distribute twist correction across all frames
            for i in 0..<count {
                let correction = twistAngle * Float(i) / Float(count)
                let t = tangents[i]
                frames[i].normal = rotateVector(frames[i].normal, axis: t, angle: correction)
                frames[i].binormal = rotateVector(frames[i].binormal, axis: t, angle: correction)
            }
            
            // Build vertices using the corrected frames
            for i in 0..<count {
                let curr = path[i]
                let (normal, binormal) = frames[i]

                for j in 0..<radialSegments {
                    let angle = Float(j) / Float(radialSegments) * .pi * 2
                    let offset = normal * cos(angle) * tubeRadius + binormal * sin(angle) * tubeRadius
                    vertices.append(curr + offset)
                    normals.append(normalize(offset))
                }
            }

            // Build indices - connect each ring to the next, wrapping around
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
        
        private func rotateVector(_ v: SCNVector3, axis: SCNVector3, angle: Float) -> SCNVector3 {
            let c = cos(angle)
            let s = sin(angle)
            let k = axis
            
            // Rodrigues' rotation formula: v_rot = v*cos(θ) + (k×v)*sin(θ) + k*(k·v)*(1-cos(θ))
            let kCrossV = cross(k, v)
            let kDotV = dot(k, v)
            
            return SCNVector3(
                v.x * c + kCrossV.x * s + k.x * kDotV * (1 - c),
                v.y * c + kCrossV.y * s + k.y * kDotV * (1 - c),
                v.z * c + kCrossV.z * s + k.z * kDotV * (1 - c)
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
