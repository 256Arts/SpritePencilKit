//
//  SpritePencilKitTests.swift
//  Sprite Pencil
//
//  Regression coverage for the 1.6.2 correctness fixes: edge-of-canvas reads,
//  the ColorComponents Hashable contract, buffer offset math, and pixel-format
//  preservation across context recreation.
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

@MainActor
private func makeController(width: Int, height: Int) -> (DocumentController, CanvasUIView) {
    let controller = DocumentController()
    controller.context = makeSpriteContext(width: width, height: height)
    // canvasView is weak, so the canvas must stay alive for the test's duration.
    let canvas = CanvasUIView(documentController: controller)
    controller.canvasView = canvas
    return (controller, canvas)
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
        let (controller, canvas) = makeController(width: 3, height: 3)
        let color = ColorComponents(red: 10, green: 20, blue: 30, opacity: 255)
        controller.simplePaint(colorComponents: color, at: PixelPoint(x: 2, y: 1))
        #expect(controller.getColorComponents(at: PixelPoint(x: 2, y: 1)) == color)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
        _ = canvas
    }

    @Test func outlineStopsAtCanvasEdges() {
        // A single colored pixel in the corner of a 2×2 canvas: outlining must
        // not read past the edges, and must outline exactly its two neighbors.
        let (controller, canvas) = makeController(width: 2, height: 2)
        let ink = ColorComponents(red: 200, green: 50, blue: 50, opacity: 255)
        controller.simplePaint(colorComponents: ink, at: PixelPoint(x: 0, y: 0))
        controller.currentOperationPixelPoints.removeAll()

        controller.outline(colorComponents: ColorComponents(red: 0, green: 0, blue: 0, opacity: 255))

        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 0)) == ink)
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 0)).opacity == 255)
        #expect(controller.getColorComponents(at: PixelPoint(x: 0, y: 1)).opacity == 255)
        // Not adjacent to the ink at collection time — stays clear.
        #expect(controller.getColorComponents(at: PixelPoint(x: 1, y: 1)) == .clear)
        _ = canvas
    }

    @Test func shadeToolsSkipOutOfBoundsCellsOfTheBrush() {
        // A 3×3 highlight/shadow stamp whose footprint hangs off every edge of
        // a 2×2 canvas: out-of-bounds cells must be skipped, in-bounds painted.
        let (controller, canvas) = makeController(width: 2, height: 2)
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
        _ = canvas
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
