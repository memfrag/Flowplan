//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import Observation

/// Which central view is shown for the active plan.
public enum PlanViewMode: String, CaseIterable, Sendable {
    case graph
    case list
    case board

    var title: String {
        switch self {
        case .graph: "Graph View"
        case .list: "List View"
        case .board: "Board View"
        }
    }

    var systemImage: String {
        switch self {
        case .graph: "point.3.connected.trianglepath.dotted"
        case .list: "list.bullet"
        case .board: "rectangle.split.3x1"
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

    /// When true, the detail area shows the Overview dashboard instead of the graph/list.
    /// Any change of ``viewMode`` (via the sidebar, commands, or actions) leaves the overview.
    public var showOverview: Bool = false

    public var viewMode: PlanViewMode = .graph {
        didSet { showOverview = false }
    }
    /// The set of currently selected tasks. Multi-selection is driven by shift-clicking cards or
    /// shift-dragging a marquee on the canvas.
    public var selectedTaskIDs: Set<UUID> = []

    /// The sole selected task, when exactly one is selected — used by single-task UI (the inspector,
    /// the list's selection binding, "Edit Title"). `nil` when zero or multiple tasks are selected.
    public var selectedTaskID: UUID? {
        selectedTaskIDs.count == 1 ? selectedTaskIDs.first : nil
    }

    public var selectedDependencyID: UUID?
    public var editingTaskID: UUID?
    public var searchText: String = ""

    /// Presents (and focuses) the toolbar search field — bound to `.searchable`, set by ⌘F.
    public var isSearchPresented: Bool = false

    /// Presents the command palette overlay (⌘K).
    public var isCommandPalettePresented: Bool = false

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

    /// Every currently selected task, in the plan's stable order.
    public var selectedTasks: [PlanTask] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    public func isSelected(_ taskID: UUID) -> Bool {
        selectedTaskIDs.contains(taskID)
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
        matches(task, displayState: displayState(of: task))
    }

    /// Filter/search match using an already-computed display state (avoids rebuilding the graph).
    public func matches(_ task: PlanTask, displayState: TaskDisplayState) -> Bool {
        if !activeFilters.isEmpty, !activeFilters.contains(displayState) {
            return false
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let haystack = ([task.title, task.details, task.notes, task.category ?? ""] + task.tags)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
    }

    // MARK: - Render snapshot

    /// A per-render snapshot of everything the graph canvas needs, computed from a single
    /// `TaskGraph` build and one sorted pass — so the canvas doesn't rebuild the graph per card
    /// or do O(N) id lookups per edge on every frame.
    public struct RenderSnapshot {
        public var orderedTasks: [PlanTask]
        public var taskByID: [UUID: PlanTask]
        public var displayStateByID: [UUID: TaskDisplayState]
        public var numberByID: [UUID: Int]

        public func displayState(of task: PlanTask) -> TaskDisplayState {
            displayStateByID[task.id] ?? .readyToStart
        }

        public func number(of task: PlanTask) -> Int {
            numberByID[task.id] ?? 0
        }
    }

    public func renderSnapshot() -> RenderSnapshot {
        guard let plan else {
            return RenderSnapshot(orderedTasks: [], taskByID: [:], displayStateByID: [:], numberByID: [:])
        }
        // The graph is built from *all* tasks (so closed prerequisites are known to be resolved),
        // but closed tasks — and the edges touching them — are hidden from the graph canvas.
        let graph = plan.graph
        let visible = tasks.filter { $0.progress != .closed }
        var taskByID: [UUID: PlanTask] = [:]
        var displayStateByID: [UUID: TaskDisplayState] = [:]
        var numberByID: [UUID: Int] = [:]
        taskByID.reserveCapacity(visible.count)
        for task in visible {
            taskByID[task.id] = task
            displayStateByID[task.id] = graph.displayState(of: task.id)
            numberByID[task.id] = task.number
        }
        return RenderSnapshot(
            orderedTasks: visible,
            taskByID: taskByID,
            displayStateByID: displayStateByID,
            numberByID: numberByID
        )
    }

    public func count(of state: TaskDisplayState) -> Int {
        tasks.filter { displayState(of: $0) == state }.count
    }

    // MARK: - Selection

    /// Replaces the selection with a single task (or clears it when `nil`).
    public func selectTask(_ taskID: UUID?) {
        selectedTaskIDs = taskID.map { [$0] } ?? []
        selectedDependencyID = nil
    }

    /// Replaces the selection with an explicit set of tasks (used by the marquee).
    public func setSelectedTasks(_ ids: Set<UUID>) {
        selectedTaskIDs = ids
        if !ids.isEmpty { selectedDependencyID = nil }
    }

    /// Adds or removes a task from the selection (shift-click).
    public func toggleSelection(_ taskID: UUID) {
        if selectedTaskIDs.contains(taskID) {
            selectedTaskIDs.remove(taskID)
        } else {
            selectedTaskIDs.insert(taskID)
        }
        selectedDependencyID = nil
    }

    public func selectDependency(_ dependencyID: UUID?) {
        selectedDependencyID = dependencyID
        selectedTaskIDs = []
    }

    /// Shows the Overview dashboard and clears any active focus filter.
    public func openOverview() {
        activeFilters = []
        showOverview = true
    }

    /// Focuses a single display state — graph (dimming non-matches) or list for Closed.
    public func focus(on state: TaskDisplayState) {
        activeFilters = [state]
        viewMode = (state == .closed) ? .list : .graph
    }

    /// Selects a task and reveals it on the graph (leaving the overview/list).
    public func openTaskInGraph(_ task: PlanTask) {
        viewMode = .graph
        selectTask(task.id)
    }

    public func clearSelection() {
        selectedTaskIDs = []
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
        let tasksToDelete = selectedTasks
        if !tasksToDelete.isEmpty {
            for task in tasksToDelete {
                store.deleteTask(task)
            }
            clearSelection()
        } else if let dependencyID = selectedDependencyID,
                  let dependency = plan?.dependencies.first(where: { $0.id == dependencyID }) {
            store.deleteDependency(dependency)
            clearSelection()
        }
    }

    // MARK: - Bulk task actions

    /// Applies a progress value directly to every selected task (used by bulk state changes). Unlike
    /// ``start(_:)`` this does not enforce the "blocked" guard — the user is acting deliberately on a
    /// whole selection, so we set the state and let the graph re-derive display states.
    public func setProgressForSelected(_ progress: TaskProgress) {
        guard let store else { return }
        let targets = selectedTasks
        guard !targets.isEmpty else { return }
        let unlocked: Set<UUID> = progress == .done
            ? Set(targets.flatMap { unlockedByCompleting($0).map(\.id) }).subtracting(selectedTaskIDs)
            : []
        for task in targets {
            store.setProgress(progress, for: task)
        }
        if progress == .done, !unlocked.isEmpty {
            let count = unlocked.count
            showToast("\(count) task\(count == 1 ? " is" : "s are") now ready to start.")
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
            presentBlockedAlert(for: task)
            return
        }
        store.setProgress(.inProgress, for: task)
    }

    /// Explains why a blocked (Backlog) task can't be started or made Ready — it still has unfinished
    /// dependencies.
    private func presentBlockedAlert(for task: PlanTask) {
        let names = blockers(of: task).map { "• \($0.title)" }.joined(separator: "\n")
        activeAlert = PlanAlert(
            title: "This task is blocked",
            message: "Finish all dependencies before starting it.\n\n\(names)"
        )
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

    /// Closes a task: hidden from the graph and treated as resolved for its dependents.
    public func close(_ task: PlanTask) {
        store?.setProgress(.closed, for: task)
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

    // MARK: - Board

    /// Applies the state change implied by dropping `task` into the board column for `target`
    /// (spec §13). Returns `false` if the drop is not allowed (e.g. Backlog is derived, or the task
    /// is still blocked), in which case the board should leave the card where it was.
    @discardableResult
    public func moveTask(_ task: PlanTask, toBoardColumn target: TaskDisplayState) -> Bool {
        switch target {
        case .backlog:
            // Backlog is a derived state — a task lands there on its own when it has unfinished
            // dependencies. It is never a direct drop target.
            return false
        case .readyToStart:
            // "Ready" is derived from having all dependencies resolved — it can't be forced. If the
            // task is still blocked, explain that instead of silently doing nothing.
            if displayState(of: task) == .backlog {
                presentBlockedAlert(for: task)
                return false
            }
            setProgress(.notStarted, for: task)
        case .inProgress:
            // Allowed from Ready (or when otherwise unblocked); blocked when the task still has
            // unfinished dependencies. Reuse `start`'s guard, which surfaces the blocked alert.
            if displayState(of: task) == .backlog {
                start(task)
                return false
            }
            setProgress(.inProgress, for: task)
        case .done:
            markDone(task)
        case .closed:
            close(task)
        }
        return true
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
