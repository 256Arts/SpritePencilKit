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
    
    public weak var documentController: DocumentController!
    public let contentView: CanvasUIView
    
    override public var bounds: CGRect {
        didSet {
            if documentController?.context != nil, !userWillStartZooming {
                zoomToFit()
            }
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
    var zoomEnabledOverride = false
    var userWillStartZooming = false
    
    var dragStartPoint: CGPoint?
    var spriteCopy: UIImage! {
        didSet {
            contentSize = spriteCopy.size
        }
    }
    var shouldStartZooming: Bool {
        (zoomEnabled && contentView.drawnPointsAreCancelable()) || zoomEnabledOverride
    }
    
    public init(contentView: CanvasUIView, documentController: DocumentController) {
        self.contentView = contentView
        self.documentController = documentController
        super.init(frame: .zero)
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.zoomToFit()
        }
    }
    
    public func zoomToFit() {
        let viewSize = safeAreaLayoutGuide.layoutFrame.size
        
        let viewRatio = viewSize.width / viewSize.height
        let spriteSize = CGSize(width: documentController.context.width, height: documentController.context.height)
        let spriteRatio = spriteSize.width / spriteSize.height
        
        var scale: CGFloat = 1/contentView.spriteZoomScale
        if viewRatio <= spriteRatio {
            scale *= viewSize.width / spriteSize.width
        } else {
            scale *= viewSize.height / spriteSize.height
        }
        zoomEnabledOverride = true
        if scale < self.minimumZoomScale || self.maximumZoomScale < scale {
            self.minimumZoomScale = scale
            self.maximumZoomScale = scale
        }
        self.setZoomScale(scale, animated: false)
        self.contentView.frame.origin = .zero
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            zoomEnabledOverride = false
        }
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
        userWillStartZooming = shouldStartZooming && !zoomEnabledOverride
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) { // Called many times while zooming
        
        func centerContent() {
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
        
        centerContent()
    }
    
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
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
        
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            userWillStartZooming = false
        }
    }
    
}

