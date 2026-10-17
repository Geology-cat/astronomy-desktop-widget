import AppKit

// macOS 10.12 では SwiftUI の Canvas や SF Symbols を使えないため、NSView で描画します。

enum Palette {
    static let primary = NSColor(white: 1, alpha: 0.92)
    static let secondary = NSColor(white: 1, alpha: 0.55)
    static let tertiary = NSColor(white: 1, alpha: 0.35)
    static let cardBackground = NSColor(white: 1, alpha: 0.105)
    static let sun = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    static let moon = NSColor(calibratedRed: 0.76, green: 0.81, blue: 1.0, alpha: 1)
    static let twilight = NSColor(calibratedRed: 0.70, green: 0.75, blue: 1.0, alpha: 1)
    static let darkNight = NSColor(calibratedRed: 0.68, green: 0.60, blue: 1.0, alpha: 1)
    static let moonlit = NSColor(calibratedRed: 0.98, green: 0.89, blue: 0.62, alpha: 0.55)
    static let otherDay = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 1)
}

/// 月の概形です（macOS 13 版の MoonPhaseView と同じ描き方）。
final class MoonPhaseNSView: NSView {
    var phase: Double = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height)
        let rect = NSRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()

        var normalized = phase.truncatingRemainder(dividingBy: 1)
        if normalized < 0 { normalized += 1 }
        let angle = normalized * 2 * .pi
        let radius = diameter / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let illuminated = NSBezierPath()
        let segments = 160

        for index in 0...segments {
            let y = -radius + (2 * radius * CGFloat(index) / CGFloat(segments))
            let limb = sqrt(max(0, radius * radius - y * y))
            let left: CGFloat
            let right: CGFloat
            if angle <= .pi {
                left = CGFloat(cos(angle)) * limb
                right = limb
            } else {
                left = -limb
                right = CGFloat(-cos(angle)) * limb
            }
            illuminated.appendRect(NSRect(
                x: center.x + left,
                y: center.y + y,
                width: max(0.35, right - left),
                height: max(0.6, 2 * radius / CGFloat(segments) + 0.4)
            ))
        }
        NSGraphicsContext.saveGraphicsState()
        illuminated.addClip()
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.86, alpha: 1),
            ending: NSColor(calibratedRed: 0.70, green: 0.74, blue: 0.78, alpha: 1)
        )
        // 座標系が反転しているため、左上→右下へ向かう角度を指定します。
        gradient?.draw(in: rect, angle: 45)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.18).setStroke()
        let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()
    }
}

/// 夜（天文薄明の外）を 1 本の帯で表し、月明かりの区間と暗夜の区間を塗り分けます。
final class DarkNightTimelineView: NSView {
    var span = DateInterval()
    var astronomicalNight: [DateInterval] = []
    var darkIntervals: [DateInterval] = []
    var now = Date()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        let width = bounds.width
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: height / 2, yRadius: height / 2).addClip()

        // 夜の間は、暗夜でなければ月が出ています。
        Palette.moonlit.setFill()
        bounds.fill(using: .sourceOver)

        // 高緯度などで夜の途中に天文薄明が挟まる場合は、その区間を薄く抜きます。
        NSColor(white: 1, alpha: 0.12).setFill()
        for (previous, next) in zip(astronomicalNight, astronomicalNight.dropFirst()) where next.start > previous.end {
            segmentRect(DateInterval(start: previous.end, end: next.start), width: width, height: height)
                .fill(using: .sourceOver)
        }

        let gradient = NSGradient(starting: Palette.darkNight.withAlphaComponent(0.85), ending: Palette.darkNight)
        for interval in darkIntervals {
            gradient?.draw(in: segmentRect(interval, width: width, height: height), angle: 90)
        }

        if span.contains(now) {
            // 現在時刻の位置に小さな目印を置きます。
            let x = fraction(now) * width - 1
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
            shadow.shadowBlurRadius = 1
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func segmentRect(_ interval: DateInterval, width: CGFloat, height: CGFloat) -> NSRect {
        let start = fraction(interval.start) * width
        let end = fraction(interval.end) * width
        return NSRect(x: start, y: 0, width: max(1, end - start), height: height)
    }

    private func fraction(_ date: Date) -> CGFloat {
        guard span.duration > 0 else { return 0 }
        let value = date.timeIntervalSince(span.start) / span.duration
        return CGFloat(min(1, max(0, value)))
    }
}

/// 角丸の背景を持つカードです。
final class CardView: NSView {
    init(cornerRadius: CGFloat, color: NSColor = Palette.cardBackground) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = cornerRadius
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

/// 色付きの小さな丸（凡例）です。
final class DotView: NSView {
    private let color: NSColor

    init(color: NSColor, diameter: CGFloat) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// アイコンです。macOS 11 以降は SF Symbols、それより前は文字記号で表します。
enum Icon {
    static func view(symbol: String, fallback: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSView {
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
               .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) {
            let imageView = NSImageView(image: image)
            imageView.contentTintColor = color
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            return imageView
        }
        let label = NSTextField(labelWithString: fallback)
        label.font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// メニューバー用の三日月アイコンです（テンプレート画像）。
    static func statusBarImage() -> NSImage {
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "天文情報ウィジェット") {
            return image
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 13, height: 13)).fill()
        // 少しずらした円で切り抜いて三日月にします。
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        NSBezierPath(ovalIn: NSRect(x: 6.5, y: 4.5, width: 11, height: 11)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        // 小さな星を 2 つ添えます。
        NSBezierPath(ovalIn: NSRect(x: 13.5, y: 12, width: 2.2, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 15, y: 7.5, width: 1.6, height: 1.6)).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
