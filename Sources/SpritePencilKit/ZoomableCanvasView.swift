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
    public var nonDrawingFingerAction: FingerAction
    public var shouldFillPaths: Bool
    public var shouldRecognizeGesturesSimultaneously: Bool

    // Called when the engine emits events
    public var onEvent: ((DocumentController.Event) -> Void)?

    // Optional additional configuration hook run before `setupView()` — the
    // place to load the drawing context into the controller.
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
        nonDrawingFingerAction: FingerAction = .ignore,
        shouldFillPaths: Bool = false,
        shouldRecognizeGesturesSimultaneously: Bool = true,
        onEvent: ((DocumentController.Event) -> Void)? = nil,
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
        context.coordinator.bind(to: documentController, onEvent: onEvent)
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
        canvasView.twoFingerUndoEnabled = twoFingerUndoEnabled
        canvasView.applePencilCanEyedrop = applePencilCanEyedrop
        canvasView.nonDrawingFingerAction = nonDrawingFingerAction
        canvasView.shouldRecognizeGesturesSimultaneously = shouldRecognizeGesturesSimultaneously
        // Diffed: this runs during SwiftUI view updates, and writing observable
        // controller state mid-update would invalidate views for no change.
        if documentController.shouldFillPaths != shouldFillPaths {
            documentController.shouldFillPaths = shouldFillPaths
        }

        // Only rebuild visuals whose inputs actually changed — SwiftUI calls
        // updateUIView often, and makeCheckerboard renders through a CIContext.
        if canvasView.checkerboardColor1 != checkerboardColor1 || canvasView.checkerboardColor2 != checkerboardColor2 {
            canvasView.checkerboardColor1 = checkerboardColor1
            canvasView.checkerboardColor2 = checkerboardColor2
            canvasView.makeCheckerboard()
        }
        if canvasView.pixelGridEnabled != pixelGridEnabled || canvasView.tileGridEnabled != tileGridEnabled
            || canvasView.pixelGridColor != pixelGridColor || canvasView.tileGridColor != tileGridColor {
            canvasView.pixelGridEnabled = pixelGridEnabled
            canvasView.tileGridEnabled = tileGridEnabled
            canvasView.pixelGridColor = pixelGridColor
            canvasView.tileGridColor = tileGridColor
            if documentController.context != nil {
                canvasView.refreshGrid()
            }
        }
    }

    // MARK: - Coordinator
    public final class Coordinator {
        private var cancellable: AnyCancellable?
        private var onEvent: ((DocumentController.Event) -> Void)?

        @MainActor fileprivate func bind(to documentController: DocumentController, onEvent: ((DocumentController.Event) -> Void)?) {
            self.onEvent = onEvent
            // Subscribe to engine events and forward to SwiftUI
            cancellable = documentController.onEvent { [weak self] event in
                self?.onEvent?(event)
            }
        }

        fileprivate func updateOnEvent(_ onEvent: ((DocumentController.Event) -> Void)?) {
            self.onEvent = onEvent
        }
    }
}

#Preview {
    ZoomableCanvasView(documentController: DocumentController(), onEvent: { _ in })
}
