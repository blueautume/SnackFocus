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
        self.frame = SnakeVisualGeometry.frame(configuration: configuration, snake: snake,
            previousSnake: previousSnake, food: food, progress: progress, time: time,
            completedMoves: completedMoves, appearance: .classic, reduceMotion: reduceMotion)
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
}

struct LabRenderSample {
    let center: CGPoint
    let radius: CGFloat
    let position: Double
}

enum LabRenderGeometry {
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
