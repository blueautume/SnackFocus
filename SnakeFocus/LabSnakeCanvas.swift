import SwiftUI

/// Cosmetic renderers for the design lab. Geometry and collision cells still
/// come from the shared simulation; materials never move the logical snake.
struct LabSnakeCanvas: View {
    let input: LabBoardInput
    let form: LabSnakeForm
    let palette: LabPalette

    var body: some View {
        Canvas { context, size in
            let cell = CGSize(width: size.width / CGFloat(input.configuration.columns),
                              height: size.height / CGFloat(input.configuration.rows))
            let unit = min(cell.width, cell.height)
            let rect = CGRect(origin: .zero, size: size)
            var clipped = context
            clipped.clip(to: Path(rect))
            clipped.fill(Path(rect), with: .color(palette.board))
            drawGrid(in: clipped, size: size, cell: cell)
            drawWalls(in: clipped, cell: cell, unit: unit)

            if form == .pixel {
                drawPixels(in: clipped, size: size)
            } else {
                let groups = LabRenderGeometry.wrappedSamples(input: input).map {
                    projected($0, cell: cell, unit: unit)
                }.filter { !$0.isEmpty }
                for points in groups {
                    switch form {
                    case .ink: drawInk(points, in: clipped, unit: unit)
                    case .neon: drawNeon(points, in: clipped, unit: unit)
                    case .origami: drawPaper(points, in: clipped, unit: unit)
                    default: drawRibbon(points, in: clipped, unit: unit)
                    }
                }
                drawHead(in: clipped, cell: cell, unit: unit)
                drawFood(in: clipped, cell: cell, unit: unit)
            }
        }
        .accessibilityHidden(true)
    }

    private struct StrandPoint {
        let center: CGPoint
        let normal: CGVector
        let radius: CGFloat
        let position: Double
    }

    /// Four samples per logical edge are enough for a continuous outline.
    /// Keep both ends of each wrap-clipped group so there is no long seam.
    private func projected(_ samples: [LabRenderSample], cell: CGSize, unit: CGFloat) -> [StrandPoint] {
        guard !samples.isEmpty else { return [] }
        let step = samples.count > 1_200 ? 3 : 2
        var indices = Array(stride(from: 0, to: samples.count, by: step))
        if indices.last != samples.count - 1 { indices.append(samples.count - 1) }
        return indices.map { index in
            let sample = samples[index]
            let before = samples[max(0, index - 1)].center
            let after = samples[min(samples.count - 1, index + 1)].center
            let dx = (after.x - before.x) * cell.width
            let dy = (after.y - before.y) * cell.height
            let length = max(0.000_1, hypot(dx, dy))
            return StrandPoint(center: CGPoint(x: sample.center.x * cell.width,
                                               y: sample.center.y * cell.height),
                               normal: CGVector(dx: -dy / length, dy: dx / length),
                               radius: min(unit * 0.42, max(unit * 0.025, sample.radius * unit)),
                               position: sample.position)
        }
    }

    private func offset(_ point: StrandPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(x: point.center.x + point.normal.dx * point.radius * fraction,
                y: point.center.y + point.normal.dy * point.radius * fraction)
    }

