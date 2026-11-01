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
        print("PASS design lab: specimen topology, wrap separation, finite tapered geometry and \(snapshots) real game snapshots across all six maps")
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
