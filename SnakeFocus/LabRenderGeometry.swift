import Foundation

/// A render-only snapshot. No renderer mutates the production simulation.
struct LabBoardInput {
    let configuration: SnakeConfiguration
    let snake: [GridCell]
    let previousSnake: [GridCell]
    let food: GridCell?
    let progress: Double
    let time: Double
    let completedMoves: Int
    let reduceMotion: Bool
    let frame: SnakeVisualFrame

    init(configuration: SnakeConfiguration, snake: [GridCell], previousSnake: [GridCell],
         food: GridCell?, progress: Double, time: Double, completedMoves: Int, reduceMotion: Bool = false) {
        self.configuration = configuration
        self.snake = snake
        self.previousSnake = previousSnake
        self.food = food
        self.progress = progress
        self.time = time
        self.completedMoves = completedMoves
        self.reduceMotion = reduceMotion
        // The lab's skin is attached to the moving body. The original classic
        // renderer intentionally pins its middle wave to the world; using it
        // here made the material look stationary except near the head/tail.
        // A head-relative wave advances with the actual interpolated cells,
        // without a second elapsed-time scroll speed or a reset at wrap seams.
        self.frame = SnakeVisualGeometry.frame(configuration: configuration, snake: snake,
            previousSnake: previousSnake, food: food, progress: progress, time: 0,
            completedMoves: completedMoves, appearance: .modern, reduceMotion: reduceMotion)
    }

    /// An intentionally legible material specimen, independent of game state.
    static let specimen: LabBoardInput = {
        var cells: [GridCell] = []
        for x in stride(from: 12, through: 4, by: -1) { cells.append(GridCell(x: x, y: 5)) }
        for y in 6...11 { cells.append(GridCell(x: 4, y: y)) }
        for x in 5...11 { cells.append(GridCell(x: x, y: 11)) }
        for y in 12...18 { cells.append(GridCell(x: 11, y: y)) }
        for x in stride(from: 10, through: 3, by: -1) { cells.append(GridCell(x: x, y: 18)) }
        return LabBoardInput(configuration: .firstMap, snake: cells, previousSnake: cells,
            food: GridCell(x: 14, y: 5), progress: 1, time: 0.3, completedMoves: 0)
    }()

    static let thumbnail: LabBoardInput = {
        var cells = stride(from: 10, through: 2, by: -1).map { GridCell(x: $0, y: 1) }
        cells += (2...3).map { GridCell(x: 2, y: $0) }
        cells += (3...9).map { GridCell(x: $0, y: 3) }
        cells += (4...5).map { GridCell(x: 9, y: $0) }
        cells += stride(from: 8, through: 5, by: -1).map { GridCell(x: $0, y: 5) }
        return LabBoardInput(configuration: SnakeConfiguration(columns: 12, rows: 6),
            snake: cells, previousSnake: cells, food: GridCell(x: 11, y: 1),
            progress: 1, time: 0, completedMoves: 0)
    }()

    /// A closed preview route demonstrates the same moving material as play.
    /// This never starts or mutates a user's session.
    static func movingThumbnail(distance: Double) -> LabBoardInput {
        var route = (1...10).map { GridCell(x: $0, y: 1) }
        route += (2...4).map { GridCell(x: 10, y: $0) }
        route += stride(from: 9, through: 1, by: -1).map { GridCell(x: $0, y: 4) }
        route += stride(from: 3, through: 2, by: -1).map { GridCell(x: 1, y: $0) }
        let whole = Int(floor(max(0, distance)))
        func cells(at head: Int) -> [GridCell] {
            (0..<19).map { route[((head - $0) % route.count + route.count) % route.count] }
        }
        return LabBoardInput(configuration: SnakeConfiguration(columns: 12, rows: 6),
            snake: cells(at: whole), previousSnake: cells(at: whole - 1),
            food: GridCell(x: 6, y: 2), progress: max(0, distance) - Double(whole),
            time: max(0, distance) / 2, completedMoves: whole + 1)
    }
}

struct LabRenderSample {
    let center: CGPoint
    let radius: CGFloat
    let position: Double
}

struct LabMaterialMark {
    let center: CGPoint
    /// Head to tail in logical board coordinates, before any wrapping.
    let tangent: CGPoint
    let radius: CGFloat
    let position: Double
}

