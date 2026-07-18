//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A separate, resizable window that edits a single task using the full inspector in a wider
/// two-column layout (fields/text on the left, relationships/comments on the right). Opened from the
/// inspector's "Task" header — see ``TaskInspectorPanel``. Keyed by task id, so reopening the same
/// task focuses its existing window.
struct TaskEditorWindow: Scene {

    static let windowID = "task-editor"

    var body: some Scene {
        WindowGroup(id: Self.windowID, for: UUID.self) { $taskID in
            TaskEditorContent(taskID: taskID)
                .frame(minWidth: 720, minHeight: 460)
                .appEnvironment(.default)
        }
        .defaultSize(width: 860, height: 620)
    }
}

/// Hosts the wide inspector for one task. Uses its own ``PlanViewModel`` on the shared store, so
/// edits flow through the same SwiftData models and the main window updates live.
private struct TaskEditorContent: View {

    let taskID: UUID?

    @Environment(PlanStore.self) private var store
    @State private var viewModel = PlanViewModel()

    var body: some View {
        TaskInspectorPanel(viewModel: viewModel, layout: .wide)
            .navigationTitle(viewModel.selectedTask?.title ?? "Task")
            .task(id: taskID) { configure() }
            .alert(
                viewModel.activeAlert?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.activeAlert != nil },
                    set: { if !$0 { viewModel.activeAlert = nil } }
                ),
                presenting: viewModel.activeAlert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
    }

    /// Points the view model at the task's plan and selects it. If the id no longer resolves (the
    /// task was deleted), the inspector falls back to its "No Selection" state.
    private func configure() {
        viewModel.configure(store: store)
        guard let taskID,
              let task = store.allPlans().flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            viewModel.clearSelection()
            viewModel.plan = nil
            return
        }
        viewModel.plan = task.plan
        viewModel.selectTask(task.id)
    }
}
