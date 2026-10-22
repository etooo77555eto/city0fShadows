import Foundation

// MARK: - Wanted system (Part 2 design, simplified but state-driven)
// States: patrol -> observe -> chase -> search -> return -> patrol.
// Arrest is resolved by the engine when a unit stays close to an on-foot,
// slow player long enough.

enum PoliceState: String {
    case patrol = "Patrolling"
    case observe = "Suspicious activity reported"
    case chase = "PURSUIT"
    case search = "Searching the area"
    case returning = "Returning to patrol"
    case arrest = "Arrest in progress"
}

final class WantedSystem {
    private(set) var level: Int = 0
    private(set) var state: PoliceState = .patrol
    private(set) var lastReason: String = ""
    var lastKnown = RoadPoint(x: 0, z: 0)
    var hasVisual: Bool = false
    var timeSinceSeen: Double = 0
    var hiddenTimer: Double = 0
    var searchRadius: Float = GameConfig.searchRadiusStart
    var arrestProgress: Double = 0
    // Event flags consumed by the engine/UI (set once, engine clears them).
    var levelJustChanged: Bool = false
    var justEscapedAll: Bool = false

    func raiseTo(_ newLevel: Int, reason: String, at pos: RoadPoint) {
        let clamped = max(0, min(5, newLevel))
        if clamped > level {
            level = clamped
            levelJustChanged = true
        }
        if clamped > 0 {
            lastReason = reason
            lastKnown = pos
            timeSinceSeen = 0
            hiddenTimer = 0
            searchRadius = GameConfig.searchRadiusStart
            state = .chase
        }
    }

    func addStar(reason: String, at pos: RoadPoint) {
        raiseTo(level + 1, reason: reason, at: pos)
    }

    func clearAll() {
        level = 0
        state = .patrol
        hasVisual = false
        timeSinceSeen = 0
        hiddenTimer = 0
        arrestProgress = 0
    }

    func arrestFine() -> Int {
        return GameConfig.arrestFineBase + GameConfig.arrestFinePerStar * level
    }

    // Called every frame by the engine with fresh visibility info.
    func update(dt: Double, seesPlayer: Bool, playerPos: RoadPoint) {
        if level == 0 {
            state = .patrol
            hasVisual = false
            return
        }
        hasVisual = seesPlayer
        if seesPlayer {
            lastKnown = playerPos
            timeSinceSeen = 0
            hiddenTimer = 0
            searchRadius = GameConfig.searchRadiusStart
            if state != .arrest { state = .chase }
            return
        }
        timeSinceSeen += dt
        hiddenTimer += dt
        if state == .chase && timeSinceSeen > 2.0 {
            state = .search
        }
        if state == .search {
            searchRadius = min(GameConfig.searchRadiusMax,
                               searchRadius + Float(dt) * 3.0)
        }
        // Hidden long enough: drop one star, reset the decay clock.
        if hiddenTimer >= GameConfig.wantedDecaySeconds {
            level -= 1
            levelJustChanged = true
            hiddenTimer = 0
            timeSinceSeen = 0
            if level <= 0 {
                level = 0
                state = .returning
                justEscapedAll = true
                clearAll()
            } else {
                state = .search
            }
        }
    }

    func statusText() -> String {
        if level == 0 { return "" }
        return state.rawValue + " — " + lastReason
    }

    // Effective vision range for a ground unit, with simple hiding rules:
    // night shrinks it; a still, on-foot player far away is hard to spot.
    static func groundVisionRange(isNight: Bool, playerOnFoot: Bool,
                                  playerSpeed: Float, distance: Float) -> Float {
        var range = GameConfig.policeVisionDistance
        if isNight { range *= 0.8 }
        if playerOnFoot && playerSpeed < 0.6 && distance > 28 {
            range *= 0.62   // hiding in the shadows
        }
        return range
    }
}

// MARK: - Pursuit coordinator: decides unit counts, speeds and targets.

final class PursuitCoordinator {
    func desiredUnits(forLevel level: Int) -> Int {
        if level < 0 || level >= GameConfig.policeCountPerLevel.count { return 0 }
        return GameConfig.policeCountPerLevel[level]
    }

    func helicopterActive(forLevel level: Int) -> Bool {
        return level >= 4
    }

    func speedFactor(forLevel level: Int) -> Float {
        if level < 0 || level >= GameConfig.policeSpeedFactor.count { return 0.9 }
        return GameConfig.policeSpeedFactor[level]
    }

    func aggression(forLevel level: Int) -> Float {
        if level < 0 || level >= GameConfig.policeAggression.count { return 0.5 }
        return GameConfig.policeAggression[level]
    }

    // Steering target for one unit. In chase: the player's position snapped
    // toward the road grid (keeps police on streets). In search: rotating
    // points around the last known position so units spread out.
    func targetPoint(unitIndex: Int, state: PoliceState, wanted: WantedSystem,
                     playerPos: RoadPoint, elapsed: Double) -> RoadPoint {
        if state == .chase || state == .arrest {
            return RoadNetwork.nearestRoadPoint(x: playerPos.x, z: playerPos.z)
        }
        if state == .search {
            let base = wanted.lastKnown
            let angle = Float(elapsed * 0.25) + Float(unitIndex) * 1.7
            let r = wanted.searchRadius * (0.45 + 0.13 * Float(unitIndex % 3))
            let px = base.x + cos(angle) * r
            let pz = base.z + sin(angle) * r
            return RoadNetwork.nearestRoadPoint(x: px, z: pz)
        }
        // Patrol: slow loop through intersections near the unit's index.
        let points = RoadNetwork.intersections()
        if points.isEmpty { return RoadPoint(x: 0, z: 0) }
        let idx = (unitIndex * 5 + Int(elapsed / 14)) % points.count
        return points[idx]
    }
}
