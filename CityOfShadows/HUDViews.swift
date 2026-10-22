import SwiftUI

// MARK: - Minimap (roads, player, police, traffic sample, objective)

struct MinimapView: View {
    let data: MinimapData

    private func mapPoint(x: Float, z: Float, size: CGSize) -> CGPoint {
        let nx = CGFloat((x + 170) / 340) * size.width
        let ny = CGFloat((z + 170) / 340) * size.height
        return CGPoint(x: nx, y: ny)
    }

    var body: some View {
        Canvas { context, size in
            // Background
            let bg = Path(CGRect(origin: .zero, size: size))
            context.fill(bg, with: .color(Color(red: 0.05, green: 0.06, blue: 0.09)))
            // Coast band (south)
            let coastY = CGFloat((GameConfig.coastZ + 170) / 340) * size.height
            var coast = Path()
            coast.addRect(CGRect(x: 0, y: coastY, width: size.width,
                                 height: size.height - coastY))
            context.fill(coast, with: .color(Color(red: 0.10, green: 0.22, blue: 0.38)))
            // Roads
            var roads = Path()
            for ax in RoadNetwork.avenuesX {
                let p = mapPoint(x: ax, z: 0, size: size)
                roads.move(to: CGPoint(x: p.x, y: 0))
                roads.addLine(to: CGPoint(x: p.x, y: size.height))
            }
            for sz in RoadNetwork.streetsZ {
                let p = mapPoint(x: 0, z: sz, size: size)
                roads.move(to: CGPoint(x: 0, y: p.y))
                roads.addLine(to: CGPoint(x: size.width, y: p.y))
            }
            context.stroke(roads, with: .color(Color(red: 0.35, green: 0.37, blue: 0.42)),
                           lineWidth: 1.5)
            // Traffic sample (grey dots)
            for t in data.trafficPoints {
                let px = CGFloat((Float(t.x) + 170) / 340) * size.width
                let py = CGFloat((Float(t.y) + 170) / 340) * size.height
                var dot = Path()
                dot.addEllipse(in: CGRect(x: px - 1.8, y: py - 1.8, width: 3.6, height: 3.6))
                context.fill(dot, with: .color(Color(red: 0.65, green: 0.66, blue: 0.70)))
            }
            // Police (red dots)
            for t in data.policePoints {
                let px = CGFloat((Float(t.x) + 170) / 340) * size.width
                let py = CGFloat((Float(t.y) + 170) / 340) * size.height
                var dot = Path()
                dot.addEllipse(in: CGRect(x: px - 2.6, y: py - 2.6, width: 5.2, height: 5.2))
                context.fill(dot, with: .color(Color(red: 0.95, green: 0.25, blue: 0.25)))
            }
            // Objective (gold ring)
            if data.hasObjective, let o = data.objectivePoint {
                let px = CGFloat((Float(o.x) + 170) / 340) * size.width
                let py = CGFloat((Float(o.y) + 170) / 340) * size.height
                var ring = Path()
                ring.addEllipse(in: CGRect(x: px - 4.5, y: py - 4.5, width: 9, height: 9))
                context.stroke(ring, with: .color(Color(red: 1, green: 0.8, blue: 0.2)),
                               lineWidth: 2)
            }
            // Player arrow (centre dot + heading tick)
            let c = mapPoint(x: data.playerX, z: data.playerZ, size: size)
            var dot = Path()
            dot.addEllipse(in: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4))
            context.fill(dot, with: .color(Color(red: 1, green: 0.9, blue: 0.35)))
            var tick = Path()
            tick.move(to: c)
            tick.addLine(to: CGPoint(x: c.x + CGFloat(sin(data.playerHeading)) * 9,
                                     y: c.y + CGFloat(cos(data.playerHeading)) * 9))
            context.stroke(tick, with: .color(Color(red: 1, green: 0.9, blue: 0.35)),
                           lineWidth: 2)
        }
        .background(Color.black.opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Wanted stars

struct StarsView: View {
    let level: Int

    func starsText() -> String {
        var s = ""
        var i = 0
        while i < 5 {
            s += i < level ? "★" : "☆"
            i += 1
        }
        return s
    }

    var body: some View {
        Text(starsText())
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(level > 0 ? .yellow : .gray)
            .shadow(color: .black, radius: 2)
    }
}

// MARK: - Hold-to-press round button (gas, brake, run, steer...)

struct HoldButton: View {
    let label: String
    var size: CGFloat = 64
    var color: Color = Color(red: 0.16, green: 0.18, blue: 0.24)
    let onPress: (Bool) -> Void
    @State private var pressed: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(pressed ? color.opacity(0.95) : color.opacity(0.72))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
            Text(label)
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        onPress(true)
                    }
                }
                .onEnded { _ in
                    pressed = false
                    onPress(false)
                }
        )
    }
}

// MARK: - Tap button (jump, interact, punch)

struct TapButton: View {
    let label: String
    var size: CGFloat = 64
    var color: Color = Color(red: 0.16, green: 0.18, blue: 0.24)
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.72))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                Text(label)
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Virtual joystick (left thumb)

struct JoystickView: View {
    let input: InputState
    @State private var knobOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 124, height: 124)
                .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1.5))
            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 54, height: 54)
                .offset(knobOffset)
        }
        .frame(width: 124, height: 124)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var dx = value.translation.width
                    var dy = value.translation.height
                    let len = sqrt(dx * dx + dy * dy)
                    let maxR: CGFloat = 42
                    if len > maxR {
                        dx = dx / len * maxR
                        dy = dy / len * maxR
                    }
                    knobOffset = CGSize(width: dx, height: dy)
                    input.joyX = Float(dx / maxR)
                    input.joyY = Float(-dy / maxR)
                }
                .onEnded { _ in
                    knobOffset = .zero
                    input.joyX = 0
                    input.joyY = 0
                }
        )
    }
}

// MARK: - Camera drag surface (middle of the screen)

struct CameraDragView: View {
    let input: InputState
    @State private var lastX: CGFloat = 0
    @State private var lastY: CGFloat = 0

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let dx = value.translation.width - lastX
                        let dy = value.translation.height - lastY
                        lastX = value.translation.width
                        lastY = value.translation.height
                        input.camDragX += Float(dx)
                        input.camDragY += Float(dy)
                    }
                    .onEnded { _ in
                        lastX = 0
                        lastY = 0
                    }
            )
    }
}

// MARK: - Small stat bar (health)

struct StatBar: View {
    let fraction: Float
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.55))
                .frame(width: 110, height: 9)
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: max(2, 110 * CGFloat(min(1, max(0, fraction)))), height: 9)
        }
    }
}
