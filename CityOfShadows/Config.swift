import Foundation
import UIKit
import SceneKit

// MARK: - Global tuning constants for CITY OF SHADOWS.
// Everything gameplay-related that a designer might want to tweak lives here.

enum GameConfig {
    // City layout (metres). Roads sit on a regular grid.
    static let cityHalf: Float = 150.0          // city spans -150 ... +150
    static let roadHalfWidth: Float = 6.0       // roads are 12 m wide
    static let sidewalkHeight: Float = 0.18
    static let coastZ: Float = 138.0            // sand starts here (south, +Z)
    static let waterZ: Float = 166.0            // water plane starts here

    // Player
    static let walkSpeed: Float = 3.2
    static let runSpeed: Float = 6.4
    static let jumpVelocity: Float = 5.2
    static let gravity: Float = -13.5
    static let playerRadius: Float = 0.45
    static let maxHealth: Float = 100.0

    // Day cycle
    static let dayLengthSeconds: Double = 300.0 // one full 24h cycle
    static let startHour: Float = 16.5           // late afternoon into night

    // Wanted / police tuning (Part 2 systems)
    static let policeVisionDistance: Float = 55.0
    static let helicopterVisionDistance: Float = 85.0
    static let loseSightBaseSeconds: Double = 7.0
    static let searchRadiusStart: Float = 45.0
    static let searchRadiusMax: Float = 110.0
    static let arrestDistance: Float = 2.3
    static let arrestSeconds: Double = 2.5
    static let wantedDecaySeconds: Double = 26.0 // hidden time to drop one star

    // Police unit counts per wanted level (index 0 unused).
    static let policeCountPerLevel: [Int] = [0, 1, 2, 3, 4, 5]
    // Police top-speed factor per wanted level (of the interceptor spec).
    static let policeSpeedFactor: [Float] = [0, 0.90, 0.95, 1.0, 1.05, 1.12]
    // Police steering aggression per wanted level.
    static let policeAggression: [Float] = [0, 0.55, 0.7, 0.85, 0.95, 1.0]

    // Phase 3: police roadblocks, jump ramps and convoy events.
    static let roadblockMinLevel: Int = 3
    static let roadblockAheadDistance: Float = 55.0   // deploy this far ahead of the car
    static let roadblockMinDeployDistance: Float = 38.0 // never closer than this
    static let roadblockRedeploySeconds: Double = 45.0 // cooldown after one clears
    static let rampTriggerSpeed: Float = 12.0          // m/s needed to launch off a ramp
    static let rampLaunchFactor: Float = 0.55          // vertical speed = |speed| * factor
    static let rampRewardPerAirSecond: Int = 120       // $ per airborne second
    static let rampMinAirTime: Double = 0.35           // shorter hops earn nothing
    static let convoyCarCount: Int = 3
    static let convoySpeed: Float = 6.5                // slow parade speed (m/s)
    static let convoyDuration: Double = 45.0          // seconds the convoy stays in the world

    // Economy
    static let startMoney: Int = 1200
    static let arrestFineBase: Int = 150
    static let arrestFinePerStar: Int = 100
    static let mealPrice: Int = 20
    static let energyDrinkPrice: Int = 10
    static let repairPrice: Int = 120

    // Performance caps by quality raw value (0 Low, 1 Medium, 2 High)
    static let trafficCap: [Int] = [4, 7, 10]
    static let pedestrianCap: [Int] = [6, 10, 14]
    static let cullDistance: [Float] = [120, 175, 240]
}

// MARK: - Vehicle catalogue

struct VehicleSpec {
    let id: String
    let name: String
    let price: Int
    let topSpeed: Float      // m/s
    let acceleration: Float  // m/s^2 at full throttle
    let braking: Float       // m/s^2
    let turning: Float       // steering responsiveness (rad/s at speed)
    let stability: Float     // 0...1 grip
    let drift: Float         // 0...1 handbrake slide factor
    let isPolice: Bool
}

