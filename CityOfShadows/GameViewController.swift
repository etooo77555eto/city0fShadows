import UIKit
import SceneKit

// MARK: - GameViewController — the engine.
// Owns the SceneKit scene and every runtime system: player, vehicles,
// traffic, pedestrians, police pursuit, helicopter, missions, races,
// deliveries, dynamic events, day/night + weather, camera and HUD sync.
// Gameplay state that must persist lives in GameState.save; this class
// keeps fast runtime mirrors and syncs them back at ~5 Hz.

final class GameViewController: UIViewController, SCNSceneRendererDelegate {
    let state: GameState

    private var scnView: SCNView!
    private var scene: SCNScene!
    private var cameraNode = SCNNode()
    private var sunLight = SCNNode()
    private var ambientLight = SCNNode()
    private var city: CityBuildResult!
    private var colliders: [BuildingCollider] = []

    // Player
    private var player: PlayerEntity!
    private var playerHeadingTarget: Float = 0
    private var health: Float = GameConfig.maxHealth
    private var money: Int = GameConfig.startMoney

    // Vehicles
    private var playerCar: VehicleEntity!
    private var drivenCar: VehicleEntity? = nil
    private var trafficCars: [TrafficCarEntity] = []
    private var brokenCar: TrafficCarEntity? = nil
    private var brokenTimer: Double = 0

    // Pedestrians
    private var pedestrians: [PedestrianEntity] = []

    // Police
    private let wanted = WantedSystem()
    private let coordinator = PursuitCoordinator()
    private var policeCars: [PoliceCarEntity] = []
    private var heli: HelicopterEntity!
    private var heliActive: Bool = false
    private var collisionWantedCooldown: Double = 0
    private var punchCooldown: Double = 0

    // Phase 3: police roadblocks (dynamic scene nodes + colliders, not nodes
    // in the static city: 2 police cars x 46 nodes + 3 barriers = 95).
    private var roadblockUnits: [PoliceCarEntity] = []
    private var roadblockBarrierNodes: [SCNNode] = []
    private var roadblockCenter = RoadPoint(x: 0, z: 0)
    private var roadblockColliderBase: Int = 0
    private var roadblockActive: Bool = false
    private var roadblockCooldown: Double = 0

    // Phase 3: ceremonial convoy (slow cars appended to trafficCars so the
    // existing collision / obstacle paths see them; tracked separately for
    // their dedicated movement and timed despawn).
    private var convoyCars: [TrafficCarEntity] = []
    private var convoyTimer: Double = 0

    // World clock / weather
    private var elapsed: Double = 0
    private var timeOfDay: Float = GameConfig.startHour
    private var weather: WeatherKind = .clear
    private var weatherTimer: Double = 0
    private var isNight: Bool = false
    private var rainNode: SCNNode? = nil
    private var lightPhase: Double = 0
    private var lastShadowQualityRaw: Int = -1

    // Camera
    private var camYaw: Float = Float.pi   // start behind the player, looking north
    private var camPitch: Float = 0.32
    private var camPos = SCNVector3(0, 4, 20)

    // Extra runtime state
    private var footSpeed: Float = 0
    private var talkPending: Bool = false
    private var seenTimeSkipToken: Int = 0
    private var jamCenter = RoadPoint(x: 0, z: 0)
    private var jamTimer: Double = 0
    private var stepSoundTimer: Double = 0
    private var sparkNodes: [SCNNode] = []
    private var sparkVelocities: [SCNVector3] = []
    private var sparkLife: [Double] = []

    // Missions
    private var currentMission: MissionDef? = nil
    private var stepIndex: Int = 0
    private var stepTimer: Double = 0
    private var stepStarted: Bool = false
    private var collectIndex: Int = 0
    private var lastDialogueToken: Int = 0
    private var missionNPC: HumanoidFigure? = nil
    private var objectiveMarker: SCNNode? = nil
    private var hudMissionTitle: String = ""
    private var hudObjective: String = ""

    // Side activities
    private var activeRace: StoryData.RaceDef? = nil
    private var raceCheckpoint: Int = 0
    private var raceElapsed: Double = 0
    private var deliveryActive: Bool = false
    private var deliveryTarget = RoadPoint(x: 0, z: 0)
    private var deliveryTimer: Double = 0
    private var eventTimer: Double = 60

    // Bookkeeping
    private var lastTime: TimeInterval = 0
    private var syncTimer: Double = 0
    private var saveTimer: Double = 0
    private var seenResetToken: Int = 0
    private var seenHealToken: Int = 0
    private var seenRepairToken: Int = 0
    private var lastShirtIndex: Int = -1
    private var lastActiveCarID: String = ""
    private var lastPaintIndex: Int = -1
    private var interactionPromptLocal: String = ""
    private var interactTargetKind: String = ""
    private var interactTargetID: String = ""
    private var nearestVehicle: VehicleEntity? = nil

    init(state: GameState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.state = GameState()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupWorld()
    }

    override var shouldAutorotate: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
    override var prefersStatusBarHidden: Bool { return true }

    // MARK: - Setup

    private func setupScene() {
        scene = SCNScene()
        if let skyImage = TextureLoader.image(named: "sky_gradient") {
            scene.background.contents = skyImage
        }
        // Image-based lighting: the equirect sky_env texture drives PBR
        // reflections (car paint, glass, chrome). Graceful fallback: if the
        // texture is missing the scene simply keeps its lights only.
        if let envImage = TextureLoader.image(named: "sky_env") {
            scene.lightingEnvironment.contents = envImage
            scene.lightingEnvironment.intensity = 1.2
        }
        scene.fogColor = UIColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        scene.fogStartDistance = 400
        scene.fogEndDistance = 900

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.scene = scene
        scnView.delegate = self
        scnView.isPlaying = true
        scnView.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        view.addSubview(scnView)

        let cam = SCNCamera()
        cam.zFar = 1200
        cam.fieldOfView = 62
        cam.wantsHDR = true
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 0.75
        cam.bloomBlurRadius = 8
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(10, 5, 124)
        scene.rootNode.addChildNode(cameraNode)
        camPos = cameraNode.position

        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1, green: 0.9, blue: 0.75, alpha: 1)
        sun.intensity = 800
        sunLight.light = sun
        sunLight.eulerAngles = SCNVector3(-0.9, 0.4, 0)
        scene.rootNode.addChildNode(sunLight)
        applyQualityToLights()
        lastShadowQualityRaw = state.quality().rawValue

        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(red: 0.55, green: 0.6, blue: 0.75, alpha: 1)
        amb.intensity = 320
        ambientLight.light = amb
        scene.rootNode.addChildNode(ambientLight)

