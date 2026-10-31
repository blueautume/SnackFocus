import CryptoKit
import Foundation

private struct DurationReport: Decodable {
    let schemaVersion: Int
    let engineSHA256: String
    let sampleCountPerMap: Int
    let quantileMethod: String
    let maps: [MapRecord]
}

private struct MapRecord: Decodable {
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
    let speedEstimates: [SpeedRecord]
}

private struct SpeedRecord: Decodable {
    let movesPerSecond: Double
    let lowerMinutes: Int
    let typicalMinutes: Int
    let upperMinutes: Int
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum SnakeDurationEstimateChecks {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Duration estimate check failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(description: message) }
    }

    private static func run() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckFailure(description: "Expected the project root argument")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = try Data(contentsOf: root.appendingPathComponent("iOSLab/SnakeEngine.swift"))
        let sourceHash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        let report = try JSONDecoder().decode(DurationReport.self, from:
            Data(contentsOf: root.appendingPathComponent("Docs/SnakeDurationSimulation.json")))
        try require(report.schemaVersion == 1, "Unsupported report schema")
        try require(report.engineSHA256 == sourceHash && SnakeDurationEstimates.engineSHA256 == sourceHash,
                    "Engine changed; regenerate with Scripts/estimate-snake-duration.sh --write")
        try require(report.sampleCountPerMap >= 256 && report.sampleCountPerMap == SnakeDurationEstimates.sampleCountPerMap,
                    "Sample count must be at least 256 and match production data")
        try require(report.quantileMethod.hasPrefix("nearest-rank:"), "Unexpected percentile convention")
        let mapIDs = SnakeMap.allCases.map(\.rawValue)
        try require(mapIDs.count == 4 && Set(report.maps.map(\.id)) == Set(mapIDs) && report.maps.count == mapIDs.count,
                    "Report does not match the four shipping maps")
        let speeds = SnakeSpeed.allCases.map(\.movesPerSecond).sorted()
        try require(speeds == [6, 10, 16], "The three shipping speeds changed; regenerate and review the estimates")
        for map in SnakeMap.allCases {
            guard let record = report.maps.first(where: { $0.id == map.rawValue }) else {
                throw CheckFailure(description: "Missing map \(map.rawValue)")
            }
            try check(map: map, record: record, sampleCount: report.sampleCountPerMap, speeds: speeds)
        }
        print("Duration estimates passed: exact engine hash, four map topologies, \(report.sampleCountPerMap) samples/map, raw quantiles and all three production speeds.")
    }

    private static func check(map: SnakeMap, record: MapRecord, sampleCount: Int, speeds: [Double]) throws {
        let configuration = map.configuration
        let context = map.rawValue
        try require(record.title == map.title && record.columns == configuration.columns && record.rows == configuration.rows
                    && record.wrapsHorizontally == configuration.wrapsHorizontally
                    && record.wrapsVertically == configuration.wrapsVertically,
                    "\(context): map geometry or topology differs from the simulation")
        try require(record.sampleCount == sampleCount && record.stepsBySeedIndex.count == sampleCount && record.failures == 0,
                    "\(context): incomplete or failed simulation samples")
        let steps = record.stepsBySeedIndex.sorted()
        let budget = configuration.cellCount * configuration.cellCount
        try require(steps.allSatisfy { $0 >= configuration.cellCount - 4 && $0 <= budget },
                    "\(context): raw game length outside the completion budget")
        let p10 = percentile(steps, fraction: 0.10)
        let p50 = percentile(steps, fraction: 0.50)
        let p90 = percentile(steps, fraction: 0.90)
        try require(record.minimumSteps == steps.first && record.maximumSteps == steps.last,
                    "\(context): raw minimum or maximum is stale")
        try require(record.p10Steps == p10 && record.p50Steps == p50 && record.p90Steps == p90 && p10 <= p50 && p50 <= p90,
                    "\(context): report percentiles do not match the raw samples")
        let actualMean = Double(steps.reduce(0, +)) / Double(sampleCount)
        try require(abs(record.meanSteps - actualMean) < 0.000_001, "\(context): report mean differs from raw samples")
        let production = SnakeDurationEstimates.stepQuantiles(for: map)
        try require(production.lower == p10 && production.typical == p50 && production.upper == p90 && production.samples == sampleCount,
                    "\(context): production constants differ from simulated percentiles")
        try require(record.speedEstimates.map(\.movesPerSecond).sorted() == speeds,
                    "\(context): simulation must describe all three actual speeds")
        var previous: SnakeDurationEstimate?
        for speed in speeds {
            guard let stored = record.speedEstimates.first(where: { $0.movesPerSecond == speed }) else {
                throw CheckFailure(description: "\(context): missing speed \(speed)")
            }
            let expected = SnakeDurationEstimate(
                sampleCount: sampleCount,
                lowerMinutes: max(1, Int(floor(Double(p10) / speed / 60))),
                typicalMinutes: max(1, Int((Double(p50) / speed / 60).rounded())),
                upperMinutes: max(1, Int(ceil(Double(p90) / speed / 60)))
            )
            let actual = SnakeDurationEstimates.estimate(for: map, movesPerSecond: speed)
            try require(actual == expected && stored.lowerMinutes == expected.lowerMinutes
                        && stored.typicalMinutes == expected.typicalMinutes && stored.upperMinutes == expected.upperMinutes,
                        "\(context): duration at \(speed) moves/s was not derived from actual speed")
            try require(actual.lowerMinutes <= actual.typicalMinutes && actual.typicalMinutes <= actual.upperMinutes,
                        "\(context): duration interval is not ordered")
            if let previous {
                try require(actual.lowerMinutes < previous.lowerMinutes && actual.typicalMinutes < previous.typicalMinutes
                            && actual.upperMinutes < previous.upperMinutes,
                            "\(context): faster speed must yield a shorter duration")
            }
            previous = actual
        }
    }

    private static func percentile(_ values: [Int], fraction: Double) -> Int {
        values[max(0, Int(ceil(Double(values.count) * fraction)) - 1)]
    }
}
