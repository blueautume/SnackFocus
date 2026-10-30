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
    var previous: GridCell?
    var total = 0
    for cell in engine.snake.reversed() {
        if let previous {
            let distance = engine.forwardDistance(from: previous, to: cell)
            expect(distance > 0, "Repeated body index, seed \(engine.seed)")
            expect(adjacent(previous, cell, on: engine.configuration), "Disconnected body, seed \(engine.seed)")
            total += distance
        }
        previous = cell
    }
    expect(total < engine.configuration.cellCount, "Body overtook its cycle order, seed \(engine.seed)")
}

private func checkCycle(_ engine: SnakeEngine) {
    let map = engine.configuration
    expect(engine.cycle.count == map.cellCount && Set(engine.cycle).count == map.cellCount, "Cycle is not spanning and unique")
    for (index, cell) in engine.cycle.enumerated() {
        expect((0..<map.columns).contains(cell.x) && (0..<map.rows).contains(cell.y), "Cycle outside board")
        expect(engine.cycleIndex(of: cell) == index, "Cycle lookup mismatch")
        expect(adjacent(cell, engine.cycle[(index + 1) % map.cellCount], on: map), "Disconnected cycle edge or seam")
    }
}

/// Compare undirected edges, so rotating/reversing an unchanged array cannot
/// pass as a genuine dynamic reconfiguration.
private func edgeSetsDiffer(_ before: [GridCell], _ after: [GridCell], on map: SnakeConfiguration) -> Bool {
    var ranks = [Int](repeating: 0, count: map.cellCount)
    for (rank, cell) in before.enumerated() { ranks[cell.y * map.columns + cell.x] = rank }
    for index in after.indices {
        let a = after[index]
        let b = after[(index + 1) % after.count]
        let difference = abs(ranks[a.y * map.columns + a.x] - ranks[b.y * map.columns + b.x])
        if difference != 1 && difference != map.cellCount - 1 { return true }
    }
    return false
}

private func checkCycles() {
    let maps = [(2, 2), (2, 3), (3, 2), (2, 24), (24, 2), (4, 4), (6, 8), (8, 6),
                (16, 24), (3, 4), (4, 3), (17, 24), (24, 17)]
    for strategy in SnakeStrategy.allCases {
        for (columns, rows) in maps {
            for seed in 0..<64 {
                let engine = SnakeEngine(configuration: SnakeConfiguration(columns: columns, rows: rows), seed: UInt64(seed), strategy: strategy)
                checkCycle(engine)
                checkBodyOrder(engine)
                expect(engine.replanAttempts <= SnakeEngine.maximumReplanAttemptsPerFood, "Initial search exceeded budget")
            }
        }
    }
}

private struct GameResult {
    let steps: Int
    let wrappedX: Bool
    let wrappedY: Bool
    let trajectory: UInt64
    let replans: Int
    let middleReplans: Int
}

