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

    @Test func replaceAllFillRecolorsDisconnectedPixels() {
        let controller = makeController(width: 5, height: 1)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let red = ColorComponents(red: 255, green: 0, blue: 0, opacity: 255)
        let blue = ColorComponents(red: 0, green: 0, blue: 255, opacity: 255)
        let wall = ColorComponents(red: 0, green: 0, blue: 0, opacity: 255)
        // red, wall, red, wall, red — no two reds touch.
        for x in 0..<5 {
            controller.contextDataManager[PixelPoint(x: x, y: 0)] = x.isMultiple(of: 2) ? red : wall
        }
        controller.toolColorComponents = blue
        controller.fillTool.replacesAllMatching = true

        controller.fill(at: PixelPoint(x: 0, y: 0))
        for x in 0..<5 {
            #expect(controller.getColorComponents(at: PixelPoint(x: x, y: 0)) == (x.isMultiple(of: 2) ? blue : wall))
        }

        controller.undo()
        for x in stride(from: 0, to: 5, by: 2) {
            #expect(controller.getColorComponents(at: PixelPoint(x: x, y: 0)) == red)
        }
    }

    @Test func remapColorsSkipsClearAndUndoesAsOneStep() {
        let controller = makeController(width: 3, height: 1)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let gray = ColorComponents(red: 100, green: 100, blue: 100, opacity: 255)
        let white = ColorComponents(red: 255, green: 255, blue: 255, opacity: 255)
        controller.contextDataManager[PixelPoint(x: 0, y: 0)] = gray
        controller.contextDataManager[PixelPoint(x: 1, y: 0)] = gray

        var calls = 0
        controller.remapColors { color in
            calls += 1
            return color.opacity == 0 ? gray : white
        }
        #expect(calls == 1) // once per distinct color; clear is never passed
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == white)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == white)
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 0)) == .clear)

        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == gray)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == gray)
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

    @Test func zeroDeltaMoveRegistersNoUndo() {
        // A tap with the move tool changes nothing and must not pollute the
        // undo stack.
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager

        controller.beginMove()
        controller.commitMove(delta: .zero)
        #expect(!undoManager.canUndo)
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

@MainActor
struct SelectionMoveTests {

    @Test func selectionMoveMovesOnlySelectedPixels() {
        let controller = makeController(width: 4, height: 4)
        let inside = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        let outside = ColorComponents(red: 50, green: 50, blue: 200, opacity: 255)
        controller.simplePaint(colorComponents: inside, at: PixelPoint(x: 0, y: 0))
        controller.simplePaint(colorComponents: outside, at: PixelPoint(x: 3, y: 3))
        controller.currentOperationPixelPoints.removeAll()

        controller.setSelectedArea(CGRect(x: 0, y: 0, width: 2, height: 2))
        controller.beginMove()
        controller.commitMove(delta: CGSize(width: 1, height: 1))

        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == inside)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
        // Pixels outside the selection stay put.
        #expect(controller.getColorComponents(at: PixelPoint(x: 3, y: 3)) == outside)
        // The selection follows its pixels.
        #expect(controller.selectedArea == CGRect(x: 1, y: 1, width: 2, height: 2))
    }

    @Test func selectionMoveClipsAtEdgesInsteadOfWrapping() {
        let controller = makeController(width: 4, height: 4)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.setSelectedArea(CGRect(x: 0, y: 0, width: 1, height: 1))
        controller.beginMove()
        controller.commitMove(delta: CGSize(width: -1, height: 0))

        // The pixel fell off the left edge — nowhere on the canvas (a
        // whole-canvas move would have wrapped it to x=3).
        for x in 0..<4 {
            for y in 0..<4 {
                #expect(controller.getColorComponents(at: PixelPoint(x: x, y: y)) == .clear)
            }
        }
        // A selection pushed entirely off-canvas clears itself.
        #expect(controller.selectedArea == nil)
    }

    @Test func selectionMoveOverwritesAndUndoRestoresEverything() {
        let controller = makeController(width: 4, height: 4)
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        let moved = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        let covered = ColorComponents(red: 50, green: 200, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: moved, at: PixelPoint(x: 0, y: 0))
        controller.simplePaint(colorComponents: covered, at: PixelPoint(x: 1, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.setSelectedArea(CGRect(x: 0, y: 0, width: 1, height: 1))
        controller.beginMove()
        controller.commitMove(delta: CGSize(width: 1, height: 0))

        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == moved)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)

        // Undo restores both the moved pixel and the one it covered
        // (an inverse move couldn't — hence the snapshot undo).
        controller.undo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == moved)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == covered)

        controller.redo()
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == moved)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
    }

    @Test func setSelectedAreaClipsToTheCanvas() {
        let controller = makeController(width: 4, height: 4)

        controller.setSelectedArea(CGRect(x: -2, y: 2, width: 10, height: 10))
        #expect(controller.selectedArea == CGRect(x: 0, y: 2, width: 4, height: 2))

        controller.setSelectedArea(CGRect(x: 5, y: 5, width: 2, height: 2))
        #expect(controller.selectedArea == nil)
    }

    @Test func leavingTheMoveToolClearsTheSelection() {
        let controller = makeController(width: 4, height: 4)
        controller.setSelectedArea(CGRect(x: 1, y: 1, width: 2, height: 2))
        #expect(controller.selectedArea != nil)

        controller.tool = controller.pencilTool
        #expect(controller.selectedArea == nil)
    }

    @Test func disablingSelectModeClearsTheSelection() {
        let controller = makeController(width: 4, height: 4)
        controller.moveTool.selectsArea = true
        controller.setSelectedArea(CGRect(x: 1, y: 1, width: 2, height: 2))

        controller.moveTool.selectsArea = false
        #expect(controller.selectedArea == nil)
    }

    @Test func canvasReplacementClearsTheSelection() {
        let controller = makeController(width: 4, height: 4)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 1, y: 2))
        controller.currentOperationPixelPoints.removeAll()
        controller.setSelectedArea(CGRect(x: 0, y: 0, width: 2, height: 2))

        controller.trimCanvas()
        #expect(controller.selectedArea == nil)
    }
}

