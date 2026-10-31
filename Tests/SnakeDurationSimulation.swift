import Foundation

private struct SpeedEstimate: Codable {
    let movesPerSecond: Double
    let lowerMinutes: Int
    let typicalMinutes: Int
    let upperMinutes: Int
}

private struct MapSimulation: Codable {
    let id: String
    let title: String
    let columns: Int
    let rows: Int
    let wrapsHorizontally: Bool
    let wrapsVertically: Bool
    let sampleCount: Int
    let failures: Int
    let minimumSteps: Int
    let p10Steps: Int
    let p50Steps: Int
    let p90Steps: Int
    let maximumSteps: Int
    let meanSteps: Double
    let stepsBySeedIndex: [Int]
    let speedEstimates: [SpeedEstimate]
}

private struct SimulationReport: Codable {
    let schemaVersion: Int
    let algorithm: String
    let engineSHA256: String
    let sourceCommitAtSimulation: String
    let engineMatchesRepositoryBaseCommit: Bool
    let compiler: String
    let generatedAtUTC: String
    let generatedAtShanghai: String
    let sampleCountPerMap: Int
    let seedFormula: String
    let quantileMethod: String
    let durationMethod: String
    let checkedInvariants: [String]
    let maps: [MapSimulation]
}

private enum SimulationError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case failed(String)

    var description: String {
        switch self {
        case .invalidArguments(let message), .failed(let message): return message
        }
    }
}

