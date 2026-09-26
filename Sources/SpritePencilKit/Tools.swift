//
//  Tools.swift
//  Sprite Pencil
//
//  Created by Jayden Irwin on 2019-06-06.
//  Copyright © 2019 Jayden Irwin. All rights reserved.
//

import CoreGraphics

public enum BrushShape: String, CaseIterable, Equatable, Hashable {
    case square
    case circle

    /// Whether the cell at `(column, row)` within a `diameter`×`diameter` brush
    /// is part of the brush mask. `column`/`row` are offsets from the brush's
    /// top-left corner. Square always fills; circle keeps cells whose center
    /// falls within the inscribed circle, tightened by half a pixel so the
    /// smallest round brush (3px) renders as a plus rather than a full square.
    /// Brushes 2px and smaller are solid blocks for both shapes (a round 1–2px
    /// brush has no meaningful curve).
    public func includes(column: Int, row: Int, diameter: Int) -> Bool {
        switch self {
        case .square:
            return true
        case .circle:
            guard diameter > 2 else { return true }
            let radius = Double(diameter) / 2.0
            let dx = Double(column) + 0.5 - radius
            let dy = Double(row) + 0.5 - radius
            return dx * dx + dy * dy <= radius * radius - 0.5
        }
    }
}

/// A drawing tool. Continuous tools apply themselves to the canvas as the
/// touch moves; the others act once, where the touch ends (fill, eyedropper)
/// or across the whole gesture (move).
public protocol Tool {
    /// The brush footprint this tool paints with. Tools with no adjustable
    /// width are a single pixel.
    var size: PixelSize { get }
    /// Whether the tool acts on every touch sample as the finger moves.
    var isContinuous: Bool { get }
    /// Applies the tool at `point` (the top-left pixel of the brush footprint).
    @MainActor func apply(at point: PixelPoint, controller: DocumentController)
}

public extension Tool {
    var size: PixelSize { PixelSize(width: 1, height: 1) }
    var isContinuous: Bool { false }
    @MainActor func apply(at point: PixelPoint, controller: DocumentController) { }
}

/// A tool whose brush width the user can adjust.
public protocol SizableTool: Tool {
    var width: Int { get set }
    /// The largest width this tool supports.
    var maxWidth: Int { get }
}

public extension SizableTool {
    var size: PixelSize { PixelSize(width: width, height: width) }
}

public struct PencilTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 10 }
    public var isContinuous: Bool { true }

    public init(width: Int) {
        self.width = width
    }

    @MainActor public func apply(at point: PixelPoint, controller: DocumentController) {
        controller.brushPaint(colorComponents: controller.toolColorComponents, at: point, size: size)
    }
}
public struct EraserTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 10 }
    public var isContinuous: Bool { true }

    public init(width: Int) {
        self.width = width
    }

    @MainActor public func apply(at point: PixelPoint, controller: DocumentController) {
        controller.brushPaint(colorComponents: .clear, at: point, size: size)
    }
}
public struct FillTool: Tool {
    /// When set, a tap replaces every pixel of the tapped color across the
    /// whole canvas instead of only the contiguous region around it.
    public var replacesAllMatching: Bool

    public init(replacesAllMatching: Bool = false) {
        self.replacesAllMatching = replacesAllMatching
    }
}
public struct MoveTool: Tool {
    // Continuous, but driven by the drag delta rather than per-point
    // application — see DocumentController.beginMove/continueMove/commitMove.
    public var isContinuous: Bool { true }

    /// When set, drags define a rectangular selection (or move an existing one)
    /// instead of moving the whole canvas — see `DocumentController.selectedArea`.
    public var selectsArea: Bool

    public init(selectsArea: Bool = false) {
        self.selectsArea = selectsArea
    }
}
public struct HighlightTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 5 }
    public var isContinuous: Bool { true }

    public init(width: Int) {
        self.width = width
    }

    @MainActor public func apply(at point: PixelPoint, controller: DocumentController) {
        controller.highlight(at: point, size: size)
    }
}
public struct ShadowTool: SizableTool {
    public var width: Int
    public var maxWidth: Int { 5 }
    public var isContinuous: Bool { true }

    public init(width: Int) {
        self.width = width
    }

    @MainActor public func apply(at point: PixelPoint, controller: DocumentController) {
        controller.shadow(at: point, size: size)
    }
}
public struct EyedropperTool: Tool {
    public init() { }
}
