import Foundation

@inline(__always)
private func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !condition() { fatalError(message()) }
}

private let map = SnakeConfiguration.firstMap

private func close(_ a: Double, _ b: Double, tolerance: Double = 0.000_001) -> Bool {
    abs(a - b) < tolerance
}

private func modulo(_ value: Double, period: Int) -> Double {
    let result = value.truncatingRemainder(dividingBy: Double(period))
    return result < 0 ? result + Double(period) : result
}

private func distance(_ a: SnakeVisualPoint, _ b: SnakeVisualPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

private func frame(_ snake: [GridCell], previous: [GridCell]? = nil, progress: Double = 1,
                   time: Double = 0, food: GridCell? = nil, reduced: Bool = false,
                   completedMoves: Int? = nil, appearance: SnakeAppearance = .classic) -> SnakeVisualFrame {
    let prior = previous ?? snake
    return SnakeVisualGeometry.frame(configuration: map, snake: snake, previousSnake: prior,
                                     food: food, progress: progress, time: time,
                                     completedMoves: completedMoves ?? (prior == snake ? 0 : 1), appearance: appearance, reduceMotion: reduced)
}

private func checkFiniteAndLocal(_ result: SnakeVisualFrame, configuration: SnakeConfiguration = map) {
    expect(result.columns == configuration.columns * SnakeVisualGeometry.pixelsPerCell, "Wrong raster width")
    expect(result.rows == configuration.rows * SnakeVisualGeometry.pixelsPerCell, "Wrong raster height")
    expect(result.dots.count == result.columns * result.rows && result.bodyMask.count == result.dots.count, "Incomplete raster or body mask")
    expect(result.headCenter.x.isFinite && result.headCenter.y.isFinite && close(result.headHeading.length, 1), "Invalid presented head")
    expect(result.motionDistance.isFinite && result.motionDistance >= 0, "Invalid motion distance")
    expect(result.dots.allSatisfy { $0 <= 2 }, "Unknown raster value")
    expect(result.heading.x.isFinite && result.heading.y.isFinite, "Nonfinite heading")
    expect(close(result.heading.length, 1), "Heading is not a direction")
    for point in result.centers {
        expect(point.x.isFinite && point.y.isFinite, "Nonfinite body anchor")
    }
    for pair in zip(result.centers, result.centers.dropFirst()) {
        expect(distance(pair.0, pair.1) <= 1.000_001, "Body anchor bridges across the board")
    }
    for sample in result.samples {
        expect(sample.center.x.isFinite && sample.center.y.isFinite, "Nonfinite curve sample")
        expect(sample.radius.isFinite && sample.radius > 0, "Invalid body radius")
        expect(sample.bodyPosition.isFinite, "Nonfinite body position")
    }
    for pair in zip(result.samples, result.samples.dropFirst()) {
        expect(distance(pair.0.center, pair.1.center) < 1, "Curve has a screen-spanning bridge")
        expect(pair.0.bodyPosition <= pair.1.bodyPosition, "Curve reverses body order")
    }
}

private func checkEndpointsAndGrowth() {
    let before = [GridCell(x: 5, y: 5), GridCell(x: 4, y: 5), GridCell(x: 3, y: 5), GridCell(x: 2, y: 5)]
    let moving = [GridCell(x: 6, y: 5)] + before.dropLast()
    let growing = [GridCell(x: 6, y: 5)] + before
    for snake in [moving, growing] {
        for progress in [0.0, 0.125, 0.5, 0.875, 1.0] {
            let result = frame(snake, previous: before, progress: progress, time: 0.37)
            checkFiniteAndLocal(result)
            expect(result.centers.count == snake.count, "Growth lost an anchor")
            expect(close(result.centers[0].x, 5.5 + progress), "Head interpolation is not one cell")
            expect(close(result.centers[0].y, 5.5), "Head drifts across its lane")
            if snake.count > before.count {
                expect(close(result.centers.last!.x, 2.5), "Growth moves the old tail")
            }
        }
        for (progress, expected) in [(0.0, before + (snake.count > before.count ? [before.last!] : [])), (1.0, snake)] {
            let result = frame(snake, previous: before, progress: progress)
            for (point, cell) in zip(result.centers, expected) {
                expect(close(modulo(point.x, period: map.columns), Double(cell.x) + 0.5), "Wrong endpoint x")
                expect(close(modulo(point.y, period: map.rows), Double(cell.y) + 0.5), "Wrong endpoint y")
            }
        }
        expect(frame(snake, previous: before, progress: -1).centers == frame(snake, previous: before, progress: 0).centers,
               "Negative progress is not clamped")
        expect(frame(snake, previous: before, progress: 2).centers == frame(snake, previous: before, progress: 1).centers,
               "Excess progress is not clamped")
    }
    checkFiniteAndLocal(frame([]))
    checkFiniteAndLocal(frame([GridCell(x: 1, y: 1)]))
    checkFiniteAndLocal(frame(Array(before.prefix(2))))
}

private func checkWrapAndCorners() {
    let before = [GridCell(x: 15, y: 8), GridCell(x: 14, y: 8), GridCell(x: 13, y: 8)]
    let after = [GridCell(x: 0, y: 8), GridCell(x: 15, y: 8), GridCell(x: 14, y: 8)]
    let middle = frame(after, previous: before, progress: 0.5, time: 0.2)
    checkFiniteAndLocal(middle)
    expect(close(middle.centers[0].x, 16) && close(middle.centers[0].y, 8.5), "Horizontal wrap crosses the board interior")
    expect(close(middle.heading.x, 1) && close(middle.heading.y, 0), "Head faces backward at a seam")
    let density = SnakeVisualGeometry.pixelsPerCell
    for index in middle.dots.indices where middle.dots[index] == 1 {
        let cellX = index % middle.columns / density
        expect(cellX <= 1 || cellX >= 12, "Wrap raster draws a bridge through middle columns")
    }

    let cornerBefore = [GridCell(x: 15, y: 0), GridCell(x: 15, y: 23), GridCell(x: 15, y: 22), GridCell(x: 14, y: 22)]
    let cornerAfter = [GridCell(x: 0, y: 0)] + cornerBefore.dropLast()
    for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
        let result = frame(cornerAfter, previous: cornerBefore, progress: progress, time: 0.43)
        checkFiniteAndLocal(result)
        expect(result.heading.x >= -0.000_001 && result.heading.y >= -0.000_001, "Corner heading takes the long rotation")
    }
    let start = frame(cornerAfter, previous: cornerBefore, progress: 0)
    let end = frame(cornerAfter, previous: cornerBefore, progress: 1)
    expect(close(start.heading.x, 0) && close(start.heading.y, 1), "Wrong initial corner heading")
    expect(close(end.heading.x, 1) && close(end.heading.y, 0), "Wrong final corner heading")
}

