import SwiftUI

struct ContentView: View {
    @StateObject private var session = SnakeSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var restartTitleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    if session.stage == .setup {
                        setup
                    } else {
                        game(in: geometry.size)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 510)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .disabled(session.showsRestartConfirmation)
            .accessibilityHidden(session.showsRestartConfirmation)
        }
        .background(LCD.paper.ignoresSafeArea())
        .foregroundStyle(LCD.ink)
        .preferredColorScheme(.light)
        .overlay {
            if session.showsRestartConfirmation { restartConfirmation }
        }
        .onChange(of: session.showsRestartConfirmation) { _, shown in
            restartTitleFocused = shown
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: session.sceneDidBecomeActive()
            case .inactive, .background: session.sceneDidEnterBackground()
            @unknown default: session.sceneDidEnterBackground()
            }
        }
    }

    private var header: some View {
        HStack {
            PixelText(text: "SNAKE", pixel: 3)
                .accessibilityLabel("自动贪吃蛇")
            Spacer()
            if session.stage == .setup {
                PixelLabel(text: "选择后开始", size: 12)
            }
        }
        .frame(height: 36)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            PixelLabel(text: "选择地图", size: 18)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SnakeMap.allCases) { map in mapChoice(map) }
            }

            HStack(alignment: .firstTextBaseline) {
                PixelLabel(text: "选择速度", size: 18)
                Spacer()
                PixelLabel(text: "速度以步 / 秒计", size: 12)
            }
            HStack(spacing: 10) {
                ForEach(SnakeSpeed.allCases) { speed in speedChoice(speed) }
            }

            let estimate = SnakeDurationEstimates.estimate(for: session.selectedMap,
                                                           movesPerSecond: session.selectedSpeed.movesPerSecond)
            PixelLabel(text: "预计 \(estimate.lowerMinutes)-\(estimate.upperMinutes) 分钟，通常约 \(estimate.typicalMinutes) 分钟",
                       size: 14)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)

            Button { session.begin() } label: {
                PixelLabel(text: "开始观看", size: 24)
            }
            .buttonStyle(PixelButtonStyle(emphasized: true))
            .accessibilityLabel("按所选地图和速度开始观看")

            PixelLabel(text: "根据 \(estimate.sampleCount) 局模拟给出常见范围。\n随机食物、暂停与设备调度会影响实际用时。", size: 12)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .opacity(0.70)
        }
    }

    private func mapChoice(_ map: SnakeMap) -> some View {
        let selected = map == session.selectedMap
        let configuration = map.configuration
        return Button { session.selectMap(map) } label: {
            HStack(spacing: 9) {
                PixelMapThumbnail(configuration: configuration, selected: selected)
                    .frame(width: 34, height: 50)
                VStack(alignment: .leading, spacing: 5) {
                    PixelLabel(text: map.title, size: 16).lineLimit(1)
                    PixelLabel(text: "\(configuration.columns) x \(configuration.rows)", size: 12)
                    PixelLabel(text: topologyLabel(configuration), size: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 82)
        }
        .buttonStyle(PixelChoiceStyle(selected: selected))
        .accessibilityLabel("地图，\(map.title)，\(map.subtitle)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func speedChoice(_ speed: SnakeSpeed) -> some View {
        let selected = speed == session.selectedSpeed
        let estimate = SnakeDurationEstimates.estimate(for: session.selectedMap, movesPerSecond: speed.movesPerSecond)
        return Button { session.selectSpeed(speed) } label: {
            VStack(spacing: 9) {
                PixelLabel(text: speed.label, size: 18)
                PixelLabel(text: "\(Int(speed.movesPerSecond)) 步/秒", size: 12)
                PixelLabel(text: "约 \(estimate.lowerMinutes)-\(estimate.upperMinutes) 分", size: 12)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.horizontal, 3)
        }
        .buttonStyle(PixelChoiceStyle(selected: selected))
        .accessibilityLabel("\(speed.label)，每秒 \(Int(speed.movesPerSecond)) 步，模拟预计 \(estimate.lowerMinutes) 至 \(estimate.upperMinutes) 分钟")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func game(in size: CGSize) -> some View {
        let configuration = session.engine.configuration
        let ratio = CGFloat(configuration.columns) / CGFloat(configuration.rows)
        let available = min(size.width - 50, max(256, (size.height - 210) * ratio), 448)
        let width = floor(available / CGFloat(configuration.columns)) * CGFloat(configuration.columns)
        return VStack(spacing: 16) {
            scoreLine
            board(width: width)
                .frame(maxWidth: .infinity)
            if !session.hasEnded {
                HStack(spacing: 14) {
                    Button { session.togglePause() } label: {
                        PixelLabel(text: session.isPaused ? "继续" : "暂停", size: 24)
                    }
                    .accessibilityLabel(session.isPaused ? "继续游戏与计时" : "暂停游戏与计时")
                    Button { session.requestRestart() } label: {
                        PixelLabel(text: "重开", size: 24)
                    }
                    .accessibilityLabel("重开，需确认后返回地图选择")
                }
                .buttonStyle(PixelButtonStyle())
                .padding(.bottom, 3)
            }
        }
    }

    private var scoreLine: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                PixelLabel(text: "SCORE", size: 12)
                PixelText(text: String(format: "%04d", session.engine.foodsEaten), pixel: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已吃 \(session.engine.foodsEaten) 个食物")
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                PixelLabel(text: "TIME", size: 12)
                PixelText(text: timeText, pixel: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本次专注 \(Int(session.elapsedSeconds) / 60) 分 \(Int(session.elapsedSeconds) % 60) 秒")
        }
        .padding(.horizontal, 5)
    }

    private func board(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !session.isRunning || reduceMotion)) { timeline in
            let time = session.animationTime(at: timeline.date)
            let progress = session.hasEnded ? 1 : min(1, max(0, (time - session.movementBeganAtElapsed) / session.moveDuration))
            RetroBoard(engine: session.engine, previousSnake: session.previousSnake,
                       progress: progress, time: time, reduceMotion: reduceMotion)
        }
        .frame(width: width, height: width * CGFloat(session.engine.configuration.rows) / CGFloat(session.engine.configuration.columns))
        .overlay {
            if session.hasEnded {
                endCard.padding(18)
            } else if session.isPaused {
                PixelLabel(text: "已暂停", size: 24)
                    .padding(20)
                    .background(LCD.paper)
                    .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
                    .accessibilityLabel("游戏与专注计时已暂停")
            }
        }
        .padding(5)
        .overlay { PixelBoundary(configuration: session.engine.configuration) }
    }

    private var endCard: some View {
        VStack(spacing: 17) {
            PixelText(text: session.engine.phase == .filled ? "CLEAR" : "OVER", pixel: 3)
            PixelLabel(text: "休息一下", size: 24)
            PixelLabel(text: "本次专注 \(timeText)\n起来走走，看看远处。", size: 12)
                .multilineTextAlignment(.center)
            Button { session.requestRestart() } label: {
                PixelLabel(text: "重开", size: 24)
            }
            .buttonStyle(PixelButtonStyle())
            .frame(maxWidth: 170)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 25)
        .frame(maxWidth: 280)
        .background(LCD.paper)
        .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
        .accessibilityElement(children: .contain)
    }

    private var restartConfirmation: some View {
        ZStack {
            LCD.paper.opacity(0.86).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }
            VStack(spacing: 20) {
                PixelLabel(text: "确认重开？", size: 24)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($restartTitleFocused)
                PixelLabel(text: session.hasEnded
                           ? "返回地图与速度选择。\n本次用时 \(timeText)"
                           : "将结束本局，返回地图与速度选择。\n本次已用 \(timeText)", size: 12)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button { session.cancelRestart() } label: {
                        PixelLabel(text: "取消", size: 18)
                    }
                    .buttonStyle(PixelButtonStyle())
                    Button { session.confirmRestart() } label: {
                        PixelLabel(text: "确认重开", size: 18)
                    }
                    .buttonStyle(PixelButtonStyle(emphasized: true))
                }
            }
            .padding(22)
            .frame(maxWidth: 330)
            .background(LCD.paper)
            .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
            .background { Rectangle().fill(LCD.ink).offset(x: 5, y: 5) }
            .padding(24)
            .accessibilityElement(children: .contain)
        }
    }

    private var timeText: String {
        let seconds = Int(session.elapsedSeconds)
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func topologyLabel(_ configuration: SnakeConfiguration) -> String {
        if configuration.wrapsHorizontally && configuration.wrapsVertically { return "四边互通" }
        if configuration.wrapsHorizontally { return "左右互通" }
        if configuration.wrapsVertically { return "上下互通" }
        return "四面有墙"
    }
}