struct TiledPreviewTests {

    @Test func ringCoversAWholeMultipleOfTheCanvas() {
        // 100pt of room around a 30pt canvas needs 4 repeats per side (120pt).
        let ring = CanvasUIView.tileRingCount(coverage: CGSize(width: 100, height: 100), canvasSize: CGSize(width: 30, height: 30))
        #expect(ring.columns == 4)
        #expect(ring.rows == 4)
    }

    @Test func ringIsAtLeastOneRepeatPerSide() {
        // Before the container has reported a visible size, the canvas still
        // has to look tiled rather than bare.
        let ring = CanvasUIView.tileRingCount(coverage: .zero, canvasSize: CGSize(width: 32, height: 32))
        #expect(ring.columns == 1)
        #expect(ring.rows == 1)
    }

    @Test func ringSurvivesAnEmptyCanvas() {
        // No division by zero before a context is loaded.
        let ring = CanvasUIView.tileRingCount(coverage: CGSize(width: 500, height: 500), canvasSize: .zero)
        #expect(ring.columns == 1)
        #expect(ring.rows == 1)
    }

    @Test func ringIsCappedForATinyCanvas() {
        // A 1×1 canvas under a zoomed-out viewport would otherwise ask for
        // hundreds of repeats per side — six figures of replicated instances.
        let ring = CanvasUIView.tileRingCount(coverage: CGSize(width: 1000, height: 1000), canvasSize: CGSize(width: 2, height: 2))
        #expect(ring.columns == CanvasUIView.maximumTileRepeatsPerSide)
        #expect(ring.rows == CanvasUIView.maximumTileRepeatsPerSide)
    }

    @Test func ringIsWiderThanItIsTallForALandscapeViewport() {
        let ring = CanvasUIView.tileRingCount(coverage: CGSize(width: 320, height: 64), canvasSize: CGSize(width: 32, height: 32))
        #expect(ring.columns == 10)
        #expect(ring.rows == 2)
    }
}

@MainActor
struct TiledPreviewViewTests {

