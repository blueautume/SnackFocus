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

enum SnakeStrategy: String, CaseIterable, Identifiable, Equatable, Sendable {
    case safeShortcuts
    case dynamicCycle

    var id: String { rawValue }
    var label: String {
        switch self {
        case .safeShortcuts: return "经典环路"
        case .dynamicCycle: return "动态环路"
        }
    }
}

/// A deterministic toroidal game. Maps require both dimensions >= 2 and at
/// least one even dimension so the serpentine Hamiltonian cycle can close.
struct SnakeEngine: Sendable {
    let configuration: SnakeConfiguration
    let seed: UInt64
    let strategy: SnakeStrategy
    private(set) var cycle: [GridCell]
    private(set) var cycleReplans = 0
    private(set) var replanAttempts = 0
    static let maximumReplanAttemptsPerFood = 136
    private(set) var snake: [GridCell]
    private(set) var food: GridCell?
    private(set) var steps = 0
    private(set) var foodsEaten = 0
    private(set) var phase: SnakePhase = .playing

    private var indices: [Int]
    private var occupied: Set<GridCell>
    private var random: SnakeRandom

    init(configuration: SnakeConfiguration = .firstMap,
         seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
         strategy: SnakeStrategy = .dynamicCycle) {
        precondition(configuration.columns >= 2 && configuration.rows >= 2,
                     "Snake maps need at least two cells on each axis.")
        precondition(configuration.columns.isMultiple(of: 2) || configuration.rows.isMultiple(of: 2),
                     "The toroidal Hamiltonian map needs at least one even dimension.")
        self.configuration = configuration
        self.seed = seed
        self.strategy = strategy
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
                if rank == 0 {
                    food = cell
                    if strategy == .dynamicCycle { reconfigureCycle() }
                    return
                }
                rank -= 1
            }
        }
        preconditionFailure("The vacancy count must match the occupied cells.")
    }

    /// Replan only when a new food appears. A frozen, verified cycle makes the
    /// forward food rank decrease every move, retaining the N-move food bound.
    private mutating func reconfigureCycle() {
        guard let head = snake.first, let food, snake.count < cycle.count - 1 else { return }
        let columns = configuration.columns
        let headID = head.y * columns + head.x
        let foodID = food.y * columns + food.x
        let bodyIDs = snake.reversed().map { $0.y * columns + $0.x }
        let original = SnakeCycleGraph(cycle: cycle, configuration: configuration)
        var bestDistance = forwardDistance(from: head, to: food)
        var bestOrder: [Int]?
        var bestLookup: [Int]?

        func consider(_ proposal: SnakeCycleGraph) {
            guard proposal.differs(from: original),
                  let candidate = proposal.orientedOrder(head: headID, body: bodyIDs, food: foodID),
                  candidate.foodDistance <= bestDistance else { return }
            if candidate.foodDistance < bestDistance || bestOrder == nil || random.integer(lessThan: 2) == 0 {
                bestDistance = candidate.foodDistance
                bestOrder = candidate.order
                bestLookup = candidate.indices
            }
        }

        // A single square flip can split a cycle into two loops. A second
        // nearby flip can reconnect them differently. Every final proposal is
        // checked as one spanning cycle, never installed in its split state.
        let nearby = [(1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)]
        for _ in 0..<8 {
            replanAttempts += 1
            let firstSquare = random.integer(lessThan: cycle.count)
            var split = original
            guard split.flip(square: firstSquare) else { continue }
            let components = split.componentLabels()
            if components.count == 1 { consider(split) }
            for attempt in 0..<16 {
                replanAttempts += 1
                let secondSquare: Int
                if attempt < nearby.count {
                    let offset = nearby[attempt]
                    let x = (firstSquare % columns + offset.0 + columns) % columns
                    let y = (firstSquare / columns + offset.1 + configuration.rows) % configuration.rows
                    secondSquare = y * columns + x
                } else {
                    secondSquare = random.integer(lessThan: cycle.count)
                }
                guard secondSquare != firstSquare,
                      let removed = split.removedEdgeOrigins(square: secondSquare) else { continue }
                if components.count == 2 && components.labels[removed.0] == components.labels[removed.1] { continue }
                var proposal = split
                guard proposal.flip(square: secondSquare) else { continue }
                consider(proposal)
            }
        }
        guard let bestOrder, let bestLookup else { return }
        cycle = bestOrder.map { GridCell(x: $0 % columns, y: $0 / columns) }
        indices = bestLookup
        cycleReplans += 1
    }
}

