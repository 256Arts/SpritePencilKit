//
//  DocumentController.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-15.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import Combine
import UIKit
import CoreImage.CIFilterBuiltins

@MainActor @Observable
public class DocumentController {

    public enum RotateDirection {
        case left, right
    }

    /// Everything the engine reports, on one bus (see `onEvent(_:)`).
    public enum Event {
        /// The canvas pixels changed (stroke sample, undo, filter, ...).
        case drawingDidChange
        /// The drawing context was swapped for another (load, rotate, trim, or
        /// an undo of either) — everything sized from the canvas is stale.
        case canvasReplaced
        case toolChanged(Tool)
        case symmetryChanged
        case eyedropColor(ColorComponents, point: PixelPoint)
        case usedColor(ColorComponents)
        case refreshUndo
        case didBeginUsingTool
        case didEndUsingTool
        case showColorPalette
    }

    // MARK: Canvas

    /// The current canvas, re-rendered by `refresh()`. Views (or a future
    /// SwiftUI/Metal renderer) observe this instead of being written to.
    public private(set) var renderedImage: UIImage?

    public private(set) var context: CGContext! {
        didSet {
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            contextDataManager = ContextDataManager(context: context)
        }
    }
    @ObservationIgnored var contextDataManager: ContextDataManager!

    // MARK: Drawing configuration

    public var palette: Palette?
    public var toolColorComponents = ColorComponents(red: 0, green: 0, blue: 0, opacity: 255)
    public var verticalSymmetry = false {
        didSet { eventSubject.send(.symmetryChanged) }
    }
    public var horizontalSymmetry = false {
        didSet { eventSubject.send(.symmetryChanged) }
    }
    public var checkeredDrawingMode = false
    public var brushShape: BrushShape = .square {
        didSet { eventSubject.send(.toolChanged(tool)) }
    }
    /// Closes and fills a pencil stroke that ends near its starting point.
    public var shouldFillPaths = false
    public var hoverPoint: PixelPoint?

    // MARK: Stroke state

    /// The pixels painted by the operation in progress, mapped to the colors
    /// they had before it began (the operation's undo diff).
    @ObservationIgnored var currentOperationPixelPoints = [PixelPoint: ColorComponents]()
    /// The stroke's sample points in touch order — the dictionary above loses
    /// ordering, which `fillDrawnPath()` needs to trace the drawn outline.
    @ObservationIgnored var currentOperationOrderedPixelPoints = [PixelPoint]()
    /// The canvas as it was when the current move drag began.
    @ObservationIgnored private var moveBaseImage: CGImage?

    // MARK: Tools

    public var pencilTool = PencilTool(width: 1)
    public var eraserTool = EraserTool(width: 1)
    public var fillTool = FillTool()
    public var moveTool = MoveTool()
    public var highlightTool = HighlightTool(width: 1)
    public var shadowTool = ShadowTool(width: 1)
    public var eyedropperTool = EyedropperTool()
    public var previousTool: Tool = EraserTool(width: 1)
    public var tool: Tool = PencilTool(width: 1) {
        didSet {
            if type(of: tool) != type(of: oldValue) {
                #if !os(visionOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                previousTool = oldValue
            }
            eventSubject.send(.toolChanged(tool))
        }
    }

    // MARK: Undo & events

    weak public var undoManager: UndoManager? {
        didSet {
            // Whole-context replacements (rotate/trim) retain full canvases;
            // an unbounded stack would hold them all forever.
            undoManager?.levelsOfUndo = 50
        }
    }
    let eventSubject = PassthroughSubject<Event, Never>()

    public init() { }

    /// Subscribes `handler` to engine events, which are always published on
    /// the main actor. The subscription lives as long as the returned token.
    public func onEvent(_ handler: @escaping @MainActor (Event) -> Void) -> AnyCancellable {
        eventSubject.sink { event in
            MainActor.assumeIsolated { handler(event) }
        }
    }

