//
//
//  DrawGestureRecognizer.swift
//  SpritePencilKit
//
//  Created by 256 Arts on 2026-03-22.
//

import UIKit
        
class DrawGestureRecognizer: UILongPressGestureRecognizer {
    
    var currentTouches: Set<UITouch> = []
    weak var currentEvent: UIEvent?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        currentTouches = touches
        currentEvent = event
    }
    
    override func reset() {
        super.reset()
        currentTouches.removeAll()
        currentEvent = nil
    }
}
