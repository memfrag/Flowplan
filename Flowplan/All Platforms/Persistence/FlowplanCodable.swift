//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

// MARK: - Codable transfer objects (spec §17.2)
//
// These plain `Codable` structs are the on-disk shape of a `.flowplan` file and the bridge for
// JSON import/export. They are intentionally decoupled from the SwiftData `@Model` types.

nonisolated public struct PlanDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tasks: [TaskDTO]
    public var dependencies: [DependencyDTO]
    public var icon: String? = nil
    public var summary: String? = nil
    public var repositoryURLs: [String]? = nil
    public var nextTaskNumber: Int? = nil
}

nonisolated public struct TaskDTO: Codable, Sendable {
    public var id: UUID
    public var number: Int? = nil
    public var title: String
    public var details: String? = nil
    public var notes: String
    public var progress: TaskProgress
    public var category: String?
    public var tags: [String]
    public var priority: TaskPriority?
    public var estimate: TaskEstimate?
    public var position: PointDTO?
    public var dueDate: Date? = nil
    public var comments: [CommentDTO]? = nil
    public var createdAt: Date
    public var updatedAt: Date
}

nonisolated public struct CommentDTO: Codable, Sendable {
    public var id: UUID
    public var author: String
    public var text: String
    public var createdAt: Date
}

nonisolated public struct DependencyDTO: Codable, Sendable {
    public var id: UUID
    public var prerequisiteTaskID: UUID
    public var dependentTaskID: UUID
}

nonisolated public struct PointDTO: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
}

// MARK: - Model -> DTO

extension PlanDTO {

    public init(plan: Plan) {
        self.id = plan.id
        self.title = plan.title
        self.createdAt = plan.createdAt
        self.updatedAt = plan.updatedAt
        self.icon = plan.icon
        self.summary = plan.summary.isEmpty ? nil : plan.summary
        self.repositoryURLs = plan.repositoryURLs.isEmpty ? nil : plan.repositoryURLs
        self.nextTaskNumber = plan.nextTaskNumber
        self.tasks = plan.tasks
            .sorted { $0.createdAt < $1.createdAt }
            .map(TaskDTO.init(task:))
        self.dependencies = plan.dependencies.map { dependency in
            DependencyDTO(
                id: dependency.id,
                prerequisiteTaskID: dependency.prerequisiteTaskID,
                dependentTaskID: dependency.dependentTaskID
            )
        }
    }
}

extension TaskDTO {

    public init(task: PlanTask) {
        self.id = task.id
        self.number = task.number
        self.title = task.title
        self.details = task.details.isEmpty ? nil : task.details
        self.notes = task.notes
        self.progress = task.progress
        self.category = task.category
        self.tags = task.tags
        self.priority = task.priority
        self.estimate = task.estimate
        self.position = task.position.map { PointDTO(x: Double($0.x), y: Double($0.y)) }
        self.dueDate = task.dueDate
        let comments = task.comments.sorted { $0.createdAt < $1.createdAt }.map { comment in
            CommentDTO(id: comment.id, author: comment.author, text: comment.text, createdAt: comment.createdAt)
        }
        self.comments = comments.isEmpty ? nil : comments
        self.createdAt = task.createdAt
        self.updatedAt = task.updatedAt
    }
}

// MARK: - DTO -> Model

extension PlanDTO {

    /// Builds a fresh `Plan` (with its tasks and dependencies) from this DTO, ready to insert into
    /// a `ModelContext`.
    @MainActor public func makePlan() -> Plan {
        let plan = Plan(
            id: id,
            title: title,
            icon: icon ?? "folder",
            summary: summary ?? "",
            repositoryURLs: repositoryURLs ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        // Assign numbers from the DTO, backfilling any that are missing (older exports) by
        // creation order so the plan's numbering stays stable and collision-free.
        var counter = max(
            nextTaskNumber ?? 0,
            (tasks.compactMap(\.number).max() ?? 0) + 1
        )
        var numberByTaskID: [UUID: Int] = [:]
        for dto in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let number = dto.number, number > 0 {
                numberByTaskID[dto.id] = number
            } else {
                numberByTaskID[dto.id] = counter
                counter += 1
            }
        }
        plan.nextTaskNumber = max(counter, (numberByTaskID.values.max() ?? 0) + 1)
        plan.tasks = tasks.map { dto in
            let task = PlanTask(
                id: dto.id,
                number: numberByTaskID[dto.id] ?? 0,
                title: dto.title,
                details: dto.details ?? "",
                notes: dto.notes,
                progress: dto.progress,
                category: dto.category,
                tags: dto.tags,
                priority: dto.priority,
                estimate: dto.estimate,
                position: dto.position.map { CGPoint(x: $0.x, y: $0.y) },
                dueDate: dto.dueDate,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            task.comments = (dto.comments ?? []).map { commentDTO in
                let comment = TaskComment(
                    id: commentDTO.id,
                    author: commentDTO.author,
                    text: commentDTO.text,
                    createdAt: commentDTO.createdAt
                )
                comment.task = task
                return comment
            }
            return task
        }
        plan.dependencies = dependencies.map { dto in
            TaskDependency(
                id: dto.id,
                prerequisiteTaskID: dto.prerequisiteTaskID,
                dependentTaskID: dto.dependentTaskID
            )
        }
        return plan
    }
}

// MARK: - JSON coding

extension PlanDTO {

    nonisolated public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated public func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    nonisolated public init(jsonData: Data) throws {
        self = try Self.makeDecoder().decode(PlanDTO.self, from: jsonData)
    }
}
