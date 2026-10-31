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
    /// Logical path distance from the visible head, with one grid edge = one.
    let bodyPosition: Double
}

struct SnakeVisualScale: Sendable {
    let center: SnakeVisualPoint
    let bodyPosition: Double
}

struct SnakeVisualFrame: Sendable {
    let columns: Int
    let rows: Int
    /// 0 is paper, 1 is snake, and 2 is food.
    let dots: [UInt8]
    let bodyMask: [Bool]
    /// Logical anchors, before the stationary wave and the small head sway.
    let centers: [SnakeVisualPoint]
    let samples: [SnakeVisualSample]
    let heading: SnakeVisualPoint
    let headCenter: SnakeVisualPoint
    let headHeading: SnakeVisualPoint
    let scales: [SnakeVisualScale]
    let motionDistance: Double
    let foodRadius: Double
}

enum SnakeAppearance: String, CaseIterable, Identifiable, Equatable, Sendable {
    case classic
    case modern

    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: return "经典"
        case .modern: return "现代"
        }
    }
}

/// Classic retains its stationary trail wave and material scales. Modern
/// retains the original elapsed-time body sway, sharing the same pixel raster.
enum SnakeVisualGeometry {
    static let pixelsPerCell = 7
    static let waveLength = 2.0
    static let waveAmplitude = 0.16
    static let scaleSpacing = 0.8
    private static let samplesPerEdge = 8
    private static let bodyRadius = 0.26

    static func frame(configuration: SnakeConfiguration, snake: [GridCell], previousSnake: [GridCell],
                      food: GridCell?, progress: Double, time: Double, completedMoves: Int = 0,
                      appearance: SnakeAppearance = .classic, reduceMotion: Bool = false) -> SnakeVisualFrame {
        if appearance == .modern {
            return modernFrame(configuration: configuration, snake: snake, previousSnake: previousSnake,
                               food: food, progress: progress, time: time, completedMoves: completedMoves,
                               reduceMotion: reduceMotion)
        }
        let columns = configuration.columns * pixelsPerCell
        let rows = configuration.rows * pixelsPerCell
        let p = reduceMotion ? 1 : min(1, max(0, progress))
        let centers = interpolate(snake: snake, previous: previousSnake, progress: p, configuration: configuration)
        let heading = centers.count > 1 ? (centers[0] - centers[1]).normalized : SnakeVisualPoint(x: 1, y: 0)
        let moving = snake != previousSnake && !previousSnake.isEmpty
            && snake.first.map { configuration.areNeighbors(previousSnake[0], $0) } == true
        let moves = max(0, completedMoves)
        let distance = moving ? max(0, Double(moves) - 1 + p) : Double(moves)
        let cells = moving ? [snake[0]] + previousSnake : snake
        var path = unwrap(cells, configuration: configuration)
        if moving, path.count > 1, let logicalHead = centers.first {
            let pathHead = path[1] * (1 - p) + path[0] * p
            let delta = logicalHead - pathHead
            let translation = SnakeVisualPoint(
                x: configuration.wrapsHorizontally ? (delta.x / Double(configuration.columns)).rounded() * Double(configuration.columns) : 0,
                y: configuration.wrapsVertically ? (delta.y / Double(configuration.rows)).rounded() * Double(configuration.rows) : 0)
            path = path.map { $0 + translation }
        }
        let start = moving ? 1 - p : 0
        let end: Double
        if moving {
            end = Double(previousSnake.count) - (snake.count > previousSnake.count ? 0 : p)
        } else {
            end = Double(max(0, snake.count - 1))
        }
        let trail = Trail(path: path, start: start, end: end, moves: moves,
                          head: centers.first ?? SnakeVisualPoint(x: 0, y: 0),
                          tail: centers.last ?? SnakeVisualPoint(x: 0, y: 0),
                          heading: heading, reduceMotion: reduceMotion)
        let samples = trail.samples()
        let headCenter = samples.first?.center ?? trail.head
        let headNormal = SnakeVisualPoint(x: -heading.y, y: heading.x)
        let swaySlope = reduceMotion || snake.count < 2 ? 0
            : -0.04 * 2 * .pi / waveLength * cos((start - Double(moves)) * 2 * .pi / waveLength)
        let headHeading = (heading + headNormal * swaySlope).normalized
        var raster = SnakePixelRaster(configuration: configuration)
        for sample in samples { raster.disc(center: sample.center, radius: sample.radius, value: 1) }
        if !snake.isEmpty { raster.head(center: headCenter + headHeading * 0.025, forward: headHeading) }
        let eyeNormal = SnakeVisualPoint(x: -headHeading.y, y: headHeading.x)
        let eyes = snake.isEmpty ? [] : [-1.0, 1.0].map {
            headCenter + headHeading * 0.14 + eyeNormal * ($0 * 0.18)
        }
        for eye in eyes { raster.eyeSocket(at: eye) }
        let bodyMask = raster.dots.map { $0 == 1 }
        var scales: [SnakeVisualScale] = []
        let lastScale = end - start - 1.1
        if lastScale >= 1.25 {
            // Fixed material coordinates: no independent time offset or extra
            // scroll speed. Every spot advances with the head along the trail.
            let count = Int(floor((lastScale - 1.25) / scaleSpacing))
            for index in 0...count {
                let s = 1.25 + Double(index) * scaleSpacing
                let center = trail.sample(at: start + s).center
                if raster.carveScale(at: center, mask: bodyMask, protecting: headCenter) {
                    scales.append(SnakeVisualScale(center: center, bodyPosition: s))
                }
            }
        }
        for eye in eyes { raster.dot(at: eye, value: 0) }
        let radius = foodRadius(at: time, reduceMotion: reduceMotion)
        if let food {
            raster.disc(center: SnakeVisualPoint(x: Double(food.x) + 0.5, y: Double(food.y) + 0.5),
                        radius: radius, value: 2)
        }
        return SnakeVisualFrame(columns: columns, rows: rows, dots: raster.dots, bodyMask: bodyMask,
                                centers: centers, samples: samples, heading: heading,
                                headCenter: headCenter, headHeading: headHeading, scales: scales,
                                motionDistance: distance, foodRadius: radius)
    }

