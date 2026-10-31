import Foundation

@inline(__always)
private func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !condition() { fatalError(message()) }
}

/// Deliberately independent of the production distance/neighbor helpers.
private func adjacent(_ a: GridCell, _ b: GridCell, on map: SnakeConfiguration) -> Bool {
    guard a.x >= 0, a.x < map.columns, a.y >= 0, a.y < map.rows,
          b.x >= 0, b.x < map.columns, b.y >= 0, b.y < map.rows,
          !map.walls.contains(a), !map.walls.contains(b) else { return false }
    let dx = abs(a.x - b.x)
    let dy = abs(a.y - b.y)
    return (dy == 0 && (dx == 1 || (map.wrapsHorizontally && dx == map.columns - 1)))
        || (dx == 0 && (dy == 1 || (map.wrapsVertically && dy == map.rows - 1)))
}

private func checkBodyOrder(_ engine: SnakeEngine) {
    var previous: GridCell?
    var total = 0
    for cell in engine.snake.reversed() {
        if let previous {
            let distance = engine.forwardDistance(from: previous, to: cell)
            expect(distance > 0, "Repeated body index, seed \(engine.seed)")
            expect(adjacent(previous, cell, on: engine.configuration), "Disconnected body or wall crossing, seed \(engine.seed)")
            total += distance
        }
        previous = cell
    }
    expect(total < engine.configuration.cellCount, "Body overtook its cycle order, seed \(engine.seed)")
}

private func checkCycle(_ engine: SnakeEngine) {
    let map = engine.configuration
    expect(engine.cycle.allSatisfy { !map.walls.contains($0) }, "Cycle includes a wall")
    expect(engine.cycle.count == map.cellCount && Set(engine.cycle).count == map.cellCount, "Cycle is not spanning and unique")
    for (index, cell) in engine.cycle.enumerated() {
        expect((0..<map.columns).contains(cell.x) && (0..<map.rows).contains(cell.y), "Cycle outside board")
        expect(engine.cycleIndex(of: cell) == index, "Cycle lookup mismatch")
        expect(adjacent(cell, engine.cycle[(index + 1) % map.cellCount], on: map), "Disconnected cycle or wall crossing")
    }
}

private func edgeSetsDiffer(_ before: [GridCell], _ after: [GridCell], on map: SnakeConfiguration) -> Bool {
    var ranks = [Int](repeating: -1, count: map.boardCellCount)
    for (rank, cell) in before.enumerated() { ranks[cell.y * map.columns + cell.x] = rank }
    for index in after.indices {
        let a = after[index]
        let b = after[(index + 1) % after.count]
        let difference = abs(ranks[a.y * map.columns + a.x] - ranks[b.y * map.columns + b.x])
        if difference != 1 && difference != map.cellCount - 1 { return true }
    }
    return false
}

private func checkTopology(_ map: SnakeConfiguration) {
    let cells = (0..<map.rows).flatMap { y in (0..<map.columns).map { GridCell(x: $0, y: y) } }
    for cell in cells {
        let expected = Set(cells.filter { adjacent(cell, $0, on: map) })
        expect(Set(map.neighbors(of: cell)) == expected, "Neighbor list does not match walls")
        expect(map.neighbors(of: cell).count == expected.count, "Duplicate neighbor")
        for other in cells {
            expect(map.areNeighbors(cell, other) == adjacent(cell, other, on: map), "Adjacency helper does not match topology")
        }
    }
    expect(map.cellCount == map.boardCellCount - map.walls.count, "Playable count includes walls")
    expect(!map.contains(GridCell(x: -1, y: 0)) && !map.contains(GridCell(x: 0, y: map.rows)), "Contains accepted outside cell")
    let engine = SnakeEngine(configuration: map, seed: 0)
    for wall in map.walls {
        expect(map.boardContains(wall) && !map.contains(wall) && map.isWall(wall), "Wall/bounds distinction wrong")
        expect(map.resolved(wall) == nil && map.neighbors(of: wall).isEmpty, "Wall resolves as playable")
        expect(engine.cycleIndex(of: wall) == -1, "Wall has a cycle index")
        expect(engine.forwardDistance(from: wall, to: engine.snake[0]) == Int.max, "Invalid cycle distance not rejected")
    }
    expect(engine.cycleIndex(of: GridCell(x: map.columns, y: 0)) == -1, "Outside cycle lookup unsafe")
    let horizontal = GridCell(x: map.columns - 1, y: 0)
    let vertical = GridCell(x: 0, y: 0)
    expect(map.resolved(GridCell(x: -1, y: 0)) == (map.wrapsHorizontally && !map.walls.contains(horizontal) ? horizontal : nil), "Horizontal resolution wrong")
    expect(map.resolved(GridCell(x: 0, y: map.rows)) == (map.wrapsVertically && !map.walls.contains(vertical) ? vertical : nil), "Vertical resolution wrong")
}