private func rowSpan(in cell: GridCell, raster: SnakeVisualFrame) -> Int {
    let density = SnakeVisualGeometry.pixelsPerCell
    var occupiedRows: [Int] = []
    for y in 0..<density {
        if (0..<density).contains(where: { x in raster.dots[(cell.y * density + y) * raster.columns + cell.x * density + x] == 1 }) {
            occupiedRows.append(y)
        }
    }
    return occupiedRows.isEmpty ? 0 : occupiedRows.last! - occupiedRows.first! + 1
}

private func enclosedEyePixels(in cell: GridCell, raster: SnakeVisualFrame) -> Int {
    let density = SnakeVisualGeometry.pixelsPerCell
    var seen = Set<Int>()
    var enclosed = 0
    func isEmpty(_ x: Int, _ y: Int) -> Bool {
        raster.dots[(cell.y * density + y) * raster.columns + cell.x * density + x] == 0
    }
    for y in 0..<density {
        for x in 0..<density where isEmpty(x, y) && !seen.contains(y * density + x) {
            var stack = [(x, y)]
            var reachesBorder = false
            while let (px, py) = stack.popLast() {
                guard !seen.contains(py * density + px) else { continue }
                seen.insert(py * density + px)
                reachesBorder = reachesBorder || px == 0 || py == 0 || px == density - 1 || py == density - 1
                for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                    if (0..<density).contains(nx) && (0..<density).contains(ny) && isEmpty(nx, ny) && !seen.contains(ny * density + nx) {
                        stack.append((nx, ny))
                    }
                }
            }
            if !reachesBorder { enclosed += 1 }
        }
    }
    return enclosed
}

private func sameSamples(_ a: SnakeVisualFrame, _ b: SnakeVisualFrame) -> Bool {
    a.samples.count == b.samples.count && zip(a.samples, b.samples).allSatisfy {
        $0.center == $1.center && close($0.radius, $1.radius) && close($0.bodyPosition, $1.bodyPosition)
    }
}

private func sameScales(_ a: SnakeVisualFrame, _ b: SnakeVisualFrame) -> Bool {
    a.scales.count == b.scales.count && zip(a.scales, b.scales).allSatisfy {
        $0.center == $1.center && close($0.bodyPosition, $1.bodyPosition)
    }
}