private func completeGame(map: SnakeConfiguration, seed: UInt64, strategy: SnakeStrategy) -> GameResult {
    var engine = SnakeEngine(configuration: map, seed: seed, strategy: strategy)
    var occupied = Set(engine.snake)
    var sinceFood = 0
    var wrappedX = false
    var wrappedY = false
    var trajectory: UInt64 = 0xCBF29CE484222325
    var middleReplans = 0
    expect(engine.snake.count == 4, "Initial length must be four")
    if let food = engine.food { expect(!occupied.contains(food), "Initial food under body") }
    while engine.phase == .playing {
        guard let head = engine.snake.first, let tail = engine.snake.last,
              let candidate = engine.nextCell, let oldFood = engine.food else {
            fatalError("Playing game missing state")
        }
        let oldLength = engine.snake.count
        let oldCycle = engine.cycle
        let oldReplans = engine.cycleReplans
        let oldAttempts = engine.replanAttempts
        let growing = candidate == oldFood
        let advance = engine.forwardDistance(from: head, to: candidate)
        let foodDistance = engine.forwardDistance(from: head, to: oldFood)
        let tailDistance = engine.forwardDistance(from: head, to: tail)
        expect(advance > 0 && advance <= foodDistance, "Shortcut skipped food, seed \(seed)")
        expect(advance < tailDistance || (advance == tailDistance && !growing), "Shortcut overtook tail, seed \(seed)")
        expect(adjacent(head, candidate, on: map), "Non-adjacent movement, seed \(seed)")
        if !growing { occupied.remove(tail) }
        expect(!occupied.contains(candidate), "Occupied-cell movement, seed \(seed)")
        engine.step()
        expect(engine.phase != .collision, "Collision, seed \(seed), step \(engine.steps)")
        expect(engine.snake.first == candidate, "Unexpected movement")
        expect(engine.snake.count == oldLength + (growing ? 1 : 0), "Incorrect growth")
        occupied.insert(candidate)
        sinceFood += 1
        expect(sinceFood <= map.cellCount, "Food exceeded one-cycle move bound, seed \(seed)")
        expect(engine.replanAttempts - oldAttempts <= SnakeEngine.maximumReplanAttemptsPerFood, "Search exceeded fixed budget")
        if abs(candidate.x - head.x) > 1 { wrappedX = true }
        if abs(candidate.y - head.y) > 1 { wrappedY = true }
        if engine.steps <= 128 {
            trajectory = (trajectory ^ UInt64(candidate.y * map.columns + candidate.x)) &* 0x100000001B3
        }
        if growing {
            expect(Set(engine.snake) == occupied && occupied.count == engine.snake.count, "Body duplicate or missing cell")
            expect(engine.foodsEaten == engine.snake.count - 4, "Food counter mismatch")
            checkBodyOrder(engine)
            if engine.cycleReplans > oldReplans {
                expect(engine.cycleReplans == oldReplans + 1, "More than one committed plan per food")
                expect(edgeSetsDiffer(oldCycle, engine.cycle, on: map), "Replan changed array order only")
                checkCycle(engine)
                if oldLength >= map.cellCount / 4 && oldLength < map.cellCount * 3 / 4 { middleReplans += 1 }
            } else {
                expect(engine.cycle == oldCycle, "Unreported cycle change")
            }
            if let food = engine.food {
                let oldHeadRank = oldCycle.firstIndex(of: candidate)!
                let oldFoodRank = oldCycle.firstIndex(of: food)!
                let previousDistance = (oldFoodRank - oldHeadRank + map.cellCount) % map.cellCount
                expect(engine.forwardDistance(from: candidate, to: food) <= previousDistance, "Replan worsened food rank")
            }
            sinceFood = 0
        } else {
            expect(engine.cycle == oldCycle && engine.replanAttempts == oldAttempts && engine.cycleReplans == oldReplans,
                   "Cycle must stay frozen between foods")
            expect(engine.forwardDistance(from: candidate, to: oldFood) < foodDistance, "Frozen-cycle food rank did not decrease")
        }
        if let food = engine.food { expect(!occupied.contains(food), "Food placed under body, seed \(seed)") }
        expect(engine.steps <= map.cellCount * map.cellCount, "Completion bound exceeded")
    }
    expect(engine.phase == .filled && engine.snake.count == map.cellCount && occupied.count == map.cellCount, "Incomplete board")
    expect(engine.food == nil, "Filled board still has food")
    if strategy == .safeShortcuts { expect(engine.cycleReplans == 0 && engine.replanAttempts == 0, "Classic strategy changed") }
    let finalSteps = engine.steps
    let finalSnake = engine.snake
    engine.step()
    expect(engine.steps == finalSteps && engine.snake == finalSnake, "Filled game should stop moving")
    return GameResult(steps: engine.steps, wrappedX: wrappedX, wrappedY: wrappedY, trajectory: trajectory,
                      replans: engine.cycleReplans, middleReplans: middleReplans)
}

private func checkDeterminismAndDiversity() {
    for strategy in SnakeStrategy.allCases {
        for seed: UInt64 in [0, 1, 42, UInt64.max, 0xC0FFEE] {
            var a = SnakeEngine(seed: seed, strategy: strategy)
            var b = SnakeEngine(seed: seed, strategy: strategy)
            expect(a.cycle == b.cycle && a.snake == b.snake && a.food == b.food, "Initial seed not deterministic")
            for _ in 0..<2_000 {
                a.step(); b.step()
                expect(a.snake == b.snake && a.food == b.food && a.phase == b.phase && a.cycle == b.cycle,
                       "Game seed not deterministic")
            }
        }
        var foods: Set<GridCell> = []
        var heads: Set<GridCell> = []
        var routes: Set<[GridCell]> = []
        for seed in 0..<2_048 {
            let engine = SnakeEngine(seed: UInt64(seed), strategy: strategy)
            if let food = engine.food { foods.insert(food) }
            if let head = engine.snake.first { heads.insert(head) }
            if seed < 128 { routes.insert(Array(engine.cycle.prefix(16))) }
        }
        expect(foods.count > 350 && heads.count > 350 && routes.count > 100, "Seed diversity unexpectedly low")
    }
}

