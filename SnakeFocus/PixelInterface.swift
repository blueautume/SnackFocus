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

/// Short controls stay on one line. Body copy uses PixelLabel and wraps freely.
struct PixelControlLabel: View {
    let text: String
    var size: CGFloat = 16

    var body: some View {
        PixelLabel(text: text, size: size)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
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

/// Selection framing is separate from the map: a wall always occupies a real
/// grid cell and keeps the same ink-on-paper appearance as in the game.
struct PixelMapChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(LCD.paper)
            .overlay { Rectangle().strokeBorder(LCD.ink.opacity(selected ? 1 : 0.35), lineWidth: selected ? 3 : 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
            .transaction { $0.animation = nil }
    }
}

struct PixelBoardOutline: View {
    var body: some View {
        Rectangle()
            .strokeBorder(LCD.ink.opacity(0.30), lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Both the thumbnail and the live board draw the exact same occupied cells.
/// Fine inset seams make adjacent wall blocks legible as whole grid squares.
struct PixelWalls: View {
    let configuration: SnakeConfiguration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let unitX = size.width / CGFloat(configuration.columns)
            let unitY = size.height / CGFloat(configuration.rows)
            let seam = 1 / displayScale
            var blocks = Path()
            var seams = Path()
            for wall in configuration.walls {
                let left = (CGFloat(wall.x) * unitX * displayScale).rounded() / displayScale
                let top = (CGFloat(wall.y) * unitY * displayScale).rounded() / displayScale
                let right = (CGFloat(wall.x + 1) * unitX * displayScale).rounded() / displayScale
                let bottom = (CGFloat(wall.y + 1) * unitY * displayScale).rounded() / displayScale
                blocks.addRect(CGRect(x: left, y: top, width: right - left, height: bottom - top))
                seams.addRect(CGRect(x: right - seam, y: top, width: seam, height: bottom - top))
                seams.addRect(CGRect(x: left, y: bottom - seam, width: right - left, height: seam))
            }
            context.fill(blocks, with: .color(LCD.ink))
            context.fill(seams, with: .color(LCD.paper.opacity(0.22)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PixelMapThumbnail: View {
    let configuration: SnakeConfiguration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Canvas { context, size in
                let unitX = size.width / CGFloat(configuration.columns)
                let unitY = size.height / CGFloat(configuration.rows)
                let pixel = 1 / displayScale
                var grid = Path()
                for column in 1..<configuration.columns {
                    let x = (CGFloat(column) * unitX * displayScale).rounded() / displayScale
                    grid.addRect(CGRect(x: x, y: 0, width: pixel, height: size.height))
                }
                for row in 1..<configuration.rows {
                    let y = (CGFloat(row) * unitY * displayScale).rounded() / displayScale
                    grid.addRect(CGRect(x: 0, y: y, width: size.width, height: pixel))
                }
                context.fill(grid, with: .color(LCD.ink.opacity(0.08)))
            }
            PixelWalls(configuration: configuration)
            PixelBoardOutline()
        }
        .background(LCD.paper)
        .accessibilityHidden(true)
    }
}
