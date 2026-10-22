import Foundation
import SceneKit
import UIKit

// MARK: - Small node factory helpers.
// All models in this game are built from SceneKit primitives (boxes, spheres,
// cylinders) with flat materials. No external assets: everything is original
// and procedural, which keeps the build self-contained.

enum NodeFactory {
    static func material(_ color: UIColor, emissive: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        if let e = emissive {
            m.emissive.contents = e
        }
        m.isDoubleSided = false
        return m
    }

    // Physically based material (metalness / roughness) used for the
    // detailed car finish: paint, glass, chrome and rims.
    static func pbrMaterial(_ color: UIColor, metalness: Float, roughness: Float,
                            emissive: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = NSNumber(value: metalness)
        m.roughness.contents = NSNumber(value: roughness)
        if let e = emissive {
            m.emissive.contents = e
        }
        m.isDoubleSided = false
        return m
    }

    static func box(w: Float, h: Float, d: Float, color: UIColor,
                    emissive: UIColor? = nil) -> SCNNode {
        let geo = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d),
                         chamferRadius: 0.02)
        geo.materials = [material(color, emissive: emissive)]
        return SCNNode(geometry: geo)
    }

    static func sphere(r: Float, color: UIColor, emissive: UIColor? = nil) -> SCNNode {
        let geo = SCNSphere(radius: CGFloat(r))
        geo.materials = [material(color, emissive: emissive)]
        return SCNNode(geometry: geo)
    }

    static func cylinder(r: Float, h: Float, color: UIColor,
                         emissive: UIColor? = nil) -> SCNNode {
        let geo = SCNCylinder(radius: CGFloat(r), height: CGFloat(h))
        geo.materials = [material(color, emissive: emissive)]
        return SCNNode(geometry: geo)
    }

    static func plane(w: Float, d: Float, color: UIColor,
                      emissive: UIColor? = nil) -> SCNNode {
        let geo = SCNPlane(width: CGFloat(w), height: CGFloat(d))
        geo.materials = [material(color, emissive: emissive)]
        let node = SCNNode(geometry: geo)
        node.eulerAngles.x = -Float.pi / 2
        return node
    }
}

// MARK: - Humanoid figure (shared by player & pedestrians)

final class HumanoidFigure {
    let root = SCNNode()
    let torsoMaterial: SCNMaterial
    private let armL = SCNNode()
    private let armR = SCNNode()
    private let legL = SCNNode()
    private let legR = SCNNode()
    var walkPhase: Float = 0

    init(shirtColor: UIColor, pantsColor: UIColor, skinColor: UIColor) {
        torsoMaterial = NodeFactory.material(shirtColor)
        let pantsMat = NodeFactory.material(pantsColor)
        let skinMat = NodeFactory.material(skinColor)

        // Legs (pivot at hip, y = 0.95)
        let legGeoL = SCNBox(width: 0.16, height: 0.9, length: 0.18, chamferRadius: 0.02)
        legGeoL.materials = [pantsMat]
        let legMeshL = SCNNode(geometry: legGeoL)
        legMeshL.position = SCNVector3(0, -0.45, 0)
        legL.addChildNode(legMeshL)
        legL.position = SCNVector3(-0.11, 0.95, 0)

        let legGeoR = SCNBox(width: 0.16, height: 0.9, length: 0.18, chamferRadius: 0.02)
        legGeoR.materials = [pantsMat]
        let legMeshR = SCNNode(geometry: legGeoR)
        legMeshR.position = SCNVector3(0, -0.45, 0)
        legR.addChildNode(legMeshR)
        legR.position = SCNVector3(0.11, 0.95, 0)

        // Torso
        let torsoGeo = SCNBox(width: 0.52, height: 0.68, length: 0.28, chamferRadius: 0.04)
        torsoGeo.materials = [torsoMaterial]
        let torso = SCNNode(geometry: torsoGeo)
        torso.position = SCNVector3(0, 1.29, 0)
        torso.castShadow = true

        // Head
        let headGeo = SCNSphere(radius: 0.16)
        headGeo.materials = [skinMat]
        let head = SCNNode(geometry: headGeo)
        head.position = SCNVector3(0, 1.82, 0)

        // Hair cap: flattened dark sphere sitting on top of the head.
        let hairGeo = SCNSphere(radius: 0.165)
        hairGeo.materials = [NodeFactory.material(UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1))]
        let hair = SCNNode(geometry: hairGeo)
        hair.scale = SCNVector3(1, 0.62, 1)
        hair.position = SCNVector3(0, 1.90, 0)
        root.addChildNode(hair)