/// An undirected two-neighbor graph permits a temporary split while searching.
/// Grid coordinates stay fixed: these are real edge changes, not board shifts.
private struct SnakeCycleGraph {
    private var first: [Int]
    private var second: [Int]
    private let configuration: SnakeConfiguration

    init(cycle: [GridCell], configuration: SnakeConfiguration) {
        self.configuration = configuration
        let count = cycle.count
        first = [Int](repeating: 0, count: count)
        second = first
        for index in cycle.indices {
            let cell = cycle[index]
            let previous = cycle[(index + count - 1) % count]
            let next = cycle[(index + 1) % count]
            let id = cell.y * configuration.columns + cell.x
            first[id] = previous.y * configuration.columns + previous.x
            second[id] = next.y * configuration.columns + next.x
        }
    }

    private func corners(square: Int) -> (a: Int, b: Int, c: Int, d: Int) {
        let columns = configuration.columns
        let x = square % columns
        let y = square / columns
        let nextX = (x + 1) % columns
        let nextY = (y + 1) % configuration.rows
        return (square, y * columns + nextX, nextY * columns + x, nextY * columns + nextX)
    }

    private func connected(_ a: Int, _ b: Int) -> Bool { first[a] == b || second[a] == b }

    func removedEdgeOrigins(square: Int) -> (Int, Int)? {
        let (a, b, c, d) = corners(square: square)
        if connected(a, b) && connected(c, d) && !connected(a, c) && !connected(b, d) { return (a, c) }
        if connected(a, c) && connected(b, d) && !connected(a, b) && !connected(c, d) { return (a, b) }
        return nil
    }

    mutating func flip(square: Int) -> Bool {
        guard let removed = removedEdgeOrigins(square: square) else { return false }
        let (a, b, c, d) = corners(square: square)
        if removed.1 == c {
            replace(a, removing: b, adding: c)
            replace(b, removing: a, adding: d)
            replace(c, removing: d, adding: a)
            replace(d, removing: c, adding: b)
        } else {
            replace(a, removing: c, adding: b)
            replace(b, removing: d, adding: a)
            replace(c, removing: a, adding: d)
            replace(d, removing: b, adding: c)
        }
        return true
    }

    private mutating func replace(_ cell: Int, removing old: Int, adding new: Int) {
        if first[cell] == old { first[cell] = new }
        else {
            precondition(second[cell] == old)
            second[cell] = new
        }
    }

    func componentLabels() -> (labels: [Int], count: Int) {
        var labels = [Int](repeating: -1, count: first.count)
        var count = 0
        for start in first.indices where labels[start] == -1 {
            var previous = -1
            var cell = start
            while labels[cell] == -1 {
                labels[cell] = count
                let next = first[cell] == previous ? second[cell] : first[cell]
                previous = cell
                cell = next
            }
            count += 1
        }
        return (labels, count)
    }

    func differs(from other: SnakeCycleGraph) -> Bool {
        for cell in first.indices {
            if !other.connected(cell, first[cell]) || !other.connected(cell, second[cell]) { return true }
        }
        return false
    }

    func orientedOrder(head: Int, body: [Int], food: Int) -> (order: [Int], indices: [Int], foodDistance: Int)? {
        var order: [Int] = []
        order.reserveCapacity(first.count)
        var indices = [Int](repeating: -1, count: first.count)
        var previous = -1
        var cell = head
        while indices[cell] == -1 {
            indices[cell] = order.count
            order.append(cell)
            let next = first[cell] == previous ? second[cell] : first[cell]
            previous = cell
            cell = next
        }
        guard cell == head, order.count == first.count else { return nil }
        if !bodyIsOrdered(body, indices: indices, reversed: false) {
            guard bodyIsOrdered(body, indices: indices, reversed: true) else { return nil }
            order = [head] + order.dropFirst().reversed()
            for id in indices.indices { indices[id] = (first.count - indices[id]) % first.count }
        }
        return (order, indices, indices[food])
    }

    private func bodyIsOrdered(_ body: [Int], indices: [Int], reversed: Bool) -> Bool {
        var total = 0
        for index in 1..<body.count {
            let before = indices[body[index - 1]]
            let after = indices[body[index]]
            let distance = reversed ? (before - after + first.count) % first.count
                : (after - before + first.count) % first.count
            guard distance > 0 else { return false }
            total += distance
            if total >= first.count { return false }
        }
        return true
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