/// A small original 5×7 bitmap alphabet keeps the HUD independent of font assets.
private struct PixelText: View {
    let text: String
    let pixel: CGFloat

    var body: some View {
        Canvas { context, _ in
            for (column, character) in text.enumerated() {
                guard let rows = Self.glyphs[character] else { continue }
                for (y, row) in rows.enumerated() {
                    for x in 0..<5 where row & (1 << (4 - x)) != 0 {
                        let rect = CGRect(x: CGFloat(column * 6 + x) * pixel, y: CGFloat(y) * pixel,
                                          width: pixel, height: pixel)
                        context.fill(Path(rect), with: .color(LCD.ink))
                    }
                }
            }
        }
        .frame(width: CGFloat(max(0, text.count * 6 - 1)) * pixel, height: pixel * 7)
        .accessibilityLabel(text)
    }

    private static let glyphs: [Character: [UInt8]] = [
        "S": [15, 16, 16, 14, 1, 1, 30], "N": [17, 25, 25, 21, 19, 19, 17],
        "A": [14, 17, 17, 31, 17, 17, 17], "K": [17, 18, 20, 24, 20, 18, 17],
        "E": [31, 16, 16, 30, 16, 16, 31], "P": [30, 17, 17, 30, 16, 16, 16],
        "U": [17, 17, 17, 17, 17, 17, 14], "D": [30, 17, 17, 17, 17, 17, 30],
        "C": [14, 17, 16, 16, 16, 17, 14], "L": [16, 16, 16, 16, 16, 16, 31],
        "R": [30, 17, 17, 30, 20, 18, 17], "O": [14, 17, 17, 17, 17, 17, 14],
        "V": [17, 17, 17, 17, 17, 10, 4],
        "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14],
        "2": [14, 17, 1, 2, 4, 8, 31], "3": [30, 1, 1, 14, 1, 1, 30],
        "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 16, 30, 1, 1, 30],
        "6": [14, 16, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8],
        "8": [14, 17, 17, 14, 17, 17, 14], "9": [14, 17, 17, 15, 1, 1, 14],
        ":": [0, 4, 4, 0, 4, 4, 0]
    ]
}

