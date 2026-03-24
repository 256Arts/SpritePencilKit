import SwiftUI
import Combine
import UIKit

/// A SwiftUI canvas view inside a zoomable container
public struct ZoomableCanvasView: UIViewRepresentable {
    public typealias UIViewType = ZoomableUIView

    // MARK: - Configuration
    public var documentController: DocumentController
    public var zoomEnabled: Bool
    public var pixelGridEnabled: Bool
    public var tileGridEnabled: Bool
    public var checkerboardColor1: UIColor
    public var checkerboardColor2: UIColor
    public var tileGridColor: UIColor
    public var pixelGridColor: UIColor
    public var twoFingerUndoEnabled: Bool
    public var applePencilCanEyedrop: Bool
    public var nonDrawingFingerAction: CanvasUIView.FingerAction
    public var shouldFillPaths: Bool
    public var shouldRecognizeGesturesSimultaneously: Bool
    
    // Called when `CanvasUIView` emits events
    public var onEvent: ((CanvasViewEvent) -> Void)?

    // Optional additional configuration hook run after `setupView()`
    public var configure: ((ZoomableUIView) -> Void)?

    public init(
        documentController: DocumentController,
        zoomEnabled: Bool = true,
        pixelGridEnabled: Bool = false,
        tileGridEnabled: Bool = false,
        checkerboardColor1: UIColor = .systemGray4,
        checkerboardColor2: UIColor = .systemGray5,
        tileGridColor: UIColor = .systemGray3,
        pixelGridColor: UIColor = .systemGray3,
        twoFingerUndoEnabled: Bool = true,
        applePencilCanEyedrop: Bool = true,
        nonDrawingFingerAction: CanvasUIView.FingerAction = .ignore,
        shouldFillPaths: Bool = false,
        shouldRecognizeGesturesSimultaneously: Bool = true,
        onEvent: ((CanvasViewEvent) -> Void)? = nil,
        configure: ((ZoomableUIView) -> Void)? = nil
    ) {
        self.documentController = documentController
        self.zoomEnabled = zoomEnabled
        self.pixelGridEnabled = pixelGridEnabled
        self.tileGridEnabled = tileGridEnabled
        self.checkerboardColor1 = checkerboardColor1
        self.checkerboardColor2 = checkerboardColor2
        self.tileGridColor = tileGridColor
        self.pixelGridColor = pixelGridColor
        self.twoFingerUndoEnabled = twoFingerUndoEnabled
        self.applePencilCanEyedrop = applePencilCanEyedrop
        self.nonDrawingFingerAction = nonDrawingFingerAction
        self.shouldFillPaths = shouldFillPaths
        self.shouldRecognizeGesturesSimultaneously = shouldRecognizeGesturesSimultaneously
        self.onEvent = onEvent
        self.configure = configure
    }

    // MARK: - UIViewRepresentable
    public func makeUIView(context: Context) -> ZoomableUIView {
        let canvasView = CanvasUIView(documentController: documentController)
        let zoomableView = ZoomableUIView(
            contentView: canvasView,
            documentController: documentController
        )
        context.coordinator.bind(to: canvasView, onEvent: onEvent)
        configure?(zoomableView)
        applyConfig(to: zoomableView)
        zoomableView.setupView()
        return zoomableView
    }

    public func updateUIView(_ uiView: ZoomableUIView, context: Context) {
        // Re-apply configuration when SwiftUI updates
        applyConfig(to: uiView)
        // Update event callback if it changed
        context.coordinator.updateOnEvent(onEvent)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Helpers
    private func applyConfig(to view: ZoomableUIView) {
        let canvasView = view.contentView
        
        // Simple property passthroughs
        view.zoomEnabled = zoomEnabled
        canvasView.pixelGridEnabled = pixelGridEnabled
        canvasView.tileGridEnabled = tileGridEnabled
        canvasView.checkerboardColor1 = checkerboardColor1
        canvasView.checkerboardColor2 = checkerboardColor2
        canvasView.tileGridColor = tileGridColor
        canvasView.pixelGridColor = pixelGridColor
        canvasView.twoFingerUndoEnabled = twoFingerUndoEnabled
        canvasView.applePencilCanEyedrop = applePencilCanEyedrop
        canvasView.nonDrawingFingerAction = nonDrawingFingerAction
        canvasView.shouldFillPaths = shouldFillPaths
        canvasView.shouldRecognizeGesturesSimultaneously = shouldRecognizeGesturesSimultaneously

        // Refresh any visuals that depend on these values
        canvasView.makeCheckerboard()
        canvasView.refreshGrid()
    }

    // MARK: - Coordinator
    public final class Coordinator {
        private var cancellable: AnyCancellable?
        private var onEvent: ((CanvasViewEvent) -> Void)?

        fileprivate func bind(to view: CanvasUIView, onEvent: ((CanvasViewEvent) -> Void)?) {
            self.onEvent = onEvent
            // Subscribe to CanvasView events and forward to SwiftUI
            cancellable = view.events.sink { [weak self] event in
                self?.onEvent?(event)
            }
        }

        fileprivate func updateOnEvent(_ onEvent: ((CanvasViewEvent) -> Void)?) {
            self.onEvent = onEvent
        }

        deinit {
            cancellable?.cancel()
        }
    }
}

#Preview {
    ZoomableCanvasView(documentController: DocumentController(), onEvent: { _ in })
}