enum VehicleCatalog {
    static let sedan = VehicleSpec(id: "sedan", name: "Vega Sedan", price: 0,
        topSpeed: 38, acceleration: 9.5, braking: 18, turning: 1.55,
        stability: 0.72, drift: 0.40, isPolice: false)
    static let suv = VehicleSpec(id: "suv", name: "Bison SUV", price: 9000,
        topSpeed: 43, acceleration: 10.5, braking: 17, turning: 1.25,
        stability: 0.86, drift: 0.25, isPolice: false)
    static let sports = VehicleSpec(id: "sports", name: "Falco GT", price: 12000,
        topSpeed: 54, acceleration: 14.5, braking: 22, turning: 1.75,
        stability: 0.66, drift: 0.62, isPolice: false)
    static let supercar = VehicleSpec(id: "supercar", name: "Nyx Hyper", price: 45000,
        topSpeed: 69, acceleration: 19.5, braking: 26, turning: 1.95,
        stability: 0.60, drift: 0.72, isPolice: false)
    static let muscle = VehicleSpec(id: "muscle", name: "Ravage V8", price: 22000,
        topSpeed: 60, acceleration: 17.0, braking: 19, turning: 1.50,
        stability: 0.62, drift: 0.75, isPolice: false)
    static let hatchback = VehicleSpec(id: "hatchback", name: "Komo Hatch", price: 6000,
        topSpeed: 42, acceleration: 12.0, braking: 19, turning: 1.85,
        stability: 0.78, drift: 0.45, isPolice: false)
    static let police = VehicleSpec(id: "police", name: "Interceptor", price: 0,
        topSpeed: 56, acceleration: 15.0, braking: 23, turning: 1.8,
        stability: 0.78, drift: 0.35, isPolice: true)

    static let purchasable: [VehicleSpec] = [sedan, suv, sports, muscle, hatchback, supercar]
    static let all: [VehicleSpec] = [sedan, suv, sports, muscle, hatchback, supercar, police]

    static func spec(forID id: String) -> VehicleSpec {
        for s in all {
            if s.id == id { return s }
        }
        return sedan
    }
}

// MARK: - Tuning

struct TuningPrices {
    static let paintPrice: Int = 250
    static let wheelPrice: Int = 150
    static let neonPrice: Int = 600
    // Cost to go from level n to n+1 for engine / brakes / handling.
    static func upgradePrice(fromLevel level: Int) -> Int {
        return 400 + level * 350
    }
    static let maxLevel: Int = 3
}

enum PaintColors {
    static let uiColors: [UIColor] = [
        UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1), // shadow black
        UIColor(red: 0.75, green: 0.08, blue: 0.10, alpha: 1), // crimson
        UIColor(red: 0.08, green: 0.25, blue: 0.75, alpha: 1), // deep blue
        UIColor(red: 0.85, green: 0.65, blue: 0.10, alpha: 1), // taxi gold
        UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1), // emerald
        UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1), // pearl white
        UIColor(red: 0.45, green: 0.10, blue: 0.60, alpha: 1), // violet
        UIColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 1)  // burnt orange
    ]
    static let names: [String] = ["Shadow", "Crimson", "Deep Blue", "Gold",
                                  "Emerald", "Pearl", "Violet", "Ember"]
    static func color(at index: Int) -> UIColor {
        if index < 0 || index >= uiColors.count { return uiColors[0] }
        return uiColors[index]
    }
    static func name(at index: Int) -> String {
        if index < 0 || index >= names.count { return names[0] }
        return names[index]
    }
}

enum WheelColors {
    static let uiColors: [UIColor] = [
        UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
        UIColor(red: 0.75, green: 0.76, blue: 0.80, alpha: 1),
        UIColor(red: 0.85, green: 0.65, blue: 0.10, alpha: 1),
        UIColor(red: 0.60, green: 0.05, blue: 0.05, alpha: 1)
    ]
    static let names: [String] = ["Black", "Silver", "Gold", "Dark Red"]
    static func color(at index: Int) -> UIColor {
        if index < 0 || index >= uiColors.count { return uiColors[0] }
        return uiColors[index]
    }
    static func name(at index: Int) -> String {
        if index < 0 || index >= names.count { return names[0] }
        return names[index]
    }
}

// Underglow neon: 6 glow colours for the garage mod. Index 0 in the
// garage UI means "off"; colours live at 1...6 and map to 0...5 here.
enum NeonColors {
    static let uiColors: [UIColor] = [
        UIColor(red: 0.00, green: 1.00, blue: 1.00, alpha: 1), // neon cyan
        UIColor(red: 1.00, green: 0.10, blue: 0.90, alpha: 1), // neon magenta
        UIColor(red: 0.45, green: 1.00, blue: 0.10, alpha: 1), // neon lime
        UIColor(red: 1.00, green: 0.42, blue: 0.05, alpha: 1), // neon ember
        UIColor(red: 0.62, green: 0.20, blue: 1.00, alpha: 1), // neon violet
        UIColor(red: 0.60, green: 0.85, blue: 1.00, alpha: 1)  // ice blue
    ]
    static let names: [String] = ["Neon Cyan", "Neon Magenta", "Neon Lime",
                                  "Neon Ember", "Neon Violet", "Ice Blue"]
    static func color(at index: Int) -> UIColor {
        if index < 0 || index >= uiColors.count { return uiColors[0] }
        return uiColors[index]
    }
    static func name(at index: Int) -> String {
        if index < 0 || index >= names.count { return names[0] }
        return names[index]
    }
}