    /// Preserve the original ca75bcb presentation: the whole body sways on
    /// elapsed time, with its original radius, taper, head and negative eyes.
    private static func modernFrame(configuration: SnakeConfiguration, snake: [GridCell], previousSnake: [GridCell],
                                    food: GridCell?, progress: Double, time: Double, completedMoves: Int,
                                    reduceMotion: Bool) -> SnakeVisualFrame {
        let p = reduceMotion ? 1 : min(1, max(0, progress))
        let centers = interpolate(snake: snake, previous: previousSnake, progress: p, configuration: configuration)
        let heading = centers.count > 1 ? (centers[0] - centers[1]).normalized : SnakeVisualPoint(x: 1, y: 0)
        let samples = modernSamples(centers: centers, time: time, reduceMotion: reduceMotion)
        var raster = SnakePixelRaster(configuration: configuration)
        for sample in samples { raster.disc(center: sample.center, radius: sample.radius, value: 1) }
        if let head = centers.first { raster.head(center: head + heading * 0.025, forward: heading) }
        let bodyMask = raster.dots.map { $0 == 1 }
        if let head = centers.first {
            let normal = SnakeVisualPoint(x: -heading.y, y: heading.x)
            for side in [-1.0, 1.0] {
                raster.dot(at: head + heading * 0.14 + normal * (side * 0.18), value: 0)
            }
        }
        let radius = foodRadius(at: time, reduceMotion: reduceMotion)
        if let food {
            raster.disc(center: SnakeVisualPoint(x: Double(food.x) + 0.5, y: Double(food.y) + 0.5),
                        radius: radius, value: 2)
        }
        let moving = snake != previousSnake && !previousSnake.isEmpty
            && snake.first.map { configuration.areNeighbors(previousSnake[0], $0) } == true
        let moves = max(0, completedMoves)
        let distance = moving ? max(0, Double(moves) - 1 + p) : Double(moves)
        return SnakeVisualFrame(columns: raster.columns, rows: raster.rows, dots: raster.dots, bodyMask: bodyMask,
                                centers: centers, samples: samples, heading: heading,
                                headCenter: centers.first ?? SnakeVisualPoint(x: 0, y: 0), headHeading: heading,
                                scales: [], motionDistance: distance, foodRadius: radius)
    }

    private static func modernSamples(centers: [SnakeVisualPoint], time: Double,
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

    static func foodRadius(at time: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0.30 }
        return 0.16 + 0.28 * (0.5 - 0.5 * cos(time * 2 * .pi / 1.4))
    }

