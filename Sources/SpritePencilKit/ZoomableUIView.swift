//
//
//  ZoomableUIView.swift
//  SpritePencilKit
//
//  Created by 256 Arts on 2026-03-21.
//

import UIKit
import Combine

/// A view that can be pinched to zoom, and can zoom to fit it's frame
public class ZoomableUIView: UIScrollView, UIGestureRecognizerDelegate, UIScrollViewDelegate {

    public static let defaultMinimumZoomScale: CGFloat = 1.0 // Must be low since if current < minimum, view will not zoom in.
    public static let defaultMaximumZoomScale: CGFloat = 32.0

    public let documentController: DocumentController
    public let contentView: CanvasUIView
    private var eventSubscription: AnyCancellable?

    /// The visible size the canvas was last fitted to.
    private var fittedSize: CGSize?

    override public func layoutSubviews() {
        super.layoutSubviews()
        // Only a size change (initial layout, rotation, split-screen resize,
        // a sheet claiming the bottom edge) re-fits; layout also runs on every
        // scroll tick. Observing `bounds` instead misses the initial layout:
        // SwiftUI sizes this view through `frame`, which never calls it.
        if safeAreaLayoutGuide.layoutFrame.size != fittedSize, !userIsZooming {
            zoomToFit()
        }
    }

    public var zoomEnabled = true {
        didSet {
            if zoomEnabled {
                minimumZoomScale = Self.defaultMinimumZoomScale
                maximumZoomScale = Self.defaultMaximumZoomScale
            } else {
                minimumZoomScale = zoomScale
                maximumZoomScale = zoomScale
            }
        }
    }
    var userIsZooming = false

    var dragStartPoint: CGPoint?
    var shouldStartZooming: Bool {
        zoomEnabled && documentController.currentOperationIsCancelable
    }

    public init(contentView: CanvasUIView, documentController: DocumentController) {
        self.contentView = contentView
        self.documentController = documentController
        super.init(frame: .zero)
        eventSubscription = documentController.onEvent { [weak self] event in
            if case .canvasReplaced = event {
                // Rebuild the canvas visuals first so zoom-to-fit measures the
                // new canvas size, not the old one.
                self?.contentView.canvasWasReplaced()
                self?.zoomToFit()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setupView() {
        delegate = self
        panGestureRecognizer.minimumNumberOfTouches = 2
        panGestureRecognizer.delegate = self
        delaysContentTouches = false
        minimumZoomScale = Self.defaultMinimumZoomScale
        maximumZoomScale = Self.defaultMaximumZoomScale
        zoomScale = 4.0
        scrollsToTop = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        isUserInteractionEnabled = true
        canCancelContentTouches = false

        contentView.layer.magnificationFilter = .nearest
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        contentView.setupView()
        // The initial zoom-to-fit runs from layoutSubviews once layout gives
        // this view a real size.
    }

    public func zoomToFit() {
        // Let a new checkerboard image's intrinsic size reach the content
        // view's frame before measuring.
        layoutIfNeeded()
        let viewSize = safeAreaLayoutGuide.layoutFrame.size
        guard 0 < viewSize.width, 0 < viewSize.height, let context = documentController.context else { return }
        fittedSize = viewSize

        let viewRatio = viewSize.width / viewSize.height
        let spriteSize = CGSize(width: context.width, height: context.height)
        let spriteRatio = spriteSize.width / spriteSize.height

        var scale: CGFloat = 1/contentView.spriteZoomScale
        if viewRatio <= spriteRatio {
            scale *= viewSize.width / spriteSize.width
        } else {
            scale *= viewSize.height / spriteSize.height
        }
        if zoomEnabled {
            // Grow the range to include the fit scale; collapsing it to
            // min == max here would permanently disable pinching afterward.
            minimumZoomScale = min(scale, Self.defaultMinimumZoomScale)
            maximumZoomScale = max(scale, Self.defaultMaximumZoomScale)
        } else {
            minimumZoomScale = scale
            maximumZoomScale = scale
        }
        setZoomScale(scale, animated: false)
        // The scroll view only recomputes contentSize during user zoom
        // gestures; sync it so panning/centering use the new dimensions.
        contentSize = contentView.frame.size
        contentView.frame.origin = .zero
        // setZoomScale centered against the stale contentSize.
        centerContent()
        refreshTiledPreviewCoverage()
    }

    /// Tells the canvas how far its tiled repeats have to reach — the visible
    /// area, measured in the canvas's own (unzoomed) points.
    private func refreshTiledPreviewCoverage() {
        guard 0 < zoomScale else { return }
        contentView.updateTiledPreview(covering: CGSize(width: bounds.width / zoomScale, height: bounds.height / zoomScale))
    }

    // MARK: - Touches & Hover

    public override func touchesShouldBegin(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) -> Bool {
        true // Allow content to receive touches
    }

    public override func touchesShouldCancel(in view: UIView) -> Bool {
        false // Do not cancel content view's touches
    }

    // Is this needed?
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // Is this needed?
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: - Zooming

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }

    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        userIsZooming = shouldStartZooming
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) { // Called many times while zooming
        centerContent()
        refreshTiledPreviewCoverage()
    }

    private func centerContent() {
        if contentSize.width < safeAreaLayoutGuide.layoutFrame.width {
            contentOffset.x = ((contentSize.width - safeAreaLayoutGuide.layoutFrame.width) / 2) - safeAreaInsets.left + safeAreaInsets.right
        }
        if contentSize.height < safeAreaLayoutGuide.layoutFrame.height {
            contentOffset.y = ((contentSize.height - safeAreaLayoutGuide.layoutFrame.height) / 2) - safeAreaInsets.top + safeAreaInsets.bottom
        }

        var h: CGFloat = 0.0
        var v: CGFloat = 0.0
        if contentSize.width < bounds.width {
            h = (safeAreaLayoutGuide.layoutFrame.width - contentSize.width) / 2.0
        }
        if contentSize.height < bounds.height {
            v = (safeAreaLayoutGuide.layoutFrame.height - contentSize.height) / 2.0
        }
        contentInset = UIEdgeInsets(top: v + safeAreaInsets.top, left: h + safeAreaInsets.left, bottom: v + safeAreaInsets.bottom, right: h + safeAreaInsets.right)
    }

    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        userIsZooming = false
        guard let view = view else { return }
        // Snap to 100%
        let thresholdToSnap: CGFloat = 0.12
        let zoomScaleDistanceRange = 1.0-thresholdToSnap...1.0+thresholdToSnap

        let contentWidthFraction = safeAreaLayoutGuide.layoutFrame.width / (view.safeAreaLayoutGuide.layoutFrame.width * zoomScale)
        if zoomScaleDistanceRange.contains(contentWidthFraction) {
            let zoom = (safeAreaLayoutGuide.layoutFrame.width / view.safeAreaLayoutGuide.layoutFrame.width)
            setZoomScale(zoom, animated: true)
            return
        }

        let contentHeightFraction = safeAreaLayoutGuide.layoutFrame.height / (view.safeAreaLayoutGuide.layoutFrame.height * zoomScale)
        if zoomScaleDistanceRange.contains(contentHeightFraction) {
            let zoom = (safeAreaLayoutGuide.layoutFrame.height / view.safeAreaLayoutGuide.layoutFrame.height)
            setZoomScale(zoom, animated: true)
            return
        }
    }

}
