import SceneKit
import Foundation

#if os(iOS)
typealias SCNFloat = Float
#else
typealias SCNFloat = CGFloat
#endif

/// Generates the morphing tube/circle geometry for Doris animation
class DorisGeometryGenerator {
    private let length: SCNFloat = 30.0
    private let radius: SCNFloat = 5.6
    private let segments = 200
    private let tubeRadius: SCNFloat = 1.5
    private let radialSegments = 12
    private let circleRadius: SCNFloat = 30.0

    /// Generate path points for current animation state
    /// - Parameters:
    ///   - progress: 0.0 = twisted loop, 1.0 = circle
    ///   - power: Audio power level for pulsing
    ///   - breathe: Breathing animation offset
    func generatePath(progress: SCNFloat, power: Double, breathe: SCNFloat) -> [SCNVector3] {
        var points: [SCNVector3] = []

        for i in 0...segments {
            let p = SCNFloat(i) / SCNFloat(segments)
            let loopPoint = loopCurvePoint(p: p)

            let angle = p * .pi * 2
            let pulseAmount = SCNFloat(power) * 8.0
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

    /// The OS1 twisted loop curve (figure-8 that weaves)
    func loopCurvePoint(p: SCNFloat) -> SCNVector3 {
        let pi2 = SCNFloat.pi * 2
        let x = length * sin(pi2 * p)
        let y = radius * cos(pi2 * 3 * p)

        var t = p.truncatingRemainder(dividingBy: 0.25) / 0.25
        t = p.truncatingRemainder(dividingBy: 0.25) - (2 * (1 - t) * t * (-0.0185) + t * t * 0.25)

        let quarter = Int(p * 4) % 4
        if quarter == 0 || quarter == 2 { t = -t }

        let z = radius * sin(pi2 * 2 * (p - t))
        return SCNVector3(x, y, z)
    }

    /// Build tube mesh from path
    func buildTubeGeometry(path: [SCNVector3]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []
        let count = path.count

        for i in 0..<count {
            let prev = path[(i - 1 + count) % count]
            let curr = path[i]
            let next = path[(i + 1) % count]

            let tangent = normalize(subtract(next, prev))
            var up = SCNVector3(0, 1, 0)
            if abs(dot(tangent, up)) > 0.9 { up = SCNVector3(1, 0, 0) }

            let right = normalize(cross(tangent, up))
            let forward = normalize(cross(right, tangent))

            for j in 0..<radialSegments {
                let angle = SCNFloat(j) / SCNFloat(radialSegments) * .pi * 2
                let offsetX = right.x * cos(angle) * tubeRadius + forward.x * sin(angle) * tubeRadius
                let offsetY = right.y * cos(angle) * tubeRadius + forward.y * sin(angle) * tubeRadius
                let offsetZ = right.z * cos(angle) * tubeRadius + forward.z * sin(angle) * tubeRadius
                let offset = SCNVector3(offsetX, offsetY, offsetZ)
                vertices.append(add(curr, offset))
                normals.append(normalize(offset))
            }
        }

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

    // MARK: - Vector Math (using functions instead of operators to avoid type issues)

    private func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        return len > 0 ? SCNVector3(v.x / len, v.y / len, v.z / len) : v
    }

    private func dot(_ a: SCNVector3, _ b: SCNVector3) -> SCNFloat {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private func subtract(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    private func add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
    }
}