    /// A single continuous variable-width polygon avoids a chain of beads.
    private func strand(_ points: [StrandPoint], lower: CGFloat = -1,
                        upper: CGFloat = 1) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        if points.count == 1 {
            let radius = first.radius * max(abs(lower), abs(upper))
            return Path(ellipseIn: CGRect(x: first.center.x - radius,
                                         y: first.center.y - radius,
                                         width: radius * 2, height: radius * 2))
        }
        path.move(to: offset(first, by: lower))
        for point in points.dropFirst() { path.addLine(to: offset(point, by: lower)) }
        for point in points.reversed() { path.addLine(to: offset(point, by: upper)) }
        path.closeSubpath()
        return path
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize, cell: CGSize) {
        var path = Path()
        for column in 1..<input.configuration.columns {
            let x = CGFloat(column) * cell.width
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for row in 1..<input.configuration.rows {
            let y = CGFloat(row) * cell.height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        let opacity = form == .ink ? 0.035 : form == .neon ? 0.075 : 0.055
        context.stroke(path, with: .color(palette.ink.opacity(opacity)), lineWidth: 0.5)
        if form == .ink {
            var fibers = Path()
            for index in 0..<160 {
                let x = grain(index * 3 + 1) * size.width
                let y = grain(index * 3 + 2) * size.height
                fibers.move(to: CGPoint(x: x, y: y))
                fibers.addLine(to: CGPoint(x: x + 0.3, y: y + 1.3))
            }
            context.stroke(fibers, with: .color(palette.ink.opacity(0.045)), lineWidth: 0.5)
        }
    }

    private func drawWalls(in context: GraphicsContext, cell: CGSize, unit: CGFloat) {
        var walls = Path()
        var highlights = Path()
        for wall in input.configuration.walls {
            let rect = CGRect(x: CGFloat(wall.x) * cell.width + 0.5,
                              y: CGFloat(wall.y) * cell.height + 0.5,
                              width: max(0, cell.width - 1), height: max(0, cell.height - 1))
            walls.addRect(rect)
            highlights.move(to: CGPoint(x: rect.minX, y: rect.minY))
            highlights.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        context.fill(walls, with: .color(palette.ink.opacity(palette.isDark ? 0.42 : 0.36)))
        context.stroke(highlights, with: .color(palette.surface.opacity(0.25)), lineWidth: max(0.5, unit * 0.045))
    }

    private func drawPixels(in context: GraphicsContext, size: CGSize) {
        let frame = input.frame
        let width = size.width / CGFloat(frame.columns)
        let height = size.height / CGFloat(frame.rows)
        var body = Path()
        var food = Path()
        for index in frame.dots.indices {
            let value = frame.dots[index]
            guard value != 0 else { continue }
            let rect = CGRect(x: CGFloat(index % frame.columns) * width,
                              y: CGFloat(index / frame.columns) * height,
                              width: width, height: height)
            if value == 1 { body.addRect(rect) }
            else if value == 2 { food.addRect(rect) }
        }
        context.fill(body, with: .color(palette.accent), style: FillStyle(antialiased: false))
        context.fill(food, with: .color(palette.accent2), style: FillStyle(antialiased: false))
    }

    private func drawRibbon(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        guard let first = points.first, let last = points.last else { return }
        let outline = strand(points)
        var shadow = context
        shadow.translateBy(x: unit * 0.035, y: unit * 0.065)
        shadow.fill(outline, with: .color(palette.ink.opacity(0.14)))
        context.fill(outline, with: .linearGradient(Gradient(colors: [palette.accent, palette.accent2, palette.accent]),
                                                    startPoint: first.center, endPoint: last.center))
        context.fill(strand(points, lower: -0.95, upper: -0.58), with: .color(palette.ink.opacity(0.15)))
        context.fill(strand(points, lower: 0.08, upper: 0.47),
                     with: .linearGradient(Gradient(colors: [Color.white.opacity(0.64), Color.white.opacity(0.12)]),
                                           startPoint: first.center, endPoint: last.center))
        context.fill(strand(points, lower: 0.16, upper: 0.23), with: .color(Color.white.opacity(0.36)))
    }

    private func drawInk(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        let outline = strand(points)
        context.fill(strand(points, lower: -1.08, upper: 1.08), with: .color(palette.ink.opacity(0.12)))
        context.fill(outline, with: .color(palette.ink.opacity(0.91)))
        context.fill(strand(points, lower: -0.60, upper: -0.13), with: .color(palette.accent.opacity(0.20)))
        var dryBrush = context
        dryBrush.clip(to: outline)
        var fibers = Path()
        // At most 1,200 tiny marks even with a full 384-cell board.
        let step = max(1, points.count / 600)
        for index in stride(from: 0, to: points.count, by: step) {
            let point = points[index]
            let seed = Int((point.position * 37).rounded(.down))
            for lane in 0..<2 {
                let amount = (grain(seed * 7 + lane + 11) * 1.7 - 0.85)
                let start = offset(point, by: amount)
                let length = unit * (0.06 + grain(seed * 11 + lane + 5) * 0.15)
                fibers.move(to: start)
                fibers.addLine(to: CGPoint(x: start.x + point.normal.dy * length,
                                           y: start.y - point.normal.dx * length))
            }
        }
        dryBrush.stroke(fibers, with: .color(palette.board.opacity(0.56)),
                        style: StrokeStyle(lineWidth: max(0.45, unit * 0.025), lineCap: .round))
    }

    private func drawNeon(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        let tube = strand(points, lower: -0.78, upper: 0.78)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: unit * 0.23))
            layer.fill(strand(points, lower: -1.05, upper: 1.05), with: .color(palette.accent.opacity(0.43)))
        }
        context.fill(tube, with: .color(palette.accent))
        context.fill(strand(points, lower: -0.44, upper: 0.44), with: .color(palette.accent2.opacity(0.72)))
        context.fill(strand(points, lower: -0.15, upper: 0.15), with: .color(Color.white.opacity(0.94)))
    }

    private func drawPaper(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        context.fill(strand(points), with: .color(palette.accent))
        guard points.count > 1 else { return }
        // Folds follow the same continuous body; each facet spans about half
        // a logical cell rather than introducing a separate collision shape.
        let step = max(1, points.count / 760)
        var index = 0
        while index < points.count - 1 {
            let end = min(points.count - 1, index + max(2, step))
            let a = points[index], b = points[end]
            let leftA = offset(a, by: -1), rightA = offset(a, by: 1)
            let leftB = offset(b, by: -1), rightB = offset(b, by: 1)
            let ridgeA = offset(a, by: 0.12), ridgeB = offset(b, by: 0.12)
            var light = Path()
            light.move(to: leftA)
            light.addLine(to: leftB)
            light.addLine(to: ridgeB)
            light.addLine(to: ridgeA)
            light.closeSubpath()
            let alternate = Int(a.position * 2) % 2 == 0
            context.fill(light, with: .color(alternate ? palette.accent2 : palette.accent2.opacity(0.70)))
            var facet = Path()
            facet.move(to: rightA)
            facet.addLine(to: rightB)
            facet.addLine(to: ridgeA)
            facet.closeSubpath()
            context.fill(facet, with: .color(palette.ink.opacity(alternate ? 0.23 : 0.12)))
            var fold = Path()
            fold.move(to: leftA)
            fold.addLine(to: ridgeB)
            fold.addLine(to: rightB)
            context.stroke(fold, with: .color(palette.surface.opacity(0.30)), lineWidth: max(0.35, unit * 0.025))
            index = end
        }
    }

    private func drawHead(in context: GraphicsContext, cell: CGSize, unit: CGFloat) {
        guard !input.snake.isEmpty else { return }
        let frame = input.frame
        let heading = frame.headHeading
        let angle = atan2(heading.y, heading.x)
        let x = CGFloat(frame.headCenter.x) * cell.width
        let y = CGFloat(frame.headCenter.y) * cell.height
        let shiftsX: [CGFloat] = input.configuration.wrapsHorizontally ? [-CGFloat(input.configuration.columns), 0, CGFloat(input.configuration.columns)] : [0]
        let shiftsY: [CGFloat] = input.configuration.wrapsVertically ? [-CGFloat(input.configuration.rows), 0, CGFloat(input.configuration.rows)] : [0]
        for sx in shiftsX {
            for sy in shiftsY {
                let center = CGPoint(x: x + sx * cell.width, y: y + sy * cell.height)
                guard center.x > -unit, center.y > -unit,
                      center.x < CGFloat(input.configuration.columns) * cell.width + unit,
                      center.y < CGFloat(input.configuration.rows) * cell.height + unit else { continue }
                var headContext = context
                headContext.translateBy(x: center.x, y: center.y)
                headContext.rotate(by: .radians(angle))
                let headRect = CGRect(x: -unit * 0.31, y: -unit * 0.30,
                                      width: unit * 0.74, height: unit * 0.60)
                let head: Path
                if form == .origami {
                    var polygon = Path()
                    polygon.move(to: CGPoint(x: -unit * 0.30, y: -unit * 0.22))
                    polygon.addLine(to: CGPoint(x: unit * 0.16, y: -unit * 0.31))
                    polygon.addLine(to: CGPoint(x: unit * 0.44, y: -unit * 0.14))
                    polygon.addLine(to: CGPoint(x: unit * 0.44, y: unit * 0.14))
                    polygon.addLine(to: CGPoint(x: unit * 0.16, y: unit * 0.31))
                    polygon.addLine(to: CGPoint(x: -unit * 0.30, y: unit * 0.22))
                    polygon.closeSubpath()
                    head = polygon
                } else {
                    head = Path(roundedRect: headRect, cornerRadius: unit * 0.24)
                }
                let color = form == .ink ? palette.ink : palette.accent
                if form == .neon {
                    headContext.drawLayer { layer in
                        layer.addFilter(.blur(radius: unit * 0.16))
                        layer.fill(head, with: .color(palette.accent.opacity(0.65)))
                    }
                }
                headContext.fill(head, with: .linearGradient(Gradient(colors: [color, form == .ink ? color : palette.accent2]),
                                                             startPoint: CGPoint(x: 0, y: -unit * 0.3),
                                                             endPoint: CGPoint(x: 0, y: unit * 0.3)))
                for side in [CGFloat(-1), CGFloat(1)] {
                    let eye = CGRect(x: unit * 0.13, y: side * unit * 0.17 - unit * 0.06,
                                     width: unit * 0.12, height: unit * 0.12)
                    headContext.fill(Path(ellipseIn: eye), with: .color(form == .ink ? palette.board : Color.white.opacity(0.95)))
                    let pupil = eye.insetBy(dx: unit * 0.033, dy: unit * 0.033).offsetBy(dx: unit * 0.014, dy: 0)
                    headContext.fill(Path(ellipseIn: pupil), with: .color(palette.ink))
                }
            }
        }
    }

    private func drawFood(in context: GraphicsContext, cell: CGSize, unit: CGFloat) {
        guard let food = input.food else { return }
        let center = CGPoint(x: (CGFloat(food.x) + 0.5) * cell.width,
                             y: (CGFloat(food.y) + 0.5) * cell.height)
        let pulse = 0.94 + 0.06 * sin(input.time * 2.2)
        let radius = unit * 0.24 * CGFloat(pulse)
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        let shape: Path
        if form == .origami {
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - radius * 1.15))
            diamond.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + radius * 1.15))
            diamond.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            diamond.closeSubpath()
            shape = diamond
        } else if form == .ink {
            shape = Path(ellipseIn: rect)
        } else {
            shape = Path(roundedRect: rect, cornerRadius: radius * 0.35)
        }
        if form == .neon {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.20))
                layer.fill(Path(ellipseIn: rect.insetBy(dx: -unit * 0.10, dy: -unit * 0.10)),
                           with: .color(palette.accent2.opacity(0.70)))
            }
        }
        context.fill(shape, with: .color(palette.accent2))
        if form != .ink {
            let glint = CGRect(x: center.x - radius * 0.50, y: center.y - radius * 0.60,
                               width: radius * 0.50, height: radius * 0.25)
            context.fill(Path(ellipseIn: glint), with: .color(Color.white.opacity(0.55)))
        }
    }

    /// Stable pseudo-grain: no redraw-time randomness or flickering texture.
    private func grain(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898 + 78.233) * 43_758.5453
        return CGFloat(value - floor(value))
    }
}
