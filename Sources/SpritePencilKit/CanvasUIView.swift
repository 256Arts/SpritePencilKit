import UIKit
import CoreImage.CIFilterBuiltins
import Combine

/// A checkerboard canvas that can be drawn on
public class CanvasUIView: UIImageView, UIGestureRecognizerDelegate {

    static let hoverViewBorderWidth: CGFloat = 0.1

    // Views
    public let documentController: DocumentController
    var referenceView = UIImageView()
    var spriteView = UIImageView()
    var hoverView = UIView()
    var toolSizeCopy = PixelSize(width: 1, height: 1)
    private var eventSubscription: AnyCancellable?

    // Grids
    public var pixelGridEnabled = false
    public var tileGridEnabled = false
    var tileGridLayer: CAShapeLayer?
    var pixelGridLayer: CAShapeLayer?
    var verticalSymmetryLineLayer: CALayer?
    var horizontalSymmetryLineLayer: CALayer?

    // Tiled preview
    /// Repeats of the sprite filling the space around the canvas, so a tilemap
    /// tile can be judged where it will actually sit. Display only — the
    /// repeats take no touches and only the canvas itself is drawable.
    let tiledPreviewRowsLayer = CAReplicatorLayer()
    let tiledPreviewColumnsLayer = CAReplicatorLayer()
    let tiledPreviewTileLayer = CALayer()
    /// The area the repeats must fill, in canvas points, set by the zoomable
    /// container from its visible rect.
    private var tiledPreviewCoverage: CGSize = .zero

    // Selection (move tool)
    var selectionLayer: CAShapeLayer?
    /// Anchor of the marquee drag in progress, or `nil` when a move-tool drag
    /// moves pixels instead of selecting them.
    private var marqueeStartPixel: PixelPoint?

    // Style
    public var checkerboardColor1: UIColor = .systemGray4
    public var checkerboardColor2: UIColor = .systemGray5
    public var tileGridColor: UIColor = .systemGray3
    public var pixelGridColor: UIColor = .systemGray3

