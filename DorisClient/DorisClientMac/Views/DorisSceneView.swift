import SwiftUI
import SceneKit
import AppKit

/// macOS SceneKit view for Doris animation orb
struct DorisAnimationView: View {
    let state: DorisAnimationState

    var body: some View {
        DorisSceneView(state: state)
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 12)
    }
}

struct DorisSceneView: NSViewRepresentable {
    let state: DorisAnimationState

    private let warmWhite = NSColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1.0) // FFF8F0

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.isPlaying = true

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 80)
        scene.rootNode.addChildNode(cameraNode)

        let tubeNode = context.coordinator.createInitialGeometry()
        scene.rootNode.addChildNode(tubeNode)
        context.coordinator.tubeNode = tubeNode

        context.coordinator.startDisplayTimer()
        context.coordinator.applyState(state, animated: false)

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
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
        let warmWhite: NSColor
        let geometryGenerator = DorisGeometryGenerator()

        var tubeNode: SCNNode?

        var lastIsCircle: Bool = true
        var currentProgress: Float = 1.0
        var targetProgress: Float = 1.0
        var currentPower: Float = 0.0
        var targetPower: Double = 0.0
        var isIdle: Bool = true
        var breathePhase: Float = 0.0

        var currentRotationX: Float = 0.0
        var isSpinning: Bool = false

        private var displayTimer: Timer?
        private var morphStartTime: CFTimeInterval = 0
        private var morphStartProgress: Float = 0
        private var isMorphing: Bool = false
        private let morphDuration: CFTimeInterval = 0.6

        init(warmWhite: NSColor) {
            self.warmWhite = warmWhite
        }

        deinit {
            displayTimer?.invalidate()
        }

        func createInitialGeometry() -> SCNNode {
            let points = geometryGenerator.generatePath(progress: 1.0, power: 0, breathe: 0)
            let geometry = geometryGenerator.buildTubeGeometry(path: points)

            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.eulerAngles = SCNVector3(0, 0, 0)
            return node
        }

        func startDisplayTimer() {
            // macOS uses Timer instead of CADisplayLink
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                self?.update()
            }
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

            if newIsCircle {
                isSpinning = false
            } else {
                isSpinning = true
            }
        }

        private func update() {
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

            if isSpinning {
                currentRotationX += 0.04
                if currentRotationX > .pi * 2 {
                    currentRotationX -= .pi * 2
                }
            } else {
                if abs(currentRotationX) > 0.001 {
                    if currentRotationX > .pi {
                        currentRotationX += 0.08
                        if currentRotationX >= .pi * 2 {
                            currentRotationX = 0
                        }
                    } else {
                        currentRotationX *= 0.85
                        if abs(currentRotationX) < 0.01 {
                            currentRotationX = 0
                        }
                    }
                }
            }

            tubeNode.eulerAngles = SCNVector3(currentRotationX, 0, 0)

            updateGeometry()
        }

        private func updateGeometry() {
            guard let tubeNode = tubeNode else { return }

            let breathe: CGFloat = isIdle ? CGFloat(sin(breathePhase) * 0.08) : 0
            let points = geometryGenerator.generatePath(progress: CGFloat(currentProgress), power: Double(currentPower), breathe: breathe)
            let geometry = geometryGenerator.buildTubeGeometry(path: points)

            let material = SCNMaterial()
            material.diffuse.contents = warmWhite
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]

            tubeNode.geometry = geometry
        }

        private func easeInOutCubic(_ t: Float) -> Float {
            t < 0.5 ? 4 * t * t * t : 1 + pow(2 * t - 2, 3) / 2
        }
    }
}

#Preview {
    ZStack {
        DorisColors.coral.ignoresSafeArea()
        DorisAnimationView(state: .idle)
            .frame(width: 200, height: 200)
    }
}
