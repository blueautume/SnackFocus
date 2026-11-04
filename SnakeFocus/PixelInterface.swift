import SwiftUI

enum LCD {
    private static let paperRGB = SIMD3(0.70, 0.76, 0.49)
    private static let inkRGB = SIMD3(0.13, 0.19, 0.10)
    static let paper = color(paperRGB)
    static let ink = color(inkRGB)

    struct GamePalette {
        let background: Color
        let snake: Color
        let food: Color
        let detailEdge: Color?
        let wall: Color
        let outline: Color

        init(immersion: Double) {
            func blend(_ light: SIMD3<Double>, _ dark: SIMD3<Double>) -> Color {
                LCD.color(light + (dark - light) * immersion)
            }

            background = blend(paperRGB, .zero)
            snake = blend(inkRGB, SIMD3(0.36, 0.42, 0.31))
            food = blend(inkRGB, SIMD3(0.53, 0.42, 0.25))
            // Hold the pixel silhouettes when ink and paper cross in brightness.
            detailEdge = (0 < immersion && immersion < 1) ? LCD.ink.opacity(sin(.pi * immersion)) : nil
            wall = blend(inkRGB, .zero)
            outline = blend(inkRGB, SIMD3(0.19, 0.24, 0.17)).opacity(0.30 + 0.70 * immersion)
        }
    }

    private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}

private struct GamePaletteKey: EnvironmentKey {
    static let defaultValue = LCD.GamePalette(immersion: 0)
}

extension EnvironmentValues {
    var gamePalette: LCD.GamePalette {
        get { self[GamePaletteKey.self] }
        set { self[GamePaletteKey.self] = newValue }
    }
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

/// A small bitmap lock matches the LCD lettering without adding header text.
struct PixelLockIcon: View {
    var body: some View {
        Canvas { context, size in
            let rows: [UInt16] = [
                0x1F8, 0x30C, 0x606, 0x606, 0x606, 0xFFF,
                0xC03, 0xC63, 0xC63, 0xC63, 0xC03, 0xFFF
            ]
            let pixel = size.width / 12
            var dots = Path()
            for (y, row) in rows.enumerated() {
                for x in 0..<12 where row & (1 << (11 - x)) != 0 {
                    dots.addRect(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel,
                                        width: pixel, height: pixel))
                }
            }
            context.fill(dots, with: .foreground)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
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
    @Environment(\.gamePalette) private var palette

    var body: some View {
        Rectangle()
            .strokeBorder(palette.outline, lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Both the thumbnail and the live board draw the exact same occupied cells.
/// Fine inset seams make adjacent wall blocks legible as whole grid squares.
struct PixelWalls: View {
    let configuration: SnakeConfiguration
    @Environment(\.displayScale) private var displayScale
    @Environment(\.gamePalette) private var palette

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
            context.fill(blocks, with: .color(palette.wall))
            context.fill(seams, with: .color(palette.background.opacity(0.22)))
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
