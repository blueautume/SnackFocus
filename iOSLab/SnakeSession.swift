import Combine
import Foundation
import UIKit

enum SnakeSpeed: String, CaseIterable, Identifiable, Sendable {
    case calm
    case steady
    case flow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calm: return "慢速"
        case .steady: return "中速"
        case .flow: return "快速"
        }
    }

    var movesPerSecond: Double {
        switch self {
        case .calm: return 6
        case .steady: return 10
        case .flow: return 16
        }
    }

    var interval: TimeInterval { 1 / movesPerSecond }
}

enum SnakeSessionStage: Equatable, Sendable {
    case setup
    case playing
    case finished
}

/// The game clock counts foreground play only. Rendering can interpolate each
/// completed logical move independently of this fixed-step scheduler.
@MainActor
final class SnakeSession: ObservableObject {
    @Published private(set) var stage: SnakeSessionStage = .setup
    @Published private(set) var selectedMap: SnakeMap = .meadow
    @Published private(set) var selectedSpeed: SnakeSpeed = .steady
    @Published private(set) var showsRestartConfirmation = false
    @Published private(set) var engine: SnakeEngine
    @Published private(set) var previousSnake: [GridCell]
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published private(set) var isInBackground = false
    @Published private(set) var movementBeganAt = Date()
    @Published private(set) var movementBeganAtElapsed: TimeInterval = 0
    @Published private(set) var moveDuration: Double = SnakeSpeed.steady.interval
    var speed: SnakeSpeed { selectedSpeed }
    var isRunning: Bool { stage == .playing && !isPaused && !isInBackground && !showsRestartConfirmation }
    var hasEnded: Bool { stage == .finished }
    var occupancy: Double { Double(engine.snake.count) / Double(engine.configuration.cellCount) }

    private let clock = ContinuousClock()
    private var activeStartedAt: ContinuousClock.Instant?
    private var elapsedBeforeActiveSegment: TimeInterval = 0
    private var loop: Task<Void, Never>?
    private var loopGeneration: UInt64 = 0
    private var restartWasRunning = false
    private let screenAwakeToken = UUID()
    private var holdsScreenAwake = false

