import Foundation

// MARK: - Road grid for the city.
// Avenues run north-south (constant X). Streets run east-west (constant Z).
// Pure logic: no SceneKit types here so it can be reasoned about and reused
// by traffic, police routing and the minimap.

struct RoadPoint {
    var x: Float
    var z: Float
}

enum RoadNetwork {
    static let avenuesX: [Float] = [-120, -60, 0, 60, 120]
    static let streetsZ: [Float] = [-120, -60, 0, 60, 120]

    static func intersections() -> [RoadPoint] {
        var result: [RoadPoint] = []
        for ax in avenuesX {
            for sz in streetsZ {
                result.append(RoadPoint(x: ax, z: sz))
            }
        }
        return result
    }

    static func distance2D(ax: Float, az: Float, bx: Float, bz: Float) -> Float {
        let dx = ax - bx
        let dz = az - bz
        return sqrt(dx * dx + dz * dz)
    }

    // Distance from a point to the closest road centre line.
    static func distanceToRoad(x: Float, z: Float) -> Float {
        var best: Float = 100000
        for ax in avenuesX {
            let d = abs(x - ax)
            if d < best { best = d }
        }
        for sz in streetsZ {
            let d = abs(z - sz)
            if d < best { best = d }
        }
        return best
    }

    static func isOnRoad(x: Float, z: Float) -> Bool {
        if abs(x) > GameConfig.cityHalf + 20 { return false }
        if z > GameConfig.waterZ { return false }
        return distanceToRoad(x: x, z: z) <= GameConfig.roadHalfWidth + 1.5
    }

    // Snaps a point to the nearest road centre line (keeps the other axis).
    static func nearestRoadPoint(x: Float, z: Float) -> RoadPoint {
        var bestAvenue = avenuesX[0]
        var bestAvenueDist: Float = 100000
        for ax in avenuesX {
            let d = abs(x - ax)
            if d < bestAvenueDist { bestAvenueDist = d; bestAvenue = ax }
        }
        var bestStreet = streetsZ[0]
        var bestStreetDist: Float = 100000
        for sz in streetsZ {
            let d = abs(z - sz)
            if d < bestStreetDist { bestStreetDist = d; bestStreet = sz }
        }
        if bestAvenueDist <= bestStreetDist {
            return RoadPoint(x: bestAvenue, z: z)
        }
        return RoadPoint(x: x, z: bestStreet)
    }

    static func randomRoadPoint() -> RoadPoint {
        let useAvenue = Bool.random()
        if useAvenue {
            let ax = avenuesX[Int.random(in: 0..<avenuesX.count)]
            let z = Float.random(in: -GameConfig.cityHalf...GameConfig.cityHalf)
            return RoadPoint(x: ax, z: z)
        }
        let sz = streetsZ[Int.random(in: 0..<streetsZ.count)]
        let x = Float.random(in: -GameConfig.cityHalf...GameConfig.cityHalf)
        return RoadPoint(x: x, z: sz)
    }

    // Given a position and a heading along a road, returns the next target
    // point: drive straight to the next intersection, then (optionally) turn.
    // axisX == true means travelling along an avenue (constant X, moving in Z).
    static func nextTarget(x: Float, z: Float, axisX: Bool, direction: Float,
                           allowTurn: Bool) -> (point: RoadPoint, axisX: Bool, direction: Float) {
        if axisX {
            // Find next intersection Z ahead.
            var nextZ: Float = direction > 0 ? GameConfig.cityHalf : -GameConfig.cityHalf
            for sz in streetsZ {
                if direction > 0 && sz > z + 1 && sz < nextZ { nextZ = sz }
                if direction < 0 && sz < z - 1 && sz > nextZ { nextZ = sz }
            }
            // Extend target a bit past the intersection when not turning.
            let targetZ = allowTurn ? nextZ : nextZ + direction * 30
            return (RoadPoint(x: x, z: targetZ), axisX, direction)
        }
        var nextX: Float = direction > 0 ? GameConfig.cityHalf : -GameConfig.cityHalf
        for ax in avenuesX {
            if direction > 0 && ax > x + 1 && ax < nextX { nextX = ax }
            if direction < 0 && ax < x - 1 && ax > nextX { nextX = ax }
        }
        let targetX = allowTurn ? nextX : nextX + direction * 30
        return (RoadPoint(x: targetX, z: z), axisX, direction)
    }

    // Right-hand traffic lane offset for a car travelling along an axis.
    static func laneOffset(axisX: Bool, direction: Float) -> Float {
        // Driving on the right: offset perpendicular to travel direction.
        if axisX {
            return direction > 0 ? -2.8 : 2.8   // along Z, right side is -X when heading +Z
        }
        return direction > 0 ? 2.8 : -2.8       // along X, right side is +Z when heading +X
    }
}