enum ShirtColors {
    static let uiColors: [UIColor] = [
        UIColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1), // default navy
        UIColor(red: 0.65, green: 0.10, blue: 0.12, alpha: 1),
        UIColor(red: 0.15, green: 0.45, blue: 0.20, alpha: 1),
        UIColor(red: 0.85, green: 0.80, blue: 0.75, alpha: 1),
        UIColor(red: 0.35, green: 0.15, blue: 0.55, alpha: 1),
        UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)
    ]
    static let names: [String] = ["Navy Jacket", "Red Jacket", "Green Jacket",
                                  "Beige Jacket", "Violet Jacket", "Amber Jacket"]
    static let price: Int = 150
    static func color(at index: Int) -> UIColor {
        if index < 0 || index >= uiColors.count { return uiColors[0] }
        return uiColors[index]
    }
    static func name(at index: Int) -> String {
        if index < 0 || index >= names.count { return names[0] }
        return names[index]
    }
}

// MARK: - Properties catalogue

struct PropertyDef {
    let id: String
    let name: String
    let detail: String
    let price: Int
    let x: Float
    let z: Float
}

enum PropertyCatalog {
    static let all: [PropertyDef] = [
        PropertyDef(id: "house_bayview", name: "Bayview House",
                    detail: "Quiet house in the residential quarter. Safehouse + garage.",
                    price: 8000, x: -120, z: -114),
        PropertyDef(id: "apt_downtown", name: "Meridian Apartment",
                    detail: "Midtown apartment above the avenue. Safehouse.",
                    price: 15000, x: 6, z: -120),
        PropertyDef(id: "condo_coast", name: "Azure Coast Condo",
                    detail: "Luxury condo on the promenade. Safehouse + prestige.",
                    price: 40000, x: 114, z: 120)
    ]
    static func def(forID id: String) -> PropertyDef? {
        for p in all {
            if p.id == id { return p }
        }
        return nil
    }
}

// MARK: - Quality

enum GraphicsQuality: Int, Codable {
    case low = 0
    case medium = 1
    case high = 2
    var label: String {
        if self == .low { return "Low" }
        if self == .medium { return "Medium" }
        return "High"
    }
}

enum WeatherKind: String, Codable {
    case clear = "Clear"
    case cloudy = "Cloudy"
    case rain = "Rain"
    case fog = "Fog"
}

// MARK: - Procedural texture loading
// Textures are generated in CI by tools/generate_textures.py into
// CityOfShadows/Textures/ and copied into the bundle as a folder reference.
// Loading is defensive: any missing texture falls back to a flat colour.

enum TextureLoader {
    static func image(named name: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: name, ofType: "jpg",
                                       inDirectory: "Textures") {
            return UIImage(contentsOfFile: path)
        }
        if let path = Bundle.main.path(forResource: name, ofType: "jpg") {
            return UIImage(contentsOfFile: path)
        }
        return UIImage(named: name)
    }

    static func apply(to material: SCNMaterial, texture name: String, fallback: UIColor) {
        if let img = image(named: name) {
            material.diffuse.contents = img
        } else {
            material.diffuse.contents = fallback
        }
    }

    static func texturedMaterial(texture: String, fallback: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        apply(to: m, texture: texture, fallback: fallback)
        // PBR facade finish: matte masonry/glass with IBL reflections.
        m.lightingModel = .physicallyBased
        m.metalness.contents = NSNumber(value: 0.0)
        m.roughness.contents = NSNumber(value: 0.85)
        return m
    }

    // For ground planes: tiled texture with repeat wrapping.
    static func groundMaterial(texture: String, fallback: UIColor,
                               repeatScale: Float) -> SCNMaterial {
        let m = SCNMaterial()
        apply(to: m, texture: texture, fallback: fallback)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatScale, repeatScale, 1)
        m.lightingModel = .physicallyBased
        m.metalness.contents = NSNumber(value: 0.0)
        m.roughness.contents = NSNumber(value: 0.95)
        return m
    }
}
