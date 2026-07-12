//
//  SpritePencilKitTests.swift
//  Sprite Pencil
//
//  Regression coverage for the 1.6.2 correctness fixes (edge-of-canvas reads,
//  the ColorComponents Hashable contract, buffer offset math, pixel-format
//  preservation) and the 2.0 controller-owned operation lifecycle
//  (commit/cancel/undo/redo without any views attached).
//

import Testing
import UIKit
@testable import SpritePencilKit

/// Matches the app's sprite drawing context format (BGRA, premultiplied-first,
/// little-endian, sRGB) — the format the engine's pointer math assumes.
private func makeSpriteContext(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// Since 2.0, the controller renders to `renderedImage` and publishes events —
/// no views are required to exercise any of it.
@MainActor
private func makeController(width: Int, height: Int) -> DocumentController {
    let controller = DocumentController()
    controller.loadContext(makeSpriteContext(width: width, height: height))
    return controller
}

struct ColorComponentsTests {

    @Test func equalValuesHashEqually() {
        let invisibleRed = ColorComponents(red: 255, green: 0, blue: 0, opacity: 0)
        let clear = ColorComponents.clear
        #expect(invisibleRed == clear)
        #expect(invisibleRed.hashValue == clear.hashValue)
        #expect(invisibleRed.id == clear.id)
        #expect(Set([invisibleRed, clear]).count == 1)
    }

    @Test func distinctColorsAreDistinct() {
        let red = ColorComponents(red: 255, green: 0, blue: 0, opacity: 255)
        let blue = ColorComponents(red: 0, green: 0, blue: 255, opacity: 255)
        #expect(red != blue)
        #expect(red.id != blue.id)
        #expect(red == ColorComponents(red: 255, green: 0, blue: 0, opacity: 255))
    }

    @Test func hexParsing() {
        let rgb = ColorComponents(hex: "#FF8000")
        #expect(rgb?.red == 255)
        #expect(rgb?.green == 128)
        #expect(rgb?.blue == 0)
        #expect(rgb?.opacity == 255)

        let rgba = ColorComponents(hex: "0080FF7F")
        #expect(rgba?.red == 0)
        #expect(rgba?.green == 128)
        #expect(rgba?.blue == 255)
        #expect(rgba?.opacity == 127)

        #expect(ColorComponents(hex: "12345") == nil)
    }
}

@MainActor
struct DocumentControllerTests {

    @Test func paintRoundTripsThroughPaddedRows() {
        // Width 3 → 12 content bytes per row, which CG typically pads; the
        // offset math must use bytesPerRow, not width.
        let controller = makeController(width: 3, height: 3)
        let color = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.simplePaint(colorComponents: color, at: PixelPoint(x: 2, y: 1))
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 1)) == color)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
    }

    @Test func outlineStopsAtCanvasEdges() {
        // A single colored pixel in the corner of a 2×2 canvas: outlining must
        // not read past the edges, and must outline exactly its two neighbors.
        let controller = makeController(width: 2, height: 2)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.outline(colorComponents: ColorComponents(red: 0, green: 0, blue: 0, opacity: 255))

        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)).opacity == 255)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)).opacity == 255)
        // Not adjacent to the ink at collection time — stays clear.
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
    }

    @Test func outlineUndoesAsOneStep() {
        // The outline is committed as a single pixel-diff: one undo() must
        // clear every outline pixel (no per-pixel undo grouping anymore).
        let controller = makeController(width: 3, height: 3)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 1, y: 1))
        controller.currentOperationPixelPoints.removeAll()

        controller.outline(colorComponents: ColorComponents(red: 0, green: 0, blue: 0, opacity: 255))
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)).opacity == 255)

        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == ink)
    }

    @Test func shadeToolsSkipOutOfBoundsCellsOfTheBrush() {
        // A 3×3 highlight/shadow stamp whose footprint hangs off every edge of
        // a 2×2 canvas: out-of-bounds cells must be skipped, in-bounds painted.
        let controller = makeController(width: 2, height: 2)
        let ink = ColorComponents(red: 120, green: 120, blue: 120, opacity: 255)
        for x in 0..<2 {
            for y in 0..<2 {
                controller.simplePaint(colorComponents: ink, at: PixelPoint(x: x, y: y))
            }
        }
        controller.currentOperationPixelPoints.removeAll()

        controller.highlight(at: PixelPoint(x: -1, y: -1), size: PixelSize(width: 3, height: 3))
        #expect(Set(controller.currentOperationPixelPoints.keys) == [PixelPoint(x: 0, y: 0), PixelPoint(x: 1, y: 0), PixelPoint(x: 0, y: 1), PixelPoint(x: 1, y: 1)])

        controller.currentOperationPixelPoints.removeAll()
        controller.shadow(at: PixelPoint(x: 1, y: 1), size: PixelSize(width: 3, height: 3))
        #expect(Set(controller.currentOperationPixelPoints.keys) == [PixelPoint(x: 1, y: 1)])
    }

    @Test func flipVerticalMirrorsRows() {
        // Non-square on purpose: a corner pixel must land in the opposite row,
        // same column. (The old implementation redrew the image unchanged.)
        let controller = makeController(width: 3, height: 2)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.flip(vertically: true)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)) == ink)

        // Flipping again restores the original.
        controller.flip(vertically: true)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
    }

    @Test func flipHorizontalMirrorsColumns() {
        let controller = makeController(width: 3, height: 2)
        let ink = ColorComponents(red: 50, green: 200, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.flip(vertically: false)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 0)) == ink)

        controller.flip(vertically: false)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
    }

    @Test func matchingContextPreservesPixelFormat() {
        let context = makeSpriteContext(width: 3, height: 5)
        let rotated = context.makeMatchingContext(width: 5, height: 3)
        #expect(rotated != nil)
        #expect(rotated?.bitmapInfo == context.bitmapInfo)
        #expect(rotated?.bitsPerComponent == context.bitsPerComponent)
        #expect(rotated?.colorSpace?.name == context.colorSpace?.name)
        #expect(rotated?.width == 5)
        #expect(rotated?.height == 3)
    }
}

