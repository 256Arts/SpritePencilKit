//
//  DocumentController.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2018-10-15.
//  Copyright © 2018 Jayden Irwin. All rights reserved.
//

import UIKit
import CoreImage.CIFilterBuiltins

public protocol ToolDelegate: AnyObject {
    func selectTool(_ tool: Tool)
}
public protocol EditorDelegate: AnyObject {
    var hoverPoint: PixelPoint? { get set }
    func eyedropColor(colorComponents components: ColorComponents, at point: PixelPoint)
    func refreshUndo()
}
public protocol RecentColorDelegate: AnyObject {
    func usedColor(components: ColorComponents)
}
public protocol PaintParticlesDelegate: AnyObject {
    func painted(context: CGContext, color: UIColor?, at point: PixelPoint)
}

public class DocumentController {
    
    public enum RotateDirection {
        case left, right
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
    public var hoverPoint: PixelPoint? {
        didSet {
            editorDelegate?.hoverPoint = hoverPoint
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
                UISelectionFeedbackGenerator().selectionChanged()
                previousTool = oldValue
            }
            switch tool {
            case let pencil as PencilTool:
                canvasView.toolSizeChanged(size: pencil.size)
            case let eraser as EraserTool:
                canvasView.toolSizeChanged(size: eraser.size)
            case is FillTool:
                canvasView.toolSizeChanged(size: PixelSize(width: 1, height: 1))
            case is MoveTool:
                canvasView.toolSizeChanged(size: PixelSize(width: 1, height: 1))
            case let highlight as HighlightTool:
                canvasView.toolSizeChanged(size: highlight.size)
            case let shadow as ShadowTool:
                canvasView.toolSizeChanged(size: shadow.size)
            case is EyedroperTool:
                canvasView.toolSizeChanged(size: PixelSize(width: 1, height: 1))
            default:
                canvasView.toolSizeChanged(size: PixelSize(width: 1, height: 1))
            }
            toolDelegate?.selectTool(tool)
        }
    }
    
    // Delegates
    weak public var undoManager: UndoManager?
    weak public var recentColorDelegate: RecentColorDelegate?
    weak public var toolDelegate: ToolDelegate?
    weak public var editorDelegate: EditorDelegate?
    weak public var paintParticlesDelegate: PaintParticlesDelegate?
    weak public var canvasView: CanvasView!
    
    public init(canvasView: CanvasView) {
        self.canvasView = canvasView
    }
    
    public func refresh() {
        canvasView.canvasDelegate?.canvasViewDrawingDidChange(canvasView)
        let image = UIImage(cgImage: context.makeImage()!)
        canvasView.spriteView.image = image
        canvasView.canvasDelegate?.canvasViewDidFinishRendering(canvasView)
        editorDelegate?.refreshUndo()
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
        editorDelegate?.refreshUndo()
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
            recentColorDelegate?.usedColor(components: colorComponents)
        }
        paintParticlesDelegate?.painted(context: context, color: UIColor(components: colorComponents), at: point)
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
        