    /// A canvas inside its zoomable container, laid out at a realistic size.
    private func makeCanvas(pixels: Int) -> (CanvasUIView, ZoomableUIView) {
        let controller = makeController(width: pixels, height: pixels)
        let canvas = CanvasUIView(documentController: controller)
        let zoomable = ZoomableUIView(contentView: canvas, documentController: controller)
        zoomable.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        zoomable.setupView()
        zoomable.layoutIfNeeded()
        return (canvas, zoomable)
    }

    @Test func enablingTheTiledPreviewRingsTheCanvasWithRepeats() {
        let (canvas, zoomable) = makeCanvas(pixels: 8)
        canvas.tiledPreviewEnabled = true
        zoomable.layoutIfNeeded()

        let tileSize = CGSize(width: 8 * canvas.spriteZoomScale, height: 8 * canvas.spriteZoomScale)
        let columns = (canvas.tiledPreviewColumnsLayer.instanceCount - 1) / 2
        let rows = (canvas.tiledPreviewRowsLayer.instanceCount - 1) / 2

        #expect(!canvas.tiledPreviewRowsLayer.isHidden)
        #expect(canvas.tiledPreviewTileLayer.contents != nil) // the sprite itself
        #expect(canvas.tiledPreviewTileLayer.frame.size == tileSize)
        // A full ring on every side, reaching past the visible area.
        #expect(1 <= columns)
        #expect(1 <= rows)
        #expect(400 <= CGFloat(columns) * tileSize.width * zoomable.zoomScale)
        #expect(300 <= CGFloat(rows) * tileSize.height * zoomable.zoomScale)
        // Starting a whole number of tiles up and to the left is what keeps the
        // repeats seamless with the canvas.
        #expect(canvas.tiledPreviewRowsLayer.frame.origin == CGPoint(x: -CGFloat(columns) * tileSize.width, y: -CGFloat(rows) * tileSize.height))
    }

    @Test func theRingIsHiddenUntilTheTiledPreviewIsTurnedOn() {
        let (canvas, _) = makeCanvas(pixels: 8)
        #expect(canvas.tiledPreviewRowsLayer.isHidden)

        canvas.tiledPreviewEnabled = true
        #expect(!canvas.tiledPreviewRowsLayer.isHidden)

        canvas.tiledPreviewEnabled = false
        #expect(canvas.tiledPreviewRowsLayer.isHidden)
    }

    @Test func theRepeatsFollowEveryEditAndCanvasResize() {
        let (canvas, zoomable) = makeCanvas(pixels: 8)
        canvas.tiledPreviewEnabled = true
        zoomable.layoutIfNeeded()
        let beforeEdit = canvas.tiledPreviewTileLayer.contents as! CGImage

        canvas.documentController.simplePaint(colorComponents: ColorComponents(red: 10, green: 20, blue: 30, opacity: 255), at: PixelPoint(x: 1, y: 1))
        canvas.documentController.refresh()
        #expect((canvas.tiledPreviewTileLayer.contents as! CGImage) !== beforeEdit)

        // Trimming replaces the context, so the tile has to be resized to match.
        canvas.documentController.trimCanvas()
        zoomable.layoutIfNeeded()
        #expect(canvas.tiledPreviewTileLayer.frame.size == CGSize(width: 1 * canvas.spriteZoomScale, height: 1 * canvas.spriteZoomScale))
    }
}

@MainActor
struct ZoomToFitTests {

    @Test func theFirstLayoutFitsTheCanvasToTheView() {
        // Sized through `frame`, as SwiftUI does — which never calls the
        // `bounds` setter, so a fit hung off that never ran.
        let controller = makeController(width: 16, height: 16)
        let zoomable = ZoomableUIView(contentView: CanvasUIView(documentController: controller), documentController: controller)
        zoomable.setupView()
        zoomable.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        zoomable.layoutIfNeeded()

        // A square canvas in a landscape view fits its height.
        #expect(abs(zoomable.contentView.frame.height - 300) < 0.5)
    }
}

struct BrushShapeTests {

