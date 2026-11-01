import SwiftUI
import SceneKit
import UIKit
import simd

/// The experimental materials use real lit geometry. SceneKit renders only
/// when SwiftUI supplies another snapshot; it owns no simulation or timer.
@MainActor
struct LabSnake3DView: UIViewRepresentable {
    let input: LabBoardInput
    let form: LabSnakeForm
    let palette: LabPalette

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.isPlaying = false
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        view.contentScaleFactor = min(2, UIScreen.main.scale)
        view.isOpaque = true
        context.coordinator.update(input: input, form: form, palette: palette, view: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(input: input, form: form, palette: palette, view: uiView)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        uiView.rendersContinuously = false
        uiView.scene = nil
        uiView.pointOfView = nil
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private let floorNode = SCNNode()
        private let gridNode = SCNNode()
        private let wallRoot = SCNNode()
        private let foodNode = SCNNode()
        private var bodyNodes: [SCNNode] = []
        private var contactNodes: [SCNNode] = []
        private var glassRimNodes: [SCNNode] = []
        private var headNodes: [SCNNode] = []
        private var configuration: SnakeConfiguration?
        private var materialKey = ""
        private var frameKey = ""
        private var bodyMaterials: [SCNMaterial] = []
        private var eyeMaterials: [SCNMaterial] = []
        private let contactMaterial = SCNMaterial()
        private let glassRimMaterial = SCNMaterial()
        private var elementCache: [String: [SCNGeometryElement]] = [:]
        private let studio: UIImage

        init() {
            studio = Self.studioEnvironment()
            scene.rootNode.addChildNode(cameraNode)
            scene.rootNode.addChildNode(floorNode)
            scene.rootNode.addChildNode(gridNode)
            scene.rootNode.addChildNode(wallRoot)
            scene.rootNode.addChildNode(foodNode)
            floorNode.renderingOrder = -3
            gridNode.renderingOrder = -2
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            cameraNode.camera?.zNear = 0.1
            cameraNode.camera?.zFar = 150
            cameraNode.camera?.wantsHDR = true
            cameraNode.camera?.wantsExposureAdaptation = false
            scene.lightingEnvironment.contents = studio
            scene.lightingEnvironment.intensity = 1.15

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 1_050
            key.light?.castsShadow = true
            key.light?.shadowMode = .deferred
            key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
            key.light?.shadowSampleCount = 8
            key.light?.shadowRadius = 6
            key.light?.shadowColor = UIColor.black.withAlphaComponent(0.25)
            key.position = SCNVector3(-10, 18, 8)
            key.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.intensity = 420
            fill.light?.color = UIColor(red: 0.74, green: 0.84, blue: 1, alpha: 1)
            fill.position = SCNVector3(12, 8, -8)
            fill.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(fill)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 200
            scene.rootNode.addChildNode(ambient)
        }

        func update(input: LabBoardInput, form: LabSnakeForm, palette: LabPalette, view: SCNView) {
            let colors = [palette.uiBoard, palette.uiAccent, palette.uiAccent2, UIColor(palette.ink)]
            let nextMaterialKey = form.rawValue + colors.map { color in
                (color.cgColor.components ?? []).map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
            }.joined(separator: ";")
            let changedMaterial = materialKey != nextMaterialKey
            if changedMaterial {
                materialKey = nextMaterialKey
                configureMaterials(form: form, palette: palette)
                scene.background.contents = palette.uiBoard
                view.backgroundColor = palette.uiBoard
                cameraNode.camera?.bloomIntensity = form == .hologram ? 0.35 : 0
                cameraNode.camera?.bloomThreshold = 1
            }
            if configuration != input.configuration || changedMaterial {
                configuration = input.configuration
                configureBoard(input.configuration, palette: palette)
                frameKey = ""
            }
            // A stopped TimelineView can still be evaluated by SwiftUI. Avoid
            // rebuilding a mesh when the supplied render snapshot is identical.
            let nextFrameKey = "\(input.completedMoves)-\(input.snake.count)-\(input.progress)-\(Int(input.time * 24))-\(input.snake.first?.x ?? -1)-\(input.snake.first?.y ?? -1)-\(input.food?.x ?? -1)-\(input.food?.y ?? -1)-\(nextMaterialKey)"
            guard frameKey != nextFrameKey else { return }
            frameKey = nextFrameKey
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            updateSnake(input: input, form: form)
            foodNode.isHidden = input.food == nil
            if let food = input.food {
                foodNode.position = SCNVector3(Float(food.x) + 0.5 - Float(input.configuration.columns) / 2,
                                              0.37, Float(food.y) + 0.5 - Float(input.configuration.rows) / 2)
                foodNode.eulerAngles = SCNVector3(0.12, Float(input.time * 0.38), 0.08)
            }
            SCNTransaction.commit()
            // SCNView coalesces changes while rendersContinuously is false.
            view.setNeedsDisplay()
        }

        private func configureMaterials(form: LabSnakeForm, palette: LabPalette) {
            let accent = palette.uiAccent
            let base = SCNMaterial()
            base.lightingModel = .physicallyBased
            base.diffuse.contents = accent
            base.roughness.contents = 0.86
            base.metalness.contents = 0.0
            base.isDoubleSided = true
            switch form {
            case .chrome:
                base.diffuse.contents = Self.mix(accent, .white, 0.72)
                base.metalness.contents = 1.0
                base.roughness.contents = 0.095
                base.reflective.contents = studio
                base.reflective.intensity = 0.9
            case .glass:
                base.diffuse.contents = Self.mix(accent, .white, 0.55)
                base.roughness.contents = 0.035
                base.metalness.contents = 0.0
                base.transparency = 0.105
                base.transparencyMode = .dualLayer
                base.blendMode = .alpha
                base.writesToDepthBuffer = false
                base.reflective.contents = studio
                base.reflective.intensity = 0.16
                base.fresnelExponent = 2.4
            case .pearl:
                base.diffuse.contents = Self.mix(accent, .white, 0.35)
                base.metalness.contents = 0.18
                base.roughness.contents = 0.32
                base.reflective.contents = studio
                base.reflective.intensity = 0.35
            case .hologram:
                base.metalness.contents = 0.55
                base.roughness.contents = 0.16
                base.emission.contents = accent
                base.emission.intensity = 0.35
            default: break
            }
            bodyMaterials = [base]
            if form == .hologram {
                for color in [palette.uiAccent2, Self.mix(accent, .white, 0.65)] {
                    let variant = base.copy() as! SCNMaterial
                    variant.diffuse.contents = color
                    variant.emission.contents = color
                    bodyMaterials.append(variant)
                }
            }
            let white = SCNMaterial()
            white.lightingModel = .physicallyBased
            white.diffuse.contents = UIColor(white: 0.98, alpha: 1)
            white.roughness.contents = 0.28
            let pupil = SCNMaterial()
            pupil.lightingModel = .physicallyBased
            pupil.diffuse.contents = UIColor(red: 0.025, green: 0.045, blue: 0.06, alpha: 1)
            pupil.roughness.contents = 0.1
            eyeMaterials = [white, pupil]
            contactMaterial.lightingModel = .constant
            contactMaterial.diffuse.contents = UIColor.black
            contactMaterial.transparency = form == .glass ? 0.035 : 0.13
            contactMaterial.isDoubleSided = true
            contactMaterial.writesToDepthBuffer = false
            glassRimMaterial.lightingModel = .constant
            glassRimMaterial.diffuse.contents = Self.mix(accent, .white, 0.82)
            glassRimMaterial.transparency = 0.62
            glassRimMaterial.isDoubleSided = true
            glassRimMaterial.writesToDepthBuffer = false
        }

        private func configureBoard(_ configuration: SnakeConfiguration, palette: LabPalette) {
            let columns = Float(configuration.columns), rows = Float(configuration.rows)
            cameraNode.position = SCNVector3(0, 36, 7)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            cameraNode.camera?.orthographicScale = Double(rows) * 0.515
            let floor = SCNBox(width: CGFloat(columns), height: 0.08, length: CGFloat(rows), chamferRadius: 0)
            let floorMaterial = SCNMaterial()
            // The UI palette is a color contract. An unlit board keeps the
            // studio environment from bleaching light themes or nighttime
            // surfaces; snake geometry still receives the full PBR lighting.
            floorMaterial.lightingModel = .constant
            floorMaterial.diffuse.contents = palette.uiBoard
            floorMaterial.roughness.contents = 0.95
            floor.materials = [floorMaterial]
            floorNode.geometry = floor
            floorNode.position.y = -0.06
            floorNode.castsShadow = false
            var grid = Mesh()
            for x in 0...configuration.columns {
                grid.quad(x0: Float(x) - columns / 2 - 0.007, z0: -rows / 2,
                          x1: Float(x) - columns / 2 + 0.007, z1: rows / 2, y: 0)
            }
            for y in 0...configuration.rows {
                grid.quad(x0: -columns / 2, z0: Float(y) - rows / 2 - 0.007,
                          x1: columns / 2, z1: Float(y) - rows / 2 + 0.007, y: 0)
            }
            let gridMaterial = SCNMaterial()
            gridMaterial.lightingModel = .constant
            gridMaterial.diffuse.contents = Self.mix(palette.uiBoard, UIColor(palette.ink), palette.isDark ? 0.10 : 0.07)
            gridNode.geometry = grid.geometry(materials: [gridMaterial])
            gridNode.castsShadow = false
            wallRoot.childNodes.forEach { $0.removeFromParentNode() }
            let wall = SCNBox(width: 0.96, height: 0.38, length: 0.96, chamferRadius: 0.065)
            wall.widthSegmentCount = 1
            wall.heightSegmentCount = 1
            wall.lengthSegmentCount = 1
            let wallMaterial = SCNMaterial()
            wallMaterial.lightingModel = .physicallyBased
            wallMaterial.diffuse.contents = Self.mix(palette.uiAccent, UIColor(palette.ink), 0.35)
            wallMaterial.roughness.contents = 0.72
            wall.materials = [wallMaterial]
            for cell in configuration.walls {
                let node = SCNNode(geometry: wall)
                node.position = SCNVector3(Float(cell.x) + 0.5 - columns / 2, 0.19, Float(cell.y) + 0.5 - rows / 2)
                wallRoot.addChildNode(node)
            }
            let food = SCNBox(width: 0.50, height: 0.56, length: 0.50, chamferRadius: 0.12)
            let foodMaterial = SCNMaterial()
            foodMaterial.lightingModel = .physicallyBased
            foodMaterial.diffuse.contents = palette.uiAccent2
            foodMaterial.roughness.contents = 0.25
            foodMaterial.metalness.contents = 0.15
            food.materials = [foodMaterial]
            foodNode.geometry = food
        }

        private func updateSnake(input: LabBoardInput, form: LabSnakeForm) {
            let bounds = SIMD2<Float>(Float(input.configuration.columns) / 2, Float(input.configuration.rows) / 2)
            // Translated seam ghosts contain the whole strip. Retain only
            // intersecting runs so distant ghost vertices never collapse into
            // an artificial ridge along the edge when clipped.
            var parts: [[LabRenderSample]] = []
            for strip in LabRenderGeometry.wrappedSamples(input: input) {
                var run: [LabRenderSample] = []
                for sample in strip {
                    let r = sample.radius * 1.12
                    let visible = sample.center.x + r >= 0 && sample.center.x - r <= CGFloat(input.configuration.columns)
                        && sample.center.y + r >= 0 && sample.center.y - r <= CGFloat(input.configuration.rows)
                    if visible { run.append(sample) }
                    else if !run.isEmpty { parts.append(run); run = [] }
                }
                if !run.isEmpty { parts.append(run) }
            }
            let sampleCount = max(1, parts.reduce(0) { $0 + $1.count })
            let strideSize = max(1, Int(ceil(Double(sampleCount) / 800)))
            while bodyNodes.count < parts.count {
                let node = SCNNode()
                scene.rootNode.addChildNode(node)
                bodyNodes.append(node)
                let contact = SCNNode()
                contact.castsShadow = false
                contact.renderingOrder = -1
                contact.scale.y = 0.001
                contact.position.y = 0.008
                scene.rootNode.addChildNode(contact)
                contactNodes.append(contact)
                let rim = SCNNode()
                rim.castsShadow = false
                rim.renderingOrder = 3
                scene.rootNode.addChildNode(rim)
                glassRimNodes.append(rim)
            }
            for (index, node) in bodyNodes.enumerated() {
                guard index < parts.count, parts[index].count > 1 else {
                    node.isHidden = true
                    contactNodes[index].isHidden = true
                    glassRimNodes[index].isHidden = true
                    continue
                }
                node.isHidden = false
                let source = parts[index]
                var samples = stride(from: 0, to: source.count, by: strideSize).map { source[$0] }
                if samples.last?.position != source.last?.position, let last = source.last { samples.append(last) }
                let sides = form == .hologram ? 8 : 12
                var mesh = Mesh()
                for (ring, sample) in samples.enumerated() {
                    let before = samples[max(0, ring - 1)].center
                    let after = samples[min(samples.count - 1, ring + 1)].center
                    var tangent = SIMD2<Float>(Float(after.x - before.x), Float(after.y - before.y))
                    tangent = simd_length_squared(tangent) > 0.00001 ? simd_normalize(tangent) : SIMD2(1, 0)
                    let side = SIMD3<Float>(-tangent.y, 0, tangent.x)
                    var radius = max(0.025, Float(sample.radius))
                    if form == .pearl {
                        // The silhouette itself has round beads and narrow necks.
                        radius *= 0.45 + 0.62 * pow(abs(cos(Float(sample.position) * .pi / 0.72)), 0.65)
                    }
                    let center = SIMD3<Float>(Float(sample.center.x) - bounds.x, radius * 0.86 + 0.075,
                                              Float(sample.center.y) - bounds.y)
                    for sideIndex in 0..<sides {
                        let angle = Float(sideIndex) * 2 * .pi / Float(sides)
                        let normal = side * cos(angle) + SIMD3<Float>(0, sin(angle), 0)
                        let crystal = form == .hologram && sideIndex.isMultiple(of: 2) ? Float(1.1) : 1
                        var point = center + normal * radius * crystal
                        point.y = center.y + normal.y * radius * (form == .clay ? 0.84 : 1)
                        point.x = min(bounds.x, max(-bounds.x, point.x))
                        point.z = min(bounds.y, max(-bounds.y, point.z))
                        mesh.vertex(point, normal: normal)
                    }
                }
                let topologyKey = "\(samples.count)-\(sides)-\(bodyMaterials.count)"
                if elementCache[topologyKey] == nil {
                    var groups = Array(repeating: [UInt32](), count: bodyMaterials.count)
                    for ring in 0..<(samples.count - 1) { for side in 0..<sides {
                        let a = UInt32(ring * sides + side), b = UInt32(ring * sides + (side + 1) % sides)
                        let c = a + UInt32(sides), d = b + UInt32(sides)
                        let group = (side + ring / 3) % bodyMaterials.count
                        groups[group].append(contentsOf: [a, c, b, b, c, d])
                    } }
                    elementCache[topologyKey] = groups.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
                }
                node.geometry = mesh.geometry(materials: bodyMaterials, elements: elementCache[topologyKey])
                node.castsShadow = form != .glass
                // A transparent projection of this same mesh gives a stable
                // contact shadow even on an unlit palette-matched board.
                let contactGeometry = node.geometry?.copy() as? SCNGeometry
                contactGeometry?.materials = [contactMaterial]
                contactNodes[index].geometry = contactGeometry
                contactNodes[index].isHidden = false
                glassRimNodes[index].isHidden = form != .glass
                if form == .glass {
                    glassRimNodes[index].geometry = glassRims(samples: samples, bounds: bounds)
                }
            }
            // Keep bounded topology storage even across maps and snake lengths.
            if elementCache.count > 48 { elementCache.removeAll(keepingCapacity: true) }
            updateHead(input: input, form: form, bounds: bounds)
        }

        private func glassRims(samples: [LabRenderSample], bounds: SIMD2<Float>) -> SCNGeometry {
            // Fine physical highlight rails leave the middle of the glass
            // shell clear enough to see the board grid through the body.
            var mesh = Mesh()
            let sides = 6
            for sign: Float in [-1, 1] {
                let first = UInt32(mesh.count)
                for (ring, sample) in samples.enumerated() {
                    let before = samples[max(0, ring - 1)].center
                    let after = samples[min(samples.count - 1, ring + 1)].center
                    var tangent = SIMD2<Float>(Float(after.x - before.x), Float(after.y - before.y))
                    tangent = simd_length_squared(tangent) > 0.00001 ? simd_normalize(tangent) : SIMD2(1, 0)
                    let side = SIMD3<Float>(-tangent.y, 0, tangent.x)
                    let radius = max(0.025, Float(sample.radius))
                    let center = SIMD3<Float>(Float(sample.center.x) - bounds.x, radius * 1.38 + 0.075,
                                              Float(sample.center.y) - bounds.y) + side * radius * sign * 0.82
                    for facet in 0..<sides {
                        let angle = Float(facet) * 2 * .pi / Float(sides)
                        let normal = side * cos(angle) + SIMD3<Float>(0, sin(angle), 0)
                        var point = center + normal * min(0.024, radius * 0.11)
                        point.x = min(bounds.x, max(-bounds.x, point.x))
                        point.z = min(bounds.y, max(-bounds.y, point.z))
                        mesh.vertex(point, normal: normal)
                    }
                }
                for ring in 0..<(samples.count - 1) { for facet in 0..<sides {
                    let a = first + UInt32(ring * sides + facet)
                    let b = first + UInt32(ring * sides + (facet + 1) % sides)
                    let c = a + UInt32(sides), d = b + UInt32(sides)
                    mesh.groups[0].append(contentsOf: [a, c, b, b, c, d])
                } }
            }
            return mesh.geometry(materials: [glassRimMaterial])
        }

        private func updateHead(input: LabBoardInput, form: LabSnakeForm, bounds: SIMD2<Float>) {
            guard !input.snake.isEmpty else { headNodes.forEach { $0.isHidden = true }; return }
            let head = LabRenderGeometry.head(input: input)
            let direction = LabRenderGeometry.headDirection(input: input)
            let heading = atan2(Float(direction.x), Float(direction.y))
            let headRadius = max(0.32, min(0.47, Float(input.frame.samples.first?.radius ?? 0.4) * 1.12))
            let xOffsets: [Float] = input.configuration.wrapsHorizontally ? [-bounds.x * 2, 0, bounds.x * 2] : [0]
            let zOffsets: [Float] = input.configuration.wrapsVertically ? [-bounds.y * 2, 0, bounds.y * 2] : [0]
            var centers: [SIMD3<Float>] = []
            for dx in xOffsets { for dz in zOffsets {
                let center = SIMD3<Float>(Float(head.x) - bounds.x + dx, headRadius * 0.86 + 0.075, Float(head.y) - bounds.y + dz)
                if abs(center.x) <= bounds.x + headRadius && abs(center.z) <= bounds.y + headRadius { centers.append(center) }
            } }
            while headNodes.count < centers.count {
                let node = SCNNode()
                node.renderingOrder = 2
                scene.rootNode.addChildNode(node)
                headNodes.append(node)
            }
            for (index, node) in headNodes.enumerated() {
                guard index < centers.count else { node.isHidden = true; continue }
                node.isHidden = false
                let center = centers[index]
                let forward = SIMD3<Float>(sin(heading), 0, cos(heading))
                let side = SIMD3<Float>(cos(heading), 0, -sin(heading))
                var mesh = Mesh(groupCount: 3)
                let main = bodyMaterials[0]
                mesh.ellipsoid(center: center, radii: SIMD3(headRadius * 1.08, headRadius * 0.89, headRadius * 1.12),
                               heading: heading, bounds: bounds, sides: form == .hologram ? 8 : 20, group: 0)
                for sign: Float in [-1, 1] {
                    let eyeCenter = center + side * sign * headRadius * 0.47 + forward * headRadius * 0.39
                        + SIMD3<Float>(0, headRadius * 0.73, 0)
                    mesh.ellipsoid(center: eyeCenter, radii: SIMD3(repeating: headRadius * 0.25), heading: heading, bounds: bounds, sides: 10, group: 1)
                    let pupilCenter = eyeCenter + forward * headRadius * 0.075 + SIMD3<Float>(0, headRadius * 0.17, 0)
                    mesh.ellipsoid(center: pupilCenter, radii: SIMD3(repeating: headRadius * 0.135), heading: heading, bounds: bounds, sides: 10, group: 2)
                }
                node.geometry = mesh.geometry(materials: [main] + eyeMaterials)
            }
        }

        private static func mix(_ a: UIColor, _ b: UIColor, _ ratio: CGFloat) -> UIColor {
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
            b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            return UIColor(red: ar * (1 - ratio) + br * ratio, green: ag * (1 - ratio) + bg * ratio,
                           blue: ab * (1 - ratio) + bb * ratio, alpha: 1)
        }

        /// A local equirectangular studio: bright softboxes, dark gaps and a
        /// cool horizon give metal real reflections without downloaded assets.
        private static func studioEnvironment() -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { context in
                let cg = context.cgContext
                let colors = [UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1).cgColor,
                              UIColor(red: 0.38, green: 0.48, blue: 0.57, alpha: 1).cgColor,
                              UIColor(red: 0.82, green: 0.87, blue: 0.91, alpha: 1).cgColor,
                              UIColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.52, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
                }
                UIColor(white: 1, alpha: 0.98).setFill()
                UIBezierPath(roundedRect: CGRect(x: 110, y: 58, width: 125, height: 330), cornerRadius: 24).fill()
                UIColor(red: 0.79, green: 0.9, blue: 1, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 660, y: 100, width: 60, height: 265), cornerRadius: 14).fill()
                UIColor(white: 0.025, alpha: 1).setFill()
                cg.fill(CGRect(x: 390, y: 0, width: 90, height: 512))
            }
        }
    }
}

