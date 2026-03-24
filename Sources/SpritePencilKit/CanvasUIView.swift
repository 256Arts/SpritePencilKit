import UIKit
import CoreImage.CIFilterBuiltins
import Combine

public enum CanvasViewEvent {
    case drawingDidChange
    case didFinishRendering
    case didBeginUsingTool
    case didEndUsingTool
    case showColorPalette
}

/// A checkerboard canvas that can be drawn on
public class CanvasUIView: UIImageView, UIGestureRecognizerDelegate {
    
    static let hoverViewBorderWidth: CGFloat = 0.1
    
    public enum FingerAction: String {
        case draw, move, eyedrop, ignore
    }
    
    // Delegates & Views
    public weak var documentController: DocumentController!
    var spriteView = UIImageView()
    var hoverView = UIView()
    var toolSizeCopy = PixelSize(width: 1, height: 1)
    
    // Single stream of CanvasView events
    public let events = PassthroughSubject<CanvasViewEvent, Never>()
    
    // Grids
    public var pixelGridEnabled = false
    public var tileGridEnabled = false
    var tileGridLayer: CAShapeLayer?
    var pixelGridLayer: CAShapeLayer?
    var verticalSymmetryLineLayer: CALayer?
    var horizontalSymmetryLineLayer: CALayer?
    
    // Style
    public var checkerboardColor1: UIColor = .systemGray4
    public var checkerboardColor2: UIColor = .systemGray5
    public var tileGridColor: UIColor = .systemGray3
    public var pixelGridColor: UIColor = .systemGray3
    
    // General
    public override var undoManager: UndoManager? {
        documentController.undoManager
    }
    public var tool: Tool {
        get {
            documentController.tool
        }
        set {
            documentController.tool = newValue
        }
    }
    public var nonDrawingFingerAction = FingerAction.ignore
    var fingerAction: FingerAction {
        #if os(visionOS)
        .draw
        #else
        if UIPencilInteraction.prefersPencilOnlyDrawing && applePencilUsed {
            nonDrawingFingerAction
        } else {
            .draw
        }
        #endif
    }
    public var twoFingerUndoEnabled = true
    var applePencilUsed = false
    public var applePencilCanEyedrop = true
    public var shouldFillPaths = false
    public var shouldRecognizeGesturesSimultaneously = true
    
    #if targetEnvironment(macCatalyst)
    // BUG: Catalyst requires scale = 1 for unknown reason
    var spriteZoomScale: CGFloat = 1.0 { // Sprite view is normally 2x scale of checkerboard view
        didSet {
            toolSizeChanged(size: toolSizeCopy)
        }
    }
    #else
    public var spriteZoomScale: CGFloat = 2.0 { // Sprite view is normally 2x scale of checkerboard view
        didSet {
            toolSizeChanged(size: toolSizeCopy)
        }
    }
    #endif
    
    var dragStartPoint: CGPoint?
    var spriteCopy: UIImage!
    
