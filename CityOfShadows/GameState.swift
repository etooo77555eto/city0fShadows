import Foundation
import SwiftUI

// MARK: - Persistent save data (Codable, stored as JSON in UserDefaults)

struct CarTuning: Codable {
    var paintIndex: Int = 0
    var wheelIndex: Int = 0
    var engineLevel: Int = 0
    var brakeLevel: Int = 0
    var handlingLevel: Int = 0
    var neonIndex: Int = 0     // 0 = off, 1...6 = NeonColors index + 1
}

struct GameSettings: Codable {
    var musicVolume: Float = 0.6
    var sfxVolume: Float = 0.8
    var sensitivity: Float = 1.0
    var qualityRaw: Int = 1            // GraphicsQuality raw value
    var weatherPreference: String = "Auto"  // Auto / Clear / Cloudy / Rain / Fog
}

struct SaveData: Codable {
    var version: Int = 1
    var money: Int = GameConfig.startMoney
    var health: Float = GameConfig.maxHealth
    var wantedLevel: Int = 0
    var ownedCarIDs: [String] = ["sedan"]
    var activeCarID: String = "sedan"
    var tuning: [String: CarTuning] = ["sedan": CarTuning()]
    var ownedProperties: [String] = []
    var ownedShirts: [Int] = [0]
    var activeShirtIndex: Int = 0
    var completedMissions: [String] = []
    var decisions: [String: String] = [:]
    var relationships: [String: Int] = [:]
    var settings: GameSettings = GameSettings()
    var raceBestSeconds: [String: Double] = [:]
    var achievements: [String] = []
    var hasStartedGame: Bool = false

    func tuningFor(carID: String) -> CarTuning {
        if let t = tuning[carID] { return t }
        return CarTuning()
    }
}

// MARK: - Runtime input channel.
// SwiftUI controls write here; the SceneKit engine reads every frame.
// Deliberately a plain class (not ObservableObject) — high-frequency writes
// must not trigger SwiftUI view updates.

final class InputState {
    var joyX: Float = 0          // -1 ... 1 strafe/steer blend on foot
    var joyY: Float = 0          // -1 ... 1 forward/back
    var runHeld: Bool = false
    var jumpTap: Bool = false    // consumed by engine
    var interactTap: Bool = false
    var punchTap: Bool = false
    var steer: Float = 0         // -1 ... 1 while driving
    var throttleHeld: Bool = false
    var brakeHeld: Bool = false
    var handbrakeHeld: Bool = false
    var camDragX: Float = 0      // accumulated orbit delta, consumed by engine
    var camDragY: Float = 0
    var paused: Bool = true      // engine idles while menus/panels are open
    var resetSessionToken: Int = 0
    var timeSkipToken: Int = 0
    var healRequestToken: Int = 0  // property rest / hospital
    var repairRequestToken: Int = 0 // garage / shop car repair

    func clearTaps() {
        jumpTap = false
        interactTap = false
        punchTap = false
    }
}

// MARK: - UI-facing dialogue & panels

struct DialogueChoice {
    let label: String
    let decisionKey: String
    let decisionValue: String
    let characterID: String
    let relationshipDelta: Int
}

struct ActiveDialogue {
    let id: String
    let speakerName: String
    let lines: [String]
    var choiceA: DialogueChoice? = nil
    var choiceB: DialogueChoice? = nil
    var endingText: String? = nil   // set for the finale: replaces choices
}

enum OpenPanel: String {
    case none
    case shop
    case dealership
    case garage
    case property
    case clothing
    case pause
    case settings
}

struct MinimapData {
    var playerX: Float = 0
    var playerZ: Float = 0
    var playerHeading: Float = 0
    var policePoints: [CGPoint] = []
    var trafficPoints: [CGPoint] = []
    var objectivePoint: CGPoint? = nil
    var hasObjective: Bool = false
}

// MARK: - GameState

final class GameState: ObservableObject {
    @Published var save: SaveData
    @Published var hasSave: Bool = false