        // Shoes: small dark boxes at the feet, children of the leg pivots so
        // they swing with the walk cycle.
        let shoeGeo = SCNBox(width: 0.17, height: 0.08, length: 0.30, chamferRadius: 0.02)
        shoeGeo.materials = [NodeFactory.material(UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))]
        let shoeL = SCNNode(geometry: shoeGeo)
        shoeL.position = SCNVector3(0, -0.90, 0.05)
        legL.addChildNode(shoeL)
        let shoeR = SCNNode(geometry: shoeGeo)
        shoeR.position = SCNVector3(0, -0.90, 0.05)
        legR.addChildNode(shoeR)

        // Arms (pivot at shoulder, y = 1.58)
        let armGeoL = SCNBox(width: 0.13, height: 0.78, length: 0.15, chamferRadius: 0.02)
        armGeoL.materials = [torsoMaterial]
        let armMeshL = SCNNode(geometry: armGeoL)
        armMeshL.position = SCNVector3(0, -0.36, 0)
        armL.addChildNode(armMeshL)
        armL.position = SCNVector3(-0.34, 1.58, 0)

        let armGeoR = SCNBox(width: 0.13, height: 0.78, length: 0.15, chamferRadius: 0.02)
        armGeoR.materials = [torsoMaterial]
        let armMeshR = SCNNode(geometry: armGeoR)
        armMeshR.position = SCNVector3(0, -0.36, 0)
        armR.addChildNode(armMeshR)
        armR.position = SCNVector3(0.34, 1.58, 0)

        root.addChildNode(legL)
        root.addChildNode(legR)
        root.addChildNode(torso)
        root.addChildNode(head)
        root.addChildNode(armL)
        root.addChildNode(armR)
    }

    // Procedural walk cycle: swing limbs with a sine phase.
    func animateWalk(dt: Float, speedFactor: Float) {
        if speedFactor > 0.05 {
            walkPhase += dt * (4.0 + speedFactor * 5.0)
            let swing = sin(walkPhase) * 0.55 * min(1, speedFactor)
            legL.eulerAngles.x = swing
            legR.eulerAngles.x = -swing
            armL.eulerAngles.x = -swing * 0.8
            armR.eulerAngles.x = swing * 0.8
        } else {
            legL.eulerAngles.x *= 0.8
            legR.eulerAngles.x *= 0.8
            armL.eulerAngles.x *= 0.8
            armR.eulerAngles.x *= 0.8
        }
    }

    func punchPose() {
        armR.eulerAngles.x = -1.5
    }
}

// MARK: - Player

final class PlayerEntity {
    let figure: HumanoidFigure
    var node: SCNNode { return figure.root }
    var heading: Float = 0
    var velocityY: Float = 0
    var isGrounded: Bool = true
    var punchTimer: Double = 0

    init(shirtIndex: Int) {
        figure = HumanoidFigure(
            shirtColor: ShirtColors.color(at: shirtIndex),
            pantsColor: UIColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1),
            skinColor: UIColor(red: 0.78, green: 0.58, blue: 0.44, alpha: 1))
    }

    func setShirt(index: Int) {
        figure.torsoMaterial.diffuse.contents = ShirtColors.color(at: index)
    }
}

// MARK: - Vehicles

class VehicleEntity {
    let node = SCNNode()
    let spec: VehicleSpec
    var heading: Float = 0
    var speed: Float = 0            // signed m/s along heading
    var lateralSpeed: Float = 0     // sideways slide (drift model)
    var health: Float = 100
    var bodyMaterial: SCNMaterial
    var wheelMaterial: SCNMaterial
    var steerVisual: Float = 0
    private var wheelSteerNodes: [SCNNode] = []
    private var wheelSpinNodes: [SCNNode] = []
    private var wheelRadiusValue: Float = 0.36
    private var underglowNode: SCNNode? = nil
    private var underglowMaterial: SCNMaterial? = nil
    private var underglowLightNode: SCNNode? = nil
    var neonIndexValue: Int = 0
    var headlightNode: SCNNode? = nil

    // AI driving state (used by traffic & police, ignored for the player car)
    var aiAxisX: Bool = true
    var aiDirection: Float = 1
    var aiTarget = RoadPoint(x: 0, z: 0)
    var aiSpeedLimit: Float = 12
    var aiDecisionTimer: Double = 0
    var aiStuckTimer: Double = 0
    var aiActive: Bool = true

    // Phase 3: jump-ramp airborne state (used by the driven car only).
    var airborne: Bool = false
    var verticalSpeed: Float = 0   // m/s, positive = rising
    var airTime: Double = 0        // seconds spent airborne this jump

