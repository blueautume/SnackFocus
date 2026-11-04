import SwiftUI

struct ContentView: View {
    @StateObject private var session = SnakeSession()
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPrivacyPolicy = false
    @State private var visibleSafeArea = EdgeInsets()
    @AccessibilityFocusState private var restartTitleFocused: Bool
    @AccessibilityFocusState private var privacyTitleFocused: Bool
    @AccessibilityFocusState private var privacyButtonFocused: Bool

    #if DEBUG
    init() {}

    /// Inject a session for previews and layout checks without changing live state.
    @MainActor init(session: SnakeSession) {
        _session = StateObject(wrappedValue: session)
    }
    #endif

    private var strings: SnakeStrings { SnakeStrings(locale: locale) }
    private var isImmersed: Bool { session.isImmersed }

    var body: some View {
        GeometryReader { geometry in
            // Some devices reclaim safe area when system bars disappear.
            let topGap = max(0, visibleSafeArea.top - geometry.safeAreaInsets.top)
            let bottomGap = max(0, visibleSafeArea.bottom - geometry.safeAreaInsets.bottom)
            let gameSize = CGSize(width: geometry.size.width, height: max(0, geometry.size.height - topGap - bottomGap))
            ScrollView(showsIndicators: false) {
                if session.stage == .setup {
                    setup(in: geometry.size)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 660)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                } else {
                    VStack(spacing: 16) {
                        header
                            .modifier(GameChrome(hidden: isImmersed))
                        game(in: gameSize)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 510)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: gameSize.height)
                    .padding(.top, topGap)
                    .padding(.bottom, bottomGap)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { session.recordInteraction() },
                                 including: session.isRunning ? .all : .subviews)
            .disabled(session.showsRestartConfirmation || showsPrivacyPolicy)
            .accessibilityHidden(session.showsRestartConfirmation || showsPrivacyPolicy)
        }
        .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { insets in
            if !isImmersed { visibleSafeArea = insets }
        }
        .modifier(GameImmersion(amount: isImmersed ? 1 : 0))
        .foregroundStyle(LCD.ink)
        .preferredColorScheme(.light)
        .statusBarHidden(isImmersed)
        .persistentSystemOverlays(isImmersed ? .hidden : .automatic)
        .animation(.easeInOut(duration: reduceMotion ? 0.25 : 1.8), value: isImmersed)
        .overlay {
            if isImmersed {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { session.recordInteraction() }
                    .accessibilityHidden(true)
            }
            if session.showsRestartConfirmation { restartConfirmation }
            if showsPrivacyPolicy { privacyPolicy }
        }
        .onChange(of: session.showsRestartConfirmation) { _, shown in
            restartTitleFocused = shown
        }
        .onChange(of: showsPrivacyPolicy) { _, shown in
            privacyTitleFocused = shown
            privacyButtonFocused = !shown
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
            PixelText(text: strings.text("app.title"), pixel: 3)
                .accessibilityLabel(strings.text("a11y.app"))
            Spacer()
            if session.stage == .setup {
                Button { showsPrivacyPolicy = true } label: {
                    PixelLockIcon()
                        .foregroundStyle(LCD.ink.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.text("a11y.privacy"))
                .accessibilityIdentifier("setup.privacy")
                .accessibilityFocused($privacyButtonFocused)
            }
        }
        .frame(height: session.stage == .setup ? 44 : 36)
    }

    private func setup(in size: CGSize) -> some View {
        let contentWidth = max(0, min(size.width, 660) - 40)
        let sectionGap: CGFloat = size.height < 700 ? 14 : 18
        let maximumThumbnailHeight = min(240, floor(max(0, contentWidth - 24) / 3 * 1.5))
        // Four columns only when every translated label and estimate has room.
        let speedColumnCount = contentWidth >= 334 && !dynamicTypeSize.isAccessibilitySize ? 4 : 2
        let reservedHeight: CGFloat = 364 + sectionGap * 4 + (speedColumnCount == 2 ? 90 : 0)
        let thumbnailHeight = min(maximumThumbnailHeight, max(108, floor((size.height - reservedHeight) / 2)))
        return VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: sectionGap)