enum LabRenderGeometry {
    /// Material anchors are placed on the full body before seam splitting.
    /// Stable head-relative positions move at the head's speed on every strip.
    static func materialMarks(input: LabBoardInput, spacing: Double) -> [LabMaterialMark] {
        guard spacing.isFinite, spacing > 0, let last = input.frame.samples.last,
              last.bodyPosition > 2 else { return [] }
        var result: [LabMaterialMark] = []
        let samples = input.frame.samples
        var cursor = 1
        var position = 1.2
        while position < last.bodyPosition - 0.8 {
            while cursor < samples.count - 1 && samples[cursor].bodyPosition < position { cursor += 1 }
            let a = samples[max(0, cursor - 1)], b = samples[cursor]
            let delta = b.bodyPosition - a.bodyPosition
            let t = delta > 0.000_001 ? min(1, max(0, (position - a.bodyPosition) / delta)) : 0
            let point = a.center * (1 - t) + b.center * t
            let tangent = (b.center - a.center).normalized
            let radius = CGFloat(a.radius * (1 - t) + b.radius * t)
            let center = wrap(point, configuration: input.configuration)
            let width = CGFloat(input.configuration.columns), height = CGFloat(input.configuration.rows)
            let margin = max(radius, 0.42)
            var xs: [CGFloat] = [0], ys: [CGFloat] = [0]
            if input.configuration.wrapsHorizontally {
                if center.x - margin < 0 { xs.append(width) }
                if center.x + margin > width { xs.append(-width) }
            }
            if input.configuration.wrapsVertically {
                if center.y - margin < 0 { ys.append(height) }
                if center.y + margin > height { ys.append(-height) }
            }
            for dx in xs { for dy in ys {
                result.append(LabMaterialMark(center: CGPoint(x: center.x + dx, y: center.y + dy),
                    tangent: CGPoint(x: tangent.x, y: tangent.y), radius: radius, position: position))
            } }
            position += spacing
        }
        return result
    }

    static func wrap(_ point: SnakeVisualPoint, configuration: SnakeConfiguration) -> CGPoint {
        func coordinate(_ v: Double, extent: Int, wraps: Bool) -> CGFloat {
            guard wraps else { return CGFloat(v) }
            let size = Double(extent)
            return CGFloat(v - floor(v / size) * size)
        }
        return CGPoint(x: coordinate(point.x, extent: configuration.columns, wraps: configuration.wrapsHorizontally),
                       y: coordinate(point.y, extent: configuration.rows, wraps: configuration.wrapsVertically))
    }

    static func head(input: LabBoardInput) -> CGPoint {
        wrap(input.frame.headCenter, configuration: input.configuration)
    }

    static func headDirection(input: LabBoardInput) -> CGPoint {
        CGPoint(x: input.frame.headHeading.x, y: input.frame.headHeading.y)
    }

    /// Edge crossings are separate strips, never a line through the playfield.
    /// Ghost strips let the clipped tube occupy both edges while crossing a seam.
    static func wrappedSamples(input: LabBoardInput) -> [[LabRenderSample]] {
        let configuration = input.configuration
        let width = CGFloat(configuration.columns), height = CGFloat(configuration.rows)
        var parts: [[LabRenderSample]] = []
        var current: [LabRenderSample] = []
        for sample in input.frame.samples {
            let next = LabRenderSample(center: wrap(sample.center, configuration: configuration),
                radius: CGFloat(sample.radius), position: sample.bodyPosition)
            if let previous = current.last,
               abs(previous.center.x - next.center.x) > width / 2 || abs(previous.center.y - next.center.y) > height / 2 {
                if !current.isEmpty { parts.append(current) }
                current = []
            }
            current.append(next)
        }
        if !current.isEmpty { parts.append(current) }
        var result = parts
        for part in parts {
            guard let minX = part.map({ $0.center.x - $0.radius }).min(),
                  let maxX = part.map({ $0.center.x + $0.radius }).max(),
                  let minY = part.map({ $0.center.y - $0.radius }).min(),
                  let maxY = part.map({ $0.center.y + $0.radius }).max() else { continue }
            var xs: [CGFloat] = [0], ys: [CGFloat] = [0]
            if configuration.wrapsHorizontally {
                if minX < 0 { xs.append(width) }
                if maxX > width { xs.append(-width) }
            }
            if configuration.wrapsVertically {
                if minY < 0 { ys.append(height) }
                if maxY > height { ys.append(-height) }
            }
            for dx in xs { for dy in ys where dx != 0 || dy != 0 {
                result.append(part.map { LabRenderSample(center: CGPoint(x: $0.center.x + dx, y: $0.center.y + dy), radius: $0.radius, position: $0.position) })
            } }
        }
        return result
    }
}
