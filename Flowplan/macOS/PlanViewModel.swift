//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import Observation

/// Which central view is shown for the active plan.
public enum PlanViewMode: String, CaseIterable, Sendable {
    case graph
    case list

    var title: String {
        switch self {
        case .graph: "Graph View"
        case .list: "List View"
        }
    }

    var systemImage: String {
        switch self {
        case .graph: "point.3.connected.trianglepath.dotted"
        case .list: "list.bullet"
        }
    }
}

/// A simple, identifiable alert payload (validation errors, blocked-start messages — spec §16).
public struct PlanAlert: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
}

/// View state and actions for the active plan (spec §20.2).
///
/// Owns selection, search, filters, and canvas transform, and routes all mutations through
/// ``PlanStore`` so validation and persistence stay centralised.
@Observable @MainActor
public final class PlanViewModel {

    // MARK: - Dependencies

    @ObservationIgnored
    public weak var store: PlanStore?

    /// The plan currently being viewed/edited.
    public var plan: Plan?

    // MARK: - UI state

    public var viewMode: PlanViewMode = .graph
    public var selectedTaskID: UUID?
    public var selectedDependencyID: UUID?
    public var editingTaskID: UUID?
    public var searchText: String = ""

    /// Focus filters; when non-empty, non-matching tasks are dimmed (spec §11.2).
    public var activeFilters: Set<TaskDisplayState> = []

    public var zoomScale: CGFloat = 1.0
    public var canvasOffset: CGSize = .zero

    /// The content-space point at the centre of the current graph viewport, updated by the canvas.
    /// New tasks created via the menu are placed here.
    @ObservationIgnored
    public var lastViewportCenter: CGPoint = CGPoint(x: 400, y: 300)

    public var activeAlert: PlanAlert?
    public var toastMessage: String?

    public init() {}

    public func configure(store: PlanStore) {
        self.store = store
    }

    // MARK: - Derived lookups