    public init(documentController: DocumentController) {
        self.documentController = documentController
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setupView() {
        #if !os(visionOS)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
        #endif
        
        layer.magnificationFilter = .nearest
        translatesAutoresizingMaskIntoConstraints = false
        
        spriteView.layer.magnificationFilter = .nearest
        spriteView.translatesAutoresizingMaskIntoConstraints = false
        
        hoverView.layer.borderWidth = Self.hoverViewBorderWidth
        hoverView.layer.borderColor = UIColor.label.cgColor
        hoverView.isHidden = true
        hoverView.frame.size = CGSize(width: spriteZoomScale + Self.hoverViewBorderWidth/2, height: spriteZoomScale + Self.hoverViewBorderWidth/2)
        
        addSubview(spriteView)
        spriteView.addSubview(hoverView)
        
        NSLayoutConstraint.activate([
            spriteView.topAnchor.constraint(equalTo: self.topAnchor),
            spriteView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            spriteView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            spriteView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
        
        let draw = DrawGestureRecognizer(target: self, action: #selector(drawGesture))
        draw.minimumPressDuration = 0
        draw.allowableMovement = .greatestFiniteMagnitude
        draw.delegate = self
        let undo = UISwipeGestureRecognizer(target: self, action: #selector(doUndo))
        undo.direction = .left
        undo.numberOfTouchesRequired = 3
        let redo = UISwipeGestureRecognizer(target: self, action: #selector(doRedo))
        redo.direction = .right
        redo.numberOfTouchesRequired = 3
        let undoAlternative = UITapGestureRecognizer(target: self, action: #selector(doUndoForAltGesture))
        undoAlternative.numberOfTouchesRequired = 2
        let redoAlternative = UITapGestureRecognizer(target: self, action: #selector(doRedoForAltGesture))
        redoAlternative.numberOfTouchesRequired = 3
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverGesture(with:)))
        addGestureRecognizer(draw)
        addGestureRecognizer(undo)
        addGestureRecognizer(redo)
        addGestureRecognizer(redoAlternative)
        addGestureRecognizer(undoAlternative)
        addGestureRecognizer(hover)
        
        documentController.refresh()
        makeCheckerboard()
		isUserInteractionEnabled = true
	}
    
    public func makeCheckerboard() {
        let checkers = CIFilter.checkerboardGenerator()
        checkers.color0 = CIColor(color: checkerboardColor1)
        checkers.color1 = CIColor(color: checkerboardColor2)
        checkers.width = 1.0
        // TODO: Re-enable this for catalyst
        // BUG: "checkers.outputImage" causes NSArray crash
        #if targetEnvironment(macCatalyst)
        let image = CIImage()
        checkerboardView.backgroundColor = checkerboardColor1
        #else
        guard let image = checkers.outputImage else { return }
        #endif
        guard let documentContext = documentController.context else { return }
        
        let minimumCheckerboardPixelSize: CGFloat = 4.0
        let checkerboardPixelSize = safeAreaLayoutGuide.layoutFrame.width / (CGFloat(documentContext.width) * spriteZoomScale)
        if checkerboardPixelSize < minimumCheckerboardPixelSize {
            spriteZoomScale = 1.0
        }
        
        let width = CGFloat(documentContext.width) * spriteZoomScale
        let height = CGFloat(documentContext.height) * spriteZoomScale
        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        let ciContext = CIContext(options: nil)
        guard let cgImage = ciContext.createCGImage(image, from: rect) else { return }
        self.image = UIImage(cgImage: cgImage)
    }
    
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            makeCheckerboard()
        }
    }
    
    public func toolSizeChanged(size: PixelSize) {
        toolSizeCopy = size
        hoverView.bounds.size.width = CGFloat(size.width) * spriteZoomScale + Self.hoverViewBorderWidth/2
        hoverView.bounds.size.height = CGFloat(size.height) * spriteZoomScale + Self.hoverViewBorderWidth/2
    }
    
    public func drawnPointsAreCancelable() -> Bool {
//        guard !documentController.currentOperationPixelPoints.isEmpty else { return false }
        let toolSize: PixelSize
        switch tool {
        case let pencil as PencilTool:
            toolSize = pencil.size
        case let eraser as EraserTool:
            toolSize = eraser.size
        case let highlight as HighlightTool:
            toolSize = highlight.size
        case let shadow as ShadowTool:
            toolSize = shadow.size
        default:
            toolSize = PixelSize(width: 1, height: 1)
        }
        let maximumCancelableDrawnPoints = 8 * (toolSize.width * toolSize.height)
        return (documentController.currentOperationPixelPoints.count <= maximumCancelableDrawnPoints)
    }
    
    public func refreshGrid() {
        let documentWidth = documentController.context.width
        let documentHeight = documentController.context.height
        
        if tileGridEnabled {
            if tileGridLayer == nil {
                let tileSize = 16
                let tileScaleFactor = spriteZoomScale * CGFloat(tileSize)
                let path = UIBezierPath()
                for row in 0...(documentHeight / tileSize) {
                    let y = CGFloat(row) * tileScaleFactor
                    let start = CGPoint(x: 0, y: y)
                    let end = CGPoint(x: CGFloat(documentWidth) * spriteZoomScale, y: y)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                for column in 0...(documentWidth / tileSize) {
                    let x = CGFloat(column) * tileScaleFactor
                    let start = CGPoint(x: x, y: 0)
                    let end = CGPoint(x: x, y: CGFloat(documentHeight) * spriteZoomScale)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                path.close()
                tileGridLayer = CAShapeLayer()
                tileGridLayer?.lineWidth = 0.2
                tileGridLayer?.path = path.cgPath
                tileGridLayer?.strokeColor = tileGridColor.cgColor
                spriteView.layer.addSublayer(tileGridLayer!)
            }
        } else {
            tileGridLayer?.removeFromSuperlayer()
            tileGridLayer = nil
        }
        if pixelGridEnabled {
            if pixelGridLayer == nil {
                let pixelScaleFactor = spriteZoomScale
                let path = UIBezierPath()
                for row in 0...documentHeight {
                    let y = CGFloat(row) * pixelScaleFactor
                    let start = CGPoint(x: 0, y: y)
                    let end = CGPoint(x: CGFloat(documentWidth) * spriteZoomScale, y: y)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                for column in 0...documentWidth {
                    let x = CGFloat(column) * pixelScaleFactor
                    let start = CGPoint(x: x, y: 0)
                    let end = CGPoint(x: x, y: CGFloat(documentHeight) * spriteZoomScale)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                path.close()
                pixelGridLayer = CAShapeLayer()
                #if os(visionOS)
                pixelGridLayer?.lineWidth = 0.1
                #else
                pixelGridLayer?.lineWidth = (0.1 / UIScreen.main.scale)
                #endif
                pixelGridLayer?.path = path.cgPath
                pixelGridLayer?.strokeColor = pixelGridColor.cgColor
                spriteView.layer.addSublayer(pixelGridLayer!)
            }
        } else {
            pixelGridLayer?.removeFromSuperlayer()
            pixelGridLayer = nil
        }
        if documentController.verticalSymmetry {
            if verticalSymmetryLineLayer == nil {
                verticalSymmetryLineLayer = CALayer()
                verticalSymmetryLineLayer?.frame = CGRect(x: (CGFloat(documentWidth) * spriteZoomScale/2.0) - 0.1, y: 0, width: 0.2, height: CGFloat(documentHeight) * spriteZoomScale)
                verticalSymmetryLineLayer?.borderWidth = 0.2
                verticalSymmetryLineLayer?.borderColor = tintColor.cgColor
                spriteView.layer.addSublayer(verticalSymmetryLineLayer!)
            }
        } else {
            verticalSymmetryLineLayer?.removeFromSuperlayer()
            verticalSymmetryLineLayer = nil
        }
        if documentController.horizontalSymmetry {
            if horizontalSymmetryLineLayer == nil {
                horizontalSymmetryLineLayer = CALayer()
                horizontalSymmetryLineLayer?.frame = CGRect(x: 0, y: (CGFloat(documentHeight) * spriteZoomScale/2.0) - 0.1, width: CGFloat(documentWidth) * spriteZoomScale, height: 0.2)
                horizontalSymmetryLineLayer?.borderWidth = 0.2
                horizontalSymmetryLineLayer?.borderColor = tintColor.cgColor
                spriteView.layer.addSublayer(horizontalSymmetryLineLayer!)
            }
        } else {
            horizontalSymmetryLineLayer?.removeFromSuperlayer()
            horizontalSymmetryLineLayer = nil
        }
    }
    
    public func makePixelPoint(touchLocation: CGPoint, toolSize: PixelSize) -> PixelPoint {
        let xOffset = CGFloat(toolSize.width-1) / 2
        let yOffset = CGFloat(toolSize.height-1) / 2
        // Returns the top left pixel of the rect of pixels.
        return PixelPoint(x: Int(floor((touchLocation.x / spriteZoomScale) - xOffset)), y: Int(floor((touchLocation.y / spriteZoomScale) - yOffset)))
    }
    
    @objc public func doUndo() {
        if 0 < documentController.undoManager?.groupingLevel ?? 0 {
            documentController.undoManager?.endUndoGrouping()
            documentController.undoManager?.undo()
        }
        documentController.undo()
    }
    @objc public func doRedo() {
        if 0 < documentController.undoManager?.groupingLevel ?? 0 {
            documentController.undoManager?.endUndoGrouping()
        }
        documentController.redo()
    }
    @objc public func doUndoForAltGesture() {
        if twoFingerUndoEnabled, drawnPointsAreCancelable() {
            doUndo()
        }
    }
    @objc public func doRedoForAltGesture() {
        if twoFingerUndoEnabled, drawnPointsAreCancelable() {
            doRedo()
        }
    }
    
    // MARK: - Touches & Hover
    
    @objc public func hoverGesture(with recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let touchLocation = recognizer.location(in: spriteView)
            let point = makePixelPoint(touchLocation: touchLocation, toolSize: toolSizeCopy)
            updateHoverLocation(at: point)
        case .ended, .cancelled:
            hoverView.isHidden = true
        default:
            break
        }
    }
    
    func updateHoverLocation(at point: PixelPoint) {
        guard 0 <= point.x, 0 <= point.y, point.x < documentController.context.width, point.y < documentController.context.height else {
            hoverView.isHidden = true
            documentController.hoverPoint = nil
            return
        }
        hoverView.frame.origin.x = CGFloat(point.x) * spriteZoomScale - Self.hoverViewBorderWidth/2
        hoverView.frame.origin.y = CGFloat(point.y) * spriteZoomScale - Self.hoverViewBorderWidth/2
        hoverView.isHidden = false
        documentController.hoverPoint = point
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldRecognizeGesturesSimultaneously
    }
    
    @objc func drawGesture(_ gesture: DrawGestureRecognizer) {
        switch gesture.state {
        case .possible:
            break
        case .began:
            guard let touch = gesture.currentTouches.first else { return }
            
            switch touch.type {
            case .pencil:
                applePencilUsed = true
                if !applePencilCanEyedrop, tool is EyedroperTool {
                    tool = documentController.pencilTool
                }
            default:
                switch fingerAction {
                case .move:
                    tool = MoveTool()
                case .eyedrop:
                    tool = EyedroperTool()
                default:
                    break
                }
            }
            
            guard validateTouchesForCurrentTool(gesture.currentTouches) else { return }
            
            switch tool {
            case is EyedroperTool, is FillTool:
                break
            case is MoveTool:
                spriteCopy = UIImage(cgImage: documentController.context.makeImage()!)
                dragStartPoint = touch.location(in: spriteView)
            default:
                let touchLocation = touch.location(in: spriteView)
                let point = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                documentController.currentOperationFirstPixelPoint = point
            }
            events.send(.didBeginUsingTool)
            if let coalesced = gesture.currentEvent?.coalescedTouches(for: touch) {
                addSamples(for: coalesced)
            }
        case .changed:
            guard let touch = gesture.currentTouches.first, validateTouchesForCurrentTool(gesture.currentTouches) else {
                return
            }
            
            if let coalesced = gesture.currentEvent?.coalescedTouches(for: touch) {
                addSamples(for: coalesced)
            }
        case .ended:
            guard let touch = gesture.currentTouches.first, validateTouchesForCurrentTool(gesture.currentTouches) else {
                return
            }
            
            switch tool {
            case is EyedroperTool:
                let location = touch.location(in: spriteView)
                let point = makePixelPoint(touchLocation: location, toolSize: PixelSize(width: 1, height: 1))
                documentController.eyedrop(at: point)
            default:
                if let coalesced = gesture.currentEvent?.coalescedTouches(for: touch) {
                    addSamples(for: coalesced)
                }
                let touchLocation = touch.location(in: spriteView)
                let point = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                documentController.currentOperationLastPixelPoint = point
                
                switch tool {
                case is PencilTool:
                    if shouldFillPaths {
                        documentController.fillDrawnPath()
                    }
                    
                    let copp = documentController.currentOperationPixelPoints
                    documentController.undoManager?.registerUndo(withTarget: documentController, handler: { (target) in
                        target.archivedPaint(pixels: copp)
                    })
                    documentController.eventPublisher.send(.refreshUndo)
                    documentController.currentOperationPixelPoints.removeAll()
                case is MoveTool:
                    guard let dragStartPoint = dragStartPoint else { return }
                    moveViaTouchLocation(touchLocation)
                    
                    let undoDeltaPoint = delta(start: touchLocation, end: dragStartPoint)
                    documentController.undoManager?.registerUndo(withTarget: documentController) { (target) in
                        target.archivedMove(deltaPoint: undoDeltaPoint)
                    }
                    documentController.eventPublisher.send(.refreshUndo)
                case is FillTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                    documentController.fill(at: point)
                    
                    let copp = documentController.currentOperationPixelPoints
                    documentController.undoManager?.registerUndo(withTarget: documentController, handler: { (target) in
                        target.archivedPaint(pixels: copp)
                    })
                    documentController.eventPublisher.send(.refreshUndo)
                    documentController.currentOperationPixelPoints.removeAll()
                    documentController.refresh()
                default:
                    let copp = documentController.currentOperationPixelPoints
                    documentController.undoManager?.registerUndo(withTarget: documentController, handler: { (target) in
                        target.archivedPaint(pixels: copp)
                    })
                    documentController.eventPublisher.send(.refreshUndo)
                    documentController.currentOperationPixelPoints.removeAll()
                }
                
                switch touch.type {
                case .pencil:
                    break
                default:
                    if fingerAction == .move {
                        tool = documentController.previousTool
                    }
                }
                hoverView.isHidden = true
                documentController.hoverPoint = nil
                documentController.currentOperationFirstPixelPoint = nil
                documentController.currentOperationLastPixelPoint = nil
            }
            events.send(.didEndUsingTool)
        case .cancelled:
            guard validateTouchesForCurrentTool(gesture.currentTouches) else { return }
            let shouldRemoveDrawnPoints = drawnPointsAreCancelable() && !documentController.currentOperationPixelPoints.isEmpty
            
            hoverView.isHidden = true
            documentController.hoverPoint = nil
            
            if shouldRemoveDrawnPoints {
                for (point, prevColor) in documentController.currentOperationPixelPoints {
                    documentController.simplePaint(colorComponents: prevColor, at: point)
                }
                documentController.refresh()
            }
            documentController.currentOperationPixelPoints.removeAll()
            
            events.send(.didEndUsingTool)
        case .failed:
            break
        case .recognized:
            break
        @unknown default:
            fatalError()
        }
    }
    
    public func validateTouchesForCurrentTool(_ touches: Set<UITouch>) -> Bool {
        switch touches.first?.type {
        case .pencil?:
            return true
        default:
            #if os(visionOS)
            return true
            #else
            if UIPencilInteraction.prefersPencilOnlyDrawing && applePencilUsed {
                switch tool {
                case is EyedroperTool:
                    return fingerAction == .eyedrop
                case is MoveTool:
                    return fingerAction == .move
                default:
                    return false
                }
            } else {
                return true
            }
            #endif
        }
    }
    
    public func addSamples(for touches: [UITouch]) {
        switch tool {
        case is PencilTool, is EraserTool, is MoveTool, is HighlightTool, is ShadowTool:
            for touch in touches {
                let touchLocation = touch.location(in: spriteView)
                switch tool {
                case let pencil as PencilTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: pencil.size)
                    documentController.brushPaint(colorComponents: documentController.toolColorComponents, at: point, size: pencil.size)
                case let eraser as EraserTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: eraser.size)
                    documentController.brushPaint(colorComponents: .clear, at: point, size: eraser.size)
                case is MoveTool:
                    moveViaTouchLocation(touchLocation)
                case let highlight as HighlightTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: highlight.size)
                    documentController.highlight(at: point, size: highlight.size)
                case let shadow as ShadowTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: shadow.size)
                    documentController.shadow(at: point, size: shadow.size)
                default:
                    break
                }
            }
            documentController.refresh()
            
            if !(tool is MoveTool), let touch = touches.first {
                let touchLocation = touch.location(in: spriteView)
                let point = makePixelPoint(touchLocation: touchLocation, toolSize: toolSizeCopy)
                updateHoverLocation(at: point)
            }
        default:
            break
        }
    }
    
    func delta(start: CGPoint, end: CGPoint) -> CGSize {
        let dx = CGFloat((end.x - start.x) / spriteZoomScale).rounded()
        let dy = CGFloat((end.y - start.y) / spriteZoomScale).rounded()
        return CGSize(width: dx, height: dy)
    }
    
    func moveViaTouchLocation(_ touchLocation: CGPoint) {
        guard let dragStartPoint = dragStartPoint else { return }
        let deltaPoint = delta(start: dragStartPoint, end: touchLocation)
        documentController.move(deltaPoint: deltaPoint)
    }
    
}

#if !os(visionOS)
extension CanvasUIView: UIPencilInteractionDelegate {
    
    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            if documentController.tool is EraserTool {
                documentController.tool = documentController.previousTool
            } else {
                documentController.tool = documentController.eraserTool
            }
        case .switchPrevious:
            documentController.tool = documentController.previousTool
        case .showColorPalette:
            events.send(.showColorPalette)
        default:
            break
        }
    }
    
}
#endif