private func checkAnatomyAndMotionClock() {
    let snake = (0..<10).map { GridCell(x: 12 - $0, y: 8) }
    let still = frame(snake, reduced: true)
    // Compare an actual cross-section at a wave crest, not the entire cell's
    // wave envelope, which can span more rows than the wider head itself.
    let crest = still.samples.min { abs($0.bodyPosition - 2.5) < abs($1.bodyPosition - 2.5) }!
    let density = SnakeVisualGeometry.pixelsPerCell
    let column = Int(floor(crest.center.x * Double(density)))
    let rows = (0..<still.rows).filter { still.dots[$0 * still.columns + column] == 1 }
    let bodyWidth = rows.last! - rows.first! + 1
    expect(rowSpan(in: snake[0], raster: still) > bodyWidth, "Head is not broader than the local body cross-section")
    expect(rowSpan(in: snake.last!, raster: still) < bodyWidth, "Tail is not visibly thinner")
    expect(enclosedEyePixels(in: snake[0], raster: still) >= 2, "Head has no distinct pair of eyes")
    expect(still.samples.last!.radius < still.samples.first!.radius * 0.4, "Tail does not taper to a point")
    let tailSamples = still.samples.filter { $0.bodyPosition >= 5 }
    for pair in zip(tailSamples, tailSamples.dropFirst()) {
        expect(pair.1.radius <= pair.0.radius + 0.000_001, "Tail widens toward its tip")
    }
    let first = frame(snake, time: 0.1, completedMoves: 7)
    let later = frame(snake, time: 90, completedMoves: 7)
    expect(first.dots == later.dots && first.bodyMask == later.bodyMask && first.centers == later.centers
           && first.headCenter == later.headCenter && first.headHeading == later.headHeading
           && sameSamples(first, later) && sameScales(first, later), "Paused distance still runs a time-based snake animation")
    expect(close(first.motionDistance, 7), "Static previous=current loses completed motion distance")
    let reducedLater = frame(snake, progress: 0.25, time: 10, reduced: true)
    expect(still.dots == reducedLater.dots && sameSamples(still, reducedLater), "Reduced Motion retains a running animation")
}

private struct MotionFixture {
    let name: String
    let route: [GridCell]
    let headIndex: Int
    let length: Int
    let x: Range<Int>
    let y: Range<Int>

    func body(at head: Int) -> [GridCell] {
        stride(from: head, through: head - length + 1, by: -1).map { route[$0] }
    }

    func render(_ travel: Double, speed: Double = 10, time: Double? = nil) -> SnakeVisualFrame {
        let tick = Int(floor(travel)) + 1
        return frame(body(at: headIndex + tick), previous: body(at: headIndex + tick - 1),
                     progress: travel - floor(travel), time: time ?? travel / speed, completedMoves: tick)
    }

    func region(in raster: SnakeVisualFrame) -> [Int] {
        y.flatMap { row in x.map { row * raster.columns + $0 } }
    }
}

private func sampleCenter(in raster: SnakeVisualFrame, at position: Double) -> SnakeVisualPoint? {
    for (a, b) in zip(raster.samples, raster.samples.dropFirst()) where a.bodyPosition <= position && position <= b.bodyPosition {
        let length = b.bodyPosition - a.bodyPosition
        let fraction = length > 0 ? (position - a.bodyPosition) / length : 0
        return a.center * (1 - fraction) + b.center * fraction
    }
    return nil
}

