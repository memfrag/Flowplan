//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
@testable import Flowplan

/// Tests for `PlanViewModel` UI state that must not bleed between projects.
@MainActor
struct PlanViewModelTests {

    @Test func switchingPlansRestoresPerPlanViewport() {
        let viewModel = PlanViewModel()
        let planA = Plan(title: "A")
        let planB = Plan(title: "B")

        // Pan/zoom project A.
        viewModel.plan = planA
        viewModel.canvasOffset = CGSize(width: 100, height: 50)
        viewModel.zoomScale = 1.5

        // Switching to a never-seen project starts at origin/100%, not A's viewport.
        viewModel.plan = planB
        #expect(viewModel.canvasOffset == .zero)
        #expect(viewModel.zoomScale == 1.0)

        // Move around in B, then switch back to A — A's viewport is restored.
        viewModel.canvasOffset = CGSize(width: -20, height: -30)
        viewModel.zoomScale = 0.75
        viewModel.plan = planA
        #expect(viewModel.canvasOffset == CGSize(width: 100, height: 50))
        #expect(viewModel.zoomScale == 1.5)

        // And back to B restores B's.
        viewModel.plan = planB
        #expect(viewModel.canvasOffset == CGSize(width: -20, height: -30))
        #expect(viewModel.zoomScale == 0.75)
    }

    @Test func reassigningSamePlanKeepsViewport() {
        let viewModel = PlanViewModel()
        let plan = Plan(title: "A")
        viewModel.plan = plan
        viewModel.canvasOffset = CGSize(width: 42, height: 7)
        viewModel.zoomScale = 1.25

        // Re-setting the same plan must not reset the viewport.
        viewModel.plan = plan
        #expect(viewModel.canvasOffset == CGSize(width: 42, height: 7))
        #expect(viewModel.zoomScale == 1.25)
    }
}