    private static func shortest(_ value: Double, period: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: period)
        if result > period / 2 { result -= period }
        if result < -period / 2 { result += period }
        return result
    }

    private static func unwrap(_ cells: [GridCell], configuration: SnakeConfiguration) -> [SnakeVisualPoint] {
        var result: [SnakeVisualPoint] = []
        for cell in cells {
            let point = SnakeVisualPoint(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5)
            if let last = result.last {
                result.append(SnakeVisualPoint(
                    x: configuration.wrapsHorizontally ? last.x + shortest(point.x - last.x, period: Double(configuration.columns)) : point.x,
                    y: configuration.wrapsVertically ? last.y + shortest(point.y - last.y, period: Double(configuration.rows)) : point.y))
            } else { result.append(point) }
        }
        return result
    }

    private static func interpolate(snake: [GridCell], previous: [GridCell], progress: Double,
                                    configuration: SnakeConfiguration) -> [SnakeVisualPoint] {
        var result: [SnakeVisualPoint] = []
        for (index, cell) in snake.enumerated() {
            let old = previous.indices.contains(index) ? previous[index] : (previous.last ?? cell)
            let dx = Double(cell.x - old.x), dy = Double(cell.y - old.y)
            let x = Double(old.x) + 0.5 + (configuration.wrapsHorizontally ? shortest(dx, period: Double(configuration.columns)) : dx) * progress
            let y = Double(old.y) + 0.5 + (configuration.wrapsVertically ? shortest(dy, period: Double(configuration.rows)) : dy) * progress
            if let last = result.last {
                result.append(SnakeVisualPoint(
                    x: configuration.wrapsHorizontally ? last.x + shortest(x - last.x, period: Double(configuration.columns)) : x,
                    y: configuration.wrapsVertically ? last.y + shortest(y - last.y, period: Double(configuration.rows)) : y))
            } else { result.append(SnakeVisualPoint(x: x, y: y)) }
        }
        return result
    }

    private struct Trail {
        let path: [SnakeVisualPoint]
        let start: Double
        let end: Double
        let moves: Int
        let head: SnakeVisualPoint
        let tail: SnakeVisualPoint
        let heading: SnakeVisualPoint
        let reduceMotion: Bool
        let headCorrection: SnakeVisualPoint
        let tailCorrection: SnakeVisualPoint
        let taperLength: Double

        init(path: [SnakeVisualPoint], start: Double, end: Double, moves: Int,
             head: SnakeVisualPoint, tail: SnakeVisualPoint, heading: SnakeVisualPoint, reduceMotion: Bool) {
            self.path = path
            self.start = start
            self.end = end
            self.moves = moves
            self.head = head
            self.tail = tail
            self.heading = heading
            self.reduceMotion = reduceMotion
            headCorrection = head - Self.base(path: path, at: start).point
            tailCorrection = tail - Self.base(path: path, at: end).point
            taperLength = min(5, max(1.5, (end - start) * 0.45))
        }

        /// Smooth the fixed controls before clipping. A grid edge retains its
        /// unit parameter even at bends; Euclidean arc length would drift.
        private static func base(path: [SnakeVisualPoint], at parameter: Double) -> (point: SnakeVisualPoint, backward: SnakeVisualPoint) {
            guard path.count > 1 else { return (path.first ?? SnakeVisualPoint(x: 0, y: 0), SnakeVisualPoint(x: -1, y: 0)) }
            let last = path.count - 1
            let u = min(Double(last), max(0, parameter))
            if u <= 0.5 { return (path[0] + (path[1] - path[0]) * u, (path[1] - path[0]).normalized) }
            if u >= Double(last) - 0.5 {
                return (path[last] + (path[last] - path[last - 1]) * (u - Double(last)),
                        (path[last] - path[last - 1]).normalized)
            }
            let index = min(last - 1, max(1, Int(floor(u + 0.5))))
            let incoming = path[index] - path[index - 1]
            let outgoing = path[index + 1] - path[index]
            if incoming == outgoing {
                return (path[index] + outgoing * (u - Double(index)), outgoing.normalized)
            }
            let a = (path[index - 1] + path[index]) * 0.5
            let control = path[index]
            let b = (control + path[index + 1]) * 0.5
            let t = u - (Double(index) - 0.5)
            return (a * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + b * (t * t),
                    ((control - a) * (1 - t) + (b - control) * t).normalized)
        }

        func sample(at u: Double) -> SnakeVisualSample {
            let s = max(0, u - start), remaining = max(0, end - u)
            let fixed = Self.base(path: path, at: u)
            let headWeight = max(0, 1 - s / 0.75), tailWeight = max(0, 1 - remaining / 0.75)
            let headBlend = headWeight * headWeight, tailBlend = tailWeight * tailWeight
            var point = fixed.point
            if headBlend > 0 { point = point + headCorrection * headBlend }
            if tailBlend > 0 { point = point + tailCorrection * tailBlend }
            let forward = headBlend > 0
                ? ((fixed.backward * -1) * (1 - headBlend) + heading * headBlend).normalized
                : fixed.backward * -1
            let normal = SnakeVisualPoint(x: -forward.y, y: forward.x)
            let headAmplitude = reduceMotion ? 0 : 0.04
            let amplitude = (headAmplitude + (waveAmplitude - headAmplitude) * min(1, s / 1.25))
                * min(1, 0.35 + remaining / 1.5)
            // u increments by one at the next logical move, as does moves.
            // Their difference fixes every middle wave to its world position.
            let phase = (u - Double(moves)) * 2 * .pi / waveLength
            point = point + normal * (amplitude * sin(phase))
            let radius = remaining >= taperLength ? bodyRadius
                : max(0.035, bodyRadius * pow(remaining / taperLength, 0.65))
            return SnakeVisualSample(center: point, radius: radius, bodyPosition: s)
        }

        func samples() -> [SnakeVisualSample] {
            guard !path.isEmpty else { return [] }
            guard end > start else { return [sample(at: start)] }
            var result = [sample(at: start)]
            // Sampling stays on the full trail's fixed lattice, rather than
            // sliding with the clipped head and making the outer pixels flicker.
            let first = Int(floor(start * Double(samplesPerEdge))) + 1
            let last = Int(ceil(end * Double(samplesPerEdge))) - 1
            if first <= last {
                for index in first...last { result.append(sample(at: Double(index) / Double(samplesPerEdge))) }
            }
            result.append(sample(at: end))
            return result
        }
    }
}

