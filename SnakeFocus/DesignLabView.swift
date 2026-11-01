import SwiftUI

/// A presentation-only gallery. Theme and material changes preserve the live
/// production session; only the existing game controls change its state.
/// Debug screenshot flags: --lab-theme=atelier --lab-form=clay.
@MainActor
struct DesignLabView: View {
    @StateObject private var session = SnakeSession()
    @AppStorage("snake.lab.theme") private var themeRaw = LabTheme.atelier.rawValue
    @AppStorage("snake.lab.form") private var formRaw = LabSnakeForm.clay.rawValue
    @AppStorage("snake.lab.favorites") private var savedCombinations = ""
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: LabSheet?
    @State private var schemeSection = 0
    @State private var showsRestartAlert = false
    @State private var restartsAfterSheetDismiss = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let value = arguments.first(where: { $0.hasPrefix("--lab-theme=") })?.dropFirst("--lab-theme=".count),
           let theme = LabTheme(rawValue: String(value)) {
            UserDefaults.standard.set(theme.rawValue, forKey: "snake.lab.theme")
        }
        if let value = arguments.first(where: { $0.hasPrefix("--lab-form=") })?.dropFirst("--lab-form=".count),
           let form = LabSnakeForm(rawValue: String(value)) {
            UserDefaults.standard.set(form.rawValue, forKey: "snake.lab.form")
        }
        #endif
    }

    private var theme: LabTheme { LabTheme(rawValue: themeRaw) ?? .atelier }
    private var form: LabSnakeForm { LabSnakeForm(rawValue: formRaw) ?? .clay }
    private var palette: LabPalette { theme.palette }
    private var strings: SnakeStrings { SnakeStrings(locale: locale) }
    private var combinationKey: String { "\(theme.rawValue):\(form.rawValue)" }
    private var favorites: [String] { savedCombinations.split(separator: ";").map(String.init) }
    private var isFavorite: Bool { favorites.contains(combinationKey) }
    private var elapsed: String {
        let seconds = Int(session.elapsedSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private var estimatedRange: String {
        let estimate = SnakeDurationEstimates.estimate(for: session.selectedMap, movesPerSecond: session.selectedSpeed.movesPerSecond)
        return strings.format("duration.range", estimate.lowerMinutes, estimate.upperMinutes)
    }
    private var mapTitle: String { strings.text("map.\(session.selectedMap.rawValue).title") }
    private var speedTitle: String { strings.text("speed.\(session.selectedSpeed.rawValue)") }
    private var stateTitle: String {
        if session.stage == .setup { return labText("待开始", "Ready") }
        if session.hasEnded { return labText("已完成", "Finished") }
        return session.isPaused ? strings.text("game.paused") : labText("自动游走中", "Autopilot on")
    }
    private var occupancyText: String { "\(Int(session.occupancy * 100))%" }
    private var layoutReservedHeight: CGFloat {
        switch theme {
        case .atelier, .gallery, .paper: return 390
        case .zen: return 420
        case .arcade: return 360
        case .observatory, .candy: return 400
        case .dashboard: return 410
        case .terminal: return 380
        case .aurora: return 350
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(320, min(geometry.size.width - 76, max(180, (geometry.size.height - layoutReservedHeight) / 1.5)))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    topBar
                    composition(boardWidth: width)
                    if session.hasEnded { finishedMessage }
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: theme == .dashboard ? 620 : 540)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .sheet(item: $activeSheet, onDismiss: sheetDidDismiss) { sheet in
            switch sheet {
            case .schemes: schemesSheet
            case .settings: settingsSheet
            case .original:
                NavigationStack {
                    ContentView()
                        .navigationTitle(labText("原版对照", "Original app"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { doneButton } }
                }
            }
        }
        .onChange(of: session.showsRestartConfirmation) { _, value in showsRestartAlert = value }
        .alert(strings.text("restart.title"), isPresented: $showsRestartAlert) {
            Button(strings.text("action.cancel"), role: .cancel) { session.cancelRestart() }
            Button(strings.text("action.confirmRestart"), role: .destructive) { session.confirmRestart() }
        } message: {
            Text(strings.format("restart.message", elapsed))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.sceneDidBecomeActive() }
            else { session.sceneDidEnterBackground() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SnakeFocus").font(.system(size: 18, weight: .semibold, design: theme == .terminal ? .monospaced : .rounded))
                Text("\(theme.code) / \(form.code)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 4)
            Button {
                schemeSection = 0
                activeSheet = .schemes
            } label: {
                Label(labText("方案", "Schemes"), systemImage: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(palette.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lab.schemes")
            Button { activeSheet = .settings } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(labText("游戏设置", "Game settings"))
            .accessibilityIdentifier("lab.settings")
        }
    }

    @ViewBuilder private var background: some View {
        if theme == .aurora {
            ZStack {
                palette.background
                LinearGradient(colors: [palette.accent.opacity(0.17), .clear, palette.accent2.opacity(0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else if theme == .paper {
            ZStack {
                palette.background
                Canvas { context, size in
                    var rules = Path()
                    for y in stride(from: 20.0, to: size.height, by: 28) {
                        rules.move(to: CGPoint(x: 0, y: y))
                        rules.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(rules, with: .color(palette.ink.opacity(0.055)), lineWidth: 1)
                }
            }
        } else { palette.background }
    }

    @ViewBuilder private func composition(boardWidth: CGFloat) -> some View {
        switch theme {
        case .atelier: atelier(width: boardWidth)
        case .zen: zen(width: boardWidth)
        case .arcade: arcade(width: boardWidth)
        case .observatory: observatory(width: boardWidth)
        case .gallery: gallery(width: boardWidth)
        case .dashboard: dashboard(width: boardWidth)
        case .paper: paper(width: boardWidth)
        case .candy: candy(width: boardWidth)
        case .terminal: terminal(width: boardWidth)
        case .aurora: aurora(width: boardWidth)
        }
    }

    private func atelier(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow(labText("留一点时间给自己", "A MOMENT TO YOURSELF"))
                    Text(labText("让思绪，慢慢流动。", "Let your mind wander."))
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                }
                Spacer(minLength: 4)
            }
            board(width: width, radius: 25)
                .padding(12)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 36))
            HStack(spacing: 0) {
                metric(labText("专注", "Focus"), elapsed)
                Spacer()
                metric(labText("进度", "Filled"), occupancyText)
                Spacer()
                metric(labText("节奏", "Pace"), speedTitle)
            }.padding(.horizontal, 14)
            controls(shape: .pill)
        }
    }

    private func zen(width: CGFloat) -> some View {
        VStack(spacing: 15) {
            HStack(spacing: 8) {
                Rectangle().fill(palette.accent2).frame(width: 25, height: 1)
                Text(labText("一呼，一吸", "BREATHE IN. BREATHE OUT."))
                    .font(.system(size: 12, weight: .regular, design: .serif)).tracking(2)
                Rectangle().fill(palette.accent2).frame(width: 25, height: 1)
            }
            ZStack {
                Circle().stroke(palette.accent.opacity(0.16), lineWidth: 1)
                Circle().trim(from: 0, to: max(0.025, session.occupancy))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(elapsed).font(.system(size: 30, weight: .light, design: .serif)).monospacedDigit()
                    Text(stateTitle).font(.system(size: 10)).foregroundStyle(palette.secondary)
                }
            }.frame(width: 108, height: 108)
            board(width: max(192, width - 22), radius: 40)
            Text(labText("蛇自游走，心自安定。", "The snake wanders. The mind settles."))
                .font(.system(size: 14, design: .serif)).foregroundStyle(palette.secondary)
            controls(shape: .quiet)
        }.frame(maxWidth: .infinity)
    }

    private func arcade(width: CGFloat) -> some View {
        VStack(spacing: 13) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SNAKE / AUTO").font(.system(size: 25, weight: .black, design: .monospaced)).tracking(-1)
                    Text(stateTitle.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.accent2)
                }
                Spacer()
                Text(String(format: "%04d", session.engine.foodsEaten))
                    .font(.system(size: 31, weight: .black, design: .monospaced)).foregroundStyle(palette.accent)
            }
            HStack {
                Text("1UP  \(elapsed)")
                Spacer()
                Text("\(labText("填充", "FILL")) \(occupancyText)")
            }.font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(palette.secondary)
            board(width: width, radius: 2)
                .padding(7)
                .overlay(Rectangle().stroke(palette.accent, lineWidth: 2))
                .shadow(color: palette.accent.opacity(0.25), radius: 12)
            controls(shape: .arcade)
            Text(labText("无需操作 · 自动挑战", "HANDS FREE · AUTO CHALLENGE"))
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.7).foregroundStyle(palette.accent2)
        }
    }

    private func observatory(width: CGFloat) -> some View {
        VStack(spacing: 17) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle().stroke(palette.line, lineWidth: 1)
                    Circle().stroke(palette.line, style: StrokeStyle(lineWidth: 1, dash: [2, 5])).padding(10)
                    Circle().trim(from: 0, to: max(0.025, session.occupancy))
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(occupancyText).font(.system(size: 23, weight: .light, design: .rounded))
                        Text(labText("轨道覆盖", "COVERAGE")).font(.system(size: 8, weight: .medium)).foregroundStyle(palette.secondary)
                    }
                }.frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 10) {
                    eyebrow(labText("专注观测站 / 01", "FOCUS OBSERVATORY / 01"))
                    Text(elapsed).font(.system(size: 29, weight: .light, design: .monospaced)).monospacedDigit()
                    Label(stateTitle, systemImage: "circle.dotted").font(.system(size: 11)).foregroundStyle(palette.accent)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 15) {
                    Image(systemName: "location.north.line").font(.system(size: 16))
                    Text("N").font(.system(size: 10, design: .monospaced))
                    Rectangle().fill(palette.line).frame(width: 1)
                    Text("24").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(palette.secondary).frame(width: 18)
                board(width: max(192, width - 15), radius: 18)
            }
            HStack {
                metric(labText("任务时长", "Duration"), estimatedRange)
                Spacer()
                metric(labText("轨道速度", "Pace"), speedTitle)
            }
            controls(shape: .pill)
        }
    }

    private func gallery(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(labText("游走的艺术", "The art of wandering"))
                    .font(.system(size: 27, weight: .regular, design: .serif))
                Spacer(minLength: 0)
                Text("No. \(String(format: "%02d", form.number))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
            }
            board(width: max(192, width - 16), radius: 0)
                .padding(18)
                .background(palette.surface)
                .overlay(Rectangle().stroke(palette.ink.opacity(0.3), lineWidth: 5).padding(-5))
                .padding(5)
                .shadow(color: palette.ink.opacity(0.09), radius: 12, y: 8)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(form.title).font(.system(size: 16, weight: .semibold, design: .serif))
                    Text("\(mapTitle) / \(form.is3D ? "3D" : "2D")")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(elapsed).font(.system(size: 21, weight: .light, design: .serif)).monospacedDigit()
                    Text(stateTitle).font(.system(size: 10)).foregroundStyle(palette.secondary)
                }
            }.padding(.horizontal, 8)
            controls(shape: .quiet)
        }
    }

    private func dashboard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(labText("今天，专注一点。", "Make room for focus."))
                        .font(.system(size: 25, weight: .bold))
                    Text(stateTitle).font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.xaxis").font(.system(size: 22)).foregroundStyle(palette.accent)
            }
            HStack(spacing: 8) {
                dashboardMetric(labText("专注时间", "Focus time"), elapsed, "clock")
                dashboardMetric(labText("已吃食物", "Food eaten"), "\(session.engine.foodsEaten)", "square.fill")
                dashboardMetric(labText("棋盘填充", "Board filled"), occupancyText, "chart.pie")
            }
            HStack {
                Text(labText("实时棋盘", "Live board")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(mapTitle).font(.system(size: 10)).foregroundStyle(palette.secondary)
            }.padding(.top, 2)
            board(width: width, radius: 16).frame(maxWidth: .infinity)
            controls(shape: .pill)
        }
    }

    private func paper(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(labText("慢游手记", "Notes on wandering"))
                        .font(.system(size: 28, weight: .medium, design: .serif))
                    Text(labText("给自己的一小段留白", "A little blank space, just for you"))
                        .font(.system(size: 11, design: .serif)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Text("\(theme.code)\n\(form.code)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).lineSpacing(4)
                    .padding(8).foregroundStyle(palette.accent)
                    .overlay(Rectangle().stroke(palette.accent, lineWidth: 1.5))
                    .rotationEffect(.degrees(6))
            }
            HStack {
                Text("\(labText("记录", "ENTRY")) 01")
                Spacer()
                Text("\(labText("专注", "FOCUS")) \(elapsed)")
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
            board(width: width, radius: 1)
                .padding(9)
                .background(palette.surface)
                .overlay(Rectangle().stroke(palette.ink.opacity(0.25), lineWidth: 1))
                .frame(maxWidth: .infinity)
            HStack {
                Image(systemName: "pencil.line")
                Text("\(form.title) · \(speedTitle)")
                Spacer()
                Text(occupancyText)
            }.font(.system(size: 12, design: .serif)).foregroundStyle(palette.secondary)
            controls(shape: .quiet)
        }
    }

    private func candy(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(labText("开个小差吧！", "Time for a little wiggle!"))
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                    Text(stateTitle).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkles").font(.system(size: 23)).foregroundStyle(palette.accent2)
                    .frame(width: 48, height: 48).background(palette.surface, in: RoundedRectangle(cornerRadius: 17)).rotationEffect(.degrees(9))
            }
            HStack(spacing: 12) {
                candyTag(elapsed, label: labText("专注计时", "Focus timer"), angle: -3, color: palette.accent2)
                candyTag("\(session.engine.foodsEaten)", label: labText("小小收获", "Little wins"), angle: 3, color: palette.accent)
            }.padding(.vertical, 2)
            board(width: max(192, width - 8), radius: 30)
                .padding(10)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 40))
                .overlay(RoundedRectangle(cornerRadius: 40).stroke(palette.accent.opacity(0.25), lineWidth: 3))
                .shadow(color: palette.accent.opacity(0.13), radius: 0, y: 6)
            controls(shape: .candy)
        }
    }

    private func terminal(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text("$ snake --autopilot").font(.system(size: 22, weight: .semibold, design: .monospaced))
                Text("[\(session.stage == .setup ? "READY" : session.hasEnded ? "DONE" : session.isPaused ? "PAUSED" : "RUNNING")] \(form.rawValue)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
            }
            Rectangle().fill(palette.accent.opacity(0.5)).frame(height: 1)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    terminalLine("time", elapsed)
                    terminalLine("food", String(format: "%04d", session.engine.foodsEaten))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    terminalLine("fill", occupancyText)
                    terminalLine("pace", "\(Int(session.speed.movesPerSecond))/s")
                }
            }
            board(width: width, radius: 0)
                .padding(5)
                .overlay(Rectangle().stroke(palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .frame(maxWidth: .infinity)
            Text("> \(mapTitle) / \(estimatedRange)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
            controls(shape: .terminal)
        }
    }

    private func aurora(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(labText("沉入此刻", "Drift into the present"))
                    .font(.system(size: 24, weight: .light, design: .rounded)).tracking(1)
                Text("\(form.title) · \(stateTitle)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(palette.secondary)
            }
            ZStack(alignment: .bottom) {
                board(width: min(340, width + 14), radius: 32)
                    .overlay(RoundedRectangle(cornerRadius: 32).stroke(LinearGradient(colors: [palette.accent.opacity(0.6), .clear, palette.accent2.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: palette.accent2.opacity(0.14), radius: 30, y: 12)
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(elapsed).font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                        Text(labText("本次专注", "FOCUS TIME")).font(.system(size: 8)).foregroundStyle(palette.secondary)
                    }
                    Rectangle().fill(palette.line).frame(width: 1, height: 27)
                    Text(occupancyText).font(.system(size: 23, weight: .light, design: .rounded))
                }
                .padding(.horizontal, 23).padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(palette.ink.opacity(0.1), lineWidth: 1))
                .offset(y: 22)
            }.padding(.bottom, 27)
            controls(shape: .floating)
            Text(labText("不必追赶，让光慢慢流过。", "No rush. Let the light flow."))
                .font(.system(size: 12, weight: .light)).foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func board(width: CGFloat, radius: CGFloat) -> some View {
        LabBoardView(session: session, form: form, theme: theme, specimen: session.stage == .setup)
            .frame(width: width, height: width * CGFloat(session.engine.configuration.rows) / CGFloat(session.engine.configuration.columns))
            .background(palette.board)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .accessibilityLabel(labText("自动贪吃蛇棋盘，", "Automatic snake board, ") + form.title)
            .accessibilityIdentifier("lab.board")
    }

    private func controls(shape: LabControlShape) -> some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: primarySymbol)
                    .font(.system(size: 14, weight: .semibold, design: shape == .terminal || shape == .arcade ? .monospaced : .rounded))
                    .frame(maxWidth: .infinity, minHeight: shape == .candy ? 52 : 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LabGameButtonStyle(palette: palette, shape: shape, primary: true))
            .accessibilityIdentifier("lab.primary")
            if session.stage != .setup && !session.hasEnded {
                Button { session.requestRestart() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 49, height: shape == .candy ? 52 : 46)
                }
                .buttonStyle(LabGameButtonStyle(palette: palette, shape: shape, primary: false))
                .accessibilityLabel(strings.text("action.restart"))
                .accessibilityIdentifier("lab.restart")
            } else {
                Button { activeSheet = .settings } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 16))
                        .frame(width: 49, height: shape == .candy ? 52 : 46)
                }
                .buttonStyle(LabGameButtonStyle(palette: palette, shape: shape, primary: false))
                .accessibilityLabel(labText("开局设置", "Game setup"))
            }
        }
        .frame(maxWidth: shape == .quiet ? 280 : 380)
        .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        if session.stage == .setup { return labText("开始专注", "Start focus") }
        if session.hasEnded { return labText("再来一局", "New session") }
        return strings.text(session.isPaused ? "action.resume" : "action.pause")
    }
    private var primarySymbol: String {
        session.stage == .setup || session.isPaused ? "play.fill" : session.hasEnded ? "arrow.counterclockwise" : "pause.fill"
    }
    private func primaryAction() {
        if session.stage == .setup { session.begin() }
        else if session.hasEnded { session.requestRestart() }
        else { session.togglePause() }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(palette.secondary)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(palette.secondary)
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
    }
    private func dashboardMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(palette.accent)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 17))
    }
    private func candyTag(_ value: String, label: String, angle: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(value).font(.system(size: 23, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(2)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 11)
        .background(color.opacity(0.19), in: RoundedRectangle(cornerRadius: 17))
        .rotationEffect(.degrees(angle))
    }
    private func terminalLine(_ key: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Text(key + ":").foregroundStyle(palette.secondary)
            Text(value).foregroundStyle(palette.accent)
        }.font(.system(size: 12, design: .monospaced)).monospacedDigit()
    }
    private var finishedMessage: some View {
        VStack(spacing: 6) {
            Text(strings.text("rest.title")).font(.headline)
            Text(strings.format("rest.message", elapsed)).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(palette.secondary)
        }.padding(18).frame(maxWidth: .infinity).background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
                Text(session.stage == .setup ? labText("蛇形预览 · 点击开始后自动游走", "Material preview · Start to run automatically") : "\(mapTitle) · \(speedTitle) · \(stateTitle)")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
            Button {
                schemeSection = 1
                activeSheet = .schemes
            } label: {
                Text("\(theme.title)  /  \(form.title)  \(form.is3D ? "3D" : "2D")")
                    .font(.system(size: 10, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var schemesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedCombination
                    Picker(labText("探索分类", "Explore"), selection: $schemeSection) {
                        Text(labText("界面 · 10", "Layouts · 10")).tag(0)
                        Text(labText("蛇形 · 10", "Snakes · 10")).tag(1)
                        Text(labText("收藏", "Saved")).tag(2)
                    }.pickerStyle(.segmented)
                    if schemeSection == 0 {
                        Text(labText("仅切换界面会保留蛇形与本局进度。也可直接选用推荐搭配。", "Changing a layout keeps your snake and session. Or try its recommended pairing."))
                            .font(.footnote).foregroundStyle(palette.secondary)
                        LazyVStack(spacing: 12) { ForEach(LabTheme.allCases) { themeOption($0) } }
                    } else if schemeSection == 1 {
                        Text(labText("蛇形独立切换，界面、地图与计时保持当前状态。", "Switch materials independently while keeping the layout, map and timer."))
                            .font(.footnote).foregroundStyle(palette.secondary)
                        LazyVStack(spacing: 10) { ForEach(LabSnakeForm.allCases) { formOption($0) } }
                    } else { favoritesSection }
                    Button { activeSheet = .original } label: {
                        Label(labText("打开原版对照", "Compare with the original"), systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(.bordered)
                }.padding(20)
            }
            .background(palette.background)
            .navigationTitle(labText("风格实验室", "Style lab"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { doneButton } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var selectedCombination: some View {
        HStack(spacing: 14) {
            Image(systemName: form.symbol).font(.system(size: 25)).foregroundStyle(palette.accent)
                .frame(width: 56, height: 56).background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(labText("当前组合", "CURRENT PAIRING")).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(palette.secondary)
                Text("\(theme.title) + \(form.title)").font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(theme.code) / \(form.code) · \(form.is3D ? "3D" : "2D")").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 2)
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "bookmark.fill" : "bookmark").font(.system(size: 19))
                    .frame(width: 40, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(isFavorite ? labText("取消收藏组合", "Remove saved pairing") : labText("收藏当前组合", "Save this pairing"))
        }
    }

    private func themeOption(_ option: LabTheme) -> some View {
        let selected = theme == option
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                themeRaw = option.rawValue
            } label: {
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(option.code).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        HStack(spacing: 3) {
                            ForEach(0..<3) { index in
                                Circle().fill([option.palette.background, option.palette.accent, option.palette.accent2][index])
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(option.palette.ink.opacity(0.15), lineWidth: 0.5))
                            }
                        }
                    }.frame(width: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(option.title).font(.system(size: 16, weight: .semibold))
                        Text(option.detail).font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? palette.accent : palette.secondary.opacity(0.4))
                        .accessibilityHidden(true)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lab.theme.\(option.rawValue)")
            .accessibilityValue(strings.text(selected ? "a11y.selected" : "a11y.notSelected"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button {
                themeRaw = option.rawValue
                formRaw = option.recommendedForm.rawValue
            } label: {
                Label(labText("推荐搭配", "Recommended") + " · " + option.recommendedForm.title, systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(palette.accent)
        }
        .padding(15)
        .background(selected ? palette.accent.opacity(0.09) : palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? palette.accent.opacity(0.45) : palette.line, lineWidth: 1))
    }

    private func formOption(_ option: LabSnakeForm) -> some View {
        let selected = form == option
        return Button {
            formRaw = option.rawValue
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol).font(.system(size: 21)).foregroundStyle(palette.accent)
                    .frame(width: 46, height: 48).background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(option.title).font(.system(size: 15, weight: .semibold))
                        Text(option.is3D ? "3D" : "2D").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(palette.accent.opacity(0.15), in: Capsule())
                    }
                    Text(option.detail).font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(option.code).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? palette.accent.opacity(0.09) : palette.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? palette.accent.opacity(0.45) : palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lab.form.\(option.rawValue)")
        .accessibilityValue(strings.text(selected ? "a11y.selected" : "a11y.notSelected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var favoritesSection: some View {
        if favorites.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bookmark").font(.system(size: 31)).foregroundStyle(palette.accent)
                Text(labText("记下喜欢的组合", "Keep your favorite pairings")).font(.headline)
                Text(labText("点击当前组合旁的书签，稍后可在这里快速比较。", "Tap the bookmark beside the current pairing to compare it here later."))
                    .font(.footnote).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 35)
        } else {
            VStack(spacing: 10) {
                ForEach(favorites, id: \.self) { key in
                    let pieces = key.split(separator: ":").map(String.init)
                    if pieces.count == 2, let savedTheme = LabTheme(rawValue: pieces[0]), let savedForm = LabSnakeForm(rawValue: pieces[1]) {
                        HStack {
                            Button {
                                themeRaw = savedTheme.rawValue
                                formRaw = savedForm.rawValue
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(savedTheme.title) + \(savedForm.title)").font(.system(size: 14, weight: .medium))
                                    Text("\(savedTheme.code) / \(savedForm.code)").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button { removeFavorite(key) } label: {
                                Image(systemName: "bookmark.slash").frame(width: 40, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(labText("取消收藏", "Remove pairing"))
                        }.padding(13).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(labText("当前界面", "Layout"), value: theme.title)
                    LabeledContent(labText("当前蛇形", "Snake material"), value: form.title)
                    Button { activeSheet = .schemes } label: {
                        Label(labText("打开方案库", "Open schemes"), systemImage: "square.grid.2x2")
                    }
                }
                Section {
                    Picker(strings.text("setup.map"), selection: Binding(get: { session.selectedMap }, set: { session.selectMap($0) })) {
                        ForEach(SnakeMap.allCases) { map in Text(strings.text("map.\(map.rawValue).title")).tag(map) }
                    }
                    Text(strings.text("map.\(session.selectedMap.rawValue).subtitle")).font(.footnote).foregroundStyle(.secondary)
                    Picker(strings.text("setup.speed"), selection: Binding(get: { session.selectedSpeed }, set: { session.selectSpeed($0) })) {
                        ForEach(SnakeSpeed.allCases) { speed in Text(strings.text("speed.\(speed.rawValue)")).tag(speed) }
                    }
                    LabeledContent(labText("预计一局", "Estimated session"), value: estimatedRange)
                } header: {
                    Text(labText("开局设置", "Game setup"))
                } footer: {
                    Text(session.stage == .setup
                         ? labText("时长取自原版模拟样本。地图和速度在开始后锁定。", "Duration comes from the production simulation samples. Map and speed lock after starting.")
                         : labText("本局进行中。重开后可更换地图和速度；界面与蛇形随时可切换。", "Restart to change the map or speed. Layout and material can change at any time."))
                }.disabled(session.stage != .setup)
                Section {
                    Button {
                        activeSheet = nil
                        primaryAction()
                    } label: { Label(primaryTitle, systemImage: primarySymbol) }
                    .accessibilityIdentifier("lab.settings.primary")
                    if session.stage != .setup && !session.hasEnded {
                        Button(role: .destructive) {
                            restartsAfterSheetDismiss = true
                            activeSheet = nil
                        } label: { Label(strings.text("action.restart"), systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("lab.settings.restart")
                    }
                    Button { activeSheet = .original } label: {
                        Label(labText("原版对照", "Original app"), systemImage: "rectangle.on.rectangle")
                    }
                }
            }
            .navigationTitle(labText("游戏设置", "Game settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { doneButton } }
        }.presentationDetents([.large])
    }

    private var doneButton: some View {
        Button(labText("完成", "Done")) { activeSheet = nil }
    }
    private func sheetDidDismiss() {
        let shouldRestart = restartsAfterSheetDismiss
        restartsAfterSheetDismiss = false
        guard shouldRestart, activeSheet == nil else { return }
        // Present the confirmation only after the sheet releases its presenter.
        session.requestRestart()
    }
    private func toggleFavorite() {
        if isFavorite { removeFavorite(combinationKey) }
        else { savedCombinations = (favorites + [combinationKey]).joined(separator: ";") }
    }
    private func removeFavorite(_ key: String) {
        savedCombinations = favorites.filter { $0 != key }.joined(separator: ";")
    }
}

private enum LabSheet: String, Identifiable {
    case schemes, settings, original
    var id: String { rawValue }
}

private enum LabControlShape { case pill, quiet, arcade, candy, terminal, floating }

private struct LabGameButtonStyle: ButtonStyle {
    let palette: LabPalette
    let shape: LabControlShape
    let primary: Bool
    private var radius: CGFloat {
        switch shape {
        case .arcade, .terminal: return 3
        case .candy: return 18
        case .quiet: return 7
        case .pill, .floating: return 30
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? palette.background : palette.ink)
            .background(primary ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(shape == .terminal || shape == .arcade ? palette.accent : .clear, lineWidth: 1))
            .shadow(color: shape == .candy ? palette.ink.opacity(0.16) : .clear, radius: 0, y: 4)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