    init() {
        var initialMap = SnakeMap.meadow
        var initialSpeed = SnakeSpeed.steady
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let argument = arguments.first(where: { $0.hasPrefix("--snake-map=") }),
           let map = SnakeMap(rawValue: String(argument.dropFirst("--snake-map=".count))) {
            initialMap = map
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--snake-speed=") }),
           let speed = SnakeSpeed(rawValue: String(argument.dropFirst("--snake-speed=".count))) {
            initialSpeed = speed
        }
        #endif
        selectedMap = initialMap
        selectedSpeed = initialSpeed
        var initial = SnakeEngine(configuration: initialMap.configuration)
        #if DEBUG
        // Only explicit Debug previews bypass setup. Release builds ignore all
        // launch arguments and always wait for the user's Begin action.
        let stopsBeforeLastBite = arguments.contains("--snake-preview-last-bite")
        let nearFull = arguments.contains("--snake-preview-near-full")
        let midpoint = arguments.contains("--snake-preview-midpoint")
        let shape = arguments.contains("--snake-preview-shape")
        let preview = !arguments.contains("--snake-preview-setup")
            && (arguments.contains("--snake-preview-filled") || nearFull || stopsBeforeLastBite || midpoint || shape)
        if preview {
            initial = SnakeEngine(configuration: initialMap.configuration, seed: 42)
            let fillCompletely = arguments.contains("--snake-preview-filled")
            let target = fillCompletely ? initial.configuration.cellCount
                : (stopsBeforeLastBite ? initial.configuration.cellCount - 1
                   : (shape ? min(64, initial.configuration.cellCount - 1)
                      : Int(ceil(Double(initial.configuration.cellCount) * (nearFull ? 0.95 : 0.5)))))
            let limit = initial.configuration.cellCount * initial.configuration.cellCount
                + initial.configuration.cellCount
            while initial.phase == .playing && initial.steps < limit
                    && (initial.snake.count < target || (stopsBeforeLastBite && initial.nextCell != initial.food)) {
                initial.step()
            }
        }
        #endif
        engine = initial
        previousSnake = initial.snake
        moveDuration = initialSpeed.interval
        #if DEBUG
        if preview {
            stage = initial.phase == .playing ? .playing : .finished
            isPaused = stage == .playing && arguments.contains("--snake-preview-static")
            startRunning()
        }
        #endif
    }

    deinit {
        loop?.cancel()
        if holdsScreenAwake {
            let token = screenAwakeToken
            Task { @MainActor in SnakeScreenAwake.release(token) }
        }
    }

    func selectMap(_ map: SnakeMap) {
        guard stage == .setup, map != selectedMap else { return }
        selectedMap = map
        prepareGame()
    }

    func selectSpeed(_ speed: SnakeSpeed) {
        guard stage == .setup else { return }
        selectedSpeed = speed
        moveDuration = speed.interval
    }

    func begin() {
        guard stage == .setup, !showsRestartConfirmation else { return }
        prepareGame()
        stage = .playing
        startRunning()
    }

    private func startRunning() {
        guard isRunning else {
            synchronizeScreenAwake()
            return
        }
        guard loop == nil else { return }
        activeStartedAt = clock.now
        synchronizeScreenAwake()
        scheduleLoop()
    }

    func togglePause() {
        guard stage == .playing, !showsRestartConfirmation else { return }
        if isPaused {
            isPaused = false
            startRunning()
        } else {
            isPaused = true
            freezeElapsedTime()
            cancelLoop()
            synchronizeScreenAwake()
        }
    }

    func requestRestart() {
        guard stage != .setup, !showsRestartConfirmation else { return }
        restartWasRunning = isRunning
        freezeElapsedTime()
        cancelLoop()
        if stage == .playing { isPaused = true }
        showsRestartConfirmation = true
        synchronizeScreenAwake()
    }

    func cancelRestart() {
        guard showsRestartConfirmation else { return }
        showsRestartConfirmation = false
        let shouldResume = restartWasRunning
        restartWasRunning = false
        if stage == .playing, shouldResume {
            isPaused = false
            startRunning()
        } else {
            synchronizeScreenAwake()
        }
    }

    func confirmRestart() {
        guard showsRestartConfirmation else { return }
        freezeElapsedTime()
        cancelLoop()
        showsRestartConfirmation = false
        restartWasRunning = false
        stage = .setup
        prepareGame()
        synchronizeScreenAwake()
    }

    private func prepareGame() {
        cancelLoop()
        activeStartedAt = nil
        elapsedBeforeActiveSegment = 0
        elapsedSeconds = 0
        engine = SnakeEngine(configuration: selectedMap.configuration)
        previousSnake = engine.snake
        movementBeganAt = Date()
        movementBeganAtElapsed = 0
        moveDuration = speed.interval
        isPaused = false
    }

    func sceneDidBecomeActive() {
        guard isInBackground else { return }
        isInBackground = false
        // Never interpolate across an interruption or replay background ticks.
        previousSnake = engine.snake
        movementBeganAt = Date()
        movementBeganAtElapsed = elapsedSeconds
        startRunning()
    }

    func sceneDidEnterBackground() {
        guard !isInBackground else { return }
        isInBackground = true
        freezeElapsedTime()
        cancelLoop()
        synchronizeScreenAwake()
    }

    /// A presentation-only clock: sampling at display refresh rate does not
    /// publish HUD updates. Ignore wall-clock dates so phase remains monotonic
    /// through system time adjustments, pauses and background interruptions.
    func animationTime(at _: Date) -> TimeInterval {
        isRunning ? currentElapsedTime() : elapsedSeconds
    }

    private func scheduleLoop() {
        cancelLoop()
        guard isRunning else { return }
        let generation = loopGeneration
        let interval = Duration.seconds(speed.interval)
        let clock = clock
        loop = Task { [weak self] in
            var nextMove = clock.now.advanced(by: interval)
            while !Task.isCancelled {
                do { try await clock.sleep(until: nextMove) } catch { return }
                guard !Task.isCancelled, let self,
                      self.loopGeneration == generation, self.isRunning else { return }
                self.advanceOneMove()
                guard self.isRunning else { return }
                nextMove = nextMove.advanced(by: interval)
                // Drop missed simulation ticks rather than bursting through
                // moves after a slow frame, foregrounding, or a debugger stop.
                if nextMove <= clock.now { nextMove = clock.now.advanced(by: interval) }
            }
        }
    }

    private func advanceOneMove() {
        updateElapsedTime()
        previousSnake = engine.snake
        movementBeganAt = Date()
        movementBeganAtElapsed = elapsedSeconds
        moveDuration = speed.interval
        engine.step()
        guard engine.phase != .playing else { return }
        stage = .finished
        freezeElapsedTime()
        cancelLoop()
        synchronizeScreenAwake()
        if !isInBackground {
            UINotificationFeedbackGenerator().notificationOccurred(engine.phase == .filled ? .success : .warning)
        }
    }

    private func cancelLoop() {
        loopGeneration &+= 1
        loop?.cancel()
        loop = nil
    }

    private func currentElapsedTime() -> TimeInterval {
        guard let activeStartedAt else { return elapsedSeconds }
        let duration = activeStartedAt.duration(to: clock.now).components
        return elapsedBeforeActiveSegment + Double(duration.seconds)
            + Double(duration.attoseconds) / 1_000_000_000_000_000_000
    }

    private func updateElapsedTime() {
        elapsedSeconds = currentElapsedTime()
    }

    private func freezeElapsedTime() {
        updateElapsedTime()
        elapsedBeforeActiveSegment = elapsedSeconds
        activeStartedAt = nil
    }

    private func synchronizeScreenAwake() {
        if isRunning && !holdsScreenAwake {
            SnakeScreenAwake.acquire(screenAwakeToken)
            holdsScreenAwake = true
        } else if !isRunning && holdsScreenAwake {
            SnakeScreenAwake.release(screenAwakeToken)
            holdsScreenAwake = false
        }
    }
}

/// A short-lived lease also handles multiple SwiftUI previews safely, restoring
/// the pre-existing idle-timer setting after the last active session releases it.
@MainActor
private enum SnakeScreenAwake {
    private static var owners: Set<UUID> = []
    private static var previousSetting = false

    static func acquire(_ token: UUID) {
        if owners.isEmpty { previousSetting = UIApplication.shared.isIdleTimerDisabled }
        owners.insert(token)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release(_ token: UUID) {
        guard owners.remove(token) != nil, owners.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = previousSetting
    }
}