    init(spec: VehicleSpec, paint: UIColor) {
        self.spec = spec
        // PBR finish: metallic clear-coat style paint, chrome rims.
        // bodyMaterial stays THE single shared paint material for every
        // painted part, so garage recoloring recolors the whole car.
        bodyMaterial = NodeFactory.pbrMaterial(paint, metalness: 0.85, roughness: 0.32)
        wheelMaterial = NodeFactory.pbrMaterial(
            UIColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1),
            metalness: 1.0, roughness: 0.15)
        let chromeMat = NodeFactory.pbrMaterial(
            UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1),
            metalness: 1.0, roughness: 0.15)

        let isSUV = spec.id == "suv" || spec.id == "police"
        let isLow = spec.id == "sports" || spec.id == "supercar"
        let isMuscle = spec.id == "muscle"
        let isHatch = spec.id == "hatchback"
        var bodyH: Float = 0.55
        var bodyY: Float = 0.58
        var length: Float = 4.2
        if isSUV {
            bodyH = 0.78
            bodyY = 0.72
        } else if isLow {
            bodyH = 0.48
            bodyY = 0.53
        } else if isMuscle {
            bodyH = 0.62
            bodyY = 0.60
        } else if isHatch {
            bodyH = 0.66
            bodyY = 0.62
        }
        if spec.id == "supercar" {
            length = 4.5
        }
        if isMuscle {
            length = 4.6
        }
        if isHatch {
            length = 3.9
        }

        let bodyGeo = SCNBox(width: 1.82, height: CGFloat(bodyH), length: CGFloat(length),
                             chamferRadius: 0.09)
        bodyGeo.materials = [bodyMaterial]
        let body = SCNNode(geometry: bodyGeo)
        body.position = SCNVector3(0, bodyY, 0)
        body.castShadow = true
        node.addChildNode(body)

        var cabinH: Float = 0.5
        var cabinLen: Float = length * 0.45
        var cabinZ: Float = length * -0.04
        if isHatch {
            // Tallboy cabin for the hatchback: taller, longer, pushed rearward.
            cabinH = 0.58
            cabinLen = length * 0.55
            cabinZ = length * -0.10
        }
        let cabinY = bodyY + bodyH / 2 + 0.22
        let cabinGeo = SCNBox(width: 1.6, height: CGFloat(cabinH), length: CGFloat(cabinLen),
                              chamferRadius: 0.08)
        let glassMat = NodeFactory.pbrMaterial(
            UIColor(red: 0.05, green: 0.08, blue: 0.13, alpha: 1),
            metalness: 0.9, roughness: 0.08)
        // Semi-transparent so the interior cabin shows through the glass.
        glassMat.transparency = 0.55
        cabinGeo.materials = [glassMat]
        let cabin = SCNNode(geometry: cabinGeo)
        cabin.position = SCNVector3(0, cabinY, cabinZ)
        cabin.castShadow = true
        node.addChildNode(cabin)

        // Simple interior cabin (every car): dashboard, two seats and a
        // steering wheel, all inside the cabin volume and sized to it so
        // nothing pokes through the roof.
        let interiorMat = NodeFactory.material(UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1))
        let seatMat = NodeFactory.material(UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
        let cabinBottomY = cabinY - cabinH / 2
        let floorY = cabinBottomY + 0.02
        let cabinFrontZ = cabinZ + cabinLen / 2
        let dashGeo = SCNBox(width: 1.45, height: 0.20, length: 0.38, chamferRadius: 0.03)
        dashGeo.materials = [interiorMat]
        let dash = SCNNode(geometry: dashGeo)
        let dashZ = cabinFrontZ - cabinLen * 0.18
        let dashY = floorY + cabinH * 0.35
        dash.position = SCNVector3(0, dashY, dashZ)
        node.addChildNode(dash)
        let seatXs: [Float] = [-0.45, 0.45]
        for sx in seatXs {
            let baseGeo = SCNBox(width: 0.50, height: 0.16, length: 0.52, chamferRadius: 0.03)
            baseGeo.materials = [seatMat]
            let seatBase = SCNNode(geometry: baseGeo)
            seatBase.position = SCNVector3(sx, floorY + 0.10, cabinFrontZ - cabinLen * 0.55)
            node.addChildNode(seatBase)
            let backH = cabinH * 0.72
            let backGeo = SCNBox(width: 0.50, height: CGFloat(backH), length: 0.16,
                                 chamferRadius: 0.03)
            backGeo.materials = [seatMat]
            let seatBack = SCNNode(geometry: backGeo)
            seatBack.position = SCNVector3(sx, floorY + cabinH * 0.42,
                                           cabinFrontZ - cabinLen * 0.72)
            node.addChildNode(seatBack)
        }
        // Steering wheel in front of the left seat: torus ring + column.
        let wheelGeo = SCNTorus(ringRadius: 0.13, pipeRadius: 0.03)
        wheelGeo.materials = [interiorMat]
        let steerWheel = SCNNode(geometry: wheelGeo)
        let steerZ = cabinFrontZ - cabinLen * 0.38
        let steerY = floorY + cabinH * 0.56
        steerWheel.position = SCNVector3(-0.45, steerY, steerZ)
        steerWheel.eulerAngles.x = -0.45
        node.addChildNode(steerWheel)
        let colGeo = SCNCylinder(radius: 0.03, height: 0.34)
        colGeo.materials = [interiorMat]
        let column = SCNNode(geometry: colGeo)
        column.eulerAngles.x = Float.pi / 2 - 0.45
        column.position = SCNVector3(-0.45, floorY + cabinH * 0.42,
                                     cabinFrontZ - cabinLen * 0.28)
        node.addChildNode(column)

        // Trim details shared by every car.
        let darkTrimMat = NodeFactory.material(UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))
        // Bumpers — painted with the SAME shared bodyMaterial as the body,
        // so a garage respray recolors them too.
        let bumperGeo = SCNBox(width: 1.86, height: 0.24, length: 0.30, chamferRadius: 0.05)
        bumperGeo.materials = [bodyMaterial]
        let bumperF = SCNNode(geometry: bumperGeo)
        bumperF.position = SCNVector3(0, 0.40, length / 2 + 0.06)
        node.addChildNode(bumperF)
        let bumperR = SCNNode(geometry: bumperGeo)
        bumperR.position = SCNVector3(0, 0.40, -length / 2 - 0.06)
        node.addChildNode(bumperR)
        // Front grille (dark) with a chrome strip.
        let grilleGeo = SCNBox(width: 1.15, height: 0.15, length: 0.06, chamferRadius: 0.02)
        grilleGeo.materials = [darkTrimMat]
        let grille = SCNNode(geometry: grilleGeo)
        grille.position = SCNVector3(0, 0.52, length / 2 + 0.02)
        node.addChildNode(grille)
        let stripGeo = SCNBox(width: 1.15, height: 0.045, length: 0.03, chamferRadius: 0.01)
        stripGeo.materials = [chromeMat]
        let strip = SCNNode(geometry: stripGeo)
        strip.position = SCNVector3(0, 0.62, length / 2 + 0.03)
        node.addChildNode(strip)
        // Side skirts + mirrors.
        let mirrorY = bodyY + bodyH / 2 + 0.28
        let mirrorZ = length * 0.16
        for side in [-1, 1] {
            let sx = Float(side)
            let skirtGeo = SCNBox(width: 0.09, height: 0.15, length: CGFloat(length * 0.52),
                                  chamferRadius: 0.02)
            skirtGeo.materials = [darkTrimMat]
            let skirt = SCNNode(geometry: skirtGeo)
            skirt.position = SCNVector3(sx * 0.94, 0.26, 0)
            node.addChildNode(skirt)
            let stalkGeo = SCNBox(width: 0.20, height: 0.045, length: 0.05, chamferRadius: 0.01)
            stalkGeo.materials = [darkTrimMat]
            let stalk = SCNNode(geometry: stalkGeo)
            stalk.position = SCNVector3(sx * 0.98, mirrorY, mirrorZ)
            node.addChildNode(stalk)
            let mirrorGeo = SCNBox(width: 0.08, height: 0.15, length: 0.20, chamferRadius: 0.02)
            mirrorGeo.materials = [bodyMaterial]
            let mirror = SCNNode(geometry: mirrorGeo)
            mirror.position = SCNVector3(sx * 1.09, mirrorY, mirrorZ)
            node.addChildNode(mirror)
        }
        // Exhaust pipe(s): chrome, one on most cars, two on sports/supercar.
        var exhaustXs: [Float] = [-0.55]
        if spec.id == "sports" || spec.id == "supercar" {
            exhaustXs = [-0.55, 0.55]
        }
        for ex in exhaustXs {
            let exGeo = SCNCylinder(radius: 0.05, height: 0.24)
            exGeo.materials = [chromeMat]
            let pipe = SCNNode(geometry: exGeo)
            pipe.eulerAngles.x = Float.pi / 2
            pipe.position = SCNVector3(ex, 0.30, -length / 2 - 0.10)
            node.addChildNode(pipe)
        }
        // Rear license plate (blank, no text).
        let plateGeo = SCNBox(width: 0.54, height: 0.17, length: 0.03, chamferRadius: 0.01)
        plateGeo.materials = [NodeFactory.material(UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1))]
        let plate = SCNNode(geometry: plateGeo)
        plate.position = SCNVector3(0, 0.58, -length / 2 - 0.03)
        node.addChildNode(plate)

        // Extra detail: rear spoiler on sports / supercar, roof box on SUV.
        if spec.id == "sports" || spec.id == "supercar" {
            // Painted rear spoiler: two stands + wing, all in bodyMaterial
            // so resprays recolor the spoiler as well. Supercar wing is wider.
            let spoilerWidth: Float = spec.id == "supercar" ? 1.85 : 1.7
            let wingGeo = SCNBox(width: CGFloat(spoilerWidth), height: 0.07, length: 0.42,
                                 chamferRadius: 0.02)
            wingGeo.materials = [bodyMaterial]
            let spoilerWing = SCNNode(geometry: wingGeo)
            spoilerWing.position = SCNVector3(0, bodyY + 0.42, -length / 2 + 0.25)
            node.addChildNode(spoilerWing)
            let strutGeo = SCNBox(width: 0.09, height: 0.3, length: 0.09, chamferRadius: 0.01)
            strutGeo.materials = [bodyMaterial]
            let strutL = SCNNode(geometry: strutGeo)
            strutL.position = SCNVector3(-0.55, bodyY + 0.22, -length / 2 + 0.25)
            node.addChildNode(strutL)
            let strutR = SCNNode(geometry: strutGeo)
            strutR.position = SCNVector3(0.55, bodyY + 0.22, -length / 2 + 0.25)
            node.addChildNode(strutR)
            // Sloped hood scoop panel on the front top.
            let hoodGeo = SCNBox(width: 1.5, height: 0.10, length: 1.15, chamferRadius: 0.03)
            hoodGeo.materials = [bodyMaterial]
            let hood = SCNNode(geometry: hoodGeo)
            hood.position = SCNVector3(0, bodyY + bodyH / 2 + 0.01, length / 2 - 0.85)
            hood.eulerAngles.x = -0.10
            node.addChildNode(hood)
        }
        if spec.id == "suv" {
            let roofGeo = SCNBox(width: 1.3, height: 0.22, length: 1.9, chamferRadius: 0.05)
            roofGeo.materials = [NodeFactory.material(UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))]
            let roofBox = SCNNode(geometry: roofGeo)
            roofBox.position = SCNVector3(0, bodyY + bodyH / 2 + 0.55, length * -0.04)
            node.addChildNode(roofBox)
            // Roof rails along the cabin top edges.
            let railGeo = SCNBox(width: 0.06, height: 0.05, length: 1.7, chamferRadius: 0.02)
            railGeo.materials = [NodeFactory.material(UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1))]
            let railL = SCNNode(geometry: railGeo)
            railL.position = SCNVector3(-0.70, bodyY + bodyH / 2 + 0.50, length * -0.04)
            node.addChildNode(railL)
            let railR = SCNNode(geometry: railGeo)
            railR.position = SCNVector3(0.70, bodyY + bodyH / 2 + 0.50, length * -0.04)
            node.addChildNode(railR)
        }
        if isMuscle {
            // Twin raised hood scoops on the front hood, in bodyMaterial so
            // garage resprays recolor them.
            let hoodTopY = bodyY + bodyH / 2
            let scoopGeo = SCNBox(width: 0.34, height: 0.14, length: 0.55, chamferRadius: 0.04)
            scoopGeo.materials = [bodyMaterial]
            let scoopXs: [Float] = [-0.38, 0.38]
            for sx in scoopXs {
                let scoop = SCNNode(geometry: scoopGeo)
                scoop.position = SCNVector3(sx, hoodTopY + 0.06, length / 2 - 1.05)
                node.addChildNode(scoop)
            }
            // Dark charcoal center racing stripe along the hood.
            let stripeMat = NodeFactory.material(UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1))
            let stripeGeo = SCNBox(width: 0.42, height: 0.03, length: 1.9, chamferRadius: 0.01)
            stripeGeo.materials = [stripeMat]
            let stripe = SCNNode(geometry: stripeGeo)
            stripe.position = SCNVector3(0, hoodTopY + 0.03, length / 2 - 0.95)
            node.addChildNode(stripe)
        }
        if isHatch {
            // Small roof lip spoiler at the rear top, in bodyMaterial so
            // garage resprays recolor it.
            let lipGeo = SCNBox(width: 1.55, height: 0.07, length: 0.30, chamferRadius: 0.02)
            lipGeo.materials = [bodyMaterial]
            let lip = SCNNode(geometry: lipGeo)
            lip.position = SCNVector3(0, cabinY + cabinH / 2 + 0.02,
                                      cabinZ - cabinLen / 2 + 0.10)
            node.addChildNode(lip)
        }

        // Headlights: emissive rounded boxes behind a high-metalness PBR
        // lens, plus one real spotlight node (enabled at night).
        let lightMat = NodeFactory.material(UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1),
                                            emissive: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1))
        let lensMat = NodeFactory.pbrMaterial(
            UIColor(red: 0.75, green: 0.85, blue: 0.95, alpha: 1),
            metalness: 0.9, roughness: 0.08)
        let hlGeo = SCNBox(width: 0.44, height: 0.13, length: 0.07, chamferRadius: 0.03)
        hlGeo.materials = [lightMat]
        let hlL = SCNNode(geometry: hlGeo)
        hlL.position = SCNVector3(-0.58, bodyY + 0.04, length / 2 + 0.01)
        let hlR = SCNNode(geometry: hlGeo)
        hlR.position = SCNVector3(0.58, bodyY + 0.04, length / 2 + 0.01)
        node.addChildNode(hlL)
        node.addChildNode(hlR)
        let lensGeo = SCNBox(width: 0.46, height: 0.15, length: 0.03, chamferRadius: 0.01)
        lensGeo.materials = [lensMat]
        let lensL = SCNNode(geometry: lensGeo)
        lensL.position = SCNVector3(-0.58, bodyY + 0.04, length / 2 + 0.05)
        let lensR = SCNNode(geometry: lensGeo)
        lensR.position = SCNVector3(0.58, bodyY + 0.04, length / 2 + 0.05)
        node.addChildNode(lensL)
        node.addChildNode(lensR)

        // Full-width emissive red taillight strip.
        let tailMat = NodeFactory.material(UIColor(red: 0.6, green: 0.05, blue: 0.05, alpha: 1),
                                           emissive: UIColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1))
        let tlGeo = SCNBox(width: 1.62, height: 0.09, length: 0.05, chamferRadius: 0.02)
        tlGeo.materials = [tailMat]
        let tlStrip = SCNNode(geometry: tlGeo)
        tlStrip.position = SCNVector3(0, bodyY + 0.06, -length / 2 - 0.01)
        node.addChildNode(tlStrip)

        let spot = SCNLight()
        spot.type = .spot
        spot.color = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        spot.intensity = 0
        spot.spotInnerAngle = 18
        spot.spotOuterAngle = 42
        spot.attenuationEndDistance = 42
        let spotNode = SCNNode()
        spotNode.light = spot
        spotNode.position = SCNVector3(0, 0.8, length / 2)
        spotNode.eulerAngles = SCNVector3(-0.32, Float.pi, 0)
        node.addChildNode(spotNode)
        headlightNode = spotNode

        // Wheels: steer pivot -> spin pivot -> tyre + brake disc + chrome
        // rim + 5 spokes. Everything spins together inside the spin node;
        // front assemblies steer via the steer node.
        let tyreMat = NodeFactory.pbrMaterial(
            UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1),
            metalness: 0.0, roughness: 0.95)
        let discMat = NodeFactory.pbrMaterial(
            UIColor(red: 0.45, green: 0.46, blue: 0.48, alpha: 1),
            metalness: 0.9, roughness: 0.35)
        var wheelRadius: Float = 0.36
        if isSUV {
            wheelRadius = 0.42
        }
        if isHatch {
            wheelRadius = 0.33
        }
        wheelRadiusValue = wheelRadius
        let wheelPositions: [SCNVector3] = [
            SCNVector3(-0.88, wheelRadius, length / 2 - 0.75),
            SCNVector3(0.88, wheelRadius, length / 2 - 0.75),
            SCNVector3(-0.88, wheelRadius, -length / 2 + 0.75),
            SCNVector3(0.88, wheelRadius, -length / 2 + 0.75)
        ]
        var index = 0
        for wp in wheelPositions {
            let steerNode = SCNNode()
            steerNode.position = wp
            let spinNode = SCNNode()
            // Supercar rear tyres are wider.
            let tyreWidth: Float = (spec.id == "supercar" && index >= 2) ? 0.34 : 0.26
            let tyreGeo = SCNCylinder(radius: CGFloat(wheelRadius), height: CGFloat(tyreWidth))
            tyreGeo.materials = [tyreMat]
            let tyre = SCNNode(geometry: tyreGeo)
            tyre.eulerAngles.z = Float.pi / 2
            spinNode.addChildNode(tyre)
            let discGeo = SCNCylinder(radius: CGFloat(wheelRadius * 0.62),
                                      height: CGFloat(tyreWidth + 0.01))
            discGeo.materials = [discMat]
            let disc = SCNNode(geometry: discGeo)
            disc.eulerAngles.z = Float.pi / 2
            spinNode.addChildNode(disc)
            let rimGeo = SCNCylinder(radius: CGFloat(wheelRadius * 0.52),
                                     height: CGFloat(tyreWidth + 0.03))
            rimGeo.materials = [wheelMaterial]
            let rim = SCNNode(geometry: rimGeo)
            rim.eulerAngles.z = Float.pi / 2
            spinNode.addChildNode(rim)
            var spokeIndex = 0
            while spokeIndex < 5 {
                let spokeGeo = SCNBox(width: CGFloat(tyreWidth + 0.02),
                                      height: CGFloat(wheelRadius * 0.92),
                                      length: 0.07, chamferRadius: 0.01)
                spokeGeo.materials = [wheelMaterial]
                let spoke = SCNNode(geometry: spokeGeo)
                spoke.eulerAngles.x = Float(spokeIndex) * Float.pi * 2 / 5
                spinNode.addChildNode(spoke)
                spokeIndex += 1
            }
            steerNode.addChildNode(spinNode)
            node.addChildNode(steerNode)
            if index < 2 { wheelSteerNodes.append(steerNode) }
            wheelSpinNodes.append(spinNode)
            index += 1
        }

        // Underglow neon: a flat emissive plane just above the ground.
        // Hidden by default; setNeon() arms it and setUnderglowNight()
        // shows it at night. The light node is created lazily, only when
        // neon is actually bought (traffic/police cars never get one).
        let glowGeo = SCNPlane(width: 1.7, height: CGFloat(length * 0.8))
        let glowMat = SCNMaterial()
        glowMat.diffuse.contents = UIColor.black
        glowMat.emissive.contents = UIColor.white
        glowGeo.materials = [glowMat]
        let glowNode = SCNNode(geometry: glowGeo)
        glowNode.eulerAngles.x = -Float.pi / 2
        glowNode.position = SCNVector3(0, 0.10, 0)
        glowNode.isHidden = true
        node.addChildNode(glowNode)
        underglowNode = glowNode
        underglowMaterial = glowMat
    }

    func applyTuning(_ tuning: CarTuning) {
        bodyMaterial.diffuse.contents = PaintColors.color(at: tuning.paintIndex)
        wheelMaterial.diffuse.contents = WheelColors.color(at: tuning.wheelIndex)
        setNeon(tuning.neonIndex)
    }

    // Arm the neon underglow: 0 = off, 1...6 = NeonColors index + 1.
    func setNeon(_ index: Int) {
        neonIndexValue = index
        if index <= 0 {
            if let glow = underglowNode {
                glow.isHidden = true
            }
            if let lightNode = underglowLightNode, let light = lightNode.light {
                light.intensity = 0
            }
            return
        }
        let color = NeonColors.color(at: index - 1)
        if let mat = underglowMaterial {
            mat.emissive.contents = color
        }
        if underglowLightNode == nil {
            let light = SCNLight()
            light.type = .omni
            light.color = color
            light.intensity = 0
            light.attenuationStartDistance = 0.5
            light.attenuationEndDistance = 8
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(0, 0.6, 0)
            node.addChildNode(lightNode)
            underglowLightNode = lightNode
        } else {
            if let lightNode = underglowLightNode, let light = lightNode.light {
                light.color = color
            }
        }
    }

    // Show/hide the armed underglow depending on the time of day.
    // No-op when no neon is bought (neonIndexValue == 0).
    func setUnderglowNight(on: Bool) {
        let active = on && neonIndexValue > 0
        if let glow = underglowNode {
            glow.isHidden = !active
        }
        if let lightNode = underglowLightNode, let light = lightNode.light {
            if active {
                light.intensity = 140
            } else {
                light.intensity = 0
            }
        }
    }

    // Effective performance with tuning applied.
    func effectiveTopSpeed() -> Float {
        let t = currentTuningLevels()
        return spec.topSpeed * (1 + 0.08 * Float(t.engine))
    }
    func effectiveAcceleration() -> Float {
        let t = currentTuningLevels()
        return spec.acceleration * (1 + 0.09 * Float(t.engine))
    }
    func effectiveBraking() -> Float {
        let t = currentTuningLevels()
        return spec.braking * (1 + 0.10 * Float(t.brake))
    }
    func effectiveTurning() -> Float {
        let t = currentTuningLevels()
        return spec.turning * (1 + 0.08 * Float(t.handling))
    }
    private var tuningCache = CarTuning()
    func setTuningCache(_ t: CarTuning) { tuningCache = t }
    private func currentTuningLevels() -> (engine: Int, brake: Int, handling: Int) {
        return (tuningCache.engineLevel, tuningCache.brakeLevel, tuningCache.handlingLevel)
    }

    func updateWheels(dt: Float) {
        let spin = speed / wheelRadiusValue * dt
        for s in wheelSpinNodes {
            s.eulerAngles.x += spin
        }
        for s in wheelSteerNodes {
            s.eulerAngles.y = steerVisual * 0.45
        }
    }

    func setHeadlights(on: Bool) {
        if let n = headlightNode, let l = n.light {
            l.intensity = on ? 900 : 0
        }
    }

    var position2D: RoadPoint {
        return RoadPoint(x: node.position.x, z: node.position.z)
    }
}

