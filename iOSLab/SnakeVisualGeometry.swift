import Foundation

struct SnakeVisualPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    static func + (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: Self, rhs: Double) -> Self { Self(x: lhs.x * rhs, y: lhs.y * rhs) }
    var length: Double { hypot(x, y) }
    var normalized: Self { length > 0.000_001 ? self * (1 / length) : Self(x: 1, y: 0) }
}

struct SnakeVisualSample: Sendable {
    let center: SnakeVisualPoint
    let radius: Double
    let bodyPosition: Double
}

struct SnakeVisualFrame: Sendable {
    let columns: Int
    let rows: Int
    /// 0 is paper, 1 is snake, and 2 is food. Eyes are negative pixels.
    let dots: [UInt8]
    let centers: [SnakeVisualPoint]
    let samples: [SnakeVisualSample]
    let heading: SnakeVisualPoint
    let foodRadius: Double
}

/// Presentation geometry is independent of the occupied-cell game rules.
/// Work in cell coordinates, then wrap each micro-pixel, so a long body may
/// cross a seam any number of times without drawing a line across the screen.
enum SnakeVisualGeometry {
    static let pixelsPerCell = 7

    static func frame(configuration: SnakeConfiguration, snake: [GridCell], previousSnake: [GridCell],
                      food: GridCell?, progress: Double, time: Double,
                      reduceMotion: Bool = false) -> SnakeVisualFrame {
        let columns = configuration.columns * pixelsPerCell
        let rows = configuration.rows * pixelsPerCell
        let centers = interpolate(snake: snake, previous: previousSnake,
                                  progress: reduceMotion ? 1 : min(1, max(0, progress)),
                                  configuration: configuration)
        let heading = centers.count > 1 ? (centers[0] - centers[1]).normalized : SnakeVisualPoint(x: 1, y: 0)
        let samples = bodySamples(centers: centers, time: time, reduceMotion: reduceMotion)
        var raster = SnakePixelRaster(columns: columns, rows: rows)
        for sample in samples {
            raster.disc(center: sample.center, radius: sample.radius, value: 1)
        }
        if let head = centers.first {
            let normal = SnakeVisualPoint(x: -heading.y, y: heading.x)
            raster.head(center: head + heading * 0.025, forward: heading)
            // A broader snout and two visible eye cutouts distinguish the head
            // even when the body is folded tightly or passing a screen edge.
            for side in [-1.0, 1.0] {
                raster.dot(at: head + heading * 0.14 + normal * (side * 0.18), value: 0)
            }
        }
        let radius = foodRadius(at: time, reduceMotion: reduceMotion)
        if let food {
            raster.disc(center: SnakeVisualPoint(x: Double(food.x) + 0.5, y: Double(food.y) + 0.5),
                        radius: radius, value: 2)
        }
        return SnakeVisualFrame(columns: columns, rows: rows, dots: raster.dots, centers: centers,
                                samples: samples, heading: heading, foodRadius: radius)
    }

