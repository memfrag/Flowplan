//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

/// The root content view of the main window. Owns the shared ``PlanViewModel``, seeds the store on
/// first launch, and keeps an active plan selected.
struct FlowplanWindow: View {

    @Environment(PlanStore.self) private var store
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @State private var viewModel = PlanViewModel()

    var body: some View {
        Sidebar(viewModel: viewModel)
            .focusedSceneValue(\.planViewModel, viewModel)
            .task { setUp() }
            .onChange(of: plans) { _, newPlans in
                ensureActivePlan(in: newPlans)
            }
    }

    private func setUp() {
        viewModel.configure(store: store)
        store.seedIfEmpty()
        store.backfillTaskNumbers()
        ensureActivePlan(in: plans)
    }

    private func ensureActivePlan(in plans: [Plan]) {
        if let current = viewModel.plan, plans.contains(where: { $0.id == current.id }) {
            return
        }
        viewModel.plan = plans.first
        viewModel.clearSelection()
    }
}
