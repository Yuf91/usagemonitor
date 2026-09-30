import AppKit

/// Animated menu-bar icons, drawn in code as template images so they follow light/dark menu bars.
/// Every style loops seamlessly over one `phase` cycle (0…2π).
enum IconStyle: String, CaseIterable, Identifiable {
    case cat, rocket, coffee, heartbeat, ghost, pinwheel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cat: "跑步貓"
        case .rocket: "火箭"
        case .coffee: "咖啡"
        case .heartbeat: "心跳"
        case .ghost: "小幽靈"
        case .pinwheel: "風車"
        }
    }
    var frameCount: Int {
        switch self {
        case .cat, .rocket: 8
        case .coffee, .ghost: 10
        case .heartbeat, .pinwheel: 12
        }
    }
    var frames: [NSImage] { MenuIcon.frames(for: self) }
}

enum MenuIcon {
    static let size = NSSize(width: 24, height: 16)
    private static var cache: [IconStyle: [NSImage]] = [:]

    static func frames(for style: IconStyle) -> [NSImage] {
        if let frames = cache[style] { return frames }
        let frames = (0..<style.frameCount).map { frame(style, phase: Double($0) / Double(style.frameCount) * 2 * .pi) }
        cache[style] = frames
        return frames
    }

    /// Seconds per frame: calm when usage is low, frantic when it is nearly used up.
    static func frameInterval(usedPercent: Double?) -> TimeInterval {
        guard let used = usedPercent, used.isFinite else { return 0.16 }
        return 0.22 - 0.16 * min(max(used, 0), 100) / 100
    }

    static func frame(_ style: IconStyle, phase: Double) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill(); NSColor.black.setStroke()
            switch style {
            case .cat: drawCat(phase)
            case .rocket: drawRocket(phase)
            case .coffee: drawCoffee(phase)
            case .heartbeat: drawHeartbeat(phase)
            case .ghost: drawGhost(phase)
            case .pinwheel: drawPinwheel(phase)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AI 用量"
        return image
    }

    /// Punches transparent holes (eyes, windows) into what is already drawn.
    private static func cutOut(_ draw: () -> Void) {
        NSGraphicsContext.current?.compositingOperation = .clear
        draw()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func drawCat(_ phase: Double) {
        let bob = CGFloat(max(0, sin(phase * 2))) * 0.7
        let tilt = CGFloat(sin(phase)) * 0.4

        // Stubby legs first so the round body overlaps their tops
        func leg(_ x: CGFloat, _ angle: Double) {
            let path = NSBezierPath()
            path.lineWidth = 2.3; path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: 5 + bob))
            path.line(to: NSPoint(x: x + 3 * CGFloat(sin(angle)), y: max(1.2, 5 + bob - 3 * CGFloat(cos(angle)) - (angle < -0.2 ? 0 : 1) * bob)))
            path.stroke()
        }
        let swing = 0.65
        leg(6.4, -swing * sin(phase)); leg(8.4, -swing * sin(phase - 0.7))
        leg(12.2, swing * sin(phase)); leg(14.2, swing * sin(phase - 0.7))