private func checkClassicCompatibility() {
    // Recorded from the previously shipped engine, before adding strategies.
    let fixtures: [(UInt64, Int, UInt64)] = [
        (0, 33_802, 3_808_118_174_082_344_886),
        (42, 35_311, 4_796_459_910_685_442_140),
        (UInt64.max, 35_374, 12_547_730_101_368_484_242)
    ]
    for (seed, steps, expectedDigest) in fixtures {
        var engine = SnakeEngine(seed: seed, strategy: .safeShortcuts)
        var digest: UInt64 = 0xCBF29CE484222325
        while engine.phase == .playing {
            engine.step()
            let head = engine.snake[0]
            let food = engine.food.map { $0.y * 16 + $0.x } ?? 384
            digest = (digest ^ UInt64(head.y * 16 + head.x)) &* 0x100000001B3
            digest = (digest ^ UInt64(food)) &* 0x100000001B3
        }
        expect(engine.steps == steps && digest == expectedDigest, "Classic seed behavior changed")
    }
}

private func benchmark() {
    var timings: [Double] = []
    for seed: UInt64 in [42, 1_337] {
        let initialStart = Date()
        var engine = SnakeEngine(seed: seed, strategy: .dynamicCycle)
        timings.append(Date().timeIntervalSince(initialStart) * 1_000)
        while engine.phase == .playing {
            if engine.nextCell == engine.food {
                let attempts = engine.replanAttempts
                let started = Date()
                engine.step()
                let milliseconds = Date().timeIntervalSince(started) * 1_000
                if engine.replanAttempts > attempts { timings.append(milliseconds) }
            } else {
                engine.step()
            }
        }
    }
    timings.sort()
    print(String(format: "Dynamic search (%d samples): median=%.3fms p95=%.3fms max=%.3fms", timings.count,
                 timings[timings.count / 2], timings[timings.count * 95 / 100], timings.last!))
}

@main
private enum SnakeEngineChecks {
    static func main() {
        if ProcessInfo.processInfo.environment["SNAKE_BENCHMARK_ONLY"] == "1" { benchmark(); return }
        let started = Date()
        checkCycles()
        checkDeterminismAndDiversity()
        checkClassicCompatibility()
        let defaultSeeds = Int(ProcessInfo.processInfo.environment["SNAKE_DEFAULT_SEEDS"] ?? "256") ?? 256
        expect(defaultSeeds > 0, "SNAKE_DEFAULT_SEEDS must be positive")
        let suites = [(4, 4, 1_000), (6, 8, 1_000), (8, 6, 1_000), (16, 24, defaultSeeds)]
        for strategy in SnakeStrategy.allCases {
            var defaultResults: [GameResult] = []
            for (columns, rows, count) in suites {
                let map = SnakeConfiguration(columns: columns, rows: rows)
                var results: [GameResult] = []
                for index in 0..<count {
                    let seed = UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
                    results.append(completeGame(map: map, seed: seed, strategy: strategy))
                }
                print("PASS \(strategy.rawValue) \(columns)×\(rows): \(count) seeded games filled")
                if map == .firstMap { defaultResults = results }
            }
            expect(defaultResults.contains(where: \.wrappedX) && defaultResults.contains(where: \.wrappedY), "Missing toroidal seam crossing")
            if defaultSeeds >= 32 {
                expect(Set(defaultResults.map(\.trajectory)).count > defaultSeeds * 9 / 10, "Routes too similar across seeds")
            }
            let steps = defaultResults.map(\.steps).sorted()
            let median = steps[steps.count / 2]
            print("\(strategy.rawValue) 16×24 moves min/median/p90/max: \(steps.first!)/\(median)/\(steps[min(steps.count - 1, steps.count * 9 / 10)])/\(steps.last!)")
            print(String(format: "Median at10steps/s: %.1fmin", Double(median) / 600))
            if strategy == .dynamicCycle {
                expect(defaultResults.allSatisfy { $0.replans > 0 && $0.middleReplans > 0 }, "Dynamic strategy must truly replan during midgame")
                let replans = defaultResults.map(\.replans).sorted()
                let middles = defaultResults.map(\.middleReplans).sorted()
                print("True edge replans min/median/max: \(replans.first!)/\(replans[replans.count / 2])/\(replans.last!); midgame minimum: \(middles.first!)")
            }
        }
        benchmark()
        print(String(format: "PASS topology, body order, food bound, frozen plans, search budget, deterministic diversity and classic compatibility (%.2fs)", Date().timeIntervalSince(started)))
    }
}