    /// Installs the initial canvas. No undo is registered: loading a document
    /// is not an edit.
    public func loadContext(_ newContext: CGContext) {
        context = newContext
        refresh()
        eventSubject.send(.canvasReplaced)
    }

    /// Re-renders `renderedImage` from the context and announces the change.
    public func refresh() {
        guard let context, let image = context.makeImage() else { return }
        renderedImage = UIImage(cgImage: image)
        eventSubject.send(.drawingDidChange)
        eventSubject.send(.refreshUndo)
    }

    // MARK: - Operation lifecycle

    public func beginCurrentOperation() {
        currentOperationOrderedPixelPoints.removeAll()
        eventSubject.send(.didBeginUsingTool)
    }

    /// Registers one pixel-diff undo for everything painted since the
    /// operation began, then clears the stroke state.
    public func commitCurrentOperation() {
        if shouldFillPaths, tool is PencilTool {
            fillDrawnPath()
        }
        if !currentOperationPixelPoints.isEmpty {
            let pixels = currentOperationPixelPoints
            undoManager?.registerUndo(withTarget: self) { target in
                target.archivedPaint(pixels: pixels)
            }
        }
        clearCurrentOperation()
        eventSubject.send(.refreshUndo)
    }

    /// Repaints the operation's pixels back to their previous colors (small
    /// strokes only) and discards the stroke state.
    public func cancelCurrentOperation() {
        if currentOperationIsCancelable, !currentOperationPixelPoints.isEmpty {
            for (point, previousColor) in currentOperationPixelPoints {
                contextDataManager[point] = previousColor
            }
            refresh()
        }
        clearCurrentOperation()
    }

    public func endCurrentOperation() {
        eventSubject.send(.didEndUsingTool)
    }

    /// Whether the operation in progress is small enough to quietly revert
    /// (used to cancel accidental marks when a zoom/undo gesture wins).
    public var currentOperationIsCancelable: Bool {
        let toolSize = tool.size
        return currentOperationPixelPoints.count <= 8 * (toolSize.width * toolSize.height)
    }

    private func clearCurrentOperation() {
        currentOperationPixelPoints.removeAll()
        currentOperationOrderedPixelPoints.removeAll()
    }

    // MARK: - Undo

    public func undo() {
        undoManager?.undo()
        clearCurrentOperation()
        refresh()
    }
    public func redo() {
        undoManager?.redo()
        clearCurrentOperation()
        refresh()
    }

    // MARK: - Painting

    func simplePaint(colorComponents: ColorComponents, at point: PixelPoint) {
        currentOperationPixelPoints[point] = contextDataManager[point]
        contextDataManager[point] = colorComponents
    }

    /// Replays a pixel diff and registers its inverse — the single undo
    /// currency for every in-place edit (strokes, fills, outline).
    func archivedPaint(pixels: [PixelPoint: ColorComponents]) {
        for (point, color) in pixels {
            simplePaint(colorComponents: color, at: point)
        }

        let inversePixels = currentOperationPixelPoints
        undoManager?.registerUndo(withTarget: self) { target in
            target.archivedPaint(pixels: inversePixels)
        }
        clearCurrentOperation()
        eventSubject.send(.refreshUndo)
    }