    @Test func squareIncludesEveryCell() {
        // Square fills its whole footprint at any diameter — including the
        // corners a circle would drop.
        for diameter in 1...9 {
            for row in 0..<diameter {
                for column in 0..<diameter {
                    #expect(BrushShape.square.includes(column: column, row: row, diameter: diameter))
                }
            }
        }
    }

    @Test func tinyCircleIsASolidBlock() {
        // 1px and 2px round brushes have no meaningful curve — every cell is in.
        for diameter in 1...2 {
            for row in 0..<diameter {
                for column in 0..<diameter {
                    #expect(BrushShape.circle.includes(column: column, row: row, diameter: diameter))
                }
            }
        }
    }

    @Test func smallestRoundBrushIsAPlus() {
        // The 3px circle is tightened by half a pixel so it renders as a plus:
        // the four edge-midpoints and center are in, the four corners are out.
        let inside = [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)]
        let outside = [(0, 0), (2, 0), (0, 2), (2, 2)]
        for (column, row) in inside {
            #expect(BrushShape.circle.includes(column: column, row: row, diameter: 3))
        }
        for (column, row) in outside {
            #expect(!BrushShape.circle.includes(column: column, row: row, diameter: 3))
        }
    }

    @Test func largerCircleClipsOnlyTheCorners() {
        // A 5px circle keeps the near-corner cells but drops the four true
        // corners, matching a round mask.
        #expect(!BrushShape.circle.includes(column: 0, row: 0, diameter: 5))
        #expect(!BrushShape.circle.includes(column: 4, row: 4, diameter: 5))
        #expect(BrushShape.circle.includes(column: 0, row: 1, diameter: 5))
        #expect(BrushShape.circle.includes(column: 2, row: 0, diameter: 5))
        #expect(BrushShape.circle.includes(column: 2, row: 2, diameter: 5)) // center
    }
}

@MainActor
struct RotateTests {

    /// The count of fully-opaque pixels in the canvas — a rotation must neither
    /// lose nor duplicate ink (the 1.6.1 bug clipped pixels off a non-square
    /// canvas by rotating without swapping dimensions).
    private func opaquePixelCount(_ controller: DocumentController) -> Int {
        var count = 0
        for y in 0..<controller.context.height {
            for x in 0..<controller.context.width {
                if controller.getColorComponents(at: PixelPoint(x: x, y: y)).opacity == 255 { count += 1 }
            }
        }
        return count
    }

    @Test func rotatingNonSquareSwapsDimensionsWithoutClipping() {
        let controller = makeController(width: 3, height: 2)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.rotate(to: .right)
        #expect(controller.context.width == 2)
        #expect(controller.context.height == 3)
        #expect(opaquePixelCount(controller) == 1) // pixel survived the turn
    }

