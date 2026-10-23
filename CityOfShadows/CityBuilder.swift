import Foundation
import SceneKit
import UIKit

// MARK: - Collision & interaction data produced by the city build

struct BuildingCollider {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float

    // Circle vs AABB overlap test used by player & vehicle collision.
    func overlapsCircle(x: Float, z: Float, r: Float) -> Bool {
        return x + r > minX && x - r < maxX && z + r > minZ && z - r < maxZ
    }

    // Push a circle centre out of the box along the smallest penetration axis.
    func pushOut(x: Float, z: Float, r: Float) -> (x: Float, z: Float, hit: Bool) {
        if !overlapsCircle(x: x, z: z, r: r) { return (x, z, false) }
        let pushLeft = (x + r) - minX
        let pushRight = maxX - (x - r)
        let pushUp = (z + r) - minZ
        let pushDown = maxZ - (z - r)
        var best = pushLeft
        var nx = minX - r
        var nz = z
        if pushRight < best { best = pushRight; nx = maxX + r; nz = z }
        if pushUp < best { best = pushUp; nx = x; nz = minZ - r }
        if pushDown < best { nx = x; nz = maxZ + r }
        return (nx, nz, true)
    }
}

enum InteractKind: String {
    case shop
    case dealership
    case garage
    case property
    case clothing
    case race
    case delivery
}

struct InteractablePoint {
    let kind: InteractKind
    let id: String       // property id / race id / "" otherwise
    let label: String
    let x: Float
    let z: Float
}

// Phase 1 — a building facade chosen for neon signs or lit windows.
struct FacadeSpot {
    let x: Float
    let z: Float
    let w: Float   // building width (x)
    let d: Float   // building depth (z)
}

struct CityBuildResult {
    let root: SCNNode
    let colliders: [BuildingCollider]
    let interactables: [InteractablePoint]
    let facadeMaterials: [SCNMaterial]   // engine warms emissive at night
    let shopGlowMaterial: SCNMaterial
    let trafficRedMaterial: SCNMaterial
    let trafficGreenMaterial: SCNMaterial
    let roadMaterial: SCNMaterial        // engine darkens when wet
    let waterNode: SCNNode
    let neonMaterials: [SCNMaterial]     // shared neon sign materials (Phase 1)
    let neonNightColors: [UIColor]       // parallel to neonMaterials: bright at night
    let neonDayColors: [UIColor]         // parallel to neonMaterials: dim by day
    let windowLitMaterials: [SCNMaterial] // shared lit-window material (Phase 1)
    let billboardMaterial: SCNMaterial  // shared 3D billboard face (Phase 1)
}

// MARK: - City builder

enum CityBuilder {
    static func hash2(_ x: Float, _ z: Float) -> Float {
        let s = sin(x * 127.1 + z * 311.7) * 43758.5453
        return s - floor(s)
    }