// MARK: - Traffic car (civilian)

final class TrafficCarEntity: VehicleEntity {
    var brakeLightTimer: Double = 0
    init(paint: UIColor) {
        let specs: [VehicleSpec] = [VehicleCatalog.sedan, VehicleCatalog.suv, VehicleCatalog.sports]
        let pick = specs[Int.random(in: 0..<specs.count)]
        super.init(spec: pick, paint: paint)
    }
}

// MARK: - Police car

final class PoliceCarEntity: VehicleEntity {
    let redMaterial: SCNMaterial
    let blueMaterial: SCNMaterial
    var sirenPhase: Double = 0

    init() {
        redMaterial = NodeFactory.material(UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
                                           emissive: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
        blueMaterial = NodeFactory.material(UIColor(red: 0.1, green: 0.2, blue: 0.95, alpha: 1),
                                            emissive: UIColor(red: 0.1, green: 0.3, blue: 1, alpha: 1))
        super.init(spec: VehicleCatalog.police,
                   paint: UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1))
        // Black doors band + light bar.
        let band = NodeFactory.box(w: 1.84, h: 0.30, d: 2.2,
                                   color: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        band.position = SCNVector3(0, 0.72, 0)
        node.addChildNode(band)
        let barBase = NodeFactory.box(w: 1.1, h: 0.07, d: 0.34,
                                      color: UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        barBase.position = SCNVector3(0, 1.48, -0.1)
        node.addChildNode(barBase)
        let redGeo = SCNBox(width: 0.5, height: 0.12, length: 0.3, chamferRadius: 0.03)
        redGeo.materials = [redMaterial]
        let redNode = SCNNode(geometry: redGeo)
        redNode.position = SCNVector3(-0.28, 1.58, -0.1)
        node.addChildNode(redNode)
        let blueGeo = SCNBox(width: 0.5, height: 0.12, length: 0.3, chamferRadius: 0.03)
        blueGeo.materials = [blueMaterial]
        let blueNode = SCNNode(geometry: blueGeo)
        blueNode.position = SCNVector3(0.28, 1.58, -0.1)
        node.addChildNode(blueNode)
        // Dark push bumper at the front.
        let pushGeo = SCNBox(width: 1.9, height: 0.30, length: 0.18, chamferRadius: 0.03)
        pushGeo.materials = [NodeFactory.material(UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))]
        let push = SCNNode(geometry: pushGeo)
        push.position = SCNVector3(0, 0.45, 2.28)
        node.addChildNode(push)
        // White door panels on both sides (no text / no logos).
        let doorGeo = SCNBox(width: 0.03, height: 0.42, length: 1.05, chamferRadius: 0.01)
        doorGeo.materials = [NodeFactory.material(UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))]
        let doorL = SCNNode(geometry: doorGeo)
        doorL.position = SCNVector3(-0.94, 0.74, 0.15)
        node.addChildNode(doorL)
        let doorR = SCNNode(geometry: doorGeo)
        doorR.position = SCNVector3(0.94, 0.74, 0.15)
        node.addChildNode(doorR)
    }