        editorDelegate?.eyedropColor(colorComponents: components, at: point)
    }
    
    public func getColorComponents(at point: PixelPoint) -> ColorComponents {
        let cdp = contextDataManager.dataPointer
        let offset = contextDataManager.dataOffset(for: point)
        return ColorComponents(red: cdp[offset+2], green: cdp[offset+1], blue: cdp[offset], opacity: cdp[offset+3])
    }
    
    public func move(deltaPoint: CGSize) {
        context.clear()
        let newOrigin = CGPoint(x: deltaPoint.width, y: deltaPoint.height)
        canvasView.spriteCopy.draw(at: newOrigin)
        
        // Draw 3 more times to create seemless loop
        let x = deltaPoint.width + (0 < deltaPoint.width ? -1 : 1) * CGFloat(context.width)
        let y = deltaPoint.height + (0 < deltaPoint.height ? -1 : 1) * CGFloat(context.height)
        
        canvasView.spriteCopy.draw(at: CGPoint(x: x, y: deltaPoint.height))
        canvasView.spriteCopy.draw(at: CGPoint(x: deltaPoint.width, y: y))
        canvasView.spriteCopy.draw(at: CGPoint(x: x, y: y))
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
        // iOS 13 BUG?
        // The bug is that the context will flip vertically every time, even when you dont ask it to.
//        let tx = vertically ? 0.0 : CGFloat(context.width)
//        let ty = vertically ? CGFloat(context.height) : 0.0
//        let flipVertical = CGAffineTransform(a: number, b: 0.0, c: 0.0, d: -number, tx: tx, ty: ty)
//        context.concatenate(flipVertical)
        
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
        let image = context.makeImage()!
        context.saveGState()
        context.clear()
        // iOS 13 BUG?
        // The bug is that the context will flip vertically every time, even when you dont ask it to.
//        context.translateBy(x: CGFloat(context.width)/2.0, y: CGFloat(context.height)/2.0)
//        context.rotate(by: CGFloat.pi / (direction == .right ? 2.0 : -2.0))
//        context.draw(image, in: CGRect(origin: CGPoint(x: -context.width/2, y: -context.height/2), size: CGSize(width: context.width, height: context.height)))
        
        // FIX
        let number: CGFloat = direction == .left ? 1.0 : -1.0
        let tx = direction == .left ? 0.0 : CGFloat(context.width)
        let ty = direction == .left ? CGFloat(context.height) : 0.0
        context.translateBy(x: tx, y: ty)
        context.scaleBy(x: number, y: -number)
        context.translateBy(x: CGFloat(context.width)/2, y: CGFloat(context.height)/2)
        context.rotate(by: .pi/2)
        context.translateBy(x: CGFloat(-context.width)/2, y: CGFloat(-context.height)/2)
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: context.width, height: context.height)))
        //
        
        context.restoreGState()
        
        undoManager?.registerUndo(withTarget: self) { (target) in
            target.rotate(to: direction == .left ? .right : .left)
            target.refresh()
        }
        refresh()
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
    
    public func trimCanvas() {
        var top: Int?
        findTop: for y in 0..<Int(context.height) {
            for x in 0..<Int(context.width) {
                let point = PixelPoint(x: x, y: y)
                if getColorComponents(at: point).opacity != 0 {
                    top = y
                    break findTop
                }
            }
        }
        guard top != nil else { return }
        var bottom = 0
        findBottom: for y in stride(from: Int(context.height), to: 0, by: -1) {
            for x in 0..<Int(context.width) {
                let point = PixelPoint(x: x, y: y)
                if getColorComponents(at: point).opacity != 0 {
                    bottom = y
                    break findBottom
                }
            }
        }
        var left = 0
        findLeft: for x in 0..<Int(context.width) {
            for y in top!..<bottom {
                let point = PixelPoint(x: x, y: y)
                if getColorComponents(at: point).opacity != 0 {
                    left = x
                    break findLeft
                }
            }
        }
        var right = 0
        findRight: for x in stride(from: Int(context.width), to: 0, by: -1) {
            for y in top!..<bottom {
                let point = PixelPoint(x: x, y: y)
                if getColorComponents(at: point).opacity != 0 {
                    right = x
                    break findRight
                }
            }
        }
        let trimRect = CGRect(x: left, y: top!, width: right-left+1, height: bottom-top!+1)
        
        guard let image = context.makeImage()?.cropping(to: trimRect), let context = CGContext(data: nil, width: Int(trimRect.width), height: Int(trimRect.height), bitsPerComponent: image.bitsPerComponent, bytesPerRow: image.bytesPerRow, space: context.colorSpace!, bitmapInfo: image.alphaInfo.rawValue) else { return }
        context.draw(image, in: CGRect(origin: .zero, size: trimRect.size))
        self.context = context
        refresh()
        canvasView.makeCheckerboard()
        canvasView.zoomToFit()
        undoManager?.registerUndo(withTarget: self, handler: { (target) in
            //
        })
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
