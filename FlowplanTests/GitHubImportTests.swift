//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import Flowplan

/// Tests for the GitHub import mapping: field/state mapping, idempotent re-import, dependency
/// inference, repository-URL parsing, and wire decoding. Network is not exercised — `apply(...)` is
/// the pure, fetch-free entry point.
@MainActor
struct GitHubImportTests {

    /// Runs `body` with a fresh in-memory store + service + a plan, holding the container alive.
    private func withService(_ body: (PlanStore, GitHubImportService, Plan) throws -> Void) rethrows {
        let container = AppEnvironment.makeModelContainer(inMemory: true)
        let store = PlanStore(modelContext: container.mainContext)
        let service = GitHubImportService(planStore: store)
        let plan = store.createPlan(title: "Repo")
        try withExtendedLifetime(container) {
            try body(store, service, plan)
        }
    }

    private func issue(
        _ number: Int, _ title: String, body: String? = nil,
        state: String = "open", reason: String? = nil, labels: [String] = []
    ) -> GitHubIssue {
        GitHubIssue(
            number: number, title: title, body: body,
            htmlURL: "https://github.com/o/r/issues/\(number)",
            state: state, stateReason: reason,
            labels: labels.map { GitHubLabel(name: $0) },
            pullRequest: nil
        )
    }

    @Test func mapsFieldsAndState() {
        withService { _, service, plan in
            let summary = service.apply(issues: [
                issue(1, "Open one", body: "do the thing", labels: ["bug", "p1"]),
                issue(2, "Done one", state: "closed", reason: "completed"),
                issue(3, "Wontfix", state: "closed", reason: "not_planned")
            ], owner: "o", repo: "r", to: plan)

            #expect(summary.created == 3)
            #expect(summary.updated == 0)
            #expect(plan.tasks.count == 3)

            let byID = Dictionary(uniqueKeysWithValues: plan.tasks.compactMap { task in
                task.externalID.map { ($0, task) }
            })
            let first = byID["o/r#1"]!
            #expect(first.title == "Open one")
            #expect(first.details == "do the thing")
            #expect(Set(first.tags) == ["bug", "p1"])
            #expect(first.progress == .notStarted)
            #expect(first.externalSource == "github")
            #expect(first.externalURL == "https://github.com/o/r/issues/1")
            #expect(byID["o/r#2"]!.progress == .done)
            #expect(byID["o/r#3"]!.progress == .closed)
        }
    }

    @Test func reimportUpdatesPreservingUserFields() {
        withService { store, service, plan in
            _ = service.apply(issues: [issue(1, "Title A", state: "open")], owner: "o", repo: "r", to: plan)
            let task = plan.tasks.first!
            store.updatePosition(CGPoint(x: 999, y: 888), for: task)
            store.updateTask(task, notes: "my note")

            let summary = service.apply(
                issues: [issue(1, "Title A renamed", state: "closed", reason: "completed")],
                owner: "o", repo: "r", to: plan
            )

            #expect(summary.created == 0)
            #expect(summary.updated == 1)
            #expect(plan.tasks.count == 1)            // not duplicated
            #expect(task.title == "Title A renamed")  // synced from GitHub
            #expect(task.progress == .done)
            #expect(task.position == CGPoint(x: 999, y: 888)) // user placement preserved
            #expect(task.notes == "my note")                  // user notes preserved
        }
    }

    @Test func infersDependenciesFromTaskList() {
        withService { _, service, plan in
            let summary = service.apply(issues: [
                issue(1, "Prereq"),
                issue(2, "Parent", body: "Subtasks:\n- [ ] #1\n")
            ], owner: "o", repo: "r", to: plan)

            #expect(summary.dependenciesLinked == 1)
            #expect(plan.dependencies.count == 1)

            let prereq = plan.tasks.first { $0.externalID == "o/r#1" }!
            let parent = plan.tasks.first { $0.externalID == "o/r#2" }!
            let dependency = plan.dependencies.first!
            #expect(dependency.prerequisiteTaskID == prereq.id)
            #expect(dependency.dependentTaskID == parent.id)

            // Re-import must not duplicate the edge (createDependency's duplicate guard is swallowed).
            let again = service.apply(issues: [
                issue(1, "Prereq"),
                issue(2, "Parent", body: "Subtasks:\n- [ ] #1\n")
            ], owner: "o", repo: "r", to: plan)
            #expect(again.dependenciesLinked == 0)
            #expect(plan.dependencies.count == 1)
        }
    }

    @Test func referenceOutsideImportIsSkipped() {
        withService { _, service, plan in
            let summary = service.apply(
                issues: [issue(2, "Parent", body: "- [ ] #404\n")],
                owner: "o", repo: "r", to: plan
            )
            #expect(summary.dependenciesLinked == 0)
            #expect(summary.skippedReferences == 1)
            #expect(plan.dependencies.isEmpty)
        }
    }

    @Test func parseRepoVariants() {
        #expect(GitHubClient.parseRepo(from: "https://github.com/owner/repo")?.owner == "owner")
        #expect(GitHubClient.parseRepo(from: "https://github.com/owner/repo")?.repo == "repo")
        #expect(GitHubClient.parseRepo(from: "https://github.com/owner/repo.git")?.repo == "repo")
        #expect(GitHubClient.parseRepo(from: "https://github.com/owner/repo/")?.repo == "repo")
        #expect(GitHubClient.parseRepo(from: "git@github.com:owner/repo.git")?.owner == "owner")
        #expect(GitHubClient.parseRepo(from: "https://gitlab.com/owner/repo") == nil)
        #expect(GitHubClient.parseRepo(from: "not a url") == nil)
    }

    @Test func referencedNumbersAreConservative() {
        let body = """
        Intro mentions #99 casually.
        - [ ] #1
        - [x] #2
        Depends on #3 and #4
        * [ ] #5
        """
        let numbers = Set(GitHubImportService.referencedIssueNumbers(inBody: body))
        #expect(numbers == [1, 2, 3, 4, 5])
        #expect(!numbers.contains(99))
    }

    @Test func decodesIssuesAndFlagsPullRequests() throws {
        let json = """
        [
          {"number":1,"title":"Issue","body":"b","html_url":"https://github.com/o/r/issues/1","state":"open","state_reason":null,"labels":[{"name":"bug"}]},
          {"number":2,"title":"A PR","body":null,"html_url":"https://github.com/o/r/pull/2","state":"open","labels":[],"pull_request":{"url":"x"}}
        ]
        """
        let issues = try JSONDecoder().decode([GitHubIssue].self, from: Data(json.utf8))
        #expect(issues.count == 2)
        #expect(issues[0].pullRequest == nil)
        #expect(issues[1].pullRequest != nil) // filtered out during import
        #expect(issues[0].labels.first?.name == "bug")
        #expect(issues[0].htmlURL == "https://github.com/o/r/issues/1")
    }
}
