import Foundation

@inline(__always)
private func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !condition() { fatalError(message()) }
}

private func adjacent(_ a: GridCell, _ b: GridCell, on map: SnakeConfiguration) -> Bool {
    let dx = abs(a.x - b.x)
    let dy = abs(a.y - b.y)
    return min(dx, map.columns - dx) + min(dy, map.rows - dy) == 1
}

private func checkBodyOrder(_ engine: SnakeEngine) {
    let tailToHead = engine.snake.reversed()
    var previous: GridCell?
    var total = 0
    for cell in tailToHead {
        if let previous {
            let distance = engine.forwardDistance(from: previous, to: cell)
            expect(distance > 0, "Repeated body index, seed \(engine.seed)")
            expect(adjacent(previous, cell, on: engine.configuration), "Disconnected body, seed \(engine.seed)")
            total += distance
        }
        previous = cell
    }
    expect(total < engine.configuration.cellCount, "Body overtook itself along the cycle, seed \(engine.seed)")
}

private func checkCycles() {
    let maps = [(2, 2), (2, 3), (3, 2), (2, 24), (24, 2), (4, 4), (6, 8), (8, 6),
                (16, 24), (3, 4), (4, 3), (17, 24), (24, 17)]
    for (columns, rows) in maps {
        let map = SnakeConfiguration(columns: columns, rows: rows)
        for seed in 0..<64 {
            let engine = SnakeEngine(configuration: map, seed: UInt64(seed))
            expect(engine.cycle.count == map.cellCount, "Wrong cycle size")
            expect(Set(engine.cycle).count == map.cellCount, "Cycle repeated a cell")
            for (index, cell) in engine.cycle.enumerated() {
                expect((0..<columns).contains(cell.x) && (0..<rows).contains(cell.y), "Cycle outside board")
                expect(engine.cycleIndex(of: cell) == index, "Cycle lookup mismatch")
                expect(adjacent(cell, engine.cycle[(index + 1) % map.cellCount], on: map), "Cycle seam not adjacent")
            }
            checkBodyOrder(engine)
        }
    }
}

private struct GameResult {
    let steps: Int
    let wrappedX: Bool
    let wrappedY: Bool
    let trajectory: UInt64
}

private func completeGame(map: SnakeConfiguration, seed: UInt64) -> GameResult {
    var engine = SnakeEngine(configuration: map, seed: seed)
    var occupied = Set(engine.snake)
    var sinceFood = 0
    var wrappedX = false
    var wrappedY = false
    var trajectory: UInt64 = 0xCBF29CE484222325
    expect(engine.snake.count == 4, "Initial length must be four")
    if let food = engine.food { expect(!occupied.contains(food), "Initial food under body") }
    while engine.phase == .playing {
        guard let head = engine.snake.first, let tail = engine.snake.last,
              let candidate = engine.nextCell, let oldFood = engine.food else {
            fatalError("Playing game missing head, tail, next step, or food")
        }
        let oldLength = engine.snake.count
        let growing = candidate == oldFood
        let advance = engine.forwardDistance(from: head, to: candidate)
        let foodDistance = engine.forwardDistance(from: head, to: oldFood)
        let tailDistance = engine.forwardDistance(from: head, to: tail)
        expect(advance > 0 && advance <= foodDistance, "Shortcut skipped food, seed \(seed)")
        expect(advance < tailDistance || (advance == tailDistance && !growing), "Shortcut overtook tail, seed \(seed)")
        expect(adjacent(head, candidate, on: map), "Non-adjacent movement, seed \(seed)")
        if !growing { occupied.remove(tail) }
        expect(!occupied.contains(candidate), "Attempted occupied-cell movement, seed \(seed)")
        engine.step()
        expect(engine.phase != .collision, "Collision, seed \(seed), step \(engine.steps)")
        expect(engine.snake.first == candidate, "Unexpected movement")
        expect(engine.snake.count == oldLength + (growing ? 1 : 0), "Incorrect growth")
        occupied.insert(candidate)
        sinceFood += 1
        expect(sinceFood <= map.cellCount, "Food exceeded one-cycle move bound, seed \(seed)")
        if abs(candidate.x - head.x) > 1 { wrappedX = true }
        if abs(candidate.y - head.y) > 1 { wrappedY = true }
        if engine.steps <= 128 {
            trajectory = (trajectory ^ UInt64(candidate.y * map.columns + candidate.x)) &* 0x100000001B3
        }
        if growing {
            expect(Set(engine.snake) == occupied && occupied.count == engine.snake.count, "Body duplicate or missing cell")
            expect(engine.foodsEaten == engine.snake.count - 4, "Food counter mismatch")
            checkBodyOrder(engine)
            sinceFood = 0
        }
        if let food = engine.food { expect(!occupied.contains(food), "Food placed under body, seed \(seed)") }
        expect(engine.steps <= map.cellCount * map.cellCount, "Game exceeded proven completion bound")
    }
    expect(engine.phase == .filled, "Game did not finish filled")
    expect(engine.snake.count == map.cellCount && occupied.count == map.cellCount, "Incomplete board")
    expect(engine.food == nil, "Filled board still has food")
    let finalSteps = engine.steps
    let finalSnake = engine.snake
    engine.step()
    expect(engine.steps == finalSteps && engine.snake == finalSnake, "Filled game should stop moving")
    return GameResult(steps: engine.steps, wrappedX: wrappedX, wrappedY: wrappedY, trajectory: trajectory)
}

