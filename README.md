# Flowplan

**See what's blocked, ready, and next.**

Flowplan is a native macOS app for planning work as a **dependency graph** instead of a flat to-do list. Each task can depend on other tasks, and a task only becomes actionable once everything it depends on is done. Flowplan makes that visible: tasks are connected cards on a canvas, and each task's state is derived automatically from its dependencies.

It answers questions a normal to-do app can't:

- What can I start right now?
- What is blocked, and by what?
- What gets unlocked when I finish this task?
- How does one task fit into the larger plan?

## Derived task states

You set a simple manual progress on each task — **Not Started**, **In Progress**, or **Done** — and Flowplan derives the state you actually see:

| State | Meaning |
|---|---|
| ⬜ **Backlog** | Not done and at least one dependency isn't done — blocked, can't be started yet |
| 🔵 **Ready to Start** | Not started, and every dependency is Done |
| 🟠 **In Progress** | Started, with all dependencies Done |
| 🟢 **Done** | Completed |

Because Backlog and Ready to Start are computed, finishing one task can instantly unlock others downstream.

## Features

- **Graph canvas** — draggable, colour-coded task cards over a dotted grid, with dependency arrows drawn between them. Pan, zoom, and select.
- **Create dependencies** by dragging from a card's handle to another card, or via the inspector — with automatic validation that prevents self-dependencies, duplicates, and cycles (the graph stays a DAG).
- **Remove dependencies** by clicking the delete marker on a connector or from the inspector.
- **Auto layout** — a layered, left-to-right topological arrangement, re-runnable from the toolbar.
- **Inspector** — edit a task's title, progress, priority, estimate, tags, and notes; see its blockers, dependencies, next tasks, and what completing it would unlock. Backlog tasks explain exactly why they're blocked.
- **List view** — a sortable table for quickly scanning and editing task metadata.
- **Focus filters & search** — filter by state (Backlog / Ready / In Progress / Done) and search titles, notes, tags, and categories; non-matching tasks dim so context is preserved.
- **Multiple plans** managed in one window.
- **Export** to `.flowplan` (JSON), a Markdown summary, or a PNG of the graph.
- **Local-first persistence** with SwiftData.

## Requirements

- macOS 26 or later
- Xcode 26 (Swift 6.2) to build

## Building

```sh
git clone git@github.com:memfrag/Flowplan.git
cd Flowplan
open Flowplan.xcodeproj
```

Build and run the **Flowplan** scheme. Swift Package Manager resolves dependencies automatically. On first launch the app seeds a sample "Product Launch Plan" so you can explore the graph immediately.

## Tests

The core graph engine (state derivation, readiness, cycle prevention, layout) is pure and unit-tested with Swift Testing. Run the `FlowplanTests` target from Xcode, or:

```sh
xcodebuild test -project Flowplan.xcodeproj -scheme "Flowplan (Debug)" -destination 'platform=macOS'
```

## Architecture

- **Models** — SwiftData `@Model` types (`Plan`, `PlanTask`, `TaskDependency`) plus value enums for progress, state, priority, and estimate.
- **Graph** — a pure, `Sendable` `TaskGraph` over task IDs and edges: display-state derivation, neighbour/blocker queries, cycle detection, and layered layout. No SwiftData or SwiftUI dependencies, so it's trivially testable.
- **Persistence** — `PlanStore` centralises all mutations, validation, and seeding; Codable DTOs handle `.flowplan`/JSON and Markdown export.
- **UI** — a `NavigationSplitView` shell (sidebar · graph/list · inspector) driven by an `@Observable` `PlanViewModel`.

## License

Licensed under the BSD Zero Clause License. See the [LICENSE](LICENSE) file for details.