    static func makeLabel(_ text: String, color: UIColor) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0.15)
        geo.font = UIFont.boldSystemFont(ofSize: 3.2)
        geo.flatness = 0.5
        geo.materials = [NodeFactory.material(color, emissive: color)]
        let node = SCNNode(geometry: geo)
        let (minB, maxB) = geo.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, minB.y, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.Y]
        node.constraints = [billboard]
        return node
    }

    static func build() -> CityBuildResult {
        let root = SCNNode()
        var colliders: [BuildingCollider] = []
        var interactables: [InteractablePoint] = []

        let asphalt = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        let groundMat = TextureLoader.groundMaterial(
            texture: "grass", fallback: UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1),
            repeatScale: 26)
        let sidewalkMat = TextureLoader.groundMaterial(
            texture: "concrete", fallback: UIColor(red: 0.30, green: 0.31, blue: 0.34, alpha: 1),
            repeatScale: 30)
        let roadMat = TextureLoader.groundMaterial(
            texture: "asphalt", fallback: asphalt, repeatScale: 22)
        // Dry asphalt PBR baseline; the engine drops this to ~0.25 in rain
        // for a wet, reflective look (see GameViewController.updateEnvironment).
        roadMat.lightingModel = .physicallyBased
        roadMat.roughness.contents = NSNumber(value: 0.9)
        let lineMat = NodeFactory.material(UIColor(red: 0.55, green: 0.55, blue: 0.42, alpha: 1))
        let shopGlowMat = NodeFactory.material(UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1),
                                               emissive: UIColor(red: 0.05, green: 0.10, blue: 0.16, alpha: 1))
        TextureLoader.apply(to: shopGlowMat, texture: "shopfront",
                            fallback: UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1))
        let trafficRedMat = NodeFactory.material(UIColor(red: 0.25, green: 0.03, blue: 0.03, alpha: 1))
        let trafficGreenMat = NodeFactory.material(UIColor(red: 0.03, green: 0.25, blue: 0.08, alpha: 1))

        // Phase 1 — city richness: shared neon sign materials. Each sign picks
        // one of 4 colours; the engine drives emissive night (bright) / day
        // (dim) from the parallel colour arrays in CityBuildResult.
        let neonBright: [UIColor] = [
            UIColor(red: 1.0, green: 0.18, blue: 0.55, alpha: 1),  // pink
            UIColor(red: 0.10, green: 0.90, blue: 1.0, alpha: 1),  // cyan
            UIColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1),  // amber
            UIColor(red: 0.62, green: 0.32, blue: 1.0, alpha: 1)    // violet
        ]
        var neonMats: [SCNMaterial] = []
        var neonNight: [UIColor] = []
        var neonDay: [UIColor] = []
        for bright in neonBright {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            bright.getRed(&r, green: &g, blue: &b, alpha: &a)
            let dim = UIColor(red: r * 0.12, green: g * 0.12, blue: b * 0.12, alpha: 1)
            neonMats.append(NodeFactory.material(dim, emissive: bright))
            neonNight.append(bright)
            neonDay.append(dim)
        }
        // Phase 1 — one shared material for the lit-window grids; the engine
        // sets warm emissive at night and near-black by day.
        let windowLitMat = NodeFactory.material(
            UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
            emissive: UIColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1))
        // Phase 1 — shared double-sided billboard face with the generated
        // billboard.jpg art; engine adds a backlit glow at night.
        let billboardMat = SCNMaterial()
        TextureLoader.apply(to: billboardMat, texture: "billboard",
                            fallback: UIColor(red: 0.12, green: 0.10, blue: 0.20, alpha: 1))
        billboardMat.isDoubleSided = true
        billboardMat.emission.contents = UIColor(white: 0.45, alpha: 1)

        // Ground slab
        let groundGeo = SCNPlane(width: 340, height: 340)
        groundGeo.materials = [groundMat]
        let ground = SCNNode(geometry: groundGeo)
        ground.eulerAngles.x = -Float.pi / 2
        ground.position = SCNVector3(0, -0.05, 0)
        root.addChildNode(ground)

        // Roads + sidewalks + centre lines
        for ax in RoadNetwork.avenuesX {
            let roadGeo = SCNPlane(width: CGFloat(GameConfig.roadHalfWidth * 2), height: 320)
            roadGeo.materials = [roadMat]
            let road = SCNNode(geometry: roadGeo)
            road.eulerAngles.x = -Float.pi / 2
            road.position = SCNVector3(ax, 0.0, 0)
            root.addChildNode(road)
            for side in [-1, 1] {
                let swGeo = SCNPlane(width: 2.4, height: 320)
                swGeo.materials = [sidewalkMat]
                let sw = SCNNode(geometry: swGeo)
                sw.eulerAngles.x = -Float.pi / 2
                sw.position = SCNVector3(ax + Float(side) * (GameConfig.roadHalfWidth + 1.2),
                                         GameConfig.sidewalkHeight * 0.5, 0)
                root.addChildNode(sw)
            }
            let lineGeo = SCNPlane(width: 0.22, height: 320)
            lineGeo.materials = [lineMat]
            let line = SCNNode(geometry: lineGeo)
            line.eulerAngles.x = -Float.pi / 2
            line.position = SCNVector3(ax, 0.01, 0)
            root.addChildNode(line)
        }
        for sz in RoadNetwork.streetsZ {
            let roadGeo = SCNPlane(width: 320, height: CGFloat(GameConfig.roadHalfWidth * 2))
            roadGeo.materials = [roadMat]
            let road = SCNNode(geometry: roadGeo)
            road.eulerAngles.x = -Float.pi / 2
            road.position = SCNVector3(0, 0.0, sz)
            root.addChildNode(road)
            for side in [-1, 1] {
                let swGeo = SCNPlane(width: 320, height: 2.4)
                swGeo.materials = [sidewalkMat]
                let sw = SCNNode(geometry: swGeo)
                sw.eulerAngles.x = -Float.pi / 2
                sw.position = SCNVector3(0, GameConfig.sidewalkHeight * 0.5,
                                         sz + Float(side) * (GameConfig.roadHalfWidth + 1.2))
                root.addChildNode(sw)
            }
            let lineGeo = SCNPlane(width: 320, height: 0.22)
            lineGeo.materials = [lineMat]
            let line = SCNNode(geometry: lineGeo)
            line.eulerAngles.x = -Float.pi / 2
            line.position = SCNVector3(0, 0.01, sz)
            root.addChildNode(line)
        }

        // Coast: promenade, sand, water
        let promGeo = SCNPlane(width: 340, height: 9)
        promGeo.materials = [NodeFactory.material(UIColor(red: 0.42, green: 0.40, blue: 0.36, alpha: 1))]
        let prom = SCNNode(geometry: promGeo)
        prom.eulerAngles.x = -Float.pi / 2
        prom.position = SCNVector3(0, 0.02, 133.5)
        root.addChildNode(prom)
        let sandGeo = SCNPlane(width: 340, height: 30)
        sandGeo.materials = [TextureLoader.groundMaterial(
            texture: "sand", fallback: UIColor(red: 0.76, green: 0.68, blue: 0.50, alpha: 1),
            repeatScale: 16)]
        let sand = SCNNode(geometry: sandGeo)
        sand.eulerAngles.x = -Float.pi / 2
        sand.position = SCNVector3(0, 0.01, GameConfig.coastZ + 15)
        root.addChildNode(sand)
        let waterGeo = SCNPlane(width: 700, height: 320)
        waterGeo.materials = [TextureLoader.groundMaterial(
            texture: "water", fallback: UIColor(red: 0.03, green: 0.16, blue: 0.30, alpha: 1),
            repeatScale: 12)]
        let water = SCNNode(geometry: waterGeo)
        water.eulerAngles.x = -Float.pi / 2
        water.position = SCNVector3(0, -0.15, GameConfig.waterZ + 150)
        root.addChildNode(water)

        // Buildings per block (blocks sit between adjacent avenues/streets)
        let districtMats: [SCNMaterial] = [
            TextureLoader.texturedMaterial(texture: "facade_high",
                fallback: UIColor(red: 0.36, green: 0.38, blue: 0.44, alpha: 1)), // downtown
            TextureLoader.texturedMaterial(texture: "facade_glass",
                fallback: UIColor(red: 0.48, green: 0.40, blue: 0.33, alpha: 1)), // commercial
            TextureLoader.texturedMaterial(texture: "facade_house",
                fallback: UIColor(red: 0.62, green: 0.55, blue: 0.45, alpha: 1)), // residential
            TextureLoader.texturedMaterial(texture: "warehouse",
                fallback: UIColor(red: 0.40, green: 0.42, blue: 0.40, alpha: 1)), // industrial
            TextureLoader.texturedMaterial(texture: "brick",
                fallback: UIColor(red: 0.50, green: 0.47, blue: 0.52, alpha: 1))  // mixed
        ]
        let gaps: [(Float, Float)] = [(-150, -120), (-120, -60), (-60, 0), (0, 60), (60, 120), (120, 150)]
        // Blocks use the wide 60m gaps between main roads only.
        let blockRanges: [(Float, Float)] = [(-120, -60), (-60, 0), (0, 60), (60, 120)]
        // Phase 1 — facades collected for neon signs / lit windows.
        var neonSpots: [FacadeSpot] = []
        var windowSpots: [FacadeSpot] = []
        for (x0, x1) in blockRanges {
            for (z0, z1) in blockRanges {
                let cx = (x0 + x1) / 2
                let cz = (z0 + z1) / 2
                let h = hash2(cx, cz)
                if h < 0.16 {
                    buildParkingLot(root: root, cx: cx, cz: cz, hash: h)
                    continue
                }
                if h < 0.26 {
                    buildPlaza(root: root, cx: cx, cz: cz)
                    continue
                }
                // District by position
                var district = 4
                var minH: Float = 10
                var maxH: Float = 22
                if abs(cx) < 40 && abs(cz) < 40 {
                    district = 0; minH = 26; maxH = 56
                } else if cx > 40 && cz < -40 {
                    district = 1; minH = 13; maxH = 25
                } else if cx < -40 && cz < -40 {
                    district = 2; minH = 5; maxH = 9
                } else if cx > 40 && cz > 40 {
                    district = 3; minH = 8; maxH = 13
                }
                // Landmark plots stay clear of random block buildings.
                let exclusions: [(Float, Float, Float)] = [
                    (60, -104, 22),   // dealership
                    (-48, -48, 17),   // police station
                    (48, -48, 15),    // clothing shop
                    (104, 60, 18),    // garage
                    (-106, 12, 16)    // gas station
                ]
                let offsets: [(Float, Float)] = [(-13, -13), (13, -13), (-13, 13), (13, 13)]
                for (ox, oz) in offsets {
                    let bx = cx + ox
                    let bz = cz + oz
                    var excluded = false
                    for (ex, ez, er) in exclusions {
                        if abs(bx - ex) < er && abs(bz - ez) < er { excluded = true }
                    }
                    if excluded { continue }
                    let bh = hash2(bx * 1.7, bz * 2.3)
                    if bh < 0.22 { continue }  // some plots stay empty
                    let height = minH + bh * (maxH - minH)
                    let width: Float = district == 3 ? 22 : 15 + bh * 5
                    let depth: Float = district == 3 ? 20 : 15 + hash2(bz, bx) * 5
                    let geo = SCNBox(width: CGFloat(width), height: CGFloat(height),
                                     length: CGFloat(depth), chamferRadius: 0.15)
                    geo.materials = [districtMats[district]]
                    let b = SCNNode(geometry: geo)
                    b.position = SCNVector3(bx, height / 2, bz)
                    b.castsShadow = true
                    root.addChildNode(b)
                    if district == 1 {
                        // Emissive shop front at street level.
                        let frontGeo = SCNPlane(width: CGFloat(width * 0.9), height: 3.2)
                        frontGeo.materials = [shopGlowMat]
                        let front = SCNNode(geometry: frontGeo)
                        front.position = SCNVector3(bx, 1.7, bz + depth / 2 + 0.06)
                        root.addChildNode(front)
                    }
                    colliders.append(BuildingCollider(minX: bx - width / 2, maxX: bx + width / 2,
                                                      minZ: bz - depth / 2, maxZ: bz + depth / 2))
                    // Phase 1 — candidate facades for neon signs (commercial)
                    // and lit-window grids (downtown + commercial).
                    if district == 1 {
                        neonSpots.append(FacadeSpot(x: bx, z: bz, w: width, d: depth))
                    }
                    if (district == 0 || district == 1) && windowSpots.count < 10
                        && hash2(bx * 2.9, bz * 1.1) < 0.55 {
                        windowSpots.append(FacadeSpot(x: bx, z: bz, w: width, d: depth))
                    }
                }
            }
        }
        _ = gaps

        // Trees (shared geometries)
        let trunkGeo = SCNCylinder(radius: 0.14, height: 1.6)
        trunkGeo.materials = [NodeFactory.material(UIColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 1))]
        let leafGeo = SCNSphere(radius: 1.5)
        leafGeo.materials = [NodeFactory.material(UIColor(red: 0.13, green: 0.32, blue: 0.16, alpha: 1))]
        var treeX: Float = -140
        while treeX <= 140 {
            addTree(root: root, x: treeX, z: 131, trunkGeo: trunkGeo, leafGeo: leafGeo)
            treeX += 20
        }
        for ax in RoadNetwork.avenuesX {
            var tz: Float = -135
            while tz <= 135 {
                if hash2(ax + tz, tz) > 0.45 {
                    addTree(root: root, x: ax + 8.6, z: tz, trunkGeo: trunkGeo, leafGeo: leafGeo)
                }
                tz += 45
            }
        }

        // Street lamps at intersections (shared geometry)
        let lampPoleGeo = SCNCylinder(radius: 0.09, height: 5.2)
        lampPoleGeo.materials = [NodeFactory.material(UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1))]
        let lampHeadGeo = SCNSphere(radius: 0.22)
        let lampHeadMat = NodeFactory.material(UIColor(red: 0.9, green: 0.85, blue: 0.6, alpha: 1),
                                               emissive: UIColor(red: 0.9, green: 0.8, blue: 0.45, alpha: 1))
        lampHeadGeo.materials = [lampHeadMat]
        for ax in RoadNetwork.avenuesX {
            for sz in RoadNetwork.streetsZ {
                let pole = SCNNode(geometry: lampPoleGeo)
                pole.position = SCNVector3(ax + 7.4, 2.6, sz + 7.4)
                root.addChildNode(pole)
                let head = SCNNode(geometry: lampHeadGeo)
                head.position = SCNVector3(ax + 7.4, 5.3, sz + 7.4)
                root.addChildNode(head)
            }
        }

        // Traffic lights at the 9 central intersections (shared materials so
        // the engine can flip every light with the global phase at once).
        for ax in [-60.0, 0.0, 60.0] as [Float] {
            for sz in [-60.0, 0.0, 60.0] as [Float] {
                let group = SCNNode()
                group.position = SCNVector3(ax + 7.2, 0, sz + 7.2)
                let pole = SCNNode(geometry: lampPoleGeo)
                pole.position = SCNVector3(0, 2.6, 0)
                group.addChildNode(pole)
                let headBox = NodeFactory.box(w: 0.5, h: 1.3, d: 0.5,
                                              color: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
                headBox.position = SCNVector3(0, 5.4, 0)
                group.addChildNode(headBox)
                let redGeo = SCNSphere(radius: 0.16)
                redGeo.materials = [trafficRedMat]
                let red = SCNNode(geometry: redGeo)
                red.position = SCNVector3(0, 5.75, 0.28)
                group.addChildNode(red)
                let greenGeo = SCNSphere(radius: 0.16)
                greenGeo.materials = [trafficGreenMat]
                let green = SCNNode(geometry: greenGeo)
                green.position = SCNVector3(0, 5.05, 0.28)
                group.addChildNode(green)
                root.addChildNode(group)
            }
        }

        // ----- Landmarks -----
        buildGasStation(root: root, colliders: &colliders, interactables: &interactables)
        buildDealership(root: root, colliders: &colliders, interactables: &interactables,
                        glowMat: shopGlowMat)
        buildGarage(root: root, colliders: &colliders, interactables: &interactables)
        buildClothingShop(root: root, colliders: &colliders, interactables: &interactables,
                          glowMat: shopGlowMat)
        buildPoliceStation(root: root, colliders: &colliders)

        // Phase 1 — city richness: neon signs, lit windows, billboards,
        // street furniture and the improved central intersection.
        // The returned node total is exact at runtime (helpers count nodes).
        _ = buildCityRichness(root: root, colliders: &colliders,
                              neonMats: neonMats, windowLitMat: windowLitMat,
                              billboardMat: billboardMat,
                              neonSpots: neonSpots, windowSpots: windowSpots)

        // Phase 3 — jump ramps (drive-over stunt ramps on real roads).
        _ = buildJumpRamps(root: root)

        // Property markers (gold rings + labels)
        for prop in PropertyCatalog.all {
            let ringGeo = SCNTorus(ringRadius: 2.2, pipeRadius: 0.16)
            ringGeo.materials = [NodeFactory.material(UIColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1),
                                                      emissive: UIColor(red: 0.6, green: 0.45, blue: 0.05, alpha: 1))]
            let ring = SCNNode(geometry: ringGeo)
            ring.eulerAngles.x = Float.pi / 2
            ring.position = SCNVector3(prop.x, 1.4, prop.z)
            root.addChildNode(ring)
            let label = makeLabel(prop.name, color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            label.position = SCNVector3(prop.x, 4.6, prop.z)
            root.addChildNode(label)
            interactables.append(InteractablePoint(kind: .property, id: prop.id,
                                                   label: prop.name, x: prop.x + 4, z: prop.z + 4))
        }

        // Race start markers
        for race in StoryData.races {
            let ringGeo = SCNTorus(ringRadius: 2.6, pipeRadius: 0.18)
            ringGeo.materials = [NodeFactory.material(UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1),
                                                      emissive: UIColor(red: 0.05, green: 0.5, blue: 0.15, alpha: 1))]
            let ring = SCNNode(geometry: ringGeo)
            ring.eulerAngles.x = Float.pi / 2
            ring.position = SCNVector3(race.startX, 1.4, race.startZ)
            root.addChildNode(ring)
            let label = makeLabel(race.name, color: UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1))
            label.position = SCNVector3(race.startX, 4.8, race.startZ)
            root.addChildNode(label)
            interactables.append(InteractablePoint(kind: .race, id: race.id,
                                                   label: race.name, x: race.startX, z: race.startZ))
        }

        return CityBuildResult(root: root, colliders: colliders, interactables: interactables,
                               facadeMaterials: districtMats, shopGlowMaterial: shopGlowMat,
                               trafficRedMaterial: trafficRedMat,
                               trafficGreenMaterial: trafficGreenMat,
                               roadMaterial: roadMat, waterNode: water,
                               neonMaterials: neonMats, neonNightColors: neonNight,
                               neonDayColors: neonDay,
                               windowLitMaterials: [windowLitMat],
                               billboardMaterial: billboardMat)
    }

    // MARK: - Phase 1: city richness

    // Master entry for Phase 1 of the improvement program. Returns the exact
    // number of scene nodes added (each helper counts its own nodes).
    private static func buildCityRichness(root: SCNNode, colliders: inout [BuildingCollider],
                                          neonMats: [SCNMaterial], windowLitMat: SCNMaterial,
                                          billboardMat: SCNMaterial,
                                          neonSpots: [FacadeSpot],
                                          windowSpots: [FacadeSpot]) -> Int {
        var count = 0
        count += addNeonSigns(root: root, neonMats: neonMats, spots: neonSpots)
        count += addLitWindows(root: root, mat: windowLitMat, spots: windowSpots)
        count += addBillboards(root: root, colliders: &colliders, mat: billboardMat)
        count += addStreetFurniture(root: root, colliders: &colliders)
        count += buildCentralIntersection(root: root, colliders: &colliders)
        return count
    }

    // MARK: - Phase 3: jump ramps
    // Drive-over stunt ramps on straight road sections. Purely visual
    // (no colliders — the car must roll over the deck): the launch is
    // triggered by a radius check in GameViewController.updateDrivenCar.
    // Node budget: 3 ramps x (1 group + 1 deck + 2 cones + 1 label) = 15.
    private static func buildJumpRamps(root: SCNNode) -> Int {
        let deckGeo = SCNBox(width: 4.2, height: 0.35, length: 7.0, chamferRadius: 0.05)
        let deckMat = NodeFactory.material(
            UIColor(red: 0.95, green: 0.45, blue: 0.08, alpha: 1),
            emissive: UIColor(red: 0.5, green: 0.2, blue: 0.03, alpha: 1))
        deckGeo.materials = [deckMat]
        let coneGeo = SCNCylinder(radius: 0.28, height: 0.75)
        let coneMat = NodeFactory.material(UIColor(red: 0.95, green: 0.35, blue: 0.05, alpha: 1))
        coneGeo.materials = [coneMat]
        let tilt: Float = 0.32   // deck slope in radians (front edge rises)
        var count = 0
        for ramp in StoryData.jumpRamps {
            let group = SCNNode()
            group.position = SCNVector3(ramp.x, 0, ramp.z)
            group.eulerAngles.y = ramp.heading
            root.addChildNode(group)
            count += 1
            let deck = SCNNode(geometry: deckGeo)
            deck.position = SCNVector3(0, 1.05, 0)
            deck.eulerAngles.x = -tilt
            group.addChildNode(deck)
            count += 1
            for side in [-1.0, 1.0] as [Float] {
                let cone = SCNNode(geometry: coneGeo)
                cone.position = SCNVector3(side * 2.8, 0.38, -3.6)
                group.addChildNode(cone)
                count += 1
            }
            let label = makeLabel("JUMP",
                                  color: UIColor(red: 1, green: 0.7, blue: 0.2, alpha: 1))
            label.position = SCNVector3(0, 3.4, 0)
            group.addChildNode(label)
            count += 1
        }
        return count
    }

    // One neon sign node: flat SCNText on a shared neon material, scaled to
    // fit the available facade width. No billboard constraint — it is fixed
    // to the facade and faces the street.
    private static func neonSignNode(text: String, mat: SCNMaterial,
                                     maxWidth: Float) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0.12)
        geo.font = UIFont.boldSystemFont(ofSize: 1.9)
        geo.flatness = 0.4
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        let (minB, maxB) = geo.boundingBox
        let bw = maxB.x - minB.x
        if bw > 0 && bw > maxWidth {
            let s = maxWidth / bw
            node.scale = SCNVector3(s, s, s)
        }
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, minB.y, 0)
        return node
    }

    private static func addNeonSigns(root: SCNNode, neonMats: [SCNMaterial],
                                     spots: [FacadeSpot]) -> Int {
        let names = ["CLUB NOVA", "SUSHI 24", "NEON MARKET", "ARCADE",
                     "ELECTRO", "PIZZA", "HOTEL", "CINEMA", "ROOFTOP"]
        var count = 0
        var ni = 0
        // Two signs per commercial building: street face (+Z) and side face (+X).
        for s in spots {
            for face in 0..<2 {
                let mat = neonMats[ni % neonMats.count]
                let sign = neonSignNode(text: names[ni % names.count], mat: mat,
                                        maxWidth: face == 0 ? s.w * 0.85 : s.d * 0.85)
                if face == 0 {
                    sign.position = SCNVector3(s.x, 3.9, s.z + s.d / 2 + 0.08)
                } else {
                    sign.position = SCNVector3(s.x + s.w / 2 + 0.08, 3.9, s.z)
                    sign.eulerAngles.y = Float.pi / 2
                }
                root.addChildNode(sign)
                count += 1
                ni += 1
            }
        }
        // The two commercial landmarks get one sign each (dealership hall is
        // 26x16 at (60,-104); clothing shop is 14x10 at (48,-48)).
        let landmarkSigns: [(String, Float, Float, Float, Float)] = [
            ("TURBO", 60, 3.9, -104 + 8 + 0.08, 0),
            ("STYLE", 48 + 7 + 0.08, 3.9, -48, Float.pi / 2)
        ]
        for (text, lx, ly, lz, rot) in landmarkSigns {
            let mat = neonMats[ni % neonMats.count]
            let sign = neonSignNode(text: text, mat: mat, maxWidth: 12)
            sign.position = SCNVector3(lx, ly, lz)
            sign.eulerAngles.y = rot
            root.addChildNode(sign)
            count += 1
            ni += 1
        }
        // Freestanding neon totems along the commercial avenues (x=68 faces
        // avenue 60, x=112 faces avenue 120). These guarantee exactly 10
        // signs even when the deterministic block layout yields few
        // commercial buildings (hash skips / landmark exclusions).
        let totemSpots: [(Float, Float, Float)] = [
            (68, -100, -Float.pi / 2), (68, -80, -Float.pi / 2),
            (68, -40, -Float.pi / 2), (68, -20, -Float.pi / 2),
            (112, -100, Float.pi / 2), (112, -80, Float.pi / 2)
        ]
        var ti = 0
        while ni < 10 && ti < totemSpots.count {
            let (tx, tz, rot) = totemSpots[ti]
            let pole = NodeFactory.cylinder(r: 0.22, h: 5,
                                            color: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
            pole.position = SCNVector3(tx, 2.5, tz)
            root.addChildNode(pole)
            count += 1
            let mat = neonMats[ni % neonMats.count]
            let sign = neonSignNode(text: names[ni % names.count], mat: mat, maxWidth: 6)
            sign.position = SCNVector3(tx, 4.4, tz)
            sign.eulerAngles.y = rot
            root.addChildNode(sign)
            count += 1
            ni += 1
            ti += 1
        }
        return count
    }

    // Lit-window grids (2 rows x 4) on the street-facing facade of a
    // deterministic subset of downtown/commercial buildings, all sharing one
    // material so the engine flips the whole set at nightfall.
    private static func addLitWindows(root: SCNNode, mat: SCNMaterial,
                                      spots: [FacadeSpot]) -> Int {
        var count = 0
        let winGeo = SCNPlane(width: 1.2, height: 0.9)
        winGeo.materials = [mat]
        for s in spots {
            for row in 0..<2 {
                for col in 0..<4 {
                    let win = SCNNode(geometry: winGeo)
                    let wx = s.x + (Float(col) - 1.5) * s.w * 0.18
                    let wy: Float = 6.5 + Float(row) * 3.0
                    win.position = SCNVector3(wx, wy, s.z + s.d / 2 + 0.05)
                    root.addChildNode(win)
                    count += 1
                }
            }
        }
        return count
    }

    // Three double-faced billboards: pole + shared backlit board material.
    private static func addBillboards(root: SCNNode, colliders: inout [BuildingCollider],
                                      mat: SCNMaterial) -> Int {
        // (x, z, rotationY): avenue 60 strip, coast road entry, (-60,-60) corner.
        let spots: [(Float, Float, Float)] = [
            (71, 4, Float.pi / 2),
            (10, 127.5, 0),
            (-50, -50, Float.pi / 4)
        ]
        var count = 0
        for (bx, bz, rot) in spots {
            let pole = NodeFactory.cylinder(r: 0.35, h: 9,
                                            color: UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1))
            pole.position = SCNVector3(bx, 4.5, bz)
            root.addChildNode(pole)
            count += 1
            let boardGeo = SCNPlane(width: 14, height: 7)
            boardGeo.materials = [mat]
            let board = SCNNode(geometry: boardGeo)
            board.position = SCNVector3(bx, 9.5, bz)
            board.eulerAngles.y = rot
            root.addChildNode(board)
            count += 1
            colliders.append(BuildingCollider(minX: bx - 0.6, maxX: bx + 0.6,
                                              minZ: bz - 0.6, maxZ: bz + 0.6))
        }
        return count
    }

    // Benches, bollards and concrete barriers at deterministic spots.
    // Barriers sit on sidewalk offsets, never on drive lanes, so traffic AI
    // paths stay clear.
    private static func addStreetFurniture(root: SCNNode,
                                           colliders: inout [BuildingCollider]) -> Int {
        var count = 0
        // Benches along the promenade (z=132), skipping avenue crossings.
        var benchX: Float = -132
        while benchX <= 132 {
            var onRoad = false
            for ax in RoadNetwork.avenuesX {
                if abs(benchX - ax) < 8 { onRoad = true }
            }
            if !onRoad {
                let bench = NodeFactory.box(w: 2.4, h: 0.5, d: 0.7,
                                            color: UIColor(red: 0.35, green: 0.25, blue: 0.16, alpha: 1))
                bench.position = SCNVector3(benchX, 0.3, 132)
                root.addChildNode(bench)
                count += 1
            }
            benchX += 24
        }
        // Short bollards along avenue sidewalk edges (visual only).
        let bollardGeo = SCNCylinder(radius: 0.12, height: 0.9)
        bollardGeo.materials = [NodeFactory.material(UIColor(red: 0.55, green: 0.57, blue: 0.60, alpha: 1))]
        var bi = 0
        for ax in [-60.0, 60.0] as [Float] {
            var bz: Float = -120
            while bz <= 120 {
                var nearStreet = false
                for sz in RoadNetwork.streetsZ {
                    if abs(bz - sz) < 8 { nearStreet = true }
                }
                if !nearStreet {
                    let side: Float = bi % 2 == 0 ? 1 : -1
                    let b = SCNNode(geometry: bollardGeo)
                    b.position = SCNVector3(ax + side * (GameConfig.roadHalfWidth + 2.5),
                                            0.45, bz)
                    root.addChildNode(b)
                    count += 1
                    bi += 1
                }
                bz += 15
            }
        }
        // Concrete barriers with colliders: first 3 parking-lot blocks get
        // two each on their north/south edges (7.5 m off the street centre
        // line = sidewalk edge, off the drive lanes), plus 2 at the
        // promenade ends.
        let barrierColor = UIColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
        let centers: [Float] = [-90, -30, 30, 90]
        var lots = 0
        for cx in centers {
            if lots >= 3 { break }
            for cz in centers {
                if lots >= 3 { break }
                // Same predicate the building loop uses for parking lots.
                if hash2(cx, cz) < 0.16 {
                    for dz in [-22.5, 22.5] as [Float] {
                        let barrier = NodeFactory.box(w: 2.2, h: 0.8, d: 0.5, color: barrierColor)
                        barrier.position = SCNVector3(cx, 0.4, cz + dz)
                        root.addChildNode(barrier)
                        count += 1
                        colliders.append(BuildingCollider(minX: cx - 1.1, maxX: cx + 1.1,
                                                          minZ: cz + dz - 0.25, maxZ: cz + dz + 0.25))
                    }
                    lots += 1
                }
            }
        }
        for ex in [-168.0, 168.0] as [Float] {
            let barrier = NodeFactory.box(w: 0.5, h: 0.8, d: 2.2, color: barrierColor)
            barrier.position = SCNVector3(ex, 0.4, 133.5)
            root.addChildNode(barrier)
            count += 1
            colliders.append(BuildingCollider(minX: ex - 0.25, maxX: ex + 0.25,
                                              minZ: 132.4, maxZ: 134.6))
        }
        return count
    }

    // Improved central intersection (0,0): zebra crossings on all four
    // approaches, corner islands with planters + lamps, and a decorative
    // promenade entrance arch.
    //
    // NOTE (bridge fallback): a drivable bridge deck is NOT built here. The
    // driven car pins pos.y = 0 every frame and the player has no
    // ground-height query, so any elevated deck would be undriveable (the
    // car would clip through it or hover under it). The improvement
    // program's fallback for this phase is this improved intersection.
    private static func buildCentralIntersection(root: SCNNode,
                                                 colliders: inout [BuildingCollider]) -> Int {
        var count = 0
        // Zebra crossings on all four approaches of (0,0).
        let stripeMat = NodeFactory.material(UIColor(red: 0.75, green: 0.75, blue: 0.72, alpha: 1))
        let stripeGeoZ = SCNPlane(width: 0.9, height: 4.2)
        stripeGeoZ.materials = [stripeMat]
        let stripeGeoX = SCNPlane(width: 4.2, height: 0.9)
        stripeGeoX.materials = [stripeMat]
        for dz in [-10.0, 10.0] as [Float] {
            var sx: Float = -4
            while sx <= 4 {
                let s = SCNNode(geometry: stripeGeoZ)
                s.eulerAngles.x = -Float.pi / 2
                s.position = SCNVector3(sx, 0.025, dz)
                root.addChildNode(s)
                count += 1
                sx += 2
            }
        }
        for dx in [-10.0, 10.0] as [Float] {
            var sz: Float = -4
            while sz <= 4 {
                let s = SCNNode(geometry: stripeGeoX)
                s.eulerAngles.x = -Float.pi / 2
                s.position = SCNVector3(dx, 0.025, sz)
                root.addChildNode(s)
                count += 1
                sz += 2
            }
        }
        // Four corner islands: low base + planter + bush + lamp.
        let islandGeo = SCNBox(width: 2.4, height: 0.35, length: 2.4, chamferRadius: 0.05)
        islandGeo.materials = [NodeFactory.material(UIColor(red: 0.38, green: 0.39, blue: 0.36, alpha: 1))]
        let planterGeo = SCNBox(width: 1.4, height: 0.7, length: 1.4, chamferRadius: 0.05)
        planterGeo.materials = [NodeFactory.material(UIColor(red: 0.45, green: 0.32, blue: 0.24, alpha: 1))]
        let bushGeo = SCNSphere(radius: 0.8)
        bushGeo.materials = [NodeFactory.material(UIColor(red: 0.14, green: 0.34, blue: 0.17, alpha: 1))]
        let islandPoleGeo = SCNCylinder(radius: 0.09, height: 5.2)
        islandPoleGeo.materials = [NodeFactory.material(UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1))]
        let islandHeadGeo = SCNSphere(radius: 0.22)
        islandHeadGeo.materials = [NodeFactory.material(UIColor(red: 0.9, green: 0.85, blue: 0.6, alpha: 1),
                                                         emissive: UIColor(red: 0.9, green: 0.8, blue: 0.45, alpha: 1))]
        for ix in [-9.2, 9.2] as [Float] {
            for iz in [-9.2, 9.2] as [Float] {
                let base = SCNNode(geometry: islandGeo)
                base.position = SCNVector3(ix, 0.175, iz)
                root.addChildNode(base)
                count += 1
                let planter = SCNNode(geometry: planterGeo)
                planter.position = SCNVector3(ix, 0.7, iz)
                root.addChildNode(planter)
                count += 1
                let bush = SCNNode(geometry: bushGeo)
                bush.position = SCNVector3(ix, 1.35, iz)
                root.addChildNode(bush)
                count += 1
                let pole = SCNNode(geometry: islandPoleGeo)
                pole.position = SCNVector3(ix, 0.35 + 2.6, iz)
                root.addChildNode(pole)
                count += 1
                let head = SCNNode(geometry: islandHeadGeo)
                head.position = SCNVector3(ix, 0.35 + 5.3, iz)
                root.addChildNode(head)
                count += 1
            }
        }
        // Decorative promenade entrance arch at (0, 129). The legs have
        // colliders; the middle stays open so avenue traffic passes through.
        let legMat = UIColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1)
        for lx in [-4.5, 4.5] as [Float] {
            let leg = NodeFactory.box(w: 0.8, h: 7, d: 0.8, color: legMat)
            leg.position = SCNVector3(lx, 3.5, 129)
            root.addChildNode(leg)
            count += 1
            colliders.append(BuildingCollider(minX: lx - 0.4, maxX: lx + 0.4,
                                              minZ: 128.6, maxZ: 129.4))
        }
        let beam = NodeFactory.box(w: 10.6, h: 1.2, d: 1.2, color: legMat,
                                   emissive: UIColor(red: 0.10, green: 0.30, blue: 0.45, alpha: 1))
        beam.position = SCNVector3(0, 7.4, 129)
        root.addChildNode(beam)
        count += 1
        let archLabel = makeLabel("SHADOW PROMENADE",
                                  color: UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1))
        archLabel.position = SCNVector3(0, 8.9, 129)
        root.addChildNode(archLabel)
        count += 1
        return count
    }

    // MARK: Block dressing

    private static func addTree(root: SCNNode, x: Float, z: Float,
                                trunkGeo: SCNCylinder, leafGeo: SCNSphere) {
        let tree = SCNNode()
        let trunk = SCNNode(geometry: trunkGeo)
        trunk.position = SCNVector3(0, 0.8, 0)
        tree.addChildNode(trunk)
        let leaves = SCNNode(geometry: leafGeo)
        leaves.position = SCNVector3(0, 2.6, 0)
        tree.addChildNode(leaves)
        tree.position = SCNVector3(x, 0, z)
        root.addChildNode(tree)
    }

    private static func buildParkingLot(root: SCNNode, cx: Float, cz: Float, hash: Float) {
        let lotGeo = SCNPlane(width: 44, height: 44)
        lotGeo.materials = [NodeFactory.material(UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1))]
        let lot = SCNNode(geometry: lotGeo)
        lot.eulerAngles.x = -Float.pi / 2
        lot.position = SCNVector3(cx, 0.03, cz)
        root.addChildNode(lot)
        // A few static parked cars (simple two-box shapes).
        let colors: [UIColor] = [
            UIColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1),
            UIColor(red: 0.35, green: 0.15, blue: 0.15, alpha: 1),
            UIColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1),
            UIColor(red: 0.6, green: 0.55, blue: 0.2, alpha: 1)
        ]
        var i = 0
        while i < 4 {
            let px = cx - 15 + Float(i) * 10
            let pz = cz + (i % 2 == 0 ? -12 : 12)
            let bodyC = NodeFactory.box(w: 1.8, h: 0.55, d: 4.1, color: colors[i])
            bodyC.position = SCNVector3(px, 0.6, pz)
            root.addChildNode(bodyC)
            let cabinC = NodeFactory.box(w: 1.55, h: 0.5, d: 1.9,
                                         color: UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1))
            cabinC.position = SCNVector3(px, 1.1, pz)
            root.addChildNode(cabinC)
            i += 1
        }
    }

    private static func buildPlaza(root: SCNNode, cx: Float, cz: Float) {
        let plazaGeo = SCNPlane(width: 44, height: 44)
        plazaGeo.materials = [NodeFactory.material(UIColor(red: 0.35, green: 0.36, blue: 0.33, alpha: 1))]
        let plaza = SCNNode(geometry: plazaGeo)
        plaza.eulerAngles.x = -Float.pi / 2
        plaza.position = SCNVector3(cx, 0.03, cz)
        root.addChildNode(plaza)
        let trunkGeo = SCNCylinder(radius: 0.14, height: 1.6)
        trunkGeo.materials = [NodeFactory.material(UIColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 1))]
        let leafGeo = SCNSphere(radius: 1.6)
        leafGeo.materials = [NodeFactory.material(UIColor(red: 0.14, green: 0.34, blue: 0.17, alpha: 1))]
        let spots: [(Float, Float)] = [(-14, -14), (14, -14), (-14, 14), (14, 14), (0, 0)]
        for (ox, oz) in spots {
            addTree(root: root, x: cx + ox, z: cz + oz, trunkGeo: trunkGeo, leafGeo: leafGeo)
        }
        let bench = NodeFactory.box(w: 2.4, h: 0.5, d: 0.7,
                                    color: UIColor(red: 0.35, green: 0.25, blue: 0.16, alpha: 1))
        bench.position = SCNVector3(cx + 6, 0.3, cz)
        root.addChildNode(bench)
    }

    // MARK: Landmarks

    private static func buildGasStation(root: SCNNode, colliders: inout [BuildingCollider],
                                        interactables: inout [InteractablePoint]) {
        // Corner of avenue -120 / street 0 — canopy + kiosk.
        let canopy = NodeFactory.box(w: 14, h: 0.5, d: 10,
                                     color: UIColor(red: 0.85, green: 0.80, blue: 0.75, alpha: 1))
        canopy.position = SCNVector3(-106, 4.6, 10)
        root.addChildNode(canopy)
        var px: Float = -112
        while px <= -100 {
            var pz: Float = 6
            while pz <= 14 {
                let pole = NodeFactory.cylinder(r: 0.18, h: 4.4,
                                                color: UIColor(red: 0.6, green: 0.6, blue: 0.62, alpha: 1))
                pole.position = SCNVector3(px, 2.2, pz)
                root.addChildNode(pole)
                pz += 8
            }
            px += 12
        }
        var pumpX: Float = -110
        while pumpX <= -102 {
            let pump = NodeFactory.box(w: 0.8, h: 1.3, d: 0.6,
                                       color: UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1))
            pump.position = SCNVector3(pumpX, 0.65, 10)
            root.addChildNode(pump)
            pumpX += 4
        }
        let kiosk = NodeFactory.box(w: 8, h: 3.4, d: 6,
                                    color: UIColor(red: 0.80, green: 0.78, blue: 0.72, alpha: 1))
        kiosk.position = SCNVector3(-106, 1.7, 20)
        root.addChildNode(kiosk)
        colliders.append(BuildingCollider(minX: -110, maxX: -102, minZ: 17, maxZ: 23))
        let label = makeLabel("FUEL & MART", color: UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1))
        label.position = SCNVector3(-106, 6.4, 10)
        root.addChildNode(label)
        interactables.append(InteractablePoint(kind: .shop, id: "", label: "Fuel & Mart shop",
                                               x: -106, z: 15))
        interactables.append(InteractablePoint(kind: .delivery, id: "", label: "Delivery job board",
                                               x: -100, z: 16))
    }

    private static func buildDealership(root: SCNNode, colliders: inout [BuildingCollider],
                                        interactables: inout [InteractablePoint],
                                        glowMat: SCNMaterial) {
        let hall = SCNNode(geometry: SCNBox(width: 26, height: 7, length: 16, chamferRadius: 0.2))
        hall.geometry?.materials = [glowMat]
        hall.position = SCNVector3(60, 3.5, -104)
        root.addChildNode(hall)
        colliders.append(BuildingCollider(minX: 47, maxX: 73, minZ: -112, maxZ: -96))
        let label = makeLabel("HALE MOTORS", color: UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1))
        label.position = SCNVector3(60, 8.6, -104)
        root.addChildNode(label)
        // Display cars outside.
        let showColors: [UIColor] = [
            UIColor(red: 0.75, green: 0.08, blue: 0.10, alpha: 1),
            UIColor(red: 0.85, green: 0.65, blue: 0.10, alpha: 1),
            UIColor(red: 0.08, green: 0.25, blue: 0.75, alpha: 1)
        ]
        var i = 0
        while i < 3 {
            let dx = 48 + Float(i) * 12
            let bodyC = NodeFactory.box(w: 1.8, h: 0.55, d: 4.2, color: showColors[i])
            bodyC.position = SCNVector3(dx, 0.6, -90)
            root.addChildNode(bodyC)
            let cabinC = NodeFactory.box(w: 1.55, h: 0.5, d: 1.9,
                                         color: UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1))
            cabinC.position = SCNVector3(dx, 1.1, -90)
            root.addChildNode(cabinC)
            i += 1
        }
        interactables.append(InteractablePoint(kind: .dealership, id: "", label: "Hale Motors dealership",
                                               x: 60, z: -92))
    }

    private static func buildGarage(root: SCNNode, colliders: inout [BuildingCollider],
                                    interactables: inout [InteractablePoint]) {
        let hall = NodeFactory.box(w: 20, h: 6, d: 14,
                                   color: UIColor(red: 0.45, green: 0.38, blue: 0.30, alpha: 1))
        hall.position = SCNVector3(104, 3, 60)
        root.addChildNode(hall)
        let door = NodeFactory.box(w: 9, h: 4.4, d: 0.3,
                                   color: UIColor(red: 0.25, green: 0.26, blue: 0.30, alpha: 1))
        door.position = SCNVector3(104, 2.2, 52.8)
        root.addChildNode(door)
        colliders.append(BuildingCollider(minX: 94, maxX: 114, minZ: 53, maxZ: 67))
        let label = makeLabel("VEGA CUSTOM GARAGE", color: UIColor(red: 1, green: 0.75, blue: 0.35, alpha: 1))
        label.position = SCNVector3(104, 7.6, 60)
        root.addChildNode(label)
        interactables.append(InteractablePoint(kind: .garage, id: "", label: "Vega Custom Garage",
                                               x: 104, z: 50))
    }

    private static func buildClothingShop(root: SCNNode, colliders: inout [BuildingCollider],
                                          interactables: inout [InteractablePoint],
                                          glowMat: SCNMaterial) {
        let shop = NodeFactory.box(w: 14, h: 5, d: 10,
                                   color: UIColor(red: 0.52, green: 0.44, blue: 0.50, alpha: 1))
        shop.position = SCNVector3(48, 2.5, -48)
        root.addChildNode(shop)
        let frontGeo = SCNPlane(width: 12, height: 3)
        frontGeo.materials = [glowMat]
        let front = SCNNode(geometry: frontGeo)
        front.position = SCNVector3(48, 1.6, -42.9)
        root.addChildNode(front)
        let awning = NodeFactory.box(w: 14.5, h: 0.25, d: 2.4,
                                     color: UIColor(red: 0.65, green: 0.12, blue: 0.18, alpha: 1))
        awning.position = SCNVector3(48, 3.4, -42.2)
        root.addChildNode(awning)
        colliders.append(BuildingCollider(minX: 41, maxX: 55, minZ: -53, maxZ: -43))
        let label = makeLabel("THREAD & CO.", color: UIColor(red: 1, green: 0.6, blue: 0.8, alpha: 1))
        label.position = SCNVector3(48, 6.6, -48)
        root.addChildNode(label)
        interactables.append(InteractablePoint(kind: .clothing, id: "", label: "Thread & Co. clothing",
                                               x: 48, z: -40))
    }

    private static func buildPoliceStation(root: SCNNode, colliders: inout [BuildingCollider]) {
        let hall = NodeFactory.box(w: 18, h: 8, d: 12,
                                   color: UIColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1))
        if let geo = hall.geometry {
            geo.materials = [TextureLoader.texturedMaterial(
                texture: "facade_mid",
                fallback: UIColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1))]
        }
        hall.position = SCNVector3(-48, 4, -48)
        root.addChildNode(hall)
        let band = NodeFactory.box(w: 18.2, h: 1.1, d: 12.2,
                                   color: UIColor(red: 0.08, green: 0.20, blue: 0.55, alpha: 1),
                                   emissive: UIColor(red: 0.02, green: 0.06, blue: 0.30, alpha: 1))
        band.position = SCNVector3(-48, 6.4, -48)
        root.addChildNode(band)
        colliders.append(BuildingCollider(minX: -57, maxX: -39, minZ: -54, maxZ: -42))
        let label = makeLabel("MBPD — POLICE", color: UIColor(red: 0.55, green: 0.75, blue: 1, alpha: 1))
        label.position = SCNVector3(-48, 9.6, -48)
        root.addChildNode(label)
    }
}
