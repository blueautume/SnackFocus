import SwiftUI

struct ContentView: View {
    @StateObject private var session = SnakeSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSettings = false

    var body: some View {
        GeometryReader { geometry in
            let available = min(geometry.size.width - 50, max(256, (geometry.size.height - 220) * 2 / 3), 448)
            let boardWidth = floor(available / 16) * 16
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    scoreLine
                    board(width: boardWidth)
                        .frame(maxWidth: .infinity)
                    if !session.hasEnded { controls }
                    Text("\(session.strategy.label) · \(session.engine.snake.count)/\(session.engine.configuration.cellCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(LCD.ink.opacity(0.65))
                        .accessibilityLabel("\(session.strategy.label)，已填充 \(session.engine.snake.count) 格，共 \(session.engine.configuration.cellCount) 格")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: 510)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(LCD.paper.ignoresSafeArea())
        .foregroundStyle(LCD.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showsSettings) { settings }
        .task { session.start() }
        .onChange(of: session.hasEnded) { _, ended in
            if ended { showsSettings = false }
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
            Button { showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("策略与节奏设置")
        }
        .frame(height: 44)
    }

    private var scoreLine: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SCORE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                PixelText(text: String(format: "%04d", session.engine.foodsEaten), pixel: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已吃 \(session.engine.foodsEaten) 个食物")
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("TIME").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
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
            .frame(width: width, height: width * 1.5)
            .overlay {
                if session.hasEnded {
                    endCard.padding(18)
                } else if session.isPaused {
                    PixelText(text: "PAUSED", pixel: 2)
                        .padding(20)
                        .background(LCD.paper)
                        .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 1) }
                        .accessibilityLabel("游戏与专注计时已暂停")
                }
            }
            .padding(5)
            .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2).allowsHitTesting(false) }
    }

    private var controls: some View {
        HStack {
            Button { session.togglePause() } label: {
                Text(session.isPaused ? "继续" : "暂停")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(session.isPaused ? "继续游戏与计时" : "暂停游戏与计时")
            Button { session.restart() } label: {
                Text("重开")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("重新开始随机的一局")
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.plain)
    }

    private var endCard: some View {
        VStack(spacing: 17) {
            PixelText(text: session.engine.phase == .filled ? "CLEAR" : "OVER", pixel: 3)
            Text("休息一下")
                .font(.system(size: 24, weight: .semibold))
            Text("本次专注 \(timeText)\n起来走走，看看远处。")
                .font(.system(size: 13))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
            Button { session.restart() } label: {
                Text("休息好了，再来一局")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 25)
        .frame(maxWidth: 280)
        .background(LCD.paper)
        .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
        .accessibilityElement(children: .contain)
    }

    private var timeText: String {
        let seconds = Int(session.elapsedSeconds)
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var settings: some View {
        NavigationStack {
            List {
                Section {
                    Picker("自动策略", selection: $session.strategy) {
                        ForEach(SnakeStrategy.allCases) { strategy in
                            Text(strategy.label).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(session.strategy == .dynamicCycle
                         ? "每次进食后尝试调整路线，保留安全闭环，逐步填满棋盘。"
                         : "沿安全环路前进，在安全时走捷径，逐步填满棋盘。")
                        .font(.footnote)
                } header: {
                    Text("自动策略")
                } footer: {
                    Text("切换策略会重新开局。两种策略均适用于当前无障碍地图。")
                }

                Section("节奏") {
                    Picker("运行节奏", selection: $session.speed) {
                        ForEach(SnakeSpeed.allCases) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LabeledContent("地图", value: "无边界 · 16 × 24")
                    Text("四边互通，打开即自动玩。填满后提醒休息，需主动开始下一局。")
                    Text("运行时屏幕常亮；暂停或离开后恢复系统设置。后台不运行、不发送通知，返回继续原局。")
                }
                .font(.footnote)
            }
            .listRowBackground(LCD.ink.opacity(0.04))
            .scrollContentBackground(.hidden)
            .background(LCD.paper)
            .foregroundStyle(LCD.ink)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsSettings = false }.tint(LCD.ink)
                }
            }
        }
        .preferredColorScheme(.light)
        .tint(LCD.ink)
    }
}

private enum LCD {
    static let paper = Color(red: 0.70, green: 0.76, blue: 0.49)
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.10)
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
        .accessibilityLabel("自动贪吃蛇，无边界棋盘")
        .accessibilityValue("蛇身 \(engine.snake.count) 格，共 \(engine.configuration.cellCount) 格")
    }
}

#Preview { ContentView() }
