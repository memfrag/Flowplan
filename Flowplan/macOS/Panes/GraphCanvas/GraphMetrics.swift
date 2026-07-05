//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import CoreGraphics

/// Shared geometry constants for the graph canvas.
enum GraphMetrics {
    static let cardSize = CGSize(width: 176, height: 82)
    static let canvasSize = CGSize(width: 4000, height: 3000)
    static let canvasSpaceName = "flowplan.canvas"
    static let minZoom: CGFloat = 0.35
    static let maxZoom: CGFloat = 2.5
}
