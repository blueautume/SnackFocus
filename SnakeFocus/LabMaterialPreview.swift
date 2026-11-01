import SwiftUI
import SceneKit
import Metal

/// Only the current pairing animates. Candidate rows share cached snapshots
/// from the real renderer instead of owning a GPU scene and clock per row.
@MainActor
struct LabMaterialPreview: View {
    let form: LabSnakeForm
    let theme: LabTheme
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: UIImage?
    @State private var beganAt = ContinuousClock.now

    private var key: String { "motion-v2/\(form.rawValue)/\(theme.rawValue)" }

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: scenePhase != .active)) { _ in
                    let elapsed = beganAt.duration(to: .now).components
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    nativeContent(LabBoardInput.movingThumbnail(distance: seconds * 2))
                }
            } else if let snapshot {
                Image(uiImage: snapshot).resizable().interpolation(.high)
            } else {
                theme.palette.board
                    .overlay { ProgressView().tint(theme.palette.accent) }
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .background(theme.palette.board)
        .clipped()
        .task(id: key) {
            if !animated || reduceMotion {
                snapshot = LabPreviewSnapshots.cache.object(forKey: key as NSString)
                if snapshot == nil {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    snapshot = LabPreviewSnapshots.make(form: form, theme: theme, key: key)
                }
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { snapshot = LabPreviewSnapshots.make(form: form, theme: theme, key: key) }
        }
    }

    @ViewBuilder private func nativeContent(_ input: LabBoardInput) -> some View {
        if form.is3D {
            LabSnake3DView(input: input, form: form, palette: theme.palette)
        } else {
            LabSnakeCanvas(input: input, form: form, palette: theme.palette)
        }
    }
}

@MainActor private enum LabPreviewSnapshots {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    static func make(form: LabSnakeForm, theme: LabTheme, key: String) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let size = CGSize(width: 360, height: 180)
        let image: UIImage? = autoreleasepool {
            if form.is3D {
                let coordinator = LabSnake3DView.Coordinator()
                let view = SCNView(frame: CGRect(origin: .zero, size: size))
                coordinator.update(input: .thumbnail, form: form, palette: theme.palette, view: view)
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = coordinator.scene
                renderer.pointOfView = coordinator.cameraNode
                renderer.autoenablesDefaultLighting = false
                return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            } else {
                let renderer = ImageRenderer(content: LabSnakeCanvas(input: .thumbnail, form: form,
                    palette: theme.palette).frame(width: size.width, height: size.height))
                renderer.scale = 1
                return renderer.uiImage
            }
        }
        if let image { cache.setObject(image, forKey: key as NSString, cost: 360 * 180 * 4) }
        return image
    }
}
