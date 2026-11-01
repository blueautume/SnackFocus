import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main enum LabRenderChecks {
    static func main() {
        let specimen = LabBoardInput.specimen
        require(specimen.snake.count > 30, "Material specimen needs a legible silhouette")
        require(Set(specimen.snake).count == specimen.snake.count, "Specimen overlaps itself")
        for (a, b) in zip(specimen.snake, specimen.snake.dropFirst()) {
            require(specimen.configuration.areNeighbors(a, b), "Specimen must be a continuous snake")
        }
        verify(specimen)
        checkMaterialAdvection()

        // Both boundaries are crossed in the underlying cell sequence. The
        // visible strips must never form a diagonal across the board.
        let seamCells = [GridCell(x: 0, y: 0), GridCell(x: 15, y: 0), GridCell(x: 15, y: 23), GridCell(x: 14, y: 23)]
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let seam = LabBoardInput(configuration: .firstMap, snake: seamCells,
                previousSnake: seamCells, food: nil, progress: progress, time: 1.3, completedMoves: 8)
            verify(seam)
            require(LabRenderGeometry.wrappedSamples(input: seam).count > 1, "Wrap crossings must split strips")
        }

        // Exercise actual evolving production states, including long snakes,
        // walls, wrapping maps and narrow channels. Render calls are read-only.
        var snapshots = 0
        for map in SnakeMap.allCases {
            var engine = SnakeEngine(configuration: map.configuration, seed: 42)
            let limit = engine.configuration.cellCount * engine.configuration.cellCount + 384
            while engine.phase == .playing && engine.steps < limit {
                let previous = engine.snake
                engine.step()
                if engine.steps % 257 == 0 || engine.phase != .playing {
                    let before = engine.snake
                    let input = LabBoardInput(configuration: engine.configuration, snake: engine.snake,
                        previousSnake: previous, food: engine.food, progress: 0.6,
                        time: Double(engine.steps) / 6, completedMoves: engine.steps)
                    verify(input)
                    require(engine.snake == before, "Rendering changed the simulation")
                    snapshots += 1
                }
            }
            require(engine.phase == .filled, "Production sample must reach its normal completed state")
        }
        print("PASS design lab: material advection at head speed on both sides of each wrap, phase continuity, frozen/reduced motion, specimen topology and \(snapshots) real snapshots across six maps")
    }

    private static func checkMaterialAdvection() {
        for vertical in [false, true] {
            // A straight body crosses a seam; some material markers are before
            // it and others are on the far side. Horizontal uses a walled map.
            let configuration = vertical ? SnakeConfiguration.firstMap : SnakeMap.doubleBars.configuration
            let extent = vertical ? configuration.rows : configuration.columns
            func cells(_ head: Int) -> [GridCell] {
                (0..<12).map { index in
                    let coordinate = ((head - index) % extent + extent) % extent
                    return vertical ? GridCell(x: 8, y: coordinate) : GridCell(x: coordinate, y: 8)
                }
            }
            func input(_ progress: Double, head: Int = 3, time: Double = 0, reduced: Bool = false) -> LabBoardInput {
                LabBoardInput(configuration: configuration, snake: cells(head), previousSnake: cells(head - 1),
                    food: nil, progress: progress, time: time, completedMoves: head + 40, reduceMotion: reduced)
            }
            func marks(_ frame: LabBoardInput) -> [LabMaterialMark] {
                LabRenderGeometry.materialMarks(input: frame, spacing: 0.8).filter {
                    $0.center.x >= 0 && $0.center.x < CGFloat(configuration.columns)
                    && $0.center.y >= 0 && $0.center.y < CGFloat(configuration.rows)
                }
            }
            let a = input(0.2), b = input(0.6)
            let before = marks(a), after = marks(b)
            require(before.count > 8 && before.count == after.count, "Missing material on a wrapped body")
            for (old, new) in zip(before, after) {
                require(abs(old.position - new.position) < 1e-8, "Material identity changed at a wrap")
                let raw = vertical ? new.center.y - old.center.y : new.center.x - old.center.x
                let delta = raw - (raw / CGFloat(extent)).rounded() * CGFloat(extent)
                require(abs(delta - 0.4) < 1e-6, "A material marker stopped or moved at a different speed from the head")
                let normalDelta = vertical ? new.center.x - old.center.x : new.center.y - old.center.y
                require(abs(normalDelta) < 1e-6, "Middle wave remains pinned to the world")
            }
            let headA = LabRenderGeometry.head(input: a), headB = LabRenderGeometry.head(input: b)
            require(abs((vertical ? headB.y-headA.y : headB.x-headA.x)-0.4) < 1e-6, "Invalid head speed fixture")

            // End of one tick equals the beginning of the next, without a
            // texture reset caused by completedMoves or a new seam split.
            for (old, new) in zip(marks(input(1)), marks(input(0, head: 4))) {
                require(hypot(old.center.x-new.center.x, old.center.y-new.center.y) < 1e-6,
                        "Material jumps at a logical move boundary")
            }
            let frozen = marks(input(0.4, time: 5)), later = marks(input(0.4, time: 500))
            require(zip(frozen, later).allSatisfy { $0.center.x == $1.center.x && $0.center.y == $1.center.y }, "Material uses a second wall clock")
            let reducedA = marks(input(0.1, reduced: true)), reducedB = marks(input(0.8, reduced: true))
            require(zip(reducedA, reducedB).allSatisfy { $0.center.x == $1.center.x && $0.center.y == $1.center.y }, "Reduced Motion still interpolates")
        }
        require(LabRenderGeometry.materialMarks(input: .specimen, spacing: 0).isEmpty, "Invalid spacing must be rejected")
        require(LabRenderGeometry.materialMarks(input: .specimen, spacing: .infinity).isEmpty, "Invalid spacing must be rejected")
        for distance in [0.0, 0.3, 23.9, 24, 24.1, 1000.2] {
            verify(.movingThumbnail(distance: distance))
        }
    }

    private static func verify(_ input: LabBoardInput) {
        let parts = LabRenderGeometry.wrappedSamples(input: input)
        require(!parts.isEmpty, "Expected visible geometry")
        for part in parts {
            for sample in part {
                require(sample.center.x.isFinite && sample.center.y.isFinite && sample.radius.isFinite,
                        "Geometry contains non-finite coordinates")
                require(sample.radius >= 0 && sample.radius <= 1, "Invalid body radius")
            }
            for (a, b) in zip(part, part.dropFirst()) {
                require(hypot(a.center.x - b.center.x, a.center.y - b.center.y) < 1,
                        "Visible strip bridges a board wrap")
                require(b.position >= a.position, "Material positions must run from head to tail")
            }
        }
        let head = LabRenderGeometry.head(input: input)
        require(head.x.isFinite && head.y.isFinite, "Invalid head")
    }
}