private struct RetroBoard: View {
    let engine: SnakeEngine
    let previousSnake: [GridCell]
    let progress: Double
    let time: Double
    let reduceMotion: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let frame = SnakeVisualGeometry.frame(
                configuration: engine.configuration, snake: engine.snake, previousSnake: previousSnake,
                food: engine.food, progress: progress, time: time, reduceMotion: reduceMotion
            )
            let pitch = size.width / CGFloat(frame.columns)
            let dotSize = max(1 / displayScale, floor(pitch * displayScale * 0.90) / displayScale)
            let inset = (pitch - dotSize) / 2
            var pixels = Path()
            for y in 0..<frame.rows {
                for x in 0..<frame.columns where frame.dots[y * frame.columns + x] != 0 {
                    let rect = CGRect(
                        x: ((CGFloat(x) * pitch + inset) * displayScale).rounded() / displayScale,
                        y: ((CGFloat(y) * pitch + inset) * displayScale).rounded() / displayScale,
                        width: dotSize, height: dotSize
                    )
                    pixels.addRect(rect)
                }
            }
            context.fill(pixels, with: .color(LCD.ink))
        }
        .background(LCD.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自动贪吃蛇，\(boundaryDescription)")
        .accessibilityValue("蛇身 \(engine.snake.count) 格，共 \(engine.configuration.cellCount) 格")
    }

    private var boundaryDescription: String {
        let configuration = engine.configuration
        if configuration.wrapsHorizontally && configuration.wrapsVertically { return "四边互通棋盘" }
        if configuration.wrapsHorizontally { return "左右互通，上下有墙的棋盘" }
        if configuration.wrapsVertically { return "上下互通，左右有墙的棋盘" }
        return "四面有墙棋盘"
    }
}

#Preview { ContentView() }