private func checkDeterminismAndDiversity() {
    for seed: UInt64 in [0, 1, 42, UInt64.max, 0xC0FFEE] {
        var a = SnakeEngine(seed: seed)
        var b = SnakeEngine(seed: seed)
        expect(a.cycle == b.cycle && a.snake == b.snake && a.food == b.food, "Initial seed not deterministic")
        for _ in 0..<2_000 {
            a.step(); b.step()
            expect(a.snake == b.snake && a.food == b.food && a.phase == b.phase, "Game seed not deterministic")
        }
    }
    var foods: Set<GridCell> = []
    var heads: Set<GridCell> = []
    var routes: Set<[GridCell]> = []
    for seed in 0..<2_048 {
        let engine = SnakeEngine(seed: UInt64(seed))
        if let food = engine.food { foods.insert(food) }
        if let head = engine.snake.first { heads.insert(head) }
        if seed < 128 { routes.insert(Array(engine.cycle.prefix(16))) }
    }
    expect(foods.count > 350, "Food distribution has unexpectedly low diversity: \(foods.count)")
    expect(heads.count > 350, "Starting position diversity too low: \(heads.count)")
    expect(routes.count > 100, "Cycle transforms lack variety: \(routes.count)")
}

@main
private enum SnakeEngineChecks {
    static func main() {
        let started = Date()
        checkCycles()
        checkDeterminismAndDiversity()
        let defaultSeeds = Int(ProcessInfo.processInfo.environment["SNAKE_DEFAULT_SEEDS"] ?? "256") ?? 256
        expect(defaultSeeds > 0, "SNAKE_DEFAULT_SEEDS must be positive")
        let suites = [(4, 4, 1_000), (6, 8, 1_000), (8, 6, 1_000), (16, 24, defaultSeeds)]
        var defaultResults: [GameResult] = []
        for (columns, rows, count) in suites {
            let map = SnakeConfiguration(columns: columns, rows: rows)
            var results: [GameResult] = []
            for index in 0..<count {
                let seed = UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
                results.append(completeGame(map: map, seed: seed))
            }
            print("PASS \(columns)×\(rows): \(count) seeded games filled without collision")
            if map == .firstMap { defaultResults = results }
        }
        expect(defaultResults.contains(where: \.wrappedX), "Never crossed horizontal torus seam")
        expect(defaultResults.contains(where: \.wrappedY), "Never crossed vertical torus seam")
        if defaultSeeds >= 32 {
            expect(Set(defaultResults.map(\.trajectory)).count > defaultSeeds * 9 / 10, "Routes too similar across seeds")
        }
        let steps = defaultResults.map(\.steps).sorted()
        let minimum = steps.first!
        let median = steps[steps.count / 2]
        let p90 = steps[min(steps.count - 1, steps.count * 9 / 10)]
        let maximum = steps.last!
        print("16×24 steps: min=\(minimum), median=\(median), p90=\(p90), max=\(maximum)")
        print(String(format: "At 10 steps/s: min=%.1f, median=%.1f, p90=%.1f, max=%.1f minutes", Double(minimum) / 600, Double(median) / 600, Double(p90) / 600, Double(maximum) / 600))
        print(String(format: "PASS cycle topology, deterministic seeds, route/food diversity, per-food bound, stop-at-fill (%.2fs)", Date().timeIntervalSince(started)))
    }
}