        // Rain particle system (hidden unless weather is rain).
        let rain = SCNParticleSystem()
        rain.birthRate = 900
        rain.particleLifeSpan = 1.1
        rain.emissionDuration = 1.0
        rain.loops = true
        rain.particleSize = 0.06
        rain.particleColor = UIColor(red: 0.65, green: 0.75, blue: 0.9, alpha: 0.55)
        rain.particleVelocity = 26
        rain.spreadingAngle = 4
        rain.emitterShape = SCNBox(width: 60, height: 0.5, length: 60, chamferRadius: 0)
        let rNode = SCNNode()
        rNode.addParticleSystem(rain)
        rNode.eulerAngles.x = Float.pi   // point emission downward
        rNode.position = SCNVector3(0, 26, 0)
        rNode.isHidden = true
        scene.rootNode.addChildNode(rNode)
        rainNode = rNode
    }

    // Shadow quality follows the graphics quality setting: bigger shadow
    // maps on High, smaller on Low. Called at setup and again whenever the
    // setting changes at runtime (see updateEnvironment).
    private func applyQualityToLights() {
        guard let sun = sunLight.light else { return }
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowSampleCount = 16
        switch state.quality() {
        case .high:
            sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        case .medium:
            sun.shadowMapSize = CGSize(width: 1024, height: 1024)
        case .low:
            sun.shadowMapSize = CGSize(width: 512, height: 512)
        }
    }

    private func setupWorld() {
        city = CityBuilder.build()
        scene.rootNode.addChildNode(city.root)
        colliders = city.colliders

        // Objective marker (gold ring) reused for missions / races / delivery.
        let ringGeo = SCNTorus(ringRadius: 2.4, pipeRadius: 0.18)
        ringGeo.materials = [NodeFactory.material(UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1),
                                                  emissive: UIColor(red: 0.7, green: 0.5, blue: 0.05, alpha: 1))]
        let marker = SCNNode(geometry: ringGeo)
        marker.eulerAngles.x = Float.pi / 2
        marker.isHidden = true
        scene.rootNode.addChildNode(marker)
        objectiveMarker = marker

        // Mission NPC figure (reused for every talk step).
        let npc = HumanoidFigure(
            shirtColor: ShirtColors.color(at: 1),
            pantsColor: UIColor(red: 0.16, green: 0.16, blue: 0.20, alpha: 1),
            skinColor: UIColor(red: 0.72, green: 0.52, blue: 0.38, alpha: 1))
        npc.root.isHidden = true
        scene.rootNode.addChildNode(npc.root)
        missionNPC = npc

        // Player
        player = PlayerEntity(shirtIndex: state.save.activeShirtIndex)
        player.node.position = SCNVector3(10, 0, 112)
        player.heading = Float.pi
        scene.rootNode.addChildNode(player.node)
        lastShirtIndex = state.save.activeShirtIndex

        spawnPlayerCar(at: RoadPoint(x: 17, z: 106), heading: Float.pi)

        // Helicopter (hidden until wanted level 4+)
        heli = HelicopterEntity()
        heli.node.position = SCNVector3(0, 60, 0)
        heli.node.isHidden = true
        scene.rootNode.addChildNode(heli.node)

        spawnTraffic(initial: true)
        spawnPedestrians(initial: true)

        // Collision spark pool (small emissive spheres, recycled).
        let sparkGeo = SCNSphere(radius: 0.07)
        sparkGeo.materials = [NodeFactory.material(
            UIColor(red: 1, green: 0.75, blue: 0.25, alpha: 1),
            emissive: UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1))]
        var si = 0
        while si < 10 {
            let spark = SCNNode(geometry: sparkGeo)
            spark.isHidden = true
            scene.rootNode.addChildNode(spark)
            sparkNodes.append(spark)
            sparkVelocities.append(SCNVector3(0, 0, 0))
            sparkLife.append(0)
            si += 1
        }

        health = state.save.health
        if health <= 0 { health = GameConfig.maxHealth }
        money = state.save.money
        seenResetToken = state.input.resetSessionToken
        seenHealToken = state.input.healRequestToken
        activateNextMission()
    }

    private func spawnPlayerCar(at point: RoadPoint, heading: Float) {
        if let old = playerCar {
            old.node.removeFromParentNode()
        }
        let spec = VehicleCatalog.spec(forID: state.save.activeCarID)
        let tuning = state.save.tuningFor(carID: spec.id)
        let car = VehicleEntity(spec: spec, paint: PaintColors.color(at: tuning.paintIndex))
        car.setTuningCache(tuning)
        car.applyTuning(tuning)
        car.node.position = SCNVector3(point.x, 0, point.z)
        car.heading = heading
        car.node.eulerAngles.y = heading
        scene.rootNode.addChildNode(car.node)
        playerCar = car
        lastActiveCarID = spec.id
        lastPaintIndex = tuning.paintIndex
    }

    private func spawnTraffic(initial: Bool) {
        let cap = GameConfig.trafficCap[state.quality().rawValue]
        while trafficCars.count < cap {
            let car = TrafficCarEntity(paint: randomTrafficPaint())
            placeTrafficCar(car, nearPlayer: !initial)
            scene.rootNode.addChildNode(car.node)
            trafficCars.append(car)
        }
    }

    private func randomTrafficPaint() -> UIColor {
        let palette: [UIColor] = [
            UIColor(red: 0.55, green: 0.56, blue: 0.60, alpha: 1),
            UIColor(red: 0.30, green: 0.32, blue: 0.38, alpha: 1),
            UIColor(red: 0.45, green: 0.20, blue: 0.18, alpha: 1),
            UIColor(red: 0.20, green: 0.30, blue: 0.45, alpha: 1),
            UIColor(red: 0.65, green: 0.60, blue: 0.45, alpha: 1),
            UIColor(red: 0.15, green: 0.35, blue: 0.25, alpha: 1)
        ]
        return palette[Int.random(in: 0..<palette.count)]
    }

    private func placeTrafficCar(_ car: TrafficCarEntity, nearPlayer: Bool) {
        var point = RoadNetwork.randomRoadPoint()
        if nearPlayer {
            let pp = playerPosition()
            var tries = 0
            while tries < 12 {
                point = RoadNetwork.randomRoadPoint()
                let d = RoadNetwork.distance2D(ax: point.x, az: point.z, bx: pp.x, bz: pp.z)
                if d > 55 && d < 130 { break }
                tries += 1
            }
        }
        car.aiAxisX = abs(point.x - RoadNetwork.nearestRoadPoint(x: point.x, z: point.z).x) < 0.1
        // Decide axis by which road the point snapped to.
        let snapped = RoadNetwork.nearestRoadPoint(x: point.x, z: point.z)
        car.aiAxisX = snapped.x == point.x && RoadNetwork.avenuesX.contains(point.x)
        car.aiDirection = Bool.random() ? 1 : -1
        let offset = RoadNetwork.laneOffset(axisX: car.aiAxisX, direction: car.aiDirection)
        if car.aiAxisX {
            car.node.position = SCNVector3(point.x + offset, 0, point.z)
            car.heading = car.aiDirection > 0 ? 0 : Float.pi
        } else {
            car.node.position = SCNVector3(point.x, 0, point.z + offset)
            car.heading = car.aiDirection > 0 ? Float.pi / 2 : -Float.pi / 2
        }
        let next = RoadNetwork.nextTarget(x: car.node.position.x, z: car.node.position.z,
                                          axisX: car.aiAxisX, direction: car.aiDirection,
                                          allowTurn: true)
        car.aiTarget = next.point
        car.speed = 0
        car.aiSpeedLimit = Float.random(in: 9...13.5)
        car.node.eulerAngles.y = car.heading
        car.aiActive = true
    }

    private func spawnPedestrians(initial: Bool) {
        let cap = GameConfig.pedestrianCap[state.quality().rawValue]
        while pedestrians.count < cap {
            let ped = PedestrianEntity()
            placePedestrian(ped, nearPlayer: !initial)
            scene.rootNode.addChildNode(ped.node)
            pedestrians.append(ped)
        }
    }

    private func placePedestrian(_ ped: PedestrianEntity, nearPlayer: Bool) {
        var point = RoadNetwork.randomRoadPoint()
        if nearPlayer {
            let pp = playerPosition()
            var tries = 0
            while tries < 12 {
                point = RoadNetwork.randomRoadPoint()
                let d = RoadNetwork.distance2D(ax: point.x, az: point.z, bx: pp.x, bz: pp.z)
                if d > 18 && d < 70 { break }
                tries += 1
            }
        }
        // Sidewalk offset: walk beside the road, not on it.
        let snapped = RoadNetwork.nearestRoadPoint(x: point.x, z: point.z)
        let onAvenue = RoadNetwork.avenuesX.contains(snapped.x) && snapped.x == point.x
        if onAvenue {
            ped.node.position = SCNVector3(point.x + 8.4, 0, point.z)
        } else {
            ped.node.position = SCNVector3(point.x, 0, snapped.z + 8.4)
        }
        ped.target = RoadPoint(x: ped.node.position.x + Float.random(in: -30...30),
                               z: ped.node.position.z + Float.random(in: -30...30))
        ped.state = "walk"
        ped.node.isHidden = false
    }

    // MARK: - Positions

    private func playerPosition() -> RoadPoint {
        if let car = drivenCar {
            return RoadPoint(x: car.node.position.x, z: car.node.position.z)
        }
        return RoadPoint(x: player.node.position.x, z: player.node.position.z)
    }

    private func playerSpeedAbs() -> Float {
        if let car = drivenCar { return abs(car.speed) }
        return 0
    }

    // MARK: - Main loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time }
        var dt = Float(time - lastTime)
        lastTime = time
        if dt > 0.05 { dt = 0.05 }
        if dt <= 0 { return }

        if state.input.paused {
            updateCamera(dt: dt)
            return
        }
        elapsed += Double(dt)

        handleSessionTokens()
        updateEnvironment(dt: dt)
        updatePlayer(dt: dt)
        if drivenCar != nil { updateDrivenCar(dt: dt) }
        updateParkedCars(dt: dt)
        updateTraffic(dt: dt)
        updatePedestrians(dt: dt)
        updatePolice(dt: dt)
        updateRoadblock(dt: dt)
        updateConvoy(dt: dt)
        updateMissions(dt: dt)
        updateActivities(dt: dt)
        updateCamera(dt: dt)
        updateSparks(dt: dt)

        if let marker = objectiveMarker, !marker.isHidden {
            marker.eulerAngles.z += dt * 1.2
        }

        syncTimer += Double(dt)
        if syncTimer >= 0.2 {
            syncTimer = 0
            syncToState()
        }
        saveTimer += Double(dt)
        if saveTimer >= 6 {
            saveTimer = 0
            persistRuntime()
        }
        if collisionWantedCooldown > 0 { collisionWantedCooldown -= Double(dt) }
        if punchCooldown > 0 { punchCooldown -= Double(dt) }
    }

    private func handleSessionTokens() {
        if state.input.resetSessionToken != seenResetToken {
            seenResetToken = state.input.resetSessionToken
            resetSession()
        }
        if state.input.healRequestToken != seenHealToken {
            seenHealToken = state.input.healRequestToken
            health = state.save.health
        }
        if state.input.repairRequestToken != seenRepairToken {
            seenRepairToken = state.input.repairRequestToken
            playerCar.health = 100
            if let dc = drivenCar { dc.health = 100 }
        }
        // Car selection changed in a panel: respawn the parked car if free.
        if drivenCar == nil && state.save.activeCarID != lastActiveCarID {
            let pp = playerPosition()
            spawnPlayerCar(at: RoadPoint(x: pp.x + 6, z: pp.z + 4), heading: Float.pi)
        }
        // Tuning changed: re-apply paint/wheels/spec cache to the player car.
        let tuning = state.save.tuningFor(carID: state.save.activeCarID)
        if tuning.paintIndex != lastPaintIndex {
            lastPaintIndex = tuning.paintIndex
            playerCar.applyTuning(tuning)
        }
        // Neon is idempotent: buying it in the garage arms the live car
        // immediately, without waiting for a respray.
        playerCar.setNeon(tuning.neonIndex)
        playerCar.setTuningCache(tuning)
        if state.save.activeShirtIndex != lastShirtIndex {
            lastShirtIndex = state.save.activeShirtIndex
            player.setShirt(index: lastShirtIndex)
        }
    }

    private func resetSession() {
        wanted.clearAll()
        for p in policeCars { p.node.removeFromParentNode() }
        policeCars.removeAll()
        heliActive = false
        heli.node.isHidden = true
        drivenCar = nil
        player.node.isHidden = false
        player.node.position = SCNVector3(10, 0, 112)
        player.heading = Float.pi
        // Collision spark pool (small emissive spheres, recycled).
        let sparkGeo = SCNSphere(radius: 0.07)
        sparkGeo.materials = [NodeFactory.material(
            UIColor(red: 1, green: 0.75, blue: 0.25, alpha: 1),
            emissive: UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1))]
        var si = 0
        while si < 10 {
            let spark = SCNNode(geometry: sparkGeo)
            spark.isHidden = true
            scene.rootNode.addChildNode(spark)
            sparkNodes.append(spark)
            sparkVelocities.append(SCNVector3(0, 0, 0))
            sparkLife.append(0)
            si += 1
        }

        health = state.save.health
        if health <= 0 { health = GameConfig.maxHealth }
        money = state.save.money
        spawnPlayerCar(at: RoadPoint(x: 17, z: 106), heading: Float.pi)
        activeRace = nil
        deliveryActive = false
        currentMission = nil
        stepIndex = 0
        stepStarted = false
        activateNextMission()
        objectiveMarker?.isHidden = true
        clearRoadblock()
        for car in convoyCars {
            if let idx = trafficCars.firstIndex(where: { $0 === car }) {
                trafficCars.remove(at: idx)
            }
            car.node.removeFromParentNode()
        }
        convoyCars.removeAll()
        convoyTimer = 0
    }

    private func persistRuntime() {
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.state.save.money = s.money
            s.state.save.health = s.health
            s.state.save.wantedLevel = s.wanted.level
            s.state.moneyDisplay = s.money
            s.state.healthDisplay = s.health
            s.state.persist()
        }
    }

    // MARK: - Player on foot

    private func updatePlayer(dt: Float) {
        if drivenCar != nil {
            // Keep the (hidden) player node glued to the car so exit works.
            return
        }
        let input = state.input
        var moveX: Float = 0
        var moveZ: Float = 0
        let joyX = input.joyX
        let joyY = input.joyY
        if abs(joyX) > 0.08 || abs(joyY) > 0.08 {
            // Move relative to the camera yaw.
            let fwdX = sin(camYaw)
            let fwdZ = cos(camYaw)
            let rightX = -cos(camYaw)
            let rightZ = sin(camYaw)
            moveX = fwdX * joyY + rightX * joyX
            moveZ = fwdZ * joyY + rightZ * joyX
            let len = sqrt(moveX * moveX + moveZ * moveZ)
            if len > 1 { moveX /= len; moveZ /= len }
        }
        let running = input.runHeld
        let speed = running ? GameConfig.runSpeed : GameConfig.walkSpeed
        var pos = player.node.position
        footSpeed = (moveX != 0 || moveZ != 0) ? speed : 0
        if moveX != 0 || moveZ != 0 {
            playerHeadingTarget = atan2(moveX, moveZ)
            pos.x += moveX * speed * dt
            pos.z += moveZ * speed * dt
            player.figure.animateWalk(dt: dt, speedFactor: running ? 1.0 : 0.55)
        } else {
            player.figure.animateWalk(dt: dt, speedFactor: 0)
        }
        // Smooth heading.
        let dh = shortestAngle(from: player.heading, to: playerHeadingTarget)
        player.heading += dh * min(1, dt * 10)
        player.node.eulerAngles.y = player.heading

        // Jump & gravity.
        if input.jumpTap && player.isGrounded {
            player.velocityY = GameConfig.jumpVelocity
            player.isGrounded = false
        }
        input.jumpTap = false
        if !player.isGrounded {
            player.velocityY += GameConfig.gravity * dt
            pos.y += player.velocityY * dt
            if pos.y <= 0 {
                pos.y = 0
                player.velocityY = 0
                player.isGrounded = true
            }
        }

        // World bounds & water.
        pos.x = max(-162, min(162, pos.x))
        pos.z = max(-162, min(GameConfig.waterZ - 2, pos.z))

        // Building collisions.
        for c in colliders {
            let res = c.pushOut(x: pos.x, z: pos.z, r: GameConfig.playerRadius)
            if res.hit { pos.x = res.x; pos.z = res.z }
        }
        player.node.position = pos

        // Footstep sounds while moving on the ground.
        if (moveX != 0 || moveZ != 0) && player.isGrounded {
            stepSoundTimer -= Double(dt)
            if stepSoundTimer <= 0 {
                stepSoundTimer = running ? 0.34 : 0.47
                SoundManager.shared.step()
            }
        }

        // Punch.
        if input.punchTap {
            input.punchTap = false
            doPunch()
        }

        // Interaction scan (foot).
        scanInteractions()
        if input.interactTap {
            input.interactTap = false
            handleInteract()
        }
    }

    private func doPunch() {
        if punchCooldown > 0 { return }
        punchCooldown = 0.5
        player.figure.punchPose()
        let pp = playerPosition()
        let fwdX = sin(player.heading)
        let fwdZ = cos(player.heading)
        for ped in pedestrians {
            let dx = ped.node.position.x - pp.x
            let dz = ped.node.position.z - pp.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 1.9 {
                let dot = (dx * fwdX + dz * fwdZ) / max(0.01, dist)
                if dot > 0.3 {
                    SoundManager.shared.punch()
                    ped.state = "down"
                    ped.stateTimer = 3.5
                    ped.node.eulerAngles.x = -Float.pi / 2
                    if collisionWantedCooldown <= 0 {
                        collisionWantedCooldown = 5
                        wanted.raiseTo(max(wanted.level, 1), reason: "Assault witnessed",
                                       at: pp)
                        pushToast("Wanted: assault")
                    }
                    return
                }
            }
        }
    }

    // MARK: - Interactions

    private func scanInteractions() {
        interactionPromptLocal = ""
        interactTargetKind = ""
        interactTargetID = ""
        nearestVehicle = nil
        let pp = playerPosition()

        if drivenCar != nil {
            interactionPromptLocal = "Exit vehicle"
            interactTargetKind = "exitCar"
            return
        }
        // Nearest enterable vehicle.
        var bestDist: Float = 3.4
        if playerCar != nil {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: playerCar.node.position.x,
                                           bz: playerCar.node.position.z)
            if d < bestDist { bestDist = d; nearestVehicle = playerCar }
        }
        for car in trafficCars {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: car.node.position.x,
                                           bz: car.node.position.z)
            if d < bestDist { bestDist = d; nearestVehicle = car }
        }
        if let v = nearestVehicle {
            interactionPromptLocal = "Enter " + v.spec.name
            interactTargetKind = "enterCar"
            return
        }
        // Mission talk target.
        if let mission = currentMission, stepIndex < mission.steps.count {
            let step = mission.steps[stepIndex]
            if step.kind == .talkTo {
                let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: step.x, bz: step.z)
                if d < 4.5 {
                    let name = Characters.def(forID: step.characterID).name
                    interactionPromptLocal = "Talk to " + name
                    interactTargetKind = "talk"
                    return
                }
            }
        }
        // City interactables.
        for point in city.interactables {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: point.x, bz: point.z)
            if d < 4.2 {
                interactionPromptLocal = point.label
                interactTargetKind = point.kind.rawValue
                interactTargetID = point.id
                return
            }
        }
    }

    private func handleInteract() {
        if interactTargetKind == "exitCar" {
            exitCar()
            return
        }
        if interactTargetKind == "enterCar", let v = nearestVehicle {
            enterCar(v)
            return
        }
        if interactTargetKind == "talk" {
            startMissionDialogue()
            return
        }
        if interactTargetKind == "race" {
            if let race = StoryData.race(forID: interactTargetID) {
                startRace(race)
            }
            return
        }
        if interactTargetKind == "delivery" {
            startDelivery()
            return
        }
        // Panels.
        var panel: OpenPanel = .none
        if interactTargetKind == "shop" { panel = .shop }
        if interactTargetKind == "dealership" { panel = .dealership }
        if interactTargetKind == "garage" { panel = .garage }
        if interactTargetKind == "clothing" { panel = .clothing }
        if interactTargetKind == "property" { panel = .property }
        if panel != .none {
            let p = panel
            let pid = interactTargetID
            DispatchQueue.main.async { [weak self] in
                guard let s = self else { return }
                if p == .property { s.state.panelPropertyID = pid }
                s.state.openPanel = p
                s.state.input.paused = true
            }
        }
    }

    private func enterCar(_ car: VehicleEntity) {
        drivenCar = car
        player.node.isHidden = true
        if let traffic = car as? TrafficCarEntity {
            // Taking someone else's car is a crime if witnessed.
            let pp = playerPosition()
            wanted.raiseTo(max(wanted.level, 1), reason: "Vehicle theft", at: pp)
            pushToast("You took the " + traffic.spec.name)
            if let idx = trafficCars.firstIndex(where: { $0 === traffic }) {
                trafficCars.remove(at: idx)
            }
        }
        if car === playerCar {
            pushToast(car.spec.name + " — your car")
        }
        scanInteractions()
    }

    private func exitCar() {
        guard let car = drivenCar else { return }
        drivenCar = nil
        // Phase 3: never leave a car floating — reset any in-progress jump.
        car.airborne = false
        car.verticalSpeed = 0
        car.airTime = 0
        car.node.position.y = 0
        let rightX = -cos(car.heading)
        let rightZ = sin(car.heading)
        var px = car.node.position.x + rightX * 2.3
        var pz = car.node.position.z + rightZ * 2.3
        for c in colliders {
            let res = c.pushOut(x: px, z: pz, r: GameConfig.playerRadius)
            if res.hit { px = res.x; pz = res.z }
        }
        player.node.position = SCNVector3(px, 0, pz)
        player.node.isHidden = false
        player.heading = car.heading
        // A stolen car left behind becomes a parked traffic car again.
        if car !== playerCar, let traffic = car as? TrafficCarEntity {
            traffic.aiActive = false
            traffic.speed = 0
            trafficCars.append(traffic)
        }
    }

    // MARK: - Driven car physics (arcade, velocity-vector model)

    private func updateDrivenCar(dt: Float) {
        guard let car = drivenCar else { return }
        let input = state.input
        let top = car.effectiveTopSpeed()
        let accel = car.effectiveAcceleration()
        let brake = car.effectiveBraking()
        let turning = car.effectiveTurning()

        // Velocity is kept decomposed: forward (vf) + lateral slide (vr).
        var pos = car.node.position
        var vf = car.speed
        var vr = car.lateralSpeed

        // Throttle / brake / reverse.
        if input.throttleHeld {
            vf += accel * dt * (1 - max(0, vf) / (top * 1.15))
        }
        if input.brakeHeld {
            if vf > 0.6 {
                vf -= brake * dt
            } else {
                vf -= accel * 0.55 * dt
                let minReverse = -top * 0.32
                if vf < minReverse { vf = minReverse }
            }
        }
        // Drag & rolling resistance.
        vf -= vf * 0.32 * dt
        vf -= vf * abs(vf) * 0.0022 * dt
        if !input.throttleHeld && !input.brakeHeld {
            if abs(vf) < 0.12 { vf = 0 }
        }
        // Lateral grip (handbrake melts it -> drift).
        let grip = input.handbrakeHeld ? 1.4 : (4.0 + 6.0 * car.spec.stability)
        vr -= vr * min(0.95, grip * dt)
        if input.handbrakeHeld {
            vf -= vf * 0.85 * dt
        }

        // Steering.
        var steerInput = input.steer
        if abs(input.joyX) > 0.1 { steerInput = input.joyX }
        car.steerVisual += (steerInput - car.steerVisual) * min(1, dt * 8)
        let speedFactor = max(-1, min(1, vf / 9))
        let driftBoost: Float = input.handbrakeHeld ? 1.35 : 1.0
        car.heading += steerInput * turning * speedFactor * driftBoost * dt
        if vf < 0 { /* heading formula already flips via speedFactor sign */ }

        // Recompute velocity from components with the new heading.
        let nfX = sin(car.heading)
        let nfZ = cos(car.heading)
        let nrX = -cos(car.heading)
        let nrZ = sin(car.heading)
        let velX = nfX * vf + nrX * vr
        let velZ = nfZ * vf + nrZ * vr
        pos.x += velX * dt
        pos.z += velZ * dt

        // Bounds & coast.
        pos.x = max(-162, min(162, pos.x))
        if pos.z > GameConfig.coastZ + 4 {
            pos.z = GameConfig.coastZ + 4
            vf *= 0.6
        }
        pos.z = max(-162, pos.z)

        // Phase 3: jump ramps. Launch only from the ground; while airborne
        // the car free-falls and all ground collisions are skipped.
        if !car.airborne {
            tryRampLaunch(car: car)
        }
        if car.airborne {
            car.airTime += Double(dt)
            car.verticalSpeed += GameConfig.gravity * dt
            pos.y += car.verticalSpeed * dt
            if pos.y <= 0 {
                landFromJump(car: car, pos: &pos)
            }
        } else {
            pos.y = 0
        }

        // Building collisions: push out + damage on hard hits (ground only).
        let impactSpeed = abs(vf)
        if !car.airborne {
            for c in colliders {
                let res = c.pushOut(x: pos.x, z: pos.z, r: 1.35)
                if res.hit {
                    pos.x = res.x
                    pos.z = res.z
                    if impactSpeed > 7 {
                        car.health -= (impactSpeed - 7) * 1.6
                        onHardCollision(at: RoadPoint(x: pos.x, z: pos.z))
                        vf *= 0.3
                        vr = 0
                    } else {
                        vf *= 0.55
                    }
                }
            }
        }
        car.node.position = pos
        car.node.eulerAngles.y = car.heading
        car.speed = vf
        car.lateralSpeed = vr
        car.updateWheels(dt: dt)

        // Collisions with other cars / pedestrians (ground only).
        if !car.airborne {
            collideCarWithWorld(car: car, dt: dt)
        }

        // Keep hidden player node at the car.
        player.node.position = SCNVector3(pos.x, 0, pos.z)

        // Interaction scan while driving = exit prompt.
        scanInteractions()
        if input.interactTap {
            input.interactTap = false
            handleInteract()
        }
    }

    private func onHardCollision(at pos: RoadPoint) {
        spawnSparks(x: pos.x, z: pos.z)
        if collisionWantedCooldown > 0 { return }
        collisionWantedCooldown = 4
        if wanted.level > 0 || nearestPoliceDistance(to: pos) < 60 {
            wanted.addStar(reason: "Reckless collision", at: pos)
            pushToast("Wanted: collision")
        }
        if health > 0 {
            health = max(1, health - 2)
        }
    }

    // MARK: - Phase 3: jump ramps (launch & landing)

    private func tryRampLaunch(car: VehicleEntity) {
        if abs(car.speed) < GameConfig.rampTriggerSpeed { return }
        let px = car.node.position.x
        let pz = car.node.position.z
        for ramp in StoryData.jumpRamps {
            let d = RoadNetwork.distance2D(ax: px, az: pz, bx: ramp.x, bz: ramp.z)
            if d < 3.0 {
                car.airborne = true
                car.airTime = 0
                car.verticalSpeed = abs(car.speed) * GameConfig.rampLaunchFactor
                pushToast("Jump! Air time earns cash.")
                return
            }
        }
    }

    private func landFromJump(car: VehicleEntity, pos: inout SCNVector3) {
        car.airborne = false
        car.verticalSpeed = 0
        pos.y = 0
        if car.airTime >= GameConfig.rampMinAirTime {
            let reward = Int(car.airTime * Double(GameConfig.rampRewardPerAirSecond))
            money += reward
            pushToast("Air time +" + String(reward) + "$")
            SoundManager.shared.cash()
        }
        persistRuntime()
    }

    private func collideCarWithWorld(car: VehicleEntity, dt: Float) {
        let pp = RoadPoint(x: car.node.position.x, z: car.node.position.z)
        // Traffic cars.
        for other in trafficCars {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: other.node.position.x,
                                           bz: other.node.position.z)
            if d < 3.1 && d > 0.01 {
                let pushX = (pp.x - other.node.position.x) / d
                let pushZ = (pp.z - other.node.position.z) / d
                car.node.position.x += pushX * (3.1 - d) * 0.6
                car.node.position.z += pushZ * (3.1 - d) * 0.6
                other.node.position.x -= pushX * (3.1 - d) * 0.4
                other.node.position.z -= pushZ * (3.1 - d) * 0.4
                if abs(car.speed) > 6 {
                    other.health -= 8
                    car.speed *= 0.55
                    onHardCollision(at: pp)
                }
            }
        }
        // Pedestrians.
        for ped in pedestrians {
            if ped.state == "down" { continue }
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: ped.node.position.x,
                                           bz: ped.node.position.z)
            if d < 1.7 {
                ped.state = "down"
                ped.stateTimer = 4
                ped.node.eulerAngles.x = -Float.pi / 2
                if abs(car.speed) > 3 {
                    if collisionWantedCooldown <= 0 {
                        collisionWantedCooldown = 5
                        wanted.raiseTo(max(wanted.level, 2), reason: "Hit and run", at: pp)
                        pushToast("Wanted: hit and run")
                    }
                    health = max(1, health - 1)
                }
            }
        }
    }

    private func updateParkedCars(dt: Float) {
        // The player's own parked car just needs wheel/heading housekeeping.
        if drivenCar == nil {
            playerCar.node.eulerAngles.y = playerCar.heading
        }
    }

    // MARK: - Traffic AI

    private func updateTraffic(dt: Float) {
        let quality = state.quality()
        let cull = GameConfig.cullDistance[quality.rawValue]
        let pp = playerPosition()
        if brokenTimer > 0 {
            brokenTimer -= Double(dt)
            if brokenTimer <= 0 { brokenCar = nil }
        }
        for car in trafficCars {
            if !car.aiActive {
                car.speed = 0
                continue
            }
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: car.node.position.x,
                                           bz: car.node.position.z)
            if d > cull + 70 {
                placeTrafficCar(car, nearPlayer: true)
                continue
            }
            car.node.isHidden = d > cull

            car.aiDecisionTimer -= Double(dt)
            if car.aiDecisionTimer <= 0 {
                car.aiDecisionTimer = 0.3
                let distT = RoadNetwork.distance2D(ax: car.node.position.x,
                                                   az: car.node.position.z,
                                                   bx: car.aiTarget.x, bz: car.aiTarget.z)
                if distT < 6 {
                    if Float.random(in: 0...1) < 0.35 {
                        car.aiAxisX = !car.aiAxisX
                        car.aiDirection = Bool.random() ? 1 : -1
                        let snapped = RoadNetwork.nearestRoadPoint(x: car.node.position.x,
                                                                   z: car.node.position.z)
                        let off = RoadNetwork.laneOffset(axisX: car.aiAxisX,
                                                         direction: car.aiDirection)
                        if car.aiAxisX {
                            car.node.position.x = snapped.x + off
                        } else {
                            car.node.position.z = snapped.z + off
                        }
                    }
                    let next = RoadNetwork.nextTarget(x: car.node.position.x,
                                                      z: car.node.position.z,
                                                      axisX: car.aiAxisX,
                                                      direction: car.aiDirection,
                                                      allowTurn: true)
                    car.aiTarget = next.point
                }
                // Stuck detection: wants to move but cannot.
                if car.aiSpeedLimit > 3 && abs(car.speed) < 0.4 {
                    car.aiStuckTimer += 0.3
                    if car.aiStuckTimer > 4 {
                        car.aiStuckTimer = 0
                        placeTrafficCar(car, nearPlayer: true)
                        continue
                    }
                } else {
                    car.aiStuckTimer = 0
                }
            }

            var desired = car.aiSpeedLimit
            if isJamNear(x: car.node.position.x, z: car.node.position.z) {
                desired = min(desired, 3.5)
            }
            if car === brokenCar { desired = 0 }
            if obstacleAhead(of: car) { desired = 0 }
            if redLightAhead(car: car) { desired = 0 }

            if car.speed < desired {
                car.speed = min(desired, car.speed + 7 * dt)
            } else {
                car.speed = max(desired, car.speed - 16 * dt)
            }
            // Steer toward target.
            let dx = car.aiTarget.x - car.node.position.x
            let dz = car.aiTarget.z - car.node.position.z
            if abs(car.speed) > 0.2 {
                let desiredHeading = atan2(dx, dz)
                let dh = shortestAngle(from: car.heading, to: desiredHeading)
                let maxTurn = 1.7 * dt * (car.speed >= 0 ? 1 : -1)
                car.heading += max(-abs(maxTurn), min(abs(maxTurn), dh))
            }
            var pos = car.node.position
            pos.x += sin(car.heading) * car.speed * dt
            pos.z += cos(car.heading) * car.speed * dt
            pos.y = 0
            if pos.z > GameConfig.coastZ + 2 { pos.z = GameConfig.coastZ + 2 }
            for c in colliders {
                let res = c.pushOut(x: pos.x, z: pos.z, r: 1.3)
                if res.hit { pos.x = res.x; pos.z = res.z }
            }
            car.node.position = pos
            car.node.eulerAngles.y = car.heading
            car.setHeadlights(on: isNight)
            car.setUnderglowNight(on: isNight)
            car.updateWheels(dt: dt)
        }
        spawnTraffic(initial: false)
    }

    private func obstacleAhead(of car: VehicleEntity) -> Bool {
        let fwdX = sin(car.heading)
        let fwdZ = cos(car.heading)
        let cx = car.node.position.x
        let cz = car.node.position.z
        func blocks(_ ox: Float, _ oz: Float) -> Bool {
            let dx = ox - cx
            let dz = oz - cz
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 0.5 || dist > 8 { return false }
            let dot = (dx * fwdX + dz * fwdZ) / dist
            return dot > 0.72
        }
        if let dc = drivenCar {
            if blocks(dc.node.position.x, dc.node.position.z) { return true }
        }
        if drivenCar == nil {
            if blocks(player.node.position.x, player.node.position.z) { return true }
        }
        for other in trafficCars {
            if other === car { continue }
            if blocks(other.node.position.x, other.node.position.z) { return true }
        }
        for unit in policeCars {
            if blocks(unit.node.position.x, unit.node.position.z) { return true }
        }
        return false
    }

    private func redLightAhead(car: VehicleEntity) -> Bool {
        // Global phase: avenues run during the first half of the cycle.
        let phase = lightPhase.truncatingRemainder(dividingBy: 16)
        let avenuesGreen = phase < 8
        if car.aiAxisX && avenuesGreen { return false }
        if !car.aiAxisX && !avenuesGreen { return false }
        // Red for this axis: stop if an intersection is just ahead.
        let fwdX = sin(car.heading)
        let fwdZ = cos(car.heading)
        for inter in RoadNetwork.intersections() {
            let dx = inter.x - car.node.position.x
            let dz = inter.z - car.node.position.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist > 3 && dist < 10 {
                let dot = (dx * fwdX + dz * fwdZ) / dist
                if dot > 0.8 { return true }
            }
        }
        return false
    }

    private func isJamNear(x: Float, z: Float) -> Bool {
        if jamTimer <= 0 { return false }
        return RoadNetwork.distance2D(ax: x, az: z, bx: jamCenter.x, bz: jamCenter.z) < 26
    }

    // MARK: - Pedestrians

    private func updatePedestrians(dt: Float) {
        let cull = GameConfig.cullDistance[state.quality().rawValue]
        let pp = playerPosition()
        for ped in pedestrians {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: ped.node.position.x,
                                           bz: ped.node.position.z)
            if d > cull + 40 {
                placePedestrian(ped, nearPlayer: true)
                continue
            }
            ped.node.isHidden = d > cull

            if ped.state == "down" {
                ped.stateTimer -= Double(dt)
                if ped.stateTimer <= 0 {
                    ped.node.eulerAngles.x = 0
                    ped.state = "flee"
                    ped.stateTimer = 2.2
                }
                continue
            }

            ped.decisionTimer -= Double(dt)
            if ped.decisionTimer <= 0 {
                ped.decisionTimer = 0.25
                decidePedestrian(ped, playerPos: pp)
            }

            var moveSpeed: Float = 0
            var tx = ped.target.x
            var tz = ped.target.z
            if ped.state == "flee" {
                ped.stateTimer -= Double(dt)
                let awayX = ped.node.position.x - pp.x
                let awayZ = ped.node.position.z - pp.z
                tx = ped.node.position.x + awayX
                tz = ped.node.position.z + awayZ
                moveSpeed = 3.3
                if ped.stateTimer <= 0 { ped.state = "walk" }
            } else if ped.state == "wait" {
                ped.stateTimer -= Double(dt)
                if ped.stateTimer <= 0 { ped.state = "walk" }
                moveSpeed = 0
            } else {
                moveSpeed = ped.speed
                let distT = RoadNetwork.distance2D(ax: ped.node.position.x,
                                                   az: ped.node.position.z, bx: tx, bz: tz)
                if distT < 1.2 {
                    pickPedestrianTarget(ped)
                }
            }
            if moveSpeed > 0 {
                // Simple car avoidance: freeze if a car is right in front.
                if pedBlockedByCar(ped) && ped.state != "flee" {
                    moveSpeed = 0
                }
            }
            if moveSpeed > 0 {
                let dx = tx - ped.node.position.x
                let dz = tz - ped.node.position.z
                let len = sqrt(dx * dx + dz * dz)
                if len > 0.05 {
                    let desiredHeading = atan2(dx, dz)
                    let dh = shortestAngle(from: ped.heading, to: desiredHeading)
                    ped.heading += dh * min(1, dt * 7)
                    ped.node.position.x += sin(ped.heading) * moveSpeed * dt
                    ped.node.position.z += cos(ped.heading) * moveSpeed * dt
                    ped.node.eulerAngles.y = ped.heading
                }
            }
            ped.node.position.z = min(ped.node.position.z, GameConfig.coastZ + 3)
            for c in colliders {
                let res = c.pushOut(x: ped.node.position.x, z: ped.node.position.z, r: 0.4)
                if res.hit {
                    ped.node.position.x = res.x
                    ped.node.position.z = res.z
                }
            }
            ped.figure.animateWalk(dt: dt, speedFactor: moveSpeed / 3)
        }
        spawnPedestrians(initial: false)
    }

    private func decidePedestrian(_ ped: PedestrianEntity, playerPos pp: RoadPoint) {
        // Flee from fast cars and active pursuits.
        if let dc = drivenCar, abs(dc.speed) > 8 {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: ped.node.position.x, bz: ped.node.position.z)
            if d < 8 && ped.state == "walk" {
                ped.state = "flee"
                ped.stateTimer = 2.0
                return
            }
        }
        if wanted.level > 0 && wanted.state == .chase {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: ped.node.position.x, bz: ped.node.position.z)
            if d < 13 && ped.state == "walk" {
                ped.state = "flee"
                ped.stateTimer = 2.4
                return
            }
        }
        // Occasionally wait (at crossings / shop fronts).
        if ped.state == "walk" && Float.random(in: 0...1) < 0.05 {
            ped.state = "wait"
            ped.stateTimer = Double(Float.random(in: 1...2.5))
        }
    }

    private func pickPedestrianTarget(_ ped: PedestrianEntity) {
        // Walk along the block: random nearby point, biased to stay off roads.
        var nx = ped.node.position.x + Float.random(in: -38...38)
        var nz = ped.node.position.z + Float.random(in: -38...38)
        let snapped = RoadNetwork.nearestRoadPoint(x: nx, z: nz)
        if RoadNetwork.avenuesX.contains(snapped.x) {
            nx = snapped.x + (nx >= snapped.x ? 8.4 : -8.4)
        } else {
            nz = snapped.z + (nz >= snapped.z ? 8.4 : -8.4)
        }
        nx = max(-155, min(155, nx))
        nz = max(-155, min(GameConfig.coastZ + 2, nz))
        ped.target = RoadPoint(x: nx, z: nz)
    }

    private func pedBlockedByCar(_ ped: PedestrianEntity) -> Bool {
        let fwdX = sin(ped.heading)
        let fwdZ = cos(ped.heading)
        func near(_ ox: Float, _ oz: Float) -> Bool {
            let dx = ox - ped.node.position.x
            let dz = oz - ped.node.position.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 0.4 || dist > 2.6 { return false }
            return (dx * fwdX + dz * fwdZ) / dist > 0.5
        }
        for car in trafficCars {
            if near(car.node.position.x, car.node.position.z) { return true }
        }
        if let dc = drivenCar {
            if near(dc.node.position.x, dc.node.position.z) { return true }
        }
        return false
    }

    // MARK: - Police & helicopter

    private func nearestPoliceDistance(to pos: RoadPoint) -> Float {
        var best: Float = 100000
        for unit in policeCars {
            let d = RoadNetwork.distance2D(ax: pos.x, az: pos.z,
                                           bx: unit.node.position.x,
                                           bz: unit.node.position.z)
            if d < best { best = d }
        }
        return best
    }

    private func updatePolice(dt: Float) {
        let pp = playerPosition()
        let pSpeed = drivenCar != nil ? abs(drivenCar!.speed) : footSpeed

        // Speeding past a patrol at zero wanted raises attention.
        if wanted.level == 0 && drivenCar != nil && abs(drivenCar!.speed) > 30 {
            for unit in policeCars {
                let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                               bx: unit.node.position.x,
                                               bz: unit.node.position.z)
                if d < 30 {
                    wanted.raiseTo(1, reason: "Speeding", at: pp)
                    pushToast("Wanted: speeding")
                    break
                }
            }
        }

        // Vision: any ground unit close enough, or the helicopter.
        var sees = false
        if wanted.level > 0 {
            let range = WantedSystem.groundVisionRange(isNight: isNight,
                                                       playerOnFoot: drivenCar == nil,
                                                       playerSpeed: pSpeed, distance: 0)
            for unit in policeCars {
                let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                               bx: unit.node.position.x,
                                               bz: unit.node.position.z)
                let r = WantedSystem.groundVisionRange(isNight: isNight,
                                                         playerOnFoot: drivenCar == nil,
                                                         playerSpeed: pSpeed, distance: d)
                _ = range
                if d < r { sees = true; break }
            }
            if !sees && heliActive {
                let hd = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                                bx: heli.node.position.x,
                                                bz: heli.node.position.z)
                if hd < GameConfig.helicopterVisionDistance { sees = true }
            }
        }
        // Hiding in shadow (off-road, slow) decays heat faster.
        let hiding = !RoadNetwork.isOnRoad(x: pp.x, z: pp.z) && pSpeed < 1.2
        let dtScaled = Double(dt) * (hiding ? 1.6 : 1.0)
        wanted.update(dt: dtScaled, seesPlayer: sees, playerPos: pp)

        if wanted.levelJustChanged {
            wanted.levelJustChanged = false
            if wanted.level > 0 {
                pushToast("Wanted level " + String(wanted.level) + " — " + wanted.lastReason)
            }
        }
        if wanted.justEscapedAll {
            wanted.justEscapedAll = false
            pushToast("You lost the police.")
            unlockAchievementFromEngine("escape")
        }

        // Spawn / despawn units to match the wanted level. At level 0 a
        // single patrol car still cruises the city.
        let desired = wanted.level == 0 ? 1 : coordinator.desiredUnits(forLevel: wanted.level)
        while policeCars.count < desired {
            spawnPoliceUnit(near: pp)
        }
        while policeCars.count > desired {
            var farIdx = 0
            var farDist: Float = -1
            for (i, unit) in policeCars.enumerated() {
                let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                               bx: unit.node.position.x,
                                               bz: unit.node.position.z)
                if d > farDist { farDist = d; farIdx = i }
            }
            policeCars[farIdx].node.removeFromParentNode()
            policeCars.remove(at: farIdx)
        }

        // Drive units.
        let pursuitState: PoliceState = wanted.level == 0 ? .patrol : wanted.state
        for (i, unit) in policeCars.enumerated() {
            let target = coordinator.targetPoint(unitIndex: i, state: pursuitState,
                                                 wanted: wanted, playerPos: pp,
                                                 elapsed: elapsed)
            var speedLimit: Float = 10.5
            if pursuitState == .chase || pursuitState == .arrest {
                speedLimit = VehicleCatalog.police.topSpeed * coordinator.speedFactor(forLevel: wanted.level)
            } else if pursuitState == .search {
                speedLimit = 13.5
            }
            // Separation from other units.
            var tx = target.x
            var tz = target.z
            for (j, other) in policeCars.enumerated() {
                if i == j { continue }
                let d = RoadNetwork.distance2D(ax: unit.node.position.x,
                                               az: unit.node.position.z,
                                               bx: other.node.position.x,
                                               bz: other.node.position.z)
                if d < 8 && d > 0.01 {
                    tx += (unit.node.position.x - other.node.position.x) / d * 6
                    tz += (unit.node.position.z - other.node.position.z) / d * 6
                }
            }
            // Obstacles: slow for traffic, never for the player in a chase.
            var desired = speedLimit
            if obstacleAhead(of: unit) && pursuitState != .chase {
                desired = 0
            }
            let distToPlayer = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                                      bx: unit.node.position.x,
                                                      bz: unit.node.position.z)
            if pursuitState == .chase && distToPlayer < 4 {
                desired = min(desired, abs(drivenCar?.speed ?? 0) + 2)
            }
            if unit.speed < desired {
                unit.speed = min(desired, unit.speed + 13 * dt)
            } else {
                unit.speed = max(desired, unit.speed - 20 * dt)
            }
            let dx = tx - unit.node.position.x
            let dz = tz - unit.node.position.z
            if abs(unit.speed) > 0.2 {
                let desiredHeading = atan2(dx, dz)
                let dh = shortestAngle(from: unit.heading, to: desiredHeading)
                let maxTurn = 2.0 * dt
                unit.heading += max(-maxTurn, min(maxTurn, dh))
            }
            var pos = unit.node.position
            pos.x += sin(unit.heading) * unit.speed * dt
            pos.z += cos(unit.heading) * unit.speed * dt
            pos.y = 0
            pos.x = max(-162, min(162, pos.x))
            pos.z = max(-162, min(GameConfig.coastZ + 2, pos.z))
            for c in colliders {
                let res = c.pushOut(x: pos.x, z: pos.z, r: 1.35)
                if res.hit {
                    pos.x = res.x
                    pos.z = res.z
                    unit.speed *= 0.5
                }
            }
            unit.node.position = pos
            unit.node.eulerAngles.y = unit.heading
            unit.setHeadlights(on: isNight)
            unit.updateSiren(dt: Double(dt), active: wanted.level > 0)
            unit.updateWheels(dt: dt)

            // Ramming the player's car in a chase.
            if pursuitState == .chase, let dc = drivenCar {
                let d = RoadNetwork.distance2D(ax: pos.x, az: pos.z,
                                               bx: dc.node.position.x,
                                               bz: dc.node.position.z)
                if d < 3.0 {
                    dc.health -= 14 * dt
                    dc.speed *= (1 - 0.6 * dt)
                    health = max(1, health - 2.5 * dt)
                }
            }
        }

        // Arrest: on foot, wanted, unit close, player slow.
        if drivenCar == nil && wanted.level > 0 {
            let nd = nearestPoliceDistance(to: pp)
            if nd < GameConfig.arrestDistance && footSpeed < 1.0 {
                wanted.arrestProgress += Double(dt)
                if wanted.arrestProgress >= GameConfig.arrestSeconds {
                    doArrest()
                    return
                }
            } else {
                wanted.arrestProgress = max(0, wanted.arrestProgress - Double(dt) * 1.5)
            }
        } else {
            wanted.arrestProgress = 0
        }

        updateHelicopter(dt: dt, playerPos: pp)
    }

    private func spawnPoliceUnit(near pp: RoadPoint) {
        let unit = PoliceCarEntity()
        var point = RoadNetwork.randomRoadPoint()
        var tries = 0
        while tries < 14 {
            point = RoadNetwork.randomRoadPoint()
            let d = RoadNetwork.distance2D(ax: point.x, az: point.z, bx: pp.x, bz: pp.z)
            if d > 45 && d < 95 { break }
            tries += 1
        }
        let snapped = RoadNetwork.nearestRoadPoint(x: point.x, z: point.z)
        unit.aiAxisX = RoadNetwork.avenuesX.contains(snapped.x) && snapped.x == point.x
        unit.aiDirection = Bool.random() ? 1 : -1
        let off = RoadNetwork.laneOffset(axisX: unit.aiAxisX, direction: unit.aiDirection)
        if unit.aiAxisX {
            unit.node.position = SCNVector3(snapped.x + off, 0, point.z)
            unit.heading = unit.aiDirection > 0 ? 0 : Float.pi
        } else {
            unit.node.position = SCNVector3(point.x, 0, snapped.z + off)
            unit.heading = unit.aiDirection > 0 ? Float.pi / 2 : -Float.pi / 2
        }
        unit.node.eulerAngles.y = unit.heading
        scene.rootNode.addChildNode(unit.node)
        policeCars.append(unit)
    }

    private func doArrest() {
        SoundManager.shared.fail()
        let fine = wanted.arrestFine()
        money = max(0, money - fine)
        wanted.clearAll()
        for p in policeCars { p.node.removeFromParentNode() }
        policeCars.removeAll()
        heliActive = false
        heli.node.isHidden = true
        if drivenCar != nil { exitCar() }
        player.node.position = SCNVector3(-62, 0, -62)
        player.node.isHidden = false
        // Restart the current mission step (chase steps re-trigger).
        stepStarted = false
        pushToast("ARRESTED — fine $" + String(fine) + ". Released outside MBPD.")
        clearRoadblock()
        persistRuntime()
    }

    // MARK: - Phase 3: police roadblocks
    // Deployed once the wanted level reaches roadblockMinLevel. Two parked
    // police cars + three concrete barriers appear across the road ahead of
    // the player's driving direction. Safe logic: only on/near a real road,
    // never closer than roadblockMinDeployDistance, with a cooldown after
    // each clearance. Dynamic node budget: 2 police cars (46 nodes each) +
    // 3 barrier boxes = 95 nodes, all removed on clear.

    private func updateRoadblock(dt: Float) {
        if roadblockCooldown > 0 { roadblockCooldown -= Double(dt) }
        for unit in roadblockUnits {
            unit.updateSiren(dt: Double(dt), active: true)
            unit.setHeadlights(on: true)
        }
        if roadblockActive {
            let pp = playerPosition()
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                           bx: roadblockCenter.x, bz: roadblockCenter.z)
            if wanted.level < GameConfig.roadblockMinLevel || d > 60 {
                clearRoadblock()
                roadblockCooldown = GameConfig.roadblockRedeploySeconds
            }
            return
        }
        if wanted.level < GameConfig.roadblockMinLevel { return }
        if drivenCar == nil { return }
        if roadblockCooldown > 0 { return }
        guard let car = drivenCar else { return }
        let hx = sin(car.heading)
        let hz = cos(car.heading)
        let aheadX = car.node.position.x + hx * GameConfig.roadblockAheadDistance
        let aheadZ = car.node.position.z + hz * GameConfig.roadblockAheadDistance
        if abs(aheadX) > GameConfig.cityHalf { return }
        if aheadZ > GameConfig.coastZ { return }
        let snapped = RoadNetwork.nearestRoadPoint(x: aheadX, z: aheadZ)
        let offRoad = RoadNetwork.distance2D(ax: aheadX, az: aheadZ,
                                             bx: snapped.x, bz: snapped.z)
        if offRoad > 20 { return }
        let dist = RoadNetwork.distance2D(ax: car.node.position.x, az: car.node.position.z,
                                          bx: snapped.x, bz: snapped.z)
        if dist < GameConfig.roadblockMinDeployDistance { return }
        deployRoadblock(at: snapped,
                        playerPos: RoadPoint(x: car.node.position.x, z: car.node.position.z))
    }

    private func deployRoadblock(at point: RoadPoint, playerPos pp: RoadPoint) {
        roadblockActive = true
        roadblockCenter = point
        roadblockColliderBase = colliders.count
        // Road axis: snapped.x exactly matches an avenue => road runs along Z.
        var axisX = false
        for ax in RoadNetwork.avenuesX {
            if abs(ax - point.x) < 0.01 { axisX = true; break }
        }
        let faceHeading = atan2(pp.x - point.x, pp.z - point.z)
        let carOffsets: [Float] = [-3.0, 3.0]
        for off in carOffsets {
            let unit = PoliceCarEntity()
            var ux = point.x
            var uz = point.z
            if axisX { ux = point.x + off } else { uz = point.z + off }
            unit.node.position = SCNVector3(ux, 0, uz)
            unit.heading = faceHeading
            unit.node.eulerAngles.y = faceHeading
            unit.setHeadlights(on: true)
            scene.rootNode.addChildNode(unit.node)
            roadblockUnits.append(unit)
            let hx: Float = axisX ? 1.0 : 2.4
            let hz: Float = axisX ? 2.4 : 1.0
            colliders.append(BuildingCollider(minX: ux - hx, maxX: ux + hx,
                                              minZ: uz - hz, maxZ: uz + hz))
        }
        let barrierOffsets: [Float] = [-1.5, 0, 1.5]
        for off in barrierOffsets {
            var bx = point.x
            var bz = point.z
            if axisX { bx = point.x + off } else { bz = point.z + off }
            let barrier = NodeFactory.box(w: 1.5, h: 1.0, d: 0.5,
                                          color: UIColor(red: 0.75, green: 0.75,
                                                         blue: 0.78, alpha: 1))
            barrier.position = SCNVector3(bx, 0.5, bz)
            if !axisX { barrier.eulerAngles.y = Float.pi / 2 }
            scene.rootNode.addChildNode(barrier)
            roadblockBarrierNodes.append(barrier)
            let hx: Float = axisX ? 0.75 : 0.25
            let hz: Float = axisX ? 0.25 : 0.75
            colliders.append(BuildingCollider(minX: bx - hx, maxX: bx + hx,
                                              minZ: bz - hz, maxZ: bz + hz))
        }
        pushToast("Police roadblock ahead!")
    }

    private func clearRoadblock() {
        let hadRoadblock = roadblockActive
        for unit in roadblockUnits { unit.node.removeFromParentNode() }
        roadblockUnits.removeAll()
        for b in roadblockBarrierNodes { b.removeFromParentNode() }
        roadblockBarrierNodes.removeAll()
        // Only truncate colliders when a roadblock actually appended them;
        // otherwise the base index (0) would wipe the whole static city.
        if hadRoadblock && roadblockColliderBase < colliders.count {
            colliders.removeSubrange(roadblockColliderBase..<colliders.count)
        }
        roadblockColliderBase = 0
        roadblockActive = false
    }

    private func updateHelicopter(dt: Float, playerPos pp: RoadPoint) {
        heliActive = coordinator.helicopterActive(forLevel: wanted.level)
        heli.node.isHidden = !heliActive
        if !heliActive { return }
        let center = wanted.hasVisual ? pp : wanted.lastKnown
        heli.angle += dt * 0.32
        let radius: Float = 27
        let tx = center.x + cos(heli.angle) * radius
        let tz = center.z + sin(heli.angle) * radius
        var pos = heli.node.position
        let blend = min(1, dt * 1.1)
        pos.x += (tx - pos.x) * blend
        pos.z += (tz - pos.z) * blend
        pos.y += (30 - pos.y) * blend
        heli.node.position = pos
        heli.node.eulerAngles.y = atan2(-sin(heli.angle), cos(heli.angle)) + Float.pi / 2
        heli.updateRotor(dt: dt)
        heli.setSpotlight(on: isNight)
    }

    func unlockAchievementFromEngine(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state.unlockAchievement(id, silent: false)
        }
    }

    // MARK: - Missions

    private func activateNextMission() {
        currentMission = StoryData.nextMission(afterCompleted: state.save.completedMissions)
        stepIndex = 0
        stepStarted = false
        collectIndex = 0
        if let m = currentMission {
            hudMissionTitle = m.chapterName + " · " + m.title
            hudObjective = m.summary
        } else {
            hudMissionTitle = "Free Roam — Meridian Bay"
            hudObjective = "Explore the city: shops, races, deliveries and properties are marked."
        }
    }

    private func startMissionDialogue() {
        guard let mission = currentMission else { return }
        let dialogue = StoryData.dialogue(forMissionID: mission.id,
                                           decisions: state.save.decisions)
            ?? defaultDialogue(for: mission)
        talkPending = true
        lastDialogueToken = state.dialogueFinishToken
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.state.activeDialogue = dialogue
            s.state.input.paused = true
        }
    }

    private func defaultDialogue(for mission: MissionDef) -> ActiveDialogue {
        let giver = Characters.def(forID: mission.giverID)
        var lines: [String] = []
        lines.append(giver.name + ": " + mission.summary)
        lines.append("Adam: Consider it done.")
        return ActiveDialogue(id: mission.id + "_talk", speakerName: giver.name, lines: lines)
    }

    private func updateMissions(dt: Float) {
        guard let mission = currentMission else {
            if activeRace == nil && !deliveryActive {
                objectiveMarker?.isHidden = true
            }
            return
        }
        if stepIndex >= mission.steps.count {
            completeMission(mission)
            return
        }
        let step = mission.steps[stepIndex]
        if !stepStarted { startStep(step) }

        // Dialogue completion advances talk steps.
        if step.kind == .talkTo && talkPending {
            if state.dialogueFinishToken != lastDialogueToken {
                talkPending = false
                advanceStep(mission)
                return
            }
        }

        let pp = playerPosition()
        switch step.kind {
        case .goTo:
            showObjectiveMarker(x: step.x, z: step.z)
            hudObjective = step.text
            if RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: step.x, bz: step.z) < step.radius {
                advanceStep(mission)
            }
        case .driveTo, .followCar:
            showObjectiveMarker(x: step.x, z: step.z)
            hudObjective = step.text + (drivenCar == nil ? " (get in a car)" : "")
            if drivenCar != nil &&
                RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: step.x, bz: step.z) < step.radius {
                advanceStep(mission)
            }
        case .timedGoTo:
            showObjectiveMarker(x: step.x, z: step.z)
            stepTimer -= Double(dt)
            hudObjective = step.text + " — " + String(max(0, Int(stepTimer))) + "s"
            if RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: step.x, bz: step.z) < step.radius {
                advanceStep(mission)
            } else if stepTimer <= 0 {
                failStep("Time's up — try again.")
            }
        case .talkTo:
            showObjectiveMarker(x: step.x, z: step.z)
            hudObjective = step.text
            positionMissionNPC(step: step, playerPos: pp)
        case .collectPoints:
            if collectIndex < step.points.count {
                let target = step.points[collectIndex]
                showObjectiveMarker(x: target.x, z: target.z)
                hudObjective = step.text + " (" + String(collectIndex) + "/" +
                    String(step.points.count) + ")"
                if RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: target.x, bz: target.z) < step.radius {
                    collectIndex += 1
                    pushToast("Collected " + String(collectIndex) + " of " +
                              String(step.points.count))
                    if collectIndex >= step.points.count {
                        advanceStep(mission)
                    }
                }
            }
        case .escapeWanted:
            objectiveMarker?.isHidden = true
            hudObjective = step.text + " (hide off-road to cool off faster)"
            if wanted.level == 0 {
                advanceStep(mission)
            }
        case .surviveChase:
            objectiveMarker?.isHidden = true
            stepTimer -= Double(dt)
            hudObjective = step.text + " — survive " + String(max(0, Int(stepTimer))) + "s"
            if stepTimer <= 0 {
                advanceStep(mission)
            }
        }
    }

    private func startStep(_ step: MissionStep) {
        stepStarted = true
        stepTimer = step.seconds
        collectIndex = 0
        let pp = playerPosition()
        if step.kind == .surviveChase {
            wanted.raiseTo(max(wanted.level, 3), reason: "Ambush", at: pp)
            pushToast("Ambush! Survive the chase.")
        }
        if step.kind == .escapeWanted && wanted.level == 0 {
            wanted.raiseTo(2, reason: "Spotted by patrol", at: pp)
        }
        if step.kind != .talkTo {
            missionNPC?.root.isHidden = true
        }
    }

    private func positionMissionNPC(step: MissionStep, playerPos pp: RoadPoint) {
        guard let npc = missionNPC else { return }
        npc.root.isHidden = false
        npc.root.position = SCNVector3(step.x + 1.6, 0, step.z + 0.5)
        let def = Characters.def(forID: step.characterID)
        npc.torsoMaterial.diffuse.contents = ShirtColors.color(at: def.shirtIndex)
        let dx = pp.x - (step.x + 1.6)
        let dz = pp.z - (step.z + 0.5)
        npc.root.eulerAngles.y = atan2(dx, dz)
    }

    private func showObjectiveMarker(x: Float, z: Float) {
        guard let marker = objectiveMarker else { return }
        marker.isHidden = false
        marker.position = SCNVector3(x, 1.3, z)
    }

    private func failStep(_ message: String) {
        SoundManager.shared.fail()
        pushToast(message)
        stepStarted = false
        stepTimer = 0
    }

    private func advanceStep(_ mission: MissionDef) {
        stepIndex += 1
        stepStarted = false
        missionNPC?.root.isHidden = true
        if stepIndex >= mission.steps.count {
            completeMission(mission)
        } else {
            pushToast("Objective updated")
        }
    }

    private func completeMission(_ mission: MissionDef) {
        SoundManager.shared.success()
        money += mission.reward
        currentMission = nil
        objectiveMarker?.isHidden = true
        let id = mission.id
        let reward = mission.reward
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            if !s.state.save.completedMissions.contains(id) {
                s.state.save.completedMissions.append(id)
            }
            if s.state.save.completedMissions.count >= StoryData.missions.count {
                s.state.unlockAchievement("shadow", silent: false)
            } else {
                s.state.unlockAchievement("first_mission", silent: true)
            }
            s.state.persist()
        }
        pushToast("Mission complete: " + mission.title + "  +$" + String(reward))
        activateNextMission()
        persistRuntime()
    }

    // MARK: - Races, deliveries, dynamic events

    private func startRace(_ race: StoryData.RaceDef) {
        if activeRace != nil {
            activeRace = nil
            objectiveMarker?.isHidden = true
            pushToast("Race cancelled.")
            return
        }
        if drivenCar == nil {
            pushToast("Get in a car first, then start the race.")
            return
        }
        activeRace = race
        raceCheckpoint = 0
        raceElapsed = 0
        pushToast(race.name + " — follow the gold markers!")
    }

    private func startDelivery() {
        if deliveryActive {
            pushToast("Finish the current delivery first.")
            return
        }
        let pp = playerPosition()
        var target = StoryData.deliveryTargets[Int.random(in: 0..<StoryData.deliveryTargets.count)]
        var tries = 0
        while tries < 8 {
            let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: target.x, bz: target.z)
            if d > 90 { break }
            target = StoryData.deliveryTargets[Int.random(in: 0..<StoryData.deliveryTargets.count)]
            tries += 1
        }
        deliveryTarget = target
        deliveryTimer = StoryData.deliverySeconds
        deliveryActive = true
        pushToast("Delivery picked up! Reach the marker in time.")
    }

    private func updateActivities(dt: Float) {
        // Dynamic city events.
        eventTimer -= Double(dt)
        if eventTimer <= 0 {
            eventTimer = Double(Float.random(in: 70...120))
            triggerDynamicEvent()
        }
        if jamTimer > 0 { jamTimer -= Double(dt) }

        let pp = playerPosition()
        if let race = activeRace {
            raceElapsed += Double(dt)
            if raceCheckpoint < race.checkpoints.count {
                let cp = race.checkpoints[raceCheckpoint]
                showObjectiveMarker(x: cp.x, z: cp.z)
                hudObjective = race.name + " — checkpoint " + String(raceCheckpoint + 1) + "/" +
                    String(race.checkpoints.count) + " · " + String(Int(raceElapsed)) + "s"
                if RoadNetwork.distance2D(ax: pp.x, az: pp.z, bx: cp.x, bz: cp.z) < 9 {
                    raceCheckpoint += 1
                    if raceCheckpoint >= race.checkpoints.count {
                        finishRace(race)
                    }
                }
            }
            return
        }
        if deliveryActive {
            deliveryTimer -= Double(dt)
            showObjectiveMarker(x: deliveryTarget.x, z: deliveryTarget.z)
            hudObjective = "Delivery — " + String(max(0, Int(deliveryTimer))) + "s left"
            if RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                      bx: deliveryTarget.x, bz: deliveryTarget.z) < 8 {
                deliveryActive = false
                money += StoryData.deliveryReward
                objectiveMarker?.isHidden = true
                pushToast("Delivery complete! +$" + String(StoryData.deliveryReward))
                unlockAchievementFromEngine("courier")
                persistRuntime()
            } else if deliveryTimer <= 0 {
                deliveryActive = false
                objectiveMarker?.isHidden = true
                pushToast("Delivery failed — too slow.")
            }
        }
    }

    private func finishRace(_ race: StoryData.RaceDef) {
        let time = raceElapsed
        activeRace = nil
        objectiveMarker?.isHidden = true
        money += race.reward
        let id = race.id
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            let best = s.state.save.raceBestSeconds[id]
            if best == nil || time < (best ?? 0) {
                s.state.save.raceBestSeconds[id] = time
            }
            s.state.persist()
        }
        pushToast(race.name + " finished in " + String(Int(time)) + "s! +$" + String(race.reward))
        unlockAchievementFromEngine("racer")
        persistRuntime()
    }

    private func triggerDynamicEvent() {
        let pp = playerPosition()
        let roll = Float.random(in: 0...1)
        var fired = false
        // Option 1: broken-down traffic car.
        if roll < 0.34 && brokenCar == nil {
            for car in trafficCars {
                if !car.aiActive { continue }   // convoy cars keep their formation
                let d = RoadNetwork.distance2D(ax: pp.x, az: pp.z,
                                               bx: car.node.position.x,
                                               bz: car.node.position.z)
                if d > 40 && d < 110 {
                    brokenCar = car
                    brokenTimer = 35
                    pushToast("Traffic report: a car has broken down ahead.")
                    fired = true
                    break
                }
            }
        }
        // Option 2: temporary jam near a random intersection.
        if !fired && roll < 0.67 {
            let points = RoadNetwork.intersections()
            if !points.isEmpty {
                jamCenter = points[Int.random(in: 0..<points.count)]
                jamTimer = 25
                pushToast("Traffic report: heavy congestion in the city.")
                fired = true
            }
        }
        // Option 3 (Phase 3): a slow ceremonial convoy crosses the city.
        if !fired {
            spawnConvoy()
        }
    }

    // MARK: - Phase 3: convoy event
    // A line of slow cars moves along one road for convoyDuration seconds.
    // The cars live in trafficCars (so traffic AI, obstacle checks and car
    // collisions see them) with aiActive=false, moved by updateConvoy only.
    // Dynamic node budget: convoyCarCount x 39 nodes per traffic car = 117.

    private func spawnConvoy() {
        if !convoyCars.isEmpty { return }
        let axisX = Bool.random()
        var x: Float = 0
        var z: Float = 0
        if axisX {
            x = RoadNetwork.avenuesX[Int.random(in: 0..<RoadNetwork.avenuesX.count)]
            z = Float.random(in: -90...90)
        } else {
            z = RoadNetwork.streetsZ[Int.random(in: 0..<RoadNetwork.streetsZ.count)]
            x = Float.random(in: -90...90)
        }
        let dir: Float = Bool.random() ? 1 : -1
        var heading: Float = 0
        if axisX {
            if dir > 0 { heading = 0 } else { heading = Float.pi }
        } else {
            if dir > 0 { heading = Float.pi / 2 } else { heading = -Float.pi / 2 }
        }
        for i in 0..<GameConfig.convoyCarCount {
            let car = TrafficCarEntity(paint: UIColor(red: 0.07, green: 0.07, blue: 0.09,
                                                     alpha: 1))
            car.aiActive = false
            car.aiSpeedLimit = GameConfig.convoySpeed
            let back = dir * Float(i) * 8.0
            if axisX {
                car.node.position = SCNVector3(x, 0, z - back)
            } else {
                car.node.position = SCNVector3(x - back, 0, z)
            }
            car.heading = heading
            car.node.eulerAngles.y = heading
            car.setHeadlights(on: true)
            scene.rootNode.addChildNode(car.node)
            trafficCars.append(car)
            convoyCars.append(car)
        }
        convoyTimer = GameConfig.convoyDuration
        pushToast("Traffic report: a ceremonial convoy is moving through the city.")
    }

    private func updateConvoy(dt: Float) {
        if convoyCars.isEmpty { return }
        convoyTimer -= Double(dt)
        var alive: [TrafficCarEntity] = []
        for car in convoyCars {
            let inTraffic = trafficCars.contains(where: { $0 === car })
            if !inTraffic {
                // Stolen by the player (enterCar removes it from trafficCars):
                // stop tracking it; the car itself lives on as driven/stolen.
                continue
            }
            if convoyTimer <= 0 {
                if let idx = trafficCars.firstIndex(where: { $0 === car }) {
                    trafficCars.remove(at: idx)
                }
                car.node.removeFromParentNode()
                continue
            }
            let hx = sin(car.heading)
            let hz = cos(car.heading)
            var pos = car.node.position
            pos.x += hx * GameConfig.convoySpeed * dt
            pos.z += hz * GameConfig.convoySpeed * dt
            // Wrap around at the city edge so the convoy keeps rolling.
            let edge = GameConfig.cityHalf + 8
            if abs(pos.x) > edge || abs(pos.z) > edge {
                if abs(hx) > abs(hz) {
                    if pos.x > 0 { pos.x = -edge } else { pos.x = edge }
                } else {
                    if pos.z > 0 { pos.z = -edge } else { pos.z = edge }
                }
            }
            car.node.position = pos
            car.updateWheels(dt: dt)
            alive.append(car)
        }
        convoyCars = alive
    }

    // MARK: - Environment (day/night, weather, lights)

    private func updateEnvironment(dt: Float) {
        if state.input.timeSkipToken != seenTimeSkipToken {
            seenTimeSkipToken = state.input.timeSkipToken
            timeOfDay = (timeOfDay + 6).truncatingRemainder(dividingBy: 24)
        }
        timeOfDay += Float(Double(dt) * 24.0 / GameConfig.dayLengthSeconds)
        if timeOfDay >= 24 { timeOfDay -= 24 }

        // Day factor: 0 at night, 1 at midday (sun up between 06:00 and 18:00).
        let sunAngle = (timeOfDay - 6) / 12 * Float.pi
        var dayFactor = sin(sunAngle)
        if dayFactor < 0 { dayFactor = 0 }
        if dayFactor > 1 { dayFactor = 1 }
        isNight = dayFactor < 0.12

        // Weather selection.
        let pref = state.save.settings.weatherPreference
        if pref == "Clear" { weather = .clear }
        else if pref == "Cloudy" { weather = .cloudy }
        else if pref == "Rain" { weather = .rain }
        else if pref == "Fog" { weather = .fog }
        else {
            weatherTimer -= Double(dt)
            if weatherTimer <= 0 {
                weatherTimer = 100
                let roll = Float.random(in: 0...1)
                if roll < 0.5 { weather = .clear }
                else if roll < 0.75 { weather = .cloudy }
                else if roll < 0.9 { weather = .rain }
                else { weather = .fog }
            }
        }

        var sunBase: Float = 90 + 950 * dayFactor
        if weather == .cloudy { sunBase *= 0.55 }
        if weather == .rain { sunBase *= 0.42 }
        if weather == .fog { sunBase *= 0.5 }
        if let l = sunLight.light {
            l.intensity = CGFloat(sunBase)
            let warm = 1 - dayFactor * 0.5
            l.color = UIColor(red: 1, green: CGFloat(0.72 + 0.2 * dayFactor),
                              blue: CGFloat(0.95 - 0.35 * warm), alpha: 1)
        }
        sunLight.eulerAngles = SCNVector3(-(0.25 + dayFactor * 0.85), 0.4, 0)
        if let l = ambientLight.light {
            l.intensity = CGFloat(130 + 300 * dayFactor)
        }

        // Facade warmth & shop glow at night (facades have lit windows baked
        // into their textures; a gentle emissive tint sells the night look).
        if isNight {
            for m in city.facadeMaterials {
                m.emissive.contents = UIColor(red: 0.20, green: 0.15, blue: 0.06, alpha: 1)
            }
            city.shopGlowMaterial.emissive.contents = UIColor(red: 0.15, green: 0.35, blue: 0.55, alpha: 1)
            // Phase 1 — neon signs blaze, windows glow warm, billboards backlit.
            for (i, m) in city.neonMaterials.enumerated() {
                if i < city.neonNightColors.count {
                    m.emissive.contents = city.neonNightColors[i]
                }
            }
            for m in city.windowLitMaterials {
                m.emissive.contents = UIColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1)
            }
            city.billboardMaterial.emissive.contents = UIColor(white: 0.55, alpha: 1)
        } else {
            for m in city.facadeMaterials {
                m.emissive.contents = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
            }
            city.shopGlowMaterial.emissive.contents = UIColor(red: 0.04, green: 0.08, blue: 0.12, alpha: 1)
            // Phase 1 — neon signs and windows go dim; billboards unlit.
            for (i, m) in city.neonMaterials.enumerated() {
                if i < city.neonDayColors.count {
                    m.emissive.contents = city.neonDayColors[i]
                }
            }
            for m in city.windowLitMaterials {
                m.emissive.contents = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
            }
            city.billboardMaterial.emissive.contents = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        }
        // Traffic light materials follow the global phase.
        lightPhase += Double(dt)
        let phase = lightPhase.truncatingRemainder(dividingBy: 16)
        if phase < 8 {
            city.trafficGreenMaterial.emissive.contents = UIColor(red: 0.1, green: 0.9, blue: 0.25, alpha: 1)
            city.trafficRedMaterial.emissive.contents = UIColor(red: 0.35, green: 0.03, blue: 0.03, alpha: 1)
        } else {
            city.trafficGreenMaterial.emissive.contents = UIColor(red: 0.03, green: 0.3, blue: 0.08, alpha: 1)
            city.trafficRedMaterial.emissive.contents = UIColor(red: 0.95, green: 0.08, blue: 0.08, alpha: 1)
        }
        // Fog & rain & wet roads.
        if weather == .fog {
            scene.fogStartDistance = 10
            scene.fogEndDistance = 95
        } else if weather == .rain {
            scene.fogStartDistance = 70
            scene.fogEndDistance = 300
        } else if weather == .cloudy {
            scene.fogStartDistance = 180
            scene.fogEndDistance = 560
        } else {
            scene.fogStartDistance = 420
            scene.fogEndDistance = 950
        }
        // Wet roads: keep the asphalt texture, just drop the PBR roughness
        // so the wet surface reflects light (IBL + lamps + headlights).
        if state.quality().rawValue != lastShadowQualityRaw {
            lastShadowQualityRaw = state.quality().rawValue
            applyQualityToLights()
        }
        if weather == .rain {
            city.roadMaterial.roughness.contents = NSNumber(value: 0.25)
            rainNode?.isHidden = false
            let pp = playerPosition()
            rainNode?.position = SCNVector3(pp.x, 26, pp.z)
        } else {
            city.roadMaterial.roughness.contents = NSNumber(value: 0.9)
            rainNode?.isHidden = true
        }
        playerCar.setHeadlights(on: isNight)
        playerCar.setUnderglowNight(on: isNight)
        if let dc = drivenCar { dc.setUnderglowNight(on: isNight) }
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        let input = state.input
        let sensitivity = state.save.settings.sensitivity
        if input.camDragX != 0 || input.camDragY != 0 {
            camYaw -= input.camDragX * 0.0042 * sensitivity
            camPitch += input.camDragY * 0.003 * sensitivity
            if camPitch < 0.10 { camPitch = 0.10 }
            if camPitch > 0.85 { camPitch = 0.85 }
            input.camDragX = 0
            input.camDragY = 0
        }
        var target = player.node.position
        if let car = drivenCar { target = car.node.position }
        let driving = drivenCar != nil
        let dist: Float = driving ? 10.5 : 6.8
        let horiz = dist * cos(camPitch)
        let desired = SCNVector3(
            target.x - sin(camYaw) * horiz,
            target.y + 1.7 + dist * sin(camPitch),
            target.z - cos(camYaw) * horiz)
        // Collision-lite: if the desired point sits inside a building,
        // pull the camera closer until it is clear.
        var finalPos = desired
        var shrink: Float = 1.0
        var tries = 0
        while tries < 4 {
            var inside = false
            for c in colliders {
                if finalPos.x > c.minX && finalPos.x < c.maxX &&
                    finalPos.z > c.minZ && finalPos.z < c.maxZ {
                    inside = true
                    break
                }
            }
            if !inside { break }
            shrink *= 0.7
            finalPos = SCNVector3(target.x - sin(camYaw) * horiz * shrink,
                                  target.y + 1.7 + dist * sin(camPitch) * shrink,
                                  target.z - cos(camYaw) * horiz * shrink)
            tries += 1
        }
        if finalPos.y < 0.6 { finalPos.y = 0.6 }
        let blend = 1 - exp(-dt * 5.5)
        camPos.x += (finalPos.x - camPos.x) * blend
        camPos.y += (finalPos.y - camPos.y) * blend
        camPos.z += (finalPos.z - camPos.z) * blend
        cameraNode.position = camPos
        cameraNode.lookAt(SCNVector3(target.x, target.y + 1.5, target.z))
    }

    // MARK: - HUD sync & life events

    private func updateAudioState() {
        let settings = state.save.settings
        SoundManager.shared.setVolumes(music: settings.musicVolume,
                                       sfx: settings.sfxVolume)
        if state.inWorld {
            SoundManager.shared.stopMenuMusic()
            SoundManager.shared.startCityAmbience()
        }
        if let car = drivenCar {
            let top = max(10, car.effectiveTopSpeed())
            let rate = 0.7 + min(1.3, abs(car.speed) / top * 1.2)
            SoundManager.shared.setEngine(on: true, rate: rate)
        } else {
            SoundManager.shared.setEngine(on: false, rate: 0.7)
        }
        let sirenNear = wanted.level > 0 && nearestPoliceDistance(to: playerPosition()) < 50
        SoundManager.shared.setSiren(on: sirenNear)
        SoundManager.shared.setRain(on: weather == .rain)
    }

    private func spawnSparks(x: Float, z: Float) {
        var spawned = 0
        var i = 0
        while i < sparkNodes.count && spawned < 6 {
            if sparkLife[i] <= 0 {
                sparkLife[i] = Double(Float.random(in: 0.25...0.45))
                sparkNodes[i].isHidden = false
                sparkNodes[i].position = SCNVector3(x, 0.8, z)
                sparkVelocities[i] = SCNVector3(Float.random(in: -2.4...2.4),
                                                Float.random(in: 1.5...3.6),
                                                Float.random(in: -2.4...2.4))
                spawned += 1
            }
            i += 1
        }
    }

    private func updateSparks(dt: Float) {
        var i = 0
        while i < sparkNodes.count {
            if sparkLife[i] > 0 {
                sparkLife[i] -= Double(dt)
                var pos = sparkNodes[i].position
                var vel = sparkVelocities[i]
                vel.y -= 9.5 * dt
                pos.x += vel.x * dt
                pos.y += vel.y * dt
                pos.z += vel.z * dt
                if pos.y < 0.08 { pos.y = 0.08; vel.y = 0 }
                sparkVelocities[i] = vel
                sparkNodes[i].position = pos
                if sparkLife[i] <= 0 {
                    sparkNodes[i].isHidden = true
                }
            }
            i += 1
        }
    }

    private func syncToState() {
        updateAudioState()
        if health <= 0 {
            handleKnockout()
        }
        let pp = playerPosition()
        var mm = MinimapData()
        mm.playerX = pp.x
        mm.playerZ = pp.z
        mm.playerHeading = drivenCar != nil ? drivenCar!.heading : player.heading
        for unit in policeCars {
            mm.policePoints.append(CGPoint(x: Double(unit.node.position.x),
                                           y: Double(unit.node.position.z)))
        }
        var trafficCount = 0
        for car in trafficCars {
            if trafficCount >= 8 { break }
            mm.trafficPoints.append(CGPoint(x: Double(car.node.position.x),
                                            y: Double(car.node.position.z)))
            trafficCount += 1
        }
        if let marker = objectiveMarker, !marker.isHidden {
            mm.hasObjective = true
            mm.objectivePoint = CGPoint(x: Double(marker.position.x),
                                        y: Double(marker.position.z))
        }
        let driving = drivenCar != nil
        let kmh = driving ? Int(abs(drivenCar!.speed) * 3.6) : Int(footSpeed * 3.6)
        var policeText = ""
        if wanted.level > 0 {
            policeText = wanted.statusText()
            if wanted.arrestProgress > 0.15 {
                policeText = "ARREST IN PROGRESS — run!"
            }
        }
        let prompt = interactionPromptLocal
        let mTitle = hudMissionTitle
        let mObj = hudObjective
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.state.speedKmh = kmh
            s.state.isDriving = driving
            s.state.healthDisplay = s.health
            s.state.moneyDisplay = s.money
            s.state.wantedStars = s.wanted.level
            s.state.policeStatusText = policeText
            s.state.missionTitle = mTitle
            s.state.objectiveText = mObj
            s.state.interactPrompt = prompt
            s.state.minimap = mm
        }
    }

    private func handleKnockout() {
        SoundManager.shared.fail()
        health = 60
        money = max(0, money - 100)
        wanted.clearAll()
        for p in policeCars { p.node.removeFromParentNode() }
        policeCars.removeAll()
        heliActive = false
        heli.node.isHidden = true
        if drivenCar != nil {
            drivenCar = nil
        }
        player.node.position = SCNVector3(10, 0, 112)
        player.node.isHidden = false
        pushToast("You woke up at the bay clinic. -$100 medical bill.")
        persistRuntime()
    }

    private func pushToast(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state.showToast(message)
        }
    }

    // MARK: - Math helpers

    private func shortestAngle(from a: Float, to b: Float) -> Float {
        var d = (b - a).truncatingRemainder(dividingBy: Float.pi * 2)
        while d > Float.pi { d -= Float.pi * 2 }
        while d < -Float.pi { d += Float.pi * 2 }
        return d
    }
}
