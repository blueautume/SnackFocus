import Foundation

struct GridCell: Hashable, Sendable {
    let x: Int
    let y: Int
}

struct SnakeConfiguration: Equatable, Sendable {
    let columns: Int
    let rows: Int

    static let firstMap = SnakeConfiguration(columns: 16, rows: 24)
    var cellCount: Int { columns * rows }
}

enum SnakePhase: Equatable, Sendable {
    case playing
    case filled
    case collision
}

/// A deterministic toroidal game. Maps require both dimensions >= 2 and at
/// least one even dimension so the serpentine Hamiltonian cycle can close.
struct SnakeEngine: Sendable {
    let configuration: SnakeConfiguration
    let seed: UInt64
    let cycle: [GridCell]
    private(set) var snake: [GridCell]
    private(set) var food: GridCell?
    private(set) var steps = 0
    private(set) var foodsEaten = 0
    private(set) var phase: SnakePhase = .playing

    private let indices: [Int]
    private var occupied: Set<GridCell>
    private var random: SnakeRandom

    init(configuration: SnakeConfiguration = .firstMap,
         seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        precondition(configuration.columns >= 2 && configuration.rows >= 2,
                     "Snake maps need at least two cells on each axis.")
        precondition(configuration.columns.isMultiple(of: 2) || configuration.rows.isMultiple(of: 2),
                     "The toroidal Hamiltonian map needs at least one even dimension.")
        self.configuration = configuration
        self.seed = seed
        var generator = SnakeRandom(seed: seed)
        let horizontal: Bool
        if configuration.columns.isMultiple(of: 2) && configuration.rows.isMultiple(of: 2) {
            horizontal = generator.integer(lessThan: 2) == 0
        } else {
            horizontal = configuration.rows.isMultiple(of: 2)
        }
        let width = horizontal ? configuration.columns : configuration.rows
        let height = horizontal ? configuration.rows : configuration.columns
        let reflectX = generator.integer(lessThan: 2) == 0
        let reflectY = generator.integer(lessThan: 2) == 0
        let offsetX = generator.integer(lessThan: configuration.columns)
        let offsetY = generator.integer(lessThan: configuration.rows)
        var route: [GridCell] = []
        route.reserveCapacity(configuration.cellCount)
        for row in 0..<height {
            for column in 0..<width {
                let along = row.isMultiple(of: 2) ? column : width - 1 - column
                var x = horizontal ? along : row
                var y = horizontal ? row : along
                if reflectX { x = configuration.columns - 1 - x }
                if reflectY { y = configuration.rows - 1 - y }
                route.append(GridCell(x: (x + offsetX) % configuration.columns,
                                      y: (y + offsetY) % configuration.rows))
            }
        }
        if generator.integer(lessThan: 2) == 0 { route.reverse() }
        // Rotating the cycle also varies the starting head relative to the seams.
        let start = generator.integer(lessThan: route.count)
        route = Array(route[start...] + route[..<start])
        cycle = route
        var lookup = [Int](repeating: 0, count: route.count)
        for (index, cell) in route.enumerated() {
            lookup[cell.y * configuration.columns + cell.x] = index
        }
        indices = lookup
        snake = Array(route.prefix(4).reversed())
        occupied = Set(snake)
        random = generator
        food = nil
        if snake.count == configuration.cellCount {
            phase = .filled
        } else {
            placeFood()
        }
    }

    func cycleIndex(of cell: GridCell) -> Int {
        indices[cell.y * configuration.columns + cell.x]
    }

    func forwardDistance(from start: GridCell, to end: GridCell) -> Int {
        (cycleIndex(of: end) - cycleIndex(of: start) + cycle.count) % cycle.count
    }

    func neighbors(of cell: GridCell) -> [GridCell] {
        let columns = configuration.columns
        let rows = configuration.rows
        return [
            GridCell(x: (cell.x + 1) % columns, y: cell.y),
            GridCell(x: (cell.x + columns - 1) % columns, y: cell.y),
            GridCell(x: cell.x, y: (cell.y + 1) % rows),
            GridCell(x: cell.x, y: (cell.y + rows - 1) % rows)
        ]
    }

    var nextCell: GridCell? {
        guard phase == .playing, let head = snake.first, let tail = snake.last, let food else { return nil }
        let foodDistance = forwardDistance(from: head, to: food)
        let tailDistance = forwardDistance(from: head, to: tail)
        var chosen: GridCell?
        var longestAdvance = 0
        for candidate in neighbors(of: head) {
            let advance = forwardDistance(from: head, to: candidate)
            let growing = candidate == food
            guard advance > 0, advance <= foodDistance,
                  advance < tailDistance || (advance == tailDistance && !growing),
                  !occupied.contains(candidate) || (candidate == tail && !growing) else { continue }
            if advance > longestAdvance {
                longestAdvance = advance
                chosen = candidate
            }
        }
        // The invariant leaves the cycle successor available, including entry
        // into a tail cell that vacates on this non-growing move.
        return chosen ?? cycle[(cycleIndex(of: head) + 1) % cycle.count]
    }

    mutating func step() {
        guard phase == .playing, let candidate = nextCell, let tail = snake.last else { return }
        let growing = candidate == food
        steps += 1
        guard !occupied.contains(candidate) || (!growing && candidate == tail) else {
            phase = .collision
            return
        }
        if !growing {
            snake.removeLast()
            occupied.remove(tail)
        }
        snake.insert(candidate, at: 0)
        occupied.insert(candidate)
        if growing {
            foodsEaten += 1
            if snake.count == configuration.cellCount {
                food = nil
                phase = .filled
            } else {
                placeFood()
            }
        }
    }

    private mutating func placeFood() {
        let available = configuration.cellCount - occupied.count
        guard available > 0 else { food = nil; return }
        // Select a uniform rank among genuinely vacant cells; this also remains
        // efficient when only one cell is left, without random retry loops.
        var rank = random.integer(lessThan: available)
        for y in 0..<configuration.rows {
            for x in 0..<configuration.columns {
                let cell = GridCell(x: x, y: y)
                guard !occupied.contains(cell) else { continue }
                if rank == 0 { food = cell; return }
                rank -= 1
            }
        }
        preconditionFailure("The vacancy count must match the occupied cells.")
    }
}

/// SplitMix64 supplies reproducible games; bounded sampling avoids modulo bias.
private struct SnakeRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func integer(lessThan bound: Int) -> Int {
        precondition(bound > 0)
        let divisor = UInt64(bound)
        let threshold = (0 &- divisor) % divisor
        while true {
            let value = next()
            if value >= threshold { return Int(value % divisor) }
        }
    }
}