@MainActor
struct OperationLifecycleTests {

    @Test func strokeCommitRegistersOneUndoableDiff() {
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)

        controller.beginCurrentOperation()
        controller.brushPaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0), size: PixelSize(width: 1, height: 1))
        controller.brushPaint(colorComponents: ink, at: PixelPoint(x: 1, y: 0), size: PixelSize(width: 1, height: 1))
        controller.commitCurrentOperation()

        #expect(controller.currentOperationPixelPoints.isEmpty)
        #expect(undoManager.canUndo)

        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == .clear)

        controller.redo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == ink)
    }

    @Test func emptyCommitRegistersNoUndo() {
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager

        controller.beginCurrentOperation()
        controller.commitCurrentOperation()
        #expect(!undoManager.canUndo)
    }

    @Test func cancelRestoresTheCanceledStroke() {
        let controller = makeController(width: 4, height: 4)
        let under = ColorComponents(red: 5, green: 5, blue: 5, opacity: 255)
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.simplePaint(colorComponents: under, at: PixelPoint(x: 1, y: 1))
        controller.currentOperationPixelPoints.removeAll()

        controller.beginCurrentOperation()
        controller.brushPaint(colorComponents: ink, at: PixelPoint(x: 1, y: 1), size: PixelSize(width: 1, height: 1))
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == ink)

        controller.cancelCurrentOperation()
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == under)
        #expect(controller.currentOperationPixelPoints.isEmpty)
    }

    @Test func fillCommitsItselfAndUndoes() {
        let controller = makeController(width: 3, height: 3)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.toolColorComponents = ink

        controller.fill(at: PixelPoint(x: 1, y: 1))
        for x in 0..<3 {
            for y in 0..<3 {
                #expect(controller.getColorComponents(at: PixelPoint(x: x, y: y)) == ink)
            }
        }

        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
    }

    @Test func pencilCommitFillsClosedLoopInterior() {
        // Stroke the perimeter of the (1,1)–(5,5) square in touch order; with
        // shouldFillPaths on, committing fills the interior as part of the
        // same undoable operation.
        let controller = makeController(width: 8, height: 8)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        controller.shouldFillPaths = true
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.toolColorComponents = ink

        var ring = [PixelPoint]()
        for x in 1...5 { ring.append(PixelPoint(x: x, y: 1)) }
        for y in 2...5 { ring.append(PixelPoint(x: 5, y: y)) }
        for x in stride(from: 4, through: 1, by: -1) { ring.append(PixelPoint(x: x, y: 5)) }
        for y in stride(from: 4, through: 2, by: -1) { ring.append(PixelPoint(x: 1, y: y)) }

        controller.beginCurrentOperation()
        for point in ring {
            controller.brushPaint(colorComponents: ink, at: point, size: PixelSize(width: 1, height: 1))
        }
        controller.commitCurrentOperation()

        for x in 2...4 {
            for y in 2...4 {
                #expect(controller.getColorComponents(at: PixelPoint(x: x, y: y)) == ink)
            }
        }
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 6, y: 6)) == .clear)

        // Stroke and fill undo together.
        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 3, y: 3)) == .clear)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
    }

    @Test func moveCommitWrapsAndUndoes() {
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.beginMove()
        controller.continueMove(delta: CGSize(width: 1, height: 0))
        controller.commitMove(delta: CGSize(width: 2, height: 1))

        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 1)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)

        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 1)) == .clear)
    }

    @Test func trimCanvasUndoRestoresTheOriginalContext() {
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let ink = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 1, y: 2))
        controller.currentOperationPixelPoints.removeAll()

        controller.trimCanvas()
        #expect(controller.context.width == 1)
        #expect(controller.context.height == 1)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)

        controller.undo()
        #expect(controller.context.width == 4)
        #expect(controller.context.height == 4)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 2)) == ink)
    }
}

struct SerializationTests {

    @Test func hexFormattingRoundTrips() {
        let color = ColorComponents(red: 255, green: 8, blue: 128, opacity: 255)
        #expect(color.hex == "#FF0880")
        #expect(ColorComponents(hex: color.hex) == color)
    }

    @Test func paletteRoundTripsThroughPNG() throws {
        let palette = Palette(name: "Round Trip", specialCase: nil, colors: [
            ColorComponents(red: 255, green: 0, blue: 0, opacity: 255),
            ColorComponents(red: 1, green: 2, blue: 3, opacity: 255),
            ColorComponents(red: 128, green: 200, blue: 50, opacity: 255),
        ], defaultGroupLength: 1)

        let data = try #require(palette.pngData())
        let image = try #require(UIImage(data: data))
        let loaded = try #require(Palette(name: palette.name, image: image, defaultGroupLength: 1))
        #expect(loaded.colors == palette.colors)
    }

    @Test func emptyPaletteHasNoPNG() {
        let empty = Palette(name: "Empty", specialCase: nil, colors: [], defaultGroupLength: 1)
        #expect(empty.pngData() == nil)
    }
}
