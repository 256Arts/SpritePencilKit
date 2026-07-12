//
//  FingerAction.swift
//  SpritePencilKit
//

/// What a finger touch does on the canvas while Apple Pencil is the drawing
/// instrument (see `CanvasUIView.nonDrawingFingerAction`). Raw values are
/// stable — apps persist them in user settings.
public enum FingerAction: String, CaseIterable, Codable, Sendable {
    case draw, move, eyedrop, ignore
}