private struct SnakePixelRaster {
    let configuration: SnakeConfiguration
    let columns: Int
    let rows: Int
    var dots: [UInt8]
    private let density = Double(SnakeVisualGeometry.pixelsPerCell)

    init(configuration: SnakeConfiguration) {
        self.configuration = configuration
        columns = configuration.columns * SnakeVisualGeometry.pixelsPerCell
        rows = configuration.rows * SnakeVisualGeometry.pixelsPerCell
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
        if radius < 1 / density { dot(at: center, value: value) }
    }

    mutating func head(center: SnakeVisualPoint, forward: SnakeVisualPoint) {
        let normal = SnakeVisualPoint(x: -forward.y, y: forward.x)
        for y in Int(floor((center.y - 0.49) * density))...Int(floor((center.y + 0.49) * density)) {
            for x in Int(floor((center.x - 0.49) * density))...Int(floor((center.x + 0.49) * density)) {
                let delta = SnakeVisualPoint(x: (Double(x) + 0.5) / density - center.x,
                                             y: (Double(y) + 0.5) / density - center.y)
                let along = (delta.x * forward.x + delta.y * forward.y) / 0.43
                let across = (delta.x * normal.x + delta.y * normal.y) / 0.34
                if along * along + across * across <= 1 { put(x: x, y: y, value: 1) }
            }
        }
    }

    mutating func eyeSocket(at point: SnakeVisualPoint) {
        let x = Int(floor(point.x * density)), y = Int(floor(point.y * density))
        // Quantized eye sockets retain their dark rim while the head sways
        // between micro-pixels, giving the classic slightly bulbous head.
        for (dx, dy) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
            put(x: x + dx, y: y + dy, value: 1)
        }
    }

    mutating func carveScale(at point: SnakeVisualPoint, mask: [Bool], protecting head: SnakeVisualPoint) -> Bool {
        let x = Int(floor(point.x * density)), y = Int(floor(point.y * density))
        var dx = abs(point.x - head.x), dy = abs(point.y - head.y)
        if configuration.wrapsHorizontally {
            dx = dx.truncatingRemainder(dividingBy: Double(configuration.columns))
            dx = min(dx, Double(configuration.columns) - dx)
        }
        if configuration.wrapsVertically {
            dy = dy.truncatingRemainder(dividingBy: Double(configuration.rows))
            dy = min(dy, Double(configuration.rows) - dy)
        }
        guard hypot(dx, dy) > 0.70 else { return false }
        for oy in -1...1 {
            for ox in -1...1 {
                guard let index = resolvedIndex(x: x + ox, y: y + oy), mask[index] else { return false }
            }
        }
        put(x: x, y: y, value: 0)
        return true
    }

    private func resolvedIndex(x: Int, y: Int) -> Int? {
        if !configuration.wrapsHorizontally && !(0..<columns).contains(x) { return nil }
        if !configuration.wrapsVertically && !(0..<rows).contains(y) { return nil }
        let x = (x % columns + columns) % columns
        let y = (y % rows + rows) % rows
        let cell = GridCell(x: x / SnakeVisualGeometry.pixelsPerCell, y: y / SnakeVisualGeometry.pixelsPerCell)
        guard !configuration.walls.contains(cell) else { return nil }
        return y * columns + x
    }

    private mutating func put(x: Int, y: Int, value: UInt8) {
        guard let index = resolvedIndex(x: x, y: y) else { return }
        dots[index] = value
    }
}