/// Interleaved positions/normals keep the dynamic tube to one small vertex
/// buffer per seam. Geometry elements are cached by the coordinator.
private struct Mesh {
    var floats: [Float] = []
    var groups: [[UInt32]]
    var count: Int { floats.count / 6 }

    init(groupCount: Int = 1) { groups = Array(repeating: [], count: groupCount) }

    mutating func vertex(_ point: SIMD3<Float>, normal: SIMD3<Float>) {
        floats.append(contentsOf: [point.x, point.y, point.z, normal.x, normal.y, normal.z])
    }

    mutating func quad(x0: Float, z0: Float, x1: Float, z1: Float, y: Float) {
        let first = UInt32(count)
        for point in [SIMD3(x0, y, z0), SIMD3(x0, y, z1), SIMD3(x1, y, z0), SIMD3(x1, y, z1)] {
            vertex(point, normal: SIMD3(0, 1, 0))
        }
        groups[0].append(contentsOf: [first, first + 1, first + 2, first + 2, first + 1, first + 3])
    }

    mutating func ellipsoid(center: SIMD3<Float>, radii: SIMD3<Float>, heading: Float,
                            bounds: SIMD2<Float>, sides: Int, group: Int) {
        let first = UInt32(count), stacks = 8
        let c = cos(heading), s = sin(heading)
        for stack in 0...stacks {
            let latitude = Float(stack) / Float(stacks) * .pi
            for side in 0..<sides {
                let longitude = Float(side) / Float(sides) * 2 * .pi
                let localNormal = SIMD3<Float>(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
                let local = localNormal * radii
                var point = center + SIMD3(c * local.x + s * local.z, local.y, -s * local.x + c * local.z)
                point.x = min(bounds.x, max(-bounds.x, point.x))
                point.z = min(bounds.y, max(-bounds.y, point.z))
                let n = simd_normalize(localNormal / radii)
                vertex(point, normal: SIMD3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z))
            }
        }
        for stack in 0..<stacks { for side in 0..<sides {
            let a = first + UInt32(stack * sides + side)
            let b = first + UInt32(stack * sides + (side + 1) % sides)
            let c = a + UInt32(sides), d = b + UInt32(sides)
            groups[group].append(contentsOf: [a, b, c, b, d, c])
        } }
    }

    func geometry(materials: [SCNMaterial], elements: [SCNGeometryElement]? = nil) -> SCNGeometry {
        let data = floats.withUnsafeBytes { Data($0) }
        let vertices = SCNGeometrySource(data: data, semantic: .vertex, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 24)
        let normals = SCNGeometrySource(data: data, semantic: .normal, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 12, dataStride: 24)
        let result = SCNGeometry(sources: [vertices, normals], elements: elements ?? groups.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        result.materials = materials
        return result
    }
}
