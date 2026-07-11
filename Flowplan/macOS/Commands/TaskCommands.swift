//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

// MARK: - Focused value plumbing

struct PlanViewModelFocusedValueKey: FocusedValueKey {
    typealias Value = PlanViewModel
}

extension FocusedValues {
    var planViewModel: PlanViewModel? {
        get { self[PlanViewModelFocusedValueKey.self] }
        set { self[PlanViewModelFocusedValueKey.self] = newValue }
    }
}

// MARK: - Task & view menu commands (spec §14)

struct TaskCommands: Commands {

    @FocusedValue(\.planViewModel) private var viewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { viewModel?.createTaskAtViewportCenter() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(viewModel?.plan == nil)
        }

        CommandMenu("Task") {
            Button("Start") {
                if isMultiSelection { viewModel?.setProgressForSelected(.inProgress) }
                else { withSelected { $0.start($1) } }
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("Mark Done") {
                if isMultiSelection { viewModel?.setProgressForSelected(.done) }
                else { withSelected { $0.markDone($1) } }
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button("Reopen") {
                if isMultiSelection { viewModel?.setProgressForSelected(.notStarted) }
                else { withSelected { $0.reopen($1) } }
            }

            Divider()

            Button("Edit Title") { viewModel?.editingTaskID = viewModel?.selectedTaskID }
                .keyboardShortcut("e", modifiers: .command)
            Button("Duplicate") { viewModel?.duplicateSelectedTask() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Delete") { viewModel?.deleteSelectedTaskOrDependency() }
                .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button("Auto Layout") { viewModel?.autoLayout() }
        }

        CommandMenu("View") {
            Button("Graph View") { viewModel?.viewMode = .graph }
                .keyboardShortcut("1", modifiers: .command)
            Button("List View") { viewModel?.viewMode = .list }
                .keyboardShortcut("2", modifiers: .command)
            Button("Board View") { viewModel?.viewMode = .board }
                .keyboardShortcut("3", modifiers: .command)
            Button("Timeline View") { viewModel?.viewMode = .timeline }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button(viewModel?.showCriticalPath == true ? "Hide Critical Path" : "Show Critical Path") {
                viewModel?.viewMode = .graph
                viewModel?.showCriticalPath.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(viewModel?.plan == nil)

            Divider()

            Button("Search") { viewModel?.isSearchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("Command Palette…") { viewModel?.isCommandPalettePresented = true }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Zoom In") { zoom(by: 0.1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { zoom(by: -0.1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Zoom") { viewModel?.zoomScale = 1 }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Clear Selection") {
                // Escape is a menu key equivalent, so it can fire while the command palette is
                // open — dismiss the palette first instead of silently clearing the selection.
                if viewModel?.isCommandPalettePresented == true {
                    viewModel?.isCommandPalettePresented = false
                } else {
                    viewModel?.clearSelection()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var isMultiSelection: Bool {
        (viewModel?.selectedTaskIDs.count ?? 0) > 1
    }

    private func withSelected(_ action: (PlanViewModel, PlanTask) -> Void) {
        guard let viewModel, let task = viewModel.selectedTask else { return }
        action(viewModel, task)
    }

    private func zoom(by delta: CGFloat) {
        guard let viewModel else { return }
        viewModel.zoomScale = min(max(viewModel.zoomScale + delta, GraphMetrics.minZoom), GraphMetrics.maxZoom)
    }
}