private func checkStationaryWaveAndMaterialMotion() {
    let density = SnakeVisualGeometry.pixelsPerCell
    let straight = MotionFixture(name: "straight", route: (0...15).map { GridCell(x: $0, y: 5) },
                                 headIndex: 11, length: 12, x: (9*density)..<(10*density), y: (4*density)..<(7*density))
    let route = (3...13).reversed().map { GridCell(x: $0, y: 16) }
        + (10...15).reversed().map { GridCell(x: 3, y: $0) }
        + (4...13).map { GridCell(x: $0, y: 10) }
    let corner = MotionFixture(name: "middle U-turn", route: route, headIndex: 22, length: 22,
                               x: (2*density)..<(5*density), y: (10*density)..<(15*density))
    let travels = [0.0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    for fixture in [straight, corner] {
        let frames = travels.map { fixture.render($0) }
        let first = frames[0]
        let region = fixture.region(in: first)
        expect(region.contains { first.bodyMask[$0] } && region.contains { !first.bodyMask[$0] }, "Stationary ROI must include outline and background")
        var changedTexture = false
        for (travel, result) in zip(travels, frames) {
            checkFiniteAndLocal(result)
            expect(close(result.motionDistance, travel), "\(fixture.name): motion distance doesn't follow actual steps/progress")
            expect(region.allSatisfy { first.bodyMask[$0] == result.bodyMask[$0] }, "\(fixture.name): middle wave outline drifts while the snake advances")
            changedTexture = changedTexture || region.contains { first.dots[$0] != result.dots[$0] }
            for scale in result.scales {
                guard let attached = sampleCenter(in: result, at: scale.bodyPosition) else { fatalError("Scale outside visible wave samples") }
                expect(distance(attached, scale.center) < 0.012, "\(fixture.name): material scale detaches from the wave")
                let x = Int(floor(scale.center.x * Double(density)))
                let y = Int(floor(scale.center.y * Double(density)))
                let index = ((y % result.rows + result.rows) % result.rows) * result.columns + (x % result.columns + result.columns) % result.columns
                expect(result.bodyMask[index] && result.dots[index] == 0, "Scale metadata doesn't identify an actual interior cutout")
            }
            let late = fixture.render(travel, time: 123)
            expect(result.dots == late.dots && result.bodyMask == late.bodyMask && sameSamples(result, late)
                   && sameScales(result, late) && result.headCenter == late.headCenter && result.headHeading == late.headHeading,
                   "\(fixture.name): time adds extra outline or material motion")
        }
        expect(changedTexture, "\(fixture.name): fixed middle contour has no passing material texture")
        for speed in [4.0, 6.0, 10.0, 16.0] {
            let result = fixture.render(1.375, speed: speed)
            let baseline = fixture.render(1.375)
            expect(result.dots == baseline.dots && sameSamples(result, baseline) && sameScales(result, baseline), "Speed changes geometry at the same traveled distance")
        }
        // A completed tick, its static snapshot, and the next tick at p=0 all
        // share one middle world wave. Endpoint corrections are intentionally
        // excluded from this ROI; they adapt only the head and tail locally.
        let current = fixture.body(at: fixture.headIndex + 1)
        let previous = fixture.body(at: fixture.headIndex)
        let next = fixture.body(at: fixture.headIndex + 2)
        let end = frame(current, previous: previous, progress: 1, completedMoves: 1)
        let snapshot = frame(current, completedMoves: 1)
        let begin = frame(next, previous: current, progress: 0, completedMoves: 2)
        for result in [end, snapshot, begin] {
            expect(close(result.motionDistance, 1), "Tick boundary changes motion distance")
            expect(region.allSatisfy { end.bodyMask[$0] == result.bodyMask[$0] }, "Tick/static boundary jumps the middle wave phase")
        }
    }
    let start = straight.render(0)
    let end = straight.render(3)
    var paired = 0
    for scale in start.scales where scale.bodyPosition > 2 && scale.bodyPosition < 6 {
        guard let next = end.scales.first(where: { close($0.bodyPosition, scale.bodyPosition) }) else { continue }
        paired += 1
        expect(close(next.center.x - scale.center.x, 3), "Material scale outruns or lags three actual head moves")
        for (value, travel) in [(scale, 0.0), (next, 3.0)] {
            let expectedY = 5.5 + 0.16 * sin((value.bodyPosition - travel) * .pi)
            expect(close(value.center.y, expectedY), "Material does not follow the stationary wave at its new world position")
        }
    }
    expect(paired > 0, "Fixture has no surviving material identities at both endpoints")
    let middleY = start.samples.filter { $0.bodyPosition > 1.25 && $0.bodyPosition < 6 }.map { $0.center.y }
    expect(middleY.max()! - middleY.min()! > 0.25, "The fixed middle contour has no visible wave")
    var sways: [Double] = []
    for result in travels.map({ straight.render($0) }) {
        let delta = result.headCenter - result.centers[0]
        expect(abs(delta.x) < 0.000_001 && delta.length <= 0.040_001, "Head sway moves forward or exceeds its small lateral range")
        let dot = result.heading.x * result.headHeading.x + result.heading.y * result.headHeading.y
        expect(dot > 0.98, "Presented head rotates away from its travel direction")
        sways.append(delta.y)
    }
    expect(sways.min()! < -0.025 && sways.max()! > 0.025, "Head does not gently sway to both sides while advancing")
}

private func checkFoodPulse() {
    let snake = (0..<8).map { GridCell(x: 12 - $0, y: 3) }
    let food = GridCell(x: 8, y: 15)
    var minimum = (time: 0.0, radius: Double.greatestFiniteMagnitude)
    var maximum = (time: 0.0, radius: 0.0)
    for index in 0...140 {
        let time = Double(index) / 100
        let radius = SnakeVisualGeometry.foodRadius(at: time)
        expect(radius >= 0.159_999 && radius <= 0.440_001, "Food pulse leaves its cell or disappears")
        expect(close(radius, SnakeVisualGeometry.foodRadius(at: time + 1.4)), "Food pulse is not periodic")
        if radius < minimum.radius { minimum = (time, radius) }
        if radius > maximum.radius { maximum = (time, radius) }
    }
    expect(maximum.radius - minimum.radius > 0.2, "Food pulse has no visible size change")
    let small = frame(snake, time: minimum.time, food: food)
    let large = frame(snake, time: maximum.time, food: food)
    let smallArea = small.dots.filter { $0 == 2 }.count
    let largeArea = large.dots.filter { $0 == 2 }.count
    expect(smallArea > 0 && largeArea > smallArea, "Food size does not change in the actual raster")
    expect(frame(snake, time: 0, food: food, reduced: true).dots == frame(snake, time: 10, food: food, reduced: true).dots,
           "Reduced Motion does not freeze the fruit and body")
    expect(frame(snake).dots.allSatisfy { $0 != 2 }, "Food remains after it was removed")
}

private func checkManyWrapsAndTranslation() {
    // A unique path can wind horizontally many times before filling this torus.
    // This catches renderers that only copy the whole path into nine tiles.
    var snake: [GridCell] = []
    for row in 0..<map.rows {
        let start = (map.columns - row % map.columns) % map.columns
        for step in 0..<map.columns { snake.append(GridCell(x: (start + step) % map.columns, y: row)) }
    }
    let original = frame(snake, time: 0.37)
    checkFiniteAndLocal(original)
    expect(original.centers.last!.x - original.centers.first!.x > Double(map.columns * 3), "Fixture does not cross enough seams")
    let density = SnakeVisualGeometry.pixelsPerCell
    for row in 0..<map.rows {
        let range = (row * density * original.columns)..<((row + 1) * density * original.columns)
        expect(original.dots[range].filter { $0 == 1 }.count > map.columns * 2, "A long wrapped body disappears in row \(row)")
    }
    let dx = 3, dy = 7
    let translated = snake.map { GridCell(x: ($0.x + dx) % map.columns, y: ($0.y + dy) % map.rows) }
    let shifted = frame(translated, time: 0.37)
    for y in 0..<original.rows {
        for x in 0..<original.columns {
            let nextX = (x + dx * density) % original.columns
            let nextY = (y + dy * density) % original.rows
            expect(original.dots[y * original.columns + x] == shifted.dots[nextY * shifted.columns + nextX], "Raster is not toroidally translation invariant")
        }
    }
}

private func checkMapTopologies() {
    let density = SnakeVisualGeometry.pixelsPerCell
    func render(_ configuration: SnakeConfiguration, before: [GridCell], after: [GridCell], progress: Double, completedMoves: Int = 1) -> SnakeVisualFrame {
        // Fixtures obey the selected map's actual rules; no test manufactures
        // an illegal jump through a wall just to exercise interpolation.
        for body in [before, after] {
            expect(body.allSatisfy { configuration.contains($0) }, "Fixture outside map")
            for (a, b) in zip(body, body.dropFirst()) {
                expect(configuration.areNeighbors(a, b), "Fixture body crosses a wall")
            }
        }
        expect(configuration.areNeighbors(before[0], after[0]), "Fixture head crosses a wall")
        let result = SnakeVisualGeometry.frame(configuration: configuration, snake: after,
                                               previousSnake: before, food: nil, progress: progress, time: 0.37, completedMoves: completedMoves)
        checkFiniteAndLocal(result, configuration: configuration)
        for wall in configuration.walls {
            for y in 0..<density {
                for x in 0..<density {
                    let index = (wall.y * density + y) * result.columns + wall.x * density + x
                    expect(result.dots[index] == 0 && !result.bodyMask[index], "Animated snake mask or pixels spill into a wall cell")
                }
            }
        }
        for point in result.centers {
            if !configuration.wrapsHorizontally {
                expect(point.x >= 0.5 && point.x <= Double(configuration.columns) - 0.5, "Interpolation left a horizontal wall")
            }
            if !configuration.wrapsVertically {
                expect(point.y >= 0.5 && point.y <= Double(configuration.rows) - 0.5, "Interpolation left a vertical wall")
            }
        }
        return result
    }

    let walls = SnakeMap.courtyard.configuration
    let wallBefore = [GridCell(x: 1, y: 2), GridCell(x: 1, y: 3), GridCell(x: 2, y: 3), GridCell(x: 3, y: 3)]
    let wallAfter = [GridCell(x: 1, y: 1)] + wallBefore.dropLast()
    for progress in [0.0, 0.5, 1.0] {
        let result = render(walls, before: wallBefore, after: wallAfter, progress: progress)
        expect(close(result.centers[0].y, 2.5 - progress), "Head doesn't approach the wall directly")
        for index in result.dots.indices where result.dots[index] == 1 {
            expect(index % result.columns / density < 5 && index / result.columns / density < 5,
                   "Walled body is mirrored to the opposite edge")
        }
    }

    let passage = SnakeConfiguration(columns: 16, rows: 24, wrapsHorizontally: true, wrapsVertically: false)
    let passageBefore = [GridCell(x: 15, y: 0), GridCell(x: 14, y: 0), GridCell(x: 13, y: 0), GridCell(x: 13, y: 1)]
    let passageAfter = [GridCell(x: 0, y: 0)] + passageBefore.dropLast()
    let horizontal = render(passage, before: passageBefore, after: passageAfter, progress: 0.5)
    expect(close(horizontal.centers[0].x, 16), "Passage does not interpolate across its open seam")
    expect((0..<horizontal.rows).contains { horizontal.dots[$0 * horizontal.columns] == 1 }, "Open left seam loses the head")
    expect((0..<horizontal.rows).contains { horizontal.dots[$0 * horizontal.columns + horizontal.columns - 1] == 1 }, "Open right seam loses the head")
    for index in horizontal.dots.indices where horizontal.dots[index] == 1 {
        expect(index / horizontal.columns / density < 4, "Passage mirrors its top body through the bottom wall")
    }

    // The renderer handles either independent wrap flag, even though the
    // current setup choices expose horizontal-only wrapping as the corridor.
    let verticalOnly = SnakeConfiguration(columns: 16, rows: 24, wrapsHorizontally: false, wrapsVertically: true)
    let verticalBefore = [GridCell(x: 0, y: 23), GridCell(x: 0, y: 22), GridCell(x: 0, y: 21), GridCell(x: 1, y: 21)]
    let verticalAfter = [GridCell(x: 0, y: 0)] + verticalBefore.dropLast()
    let vertical = render(verticalOnly, before: verticalBefore, after: verticalAfter, progress: 0.5)
    expect(close(vertical.centers[0].y, 24), "Vertical seam takes a long route")
    expect(vertical.dots[0..<vertical.columns].contains(1), "Open top seam loses the head")
    expect(vertical.dots[(vertical.rows - 1) * vertical.columns..<vertical.dots.count].contains(1), "Open bottom seam loses the head")
    for index in vertical.dots.indices where vertical.dots[index] == 1 {
        expect(index % vertical.columns / density < 4, "Vertical-only wrapping mirrors through a side wall")
    }

    // Exercise real, consecutive game states on all displayed maps so growth
    // and interpolation use each map's dimensions and boundary topology.
    for selectedMap in SnakeMap.allCases {
        var game = SnakeEngine(configuration: selectedMap.configuration, seed: 42)
        for _ in 0..<96 {
            let before = game.snake
            game.step()
            for progress in [0.0, 0.5, 1.0] {
                _ = render(selectedMap.configuration, before: before, after: game.snake, progress: progress, completedMoves: game.steps)
            }
        }
        while game.phase == .playing && game.snake.count < game.configuration.cellCount / 2 { game.step() }
        let before = game.snake
        game.step()
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            _ = render(selectedMap.configuration, before: before, after: game.snake, progress: progress, completedMoves: game.steps)
        }
    }
}

