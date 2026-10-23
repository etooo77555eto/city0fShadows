import SwiftUI

// MARK: - SceneKit container

struct GameContainer: UIViewControllerRepresentable {
    @EnvironmentObject var state: GameState

    func makeUIViewController(context: Context) -> GameViewController {
        return GameViewController(state: state)
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {
    }
}

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject var state: GameState
    @State private var showCredits: Bool = false

    var body: some View {
        ZStack {
            GameContainer()
                .ignoresSafeArea()

            if state.inWorld {
                CameraDragView(input: state.input)
                    .ignoresSafeArea()
                hudLayer
                controlsLayer
            }

            if !state.toast.isEmpty && state.inWorld {
                VStack {
                    Spacer().frame(height: 54)
                    Text(state.toast)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.72))
                        .cornerRadius(10)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if let dialogue = state.activeDialogue {
                DialogueView(dialogue: dialogue)
                    .id(dialogue.id)
            }

            if state.openPanel != .none {
                panelLayer
            }

            if !state.inWorld {
                mainMenu
            }
        }
        .background(Color.black)
        .onAppear {
            SoundManager.shared.setVolumes(music: state.save.settings.musicVolume,
                                           sfx: state.save.settings.sfxVolume)
            if !state.inWorld {
                SoundManager.shared.startMenuMusic()
            }
        }
    }

    // MARK: HUD

    private var hudLayer: some View {
        ZStack {
            // Top-left: minimap + mission card
            VStack(alignment: .leading, spacing: 6) {
                MinimapView(data: state.minimap)
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.missionTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.85, blue: 0.4))
                        .lineLimit(2)
                    Text(state.objectiveText)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .lineLimit(3)
                }
                .padding(7)
                .frame(width: 218, alignment: .leading)
                .background(Color.black.opacity(0.55))
                .cornerRadius(8)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Top-right: wanted, status, money, health, pause
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    StarsView(level: state.wantedStars)
                    Button(action: openPause) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                if !state.policeStatusText.isEmpty {
                    Text(state.policeStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.45, blue: 0.4))
                }
                Text("$" + String(state.moneyDisplay))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.45, green: 0.95, blue: 0.55))
                StatBar(fraction: state.healthDisplay / GameConfig.maxHealth,
                        color: Color(red: 0.85, green: 0.25, blue: 0.25))
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Bottom-right: speedometer while driving
            if state.isDriving {
                VStack(alignment: .trailing, spacing: 0) {
                    Spacer()
                    Text(String(state.speedKmh))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 3)
                    Text("km/h")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 108)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
            }

            // Bottom-centre: interaction prompt
            if !state.interactPrompt.isEmpty {
                VStack {
                    Spacer()
                    Text(state.interactPrompt)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(red: 1, green: 0.85, blue: 0.35))
                        .cornerRadius(16)
                        .padding(.bottom, 128)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Touch controls

    private var controlsLayer: some View {
        ZStack {
            // Left: joystick
            VStack {
                Spacer()
                JoystickView(input: state.input)
                    .padding(.leading, 22)
                    .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Right: context buttons
            VStack {
                Spacer()
                if state.isDriving {
                    drivingButtons
                } else {
                    footButtons
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private var footButtons: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 10) {
                TapButton(label: "USE", size: 62,
                          color: Color(red: 0.55, green: 0.42, blue: 0.08)) {
                    state.input.interactTap = true
                }
                TapButton(label: "HIT", size: 54,
                          color: Color(red: 0.45, green: 0.14, blue: 0.14)) {
                    state.input.punchTap = true
                }
            }
            VStack(spacing: 10) {
                TapButton(label: "JUMP", size: 58) {
                    state.input.jumpTap = true
                }
                HoldButton(label: "RUN", size: 66,
                           color: Color(red: 0.10, green: 0.32, blue: 0.45)) { pressed in
                    state.input.runHeld = pressed
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private var drivingButtons: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HoldButton(label: "◀", size: 62) { pressed in
                state.input.steer = pressed ? -1 : 0
            }
            HoldButton(label: "▶", size: 62) { pressed in
                state.input.steer = pressed ? 1 : 0
            }
            VStack(spacing: 10) {
                TapButton(label: "EXIT", size: 54,
                          color: Color(red: 0.55, green: 0.42, blue: 0.08)) {
                    state.input.interactTap = true
                }
                HoldButton(label: "DRIFT", size: 56,
                           color: Color(red: 0.35, green: 0.20, blue: 0.45)) { pressed in
                    state.input.handbrakeHeld = pressed
                }
            }
            VStack(spacing: 10) {
                HoldButton(label: "BRK", size: 62,
                           color: Color(red: 0.50, green: 0.16, blue: 0.16)) { pressed in
                    state.input.brakeHeld = pressed
                }
                HoldButton(label: "GAS", size: 74,
                           color: Color(red: 0.12, green: 0.45, blue: 0.25)) { pressed in
                    state.input.throttleHeld = pressed
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    // MARK: Menu & flow helpers

    private func openPause() {
        state.openPanel = .pause
        state.input.paused = true
    }

    private func startPlaying(newGame: Bool) {
        SoundManager.shared.stopMenuMusic()
        if newGame {
            state.newGame()
        } else {
            state.markStarted()
        }
        state.inWorld = true
        state.input.paused = false
        showCredits = false
    }

    private var mainMenu: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Spacer()
                Text("CITY OF SHADOWS")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 0.4, green: 0.6, blue: 1), radius: 12)
                Text("Meridian Bay — an original open-world story in five chapters")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.75, green: 0.78, blue: 0.85))
                Spacer().frame(height: 8)
                if showCredits {
                    creditsCard
                } else {
                    VStack(spacing: 10) {
                        if state.hasSave {
                            menuButton("CONTINUE") { startPlaying(newGame: false) }
                        }
                        menuButton(state.hasSave ? "NEW GAME (RESET SAVE)" : "NEW GAME") {
                            startPlaying(newGame: true)
                        }
                        menuButton("SETTINGS") {
                            state.openPanel = .settings
                        }
                        menuButton("CREDITS") { showCredits = true }
                    }
                }
                Spacer()
                Text("Touch: left stick moves · drag centre to orbit camera · drive with GAS / BRK / ◀ ▶")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 30)
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            SoundManager.shared.click()
            action()
        }) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 300, height: 46)
                .background(Color(red: 0.13, green: 0.16, blue: 0.24).opacity(0.92))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 1, green: 0.85, blue: 0.35).opacity(0.65), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var creditsCard: some View {
        VStack(spacing: 6) {
            Text("CITY OF SHADOWS")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("An original open-world prototype.\nStory, characters and city created for this game.\nBuilt with SceneKit + SwiftUI.\nModels are procedural primitives; driving is arcade physics.")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.8, green: 0.82, blue: 0.88))
                .multilineTextAlignment(.center)
            Button(action: { showCredits = false }) {
                Text("BACK")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.35))
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.95))
        .cornerRadius(12)
    }

    // MARK: Panels dispatcher

    private var panelLayer: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            if state.openPanel == .shop { ShopPanel() }
            if state.openPanel == .dealership { DealershipPanel() }
            if state.openPanel == .garage { GaragePanel() }
            if state.openPanel == .property { PropertyPanel() }
            if state.openPanel == .clothing { ClothingPanel() }
            if state.openPanel == .pause { PausePanel() }
            if state.openPanel == .settings { SettingsPanel() }
        }
    }
}