    public func brushPaint(colorComponents: ColorComponents, at point: PixelPoint, size: PixelSize) {

        let pointInBounds: PixelPoint
        let sizeInBounds: PixelSize
        if size == PixelSize(width: 1, height: 1) {
            guard point.x < context.width, point.y < context.height, 0 <= point.x, 0 <= point.y else { return }
            pointInBounds = point
            sizeInBounds = size
        } else {
            guard point.x < context.width, point.y < context.height, 0 <= point.x + size.width-1, 0 <= point.y + size.height-1 else { return }
            pointInBounds = PixelPoint(x: max(0, point.x), y: max(0, point.y))
            let newWidth = min(size.width - (pointInBounds.x - point.x), (context.width - pointInBounds.x))
            let newHeight = min(size.height - (pointInBounds.y - point.y), (context.height - pointInBounds.y))
            sizeInBounds = PixelSize(width: newWidth, height: newHeight)
        }

        currentOperationOrderedPixelPoints.append(pointInBounds)

        for xOffset in 0..<(sizeInBounds.width) {
            for yOffset in 0..<(sizeInBounds.height) {
                let brushPoint = PixelPoint(x: pointInBounds.x + xOffset, y: pointInBounds.y + yOffset)
                guard !currentOperationPixelPoints.keys.contains(brushPoint) else { continue }
                // Mask against the brush shape using the offset within the full
                // (unclipped) brush, so the circle stays centered at canvas edges.
                guard brushShape.includes(column: brushPoint.x - point.x, row: brushPoint.y - point.y, diameter: size.width) else { continue }

                if !checkeredDrawingMode || (brushPoint.x % 2 != brushPoint.y % 2) {
                    simplePaint(colorComponents: colorComponents, at: brushPoint)
                }
                if horizontalSymmetry {
                    let mirroredY = context.height - brushPoint.y - 1
                    let brushPoint = PixelPoint(x: brushPoint.x, y: mirroredY)
                    if !checkeredDrawingMode || (brushPoint.x % 2 != brushPoint.y % 2) {
                        simplePaint(colorComponents: colorComponents, at: brushPoint)
                    }
                    if verticalSymmetry {
                        let brushPoint = PixelPoint(x: context.width - brushPoint.x - 1, y: mirroredY)
                        if !checkeredDrawingMode || (brushPoint.x % 2 != brushPoint.y % 2) {
                            simplePaint(colorComponents: colorComponents, at: brushPoint)
                        }
                    }
                }
                if verticalSymmetry {
                    let brushPoint = PixelPoint(x: context.width - brushPoint.x - 1, y: brushPoint.y)
                    if !checkeredDrawingMode || (brushPoint.x % 2 != brushPoint.y % 2) {
                        simplePaint(colorComponents: colorComponents, at: brushPoint)
                    }
                }
            }
        }

        if 32 < colorComponents.opacity {
            eventSubject.send(.usedColor(colorComponents))
        }
    }