// This catalog is also compiled independently against the original ca75bcb
// geometry to obtain the golden rasters, without importing today's helpers.
private struct AppearanceFixture {
    let name: String
    let configuration: SnakeConfiguration
    let snake: [GridCell]
    let previous: [GridCell]
    let food: GridCell?
    let progress: Double
    let time: Double
    let reduced: Bool

    init(_ name: String, _ snake: [GridCell], previous: [GridCell]? = nil,
         configuration: SnakeConfiguration = .firstMap, food: GridCell? = nil,
         progress: Double = 1, time: Double = 0, reduced: Bool = false) {
        self.name = name
        self.configuration = configuration
        self.snake = snake
        self.previous = previous ?? snake
        self.food = food
        self.progress = progress
        self.time = time
        self.reduced = reduced
    }
}

private func appearanceFixtures() -> [AppearanceFixture] {
    let straight = (0..<10).map { GridCell(x: 12 - $0, y: 8) }
    let before = [GridCell(x: 5, y: 5), GridCell(x: 4, y: 5), GridCell(x: 3, y: 5), GridCell(x: 2, y: 5)]
    let moving = [GridCell(x: 6, y: 5)] + before.dropLast()
    let growing = [GridCell(x: 6, y: 5)] + before
    let seamBefore = [GridCell(x: 15, y: 8), GridCell(x: 14, y: 8), GridCell(x: 13, y: 8)]
    let seamAfter = [GridCell(x: 0, y: 8), GridCell(x: 15, y: 8), GridCell(x: 14, y: 8)]
    let cornerBefore = [GridCell(x: 15, y: 0), GridCell(x: 15, y: 23), GridCell(x: 15, y: 22), GridCell(x: 14, y: 22)]
    let wallBefore = [GridCell(x: 1, y: 2), GridCell(x: 1, y: 3), GridCell(x: 2, y: 3), GridCell(x: 3, y: 3)]
    var winding: [GridCell] = []
    for y in 0..<24 {
        let start = (16 - y % 16) % 16
        for step in 0..<16 { winding.append(GridCell(x: (start + step) % 16, y: y)) }
    }
    return [
        AppearanceFixture("straight-a", straight, time: 0.1),
        AppearanceFixture("straight-b", straight, time: 0.6),
        AppearanceFixture("reduced", straight, progress: 0.25, time: 10, reduced: true),
        AppearanceFixture("moving-start", moving, previous: before, progress: 0, time: 0.37),
        AppearanceFixture("moving-middle", moving, previous: before, progress: 0.5, time: 0.37),
        AppearanceFixture("moving-end", moving, previous: before, time: 0.37),
        AppearanceFixture("growing-early", growing, previous: before, progress: 0.125, time: 0.37),
        AppearanceFixture("growing-middle", growing, previous: before, progress: 0.5, time: 0.37),
        AppearanceFixture("growing-end", growing, previous: before, time: 0.37),
        AppearanceFixture("horizontal-seam", seamAfter, previous: seamBefore, progress: 0.5, time: 0.2),
        AppearanceFixture("two-axis-corner", [GridCell(x: 0, y: 0)] + cornerBefore.dropLast(), previous: cornerBefore, progress: 0.5, time: 0.43),
        AppearanceFixture("wall-corner", [GridCell(x: 1, y: 1)] + wallBefore.dropLast(), previous: wallBefore,
                          configuration: SnakeMap.courtyard.configuration, progress: 0.5, time: 0.37),
        AppearanceFixture("long-multiple-wraps", winding, time: 0.37),
        AppearanceFixture("small-food", straight, food: GridCell(x: 8, y: 15)),
        AppearanceFixture("large-food", straight, food: GridCell(x: 8, y: 15), time: 0.7),
        AppearanceFixture("reduced-food", straight, food: GridCell(x: 8, y: 15), time: 10, reduced: true),
        AppearanceFixture("empty", []),
        AppearanceFixture("one-cell", [GridCell(x: 1, y: 1)], time: 0.6)
    ]
}