// MARK: - Dialogue overlay

struct DialogueView: View {
    @EnvironmentObject var state: GameState
    let dialogue: ActiveDialogue
    @State private var lineIndex: Int = 0

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(dialogue.speakerName)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.35))
                if lineIndex < dialogue.lines.count {
                    Text(dialogue.lines[lineIndex])
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(action: advance) {
                            Text(lineIndex == dialogue.lines.count - 1 ? "DONE" : "NEXT ▸")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(red: 1, green: 0.85, blue: 0.35))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else if let ending = dialogue.endingText {
                    Text(ending)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.85, green: 0.90, blue: 1))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(action: { state.resolveDialogue(choice: nil) }) {
                            Text("CLOSE")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(red: 1, green: 0.85, blue: 0.35))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Choose:")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    if let a = dialogue.choiceA {
                        choiceButton(a)
                    }
                    if let b = dialogue.choiceB {
                        choiceButton(b)
                    }
                    if dialogue.choiceA == nil && dialogue.choiceB == nil {
                        Button(action: { state.resolveDialogue(choice: nil) }) {
                            Text("CLOSE")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(red: 1, green: 0.85, blue: 0.35))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12).opacity(0.96))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }

    private func advance() {
        if lineIndex < dialogue.lines.count {
            lineIndex += 1
        }
    }

    private func choiceButton(_ choice: DialogueChoice) -> some View {
        Button(action: { state.resolveDialogue(choice: choice) }) {
            Text(choice.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(red: 0.16, green: 0.20, blue: 0.30))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Panel shell

struct PanelShell<Content: View>: View {
    @EnvironmentObject var state: GameState
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)
                Spacer()
                Text("$" + String(state.moneyDisplay))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.45, green: 0.95, blue: 0.55))
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            ScrollView {
                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 580, height: 330)
        .background(Color(red: 0.08, green: 0.09, blue: 0.13).opacity(0.97))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(red: 1, green: 0.85, blue: 0.35).opacity(0.5), lineWidth: 1))
    }

    func close() {
        state.openPanel = .none
        if state.inWorld {
            state.input.paused = false
        }
    }
}