    @Test func fourRightTurnsIsIdentityOnSquare() {
        let controller = makeController(width: 3, height: 3)
        let ink = ColorComponents(red: 10, green: 180, blue: 220, opacity: 255)
        // An L of three pixels — asymmetric so any wrong turn direction shows up.
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 1, y: 0))
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 1))
        controller.currentOperationPixelPoints.removeAll()

        for _ in 0..<4 { controller.rotate(to: .right) }

        #expect(controller.context.width == 3)
        #expect(controller.context.height == 3)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)) == ink)
        #expect(opaquePixelCount(controller) == 3)
    }

    @Test func rightTurnIsClockwise() {
        // A right (clockwise) quarter-turn sends the top row to the right column:
        // old (x,y) → new (H-1-y, x). Marking three corners of an L pins the
        // exact geometry (a reflection would fail these — see the fix in
        // DocumentController.rotate).
        let controller = makeController(width: 3, height: 3)
        let topLeft = ColorComponents(red: 200, green: 0, blue: 0, opacity: 255)
        let topRight = ColorComponents(red: 0, green: 200, blue: 0, opacity: 255)
        let bottomLeft = ColorComponents(red: 0, green: 0, blue: 200, opacity: 255)
        controller.simplePaint(colorComponents: topLeft, at: PixelPoint(x: 0, y: 0))
        controller.simplePaint(colorComponents: topRight, at: PixelPoint(x: 2, y: 0))
        controller.simplePaint(colorComponents: bottomLeft, at: PixelPoint(x: 0, y: 2))
        controller.currentOperationPixelPoints.removeAll()

        controller.rotate(to: .right)

        // top-left → top-right, top-right → bottom-right, bottom-left → top-left.
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 0)) == topLeft)
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 2)) == topRight)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == bottomLeft)
    }

    @Test func leftTurnIsCounterClockwise() {
        // A left turn is the mirror image: old (x,y) → new (y, W-1-x).
        let controller = makeController(width: 3, height: 3)
        let topLeft = ColorComponents(red: 200, green: 0, blue: 0, opacity: 255)
        let topRight = ColorComponents(red: 0, green: 200, blue: 0, opacity: 255)
        let bottomLeft = ColorComponents(red: 0, green: 0, blue: 200, opacity: 255)
        controller.simplePaint(colorComponents: topLeft, at: PixelPoint(x: 0, y: 0))
        controller.simplePaint(colorComponents: topRight, at: PixelPoint(x: 2, y: 0))
        controller.simplePaint(colorComponents: bottomLeft, at: PixelPoint(x: 0, y: 2))
        controller.currentOperationPixelPoints.removeAll()

        controller.rotate(to: .left)

        // top-left → bottom-left, top-right → top-left, bottom-left → bottom-right.
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 2)) == topLeft)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == topRight)
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 2)) == bottomLeft)
    }

    @Test func twoRightTurnsRotate180() {
        // The regression guard: a reflection would make this the identity.
        let controller = makeController(width: 3, height: 3)
        let ink = ColorComponents(red: 30, green: 90, blue: 240, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.rotate(to: .right)
        controller.rotate(to: .right)

        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 2)) == ink) // opposite corner
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == .clear)
    }

    @Test func leftAndRightAreInverses() {
        let controller = makeController(width: 4, height: 2)
        let ink = ColorComponents(red: 30, green: 90, blue: 240, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 3, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.rotate(to: .right)
        controller.rotate(to: .left)

        #expect(controller.context.width == 4)
        #expect(controller.context.height == 2)
        #expect(controller.getColorComponents(at: PixelPoint(x: 3, y: 0)) == ink)
        #expect(opaquePixelCount(controller) == 1)
    }
}

@MainActor
struct PaletteRampTests {

    // The RRGGBB special palette shades by a fixed ±255/3 (== 85) per channel,
    // integer math with no HSB float rounding — exact and deterministic.
    private let step = UInt8(255 / 3)

    @Test func rrggbbHighlightAddsAFixedStep() {
        let mid = ColorComponents(red: 100, green: 100, blue: 100, opacity: 255)
        let lit = Palette.rrggbb.highlight(forColorComponents: mid)
        #expect(lit.red == 100 + step)
        #expect(lit.green == 100 + step)
        #expect(lit.blue == 100 + step)
        #expect(lit.opacity == 255)
    }

    @Test func rrggbbHighlightClampsNearWhite() {
        // A channel within one step of 255 saturates rather than overflowing.
        let bright = ColorComponents(red: 250, green: 100, blue: 0, opacity: 255)
        let lit = Palette.rrggbb.highlight(forColorComponents: bright)
        #expect(lit.red == 255)      // clamped
        #expect(lit.green == 100 + step)
        #expect(lit.blue == 0)       // a lone zero channel stays put
    }

    @Test func rrggbbShadowSubtractsAFixedStepAndClampsAtZero() {
        let mid = ColorComponents(red: 100, green: 40, blue: 200, opacity: 255)
        let dark = Palette.rrggbb.shadow(forColorComponents: mid)
        #expect(dark.red == 100 - step)
        #expect(dark.green == 0)      // 40 < step → clamped to 0
        #expect(dark.blue == 200 - step)
        #expect(dark.opacity == 255)
    }

    @Test func rampsPreserveOpacity() {
        let translucent = ColorComponents(red: 120, green: 120, blue: 120, opacity: 128)
        #expect(Palette.rrggbb.highlight(forColorComponents: translucent).opacity == 128)
        #expect(Palette.rrggbb.shadow(forColorComponents: translucent).opacity == 128)
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