private func modernFrame(_ fixture: AppearanceFixture) -> SnakeVisualFrame {
    SnakeVisualGeometry.frame(configuration: fixture.configuration, snake: fixture.snake, previousSnake: fixture.previous,
                              food: fixture.food, progress: fixture.progress, time: fixture.time,
                              completedMoves: 37, appearance: .modern, reduceMotion: fixture.reduced)
}

private func rasterHash(_ dots: [UInt8]) -> UInt64 {
    dots.reduce(0xCBF29CE484222325) { ($0 ^ UInt64($1)) &* 0x100000001B3 }
}

private func checkModernBehavior() {
    expect(SnakeAppearance.allCases.map(\.label) == ["经典", "现代"], "Appearance choices or labels changed")
    let snake = (0..<10).map { GridCell(x: 12 - $0, y: 8) }
    let early = frame(snake, time: 0.1, appearance: .modern)
    let later = frame(snake, time: 0.6, appearance: .modern)
    expect(early.centers == later.centers && early.heading == later.heading, "Modern animation changes logical anchors")
    expect(zip(early.samples, later.samples).contains { distance($0.center, $1.center) > 0.03 }, "Modern body does not sway with elapsed time")
    expect(early.bodyMask != later.bodyMask && early.dots != later.dots, "Modern whole-body wave does not reach the raster")
    expect(early.headCenter == early.centers[0] && early.headHeading == early.heading && early.scales.isEmpty, "Modern appearance acquired classic sway or scales")
    let reduced = frame(snake, time: 0.1, reduced: true, appearance: .modern)
    let reducedLater = frame(snake, time: 100, reduced: true, appearance: .modern)
    expect(reduced.dots == reducedLater.dots && reduced.bodyMask == reducedLater.bodyMask && sameSamples(reduced, reducedLater), "Modern Reduced Motion still animates")
    for fixture in appearanceFixtures() {
        let result = modernFrame(fixture)
        checkFiniteAndLocal(result, configuration: fixture.configuration)
        let density = SnakeVisualGeometry.pixelsPerCell
        for wall in fixture.configuration.walls {
            for y in 0..<density {
                for x in 0..<density {
                    let index = (wall.y * density + y) * result.columns + wall.x * density + x
                    expect(!result.bodyMask[index] && result.dots[index] == 0, "Modern raster spills into a real wall")
                }
            }
        }
    }
    let before = [GridCell(x: 5, y: 5), GridCell(x: 4, y: 5), GridCell(x: 3, y: 5), GridCell(x: 2, y: 5)]
    let growing = [GridCell(x: 6, y: 5)] + before
    for progress in [0.0, 0.5, 1.0] {
        let result = frame(growing, previous: before, progress: progress, time: 0.37, appearance: .modern)
        expect(result.centers.count == growing.count && close(result.centers[0].x, 5.5 + progress)
               && close(result.centers.last!.x, 2.5), "Modern growth changed the original head/tail interpolation")
    }
    // Source-derived fixtures are supplemented with actual consecutive states
    // on every obstacle map so the shared raster retains today's wall masks.
    for map in SnakeMap.allCases {
        var game = SnakeEngine(configuration: map.configuration, seed: 42)
        let before = game.snake
        game.step()
        let fixture = AppearanceFixture(map.rawValue, game.snake, previous: before, configuration: map.configuration, progress: 0.5, time: 0.37)
        let result = modernFrame(fixture)
        checkFiniteAndLocal(result, configuration: map.configuration)
        let density = SnakeVisualGeometry.pixelsPerCell
        for wall in map.configuration.walls {
            for y in 0..<density { for x in 0..<density {
                let index = (wall.y * density + y) * result.columns + wall.x * density + x
                expect(result.dots[index] == 0 && !result.bodyMask[index], "Modern snake crosses map walls")
            } }
        }
    }
}