    static func foodRadius(at time: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0.30 }
        // At the small end the circle rasterizes to a cross, and at the large
        // end it becomes a round pixel fruit, as in the supplied reference.
        return 0.16 + 0.28 * (0.5 - 0.5 * cos(time * 2 * .pi / 1.4))
    }

    private static func shortest(_ value: Double, period: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: period)
        if result > period / 2 { result -= period }
        if result < -period / 2 { result += period }
        return result
    }

    private static func interpolate(snake: [GridCell], previous: [GridCell], progress: Double,
                                    configuration: SnakeConfiguration) -> [SnakeVisualPoint] {
        var result: [SnakeVisualPoint] = []
        result.reserveCapacity(snake.count)
        for (index, cell) in snake.enumerated() {
            let old = previous.indices.contains(index) ? previous[index] : (previous.last ?? cell)
            let x = Double(old.x) + 0.5 + shortest(Double(cell.x - old.x), period: Double(configuration.columns)) * progress
            let y = Double(old.y) + 0.5 + shortest(Double(cell.y - old.y), period: Double(configuration.rows)) * progress
            if let last = result.last {
                result.append(SnakeVisualPoint(x: last.x + shortest(x - last.x, period: Double(configuration.columns)),
                                               y: last.y + shortest(y - last.y, period: Double(configuration.rows))))
            } else {
                result.append(SnakeVisualPoint(x: x, y: y))
            }
        }
        return result
    }

    private static func bodySamples(centers: [SnakeVisualPoint], time: Double,
                                    reduceMotion: Bool) -> [SnakeVisualSample] {
        guard let head = centers.first else { return [] }
        guard centers.count > 1 else {
            return [SnakeVisualSample(center: head, radius: 0.24, bodyPosition: 0)]
        }
        var curve: [(point: SnakeVisualPoint, position: Double)] = [(head, 0)]
        curve.reserveCapacity(centers.count * 8)
        func line(from a: SnakeVisualPoint, to b: SnakeVisualPoint, start: Double, end: Double) {
            for step in 1...4 {
                let t = Double(step) / 4
                curve.append((a * (1 - t) + b * t, start + (end - start) * t))
            }
        }
        line(from: head, to: (head + centers[1]) * 0.5, start: 0, end: 0.5)
        for index in 1..<(centers.count - 1) {
            let a = (centers[index - 1] + centers[index]) * 0.5
            let control = centers[index]
            let b = (centers[index] + centers[index + 1]) * 0.5
            for step in 1...8 {
                let t = Double(step) / 8
                let point = a * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + b * (t * t)
                curve.append((point, Double(index) - 0.5 + t))
            }
        }
        let last = centers.count - 1
        line(from: (centers[last - 1] + centers[last]) * 0.5, to: centers[last],
             start: Double(last) - 0.5, end: Double(last))
        let taperLength = min(5, max(1.5, Double(last) * 0.45))
        return curve.indices.map { index in
            let item = curve[index]
            let before = curve[max(0, index - 1)].point
            let after = curve[min(curve.count - 1, index + 1)].point
            let tangent = (after - before).normalized
            let normal = SnakeVisualPoint(x: -tangent.y, y: tangent.x)
            let remaining = max(0, Double(last) - item.position)
            let headFade = min(1, item.position / 1.8)
            let tailFade = min(1, 0.25 + remaining / 1.5)
            let wave = reduceMotion ? 0 : 0.15 * headFade * tailFade * sin(item.position * 1.5 - time * 5.2)
            let radius = max(0.035, 0.24 * pow(min(1, remaining / taperLength), 0.65))
            return SnakeVisualSample(center: item.point + normal * wave, radius: radius, bodyPosition: item.position)
        }
    }
}

private struct SnakePixelRaster {
    let columns: Int
    let rows: Int
    var dots: [UInt8]
    private let density = Double(SnakeVisualGeometry.pixelsPerCell)

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        dots = [UInt8](repeating: 0, count: columns * rows)
    }

    mutating func dot(at point: SnakeVisualPoint, value: UInt8) {
        put(x: Int(floor(point.x * density)), y: Int(floor(point.y * density)), value: value)
    }

    mutating func disc(center: SnakeVisualPoint, radius: Double, value: UInt8) {
        for y in Int(floor((center.y - radius) * density))...Int(floor((center.y + radius) * density)) {
            for x in Int(floor((center.x - radius) * density))...Int(floor((center.x + radius) * density)) {
                let dx = (Double(x) + 0.5) / density - center.x
                let dy = (Double(y) + 0.5) / density - center.y
                if dx * dx + dy * dy <= radius * radius { put(x: x, y: y, value: value) }
            }
        }
        // Keep the last sub-pixel of a tapered tail visible at every phase.
        if radius < 1 / density { dot(at: center, value: value) }
    }

    mutating func head(center: SnakeVisualPoint, forward: SnakeVisualPoint) {
        let normal = SnakeVisualPoint(x: -forward.y, y: forward.x)
        for y in Int(floor((center.y - 0.46) * density))...Int(floor((center.y + 0.46) * density)) {
            for x in Int(floor((center.x - 0.46) * density))...Int(floor((center.x + 0.46) * density)) {
                let delta = SnakeVisualPoint(x: (Double(x) + 0.5) / density - center.x,
                                             y: (Double(y) + 0.5) / density - center.y)
                let along = (delta.x * forward.x + delta.y * forward.y) / 0.43
                let across = (delta.x * normal.x + delta.y * normal.y) / 0.34
                if along * along + across * across <= 1 { put(x: x, y: y, value: 1) }
            }
        }
    }

    private mutating func put(x: Int, y: Int, value: UInt8) {
        let wrappedX = (x % columns + columns) % columns
        let wrappedY = (y % rows + rows) % rows
        dots[wrappedY * columns + wrappedX] = value
    }
}
