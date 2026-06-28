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
    
    public enum Event {
        case selectTool(Tool)
        case eyedropColor(ColorComponents, point: PixelPoint)
        case refreshUndo
        case usedColor(ColorComponents)
        case hovered(PixelPoint?)
        case painted(context: CGContext, color: UIColor?, point: PixelPoint)
    }
    
    public var context: CGContext! {
        didSet {
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            contextDataManager = ContextDataManager(context: context)
        }
    }
    public var palette: Palette?
    public var toolColorComponents = ColorComponents(red: 0, green: 0, blue: 0, opacity: 255)
    public var currentOperationPixelPoints = [PixelPoint: ColorComponents]()
    public var currentOperationFirstPixelPoint: PixelPoint?
    public var currentOperationLastPixelPoint: PixelPoint?
    public var fillFromColorComponents: ColorComponents?
    public var contextDataManager: ContextDataManager!
    public var verticalSymmetry = false
    public var horizontalSymmetry = false
    public var checkeredDrawingMode = false
    public var brushShape: BrushShape = .square
    public var hoverPoint: PixelPoint? {
        didSet {
            eventPublisher.send(.hovered(hoverPoint))
        }
    }
    
    // Tools
    public var pencilTool = PencilTool(width: 1)
    public var eraserTool = EraserTool(width: 1)
    public var fillTool = FillTool()
    public var moveTool = MoveTool()
    public var highlightTool = HighlightTool(width: 1)
    public var shadowTool = ShadowTool(width: 1)
    public var eyedroperTool = EyedroperTool()
    public var previousTool: Tool = EraserTool(width: 1)
    public var tool: Tool = PencilTool(width: 1) {
        didSet {
            if type(of: tool) != type(of: oldValue) {
                #if !os(visionOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                previousTool = oldValue
            }
            canvasView.toolSizeChanged(size: tool.size)
            eventPublisher.send(.selectTool(tool))
        }
    }
    
    // Delegates
    weak public var undoManager: UndoManager?
    weak public var zoomableView: ZoomableUIView!
    weak public var canvasView: CanvasUIView!
    public var eventPublisher: PassthroughSubject<Event, Never> = .init()
    
    public init() { }
    
    public func refresh() {
        canvasView.events.send(.drawingDidChange)
        let image = UIImage(cgImage: context.makeImage()!)
        canvasView.spriteView.image = image
        canvasView.events.send(.didFinishRendering)
        eventPublisher.send(.refreshUndo)
    }
    
    public func undo() {
        undoManager?.undo()
        currentOperationPixelPoints.removeAll()
        refresh()
    }
    public func redo() {
        undoManager?.redo()
        currentOperationPixelPoints.removeAll()
        refresh()
    }
    
    func simplePaint(colorComponents: ColorComponents, at point: PixelPoint) {
        let cdp = contextDataManager.dataPointer
        let offset = contextDataManager.dataOffset(for: point)
        
        let undoRed = cdp[offset+2]
        let undoGreen = cdp[offset+1]
        let undoBlue = cdp[offset]
        let undoOpacity = cdp[offset+3]
        let undoColor = ColorComponents(red: undoRed, green: undoGreen, blue: undoBlue, opacity: undoOpacity)
        currentOperationPixelPoints[point] = undoColor
        
        cdp[offset+2] = colorComponents.red
        cdp[offset+1] = colorComponents.green
        cdp[offset] = colorComponents.blue
        cdp[offset+3] = colorComponents.opacity
    }
    
    func archivedPaint(pixels: [PixelPoint: ColorComponents]) {
        for (point, color) in pixels {
            simplePaint(colorComponents: color, at: point)
        }
        
        let copp = currentOperationPixelPoints
        undoManager?.registerUndo(withTarget: self, handler: { (target) in
            target.archivedPaint(pixels: copp)
        })
        eventPublisher.send(.refreshUndo)
        currentOperationPixelPoints.removeAll()
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
            eventPublisher.send(.usedColor(colorComponents))
        }
        eventPublisher.send(.painted(context: context, color: UIColor(components: colorComponents), point: point))
    }
    
    public func fillDrawnPath() {
        guard 7 <= currentOperationPixelPoints.count, let firstPoint = currentOperationFirstPixelPoint, let lastPoint = currentOperationLastPixelPoint else { return }
        guard abs(firstPoint.x - lastPoint.x) <= 1, abs(firstPoint.y - lastPoint.y) <= 1 else { return }
        let image = context.makeImage()!
        context.beginPath()
        context.move(to: CGPoint(x: CGFloat(firstPoint.x) + 0.5, y: CGFloat(firstPoint.y) + 0.5))
        for pixelPoint in currentOperationPixelPoints.keys { // ISSUE: points are not in order in Set<>
            context.addLine(to: CGPoint(x: CGFloat(pixelPoint.x) + 0.5, y: CGFloat(pixelPoint.y) + 0.5))
        }
        context.closePath()
        context.fillPath()
        undoManager?.registerUndo(withTarget: self, handler: { (target) in // POSSIBLE ISSUE: I dont think I should be registering undos here anymore
            target.context.clear()
            self.context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: self.context.width, height: self.context.height)))
        })
    }
    
    public func eyedrop(at point: PixelPoint) {
        let components = getColorComponents(at: point)
        guard components.opacity == 255 else { return }
        
        eventPublisher.send(.eyedropColor(components, point: point))
    }
    
    public func getColorComponents(at point: PixelPoint) -> ColorComponents {
        let cdp = contextDataManager.dataPointer
        let offset = contextDataManager.dataOffset(for: point)
        return ColorComponents(red: cdp[offset+2], green: cdp[offset+1], blue: cdp[offset], opacity: cdp[offset+3])
    }
    
    public func move(deltaPoint: CGSize) {
        // Blit the CGImage straight into the pixel buffer. UIImage.draw(at:) can't be
        // used here: it targets the current UIKit graphics context, which no longer
        // exists during a move after the canvas refactor, so it silently drew nothing
        // and left the cleared (blank) context behind.
        guard let cgImage = canvasView.spriteCopy.cgImage else { return }
        context.clear()

        let w = CGFloat(context.width)
        let h = CGFloat(context.height)
        let size = CGSize(width: w, height: h)
        let dx = deltaPoint.width
        let dy = deltaPoint.height

        // Second copy on each axis creates the seamless wrap-around while dragging.
        let wrapX = dx + (0 < dx ? -1 : 1) * w
        let wrapY = dy + (0 < dy ? -1 : 1) * h

        // CGContext is y-up (origin bottom-left), so the vertical offset is negated
        // relative to the touch delta (y-down).
        for origin in [CGPoint(x: dx, y: -dy),
                       CGPoint(x: wrapX, y: -dy),
                       CGPoint(x: dx, y: -wrapY),
                       CGPoint(x: wrapX, y: -wrapY)] {
            context.draw(cgImage, in: CGRect(origin: origin, size: size))
        }
    }
    
    func archivedMove(deltaPoint: CGSize) {
        canvasView.spriteCopy = UIImage(cgImage: context.makeImage()!)
        move(deltaPoint: deltaPoint)
        
        undoManager?.registerUndo(withTarget: self) { (target) in
            target.archivedMove(deltaPoint: CGSize(width: -deltaPoint.width, height: -deltaPoint.height))
        }
    }
    
    public func highlight(at point: PixelPoint, size: PixelSize) {
        for xOffset in 0..<size.width {
            for yOffset in 0..<size.height {
                guard brushShape.includes(column: xOffset, row: yOffset, diameter: size.width) else { continue }
                let brushPoint = PixelPoint(x: point.x + xOffset, y: point.y + yOffset)
                guard !currentOperationPixelPoints.keys.contains(brushPoint) else { continue }
                let highlightComponents = (palette ?? Palette.sp16).highlight(forColorComponents: getColorComponents(at: brushPoint))
                brushPaint(colorComponents: highlightComponents, at: brushPoint, size: PixelSize(width: 1, height: 1))
            }
        }
    }
    
    public func shadow(at point: PixelPoint, size: PixelSize) {
        for xOffset in 0..<size.width {
            for yOffset in 0..<size.height {
                guard brushShape.includes(column: xOffset, row: yOffset, diameter: size.width) else { continue }
                let brushPoint = PixelPoint(x: point.x + xOffset, y: point.y + yOffset)
                guard !currentOperationPixelPoints.keys.contains(brushPoint) else { continue }
                let shadowComponents = (palette ?? Palette.sp16).shadow(forColorComponents: getColorComponents(at: brushPoint))
                brushPaint(colorComponents: shadowComponents, at: brushPoint, size: PixelSize(width: 1, height: 1))
            }
        }
    }
    
    public func fill(at startPoint: PixelPoint) {
        fillFromColorComponents = getColorComponents(at: startPoint)
        guard fillFromColorComponents != toolColorComponents else { return }
        
        let maxCheckedPixels = 2048
        var stack = [startPoint]
        var checkedPixels = 0
        while checkedPixels < maxCheckedPixels {
            guard let pixelPoint = stack.popLast() else { return }
            if currentOperationPixelPoints.keys.contains(pixelPoint) || (pixelPoint.y < 0 || pixelPoint.y > context.height - 1 || pixelPoint.x < 0 || pixelPoint.x > context.width - 1) {
                continue
            }
            guard getColorComponents(at: pixelPoint) == fillFromColorComponents else { continue }
            
            simplePaint(colorComponents: toolColorComponents, at: pixelPoint)
            currentOperationPixelPoints[pixelPoint] = fillFromColorComponents
            
            stack += [
                PixelPoint(x: pixelPoint.x+1, y: pixelPoint.y),
                PixelPoint(x: pixelPoint.x-1, y: pixelPoint.y),
                PixelPoint(x: pixelPoint.x, y: pixelPoint.y+1),
                PixelPoint(x: pixelPoint.x, y: pixelPoint.y-1)
            ]
            
            checkedPixels += 1
        }
        
//        refresh() // Not working
    }
    
    public func flip(vertically: Bool) {
        let image = context.makeImage()!
        context.clear()
        context.saveGState()
        let number: CGFloat = vertically ? 1.0 : -1.0
        
        // FIX (1/2)
        if !vertically {
            let tx = vertically ? 0.0 : CGFloat(context.width)
            let ty = vertically ? CGFloat(context.height) : 0.0
            let flipVertical = CGAffineTransform(a: number, b: 0.0, c: 0.0, d: -number, tx: tx, ty: ty)
            context.concatenate(flipVertical)
        }
        //
        
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: context.width, height: context.height)))
        context.restoreGState()
        
        // FIX (2/2)
        if !vertically {
            let image = context.makeImage()!
            context.clear()
            context.saveGState()
            context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: context.width, height: context.height)))
            context.restoreGState()
        }
        //
        
        undoManager?.registerUndo(withTarget: self) { (target) in
            target.flip(vertically: vertically)
            target.refresh()
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
              let newContext = CGContext(data: nil, width: oldHeight, height: oldWidth, bitsPerComponent: image.bitsPerComponent, bytesPerRow: 0, space: context.colorSpace!, bitmapInfo: image.alphaInfo.rawValue) else { return }

        let w = CGFloat(oldWidth)
        let h = CGFloat(oldHeight)
        // The leading translate/scale is the vertical (left) or horizontal
        // (right) flip across the *new* canvas; the centered translates pivot the
        // quarter-turn about each context's own center so rectangles stay framed.
        switch direction {
        case .left:
            newContext.translateBy(x: 0, y: w)
            newContext.scaleBy(x: 1, y: -1)
        case .right:
            newContext.translateBy(x: h, y: 0)
            newContext.scaleBy(x: -1, y: 1)
        }
        newContext.translateBy(x: h / 2, y: w / 2)
        newContext.rotate(by: .pi / 2)
        newContext.translateBy(x: -w / 2, y: -h / 2)
        newContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // replaceContext registers the undo (it swaps the prior context back) and
        // resizes the canvas/zoom for the new dimensions.
        replaceContext(with: newContext)
    }
    
    public func outline(colorComponents: ColorComponents? = nil) {
        var outline = [(point: PixelPoint, neighborColorComponents: ColorComponents)]()
        for y in 0..<context.height {
            for x in 0..<context.width {
                let point = PixelPoint(x: x, y: y)
                let opacity = getColorComponents(at: point).opacity
                if opacity == 0 {
                    // Check if a neighbor has a color
                    let componentsAbove = getColorComponents(at: PixelPoint(x: x, y: y+1))
                    if y+1 < context.height, componentsAbove.opacity != 0 {
                        outline.append((point, componentsAbove))
                        continue
                    }
                    let componentsRight = getColorComponents(at: PixelPoint(x: x+1, y: y))
                    if x+1 < context.width, componentsRight.opacity != 0 {
                        outline.append((point, componentsRight))
                        continue
                    }
                    let componentsBelow = getColorComponents(at: PixelPoint(x: x, y: y-1))
                    if 0 <= y-1, componentsBelow.opacity != 0 {
                        outline.append((point, componentsBelow))
                        continue
                    }
                    let componentsLeft = getColorComponents(at: PixelPoint(x: x-1, y: y))
                    if 0 <= x-1, componentsLeft.opacity != 0 {
                        outline.append((point, componentsLeft))
                        continue
                    }
                }
            }
        }
        undoManager?.beginUndoGrouping()
        if let colorComponents = colorComponents {
            for point in outline {
                undoManager?.registerUndo(withTarget: self, handler: { (target) in
                    target.simplePaint(colorComponents: .clear, at: point.point)
                })
                simplePaint(colorComponents: colorComponents, at: point.point)
            }
        } else {
            // Automatic color
            for point in outline {
                let shadowColor = (palette ?? Palette.sp16).shadow(forColorComponents: point.neighborColorComponents)
                undoManager?.registerUndo(withTarget: self, handler: { (target) in
                    target.simplePaint(colorComponents: .clear, at: point.point)
                })
                simplePaint(colorComponents: shadowColor, at: point.point)
            }
        }
        undoManager?.endUndoGrouping()
        currentOperationPixelPoints.removeAll()
        refresh()
    }
    
    public func posterize() {
        guard let image = context.makeImage() else { return }
        let filter = CIFilter.colorPosterize()
        filter.inputImage = CIImage(cgImage: image)
        filter.levels = 4
        let newImage = UIImage(ciImage: filter.outputImage!)
        newImage.draw(at: .zero)
        
        undoManager?.registerUndo(withTarget: self, handler: { (target) in
            UIImage(cgImage: image).draw(at: .zero)
            target.refresh()
        })
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
              let newContext = CGContext(data: nil, width: Int(trimRect.width), height: Int(trimRect.height), bitsPerComponent: image.bitsPerComponent, bytesPerRow: image.bytesPerRow, space: context.colorSpace!, bitmapInfo: image.alphaInfo.rawValue) else { return }
        newContext.draw(image, in: CGRect(origin: .zero, size: trimRect.size))

        replaceContext(with: newContext)
    }

    /// Swaps in a context of a different size (trim/resize), refreshes the
    /// canvas, and registers a symmetric undo that restores the previous context
    /// (which in turn registers the redo). Unlike in-place edits, a resize can't
    /// be undone by replaying the inverse operation, so we hold onto the old
    /// context and swap it back.
    private func replaceContext(with newContext: CGContext) {
        let oldContext = context!
        context = newContext
        refresh()
        canvasView.makeCheckerboard()
        // The scroll view sizes its content from `spriteCopy`; keep it in sync
        // with the new canvas size before fitting, or panning/centering use the
        // stale dimensions.
        zoomableView.spriteCopy = UIImage(cgImage: newContext.makeImage()!)
        zoomableView.zoomToFit()
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
