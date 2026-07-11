//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics
import OSLog

/// Imports a GitHub repository's issues into a plan as tasks, one way. Re-running updates existing
/// tasks in place (matched by external identity) rather than duplicating them.
///
/// The network fetch lives in ``GitHubClient``; this type owns the *mapping* — issue → task fields,
/// state, labels, and best-effort dependency inference — and all writes go through ``PlanStore``.
@MainActor
final class GitHubImportService {

    private let planStore: PlanStore
    private let log = Logger(subsystem: "io.apparata.Flowplan", category: "GitHubImport")

    /// The `externalSource` tag stamped on imported tasks.
    static let source = "github"

    /// New tasks are laid out in a grid this many columns wide, below the existing bounding box.
    private static let gridColumns = 5
    private static let gridStepX: CGFloat = 220
    private static let gridStepY: CGFloat = 130

    init(planStore: PlanStore) {
        self.planStore = planStore
    }

    /// Fetches issues for the repository at `repoURL` and applies them to `plan`.
    func importIssues(from repoURL: String, into plan: Plan) async throws -> ImportSummary {
        guard let token = Keychain.get(account: Keychain.Account.githubToken), !token.isEmpty else {
            throw GitHubError.missingToken
        }
        guard let (owner, repo) = GitHubClient.parseRepo(from: repoURL) else {
            throw GitHubError.badRepositoryURL
        }
        let client = GitHubClient(token: token)
        let issues = try await client.issues(owner: owner, repo: repo)
        return apply(issues: issues, owner: owner, repo: repo, to: plan)
    }

    /// Network-free application of already-fetched issues to a plan. Exposed for testing.
    @discardableResult
    func apply(issues: [GitHubIssue], owner: String, repo: String, to plan: Plan) -> ImportSummary {
        var summary = ImportSummary()

        // Existing imported tasks, keyed by external id, so re-import updates in place.
        var taskByExternalID: [String: PlanTask] = [:]
        for task in plan.tasks where task.externalSource == Self.source {
            if let id = task.externalID { taskByExternalID[id] = task }
        }

        // Maps this import's issue numbers to their task, for wiring dependencies afterwards.
        var taskByNumber: [Int: PlanTask] = [:]
        var origin = gridOrigin(in: plan)
        var placedCount = 0

        for issue in issues {
            let externalID = Self.externalID(owner: owner, repo: repo, number: issue.number)
            let details = issue.body ?? ""
            let tags = issue.labels.map(\.name)

            if let existing = taskByExternalID[externalID] {
                planStore.updateTask(existing, title: issue.title, details: details, tags: tags)
                planStore.setProgress(Self.progress(for: issue), for: existing)
                taskByNumber[issue.number] = existing
                summary.updated += 1
            } else {
                let position = gridPosition(origin: origin, index: placedCount)
                placedCount += 1
                let task = planStore.createTask(in: plan, title: issue.title, at: position)
                planStore.updateTask(task, details: details, tags: tags)
                planStore.setProgress(Self.progress(for: issue), for: task)
                planStore.setExternalReference(
                    source: Self.source, id: externalID, url: issue.htmlURL, for: task
                )
                taskByNumber[issue.number] = task
                summary.created += 1
            }
        }

        // Best-effort dependency inference from task-list / "depends on" references in bodies.
        // A reference `#B` inside issue A's body reads as: B is a prerequisite of A (B ──▶ A).
        for issue in issues {
            guard let dependent = taskByNumber[issue.number] else { continue }
            for prerequisiteNumber in Self.referencedIssueNumbers(inBody: issue.body) {
                guard prerequisiteNumber != issue.number else { continue }
                guard let prerequisite = taskByNumber[prerequisiteNumber] else {
                    summary.skippedReferences += 1   // points outside this import
                    continue
                }
                do {
                    try planStore.createDependency(in: plan, from: prerequisite, to: dependent)
                    summary.dependenciesLinked += 1
                } catch {
                    // Duplicate/self/cycle — expected and harmless for inferred edges.
                }
            }
        }

        log.info("Imported \(owner)/\(repo): \(summary.created) created, \(summary.updated) updated, \(summary.dependenciesLinked) linked")
        return summary
    }

    // MARK: - Mapping helpers

    static func externalID(owner: String, repo: String, number: Int) -> String {
        "\(owner)/\(repo)#\(number)"
    }

    /// Maps GitHub issue state to Flowplan progress. Open → Not Started; closed-as-completed → Done;
    /// closed-as-not-planned → Closed. There is no GitHub equivalent of In Progress.
    static func progress(for issue: GitHubIssue) -> TaskProgress {
        guard issue.state != "open" else { return .notStarted }
        return issue.stateReason == "not_planned" ? .closed : .done
    }

    /// Extracts `#N` issue numbers from lines that look like task-list items or dependency notes.
    /// Deliberately conservative to avoid treating incidental cross-references as dependencies.
    static func referencedIssueNumbers(inBody body: String?) -> [Int] {
        guard let body else { return [] }
        var numbers: [Int] = []
        for rawLine in body.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            let isTaskItem = ["- [ ]", "- [x]", "* [ ]", "* [x]"].contains { lower.hasPrefix($0) }
            let isDependency = lower.contains("depends on") || lower.contains("blocked by")
            guard isTaskItem || isDependency else { continue }
            numbers.append(contentsOf: hashNumbers(in: line))
        }
        return numbers
    }

    private static func hashNumbers(in line: String) -> [Int] {
        var result: [Int] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            guard characters[index] == "#" else { index += 1; continue }
            var cursor = index + 1
            var digits = ""
            while cursor < characters.count, characters[cursor].isNumber {
                digits.append(characters[cursor])
                cursor += 1
            }
            if let number = Int(digits) { result.append(number) }
            index = cursor
        }
        return result
    }

    // MARK: - Placement

    /// A deterministic starting point one row below the plan's existing card bounding box.
    private func gridOrigin(in plan: Plan) -> CGPoint {
        let positioned = plan.tasks.compactMap(\.position)
        guard let maxY = positioned.map(\.y).max() else { return CGPoint(x: 120, y: 100) }
        let minX = positioned.map(\.x).min() ?? 120
        return CGPoint(x: minX, y: maxY + Self.gridStepY)
    }

    private func gridPosition(origin: CGPoint, index: Int) -> CGPoint {
        let column = index % Self.gridColumns
        let row = index / Self.gridColumns
        return CGPoint(
            x: origin.x + CGFloat(column) * Self.gridStepX,
            y: origin.y + CGFloat(row) * Self.gridStepY
        )
    }
}

/// The outcome of an import, for a result alert.
nonisolated struct ImportSummary: Sendable {
    var created = 0
    var updated = 0
    var dependenciesLinked = 0
    var skippedReferences = 0

    /// A human-readable one-liner, e.g. "Created 12, updated 3, linked 5 dependencies".
    var message: String {
        var parts = ["Created \(created)", "updated \(updated)"]
        if dependenciesLinked > 0 { parts.append("linked \(dependenciesLinked) dependenc\(dependenciesLinked == 1 ? "y" : "ies")") }
        return parts.joined(separator: ", ") + "."
    }
}
