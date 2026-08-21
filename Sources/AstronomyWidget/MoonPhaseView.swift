import SwiftUI

struct MoonPhaseView: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let rect = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.08, green: 0.10, blue: 0.15)))

            let normalized = phase.truncatingRemainder(dividingBy: 1) < 0
                ? phase.truncatingRemainder(dividingBy: 1) + 1
                : phase.truncatingRemainder(dividingBy: 1)
            let angle = normalized * 2 * .pi
            let radius = diameter / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var illuminated = Path()
            let segments = 160

            for index in 0...segments {
                let y = -radius + (2 * radius * CGFloat(index) / CGFloat(segments))
                let limb = sqrt(max(0, radius * radius - y * y))
                let terminator: CGFloat
                let left: CGFloat
                let right: CGFloat
                if angle <= .pi {
                    terminator = CGFloat(cos(angle)) * limb
                    left = terminator
                    right = limb
                } else {
                    terminator = CGFloat(-cos(angle)) * limb
                    left = -limb
                    right = terminator
                }
                let lineRect = CGRect(
                    x: center.x + left,
                    y: center.y + y,
                    width: max(0.35, right - left),
                    height: max(0.6, 2 * radius / CGFloat(segments) + 0.4)
                )
                illuminated.addRect(lineRect)
            }
            context.fill(illuminated, with: .linearGradient(
                Gradient(colors: [Color(red: 0.92, green: 0.93, blue: 0.86), Color(red: 0.70, green: 0.74, blue: 0.78)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            ))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
        .accessibilityLabel("月の概形")
        .accessibilityValue(accessibilityPhaseName)
    }

    private var accessibilityPhaseName: String {
        switch phase {
        case 0..<0.03, 0.97...1: return "新月"
        case 0.03..<0.22: return "満ちていく三日月"
        case 0.22..<0.28: return "上弦"
        case 0.28..<0.47: return "満ちていく月"
        case 0.47..<0.53: return "満月"
        case 0.53..<0.72: return "欠けていく月"
        case 0.72..<0.78: return "下弦"
        default: return "欠けていく三日月"
        }
    }
}