        // Curly tail
        let tail = NSBezierPath()
        tail.lineWidth = 1.8; tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: 5.5, y: 7.5 + bob))
        tail.curve(to: NSPoint(x: 3.2 - tilt, y: 12.2 + bob),
                   controlPoint1: NSPoint(x: 1.2, y: 7.4 + bob),
                   controlPoint2: NSPoint(x: 1.2 - tilt, y: 11.6 + bob))
        tail.stroke()

        // Bean body and big round head
        NSBezierPath(ovalIn: NSRect(x: 4.4, y: 3.6 + bob, width: 10.6, height: 6.4)).fill()
        let head = NSPoint(x: 16.4, y: 9 + bob)
        NSBezierPath(ovalIn: NSRect(x: head.x - 4.6, y: head.y - 3.9, width: 9.2, height: 7.8)).fill()
        for dx: CGFloat in [-2.7, 2.7] {
            let ear = NSBezierPath()
            ear.lineWidth = 1; ear.lineJoinStyle = .round
            ear.move(to: NSPoint(x: head.x + dx - 2.1, y: head.y + 2))
            ear.line(to: NSPoint(x: head.x + dx * 1.15 + tilt * 0.5, y: head.y + 5.2))
            ear.line(to: NSPoint(x: head.x + dx + 2.1, y: head.y + 2))
            ear.close(); ear.fill(); ear.stroke()
        }
        cutOut {
            for dx: CGFloat in [-1.6, 2.2] {
                NSBezierPath(ovalIn: NSRect(x: head.x + dx - 0.75, y: head.y - 0.5, width: 1.5, height: 1.9)).fill()
            }
        }
    }

    /// Rocket flying right with a flickering flame and passing speed lines.
    private static func drawRocket(_ phase: Double) {
        let shake = CGFloat(sin(phase * 2)) * 0.5
        let y = 8 + shake

        // Flame: length flickers at two frequencies so it never looks mechanical
        let length = 3.6 + 1.4 * CGFloat(sin(phase * 3)) + 0.6 * CGFloat(sin(phase * 5 + 1))
        let flame = NSBezierPath()
        flame.move(to: NSPoint(x: 8.5, y: y + 1.6))
        flame.curve(to: NSPoint(x: 8.5 - length, y: y), controlPoint1: NSPoint(x: 7, y: y + 1.8), controlPoint2: NSPoint(x: 8.5 - length * 0.6, y: y + 0.8))
        flame.curve(to: NSPoint(x: 8.5, y: y - 1.6), controlPoint1: NSPoint(x: 8.5 - length * 0.6, y: y - 0.8), controlPoint2: NSPoint(x: 7, y: y - 1.8))
        flame.close()
        NSColor.black.withAlphaComponent(0.7).setFill(); flame.fill()
        NSColor.black.setFill()

        // Speed lines drifting left
        let drift = CGFloat(phase / (2 * .pi)) * 7
        for (row, offset) in [(2.6, 0.0), (13.4, 3.5)] as [(CGFloat, CGFloat)] {
            let x = 7.5 - (drift + offset).truncatingRemainder(dividingBy: 7)
            let line = NSBezierPath()
            line.lineWidth = 1.1; line.lineCapStyle = .round
            line.move(to: NSPoint(x: max(x - 2.4, 0.8), y: row)); line.line(to: NSPoint(x: x, y: row))
            line.stroke()
        }

        // Fins, then the body with a pointed nose
        for sign: CGFloat in [1, -1] {
            let fin = NSBezierPath()
            fin.move(to: NSPoint(x: 9, y: y + 2.4 * sign))
            fin.line(to: NSPoint(x: 12.5, y: y + 2.4 * sign))
            fin.line(to: NSPoint(x: 8.2, y: y + 5.6 * sign))
            fin.close(); fin.fill()
        }
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 8.5, y: y - 2.6))
        body.line(to: NSPoint(x: 16.5, y: y - 2.6))
        body.curve(to: NSPoint(x: 22.5, y: y), controlPoint1: NSPoint(x: 19.5, y: y - 2.6), controlPoint2: NSPoint(x: 21.5, y: y - 1.4))
        body.curve(to: NSPoint(x: 16.5, y: y + 2.6), controlPoint1: NSPoint(x: 21.5, y: y + 1.4), controlPoint2: NSPoint(x: 19.5, y: y + 2.6))
        body.line(to: NSPoint(x: 8.5, y: y + 2.6))
        body.close(); body.fill()
        cutOut { NSBezierPath(ovalIn: NSRect(x: 14.2, y: y - 1.3, width: 2.6, height: 2.6)).fill() }
    }

    /// Coffee cup with three wisps of steam rising.
    private static func drawCoffee(_ phase: Double) {
        let saucer = NSBezierPath()
        saucer.lineWidth = 1.3; saucer.lineCapStyle = .round
        saucer.move(to: NSPoint(x: 3.5, y: 1.2)); saucer.line(to: NSPoint(x: 17.5, y: 1.2))
        saucer.stroke()

        let handle = NSBezierPath(ovalIn: NSRect(x: 13.6, y: 4, width: 5.2, height: 4.4))
        handle.lineWidth = 1.6; handle.stroke()
        NSBezierPath(roundedRect: NSRect(x: 5, y: 2.2, width: 10.5, height: 7.2), xRadius: 2.2, yRadius: 2.2).fill()

        // Crests travel upward as the phase advances
        for (index, base) in [7.6, 10.25, 12.9].enumerated() {
            let wisp = NSBezierPath()
            wisp.lineWidth = 1.1; wisp.lineCapStyle = .round
            var first = true
            for step in 0...16 {
                let y = 10.8 + Double(step) * 0.28
                let fade = Double(step) / 16
                let x = base + (0.3 + 0.4 * fade) * sin(y * 1.6 - phase + Double(index) * 2.1)
                let point = NSPoint(x: x, y: y)
                if first { wisp.move(to: point); first = false } else { wisp.line(to: point) }
            }
            NSColor.black.withAlphaComponent(index == 1 ? 0.9 : 0.65).setStroke()
            wisp.stroke()
        }
    }

    /// Pulsing heart next to a scrolling ECG trace.
    private static func drawHeartbeat(_ phase: Double) {
        let beat = pow(max(0, sin(phase)), 6) + 0.6 * pow(max(0, sin(phase - 0.9)), 6)
        let scale = CGFloat(1 + 0.22 * beat)
        let center = NSPoint(x: 5, y: 8)
        let heart = NSBezierPath()
        heart.move(to: NSPoint(x: center.x, y: center.y - 3.9 * scale))
        heart.curve(to: NSPoint(x: center.x, y: center.y + 1.9 * scale),
                    controlPoint1: NSPoint(x: center.x - 6.2 * scale, y: center.y + 0.4 * scale),
                    controlPoint2: NSPoint(x: center.x - 2.6 * scale, y: center.y + 5.4 * scale))
        heart.curve(to: NSPoint(x: center.x, y: center.y - 3.9 * scale),
                    controlPoint1: NSPoint(x: center.x + 2.6 * scale, y: center.y + 5.4 * scale),
                    controlPoint2: NSPoint(x: center.x + 6.2 * scale, y: center.y + 0.4 * scale))
        heart.fill()

        // One ECG period as (position, height) knots; the trace scrolls left by exactly one period per cycle
        let knots: [(Double, Double)] = [(0, 0), (2.5, 0), (3.3, 1), (4.1, 0), (5, 0), (5.8, 6.4), (6.8, -4.6), (7.6, 0), (9.4, 0), (10.4, 1.4), (11.6, 0), (13, 0)]
        let period = 13.0, start = 11.0, end = 23.5
        let shift = phase / (2 * .pi) * period
        func height(_ u: Double) -> Double {
            for (a, b) in zip(knots, knots.dropFirst()) where u <= b.0 {
                return a.1 + (b.1 - a.1) * (u - a.0) / (b.0 - a.0)
            }
            return 0
        }
        let trace = NSBezierPath()
        trace.lineWidth = 1.3; trace.lineJoinStyle = .round; trace.lineCapStyle = .round
        var x = start
        while x <= end {
            let u = (x - start + shift).truncatingRemainder(dividingBy: period)
            let point = NSPoint(x: x, y: 8 + height(u))
            if x == start { trace.move(to: point) } else { trace.line(to: point) }
            x += 0.25
        }
        trace.stroke()
    }

    /// Floating ghost with a rippling hem.
    private static func drawGhost(_ phase: Double) {
        let float = CGFloat(sin(phase)) * 1.1
        let sway = CGFloat(sin(phase)) * 0.6
        let center = NSPoint(x: 12 + sway, y: 9.2 + float)
        let radius: CGFloat = 5.4
        let ghost = NSBezierPath()
        ghost.move(to: NSPoint(x: center.x - radius, y: center.y))
        ghost.appendArc(withCenter: center, radius: radius, startAngle: 180, endAngle: 0, clockwise: true)
        let hem = 3.2 + float
        ghost.line(to: NSPoint(x: center.x + radius, y: hem))
        let wave = 2 * radius / 3
        var x = center.x + radius
        while x >= center.x - radius {
            ghost.line(to: NSPoint(x: x, y: hem + 1.1 * CGFloat(sin(Double((x - center.x) / wave) * 2 * .pi + phase))))
            x -= 0.4
        }
        ghost.close(); ghost.fill()

        // Little arms waving opposite the sway
        for sign: CGFloat in [-1, 1] {
            let arm = NSBezierPath()
            arm.lineWidth = 1.5; arm.lineCapStyle = .round
            arm.move(to: NSPoint(x: center.x + sign * (radius - 0.5), y: center.y - 1.5))
            arm.line(to: NSPoint(x: center.x + sign * (radius + 1.6), y: center.y - 0.3 + sign * sway * 1.5))
            arm.stroke()
        }
        cutOut {
            for dx: CGFloat in [-2, 2] {
                NSBezierPath(ovalIn: NSRect(x: center.x + dx - 0.85, y: center.y - 0.3, width: 1.7, height: 2.3)).fill()
            }
            NSBezierPath(ovalIn: NSRect(x: center.x - 0.8, y: center.y - 3, width: 1.6, height: 1.8)).fill()
        }
    }

    /// Four-blade pinwheel on a stick; alternating shades make the spin readable.
    private static func drawPinwheel(_ phase: Double) {
        let hub = NSPoint(x: 12, y: 9.6)
        let stick = NSBezierPath()
        stick.lineWidth = 1.4; stick.lineCapStyle = .round
        stick.move(to: hub); stick.line(to: NSPoint(x: 12, y: 0.8))
        stick.stroke()

        // Two-fold symmetric (shade alternates), so half a turn per cycle loops seamlessly
        let rotation = -phase / 2
        for blade in 0..<4 {
            let angle = rotation + Double(blade) * .pi / 2
            func point(_ a: Double, _ r: Double) -> NSPoint { NSPoint(x: hub.x + r * cos(a), y: hub.y + r * sin(a)) }
            let path = NSBezierPath()
            path.move(to: hub)
            path.line(to: point(angle, 6))
            path.curve(to: point(angle + 1.1, 3.4), controlPoint1: point(angle + 0.45, 6), controlPoint2: point(angle + 0.9, 4.8))
            path.close()
            NSColor.black.withAlphaComponent(blade.isMultiple(of: 2) ? 1 : 0.55).setFill()
            path.fill()
        }
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: hub.x - 1.1, y: hub.y - 1.1, width: 2.2, height: 2.2)).fill()
    }
}
