import Foundation

struct GridCell: Hashable, Sendable {
    let x: Int
    let y: Int
}

struct SnakeConfiguration: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let wrapsHorizontally: Bool
    let wrapsVertically: Bool
    let walls: Set<GridCell>

    init(columns: Int, rows: Int, wrapsHorizontally: Bool = true, wrapsVertically: Bool = true,
         walls: Set<GridCell> = []) {
        self.columns = columns
        self.rows = rows
        self.wrapsHorizontally = wrapsHorizontally
        self.wrapsVertically = wrapsVertically
        self.walls = Set(walls.filter { $0.x >= 0 && $0.x < columns && $0.y >= 0 && $0.y < rows })
    }

    static let firstMap = SnakeConfiguration(columns: 16, rows: 24)
    var boardCellCount: Int { columns * rows }
    var cellCount: Int { boardCellCount - walls.count }

    func boardContains(_ cell: GridCell) -> Bool {
        cell.x >= 0 && cell.x < columns && cell.y >= 0 && cell.y < rows
    }

    func contains(_ cell: GridCell) -> Bool { boardContains(cell) && !walls.contains(cell) }
    func isWall(_ cell: GridCell) -> Bool { walls.contains(cell) }

    /// Normalize board coordinates without rejecting wall cells. Tiling needs
    /// to distinguish an entirely blocked square from a partly blocked square.
    func boardResolved(_ cell: GridCell) -> GridCell? {
        guard columns > 0, rows > 0 else { return nil }
        if !wrapsHorizontally && !(0..<columns).contains(cell.x) { return nil }
        if !wrapsVertically && !(0..<rows).contains(cell.y) { return nil }
        return GridCell(x: (cell.x % columns + columns) % columns,
                        y: (cell.y % rows + rows) % rows)
    }

    func resolved(_ cell: GridCell) -> GridCell? {
        guard let cell = boardResolved(cell), contains(cell) else { return nil }
        return cell
    }

    func areNeighbors(_ a: GridCell, _ b: GridCell) -> Bool {
        guard contains(a), contains(b) else { return false }
        let rawX = abs(a.x - b.x)
        let rawY = abs(a.y - b.y)
        let dx = wrapsHorizontally ? min(rawX, columns - rawX) : rawX
        let dy = wrapsVertically ? min(rawY, rows - rawY) : rawY
        return dx + dy == 1
    }

    func neighbors(of cell: GridCell) -> [GridCell] {
        guard contains(cell) else { return [] }
        var result: [GridCell] = []
        for raw in [GridCell(x: cell.x + 1, y: cell.y), GridCell(x: cell.x - 1, y: cell.y),
                    GridCell(x: cell.x, y: cell.y + 1), GridCell(x: cell.x, y: cell.y - 1)] {
            if let neighbor = resolved(raw), !result.contains(neighbor) { result.append(neighbor) }
        }
        return result
    }
}

enum SnakeMap: String, CaseIterable, Identifiable, Sendable {
    case meadow
    case courtyard
    case doubleBars
    case staggered
    case twinRails
    case channels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meadow: return "无边空场"
        case .courtyard: return "外圈围墙"
        case .doubleBars: return "双横杠墙"
        case .staggered: return "交错隔墙"
        case .twinRails: return "双竖围栏"
        case .channels: return "多层通道"
        }
    }

    var subtitle: String {
        switch self {
        case .meadow: return "16 × 24 · 无墙环绕"
        case .courtyard: return "16 × 24 · 单格外圈墙"
        case .doubleBars: return "16 × 24 · 双横墙与角墙"
        case .staggered: return "16 × 24 · 交错横向隔墙"
        case .twinRails: return "16 × 24 · 双竖栏与侧边通道"
        case .channels: return "16 × 24 · 多层相连通道"
        }
    }

    var configuration: SnakeConfiguration {
        SnakeConfiguration(columns: 16, rows: 24, wrapsHorizontally: self != .courtyard,
                           wrapsVertically: self != .courtyard && self != .twinRails, walls: wallCells)
    }

    private var wallCells: Set<GridCell> {
        var cells: Set<GridCell> = []
        func fill(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>) {
            for y in ys { for x in xs { cells.insert(GridCell(x: x, y: y)) } }
        }
        switch self {
        case .meadow:
            break
        case .courtyard:
            fill(0...15, 0...0); fill(0...15, 23...23)
            fill(0...0, 1...22); fill(15...15, 1...22)
        case .doubleBars:
            fill(2...13, 6...7); fill(2...13, 16...17)
            for x in [0, 14] { for y in [0, 22] { fill(x...(x + 1), y...(y + 1)) } }
        case .staggered:
            fill(0...9, 4...5); fill(6...15, 10...11); fill(0...9, 16...17)
        case .twinRails:
            fill(0...15, 0...0); fill(0...15, 23...23)
            for x in [0, 15] { fill(x...x, 1...8); fill(x...x, 15...22) }
            fill(3...4, 5...18); fill(11...12, 5...18)
        case .channels:
            fill(0...11, 4...5); fill(4...15, 10...11)
            fill(0...11, 16...17); fill(4...15, 22...23)
            fill(10...11, 6...9); fill(4...5, 12...15); fill(10...11, 18...21)
        }
        return cells
    }
}

