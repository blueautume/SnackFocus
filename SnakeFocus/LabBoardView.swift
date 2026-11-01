import SwiftUI

struct LabBoardView: View {
    @ObservedObject var session: SnakeSession
    let form: LabSnakeForm
    let theme: LabTheme
    var specimen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: specimen || !session.isRunning || reduceMotion || scenePhase != .active)) { timeline in
            let input = snapshot(at: timeline.date)
            Group {
                if form.is3D {
                    LabSnake3DView(input: input, form: form, palette: theme.palette)
                } else {
                    LabSnakeCanvas(input: input, form: form, palette: theme.palette)
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(labText("贪吃蛇棋盘，", "Snake board, ") + form.title)
            .accessibilityValue(specimen ? labText("材质试样", "Material specimen") : labText("得分 ", "Score ") + String(session.engine.foodsEaten))
        }
        .aspectRatio(CGFloat(session.engine.configuration.columns) / CGFloat(session.engine.configuration.rows), contentMode: .fit)
        .background(theme.palette.board)
    }

    private func snapshot(at date: Date) -> LabBoardInput {
        if specimen { return .specimen }
        let time = session.animationTime(at: date)
        let progress = session.hasEnded ? 1 : min(1, max(0, (time - session.movementBeganAtElapsed) / session.moveDuration))
        return LabBoardInput(configuration: session.engine.configuration, snake: session.engine.snake,
            previousSnake: session.previousSnake, food: session.engine.food, progress: progress,
            time: time, completedMoves: session.engine.steps, reduceMotion: reduceMotion)
    }
}

#if DEBUG
/// Screenshot fixture of the actual renderer, not an artist's approximation.
struct LabReferenceView: View {
    @StateObject private var session = SnakeSession()
    private var form: LabSnakeForm {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--lab-form=") })
            .flatMap { LabSnakeForm(rawValue: String($0.dropFirst("--lab-form=".count))) } ?? .clay
    }
    private var theme: LabTheme {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--lab-theme=") })
            .flatMap { LabTheme(rawValue: String($0.dropFirst("--lab-theme=".count))) } ?? .atelier
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SNAKEFOCUS / MATERIAL STUDY")
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2)
                .foregroundStyle(theme.palette.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(form.code).foregroundStyle(theme.palette.accent)
                Text(form.title)
                Spacer()
                Text(form.is3D ? "3D" : "2D").font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text(form.detail).font(.system(size: 13)).foregroundStyle(theme.palette.secondary)
            Spacer(minLength: 0)
            LabBoardView(session: session, form: form, theme: theme, specimen: true)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer(minLength: 0)
            HStack {
                Text(labText("应用实际渲染 · 材质试样", "Live app renderer · Material specimen"))
                Spacer()
                Text(theme.code)
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.palette.secondary)
        }
        .padding(24)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.palette.ink)
        .background(theme.palette.background.ignoresSafeArea())
        .preferredColorScheme(theme.palette.isDark ? .dark : .light)
    }
}
#endif
