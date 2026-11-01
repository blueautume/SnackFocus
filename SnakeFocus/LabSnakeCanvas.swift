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
            // Shadows and neon bloom obey the same occupied wall cells as
            // the body. Painting a translucent wall on top is insufficient.
            var playable = Path(rect)
            for wall in input.configuration.walls {
                playable.addRect(CGRect(x: CGFloat(wall.x) * cell.width,
                                        y: CGFloat(wall.y) * cell.height,
                                        width: cell.width, height: cell.height))
            }
            var snakeContext = clipped
            snakeContext.clip(to: playable, style: FillStyle(eoFill: true, antialiased: false))

            if form == .pixel {
                drawPixels(in: snakeContext, size: size, cell: cell, unit: unit)
            } else {
                let groups = LabRenderGeometry.wrappedSamples(input: input).map {
                    projected($0, cell: cell, unit: unit)
                }.filter { !$0.isEmpty }
                for points in groups {
                    switch form {
                    case .ink: drawInk(points, in: snakeContext, unit: unit)
                    case .neon: drawNeon(points, in: snakeContext, unit: unit)
                    case .origami: drawPaper(points, in: snakeContext, unit: unit)
                    default: drawRibbon(points, in: snakeContext, unit: unit)
                    }
                }
                var bodyMask = Path()
                for points in groups { bodyMask.addPath(strand(points)) }
                var materialContext = snakeContext
                materialContext.clip(to: bodyMask)
                drawMaterialMarks(in: materialContext, cell: cell, unit: unit)
                drawHead(in: snakeContext, cell: cell, unit: unit)
                drawFood(in: snakeContext, cell: cell, unit: unit)
            }
            drawWalls(in: clipped, cell: cell, unit: unit)
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

    private func drawPixels(in context: GraphicsContext, size: CGSize, cell: CGSize, unit: CGFloat) {
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
        var materialContext = context
        materialContext.clip(to: body, style: FillStyle(antialiased: false))
        drawMaterialMarks(in: materialContext, cell: cell, unit: unit)
        context.fill(food, with: .color(palette.accent2), style: FillStyle(antialiased: false))
    }

    private func drawRibbon(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        guard !points.isEmpty else { return }
        let outline = strand(points)
        var shadow = context
        shadow.translateBy(x: unit * 0.035, y: unit * 0.065)
        shadow.fill(outline, with: .color(palette.ink.opacity(0.14)))
        context.fill(outline, with: .color(palette.accent))
        context.fill(strand(points, lower: -0.95, upper: -0.58), with: .color(palette.ink.opacity(0.15)))
        context.fill(strand(points, lower: -0.18, upper: 0.58), with: .color(palette.accent2.opacity(0.38)))
        context.fill(strand(points, lower: 0.16, upper: 0.27), with: .color(Color.white.opacity(0.20)))
    }

    private func drawInk(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        let outline = strand(points)
        context.fill(strand(points, lower: -1.08, upper: 1.08), with: .color(palette.ink.opacity(0.12)))
        context.fill(outline, with: .color(palette.ink.opacity(0.91)))
        context.fill(strand(points, lower: -0.60, upper: -0.13), with: .color(palette.accent.opacity(0.20)))
    }

    private func drawNeon(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        let tube = strand(points, lower: -0.78, upper: 0.78)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: unit * 0.23))
            layer.fill(strand(points, lower: -1.05, upper: 1.05), with: .color(palette.accent.opacity(0.43)))
        }
        context.fill(tube, with: .color(palette.accent))
        context.fill(strand(points, lower: -0.44, upper: 0.44), with: .color(palette.accent2.opacity(0.72)))
        context.fill(strand(points, lower: -0.15, upper: 0.15), with: .color(Color.white.opacity(0.34)))
    }

    private func drawPaper(_ points: [StrandPoint], in context: GraphicsContext, unit: CGFloat) {
        context.fill(strand(points), with: .color(palette.accent))
        context.fill(strand(points, lower: -1, upper: -0.05), with: .color(palette.accent2.opacity(0.38)))
    }

    /// Material coordinates are sampled on the complete head-to-tail path
    /// before wrapping. Neither a new strip nor a seam starts a new pattern.
    /// A fixed mark travels with the body, so straight middle sections remain
    /// visibly alive without an unrelated clock or a scrolling UV offset.
    private func drawMaterialMarks(in context: GraphicsContext, cell: CGSize, unit: CGFloat) {
        let spacing: Double
        switch form {
        case .pixel: spacing = 0.80
        case .ink: spacing = 0.62
        case .neon: spacing = 1.10
        case .origami: spacing = 0.66
        default: spacing = 1.00
        }
        let marks = LabRenderGeometry.materialMarks(input: input, spacing: spacing)
        for mark in marks {
            let radius = min(unit * 0.42, mark.radius * unit)
            guard radius > unit * 0.07 else { continue }
            let center = CGPoint(x: mark.center.x * cell.width, y: mark.center.y * cell.height)
            let angle = atan2(mark.tangent.y * cell.height, mark.tangent.x * cell.width)
            let seed = Int((mark.position * 1_000).rounded())
            if form == .pixel {
                // Quantize to the original 7-dot cell lattice instead of
                // drawing a smooth decoration over the coarse pixel body.
                let dot = CGSize(width: cell.width / CGFloat(SnakeVisualGeometry.pixelsPerCell),
                                 height: cell.height / CGFloat(SnakeVisualGeometry.pixelsPerCell))
                let normal = CGPoint(x: -sin(angle), y: cos(angle))
                let x = center.x - normal.x * radius * 0.24
                let y = center.y - normal.y * radius * 0.24
                let scale = Path(CGRect(x: (x / dot.width).rounded(.down) * dot.width,
                                        y: (y / dot.height).rounded(.down) * dot.height,
                                        width: dot.width, height: dot.height))
                // A single light scale preserves a continuous 3-dot body;
                // two dark holes could visually sever a narrow pixel turn.
                context.fill(scale, with: .color(Color.white.opacity(0.62)), style: FillStyle(antialiased: false))
                continue
            }
            var material = context
            material.translateBy(x: center.x, y: center.y)
            material.rotate(by: .radians(angle))
            switch form {
            case .ink:
                var flecks = Path()
                for lane in 0..<4 {
                    let x = (grain(seed + lane * 17) - 0.5) * unit * 0.24
                    let y = (grain(seed + lane * 31 + 7) - 0.5) * radius * 1.50
                    let length = unit * (0.12 + grain(seed + lane * 11 + 3) * 0.16)
                    flecks.move(to: CGPoint(x: x - length / 2, y: y))
                    flecks.addLine(to: CGPoint(x: x + length / 2, y: y + radius * 0.05))
                }
                material.stroke(flecks, with: .color(palette.board.opacity(0.68)),
                                style: StrokeStyle(lineWidth: max(0.55, unit * 0.043), lineCap: .round))
                let wash = CGRect(x: -unit * 0.12, y: radius * 0.35,
                                  width: unit * 0.25, height: radius * 0.20)
                material.fill(Path(ellipseIn: wash), with: .color(palette.accent2.opacity(0.38)))
            case .neon:
                let segment = CGRect(x: -unit * 0.19, y: -radius * 0.43,
                                     width: unit * 0.38, height: radius * 0.86)
                material.fill(Path(roundedRect: segment, cornerRadius: radius * 0.35),
                              with: .color(palette.accent2.opacity(0.88)))
                let core = CGRect(x: -unit * 0.17, y: -radius * 0.19,
                                  width: unit * 0.34, height: radius * 0.38)
                material.fill(Path(roundedRect: core, cornerRadius: radius * 0.18),
                              with: .color(Color.white.opacity(0.98)))
            case .origami:
                let halfLength = unit * 0.29
                var light = Path()
                light.move(to: CGPoint(x: -halfLength, y: -radius))
                light.addLine(to: CGPoint(x: halfLength, y: -radius * 0.83))
                light.addLine(to: CGPoint(x: halfLength * 0.52, y: radius * 0.10))
                light.addLine(to: CGPoint(x: -halfLength, y: radius * 0.03))
                light.closeSubpath()
                material.fill(light, with: .color(palette.accent2.opacity(0.93)))
                var shade = Path()
                shade.move(to: CGPoint(x: -halfLength, y: radius * 0.03))
                shade.addLine(to: CGPoint(x: halfLength * 0.52, y: radius * 0.10))
                shade.addLine(to: CGPoint(x: halfLength, y: radius * 0.85))
                shade.addLine(to: CGPoint(x: -halfLength, y: radius))
                shade.closeSubpath()
                material.fill(shade, with: .color(palette.ink.opacity(0.24)))
                var crease = Path()
                crease.move(to: CGPoint(x: -halfLength, y: -radius))
                crease.addLine(to: CGPoint(x: halfLength * 0.52, y: radius * 0.10))
                crease.addLine(to: CGPoint(x: -halfLength, y: radius))
                material.stroke(crease, with: .color(palette.surface.opacity(0.63)),
                                lineWidth: max(0.45, unit * 0.035))
            default:
                var glint = Path()
                glint.move(to: CGPoint(x: -unit * 0.14, y: -radius * 0.76))
                glint.addQuadCurve(to: CGPoint(x: unit * 0.10, y: 0),
                                  control: CGPoint(x: -unit * 0.02, y: -radius * 0.20))
                glint.addQuadCurve(to: CGPoint(x: -unit * 0.14, y: radius * 0.76),
                                  control: CGPoint(x: -unit * 0.02, y: radius * 0.20))
                material.stroke(glint, with: .color(Color.white.opacity(0.66)),
                                style: StrokeStyle(lineWidth: max(0.65, unit * 0.063), lineCap: .round))
                let sheen = CGRect(x: -unit * 0.10, y: -radius * 0.50,
                                   width: unit * 0.25, height: radius * 0.16)
                material.fill(Path(ellipseIn: sheen), with: .color(palette.accent2.opacity(0.72)))
            }
        }
    }

    private func drawHead(in context: GraphicsContext, cell: CGSize, unit: CGFloat) {
        guard !input.snake.isEmpty else { return }
        let frame = input.frame
        let heading = frame.headHeading
        let angle = atan2(heading.y, heading.x)
        let logicalHead = LabRenderGeometry.head(input: input)
        let x = logicalHead.x * cell.width
        let y = logicalHead.y * cell.height
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
        let pulse = input.reduceMotion ? 1 : 0.94 + 0.06 * sin(input.time * 2.2)
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