struct PanelMessage: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 1, green: 0.85, blue: 0.4))
                .padding(.top, 6)
        }
    }
}

struct RowButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: {
            SoundManager.shared.click()
            action()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.72, green: 0.75, blue: 0.82))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(10)
            .background(Color(red: 0.14, green: 0.16, blue: 0.22))
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shop (Fuel & Mart)

struct ShopPanel: View {
    @EnvironmentObject var state: GameState
    @State private var msg: String = ""

    var body: some View {
        PanelShell(title: "FUEL & MART") {
            VStack(alignment: .leading, spacing: 9) {
                RowButton(title: "Hot Meal — $" + String(GameConfig.mealPrice),
                          subtitle: "Restores full health") {
                    msg = state.buyMeal()
                }
                RowButton(title: "Energy Drink — $" + String(GameConfig.energyDrinkPrice),
                          subtitle: "Restores 30 health") {
                    msg = state.buyEnergyDrink()
                }
                RowButton(title: "Full Car Repair — $" + String(GameConfig.repairPrice),
                          subtitle: "Repairs your active car to 100%") {
                    msg = state.buyRepair()
                }
                Text("Deliveries: use the job board outside to earn $" +
                     String(StoryData.deliveryReward) + " per run.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                PanelMessage(text: msg)
            }
        }
    }
}

// MARK: - Dealership

struct DealershipPanel: View {
    @EnvironmentObject var state: GameState
    @State private var msg: String = ""

    func statLine(_ spec: VehicleSpec) -> String {
        let top = Int(spec.topSpeed * 3.6)
        let acc = Int(spec.acceleration)
        let turn = Int(spec.turning * 10)
        let stab = Int(spec.stability * 10)
        return "Top " + String(top) + " km/h · Accel " + String(acc) +
            " · Handling " + String(turn) + "/20 · Grip " + String(stab) + "/10"
    }

    var body: some View {
        PanelShell(title: "HALE MOTORS — DEALERSHIP") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(VehicleCatalog.purchasable, id: \.id) { spec in
                    let owned = state.save.ownedCarIDs.contains(spec.id)
                    let active = state.save.activeCarID == spec.id
                    RowButton(
                        title: spec.name + (active ? " — ACTIVE" : (owned ? " — OWNED" : " — $" + String(spec.price))),
                        subtitle: statLine(spec) + (owned ? " · Tap to select" : " · Tap to buy")
                    ) {
                        msg = state.buyCar(id: spec.id)
                    }
                }
                Text("Your selected car appears near you after purchase. Tuning is per-car and saved.")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                PanelMessage(text: msg)
            }
        }
    }
}

// MARK: - Garage (tuning)

struct GaragePanel: View {
    @EnvironmentObject var state: GameState
    @State private var msg: String = ""