@main
private enum SnakeDurationSimulation {
    private static let speedValues: [Double] = [6, 10, 16]

    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Duration simulation failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var samples = 256
        var writeRoot: URL?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--samples":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                    throw SimulationError.invalidArguments("--samples requires a positive integer")
                }
                samples = value
            case "--write-root":
                index += 1
                guard index < arguments.count else {
                    throw SimulationError.invalidArguments("--write-root requires a directory")
                }
                writeRoot = URL(fileURLWithPath: arguments[index], isDirectory: true)
            default:
                throw SimulationError.invalidArguments("Unknown argument: \(arguments[index])")
            }
            index += 1
        }
        if writeRoot != nil && samples < 256 {
            throw SimulationError.invalidArguments("Writing production estimates requires at least 256 seeds per map")
        }

        let environment = ProcessInfo.processInfo.environment
        let engineHash = environment["SNAKE_ESTIMATE_ENGINE_SHA256"] ?? "unspecified"
        if writeRoot != nil && (engineHash.count != 64 || !engineHash.allSatisfy({ $0.isHexDigit })) {
            throw SimulationError.invalidArguments("Writing production estimates requires the exact engine SHA-256")
        }
        let started = Date()
        var records: [MapSimulation] = []
        for map in SnakeMap.allCases {
            let record = try simulate(map: map, samples: samples)
            records.append(record)
            let summary = "PASS \(map.rawValue): \(samples) filled, moves P10/P50/P90 "
                + "\(record.p10Steps)/\(record.p50Steps)/\(record.p90Steps)\n"
            FileHandle.standardError.write(Data(summary.utf8))
        }
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        let shanghai = DateFormatter()
        shanghai.locale = Locale(identifier: "en_US_POSIX")
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")
        shanghai.dateFormat = "yyyy-MM-dd HH:mm:ss 'Asia/Shanghai'"
        let report = SimulationReport(
            schemaVersion: 1,
            algorithm: "bounded paired-plaquette dynamic Hamiltonian cycle with order-preserving shortcuts",
            engineSHA256: engineHash,
            sourceCommitAtSimulation: environment["SNAKE_ESTIMATE_SOURCE_COMMIT"] ?? "unspecified",
            engineMatchesRepositoryBaseCommit: engineHash == environment["SNAKE_ESTIMATE_BASE_ENGINE_SHA256"],
            compiler: environment["SNAKE_ESTIMATE_COMPILER"] ?? "unspecified",
            generatedAtUTC: iso.string(from: Date()),
            generatedAtShanghai: shanghai.string(from: Date()),
            sampleCountPerMap: samples,
            seedFormula: "UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03; index starts at 0",
            quantileMethod: "nearest-rank: sortedSteps[max(0, ceil(percentile * sampleCount) - 1)]",
            durationMethod: "logicalMoves / actualMovesPerSecond / 60; lower=floor(P10), typical=round(P50), upper=ceil(P90), minimum 1 minute; pauses and scheduling delays excluded",
            checkedInvariants: [
                "every logical move stays inside the selected map",
                "every move is a legal adjacent edge under the selected wall/wrap topology",
                "no engine collision or N-squared completion-budget exhaustion",
                "each game finishes with all cells occupied exactly once and no food remaining"
            ],
            maps: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var json = try encoder.encode(report)
        json.append(0x0A)
        if let writeRoot {
            let jsonURL = writeRoot.appendingPathComponent("Docs/SnakeDurationSimulation.json")
            let swiftURL = writeRoot.appendingPathComponent("iOSLab/SnakeDurationEstimates.swift")
            try json.write(to: jsonURL, options: .atomic)
            try makeSwift(report).write(to: swiftURL, atomically: true, encoding: .utf8)
            let note = "Wrote production estimates and raw simulation report (\(String(format: "%.2f", Date().timeIntervalSince(started)))s).\n"
            FileHandle.standardError.write(Data(note.utf8))
        } else {
            FileHandle.standardOutput.write(json)
        }
    }

    private static func simulate(map: SnakeMap, samples: Int) throws -> MapSimulation {
        let configuration = map.configuration
        var stepsBySeed: [Int] = []
        stepsBySeed.reserveCapacity(samples)
        for index in 0..<samples {
            let seed = UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
            var engine = SnakeEngine(configuration: configuration, seed: seed)
            let budget = configuration.cellCount * configuration.cellCount
            while engine.phase == .playing && engine.steps < budget {
                guard let previous = engine.snake.first else {
                    throw SimulationError.failed("\(map.rawValue) seed \(seed) has no head")
                }
                engine.step()
                guard engine.phase != .collision, let head = engine.snake.first,
                      (0..<configuration.columns).contains(head.x),
                      (0..<configuration.rows).contains(head.y),
                      adjacent(previous, head, configuration: configuration) else {
                    throw SimulationError.failed("\(map.rawValue) seed \(seed) invalid move at \(engine.steps)")
                }
            }
            guard engine.phase == .filled, engine.snake.count == configuration.cellCount,
                  Set(engine.snake).count == configuration.cellCount, engine.food == nil,
                  engine.foodsEaten == configuration.cellCount - 4 else {
                throw SimulationError.failed("\(map.rawValue) seed \(seed) failed to fill within \(budget) moves")
            }
            stepsBySeed.append(engine.steps)
        }
        let sorted = stepsBySeed.sorted()
        let p10 = percentile(sorted, fraction: 0.10)
        let p50 = percentile(sorted, fraction: 0.50)
        let p90 = percentile(sorted, fraction: 0.90)
        return MapSimulation(
            id: map.rawValue, title: map.title,
            columns: configuration.columns, rows: configuration.rows,
            wrapsHorizontally: configuration.wrapsHorizontally,
            wrapsVertically: configuration.wrapsVertically,
            sampleCount: samples, failures: 0,
            minimumSteps: sorted[0], p10Steps: p10, p50Steps: p50, p90Steps: p90,
            maximumSteps: sorted[sorted.count - 1],
            meanSteps: Double(sorted.reduce(0, +)) / Double(sorted.count),
            stepsBySeedIndex: stepsBySeed,
            speedEstimates: speedValues.map { speed in
                SpeedEstimate(movesPerSecond: speed,
                              lowerMinutes: max(1, Int(floor(Double(p10) / speed / 60))),
                              typicalMinutes: max(1, Int((Double(p50) / speed / 60).rounded())),
                              upperMinutes: max(1, Int(ceil(Double(p90) / speed / 60))))
            }
        )
    }

    private static func adjacent(_ a: GridCell, _ b: GridCell, configuration: SnakeConfiguration) -> Bool {
        let dx = abs(a.x - b.x)
        let dy = abs(a.y - b.y)
        if dy == 0 && dx == 1 || dx == 0 && dy == 1 { return true }
        if configuration.wrapsHorizontally && dy == 0 && dx == configuration.columns - 1 { return true }
        return configuration.wrapsVertically && dx == 0 && dy == configuration.rows - 1
    }

    private static func percentile(_ values: [Int], fraction: Double) -> Int {
        values[max(0, Int(ceil(Double(values.count) * fraction)) - 1)]
    }

    private static func makeSwift(_ report: SimulationReport) -> String {
        let cases = report.maps.map {
            "        case .\($0.id): steps = (\($0.p10Steps), \($0.p50Steps), \($0.p90Steps), \($0.sampleCount))"
        }.joined(separator: "\n")
        return """
        import Foundation

        /// Approximate foreground runtime, derived from seeded production-engine simulations.
        /// The displayed interval is the sampled P10–P90 range, rounded outward to minutes.
        struct SnakeDurationEstimate: Equatable, Sendable {
            let sampleCount: Int
            let lowerMinutes: Int
            let typicalMinutes: Int
            let upperMinutes: Int
        }

        /// Generated by Scripts/estimate-snake-duration.sh --write.
        /// Raw steps, deterministic seeds and provenance: Docs/SnakeDurationSimulation.json.
        enum SnakeDurationEstimates {
            static let engineSHA256 = "\(report.engineSHA256)"
            static let sampleCountPerMap = \(report.sampleCountPerMap)

            static func stepQuantiles(for map: SnakeMap) -> (lower: Int, typical: Int, upper: Int, samples: Int) {
                let steps: (lower: Int, typical: Int, upper: Int, samples: Int)
                switch map {
        \(cases)
                }
                return steps
            }

            static func estimate(for map: SnakeMap, movesPerSecond: Double) -> SnakeDurationEstimate {
                precondition(movesPerSecond.isFinite && movesPerSecond > 0)
                let steps = stepQuantiles(for: map)
                return SnakeDurationEstimate(
                    sampleCount: steps.samples,
                    lowerMinutes: max(1, Int(floor(Double(steps.lower) / movesPerSecond / 60))),
                    typicalMinutes: max(1, Int((Double(steps.typical) / movesPerSecond / 60).rounded())),
                    upperMinutes: max(1, Int(ceil(Double(steps.upper) / movesPerSecond / 60)))
                )
            }
        }

        """
    }
}