private func checkModernGoldenRasters() {
    // Generated by independently compiling ca75bcb with the fixture catalog.
    let expected: [UInt64] = [
        9370632795737805272, // straight-a
        8570509640291317058, // straight-b
        10308911250418179574, // reduced
        9694301604952292666, // moving-start
        10231017567877669524, // moving-middle
        11572095293383641332, // moving-end
        10571101157123011483, // growing-early
        13735504228264282009, // growing-middle
        2214836453874683211, // growing-end
        4989490125271167877, // horizontal-seam
        3667029496880679291, // two-axis-corner
        5315045117738430461, // wall-corner
        4164677751938553151, // long-multiple-wraps
        13871521514563730908, // small-food
        3379045248915045501, // large-food
        13337546295866168264, // reduced-food
        6331361937516929317, // empty
        17691176902789943427, // one-cell
    ]
    let fixtures = appearanceFixtures()
    expect(fixtures.count == expected.count, "Legacy fixture catalog and golden hashes disagree")
    for (fixture, expectedHash) in zip(fixtures, expected) {
        expect(rasterHash(modernFrame(fixture).dots) == expectedHash, "Modern raster differs from ca75bcb: \(fixture.name)")
    }
}

private func benchmark() {
    var game = SnakeEngine(seed: 42)
    while game.phase == .playing { game.step() }
    for _ in 0..<5 { _ = frame(game.snake, time: 0.2) }
    var times: [Double] = []
    var checksum = 0
    for index in 0..<180 {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = frame(game.snake, time: Double(index) / 24)
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        checksum += result.dots[index % result.dots.count].hashValue & 1
    }
    times.sort()
    print(String(format: "384-cell geometry, 180 frames: median %.3f ms; p95 %.3f ms; max %.3f ms (host only; checksum %d)",
                 times[times.count / 2], times[Int(Double(times.count - 1) * 0.95)], times.last!, checksum))
}

@main
private enum SnakeVisualChecks {
    static func main() {
        checkEndpointsAndGrowth()
        checkWrapAndCorners()
        checkAnatomyAndMotionClock()
        checkStationaryWaveAndMaterialMotion()
        checkFoodPulse()
        checkManyWrapsAndTranslation()
        checkMapTopologies()
        checkModernBehavior()
        checkModernGoldenRasters()
        print("Visual geometry checks passed: growth, seams/corners, head/eyes/tail, stationary world wave, same-speed material, distance clock, pulse, Reduced Motion, long paths, translation, walls and exact ca75bcb modern rasters.")
        if ProcessInfo.processInfo.arguments.contains("--benchmark") { benchmark() }
    }
}