    func updateSiren(dt: Double, active: Bool) {
        sirenPhase += dt * 6
        let on = sin(sirenPhase) > 0
        if active {
            redMaterial.emissive.contents = on ? UIColor.red : UIColor(red: 0.25, green: 0.02, blue: 0.02, alpha: 1)
            blueMaterial.emissive.contents = on ? UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 1) : UIColor.blue
        } else {
            redMaterial.emissive.contents = UIColor(red: 0.3, green: 0.03, blue: 0.03, alpha: 1)
            blueMaterial.emissive.contents = UIColor(red: 0.03, green: 0.05, blue: 0.35, alpha: 1)
        }
    }
}

// MARK: - Pedestrian

final class PedestrianEntity {
    let figure: HumanoidFigure
    var node: SCNNode { return figure.root }
    var heading: Float = 0
    var speed: Float = 1.1
    var target = RoadPoint(x: 0, z: 0)
    var state: String = "walk"   // walk / wait / flee / down
    var decisionTimer: Double = 0
    var stateTimer: Double = 0
    var health: Float = 100

    init() {
        let shirts: [UIColor] = [
            UIColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1),
            UIColor(red: 0.25, green: 0.45, blue: 0.55, alpha: 1),
            UIColor(red: 0.60, green: 0.55, blue: 0.15, alpha: 1),
            UIColor(red: 0.45, green: 0.20, blue: 0.45, alpha: 1),
            UIColor(red: 0.30, green: 0.55, blue: 0.30, alpha: 1),
            UIColor(red: 0.65, green: 0.30, blue: 0.25, alpha: 1)
        ]
        let pick = shirts[Int.random(in: 0..<shirts.count)]
        figure = HumanoidFigure(
            shirtColor: pick,
            pantsColor: UIColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
            skinColor: UIColor(red: 0.72, green: 0.52, blue: 0.38, alpha: 1))
        speed = Float.random(in: 0.9...1.5)
    }
}

