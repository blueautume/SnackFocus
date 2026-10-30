import Combine
import Foundation
import UIKit

enum SnakeSpeed: String, CaseIterable, Identifiable {
    case calm
    case steady
    case flow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calm: return "舒缓"
        case .steady: return "平稳"
        case .flow: return "流动"
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

/// The game clock counts foreground play only. Rendering can interpolate each
/// completed logical move independently of this fixed-step scheduler.
@MainActor
final class SnakeSession: ObservableObject {
    @Published private(set) var engine: SnakeEngine
    @Published private(set) var previousSnake: [GridCell]
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published private(set) var isInBackground = false
    @Published private(set) var movementBeganAt = Date()
    @Published private(set) var moveDuration: Double = SnakeSpeed.steady.interval
    @Published var speed: SnakeSpeed = .steady {
        didSet {
            guard speed != oldValue, isRunning else { return }
            scheduleLoop()
        }
    }

    var isRunning: Bool { hasStarted && !isPaused && !isInBackground && !hasEnded }
    var hasEnded: Bool { engine.phase != .playing }
    var occupancy: Double { Double(engine.snake.count) / Double(engine.configuration.cellCount) }

    private let clock = ContinuousClock()
    private var activeStartedAt: ContinuousClock.Instant?
    private var elapsedBeforeActiveSegment: TimeInterval = 0
    private var loop: Task<Void, Never>?
    private var loopGeneration: UInt64 = 0
    private var hasStarted = false
    private let screenAwakeToken = UUID()
    private var holdsScreenAwake = false

    init() {
        var initial = SnakeEngine()
        #if DEBUG
        // Launch arguments are only a simulator inspection aid. A regular
        // launch, including every Release build, always starts a fresh game.
        let arguments = ProcessInfo.processInfo.arguments
        let stopsBeforeLastBite = arguments.contains("--snake-preview-last-bite")
        if arguments.contains("--snake-preview-filled") || arguments.contains("--snake-preview-near-full") || stopsBeforeLastBite {
            initial = SnakeEngine(seed: 42)
            let fillCompletely = arguments.contains("--snake-preview-filled")
            let target = fillCompletely ? initial.configuration.cellCount
                : (stopsBeforeLastBite ? initial.configuration.cellCount - 1
                   : Int(ceil(Double(initial.configuration.cellCount) * 0.95)))
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
    }

    deinit {
        loop?.cancel()
        if holdsScreenAwake {
            let token = screenAwakeToken
            Task { @MainActor in SnakeScreenAwake.release(token) }
        }
    }

    func start() {
        hasStarted = true
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
        guard !hasEnded else { return }
        if isPaused {
            isPaused = false
            start()
        } else {
            hasStarted = true
            isPaused = true
            freezeElapsedTime()
            cancelLoop()
            synchronizeScreenAwake()
        }
    }

    func restart() {
        cancelLoop()
        activeStartedAt = nil
        elapsedBeforeActiveSegment = 0
        elapsedSeconds = 0
        engine = SnakeEngine()
        previousSnake = engine.snake
        movementBeganAt = Date()
        moveDuration = speed.interval
        isPaused = false
        start()
    }

    func sceneDidBecomeActive() {
        guard isInBackground else { return }
        isInBackground = false
        // Never interpolate across an interruption or replay background ticks.
        previousSnake = engine.snake
        movementBeganAt = Date()
        if hasStarted && !isPaused { start() }
    }

    func sceneDidEnterBackground() {
        guard !isInBackground else { return }
        isInBackground = true
        freezeElapsedTime()
        cancelLoop()
        synchronizeScreenAwake()
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
        moveDuration = speed.interval
        engine.step()
        guard hasEnded else { return }
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

    private func updateElapsedTime() {
        guard let activeStartedAt else { return }
        let duration = activeStartedAt.duration(to: clock.now).components
        elapsedSeconds = elapsedBeforeActiveSegment + Double(duration.seconds)
            + Double(duration.attoseconds) / 1_000_000_000_000_000_000
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