    var body: some View {
        PanelShell(title: "VEGA CUSTOM GARAGE") {
            let carID = state.save.activeCarID
            let spec = VehicleCatalog.spec(forID: carID)
            let tuning = state.save.tuningFor(carID: carID)
            VStack(alignment: .leading, spacing: 10) {
                Text("Tuning: " + spec.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.4))
                Text("PAINT — $" + String(TuningPrices.paintPrice))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    ForEach(0..<PaintColors.names.count, id: \.self) { i in
                        Button(action: { msg = state.buyPaint(carID: carID, paintIndex: i) }) {
                            Circle()
                                .fill(Color(PaintColors.uiColors[i]))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(
                                    tuning.paintIndex == i ? Color.yellow : Color.white.opacity(0.3),
                                    lineWidth: tuning.paintIndex == i ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Current: " + PaintColors.name(at: tuning.paintIndex))
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text("WHEELS — $" + String(TuningPrices.wheelPrice))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    ForEach(0..<WheelColors.names.count, id: \.self) { i in
                        Button(action: { msg = state.buyWheels(carID: carID, wheelIndex: i) }) {
                            Circle()
                                .fill(Color(WheelColors.uiColors[i]))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(
                                    tuning.wheelIndex == i ? Color.yellow : Color.white.opacity(0.3),
                                    lineWidth: tuning.wheelIndex == i ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("NEON UNDERGLOW — $" + String(TuningPrices.neonPrice))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        Button(action: { msg = state.buyNeon(carID: carID, neonIndex: i) }) {
                            Circle()
                                .fill(neonCircleColor(index: i))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(
                                    tuning.neonIndex == i ? Color.yellow : Color.white.opacity(0.3),
                                    lineWidth: tuning.neonIndex == i ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Current: " + (tuning.neonIndex == 0 ? "Off" : NeonColors.name(at: tuning.neonIndex - 1)))
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text("Glows under your car at night. Changing color costs $" + String(TuningPrices.neonPrice) + " — turning it off is free.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                upgradeRow(carID: carID, kind: "engine", label: "Engine", level: tuning.engineLevel)
                upgradeRow(carID: carID, kind: "brake", label: "Brakes", level: tuning.brakeLevel)
                upgradeRow(carID: carID, kind: "handling", label: "Handling", level: tuning.handlingLevel)
                RowButton(title: "Full Repair — $" + String(GameConfig.repairPrice),
                          subtitle: "Restore this car to 100% condition") {
                    msg = state.buyRepair()
                }
                PanelMessage(text: msg)
            }
        }
    }

    private func neonCircleColor(index: Int) -> Color {
        if index == 0 {
            return Color(red: 0.35, green: 0.35, blue: 0.38)
        }
        return Color(NeonColors.uiColors[index - 1])
    }

    private func upgradeRow(carID: String, kind: String, label: String, level: Int) -> some View {
        let maxed = level >= TuningPrices.maxLevel
        let price = maxed ? 0 : TuningPrices.upgradePrice(fromLevel: level)
        return RowButton(
            title: label + " — Level " + String(level) + "/" + String(TuningPrices.maxLevel),
            subtitle: maxed ? "Maxed out" : "Upgrade for $" + String(price) + " (real performance gain)"
        ) {
            msg = state.buyUpgrade(carID: carID, kind: kind)
        }
    }
}

// MARK: - Property

struct PropertyPanel: View {
    @EnvironmentObject var state: GameState
    @State private var msg: String = ""

    var body: some View {
        PanelShell(title: "PROPERTY") {
            VStack(alignment: .leading, spacing: 9) {
                if let def = PropertyCatalog.def(forID: state.panelPropertyID) {
                    propertyRow(def)
                } else {
                    ForEach(PropertyCatalog.all, id: \.id) { def in
                        propertyRow(def)
                    }
                }
                PanelMessage(text: msg)
            }
        }
    }

    private func propertyRow(_ def: PropertyDef) -> some View {
        let owned = state.save.ownedProperties.contains(def.id)
        return VStack(alignment: .leading, spacing: 6) {
            RowButton(
                title: def.name + (owned ? " — OWNED" : " — $" + String(def.price)),
                subtitle: def.detail + (owned ? " · Tap to rest" : " · Tap to buy")
            ) {
                if owned {
                    state.save.health = GameConfig.maxHealth
                    state.healthDisplay = GameConfig.maxHealth
                    state.input.healRequestToken += 1
                    state.persist()
                    msg = "Rested at " + def.name + ". Health restored, progress saved."
                } else {
                    msg = state.buyProperty(id: def.id)
                }
            }
        }
    }
}

// MARK: - Clothing

struct ClothingPanel: View {
    @EnvironmentObject var state: GameState
    @State private var msg: String = ""

    var body: some View {
        PanelShell(title: "THREAD & CO. — CLOTHING") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(0..<ShirtColors.names.count, id: \.self) { i in
                    let owned = state.save.ownedShirts.contains(i)
                    let active = state.save.activeShirtIndex == i
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(ShirtColors.uiColors[i]))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        RowButton(
                            title: ShirtColors.name(at: i) + (active ? " — WEARING" : (owned ? " — OWNED" : " — $" + String(ShirtColors.price))),
                            subtitle: owned ? "Tap to wear" : "Tap to buy & wear"
                        ) {
                            msg = state.buyShirt(index: i)
                        }
                    }
                }
                PanelMessage(text: msg)
            }
        }
    }
}

// MARK: - Pause

struct PausePanel: View {
    @EnvironmentObject var state: GameState

    var body: some View {
        PanelShell(title: "PAUSED") {
            VStack(alignment: .leading, spacing: 9) {
                RowButton(title: "Resume", subtitle: "Back to the streets") {
                    state.openPanel = .none
                    state.input.paused = false
                }
                RowButton(title: "Settings", subtitle: "Quality, controls, weather, time") {
                    state.openPanel = .settings
                }
                RowButton(title: "Restart Session", subtitle: "Respawn in the city (save is kept)") {
                    state.input.resetSessionToken += 1
                    state.openPanel = .none
                    state.input.paused = false
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievements")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(achievementsText())
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.72, green: 0.75, blue: 0.82))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.14, green: 0.16, blue: 0.22))
                .cornerRadius(9)
                RowButton(title: "Quit to Main Menu", subtitle: "Progress is saved automatically") {
                    SoundManager.shared.stopAllLoops()
                    SoundManager.shared.startMenuMusic()
                    state.persist()
                    state.openPanel = .none
                    state.inWorld = false
                    state.input.paused = true
                }
            }
        }
    }

    private func achievementsText() -> String {
        let names: [String: String] = [
            "first_mission": "First Steps", "shadow": "City of Shadows (story complete)",
            "first_car": "New Ride", "tuner": "Tuner", "landlord": "Landlord",
            "racer": "Street Racer", "courier": "Courier", "escape": "Ghost (escaped police)"
        ]
        var unlocked: [String] = []
        for a in state.save.achievements {
            unlocked.append(names[a] ?? a)
        }
        if unlocked.isEmpty { return "None yet — play missions, races and deliveries." }
        return unlocked.joined(separator: " · ")
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @EnvironmentObject var state: GameState
    @State private var qualityIdx: Int = 1
    @State private var sensitivity: Double = 1.0
    @State private var musicVol: Double = 0.6
    @State private var sfxVol: Double = 0.8
    @State private var weatherPref: String = "Auto"
    @State private var loaded: Bool = false

    var body: some View {
        PanelShell(title: "SETTINGS") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Graphics quality (traffic & crowd density apply live; AA applies next launch)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Picker("Quality", selection: $qualityIdx) {
                    Text("Low").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: qualityIdx) { _ in writeSettings() }

                Text("Camera sensitivity: " + String(format: "%.1f", sensitivity))
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Slider(value: $sensitivity, in: 0.4...2.0, step: 0.1)
                    .onChange(of: sensitivity) { _ in writeSettings() }

                Text("Weather")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Picker("Weather", selection: $weatherPref) {
                    Text("Auto").tag("Auto")
                    Text("Clear").tag("Clear")
                    Text("Cloudy").tag("Cloudy")
                    Text("Rain").tag("Rain")
                    Text("Fog").tag("Fog")
                }
                .pickerStyle(.segmented)
                .onChange(of: weatherPref) { _ in writeSettings() }

                Text("Volume — music " + String(format: "%.0f%%", musicVol * 100) +
                     " · effects " + String(format: "%.0f%%", sfxVol * 100))
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Slider(value: $musicVol, in: 0...1, step: 0.05)
                    .onChange(of: musicVol) { _ in writeSettings() }
                Slider(value: $sfxVol, in: 0...1, step: 0.05)
                    .onChange(of: sfxVol) { _ in writeSettings() }
                Text("Volumes control the synthesized audio pack: menu music, city ambience, engine, sirens, rain and effects.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)

                RowButton(title: "Skip Time (+6 hours)", subtitle: "Jump the city clock forward") {
                    state.input.timeSkipToken += 1
                }
                RowButton(title: "Close Settings", subtitle: "Return") {
                    if state.inWorld {
                        state.openPanel = .pause
                    } else {
                        state.openPanel = .none
                    }
                }
            }
        }
        .onAppear {
            if !loaded {
                loaded = true
                qualityIdx = state.save.settings.qualityRaw
                sensitivity = Double(state.save.settings.sensitivity)
                musicVol = Double(state.save.settings.musicVolume)
                sfxVol = Double(state.save.settings.sfxVolume)
                weatherPref = state.save.settings.weatherPreference
            }
        }
    }

    private func writeSettings() {
        state.save.settings.qualityRaw = qualityIdx
        state.save.settings.sensitivity = Float(sensitivity)
        state.save.settings.musicVolume = Float(musicVol)
        state.save.settings.sfxVolume = Float(sfxVol)
        state.save.settings.weatherPreference = weatherPref
        state.persist()
    }
}