private func checkCycles() {
    let dimensions = [(2, 2), (2, 3), (3, 2), (2, 5), (5, 2), (2, 24), (24, 2),
                      (4, 4), (6, 8), (8, 6), (3, 4), (4, 3), (7, 10), (10, 7)]
    for (columns, rows) in dimensions {
        for wrapsX in [false, true] {
            for wrapsY in [false, true] {
                let map = SnakeConfiguration(columns: columns, rows: rows, wrapsHorizontally: wrapsX, wrapsVertically: wrapsY)
                checkTopology(map)
                for seed in 0..<32 {
                    let engine = SnakeEngine(configuration: map, seed: UInt64(seed))
                    checkCycle(engine)
                    checkBodyOrder(engine)
                    expect(engine.replanAttempts <= SnakeEngine.maximumReplanAttemptsPerFood, "Initial search exceeded budget")
                }
            }
        }
    }
    expect(SnakeMap.allCases.count == 6 && Set(SnakeMap.allCases.map(\.rawValue)).count == 6, "Map catalog changed unexpectedly")
    expect(SnakeMap.meadow.configuration == .firstMap, "Default map mismatch")
    let playableCounts = ["meadow": 384, "courtyard": 308, "doubleBars": 320, "staggered": 324, "twinRails": 264, "channels": 264]
    for map in SnakeMap.allCases {
        expect(map.configuration.columns == 16 && map.configuration.rows == 24 && map.configuration.boardCellCount == 384, "Catalog boards must be uniformly 16×24")
        expect(map.configuration.cellCount == playableCounts[map.rawValue], "Unexpected wall pattern/playable count")
        checkTopology(map.configuration)
    }
    let courtyard = SnakeMap.courtyard.configuration
    for y in 0..<24 {
        for x in 0..<16 {
            expect(courtyard.isWall(GridCell(x: x, y: y)) == (x == 0 || x == 15 || y == 0 || y == 23), "Courtyard border must be exactly one cell thick")
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

private func completeGame(map: SnakeConfiguration, seed: UInt64) -> GameResult {
    var engine = SnakeEngine(configuration: map, seed: seed)
    var occupied = Set(engine.snake)
    var sinceFood = 0
    var wrappedX = false
    var wrappedY = false
    var trajectory: UInt64 = 0xCBF29CE484222325
    var middleReplans = 0
    expect(engine.snake.count == 4 && engine.snake.allSatisfy { !map.walls.contains($0) }, "Initial body is invalid")
    if let food = engine.food { expect(!occupied.contains(food) && !map.walls.contains(food), "Initial food on body/wall") }
    while engine.phase == .playing {
        guard let head = engine.snake.first, let tail = engine.snake.last,
              let candidate = engine.nextCell, let oldFood = engine.food else { fatalError("Playing game missing state") }
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
        expect(adjacent(head, candidate, on: map), "Non-adjacent movement or wall crossing, seed \(seed)")
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
        expect(!wrappedX || map.wrapsHorizontally, "Crossed a horizontal wall")
        expect(!wrappedY || map.wrapsVertically, "Crossed a vertical wall")
        if engine.steps <= 128 { trajectory = (trajectory ^ UInt64(candidate.y * map.columns + candidate.x)) &* 0x100000001B3 }
        if growing {
            expect(Set(engine.snake) == occupied && occupied.count == engine.snake.count, "Body duplicate or missing cell")
            expect(engine.foodsEaten == engine.snake.count - 4, "Food counter mismatch")
            checkBodyOrder(engine)
            if engine.cycleReplans > oldReplans {
                expect(engine.cycleReplans == oldReplans + 1, "More than one committed plan per food")
                expect(edgeSetsDiffer(oldCycle, engine.cycle, on: map), "Replan changed array order only")
                checkCycle(engine)
                if oldLength >= map.cellCount / 4 && oldLength < map.cellCount * 3 / 4 { middleReplans += 1 }
            } else { expect(engine.cycle == oldCycle, "Unreported cycle change") }
            if let food = engine.food {
                let oldHeadRank = oldCycle.firstIndex(of: candidate)!
                let oldFoodRank = oldCycle.firstIndex(of: food)!
                let previousDistance = (oldFoodRank - oldHeadRank + map.cellCount) % map.cellCount
                expect(engine.forwardDistance(from: candidate, to: food) <= previousDistance, "Replan worsened food rank")
            }
            sinceFood = 0
        } else {
            expect(engine.cycle == oldCycle && engine.replanAttempts == oldAttempts && engine.cycleReplans == oldReplans, "Cycle changed between foods")
            expect(engine.forwardDistance(from: candidate, to: oldFood) < foodDistance, "Frozen-cycle food rank did not decrease")
        }
        if let food = engine.food { expect(!occupied.contains(food) && !map.walls.contains(food), "Food placed on body/wall, seed \(seed)") }
        expect(engine.steps <= map.cellCount * map.cellCount, "Completion bound exceeded")
    }
    expect(engine.phase == .filled && engine.snake.count == map.cellCount && occupied.count == map.cellCount, "Incomplete board")
    expect(engine.food == nil && occupied.isDisjoint(with: map.walls), "Filled board includes a wall or food")
    let finalSteps = engine.steps
    let finalSnake = engine.snake
    engine.step()
    expect(engine.steps == finalSteps && engine.snake == finalSnake, "Filled game should stop")
    return GameResult(steps: engine.steps, wrappedX: wrappedX, wrappedY: wrappedY, trajectory: trajectory,
                      replans: engine.cycleReplans, middleReplans: middleReplans)
}

private func checkDeterminismAndDiversity() {
    for map in SnakeMap.allCases {
        for seed: UInt64 in [0, 1, 42, UInt64.max] {
            var a = SnakeEngine(configuration: map.configuration, seed: seed)
            var b = SnakeEngine(configuration: map.configuration, seed: seed)
            expect(a.cycle == b.cycle && a.snake == b.snake && a.food == b.food, "Initial seed not deterministic")
            for _ in 0..<2_000 {
                a.step(); b.step()
                expect(a.snake == b.snake && a.food == b.food && a.phase == b.phase && a.cycle == b.cycle, "Game seed not deterministic")
            }
        }
        var foods: Set<GridCell> = []
        var heads: Set<GridCell> = []
        var routes: Set<[GridCell]> = []
        for seed in 0..<1_024 {
            let engine = SnakeEngine(configuration: map.configuration, seed: UInt64(seed))
            if let food = engine.food { foods.insert(food) }
            if let head = engine.snake.first { heads.insert(head) }
            if seed < 128 { routes.insert(Array(engine.cycle.prefix(16))) }
        }
        expect(foods.count > map.configuration.cellCount * 85 / 100 && heads.count > map.configuration.cellCount * 85 / 100 && routes.count > 100,
               "Seed diversity unexpectedly low for \(map.rawValue)")
    }
}

private func checkObstacleFallbacks() {
    let all = Set((0..<4).flatMap { y in (0..<4).map { GridCell(x: $0, y: y) } })
    let island = Set((2..<4).flatMap { y in (2..<4).map { GridCell(x: $0, y: y) } })
    let tiny = SnakeConfiguration(columns: 4, rows: 4, wrapsHorizontally: false, wrapsVertically: false, walls: all.subtracting(island))
    let corner = Set((0..<2).flatMap { y in (0..<2).map { GridCell(x: $0, y: y) } })
    let bent = SnakeConfiguration(columns: 4, rows: 4, wrapsHorizontally: false, wrapsVertically: false, walls: corner)
    let hole = Set((2..<4).flatMap { y in (2..<4).map { GridCell(x: $0, y: y) } })
    for map in [tiny, bent, SnakeConfiguration(columns: 6, rows: 8, walls: hole)] {
        checkTopology(map)
        for seed in 0..<64 { _ = completeGame(map: map, seed: UInt64(seed)) }
    }
}

private func seedSignature() -> String {
    var digest: UInt64 = 0xCBF29CE484222325
    for map in SnakeMap.allCases {
        for seed: UInt64 in [0, 42, UInt64.max] {
            var engine = SnakeEngine(configuration: map.configuration, seed: seed)
            for cell in engine.cycle { digest = (digest ^ UInt64(cell.y * 16 + cell.x)) &* 0x100000001B3 }
            for _ in 0..<2_000 {
                engine.step()
                let head = engine.snake[0]
                let food = engine.food.map { $0.y * 16 + $0.x } ?? 384
                digest = (digest ^ UInt64(head.y * 16 + head.x)) &* 0x100000001B3
                digest = (digest ^ UInt64(food)) &* 0x100000001B3
            }
        }
    }
    return String(digest)
}

private func checkCrossProcessSeeds() {
    func childSignature() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--snake-seed-signature"]
        var environment = ProcessInfo.processInfo.environment
        environment["SWIFT_DETERMINISTIC_HASHING"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        do { try process.run() } catch { fatalError("Could not launch seed subprocess: \(error)") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expect(process.terminationStatus == 0, "Seed subprocess failed")
        return String(decoding: data, as: UTF8.self)
    }
    expect(childSignature() == childSignature(), "Seed result depends on per-process Set/Dictionary hashing")
}

private func benchmark() {
    for map in SnakeMap.allCases {
        var timings: [Double] = []
        for seed: UInt64 in [42, 1_337] {
            let initialStart = Date()
            var engine = SnakeEngine(configuration: map.configuration, seed: seed)
            timings.append(Date().timeIntervalSince(initialStart) * 1_000)
            while engine.phase == .playing {
                if engine.nextCell == engine.food {
                    let attempts = engine.replanAttempts
                    let started = Date()
                    engine.step()
                    if engine.replanAttempts > attempts { timings.append(Date().timeIntervalSince(started) * 1_000) }
                } else { engine.step() }
            }
        }
        timings.sort()
        print(String(format: "%@ search (%d samples): median=%.3fms p95=%.3fms max=%.3fms", map.rawValue, timings.count,
                     timings[timings.count / 2], timings[timings.count * 95 / 100], timings.last!))
    }
}

@main
private enum SnakeEngineChecks {
    static func main() {
        if CommandLine.arguments.contains("--snake-seed-signature") { print(seedSignature()); return }
        if ProcessInfo.processInfo.environment["SNAKE_BENCHMARK_ONLY"] == "1" { benchmark(); return }
        let started = Date()
        checkCycles()
        checkDeterminismAndDiversity()
        checkCrossProcessSeeds()
        checkObstacleFallbacks()
        // All combinations of wall/wrap axes also get complete small-map games,
        // including two-cell dimensions and odd/even orientation changes.
        for (columns, rows) in [(2, 2), (2, 3), (3, 2), (2, 5), (5, 2), (3, 4), (4, 3), (7, 10)] {
            for wrapsX in [false, true] {
                for wrapsY in [false, true] {
                    let map = SnakeConfiguration(columns: columns, rows: rows, wrapsHorizontally: wrapsX, wrapsVertically: wrapsY)
                    for seed in 0..<32 { _ = completeGame(map: map, seed: UInt64(seed)) }
                }
            }
        }
        print("PASS 1,024 boundary/odd-even full games across all four topology combinations")
        let mapSeeds = Int(ProcessInfo.processInfo.environment["SNAKE_MAP_SEEDS"] ?? "256") ?? 256
        expect(mapSeeds > 0, "SNAKE_MAP_SEEDS must be positive")
        for map in SnakeMap.allCases {
            var results: [GameResult] = []
            for index in 0..<mapSeeds {
                let seed = UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
                results.append(completeGame(map: map.configuration, seed: seed))
            }
            let c = map.configuration
            let openX = (0..<c.rows).contains { y in !c.walls.contains(GridCell(x: 0, y: y)) && !c.walls.contains(GridCell(x: c.columns - 1, y: y)) }
            let openY = (0..<c.columns).contains { x in !c.walls.contains(GridCell(x: x, y: 0)) && !c.walls.contains(GridCell(x: x, y: c.rows - 1)) }
            if c.wrapsHorizontally && openX { expect(results.contains(where: \.wrappedX), "Never crossed an open X seam") }
            if c.wrapsVertically && openY { expect(results.contains(where: \.wrappedY), "Never crossed an open Y seam") }
            if mapSeeds >= 32 { expect(Set(results.map(\.trajectory)).count > mapSeeds * 9 / 10, "Routes too similar across seeds") }
            expect(results.allSatisfy { $0.replans > 0 && $0.middleReplans > 0 }, "Missing genuine midgame changes")
            let steps = results.map(\.steps).sorted()
            print("PASS \(map.rawValue): \(mapSeeds) complete seeded games, moves min/median/p90/max \(steps.first!)/\(steps[steps.count / 2])/\(steps[min(steps.count - 1, steps.count * 9 / 10)])/\(steps.last!)")
            print("Minimum genuine/midgame edge replans: \(results.map(\.replans).min()!)/\(results.map(\.middleReplans).min()!)")
        }
        benchmark()
        print(String(format: "PASS six 16×24 obstacle maps, playable-only cycles, safe wall lookup, food bounds, frozen plans, budget and cross-process seeds (%.2fs)", Date().timeIntervalSince(started)))
    }
}