    // Live HUD state, refreshed by the engine (~5 Hz) plus event pushes.
    @Published var speedKmh: Int = 0
    @Published var isDriving: Bool = false
    @Published var healthDisplay: Float = GameConfig.maxHealth
    @Published var moneyDisplay: Int = GameConfig.startMoney
    @Published var wantedStars: Int = 0
    @Published var policeStatusText: String = ""
    @Published var missionTitle: String = ""
    @Published var objectiveText: String = ""
    @Published var interactPrompt: String = ""
    @Published var toast: String = ""
    @Published var minimap: MinimapData = MinimapData()
    @Published var activeDialogue: ActiveDialogue? = nil
    @Published var openPanel: OpenPanel = .none
    @Published var panelPropertyID: String = ""   // property the player is standing at
    @Published var inWorld: Bool = false   // false while the main menu is up

    let input = InputState()
    var dialogueFinishToken: Int = 0       // engine watches this for talk steps
    private var toastToken: Int = 0

    private let saveKey = "cityOfShadows.save.v1"

    init() {
        var loaded = SaveData()
        var found = false
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(SaveData.self, from: data) {
                loaded = decoded
                found = true
            }
        }
        // Migration / sanity fix-ups for older or partial saves.
        if loaded.ownedCarIDs.isEmpty { loaded.ownedCarIDs = ["sedan"] }
        if !loaded.ownedCarIDs.contains(loaded.activeCarID) {
            loaded.activeCarID = loaded.ownedCarIDs[0]
        }
        if loaded.tuning[loaded.activeCarID] == nil {
            loaded.tuning[loaded.activeCarID] = CarTuning()
        }
        self.save = loaded
        self.hasSave = found && loaded.hasStartedGame
        self.moneyDisplay = loaded.money
        self.healthDisplay = loaded.health
    }

    // MARK: Persistence

    func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(save) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    func newGame() {
        var fresh = SaveData()
        fresh.hasStartedGame = true
        save = fresh
        hasSave = true
        moneyDisplay = fresh.money
        healthDisplay = fresh.health
        wantedStars = 0
        persist()
        input.resetSessionToken += 1
    }

    func markStarted() {
        if !save.hasStartedGame {
            save.hasStartedGame = true
            hasSave = true
            persist()
        }
    }

    // MARK: Toasts

    func showToast(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if let s = self {
                if s.toastToken == token { s.toast = "" }
            }
        }
    }

    // MARK: Dialogue resolution

    func resolveDialogue(choice: DialogueChoice?) {
        if let c = choice {
            save.decisions[c.decisionKey] = c.decisionValue
            let current = save.relationships[c.characterID] ?? 0
            save.relationships[c.characterID] = current + c.relationshipDelta
            persist()
        }
        activeDialogue = nil
        dialogueFinishToken += 1
        input.paused = false
    }

    // MARK: Economy actions (called from panels; all validate funds)

    func spend(_ amount: Int) -> Bool {
        if save.money < amount { return false }
        save.money -= amount
        if amount > 0 { SoundManager.shared.cash() }
        moneyDisplay = save.money
        persist()
        return true
    }

    func earn(_ amount: Int) {
        save.money += amount
        moneyDisplay = save.money
        persist()
    }

    func buyMeal() -> String {
        if save.money < GameConfig.mealPrice { return "Not enough money." }
        if !spend(GameConfig.mealPrice) { return "Not enough money." }
        save.health = GameConfig.maxHealth
        healthDisplay = save.health
        persist()
        input.healRequestToken += 1
        return "Meal eaten. Health restored."
    }

    func buyEnergyDrink() -> String {
        if save.money < GameConfig.energyDrinkPrice { return "Not enough money." }
        if !spend(GameConfig.energyDrinkPrice) { return "Not enough money." }
        save.health = min(GameConfig.maxHealth, save.health + 30)
        healthDisplay = save.health
        persist()
        input.healRequestToken += 1
        return "Energy drink: +30 health."
    }

    func buyRepair() -> String {
        if !spend(GameConfig.repairPrice) { return "Not enough money." }
        input.repairRequestToken += 1
        return "Car repaired to full condition."
    }

    func buyCar(id: String) -> String {
        let spec = VehicleCatalog.spec(forID: id)
        if save.ownedCarIDs.contains(id) {
            save.activeCarID = id
            persist()
            return spec.name + " selected. It will be waiting near you."
        }
        if save.money < spec.price { return "Not enough money for the " + spec.name + "." }
        if !spend(spec.price) { return "Not enough money." }
        save.ownedCarIDs.append(id)
        if save.tuning[id] == nil { save.tuning[id] = CarTuning() }
        save.activeCarID = id
        persist()
        unlockAchievement("first_car", silent: true)
        return "You bought the " + spec.name + "!"
    }

    func buyPaint(carID: String, paintIndex: Int) -> String {
        var t = save.tuningFor(carID: carID)
        if t.paintIndex == paintIndex { return "That paint is already applied." }
        if !spend(TuningPrices.paintPrice) { return "Not enough money." }
        t.paintIndex = paintIndex
        save.tuning[carID] = t
        persist()
        return "Paint applied: " + PaintColors.name(at: paintIndex)
    }

    func buyWheels(carID: String, wheelIndex: Int) -> String {
        var t = save.tuningFor(carID: carID)
        if t.wheelIndex == wheelIndex { return "Those wheels are already fitted." }
        if !spend(TuningPrices.wheelPrice) { return "Not enough money." }
        t.wheelIndex = wheelIndex
        save.tuning[carID] = t
        persist()
        return "Wheels fitted: " + WheelColors.name(at: wheelIndex)
    }

    func buyNeon(carID: String, neonIndex: Int) -> String {
        var t = save.tuningFor(carID: carID)
        if t.neonIndex == neonIndex { return "Neon underglow is already set to this." }
        if neonIndex == 0 {
            t.neonIndex = 0
            save.tuning[carID] = t
            persist()
            return "Neon underglow turned off."
        }
        let price = TuningPrices.neonPrice
        if !spend(price) {
            return "Not enough money. Neon underglow costs $" + String(price) + "."
        }
        t.neonIndex = neonIndex
        save.tuning[carID] = t
        persist()
        return "Neon underglow installed: " + NeonColors.name(at: neonIndex - 1) + "."
    }

    func buyUpgrade(carID: String, kind: String) -> String {
        var t = save.tuningFor(carID: carID)
        var level = 0
        if kind == "engine" { level = t.engineLevel }
        if kind == "brake" { level = t.brakeLevel }
        if kind == "handling" { level = t.handlingLevel }
        if level >= TuningPrices.maxLevel { return "Already at max level." }
        let price = TuningPrices.upgradePrice(fromLevel: level)
        if !spend(price) { return "Not enough money. Upgrade costs $" + String(price) + "." }
        if kind == "engine" { t.engineLevel = level + 1 }
        if kind == "brake" { t.brakeLevel = level + 1 }
        if kind == "handling" { t.handlingLevel = level + 1 }
        save.tuning[carID] = t
        persist()
        unlockAchievement("tuner", silent: true)
        return kind.capitalized + " upgraded to level " + String(level + 1) + "."
    }

    func buyProperty(id: String) -> String {
        if save.ownedProperties.contains(id) { return "You already own this property." }
        guard let def = PropertyCatalog.def(forID: id) else { return "Unknown property." }
        if !spend(def.price) { return "Not enough money. It costs $" + String(def.price) + "." }
        save.ownedProperties.append(id)
        persist()
        unlockAchievement("landlord", silent: true)
        return "You bought " + def.name + "! Rest there to heal and save."
    }

    func buyShirt(index: Int) -> String {
        if save.ownedShirts.contains(index) {
            save.activeShirtIndex = index
            persist()
            return "Wearing: " + ShirtColors.name(at: index)
        }
        if !spend(ShirtColors.price) { return "Not enough money." }
        save.ownedShirts.append(index)
        save.activeShirtIndex = index
        persist()
        return "Bought and wearing: " + ShirtColors.name(at: index)
    }

    func unlockAchievement(_ id: String, silent: Bool) {
        if save.achievements.contains(id) { return }
        save.achievements.append(id)
        persist()
        if !silent { showToast("Achievement unlocked!") }
    }

    // MARK: Settings helpers

    func quality() -> GraphicsQuality {
        let q = GraphicsQuality(rawValue: save.settings.qualityRaw)
        if let valid = q { return valid }
        return .medium
    }
}