// MARK: - Police helicopter (unlocked at high wanted levels)

final class HelicopterEntity {
    let node = SCNNode()
    private let rotor = SCNNode()
    var heading: Float = 0
    var angle: Float = 0
    var searchCenter = RoadPoint(x: 0, z: 0)
    var spotNode: SCNNode? = nil

    init() {
        let bodyMat = NodeFactory.material(UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
        let bodyGeo = SCNBox(width: 1.9, height: 1.5, length: 4.4, chamferRadius: 0.3)
        bodyGeo.materials = [bodyMat]
        let body = SCNNode(geometry: bodyGeo)
        node.addChildNode(body)
        let tail = NodeFactory.box(w: 0.35, h: 0.35, d: 3.4,
                                   color: UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
        tail.position = SCNVector3(0, 0.25, -3.6)
        node.addChildNode(tail)
        let fin = NodeFactory.box(w: 0.1, h: 0.9, d: 0.5,
                                  color: UIColor(red: 0.75, green: 0.08, blue: 0.10, alpha: 1))
        fin.position = SCNVector3(0, 0.55, -5.2)
        node.addChildNode(fin)
        let rotorGeo = SCNBox(width: 7.6, height: 0.05, length: 0.28, chamferRadius: 0.02)
        rotorGeo.materials = [NodeFactory.material(UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1))]
        let rotorMesh = SCNNode(geometry: rotorGeo)
        rotor.addChildNode(rotorMesh)
        rotor.position = SCNVector3(0, 0.95, 0)
        node.addChildNode(rotor)
        let skidL = NodeFactory.box(w: 0.08, h: 0.08, d: 2.6,
                                    color: UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1))
        skidL.position = SCNVector3(-0.8, -0.95, 0)
        node.addChildNode(skidL)
        let skidR = NodeFactory.box(w: 0.08, h: 0.08, d: 2.6,
                                    color: UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1))
        skidR.position = SCNVector3(0.8, -0.95, 0)
        node.addChildNode(skidR)

        let spot = SCNLight()
        spot.type = .spot
        spot.color = UIColor(red: 1, green: 0.98, blue: 0.9, alpha: 1)
        spot.intensity = 0
        spot.spotInnerAngle = 14
        spot.spotOuterAngle = 30
        spot.attenuationEndDistance = 90
        let sNode = SCNNode()
        sNode.light = spot
        sNode.position = SCNVector3(0, -0.8, 0.6)
        sNode.eulerAngles = SCNVector3(-2.2, Float.pi, 0)
        node.addChildNode(sNode)
        spotNode = sNode
    }

    func updateRotor(dt: Float) {
        rotor.eulerAngles.y += dt * 28
    }

    func setSpotlight(on: Bool) {
        if let n = spotNode, let l = n.light {
            l.intensity = on ? 2600 : 0
        }
    }
}