    private func fillDrawnPath() {
        let points = currentOperationOrderedPixelPoints
        guard 7 <= points.count, let firstPoint = points.first, let lastPoint = points.last else { return }
        guard abs(firstPoint.x - lastPoint.x) <= 1, abs(firstPoint.y - lastPoint.y) <= 1 else { return }

        // Trace the stroke in touch order and fill its interior pixel-by-pixel
        // through simplePaint, so the fill lands in currentOperationPixelPoints
        // and is undone together with the stroke by commitCurrentOperation.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: CGFloat(firstPoint.x) + 0.5, y: CGFloat(firstPoint.y) + 0.5))
        for point in points {
            path.addLine(to: CGPoint(x: CGFloat(point.x) + 0.5, y: CGFloat(point.y) + 0.5))
        }
        path.closeSubpath()

        let box = path.boundingBox
        let minX = max(0, Int(box.minX)), maxX = min(context.width - 1, Int(box.maxX))
        let minY = max(0, Int(box.minY)), maxY = min(context.height - 1, Int(box.maxY))
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let pixel = PixelPoint(x: x, y: y)
                // Skip stroke pixels: repainting them would overwrite their
                // recorded undo colors with the already-painted tool color.
                guard !currentOperationPixelPoints.keys.contains(pixel) else { continue }
                if path.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    simplePaint(colorComponents: toolColorComponents, at: pixel)
                }
            }
        }
    }

    public func eyedrop(at point: PixelPoint) {
        let components = getColorComponents(at: point)
        guard components.opacity == 255 else { return }

        eventSubject.send(.eyedropColor(components, point: point))
    }

    public func getColorComponents(at point: PixelPoint) -> ColorComponents {
        contextDataManager[point]
    }

    // MARK: - Move

    /// Snapshots the canvas; `continueMove(delta:)` offsets are relative to it.
    public func beginMove() {
        moveBaseImage = context.makeImage()
    }

    /// Blits the drag-start snapshot offset by `delta`, wrapping around the
    /// canvas edges.
    public func continueMove(delta: CGSize) {
        guard let baseImage = moveBaseImage else { return }
        context.clear()

        let w = CGFloat(context.width)
        let h = CGFloat(context.height)
        let size = CGSize(width: w, height: h)
        let dx = delta.width
        let dy = delta.height

        // Second copy on each axis creates the seamless wrap-around while dragging.
        let wrapX = dx + (0 < dx ? -1 : 1) * w
        let wrapY = dy + (0 < dy ? -1 : 1) * h

        // CGContext is y-up (origin bottom-left), so the vertical offset is negated
        // relative to the touch delta (y-down).
        for origin in [CGPoint(x: dx, y: -dy),
                       CGPoint(x: wrapX, y: -dy),
                       CGPoint(x: dx, y: -wrapY),
                       CGPoint(x: wrapX, y: -wrapY)] {
            context.draw(baseImage, in: CGRect(origin: origin, size: size))
        }
    }

    public func commitMove(delta: CGSize) {
        continueMove(delta: delta)
        moveBaseImage = nil
        undoManager?.registerUndo(withTarget: self) { target in
            target.archivedMove(deltaPoint: CGSize(width: -delta.width, height: -delta.height))
        }
        refresh()
    }

    func archivedMove(deltaPoint: CGSize) {
        beginMove()
        continueMove(delta: deltaPoint)
        moveBaseImage = nil

        undoManager?.registerUndo(withTarget: self) { target in
            target.archivedMove(deltaPoint: CGSize(width: -deltaPoint.width, height: -deltaPoint.height))
        }
    }

    // MARK: - Shading

    public func highlight(at point: PixelPoint, size: PixelSize) {
        shade(at: point, size: size, using: (palette ?? Palette.sp16).highlight(forColorComponents:))
    }

    public func shadow(at point: PixelPoint, size: PixelSize) {
        shade(at: point, size: size, using: (palette ?? Palette.sp16).shadow(forColorComponents:))
    }

    private func shade(at point: PixelPoint, size: PixelSize, using shade: (ColorComponents) -> ColorComponents) {
        for xOffset in 0..<size.width {
            for yOffset in 0..<size.height {
                guard brushShape.includes(column: xOffset, row: yOffset, diameter: size.width) else { continue }
                let brushPoint = PixelPoint(x: point.x + xOffset, y: point.y + yOffset)
                // Unlike brushPaint's writes, the read below is not clipped to the
                // canvas, so skip out-of-bounds cells of the brush footprint here.
                guard 0 <= brushPoint.x, brushPoint.x < context.width, 0 <= brushPoint.y, brushPoint.y < context.height else { continue }
                guard !currentOperationPixelPoints.keys.contains(brushPoint) else { continue }
                brushPaint(colorComponents: shade(getColorComponents(at: brushPoint)), at: brushPoint, size: PixelSize(width: 1, height: 1))
            }
        }
    }

    // MARK: - Fill

    /// Flood-fills from `startPoint` and commits the result as one operation.
    public func fill(at startPoint: PixelPoint) {
        guard 0 <= startPoint.x, startPoint.x < context.width, 0 <= startPoint.y, startPoint.y < context.height else { return }
        let fillFromColorComponents = getColorComponents(at: startPoint)
        guard fillFromColorComponents != toolColorComponents else { return }

        let maxCheckedPixels = 2048
        var stack = [startPoint]
        var checkedPixels = 0
        while checkedPixels < maxCheckedPixels, let pixelPoint = stack.popLast() {
            if currentOperationPixelPoints.keys.contains(pixelPoint) || (pixelPoint.y < 0 || pixelPoint.y > context.height - 1 || pixelPoint.x < 0 || pixelPoint.x > context.width - 1) {
                continue
            }
            guard getColorComponents(at: pixelPoint) == fillFromColorComponents else { continue }

            simplePaint(colorComponents: toolColorComponents, at: pixelPoint)

            stack += [
                PixelPoint(x: pixelPoint.x+1, y: pixelPoint.y),
                PixelPoint(x: pixelPoint.x-1, y: pixelPoint.y),
                PixelPoint(x: pixelPoint.x, y: pixelPoint.y+1),
                PixelPoint(x: pixelPoint.x, y: pixelPoint.y-1)
            ]

            checkedPixels += 1
        }

        commitCurrentOperation()
        refresh()
    }

    // MARK: - Whole-canvas edits

    public func flip(vertically: Bool) {
        guard let image = context.makeImage() else { return }
        let width = CGFloat(context.width)
        let height = CGFloat(context.height)
        context.clear()
        context.saveGState()
        if vertically {
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        } else {
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()

        // Flipping again is its own inverse (and re-registers the redo).
        undoManager?.registerUndo(withTarget: self) { (target) in
            target.flip(vertically: vertically)
        }
        refresh()
    }

    public func rotate(to direction: RotateDirection) {
        let oldWidth = context.width
        let oldHeight = context.height

        // A 90° turn swaps the canvas dimensions, so we can't rotate in place:
        // draw into a fresh height×width context instead. (For a square canvas
        // the swap is a no-op and the result matches the previous behavior.)
        guard let image = context.makeImage(),
              let newContext = context.makeMatchingContext(width: oldHeight, height: oldWidth) else { return }

        let w = CGFloat(oldWidth)
        let h = CGFloat(oldHeight)
        // Pivot a pure quarter-turn about the shared center of the old (w×h)
        // image and the new (h×w) canvas: translate to the new canvas's center,
        // rotate, then translate back by the old image's center. Right turns
        // clockwise, left counter-clockwise. (The earlier implementation added a
        // leading axis flip, which composed with the turn into a *reflection* —
        // two Rights were a no-op instead of a 180° turn.)
        newContext.translateBy(x: h / 2, y: w / 2)
        newContext.rotate(by: direction == .right ? -.pi / 2 : .pi / 2)
        newContext.translateBy(x: -w / 2, y: -h / 2)
        newContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // replaceContext registers the undo (it swaps the prior context back)
        // and announces the size change.
        replaceContext(with: newContext)
    }

    public func outline(colorComponents: ColorComponents? = nil) {
        var outline = [(point: PixelPoint, neighborColorComponents: ColorComponents)]()
        for y in 0..<context.height {
            for x in 0..<context.width {
                let point = PixelPoint(x: x, y: y)
                let opacity = getColorComponents(at: point).opacity
                if opacity == 0 {
                    // Check if a neighbor has a color. Bounds-check each neighbor
                    // *before* reading it — pixels along the canvas edges would
                    // otherwise read outside the buffer.
                    for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                        let neighbor = PixelPoint(x: x + dx, y: y + dy)
                        guard 0 <= neighbor.x, neighbor.x < context.width, 0 <= neighbor.y, neighbor.y < context.height else { continue }
                        let components = getColorComponents(at: neighbor)
                        if components.opacity != 0 {
                            outline.append((point, components))
                            break
                        }
                    }
                }
            }
        }
        // Paint through simplePaint so the whole outline becomes one pixel-diff
        // undo step (no undo grouping needed).
        for (point, neighborColorComponents) in outline {
            let color = colorComponents ?? (palette ?? Palette.sp16).shadow(forColorComponents: neighborColorComponents)
            simplePaint(colorComponents: color, at: point)
        }
        commitCurrentOperation()
        refresh()
    }

    public func posterize() {
        guard let image = context.makeImage() else { return }
        let filter = CIFilter.colorPosterize()
        filter.inputImage = CIImage(cgImage: image)
        filter.levels = 4
        // UIImage.draw(at:) targets the current UIKit graphics context, which
        // doesn't exist here, so it silently drew nothing (same bug class as
        // the old move()). Render the filter output explicitly instead.
        guard let output = filter.outputImage,
              let posterized = CIContext(options: nil).createCGImage(output, from: CGRect(x: 0, y: 0, width: context.width, height: context.height)) else { return }
        archivedDraw(posterized)
    }

    /// Replaces the canvas contents with `image` and registers the inverse,
    /// giving whole-canvas edits (e.g. filters) symmetric undo/redo.
    private func archivedDraw(_ image: CGImage) {
        guard let previous = context.makeImage() else { return }
        context.clear()
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        undoManager?.registerUndo(withTarget: self) { (target) in
            target.archivedDraw(previous)
        }
        refresh()
    }

    /// Crops away any fully-transparent border, shrinking the canvas to the
    /// bounding box of the drawn pixels.
    public func trimCanvas() {
        let width = context.width
        let height = context.height

        func hasContent(x: Int, y: Int) -> Bool {
            getColorComponents(at: PixelPoint(x: x, y: y)).opacity != 0
        }

        var top: Int?
        findTop: for y in 0..<height {
            for x in 0..<width where hasContent(x: x, y: y) {
                top = y
                break findTop
            }
        }
        // A fully-transparent canvas has no content to trim around.
        guard let top else { return }

        // From here every scan stays inside [0, width) × [top, height), so the
        // out-of-bounds reads of the old `stride(from: count, ...)` are avoided,
        // and the inclusive `top...bottom` ranges no longer drop the edge rows.
        var bottom = top
        findBottom: for y in stride(from: height - 1, through: top, by: -1) {
            for x in 0..<width where hasContent(x: x, y: y) {
                bottom = y
                break findBottom
            }
        }
        var left = 0
        findLeft: for x in 0..<width {
            for y in top...bottom where hasContent(x: x, y: y) {
                left = x
                break findLeft
            }
        }
        var right = width - 1
        findRight: for x in stride(from: width - 1, through: left, by: -1) {
            for y in top...bottom where hasContent(x: x, y: y) {
                right = x
                break findRight
            }
        }

        let trimRect = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        // Content already fills the canvas; trimming would change nothing.
        guard Int(trimRect.width) < width || Int(trimRect.height) < height else { return }

        guard let image = context.makeImage()?.cropping(to: trimRect),
              let newContext = context.makeMatchingContext(width: Int(trimRect.width), height: Int(trimRect.height)) else { return }
        newContext.draw(image, in: CGRect(origin: .zero, size: trimRect.size))

        replaceContext(with: newContext)
    }

    /// Swaps in a context of a different size (trim/rotate), announces the
    /// change, and registers a symmetric undo that restores the previous
    /// context (which in turn registers the redo). Unlike in-place edits, a
    /// resize can't be undone by replaying an inverse diff, so we hold onto
    /// the old context and swap it back.
    private func replaceContext(with newContext: CGContext) {
        let oldContext = context!
        context = newContext
        refresh()
        eventSubject.send(.canvasReplaced)
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceContext(with: oldContext)
        }
    }

    public func export(scale: CGFloat, backgroundColor: UIColor? = nil) -> UIImage? {
        guard let cgImage = context.makeImage() else { return nil }
        let image = UIImage(cgImage: cgImage)
        if scale == 1.0, backgroundColor == nil { return image }

        let scaledImageSize = image.size.applying(CGAffineTransform(scaleX: scale, y: scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: scaledImageSize, format: format)
        let scaledImage = renderer.image { (context) in
            let rect = CGRect(origin: .zero, size: scaledImageSize)
            if let color = backgroundColor {
                color.setFill()
                UIRectFill(rect)
            }
            context.cgContext.interpolationQuality = .none
            image.draw(in: rect)
        }
        return scaledImage
    }

}