enum SnakePhase: Equatable, Sendable {
    case playing
    case filled
    case collision
}

/// A deterministic game whose cycles span playable cells only. Obstacle maps
/// are connected unions of 2×2 tiles; joining their small cycles along a tree
/// supplies a Hamiltonian cycle without solving an unbounded path search.

struct SnakeEngine: Sendable {
    let configuration: SnakeConfiguration
    let seed: UInt64
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
         seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        precondition(configuration.columns >= 2 && configuration.rows >= 2,
                     "Snake maps need at least two cells on each axis.")
        precondition(configuration.columns.isMultiple(of: 2) || configuration.rows.isMultiple(of: 2),
                     "The Hamiltonian map needs at least one even dimension.")
        self.configuration = configuration
        self.seed = seed
        var generator = SnakeRandom(seed: seed)
        precondition(configuration.cellCount >= 4, "Snake maps need at least four playable cells.")
        var route = SnakeCycleGraph.initialCycle(configuration: configuration, random: &generator)
        if generator.integer(lessThan: 2) == 0 { route.reverse() }
        // Rotating the cycle also varies the starting head relative to the seams.
        let start = generator.integer(lessThan: route.count)
        route = Array(route[start...] + route[..<start])
        cycle = route
        var lookup = [Int](repeating: -1, count: configuration.boardCellCount)
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
        guard configuration.contains(cell) else { return -1 }
        return indices[cell.y * configuration.columns + cell.x]
    }

    func forwardDistance(from start: GridCell, to end: GridCell) -> Int {
        let first = cycleIndex(of: start)
        let last = cycleIndex(of: end)
        guard first >= 0, last >= 0 else { return Int.max }
        return (last - first + cycle.count) % cycle.count
    }

    func neighbors(of cell: GridCell) -> [GridCell] {
        configuration.neighbors(of: cell)
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
        guard phase == .playing, let candidate = nextCell, let tail = snake.last, let head = snake.first else { return }
        let growing = candidate == food
        steps += 1
        guard configuration.areNeighbors(head, candidate),
              !occupied.contains(candidate) || (!growing && candidate == tail) else {
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
                guard configuration.contains(cell), !occupied.contains(cell) else { continue }
                if rank == 0 {
                    food = cell
                    reconfigureCycle()
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
            let firstSquare = random.integer(lessThan: configuration.boardCellCount)
            var split = original
            guard split.flip(square: firstSquare) else { continue }
            let components = split.componentLabels()
            if components.count == 1 { consider(split) }
            for attempt in 0..<16 {
                replanAttempts += 1
                let secondSquare: Int
                if attempt < nearby.count {
                    let offset = nearby[attempt]
                    guard let square = configuration.resolved(GridCell(x: firstSquare % columns + offset.0,
                                                                       y: firstSquare / columns + offset.1)) else { continue }
                    secondSquare = square.y * columns + square.x
                } else {
                    secondSquare = random.integer(lessThan: configuration.boardCellCount)
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
    private var count: Int { configuration.cellCount }

    private init(configuration: SnakeConfiguration) {
        self.configuration = configuration
        first = [Int](repeating: -1, count: configuration.boardCellCount)
        second = first
    }

    init(cycle: [GridCell], configuration: SnakeConfiguration) {
        self.init(configuration: configuration)
        let length = cycle.count
        for index in cycle.indices {
            let cell = cycle[index]
            let previous = cycle[(index + length - 1) % length]
            let next = cycle[(index + 1) % length]
            let id = cell.y * configuration.columns + cell.x
            first[id] = previous.y * configuration.columns + previous.x
            second[id] = next.y * configuration.columns + next.x
        }
    }

    private struct Tile {
        let anchor: GridCell
        // top-left, top-right, bottom-left, bottom-right (possibly at a seam)
        let cells: [Int]
    }

    static func initialCycle(configuration: SnakeConfiguration, random: inout SnakeRandom) -> [GridCell] {
        // Row-major order and fixed neighbor order make seeds reproducible
        // across processes; wall Sets are used only for membership checks.
        for parity in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            if let tiles = tilePartition(configuration, x: parity.0, y: parity.1) {
                return joinTiles(tiles, configuration: configuration, random: &random)
            }
        }
        precondition(configuration.walls.isEmpty, "Obstacle maps must be connected unions of whole 2×2 tiles.")
        return rectangleCycle(configuration, random: &random)
    }

    private static func tilePartition(_ map: SnakeConfiguration, x parityX: Int, y parityY: Int) -> [Tile]? {
        var tiles: [Tile] = []
        var covered = [Bool](repeating: false, count: map.boardCellCount)
        var coveredCount = 0
        for y in stride(from: parityY, to: map.rows, by: 2) {
            for x in stride(from: parityX, to: map.columns, by: 2) {
                let raw = [GridCell(x: x, y: y), GridCell(x: x + 1, y: y),
                           GridCell(x: x, y: y + 1), GridCell(x: x + 1, y: y + 1)]
                let cells = raw.compactMap { map.boardResolved($0) }.filter { map.contains($0) }
                if cells.isEmpty { continue }
                guard cells.count == 4, Set(cells).count == 4 else { return nil }
                let ids = cells.map { $0.y * map.columns + $0.x }
                for id in ids {
                    guard !covered[id] else { return nil }
                    covered[id] = true
                    coveredCount += 1
                }
                tiles.append(Tile(anchor: GridCell(x: x, y: y), cells: ids))
            }
        }
        return coveredCount == map.cellCount ? tiles : nil
    }

    private static func joinTiles(_ tiles: [Tile], configuration map: SnakeConfiguration,
                                  random: inout SnakeRandom) -> [GridCell] {
        var graph = SnakeCycleGraph(configuration: map)
        var byAnchor: [GridCell: Int] = [:]
        for (index, tile) in tiles.enumerated() {
            byAnchor[tile.anchor] = index
            let ring = [tile.cells[0], tile.cells[1], tile.cells[3], tile.cells[2]]
            for position in ring.indices {
                graph.first[ring[position]] = ring[(position + 3) % 4]
                graph.second[ring[position]] = ring[(position + 1) % 4]
            }
        }
        let start = random.integer(lessThan: tiles.count)
        var seen = [Bool](repeating: false, count: tiles.count)
        seen[start] = true
        var stack = [start]
        var joined = 1
        let directions = [(2, 0), (-2, 0), (0, 2), (0, -2)]
        while let current = stack.last {
            var candidates: [(tile: Int, direction: Int)] = []
            for (direction, offset) in directions.enumerated() {
                let anchor = tiles[current].anchor
                guard let next = map.boardResolved(GridCell(x: anchor.x + offset.0, y: anchor.y + offset.1)),
                      let index = byAnchor[next], !seen[index],
                      !candidates.contains(where: { $0.tile == index }) else { continue }
                candidates.append((index, direction))
            }
            guard !candidates.isEmpty else { stack.removeLast(); continue }
            let selected = candidates[random.integer(lessThan: candidates.count)]
            let a = tiles[current].cells
            let b = tiles[selected.tile].cells
            switch selected.direction {
            case 0: graph.join((a[1], a[3]), (b[0], b[2]))
            case 1: graph.join((a[0], a[2]), (b[1], b[3]))
            case 2: graph.join((a[2], a[3]), (b[0], b[1]))
            default: graph.join((a[0], a[1]), (b[2], b[3]))
            }
            seen[selected.tile] = true
            joined += 1
            stack.append(selected.tile)
        }
        precondition(joined == tiles.count, "Playable tile graph must be connected.")
        guard let walk = graph.walk(start: tiles[start].cells[0]) else {
            preconditionFailure("Tree merges must produce one spanning cycle.")
        }
        return walk.order.map { GridCell(x: $0 % map.columns, y: $0 / map.columns) }
    }

    /// Every merge removes one edge from each of two disjoint cycles and adds
    /// two legal cross edges, preserving degree two and joining the components.
    private mutating func join(_ a: (Int, Int), _ b: (Int, Int)) {
        precondition(connected(a.0, a.1) && connected(b.0, b.1))
        precondition(configuration.areNeighbors(cell(a.0), cell(b.0)) && configuration.areNeighbors(cell(a.1), cell(b.1)))
        replace(a.0, removing: a.1, adding: b.0)
        replace(a.1, removing: a.0, adding: b.1)
        replace(b.0, removing: b.1, adding: a.0)
        replace(b.1, removing: b.0, adding: a.1)
    }

    /// Odd/even empty test boards need not tile into 2×2 squares. A bounded
    /// rail cycle (or toroidal serpentine) handles these obstacle-free cases.
    private static func rectangleCycle(_ map: SnakeConfiguration, random: inout SnakeRandom) -> [GridCell] {
        let horizontal = map.rows.isMultiple(of: 2)
        let width = horizontal ? map.columns : map.rows
        let height = horizontal ? map.rows : map.columns
        var route: [GridCell] = []
        if map.wrapsHorizontally && map.wrapsVertically {
            for y in 0..<height {
                for x in 0..<width { route.append(GridCell(x: y.isMultiple(of: 2) ? x : width - 1 - x, y: y)) }
            }
        } else {
            route.append(GridCell(x: 0, y: 0))
            for y in 0..<height {
                for x in 1..<width { route.append(GridCell(x: y.isMultiple(of: 2) ? x : width - x, y: y)) }
            }
            for y in stride(from: height - 1, through: 1, by: -1) { route.append(GridCell(x: 0, y: y)) }
        }
        return route.map { horizontal ? $0 : GridCell(x: $0.y, y: $0.x) }
    }

    private func cell(_ id: Int) -> GridCell { GridCell(x: id % configuration.columns, y: id / configuration.columns) }

    private func corners(square: Int) -> (a: Int, b: Int, c: Int, d: Int)? {
        let columns = configuration.columns
        let x = square % columns
        let y = square / columns
        guard (x + 1 < columns || configuration.wrapsHorizontally),
              (y + 1 < configuration.rows || configuration.wrapsVertically) else { return nil }
        let nextX = (x + 1) % columns
        let nextY = (y + 1) % configuration.rows
        let result = (square, y * columns + nextX, nextY * columns + x, nextY * columns + nextX)
        guard [result.0, result.1, result.2, result.3].allSatisfy({ configuration.contains(cell($0)) }) else { return nil }
        return result
    }

    private func connected(_ a: Int, _ b: Int) -> Bool { first[a] == b || second[a] == b }

    func removedEdgeOrigins(square: Int) -> (Int, Int)? {
        guard let (a, b, c, d) = corners(square: square) else { return nil }
        if connected(a, b) && connected(c, d) && !connected(a, c) && !connected(b, d) { return (a, c) }
        if connected(a, c) && connected(b, d) && !connected(a, b) && !connected(c, d) { return (a, b) }
        return nil
    }

    mutating func flip(square: Int) -> Bool {
        guard let removed = removedEdgeOrigins(square: square), let (a, b, c, d) = corners(square: square) else { return false }
        if removed.1 == c {
            replace(a, removing: b, adding: c); replace(b, removing: a, adding: d)
            replace(c, removing: d, adding: a); replace(d, removing: c, adding: b)
        } else {
            replace(a, removing: c, adding: b); replace(b, removing: d, adding: a)
            replace(c, removing: a, adding: d); replace(d, removing: b, adding: c)
        }
        return true
    }

    private mutating func replace(_ id: Int, removing old: Int, adding new: Int) {
        if first[id] == old { first[id] = new }
        else { precondition(second[id] == old); second[id] = new }
    }

    func componentLabels() -> (labels: [Int], count: Int) {
        var labels = [Int](repeating: -1, count: first.count)
        var components = 0
        for start in first.indices where first[start] >= 0 && labels[start] == -1 {
            var previous = -1
            var current = start
            while labels[current] == -1 {
                labels[current] = components
                let next = first[current] == previous ? second[current] : first[current]
                previous = current
                current = next
            }
            components += 1
        }
        return (labels, components)
    }

    func differs(from other: SnakeCycleGraph) -> Bool {
        for id in first.indices where first[id] >= 0 {
            if !other.connected(id, first[id]) || !other.connected(id, second[id]) { return true }
        }
        return false
    }

    private func walk(start: Int) -> (order: [Int], indices: [Int])? {
        var order: [Int] = []
        order.reserveCapacity(count)
        var indices = [Int](repeating: -1, count: first.count)
        var previous = -1
        var current = start
        while indices[current] == -1 {
            indices[current] = order.count
            order.append(current)
            let next = first[current] == previous ? second[current] : first[current]
            guard next >= 0, configuration.areNeighbors(cell(current), cell(next)) else { return nil }
            previous = current
            current = next
        }
        return current == start && order.count == count ? (order, indices) : nil
    }

    func orientedOrder(head: Int, body: [Int], food: Int) -> (order: [Int], indices: [Int], foodDistance: Int)? {
        guard var candidate = walk(start: head) else { return nil }
        if !bodyIsOrdered(body, indices: candidate.indices, reversed: false) {
            guard bodyIsOrdered(body, indices: candidate.indices, reversed: true) else { return nil }
            candidate.order = [head] + candidate.order.dropFirst().reversed()
            for id in candidate.indices.indices where candidate.indices[id] >= 0 {
                candidate.indices[id] = (count - candidate.indices[id]) % count
            }
        }
        return (candidate.order, candidate.indices, candidate.indices[food])
    }

    private func bodyIsOrdered(_ body: [Int], indices: [Int], reversed: Bool) -> Bool {
        var total = 0
        for index in 1..<body.count {
            let before = indices[body[index - 1]]
            let after = indices[body[index]]
            let distance = reversed ? (before - after + count) % count : (after - before + count) % count
            guard distance > 0 else { return false }
            total += distance
            if total >= count { return false }
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