    public var tasks: [PlanTask] {
        (plan?.tasks ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    public var selectedTask: PlanTask? {
        guard let selectedTaskID else { return nil }
        return plan?.task(id: selectedTaskID)
    }

    public func task(id: UUID) -> PlanTask? {
        plan?.task(id: id)
    }

    public func displayState(of task: PlanTask) -> TaskDisplayState {
        plan?.graph.displayState(of: task.id) ?? .readyToStart
    }

    public func blockers(of task: PlanTask) -> [PlanTask] {
        guard let plan else { return [] }
        return plan.graph.blockerIDs(of: task.id).compactMap { plan.task(id: $0) }
    }

    public func prerequisites(of task: PlanTask) -> [PlanTask] {
        guard let plan else { return [] }
        return plan.graph.prerequisiteIDs(of: task.id).compactMap { plan.task(id: $0) }
    }

    public func dependents(of task: PlanTask) -> [PlanTask] {
        guard let plan else { return [] }
        return plan.graph.dependentIDs(of: task.id).compactMap { plan.task(id: $0) }
    }

    public func unlockedByCompleting(_ task: PlanTask) -> [PlanTask] {
        guard let plan else { return [] }
        return plan.graph.unlockedByCompleting(task.id).compactMap { plan.task(id: $0) }
    }

    /// Whether a task matches the current search + filter state (used for dimming).
    public func matchesFilters(_ task: PlanTask) -> Bool {
        if !activeFilters.isEmpty, !activeFilters.contains(displayState(of: task)) {
            return false
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let haystack = ([task.title, task.notes, task.category ?? ""] + task.tags)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
    }

    public func count(of state: TaskDisplayState) -> Int {
        tasks.filter { displayState(of: $0) == state }.count
    }

    // MARK: - Selection

    public func selectTask(_ taskID: UUID?) {
        selectedTaskID = taskID
        selectedDependencyID = nil
    }

    public func selectDependency(_ dependencyID: UUID?) {
        selectedDependencyID = dependencyID
        selectedTaskID = nil
    }

    public func clearSelection() {
        selectedTaskID = nil
        selectedDependencyID = nil
        editingTaskID = nil
    }

    // MARK: - Task actions

    @discardableResult
    public func createTask(at position: CGPoint) -> PlanTask? {
        guard let store, let plan else { return nil }
        let task = store.createTask(in: plan, at: position)
        selectTask(task.id)
        editingTaskID = task.id
        return task
    }

    /// Creates a task at the centre of the current graph viewport (used by the New Task menu item).
    @discardableResult
    public func createTaskAtViewportCenter() -> PlanTask? {
        viewMode = .graph
        return createTask(at: lastViewportCenter)
    }

    public func deleteSelectedTaskOrDependency() {
        guard let store else { return }
        if let task = selectedTask {
            store.deleteTask(task)
            clearSelection()
        } else if let dependencyID = selectedDependencyID,
                  let dependency = plan?.dependencies.first(where: { $0.id == dependencyID }) {
            store.deleteDependency(dependency)
            clearSelection()
        }
    }

    public func duplicateSelectedTask() {
        guard let store, let task = selectedTask else { return }
        let copy = store.duplicateTask(task)
        selectTask(copy.id)
    }

    /// Attempts to start a task, surfacing the blocked message if it is not Ready (spec §10.3, §16.3).
    public func start(_ task: PlanTask) {
        guard let store else { return }
        guard displayState(of: task) == .readyToStart else {
            let names = blockers(of: task).map { "• \($0.title)" }.joined(separator: "\n")
            activeAlert = PlanAlert(
                title: "This task is blocked",
                message: "Finish all dependencies before starting it.\n\n\(names)"
            )
            return
        }
        store.setProgress(.inProgress, for: task)
    }

    /// Marks a task Done and shows a toast if doing so unlocked any dependents (spec §10.4).
    public func markDone(_ task: PlanTask) {
        guard let store else { return }
        let unlocked = unlockedByCompleting(task)
        store.setProgress(.done, for: task)
        if !unlocked.isEmpty {
            let count = unlocked.count
            showToast("\(count) task\(count == 1 ? " is" : "s are") now ready to start.")
        }
    }

    public func setProgress(_ progress: TaskProgress, for task: PlanTask) {
        store?.setProgress(progress, for: task)
    }

    public func reopen(_ task: PlanTask) {
        store?.setProgress(.notStarted, for: task)
    }

    public func moveTask(_ task: PlanTask, to position: CGPoint) {
        store?.updatePosition(position, for: task)
    }

    // MARK: - Dependency actions

    /// Tasks that may be added as a prerequisite of `task` (no self/duplicate/cycle).
    public func candidatePrerequisites(for task: PlanTask) -> [PlanTask] {
        guard let plan else { return [] }
        let graph = plan.graph
        return tasks.filter { candidate in
            candidate.id != task.id
                && (try? graph.validateNewDependency(from: candidate.id, to: task.id)) != nil
        }
    }

    /// Adds `prerequisite ───▶ task` (i.e. `task` depends on `prerequisite`).
    public func addPrerequisite(_ prerequisite: PlanTask, to task: PlanTask) {
        createDependency(from: prerequisite, to: task)
    }

    /// Removes the dependency edge `prerequisite ───▶ task`, if present.
    public func removePrerequisite(_ prerequisite: PlanTask, from task: PlanTask) {
        guard let store, let plan else { return }
        if let edge = plan.dependencies.first(where: {
            $0.prerequisiteTaskID == prerequisite.id && $0.dependentTaskID == task.id
        }) {
            store.deleteDependency(edge)
            if selectedDependencyID == edge.id { selectedDependencyID = nil }
        }
    }

    public func createDependency(from prerequisite: PlanTask, to dependent: PlanTask) {
        guard let store, let plan else { return }
        do {
            let dependency = try store.createDependency(in: plan, from: prerequisite, to: dependent)
            let unlocked = unlockedByCompleting(prerequisite)
            selectDependency(dependency.id)
            _ = unlocked
        } catch let error as DependencyValidationError {
            activeAlert = PlanAlert(title: error.title, message: error.message)
        } catch {
            activeAlert = PlanAlert(title: "Cannot create dependency", message: error.localizedDescription)
        }
    }

    // MARK: - Layout

    public func autoLayout() {
        plan?.applyAutoLayout()
        store?.save()
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        let token = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.toastMessage == token else { return }
            self.toastMessage = nil
        }
    }
}
