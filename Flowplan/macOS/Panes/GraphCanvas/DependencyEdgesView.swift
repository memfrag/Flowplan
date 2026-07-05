//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Draws dependency edges behind the task cards: curved connectors from each prerequisite's right
/// edge to its dependent's left edge, with an arrowhead at the dependent end (spec §22).
struct DependencyEdgesView: View {

    struct Edge: Identifiable {
        let id: UUID
        let start: CGPoint
        let end: CGPoint
        let isHighlighted: Bool
    }

    let edges: [Edge]
    /// A temporary line shown while the user drags to create a new dependency.
    let pendingLink: (start: CGPoint, end: CGPoint)?
    /// The region (in canvas coordinates) the Canvas covers. May start at a negative origin so
    /// connectors above/left of the content origin aren't clipped.
    let frameRect: CGRect

    var body: some View {
        Canvas { context, _ in
            // Draw in absolute canvas coordinates regardless of where the Canvas sits.
            context.translateBy(x: -frameRect.origin.x, y: -frameRect.origin.y)

            for edge in edges {
                let path = Self.connectorPath(from: edge.start, to: edge.end)
                let color = edge.isHighlighted ? Color.accentColor : Color.secondary.opacity(0.55)
                let width: CGFloat = edge.isHighlighted ? 2.5 : 1.5
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                context.fill(Self.arrowhead(at: edge.end), with: .color(color))
            }

            if let pendingLink {
                let path = Self.connectorPath(from: pendingLink.start, to: pendingLink.end)
                context.stroke(
                    path,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
                )
                context.fill(Self.arrowhead(at: pendingLink.end), with: .color(.accentColor))
            }
        }
        .frame(width: frameRect.width, height: frameRect.height)
        .position(x: frameRect.midX, y: frameRect.midY)
        .allowsHitTesting(false)
    }

    /// A horizontal cubic-bezier connector.
    static func connectorPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let dx = max(40, abs(end.x - start.x) * 0.5)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + dx, y: start.y),
            control2: CGPoint(x: end.x - dx, y: end.y)
        )
        return path
    }

    /// A small triangular arrowhead pointing right, centred on `point`.
    static func arrowhead(at point: CGPoint, size: CGFloat = 7) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y))
        path.addLine(to: CGPoint(x: point.x - size, y: point.y - size * 0.6))
        path.addLine(to: CGPoint(x: point.x - size, y: point.y + size * 0.6))
        path.closeSubpath()
        return path
    }
}
