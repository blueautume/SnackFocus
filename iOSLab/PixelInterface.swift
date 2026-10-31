import SwiftUI

enum LCD {
    static let paper = Color(red: 0.70, green: 0.76, blue: 0.49)
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.10)
}

struct PixelLabel: View {
    let text: String
    var size: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.custom("Fusion-Pixel-12px-Mono-zh-Hans-Regular", size: size))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PixelButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        let inverted = emphasized || configuration.isPressed
        configuration.label
            .foregroundStyle(inverted ? LCD.paper : LCD.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(inverted ? LCD.ink : LCD.paper)
            .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
            .background { Rectangle().fill(LCD.ink).offset(x: 3, y: 3) }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .contentShape(Rectangle())
            .transaction { $0.animation = nil }
    }
}

struct PixelChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? LCD.paper : LCD.ink)
            .background(selected ? LCD.ink : LCD.paper)
            .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: selected ? 3 : 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
            .transaction { $0.animation = nil }
    }
}

/// Solid pixel walls versus broken, traversable edges use the same vocabulary
/// in map thumbnails and in the actual game field.
struct PixelBoundary: View {
    let configuration: SnakeConfiguration
    var color = LCD.ink

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 1.5
            let left = inset
            let right = size.width - inset
            let top = inset
            let bottom = size.height - inset
            let sides: [(CGPoint, CGPoint, Bool)] = [
                (CGPoint(x: left, y: top), CGPoint(x: right, y: top), !configuration.wrapsVertically),
                (CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom), !configuration.wrapsVertically),
                (CGPoint(x: left, y: top), CGPoint(x: left, y: bottom), !configuration.wrapsHorizontally),
                (CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), !configuration.wrapsHorizontally)
            ]
            for (start, end, wall) in sides {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(color.opacity(wall ? 1 : 0.50)),
                               style: StrokeStyle(lineWidth: wall ? 3 : 1, lineCap: .butt,
                                                  dash: wall ? [] : [2, 3]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PixelMapThumbnail: View {
    let configuration: SnakeConfiguration
    var selected = false

    var body: some View {
        ZStack {
            Canvas { context, size in
                let points = [CGPoint(x: 0.22, y: 0.72), CGPoint(x: 0.22, y: 0.28),
                              CGPoint(x: 0.48, y: 0.28), CGPoint(x: 0.48, y: 0.60),
                              CGPoint(x: 0.76, y: 0.60), CGPoint(x: 0.76, y: 0.20)]
                let color = selected ? LCD.paper : LCD.ink
                for index in 1..<points.count {
                    let a = CGPoint(x: points[index - 1].x * size.width, y: points[index - 1].y * size.height)
                    let b = CGPoint(x: points[index].x * size.width, y: points[index].y * size.height)
                    let count = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 2))
                    for step in 0...count {
                        let t = CGFloat(step) / CGFloat(count)
                        let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                        context.fill(Path(CGRect(x: point.x.rounded(), y: point.y.rounded(), width: 2, height: 2)),
                                     with: .color(color))
                    }
                }
            }
            PixelBoundary(configuration: configuration, color: selected ? LCD.paper : LCD.ink)
        }
        .accessibilityHidden(true)
    }
}
