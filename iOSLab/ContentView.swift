import SwiftUI

struct ContentView: View {
    @StateObject private var session = SnakeSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsGuide = false

    var body: some View {
        GeometryReader { geometry in
            let boardWidth = min(geometry.size.width - 40, max(270, (geometry.size.height - 256) * 2 / 3), 540)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    statistics
                    board
                        .frame(width: boardWidth, height: boardWidth * 1.5)
                        .frame(maxWidth: .infinity)
                    controls
                    Text(session.hasEnded ? "给自己一点空白，也是一种前进。" : "它来玩，你去专注。一局结束，休息一下。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SnakePalette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(SnakePalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsGuide) { guide }
        .task { session.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: session.sceneDidBecomeActive()
            case .background, .inactive: session.sceneDidEnterBackground()
            @unknown default: session.sceneDidEnterBackground()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("蛇行")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(SnakePalette.text)
                Text("01 / 无边界")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SnakePalette.secondary)
            }
            Spacer()
            Button { showsGuide = true } label: {
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SnakePalette.secondary)
                    .frame(width: 44, height: 44)
                    .background(SnakePalette.panel, in: Circle())
            }
            .accessibilityLabel("玩法与专注说明")
        }
    }

    private var statistics: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本次专注")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SnakePalette.secondary)
                Text(timeText)
                    .font(.system(size: 28, weight: .light, design: .monospaced))
                    .foregroundStyle(SnakePalette.text)
                    .monospacedDigit()
                    .accessibilityLabel("本次专注 \(Int(session.elapsedSeconds) / 60) 分 \(Int(session.elapsedSeconds) % 60) 秒")
            }
            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(SnakePalette.line, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: session.occupancy)
                        .stroke(SnakePalette.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 29, height: 29)
                .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(session.occupancy * 100))%")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(SnakePalette.mint)
                        .monospacedDigit()
                    Text("\(session.engine.snake.count) / \(session.engine.configuration.cellCount) 格")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SnakePalette.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("棋盘填充 \(Int(session.occupancy * 100))%，蛇身 \(session.engine.snake.count) 格")
        }
    }

    private var board: some View {
        SnakeBoard(
            engine: session.engine,
            previousSnake: session.previousSnake,
            movementBeganAt: session.movementBeganAt,
            moveDuration: session.moveDuration,
            isRunning: session.isRunning,
            reduceMotion: reduceMotion
        )
        .background(SnakePalette.board)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SnakePalette.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay {
            if session.hasEnded {
                breakCard.padding(18)
            } else if session.isPaused {
                VStack(spacing: 12) {
                    Image(systemName: "pause.fill").font(.title2)
                    Text("暂停片刻").font(.headline)
                }
                .foregroundStyle(SnakePalette.text)
                .padding(28)
                .background(SnakePalette.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
                .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isRunning ? SnakePalette.mint : SnakePalette.amber)
                        .frame(width: 5, height: 5)
                    Text(session.hasEnded ? "现在，轮到你休息" : (session.isPaused ? "专注计时已暂停" : "自动驾驶中"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SnakePalette.text)
                }
                if !session.hasEnded {
                    Menu {
                        Picker("运行节奏", selection: $session.speed) {
                            ForEach(SnakeSpeed.allCases) { speed in
                                Text(speed.label).tag(speed)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(session.speed.label)节奏")
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(SnakePalette.secondary)
                        .padding(.vertical, 5)
                    }
                    .accessibilityLabel("运行节奏，当前\(session.speed.label)")
                }
            }
            Spacer(minLength: 0)
            if !session.hasEnded {
                Button { session.togglePause() } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SnakePalette.background)
                        .frame(width: 50, height: 50)
                        .background(SnakePalette.mint, in: Circle())
                }
                .accessibilityLabel(session.isPaused ? "继续专注" : "暂停游戏与计时")
                Button { session.restart() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SnakePalette.text)
                        .frame(width: 50, height: 50)
                        .background(SnakePalette.panel, in: Circle())
                }
                .accessibilityLabel("重新开始随机的一局")
            } else {
                Image(systemName: "leaf")
                    .font(.title2)
                    .foregroundStyle(SnakePalette.mint)
                    .padding(.trailing, 8)
            }
        }
        .frame(minHeight: 50)
    }

    private var breakCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 43, weight: .ultraLight))
                .foregroundStyle(SnakePalette.mint)
            VStack(spacing: 10) {
                Text(session.engine.phase == .filled ? "这一局，圆满了。" : "这一局，结束了。")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundStyle(SnakePalette.text)
                Text("已陪你专注 \(timeText)\n抬头看看远处，起来走走吧。")
                    .font(.system(size: 13))
                    .foregroundStyle(SnakePalette.secondary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
            }
            Button { session.restart() } label: {
                Text("休息好了，再来一局")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SnakePalette.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(SnakePalette.mint, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
        .frame(maxWidth: 310)
        .background(SnakePalette.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(SnakePalette.line) }
        .accessibilityElement(children: .contain)
    }

    private var timeText: String {
        let seconds = Int(session.elapsedSeconds)
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var guide: some View {
        NavigationStack {
            List {
                Section("它来玩，你去专注") {
                    Text("打开即自动开始。把手机放在一旁，处理眼前的工作；偶尔看一眼它慢慢生长。")
                    Text("填满棋盘或发生碰撞时，本局结束并提醒你休息。不会自动开启下一局。每局时长随随机食物和运行节奏变化，不是固定时长的倒计时。")
                }
                Section("01 / 无边界") {
                    Text("16 × 24 格，四边互通。从右侧离开会从左侧回来，上下同理。食物只出现在空格，每局的食物与路线都重新随机。")
                    Text("机器人会沿安全路线前进，在有余地时走捷径，逐步把棋盘填满。无需操作方向，也无需联网或下载模型。")
                }
                Section("按自己的节奏") {
                    Text("舒缓、平稳、流动三种节奏可随时切换。暂停会同时暂停专注计时；切到后台也会暂停，返回时继续，不追赶后台错过的步数。")
                    Text("运行时屏幕保持常亮，暂停或离开后恢复系统行为。休息提醒只在应用内出现，后台不发送通知。关闭应用后，下次会开始新的一局。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SnakePalette.background)
            .navigationTitle("关于蛇行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { showsGuide = false }.tint(SnakePalette.mint)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private enum SnakePalette {
    static let background = Color(red: 0.045, green: 0.078, blue: 0.065)
    static let board = Color(red: 0.070, green: 0.117, blue: 0.092)
    static let panel = Color(red: 0.102, green: 0.160, blue: 0.126)
    static let line = Color(red: 0.170, green: 0.245, blue: 0.190)
    static let text = Color(red: 0.898, green: 0.929, blue: 0.859)
    static let secondary = Color(red: 0.515, green: 0.625, blue: 0.550)
    static let mint = Color(red: 0.729, green: 0.890, blue: 0.580)
    static let amber = Color(red: 0.957, green: 0.655, blue: 0.337)
}

private struct SnakeBoard: View {
    let engine: SnakeEngine
    let previousSnake: [GridCell]
    let movementBeganAt: Date
    let moveDuration: Double
    let isRunning: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isRunning || reduceMotion)) { timeline in
            Canvas { context, size in
                let unit = size.width / CGFloat(engine.configuration.columns)
                let fraction = reduceMotion || !isRunning ? 1 : min(1, max(0, timeline.date.timeIntervalSince(movementBeganAt) / moveDuration))
                drawGrid(context: context, size: size, unit: unit)
                if let food = engine.food {
                    let point = CGPoint(x: (CGFloat(food.x) + 0.5) * unit, y: (CGFloat(food.y) + 0.5) * unit)
                    let pulse = reduceMotion ? 1 : 0.85 + 0.15 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - unit * 0.60, y: point.y - unit * 0.60, width: unit * 1.2, height: unit * 1.2)), with: .color(SnakePalette.amber.opacity(0.10 * pulse)))
                    context.fill(Path(roundedRect: CGRect(x: point.x - unit * 0.26, y: point.y - unit * 0.26, width: unit * 0.52, height: unit * 0.52), cornerRadius: unit * 0.18), with: .color(SnakePalette.amber))
                    var leaf = Path()
                    leaf.move(to: CGPoint(x: point.x, y: point.y - unit * 0.28))
                    leaf.addLine(to: CGPoint(x: point.x + unit * 0.12, y: point.y - unit * 0.41))
                    context.stroke(leaf, with: .color(SnakePalette.mint), style: StrokeStyle(lineWidth: max(1.5, unit * 0.07), lineCap: .round))
                }

                let points = engine.snake.enumerated().map { index, cell in
                    interpolate(from: previousSnake.indices.contains(index) ? previousSnake[index] : (previousSnake.last ?? cell), to: cell, fraction: fraction, unit: unit, size: size)
                }
                for index in points.indices.reversed() {
                    let proportion = 1 - Double(index) / Double(max(1, points.count))
                    let color = Color(red: 0.29 + proportion * 0.44, green: 0.48 + proportion * 0.41, blue: 0.31 + proportion * 0.27)
                    if index + 1 < points.count {
                        drawSegment(context: context, from: points[index], to: points[index + 1], color: color, unit: unit, size: size)
                    }
                    drawDisc(context: context, at: points[index], radius: unit * 0.37, color: color, size: size)
                }
                if let head = points.first { drawEyes(context: context, head: head, unit: unit, size: size) }
                drawPortals(context: context, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自动贪吃蛇，无边界棋盘")
        .accessibilityValue("蛇身 \(engine.snake.count) 格，共 \(engine.configuration.cellCount) 格")
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, unit: CGFloat) {
        var grid = Path()
        for column in 1..<engine.configuration.columns {
            grid.move(to: CGPoint(x: CGFloat(column) * unit, y: 0))
            grid.addLine(to: CGPoint(x: CGFloat(column) * unit, y: size.height))
        }
        for row in 1..<engine.configuration.rows {
            grid.move(to: CGPoint(x: 0, y: CGFloat(row) * unit))
            grid.addLine(to: CGPoint(x: size.width, y: CGFloat(row) * unit))
        }
        context.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
    }

    private func interpolate(from: GridCell, to: GridCell, fraction: Double, unit: CGFloat, size: CGSize) -> CGPoint {
        let dx = wrappedDelta(CGFloat(to.x - from.x), period: CGFloat(engine.configuration.columns))
        let dy = wrappedDelta(CGFloat(to.y - from.y), period: CGFloat(engine.configuration.rows))
        return CGPoint(
            x: normalized((CGFloat(from.x) + 0.5 + dx * fraction) * unit, period: size.width),
            y: normalized((CGFloat(from.y) + 0.5 + dy * fraction) * unit, period: size.height)
        )
    }

    private func drawSegment(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, unit: CGFloat, size: CGSize) {
        let end = CGPoint(x: from.x + wrappedDelta(to.x - from.x, period: size.width), y: from.y + wrappedDelta(to.y - from.y, period: size.height))
        let bounds = CGRect(x: min(from.x, end.x) - unit / 2, y: min(from.y, end.y) - unit / 2,
                            width: abs(end.x - from.x) + unit, height: abs(end.y - from.y) + unit)
        for offset in visibleOffsets(bounds: bounds, size: size) {
            var line = Path()
            line.move(to: CGPoint(x: from.x + offset.width, y: from.y + offset.height))
            line.addLine(to: CGPoint(x: end.x + offset.width, y: end.y + offset.height))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: unit * 0.74, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawDisc(context: GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, size: CGSize) {
        let bounds = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        for offset in visibleOffsets(bounds: bounds, size: size) {
            context.fill(Path(ellipseIn: bounds.offsetBy(dx: offset.width, dy: offset.height)), with: .color(color))
        }
    }

    private func drawEyes(context: GraphicsContext, head: CGPoint, unit: CGFloat, size: CGSize) {
        guard let current = engine.snake.first else { return }
        let previous = previousSnake.first ?? current
        var dx = wrappedDelta(CGFloat(current.x - previous.x), period: CGFloat(engine.configuration.columns))
        var dy = wrappedDelta(CGFloat(current.y - previous.y), period: CGFloat(engine.configuration.rows))
        if dx == 0 && dy == 0, engine.snake.count > 1 {
            dx = wrappedDelta(CGFloat(current.x - engine.snake[1].x), period: CGFloat(engine.configuration.columns))
            dy = wrappedDelta(CGFloat(current.y - engine.snake[1].y), period: CGFloat(engine.configuration.rows))
        }
        for side: CGFloat in [-1, 1] {
            let eye = CGPoint(x: head.x + (dx * 0.12 - dy * 0.16 * side) * unit,
                              y: head.y + (dy * 0.12 + dx * 0.16 * side) * unit)
            drawDisc(context: context, at: eye, radius: unit * 0.065, color: SnakePalette.background, size: size)
        }
    }

    private func drawPortals(context: GraphicsContext, size: CGSize) {
        for rect in [
            CGRect(x: size.width / 2 - 12, y: 0, width: 24, height: 2),
            CGRect(x: size.width / 2 - 12, y: size.height - 2, width: 24, height: 2),
            CGRect(x: 0, y: size.height / 2 - 12, width: 2, height: 24),
            CGRect(x: size.width - 2, y: size.height / 2 - 12, width: 2, height: 24)
        ] {
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(SnakePalette.mint.opacity(0.35)))
        }
    }

    private func visibleOffsets(bounds: CGRect, size: CGSize) -> [CGSize] {
        var offsets = [CGSize.zero]
        if bounds.minX < 0 { offsets += offsets.map { CGSize(width: $0.width + size.width, height: $0.height) } }
        if bounds.maxX > size.width { offsets += offsets.map { CGSize(width: $0.width - size.width, height: $0.height) } }
        if bounds.minY < 0 { offsets += offsets.map { CGSize(width: $0.width, height: $0.height + size.height) } }
        if bounds.maxY > size.height { offsets += offsets.map { CGSize(width: $0.width, height: $0.height - size.height) } }
        return offsets
    }

    private func wrappedDelta(_ value: CGFloat, period: CGFloat) -> CGFloat {
        if value > period / 2 { return value - period }
        if value < -period / 2 { return value + period }
        return value
    }

    private func normalized(_ value: CGFloat, period: CGFloat) -> CGFloat {
        (value.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
    }
}

#Preview { ContentView() }