            VStack(alignment: .leading, spacing: 10) {
                PixelLabel(text: strings.text("setup.map"), size: 18)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(SnakeMap.allCases) { map in
                        mapChoice(map, height: thumbnailHeight)
                    }
                }
            }
            Spacer(minLength: sectionGap)

            VStack(alignment: .leading, spacing: 12) {
                PixelLabel(text: strings.text("setup.style"), size: 18)
                HStack(spacing: 10) {
                    ForEach(SnakeAppearance.allCases) { appearance in appearanceChoice(appearance) }
                }
            }
            Spacer(minLength: sectionGap)

            VStack(alignment: .leading, spacing: 12) {
                PixelLabel(text: strings.text("setup.speed"), size: 18)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: speedColumnCount), spacing: 10) {
                    ForEach(SnakeSpeed.allCases) { speed in speedChoice(speed) }
                }
            }
            Spacer(minLength: sectionGap)

            Button { session.begin() } label: {
                PixelControlLabel(text: strings.text("setup.start"), size: 24)
                    .frame(minHeight: 56)
            }
            .buttonStyle(PixelButtonStyle(emphasized: true))
            .accessibilityLabel(strings.text("a11y.start"))
            .accessibilityIdentifier("setup.start")
        }
    }

    private func appearanceChoice(_ appearance: SnakeAppearance) -> some View {
        let selected = appearance == session.selectedAppearance
        return Button { session.selectAppearance(appearance) } label: {
            PixelControlLabel(text: strings.text("appearance.\(appearance.rawValue)"), size: 18)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(PixelChoiceStyle(selected: selected))
        .accessibilityLabel(strings.format("a11y.appearance", strings.text("appearance.\(appearance.rawValue)")))
        .accessibilityIdentifier("appearance.\(appearance.rawValue)")
        .accessibilityValue(strings.text(selected ? "a11y.selected" : "a11y.notSelected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func mapChoice(_ map: SnakeMap, height: CGFloat) -> some View {
        let selected = map == session.selectedMap
        let configuration = map.configuration
        return Button { session.selectMap(map) } label: {
            PixelMapThumbnail(configuration: configuration)
                .aspectRatio(CGFloat(configuration.columns) / CGFloat(configuration.rows), contentMode: .fit)
                .padding(7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(PixelMapChoiceStyle(selected: selected))
        .accessibilityLabel(strings.format("a11y.map", strings.text("map.\(map.rawValue).title"), strings.text("map.\(map.rawValue).subtitle")))
        .accessibilityIdentifier("map.\(map.rawValue)")
        .accessibilityValue(strings.text(selected ? "a11y.selected" : "a11y.notSelected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func speedChoice(_ speed: SnakeSpeed) -> some View {
        let selected = speed == session.selectedSpeed
        let estimate = SnakeDurationEstimates.estimate(for: session.selectedMap, movesPerSecond: speed.movesPerSecond)
        return Button { session.selectSpeed(speed) } label: {
            VStack(spacing: 8) {
                PixelControlLabel(text: strings.text("speed.\(speed.rawValue)"), size: 18)
                PixelControlLabel(text: strings.format("duration.range", estimate.lowerMinutes, estimate.upperMinutes), size: 12)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 4)
        }
        .buttonStyle(PixelChoiceStyle(selected: selected))
        .accessibilityLabel(strings.format("duration.a11y", strings.text("speed.\(speed.rawValue)"), estimate.lowerMinutes, estimate.upperMinutes))
        .accessibilityIdentifier("speed.\(speed.rawValue)")
        .accessibilityValue(strings.text(selected ? "a11y.selected" : "a11y.notSelected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func game(in size: CGSize) -> some View {
        let configuration = session.engine.configuration
        let ratio = CGFloat(configuration.columns) / CGFloat(configuration.rows)
        let available = min(size.width - 50, max(256, (size.height - 210) * ratio), 448)
        let width = floor(available / CGFloat(configuration.columns)) * CGFloat(configuration.columns)
        return VStack(spacing: 16) {
            scoreLine
                .modifier(GameChrome(hidden: isImmersed))
            board(width: width)
                .frame(maxWidth: .infinity)
            if !session.hasEnded {
                HStack(spacing: 14) {
                    Button { session.togglePause() } label: {
                        PixelControlLabel(text: strings.text(session.isPaused ? "action.resume" : "action.pause"), size: 24)
                    }
                    .accessibilityLabel(strings.text(session.isPaused ? "a11y.resume" : "a11y.pause"))
                    .accessibilityIdentifier("game.pause")
                    Button { session.requestRestart() } label: {
                        PixelControlLabel(text: strings.text("action.restart"), size: 24)
                    }
                    .accessibilityLabel(strings.text("a11y.restart"))
                    .accessibilityIdentifier("game.restart")
                }
                .buttonStyle(PixelButtonStyle())
                .padding(.bottom, 3)
                .modifier(GameChrome(hidden: isImmersed))
            }
        }
    }

    private var scoreLine: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                PixelLabel(text: strings.text("game.score"), size: 12)
                PixelText(text: String(format: "%04d", session.engine.foodsEaten), pixel: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.format("a11y.score", session.engine.foodsEaten))
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                PixelLabel(text: strings.text("game.time"), size: 12)
                PixelText(text: timeText, pixel: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.format("a11y.time", Int(session.elapsedSeconds) / 60, Int(session.elapsedSeconds) % 60))
        }
        .padding(.horizontal, 5)
    }

    private func board(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !session.isRunning || reduceMotion)) { timeline in
            let time = session.animationTime(at: timeline.date)
            let progress = session.hasEnded ? 1 : min(1, max(0, (time - session.movementBeganAtElapsed) / session.moveDuration))
            RetroBoard(engine: session.engine, previousSnake: session.previousSnake,
                       progress: progress, time: time, appearance: session.selectedAppearance,
                       reduceMotion: reduceMotion)
        }
        .frame(width: width, height: width * CGFloat(session.engine.configuration.rows) / CGFloat(session.engine.configuration.columns))
        .overlay {
            if session.hasEnded {
                endCard.padding(18)
            } else if session.isPaused {
                PixelLabel(text: strings.text("game.paused"), size: 24)
                    .padding(20)
                    .background(LCD.paper)
                    .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
                    .accessibilityLabel(strings.text("a11y.paused"))
            }
        }
        .padding(5)
        .overlay { PixelBoardOutline() }
        .accessibilityActions {
            if isImmersed {
                Button(strings.text("a11y.showControls")) { session.recordInteraction() }
            }
        }
    }

    private var endCard: some View {
        VStack(spacing: 17) {
            PixelControlLabel(text: strings.text(session.engine.phase == .filled ? "game.clear" : "game.over"), size: 24)
            PixelControlLabel(text: strings.text("rest.title"), size: 24)
            PixelLabel(text: strings.format("rest.message", timeText), size: 12)
                .multilineTextAlignment(.center)
            Button { session.requestRestart() } label: {
                PixelControlLabel(text: strings.text("action.restart"), size: 24)
            }
            .buttonStyle(PixelButtonStyle())
            .frame(maxWidth: 170)
            .accessibilityLabel(strings.text("a11y.restartFinished"))
            .accessibilityIdentifier("game.restart")
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
                PixelControlLabel(text: strings.text("restart.title"), size: 24)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($restartTitleFocused)
                PixelLabel(text: strings.format("restart.message", timeText), size: 12)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button { session.cancelRestart() } label: {
                        PixelControlLabel(text: strings.text("action.cancel"), size: 18)
                    }
                    .buttonStyle(PixelButtonStyle())
                    .accessibilityIdentifier("restart.cancel")
                    Button { session.confirmRestart() } label: {
                        PixelControlLabel(text: strings.text("action.confirmRestart"), size: 18)
                    }
                    .buttonStyle(PixelButtonStyle(emphasized: true))
                    .accessibilityIdentifier("restart.confirm")
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

    private var privacyPolicy: some View {
        GeometryReader { geometry in
            ZStack {
                LCD.paper.opacity(0.86)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showsPrivacyPolicy = false }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        PixelLabel(text: strings.text("privacy.title"), size: 24)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($privacyTitleFocused)
                            .accessibilityIdentifier("privacy.title")
                        Spacer(minLength: 0)
                        Button { showsPrivacyPolicy = false } label: {
                            PixelControlLabel(text: strings.text("action.close"), size: 18)
                        }
                        .buttonStyle(PixelButtonStyle())
                        .frame(width: 84)
                        .accessibilityLabel(strings.text("a11y.closePrivacy"))
                        .accessibilityIdentifier("privacy.close")
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            PixelLabel(text: strings.text("privacy.updated"), size: 12)
                            PixelLabel(text: strings.text("privacy.intro"), size: 16)
                            privacySection(title: "privacy.data.title", body: "privacy.data.body")
                            privacySection(title: "privacy.storage.title", body: "privacy.storage.body")
                            privacySection(title: "privacy.services.title", body: "privacy.services.body")
                            privacySection(title: "privacy.choices.title", body: "privacy.choices.body")
                            privacySection(title: "privacy.updates.title", body: "privacy.updates.body")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 8)
                    }
                    .accessibilityIdentifier("privacy.content")
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(height: min(680, max(0, geometry.size.height - 48)))
                .background(LCD.paper)
                .overlay { Rectangle().strokeBorder(LCD.ink, lineWidth: 2) }
                .background { Rectangle().fill(LCD.ink).offset(x: 5, y: 5) }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { showsPrivacyPolicy = false }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func privacySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelLabel(text: strings.text(title), size: 18)
                .accessibilityAddTraits(.isHeader)
            PixelLabel(text: strings.text(body), size: 16)
        }
    }

    private var timeText: String {
        let seconds = Int(session.elapsedSeconds)
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

}

private struct GameChrome: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

private struct GameImmersion: ViewModifier, Animatable {
    var amount: Double

    nonisolated var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        let palette = LCD.GamePalette(immersion: amount)
        content
            .environment(\.gamePalette, palette)
            .background(palette.background.ignoresSafeArea())
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
    let appearance: SnakeAppearance
    let reduceMotion: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.gamePalette) private var palette
    @Environment(\.locale) private var locale
    private var strings: SnakeStrings { SnakeStrings(locale: locale) }

    var body: some View {
        Canvas { context, size in
            let frame = SnakeVisualGeometry.frame(
                configuration: engine.configuration, snake: engine.snake, previousSnake: previousSnake,
                food: engine.food, progress: progress, time: time,
                completedMoves: engine.steps, appearance: appearance, reduceMotion: reduceMotion
            )
            let pitch = size.width / CGFloat(frame.columns)
            let dotSize = max(1 / displayScale, floor(pitch * displayScale * 0.90) / displayScale)
            let inset = (pitch - dotSize) / 2
            var snake = Path()
            var food = Path()
            for y in 0..<frame.rows {
                for x in 0..<frame.columns where frame.dots[y * frame.columns + x] != 0 {
                    let rect = CGRect(
                        x: ((CGFloat(x) * pitch + inset) * displayScale).rounded() / displayScale,
                        y: ((CGFloat(y) * pitch + inset) * displayScale).rounded() / displayScale,
                        width: dotSize, height: dotSize
                    )
                    if frame.dots[y * frame.columns + x] == 2 {
                        food.addRect(rect)
                    } else {
                        snake.addRect(rect)
                    }
                }
            }
            if let edge = palette.detailEdge {
                let lineWidth = 2 / displayScale
                context.stroke(snake, with: .color(edge), lineWidth: lineWidth)
                context.stroke(food, with: .color(edge), lineWidth: lineWidth)
            }
            context.fill(snake, with: .color(palette.snake))
            context.fill(food, with: .color(palette.food))
        }
        .background(palette.background)
        .overlay { PixelWalls(configuration: engine.configuration) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings.format("a11y.board", boundaryDescription))
        .accessibilityValue(strings.format("a11y.occupancy", engine.snake.count, engine.configuration.cellCount))
    }

    private var boundaryDescription: String {
        let configuration = engine.configuration
        let horizontalPassage = configuration.wrapsHorizontally && (0..<configuration.rows).contains { row in
            configuration.contains(GridCell(x: 0, y: row))
                && configuration.contains(GridCell(x: configuration.columns - 1, y: row))
        }
        let verticalPassage = configuration.wrapsVertically && (0..<configuration.columns).contains { column in
            configuration.contains(GridCell(x: column, y: 0))
                && configuration.contains(GridCell(x: column, y: configuration.rows - 1))
        }
        let edges: String
        if horizontalPassage && verticalPassage { edges = strings.text("a11y.boundary.both") }
        else if horizontalPassage { edges = strings.text("a11y.boundary.horizontal") }
        else if verticalPassage { edges = strings.text("a11y.boundary.vertical") }
        else { edges = strings.text("a11y.boundary.closed") }
        return configuration.walls.isEmpty
            ? strings.format("a11y.boundary.board", edges)
            : strings.format("a11y.boundary.walls", edges, configuration.walls.count)
    }
}

#Preview { ContentView() }