    // General
    private var tool: Tool {
        documentController.tool
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
    /// An imported image shown behind the sprite's transparent pixels (above the
    /// checkerboard, below the drawing) for tracing. Aspect-fit within the canvas.
    public var referenceImage: UIImage? {
        didSet {
            referenceView.image = referenceImage
        }
    }
    /// Draws the sprite repeating in every direction around the canvas, for
    /// checking that a tilemap tile lines up with its neighbours.
    public var tiledPreviewEnabled = false {
        didSet {
            guard tiledPreviewEnabled != oldValue else { return }
            tiledPreviewRowsLayer.isHidden = !tiledPreviewEnabled
            refreshTiledPreview()
        }
    }
    public var twoFingerUndoEnabled = true
    var applePencilUsed = false
    public var applePencilCanEyedrop = true
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

    public init(documentController: DocumentController) {
        self.documentController = documentController
        super.init(frame: .zero)
        eventSubscription = documentController.onEvent { [weak self] event in
            self?.handle(event)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func handle(_ event: DocumentController.Event) {
        switch event {
        case .drawingDidChange:
            spriteView.image = documentController.renderedImage
            refreshTiledPreviewContents()
        case .toolChanged(let tool):
            toolSizeChanged(size: tool.size)
        case .symmetryChanged:
            refreshGrid()
        case .selectionChanged:
            refreshSelectionLayer()
        default:
            break
        }
    }

    /// Rebuilds everything sized from the canvas after the drawing context was
    /// swapped for one of a different size (load, rotate, trim, or an undo of
    /// either). Called by the zoomable container so the rebuild is ordered
    /// before its zoom-to-fit.
    func canvasWasReplaced() {
        hoverView.isHidden = true
        refreshSelectionLayer() // the controller cleared the selection
        makeCheckerboard()
        // The ring is sized in canvases, so a new canvas size needs a new ring.
        tiledPreviewCoverage = .zero
        refreshTiledPreview()
        tileGridLayer?.removeFromSuperlayer()
        tileGridLayer = nil
        pixelGridLayer?.removeFromSuperlayer()
        pixelGridLayer = nil
        verticalSymmetryLineLayer?.removeFromSuperlayer()
        verticalSymmetryLineLayer = nil
        horizontalSymmetryLineLayer?.removeFromSuperlayer()
        horizontalSymmetryLineLayer = nil
        refreshGrid()
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

        // The sprite view's intrinsic size drives the canvas size; a reference
        // photo's own (much larger) intrinsic size must not compete with it.
        referenceView.contentMode = .scaleAspectFit
        referenceView.translatesAutoresizingMaskIntoConstraints = false
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            referenceView.setContentHuggingPriority(UILayoutPriority(1), for: axis)
            referenceView.setContentCompressionResistancePriority(UILayoutPriority(1), for: axis)
        }

        hoverView.layer.borderWidth = Self.hoverViewBorderWidth
        hoverView.layer.borderColor = UIColor.label.cgColor
        hoverView.isHidden = true
        hoverView.frame.size = CGSize(width: spriteZoomScale + Self.hoverViewBorderWidth/2, height: spriteZoomScale + Self.hoverViewBorderWidth/2)

        tiledPreviewTileLayer.magnificationFilter = .nearest
        tiledPreviewRowsLayer.isHidden = !tiledPreviewEnabled
        tiledPreviewColumnsLayer.addSublayer(tiledPreviewTileLayer)
        tiledPreviewRowsLayer.addSublayer(tiledPreviewColumnsLayer)
        // Below the checkerboard's own subviews, and outside the canvas bounds:
        // neither replicator clips, so the ring spills into the surrounding
        // scroll view the way an infinite tiling should.
        layer.addSublayer(tiledPreviewRowsLayer)

        addSubview(referenceView)
        addSubview(spriteView)
        spriteView.addSubview(hoverView)

        NSLayoutConstraint.activate([
            spriteView.topAnchor.constraint(equalTo: self.topAnchor),
            spriteView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            spriteView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            spriteView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            referenceView.topAnchor.constraint(equalTo: self.topAnchor),
            referenceView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            referenceView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            referenceView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
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
        // BUG: "checkers.outputImage" causes NSArray crash, so Catalyst gets a
        // solid background instead of the generated checkerboard image.
        #if targetEnvironment(macCatalyst)
        backgroundColor = checkerboardColor1
        #else
        guard let image = checkers.outputImage else { return }
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
        #endif
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        // Picks up canvas resizes and spriteZoomScale changes.
        refreshTiledPreview()
    }

    // MARK: - Tiled preview

    /// Reports how much room the repeats have to fill, in canvas points. The
    /// zoomable container calls this as the visible area changes; the ring only
    /// ever grows, so zooming out doesn't rebuild it on every frame.
    func updateTiledPreview(covering coverage: CGSize) {
        guard tiledPreviewCoverage.width < coverage.width || tiledPreviewCoverage.height < coverage.height else { return }
        tiledPreviewCoverage = CGSize(width: max(tiledPreviewCoverage.width, coverage.width), height: max(tiledPreviewCoverage.height, coverage.height))
        refreshTiledPreview()
    }

    /// The number of repeats needed on each side of the canvas to fill
    /// `coverage`. At least one, so the feature reads as tiled even before the
    /// container has reported a visible size.
    nonisolated static func tileRingCount(coverage: CGSize, canvasSize: CGSize) -> (columns: Int, rows: Int) {
        guard 0 < canvasSize.width, 0 < canvasSize.height else { return (1, 1) }
        return (max(1, Int(ceil(coverage.width / canvasSize.width))),
                max(1, Int(ceil(coverage.height / canvasSize.height))))
    }

    private func refreshTiledPreview() {
        guard tiledPreviewEnabled, let context = documentController.context else { return }

        let tileSize = CGSize(width: CGFloat(context.width) * spriteZoomScale, height: CGFloat(context.height) * spriteZoomScale)
        let (columns, rows) = Self.tileRingCount(coverage: tiledPreviewCoverage, canvasSize: tileSize)

        // Replicated instances only run in +x/+y, so the source tile starts a
        // full ring up and to the left of the canvas.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tiledPreviewRowsLayer.frame = CGRect(origin: CGPoint(x: -CGFloat(columns) * tileSize.width, y: -CGFloat(rows) * tileSize.height), size: tileSize)
        tiledPreviewRowsLayer.instanceCount = 2 * rows + 1
        tiledPreviewRowsLayer.instanceTransform = CATransform3DMakeTranslation(0, tileSize.height, 0)
        tiledPreviewColumnsLayer.frame = CGRect(origin: .zero, size: tileSize)
        tiledPreviewColumnsLayer.instanceCount = 2 * columns + 1
        tiledPreviewColumnsLayer.instanceTransform = CATransform3DMakeTranslation(tileSize.width, 0, 0)
        tiledPreviewTileLayer.frame = CGRect(origin: .zero, size: tileSize)
        CATransaction.commit()

        refreshTiledPreviewContents()
    }

    private func refreshTiledPreviewContents() {
        guard tiledPreviewEnabled else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no crossfade behind every stroke
        tiledPreviewTileLayer.contents = documentController.renderedImage?.cgImage
        CATransaction.commit()
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
        // Round the hover outline when a circular brush is active (and only when
        // the shape actually differs from a square — i.e. brushes larger than 2px).
        let rounded = documentController.brushShape == .circle && 2 < size.width
        hoverView.layer.cornerRadius = rounded ? hoverView.bounds.size.width / 2 : 0
        refreshSelectionLayer() // called on spriteZoomScale changes, which resize the marquee
    }

    /// Rebuilds the dashed marquee over `documentController.selectedArea`
    /// (removing it when there is no selection).
    func refreshSelectionLayer() {
        guard let selection = documentController.selectedArea else {
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
            return
        }
        let layer = selectionLayer ?? {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineWidth = 0.4
            layer.lineDashPattern = [1, 1]
            layer.strokeColor = tintColor.cgColor
            spriteView.layer.addSublayer(layer)
            selectionLayer = layer
            return layer
        }()
        // Without this, CALayer's implicit 0.25s animations make the marquee
        // trail behind the marquee drag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: selection.minX * spriteZoomScale, y: selection.minY * spriteZoomScale, width: selection.width * spriteZoomScale, height: selection.height * spriteZoomScale)
        layer.path = CGPath(rect: CGRect(origin: .zero, size: layer.frame.size), transform: nil)
        CATransaction.commit()
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

    @objc func doUndo() {
        documentController.undo()
    }
    @objc func doRedo() {
        documentController.redo()
    }
    @objc func doUndoForAltGesture() {
        if twoFingerUndoEnabled, documentController.currentOperationIsCancelable {
            documentController.undo()
        }
    }
    @objc func doRedoForAltGesture() {
        // Unlike undo, redo must NOT require the cancelable check: that guard
        // limits the quick tap-to-undo to small accidental strokes, but redo
        // re-applies a previously undone action and has no "current stroke"
        // to evaluate, so the guard would block legitimate redos.
        if twoFingerUndoEnabled {
            documentController.redo()
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
                if !applePencilCanEyedrop, tool is EyedropperTool {
                    documentController.tool = documentController.pencilTool
                }
            default:
                switch fingerAction {
                case .move:
                    documentController.tool = MoveTool()
                case .eyedrop:
                    documentController.tool = EyedropperTool()
                default:
                    break
                }
            }

            guard validateTouchesForCurrentTool(gesture.currentTouches) else { return }

            if let moveTool = tool as? MoveTool {
                let touchLocation = touch.location(in: spriteView)
                let pixel = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                if moveTool.selectsArea,
                   !(documentController.selectedArea?.contains(CGPoint(x: CGFloat(pixel.x) + 0.5, y: CGFloat(pixel.y) + 0.5)) ?? false) {
                    // In select mode, a drag outside the current selection (or
                    // with none) draws a new marquee; inside it moves the pixels.
                    marqueeStartPixel = clampedToCanvas(pixel)
                    documentController.setSelectedArea(marqueeRect(from: marqueeStartPixel!, to: pixel))
                } else {
                    documentController.beginMove()
                    dragStartPoint = touchLocation
                }
            }
            documentController.beginCurrentOperation()
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
            case is EyedropperTool:
                let location = touch.location(in: spriteView)
                let point = makePixelPoint(touchLocation: location, toolSize: PixelSize(width: 1, height: 1))
                documentController.eyedrop(at: point)
            default:
                if let coalesced = gesture.currentEvent?.coalescedTouches(for: touch) {
                    addSamples(for: coalesced)
                }
                let touchLocation = touch.location(in: spriteView)

                switch tool {
                case is MoveTool:
                    if marqueeStartPixel != nil {
                        marqueeStartPixel = nil
                        // A tap (1×1 marquee) clears the selection rather than
                        // leaving a near-invisible one.
                        if let selection = documentController.selectedArea, selection.width <= 1, selection.height <= 1 {
                            documentController.setSelectedArea(nil)
                        }
                    } else if let dragStartPoint {
                        documentController.commitMove(delta: delta(start: dragStartPoint, end: touchLocation))
                    }
                    dragStartPoint = nil
                case is FillTool:
                    let point = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                    documentController.fill(at: point)
                default:
                    documentController.commitCurrentOperation()
                }

                switch touch.type {
                case .pencil:
                    break
                default:
                    if fingerAction == .move {
                        documentController.tool = documentController.previousTool
                    }
                }
                hoverView.isHidden = true
                documentController.hoverPoint = nil
            }
            documentController.endCurrentOperation()
        case .cancelled:
            guard validateTouchesForCurrentTool(gesture.currentTouches) else { return }

            hoverView.isHidden = true
            documentController.hoverPoint = nil
            dragStartPoint = nil
            marqueeStartPixel = nil

            documentController.cancelCurrentOperation()
            documentController.endCurrentOperation()
        case .failed:
            break
        case .recognized:
            break
        @unknown default:
            // A future UIKit gesture state must not crash shipping apps.
            break
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
                case is EyedropperTool:
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
        guard tool.isContinuous else { return }
        for touch in touches {
            let touchLocation = touch.location(in: spriteView)
            if let start = marqueeStartPixel {
                let pixel = makePixelPoint(touchLocation: touchLocation, toolSize: PixelSize(width: 1, height: 1))
                documentController.setSelectedArea(marqueeRect(from: start, to: pixel))
            } else if tool is MoveTool {
                moveViaTouchLocation(touchLocation)
            } else {
                let point = makePixelPoint(touchLocation: touchLocation, toolSize: tool.size)
                tool.apply(at: point, controller: documentController)
            }
        }
        // A marquee drag changes no pixels — nothing to re-render.
        guard marqueeStartPixel == nil else { return }
        documentController.refresh()

        if !(tool is MoveTool), let touch = touches.first {
            let touchLocation = touch.location(in: spriteView)
            let point = makePixelPoint(touchLocation: touchLocation, toolSize: toolSizeCopy)
            updateHoverLocation(at: point)
        }
    }

    func delta(start: CGPoint, end: CGPoint) -> CGSize {
        let dx = CGFloat((end.x - start.x) / spriteZoomScale).rounded()
        let dy = CGFloat((end.y - start.y) / spriteZoomScale).rounded()
        return CGSize(width: dx, height: dy)
    }

    func moveViaTouchLocation(_ touchLocation: CGPoint) {
        guard let dragStartPoint = dragStartPoint else { return }
        let delta = delta(start: dragStartPoint, end: touchLocation)
        documentController.continueMove(delta: delta)
        // The marquee rides along with the pixels it frames; the controller
        // re-announces the settled selection on commit.
        if let selection = documentController.selectedArea, let layer = selectionLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame.origin = CGPoint(x: (selection.minX + delta.width) * spriteZoomScale, y: (selection.minY + delta.height) * spriteZoomScale)
            CATransaction.commit()
        }
    }

    // MARK: - Marquee helpers

    private func clampedToCanvas(_ pixel: PixelPoint) -> PixelPoint {
        PixelPoint(x: min(max(0, pixel.x), documentController.context.width - 1),
                   y: min(max(0, pixel.y), documentController.context.height - 1))
    }

    /// The inclusive pixel rect spanned by a marquee drag from `start`
    /// (already clamped) to `end` (clamped here — drags may leave the canvas).
    private func marqueeRect(from start: PixelPoint, to end: PixelPoint) -> CGRect {
        let end = clampedToCanvas(end)
        return CGRect(x: min(start.x, end.x),
                      y: min(start.y, end.y),
                      width: abs(start.x - end.x) + 1,
                      height: abs(start.y - end.y) + 1)
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
            documentController.eventSubject.send(.showColorPalette)
        default:
            break
        }
    }

}
#endif
