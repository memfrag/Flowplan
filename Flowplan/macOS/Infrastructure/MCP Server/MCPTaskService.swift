//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics

/// The MainActor-isolated service layer behind the MCP tools. Resolves project/task references,
/// enforces the same rules the UI does (e.g. the blocked-task guard), and translates to/from
/// ``PlanStore`` calls and agent-facing snapshot types.
///
/// Being `@MainActor` makes this class safe to capture from the `@Sendable` MCP tool-call
/// closures — the compiler proves every call into it is properly isolated.
@MainActor
final class MCPTaskService {

    private let planStore: PlanStore

    init(planStore: PlanStore) {
        self.planStore = planStore
    }

    // MARK: - Projects

    func listProjects() -> [ProjectSnapshot] {
        planStore.allPlans().map(makeProjectSnapshot)
    }

    // MARK: - Tasks

    func listTasks(project: String, state: String?) throws -> [TaskSnapshot] {
        let plan = try resolvePlan(project)
        let graph = plan.graph
        let filterState = try state.map { try parseDisplayState($0) }
        return plan.tasks
            .filter { filterState == nil || graph.displayState(of: $0.id) == filterState }
            .sorted { $0.number < $1.number }
            .map { makeTaskSnapshot($0, in: plan) }
    }

    func getTask(project: String, task: String) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let planTask = try resolveTask(in: plan, query: task)
        return makeTaskSnapshot(planTask, in: plan)
    }

    /// Tasks that are Ready to Start, priority-sorted (high first), then by number.
    func nextReadyTasks(project: String) throws -> [TaskSnapshot] {
        let plan = try resolvePlan(project)
        let graph = plan.graph
        return plan.tasks
            .filter { graph.isReadyToStart($0.id) }
            .sorted { lhs, rhs in
                let lp = priorityRank(lhs.priority), rp = priorityRank(rhs.priority)
                if lp != rp { return lp > rp }
                return lhs.number < rhs.number
            }
            .map { makeTaskSnapshot($0, in: plan) }
    }

    /// The critical path: the longest-duration chain of dependent tasks that sets the project length.
    func criticalPath(project: String) throws -> CriticalPathSnapshot {
        let plan = try resolvePlan(project)
        let graph = plan.graph
        let result = graph.criticalPath(durations: CriticalPathDuration.durations(for: plan.tasks))
        let path = result.orderedPath.compactMap { id -> TaskRef? in
            guard let task = plan.task(id: id) else { return nil }
            return TaskRef(number: task.number, title: task.title, state: graph.displayState(of: task.id).mcpValue)
        }
        return CriticalPathSnapshot(
            totalDuration: PlanViewModel.formatDurationHours(result.totalDuration),
            totalDurationHours: result.totalDuration,
            taskCount: path.count,
            path: path
        )
    }

    @discardableResult
    func createTask(
        project: String,
        title: String,
        details: String?,
        notes: String?,
        category: String?,
        tags: [String]?,
        priority: String?,
        estimateValue: Double?,
        estimateUnit: String?,
        dueDate: String?,
        prerequisites: [String]?
    ) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw MCPToolError.invalidArgument("title must not be empty.")
        }

        let estimate = try makeEstimate(value: estimateValue, unit: estimateUnit)
        let parsedPriority = try priority.map { try parsePriority($0) }
        let parsedDueDate = try dueDate.map { try parseDueDate($0) }

        let task = planStore.createTask(in: plan, title: trimmedTitle, at: nextCanvasPosition(in: plan))
        planStore.updateTask(
            task,
            details: details,
            notes: notes,
            category: category.map { .some($0) },
            tags: tags,
            priority: parsedPriority.map { .some($0) },
            estimate: estimate.map { .some($0) },
            dueDate: parsedDueDate.map { .some($0) }
        )

        var dependencyErrors: [String] = []
        for ref in prerequisites ?? [] {
            do {
                let prerequisite = try resolveTask(in: plan, query: ref)
                try planStore.createDependency(in: plan, from: prerequisite, to: task)
            } catch let error as MCPToolError {
                dependencyErrors.append(error.message)
            } catch let error as DependencyValidationError {
                dependencyErrors.append(MCPToolError.dependencyInvalid(error).message)
            }
        }

        guard dependencyErrors.isEmpty else {
            throw MCPToolError.invalidArgument(
                "Created task #\(task.number) '\(task.title)', but some prerequisites could not be added: "
                    + dependencyErrors.joined(separator: " ")
            )
        }

        return makeTaskSnapshot(task, in: plan)
    }

    @discardableResult
    func updateTask(
        project: String,
        task: String,
        title: String?,
        details: String?,
        notes: String?,
        category: String?,
        tags: [String]?,
        priority: String?,
        estimateValue: Double?,
        estimateUnit: String?,
        dueDate: String?
    ) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let planTask = try resolveTask(in: plan, query: task)

        let categoryUpdate: String??
        if let category {
            categoryUpdate = category.lowercased() == "none" ? .some(nil) : .some(category)
        } else {
            categoryUpdate = nil
        }

        let dueDateUpdate: Date??
        if let dueDate {
            dueDateUpdate = dueDate.lowercased() == "none" ? .some(nil) : .some(try parseDueDate(dueDate))
        } else {
            dueDateUpdate = nil
        }

        let priorityUpdate: TaskPriority??
        if let priority {
            priorityUpdate = priority.lowercased() == "none" ? .some(nil) : .some(try parsePriority(priority))
        } else {
            priorityUpdate = nil
        }

        let estimateUpdate: TaskEstimate??
        if estimateValue != nil || estimateUnit != nil {
            if (estimateValue.map { $0 <= 0 } ?? false) || estimateUnit?.lowercased() == "none" {
                estimateUpdate = .some(nil)
            } else {
                estimateUpdate = .some(try makeEstimate(value: estimateValue, unit: estimateUnit))
            }
        } else {
            estimateUpdate = nil
        }

        planStore.updateTask(
            planTask,
            title: title,
            details: details,
            notes: notes,
            category: categoryUpdate,
            tags: tags,
            priority: priorityUpdate,
            estimate: estimateUpdate,
            dueDate: dueDateUpdate
        )
        return makeTaskSnapshot(planTask, in: plan)
    }

    @discardableResult
    func setTaskState(project: String, task: String, state: String, force: Bool) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let planTask = try resolveTask(in: plan, query: task)
        let progress = try parseProgress(state)

        let isBlocked = plan.graph.displayState(of: planTask.id) == .backlog
        if isBlocked, !force, (progress == .inProgress || progress == .done) {
            let blockers = plan.graph.blockerIDs(of: planTask.id).compactMap { plan.task(id: $0) }
            throw MCPToolError.taskBlocked(
                task: "#\(planTask.number) '\(planTask.title)'",
                blockers: blockers.map { "#\($0.number) '\($0.title)'" }
            )
        }

        planStore.setProgress(progress, for: planTask)
        return makeTaskSnapshot(planTask, in: plan)
    }

    func deleteClosedTasks(project: String) throws -> String {
        let plan = try resolvePlan(project)
        let count = planStore.deleteClosedTasks(in: plan)
        return "Deleted \(count) closed task\(count == 1 ? "" : "s")."
    }

    func deleteTask(project: String, task: String) throws -> String {
        let plan = try resolvePlan(project)
        let planTask = try resolveTask(in: plan, query: task)
        let number = planTask.number
        let title = planTask.title
        let referencing = plan.dependencies.filter {
            $0.prerequisiteTaskID == planTask.id || $0.dependentTaskID == planTask.id
        }.count
        planStore.deleteTask(planTask)
        return "Deleted task #\(number) '\(title)' and \(referencing) dependency edge(s)."
    }

    // MARK: - Dependencies

    @discardableResult
    func addDependency(project: String, prerequisite: String, dependent: String) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let prerequisiteTask = try resolveTask(in: plan, query: prerequisite)
        let dependentTask = try resolveTask(in: plan, query: dependent)
        do {
            try planStore.createDependency(in: plan, from: prerequisiteTask, to: dependentTask)
        } catch let error as DependencyValidationError {
            throw MCPToolError.dependencyInvalid(error)
        }
        return makeTaskSnapshot(dependentTask, in: plan)
    }

    @discardableResult
    func removeDependency(project: String, prerequisite: String, dependent: String) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let prerequisiteTask = try resolveTask(in: plan, query: prerequisite)
        let dependentTask = try resolveTask(in: plan, query: dependent)
        guard let edge = plan.dependencies.first(where: {
            $0.prerequisiteTaskID == prerequisiteTask.id && $0.dependentTaskID == dependentTask.id
        }) else {
            throw MCPToolError.dependencyNotFound
        }
        planStore.deleteDependency(edge)
        return makeTaskSnapshot(dependentTask, in: plan)
    }

    // MARK: - Comments

    @discardableResult
    func addComment(project: String, task: String, text: String, author: String) throws -> TaskSnapshot {
        let plan = try resolvePlan(project)
        let planTask = try resolveTask(in: plan, query: task)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPToolError.invalidArgument("text must not be empty.")
        }
        planStore.addComment(trimmed, author: author, to: planTask)
        return makeTaskSnapshot(planTask, in: plan)
    }

    // MARK: - Addressing

    /// Resolves a project reference by UUID, exact (case-insensitive) title, or unique title prefix.
    private func resolvePlan(_ query: String) throws -> Plan {
        let plans = planStore.allPlans()
        if let uuid = UUID(uuidString: query), let match = plans.first(where: { $0.id == uuid }) {
            return match
        }
        let lowered = query.lowercased()
        if let exact = plans.first(where: { $0.title.lowercased() == lowered }) {
            return exact
        }
        let prefixMatches = plans.filter { $0.title.lowercased().hasPrefix(lowered) }
        if prefixMatches.count == 1 {
            return prefixMatches[0]
        }
        if prefixMatches.count > 1 {
            throw MCPToolError.ambiguousProject(query: query, matches: prefixMatches.map(\.title))
        }
        throw MCPToolError.projectNotFound(query: query, available: plans.map(\.title))
    }

    /// Resolves a task reference within a project by its stable per-project number (preferred,
    /// matches the `#N` shown in the UI) or by UUID.
    private func resolveTask(in plan: Plan, query: String) throws -> PlanTask {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if let number = Int(normalized), let match = plan.tasks.first(where: { $0.number == number }) {
            return match
        }
        if let uuid = UUID(uuidString: trimmed), let match = plan.task(id: uuid) {
            return match
        }
        throw MCPToolError.taskNotFound(project: plan.title, query: query)
    }

    // MARK: - Parsing

    private func parseDisplayState(_ value: String) throws -> TaskDisplayState {
        switch value {
        case "blocked": return .backlog
        case "ready": return .readyToStart
        case "in_progress": return .inProgress
        case "done": return .done
        case "closed": return .closed
        default:
            throw MCPToolError.invalidArgument("Unknown state \"\(value)\". Use blocked, ready, in_progress, done, or closed.")
        }
    }

    private func parseProgress(_ value: String) throws -> TaskProgress {
        guard let progress = TaskProgress(mcpValue: value) else {
            throw MCPToolError.invalidArgument("Unknown state \"\(value)\". Use not_started, in_progress, done, or closed.")
        }
        return progress
    }

    private func parsePriority(_ value: String) throws -> TaskPriority {
        guard let priority = TaskPriority(mcpValue: value) else {
            throw MCPToolError.invalidArgument("Unknown priority \"\(value)\". Use low, medium, or high.")
        }
        return priority
    }

    private func makeEstimate(value: Double?, unit: String?) throws -> TaskEstimate? {
        guard let value, let unit else {
            if value != nil || unit != nil {
                throw MCPToolError.invalidArgument("estimate_value and estimate_unit must be provided together.")
            }
            return nil
        }
        guard let parsedUnit = EstimateUnit(mcpValue: unit) else {
            throw MCPToolError.invalidArgument("Unknown estimate unit \"\(unit)\". Use minutes, hours, or days.")
        }
        return TaskEstimate(value: value, unit: parsedUnit)
    }

    /// Parses an ISO 8601 date. Accepts a plain `YYYY-MM-DD` (normalized to the start of that day)
    /// or a full ISO 8601 timestamp.
    private func parseDueDate(_ value: String) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .iso8601)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current
        if let date = dayFormatter.date(from: trimmed) {
            return Calendar.current.startOfDay(for: date)
        }
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }
        throw MCPToolError.invalidArgument("Unknown date \"\(value)\". Use YYYY-MM-DD (or an ISO 8601 timestamp).")
    }

    private func priorityRank(_ priority: TaskPriority?) -> Int {
        switch priority {
        case .high: 2
        case .medium: 1
        case .low: 0
        case nil: -1
        }
    }

    // MARK: - Placement

    /// A deterministic spot for a newly created task: one row below the plan's existing bounding
    /// box, left-aligned. Never runs the plan-wide auto-layout, so it doesn't disturb the user's
    /// existing card positions.
    private func nextCanvasPosition(in plan: Plan) -> CGPoint {
        let positioned = plan.tasks.compactMap(\.position)
        guard let maxY = positioned.map(\.y).max() else {
            return CGPoint(x: 120, y: 100)
        }
        let minX = positioned.map(\.x).min() ?? 120
        return CGPoint(x: minX, y: maxY + 130)
    }

    // MARK: - Snapshot construction

    private func makeProjectSnapshot(_ plan: Plan) -> ProjectSnapshot {
        let graph = plan.graph
        var counts: [String: Int] = [:]
        for task in plan.tasks {
            let state = graph.displayState(of: task.id).mcpValue
            counts[state, default: 0] += 1
        }
        return ProjectSnapshot(
            id: plan.id,
            title: plan.title,
            summary: plan.summary.isEmpty ? nil : plan.summary,
            group: plan.group.isEmpty ? nil : plan.group,
            repositoryURLs: plan.repositoryURLs,
            taskCounts: counts,
            updatedAt: plan.updatedAt
        )
    }

    private func makeTaskSnapshot(_ task: PlanTask, in plan: Plan) -> TaskSnapshot {
        let graph = plan.graph
        func ref(_ id: UUID) -> TaskRef? {
            guard let t = plan.task(id: id) else { return nil }
            return TaskRef(number: t.number, title: t.title, state: graph.displayState(of: t.id).mcpValue)
        }
        return TaskSnapshot(
            id: task.id,
            number: task.number,
            title: task.title,
            details: task.details.isEmpty ? nil : task.details,
            notes: task.notes.isEmpty ? nil : task.notes,
            progress: task.progress.mcpValue,
            state: graph.displayState(of: task.id).mcpValue,
            category: task.category,
            tags: task.tags,
            priority: task.priority?.rawValue,
            estimate: task.estimate?.displayText,
            dueDate: task.dueDate,
            overdue: task.isOverdue,
            blockedBy: graph.blockerIDs(of: task.id).compactMap(ref),
            prerequisites: graph.prerequisiteIDs(of: task.id).compactMap(ref),
            dependents: graph.dependentIDs(of: task.id).compactMap(ref),
            comments: task.comments
                .sorted { $0.createdAt < $1.createdAt }
                .map { CommentSnapshot(author: $0.author, text: $0.text, createdAt: $0.createdAt) },
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }
}
