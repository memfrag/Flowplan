# Flowplan App Specification

## 1. Product Summary

**Flowplan** is a native macOS planning app for managing tasks as a dependency graph rather than as a flat todo list.

The central idea is that each task can depend on other tasks. A task is only actionable when all of its dependencies are complete. Flowplan should make this visible by showing tasks as connected cards in a directed graph, with arrows representing dependency relationships.

The app should help users answer:

- What can I start now?
- What is blocked?
- What needs to be completed to unblock a task?
- What downstream work will be unlocked when I finish this task?
- How does an individual task fit into the larger plan?

The app is inspired by a manually created planning diagram where tasks are represented as labeled boxes connected by arrows, with some tasks branching into multiple follow-up tasks and others converging into shared downstream tasks.

## 2. Target Platform

- Platform: macOS
- Preferred implementation: Swift + SwiftUI
- Data persistence: local-first
- Minimum viable persistence options:
  - SwiftData, or
  - Core Data, or
  - local JSON document format for an initial prototype
- App style: modern native Mac productivity app

## 3. Core Concept

Flowplan is both:

1. A todo/planning app.
2. A visual dependency graph editor.

Unlike a normal todo app, task state is partly derived from dependency completion.

A task can be manually marked as:

- Not Started
- In Progress
- Done

But the visible task state shown to the user is one of:

- Backlog
- Ready to Start
- In Progress
- Done

The difference matters because **Backlog is derived**. A task is Backlog when it has unfinished dependencies and therefore cannot be started yet.

## 4. Task States

### 4.1 Visible States

Flowplan has four user-facing task states.

#### Backlog

A task is in **Backlog** when it is not done and at least one of its dependencies is not done.

This means the task is blocked and cannot be started yet.

Example:

- “Beta release” depends on “User testing” and “Polish interactions”.
- If either dependency is not Done, then “Beta release” is Backlog.

Backlog should generally be computed by the app, not manually assigned by the user.

#### Ready to Start

A task is **Ready to Start** when:

- It is not started, and
- all of its dependencies are Done.

Tasks with no dependencies are Ready to Start by default, unless they are already In Progress or Done.

#### In Progress

A task is **In Progress** when:

- The user has started it, and
- all dependencies are Done.

The app should not allow a task to be moved to In Progress if it has unfinished dependencies, unless an explicit override feature is added later.

#### Done

A task is **Done** when the user marks it complete.

Done tasks should visually unlock any dependent tasks whose remaining dependencies are also done.

### 4.2 Internal Progress Model

The stored state should be simple and manual:

```swift
enum TaskProgress: String, Codable, CaseIterable {
    case notStarted
    case inProgress
    case done
}
```

The displayed state should be derived:

```swift
enum TaskDisplayState: String, Codable, CaseIterable {
    case backlog
    case readyToStart
    case inProgress
    case done
}
```

### 4.3 Display State Algorithm

```swift
func displayState(for task: PlanTask, in graph: TaskGraph) -> TaskDisplayState {
    if task.progress == .done {
        return .done
    }

    let dependencies = graph.dependencies(of: task)
    let hasUnfinishedDependency = dependencies.contains { $0.progress != .done }

    if hasUnfinishedDependency {
        return .backlog
    }

    switch task.progress {
    case .notStarted:
        return .readyToStart
    case .inProgress:
        return .inProgress
    case .done:
        return .done
    }
}
```

### 4.4 State Transition Rules

Allowed transitions:

| Current Display State | User Action | Result |
|---|---|---|
| Ready to Start | Start | In Progress |
| Ready to Start | Mark Done | Done |
| In Progress | Mark Done | Done |
| In Progress | Mark Not Started | Ready to Start |
| Done | Reopen | Ready to Start or Backlog, depending on dependencies |
| Backlog | Start | Not allowed by default |
| Backlog | Mark Done | Should require confirmation or be disallowed in MVP |

When a dependency changes state, downstream task display states must update automatically.

## 5. Dependency Model

### 5.1 Direction

A dependency relationship means:

> Task B depends on Task A.

Visually:

```text
Task A ───▶ Task B
```

This means Task A must be Done before Task B can be Ready to Start.

### 5.2 Graph Type

The task graph should be a directed graph.

For the MVP, the graph should be a **DAG**: directed acyclic graph.

The app should prevent cycles such as:

```text
A depends on B
B depends on C
C depends on A
```

Cycles make readiness impossible to determine cleanly.

### 5.3 Dependency Validation

When the user creates or edits a dependency, validate:

- A task cannot depend on itself.
- A dependency cannot be duplicated.
- A dependency cannot create a cycle.
- Deleting a task should remove incoming and outgoing dependency references.

### 5.4 Useful Graph Queries

The model should support these queries:

```swift
func dependencies(of task: PlanTask) -> [PlanTask]
func dependents(of task: PlanTask) -> [PlanTask]
func blockers(of task: PlanTask) -> [PlanTask]
func unlockedByCompleting(_ task: PlanTask) -> [PlanTask]
func isReadyToStart(_ task: PlanTask) -> Bool
func wouldCreateCycle(from prerequisite: PlanTask, to dependent: PlanTask) -> Bool
```

Definitions:

- **Dependencies**: tasks that must be completed before this task.
- **Dependents**: tasks that depend on this task.
- **Blockers**: dependencies that are not Done.
- **Unlocked by completing**: dependent tasks that would become Ready to Start if this task were marked Done.

## 6. Data Model

### 6.1 Plan

```swift
struct Plan: Identifiable, Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var tasks: [PlanTask]
    var dependencies: [TaskDependency]
}
```

### 6.2 Task

```swift
struct PlanTask: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var progress: TaskProgress

    var category: String?
    var tags: [String]
    var priority: TaskPriority?
    var estimate: TaskEstimate?

    var position: CGPointCodable?

    var createdAt: Date
    var updatedAt: Date
}
```

### 6.3 Dependency

```swift
struct TaskDependency: Identifiable, Codable, Hashable {
    var id: UUID
    var prerequisiteTaskID: UUID
    var dependentTaskID: UUID
}
```

This means:

```text
prerequisiteTaskID ───▶ dependentTaskID
```

### 6.4 Priority

```swift
enum TaskPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high
}
```

### 6.5 Estimate

```swift
struct TaskEstimate: Codable, Hashable {
    var value: Double
    var unit: EstimateUnit
}

 enum EstimateUnit: String, Codable, CaseIterable {
    case minutes
    case hours
    case days
}
```

### 6.6 Codable CGPoint Helper

If using JSON persistence, `CGPoint` needs a Codable wrapper:

```swift
struct CGPointCodable: Codable, Hashable {
    var x: Double
    var y: Double
}
```

## 7. Main User Interface

### 7.1 Window Layout

The main app window should have four major areas:

1. macOS title bar / toolbar
2. Left sidebar
3. Central graph canvas
4. Right inspector panel

Suggested layout:

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Toolbar: Plan title, New Task, view controls, search                       │
├───────────────┬──────────────────────────────────────────────┬─────────────┤
│ Sidebar       │ Graph Canvas                                 │ Inspector   │
│               │                                              │             │
│ All Tasks     │     [Task] ───▶ [Task] ───▶ [Task]           │ Task title  │
│ Graph View    │        │                         │           │ Status      │
│ Board View    │        └──────▶ [Task] ──────────┘           │ Blocked by  │
│ Today         │                                              │ Next tasks  │
│ Blocked       │                                              │ Notes       │
│ Ready         │                                              │             │
└───────────────┴──────────────────────────────────────────────┴─────────────┘
```

### 7.2 Toolbar

The toolbar should include:

- Current plan title
- New Task button
- Graph View toggle
- List View toggle
- Board View toggle, optional for later
- Search field
- Zoom controls, either in toolbar or graph canvas

### 7.3 Sidebar

The sidebar should include:

#### Views

- All Tasks
- Graph View
- List View
- Board View, optional

#### Focus Filters

- Backlog
- Ready to Start
- In Progress
- Done
- Blocked

#### Plans

- List of plans/projects
- Add plan button

### 7.4 Central Graph Canvas

The graph canvas is the primary interface.

It should show:

- Task cards as rounded rectangles
- Arrows from prerequisite tasks to dependent tasks
- Color-coded task states
- Optional small metadata icons on each task card
- Selection highlight for the active task
- Pan and zoom support
- A subtle grid or dotted background

Interactions:

- Click a task to select it.
- Double-click a task to edit title.
- Drag a task to move it.
- Drag from a dependency handle to another task to create a dependency.
- Click an arrow to select or delete a dependency.
- Right-click a task for context menu actions.
- Use keyboard shortcuts for common actions.

### 7.5 Right Inspector

The inspector should show details for the selected task.

Fields:

- Title
- Display state
- Manual progress
- Notes
- Priority
- Estimate
- Tags
- Created date
- Updated date

Dependency sections:

- Blocked by
- Dependencies
- Next tasks / dependents
- Tasks unlocked by completing this task

For a Backlog task, the inspector should clearly explain why the task is not ready.

Example:

```text
Beta release
Status: Backlog

Blocked by:
- User testing — In Progress
- Polish interactions — Ready to Start

This task will become Ready to Start when all blockers are Done.
```

## 8. Visual Design

### 8.1 State Colors

Suggested state styling:

| State | Color | Meaning |
|---|---|---|
| Backlog | Gray | Blocked / not actionable |
| Ready to Start | Blue | Actionable now |
| In Progress | Orange / Amber | Currently active |
| Done | Green | Completed |

Colors should be accessible and should not rely on color alone. Include labels, icons, or borders.

### 8.2 Task Card Design

Each task card should contain:

- Status indicator dot or icon
- Task title
- Optional task number or short ID
- Optional category/tag label
- Small metadata row for notes, comments, estimate, or checklist count

Example card:

```text
┌──────────────────────────┐
│ ● 12  Beta release       │
│                          │
│ 💬 2              ☐ 0/2  │
└──────────────────────────┘
```

### 8.3 Backlog Card Design

Backlog cards should feel visibly blocked, for example:

- Muted gray fill
- Gray border
- Reduced emphasis
- Lock or blocked icon
- Tooltip or inspector explanation

### 8.4 Ready Card Design

Ready to Start cards should be prominent enough to invite action:

- Blue accent border
- Blue status dot
- Context action: Start

### 8.5 In Progress Card Design

In Progress cards should use:

- Orange or amber border
- Small progress indicator
- Context action: Mark Done

### 8.6 Done Card Design

Done cards should use:

- Green border or fill
- Checkmark icon
- Optional lower visual emphasis so active work stands out

## 9. Graph Layout

### 9.1 MVP Layout

For MVP, support manual layout:

- Each task stores a canvas position.
- Users can drag tasks freely.
- Arrows update as tasks move.

This is simpler and gives users direct control.

### 9.2 Automatic Layout

A later version should support automatic layout using topological ordering.

Possible algorithm:

1. Compute graph layers based on dependency depth.
2. Place tasks with no dependencies in the first column.
3. Place dependent tasks in later columns.
4. Minimize edge crossings where possible.
5. Allow the user to re-run auto layout.

Suggested layout direction:

```text
Left to right:
Prerequisites ───▶ Later work
```

### 9.3 Layout Rules

- Tasks with no dependencies should appear near the left.
- Tasks with many dependents should be visually central or prominent.
- Converging dependencies should be easy to follow.
- Arrowheads should clearly indicate direction.
- Selected task should highlight connected incoming and outgoing edges.

## 10. Interactions

### 10.1 Creating a Task

User flow:

1. User clicks New Task.
2. A new task is created at the center of the current canvas viewport.
3. Task starts with progress `.notStarted`.
4. If it has no dependencies, it displays as Ready to Start.
5. User can edit title immediately.

### 10.2 Creating a Dependency

User flow:

1. User hovers over a task.
2. Dependency handles appear on left and right edges.
3. User drags from the prerequisite task to the dependent task.
4. App validates the new dependency.
5. If valid, arrow is created.
6. Display states update.

Alternative command:

- Select dependent task.
- In inspector, add dependency by searching for prerequisite task.

### 10.3 Starting a Task

User can start a task only when it is Ready to Start.

If the user attempts to start a Backlog task, show a message:

```text
This task cannot be started yet.
Finish these blockers first:
- User testing
- Polish interactions
```

### 10.4 Completing a Task

When the user marks a task Done:

1. Set progress to `.done`.
2. Recompute display states for dependent tasks.
3. Highlight tasks that became Ready to Start.
4. Optionally show a small toast:

```text
2 tasks are now ready to start.
```

### 10.5 Reopening a Done Task

When reopening a Done task:

1. Set progress to `.notStarted` or `.inProgress`, depending on user choice.
2. Recompute all downstream states.
3. Some dependent tasks may become Backlog again.
4. If any Done downstream tasks now depend on an undone task, do not automatically change them, but visually flag the inconsistency.

MVP simplification:

- Allow Done downstream tasks to remain Done.
- Only not-done tasks become blocked.

### 10.6 Deleting a Task

When deleting a task:

- Remove the task.
- Remove all dependencies where it is prerequisite or dependent.
- Recompute states.

Ask for confirmation if the task has dependents.

### 10.7 Deleting a Dependency

When deleting a dependency:

- Remove only that edge.
- Recompute the dependent task’s state.
- The dependent task may become Ready to Start.

## 11. Search and Filtering

### 11.1 Search

Search should match:

- Task title
- Notes
- Tags
- Category

Search results should highlight matching tasks in the graph.

### 11.2 Filters

Filters:

- Backlog
- Ready to Start
- In Progress
- Done
- Has dependencies
- Has dependents
- No dependencies
- No dependents

Filtering should either:

- Dim non-matching tasks, or
- hide non-matching tasks.

Preferred MVP behavior: dim non-matching tasks so graph context remains visible.

## 12. List View

In addition to Graph View, include a simple list view.

Columns:

- Title
- Display state
- Manual progress
- Blockers
- Dependencies count
- Dependents count
- Priority
- Estimate

List view is useful for quickly editing task metadata.

## 13. Board View

Optional post-MVP feature.

Columns:

- Backlog
- Ready to Start
- In Progress
- Done

Important rule:

- Dragging a task into Backlog should not be allowed directly if Backlog is derived.
- Dragging a Backlog task into In Progress should be blocked unless dependencies are complete.
- Dragging a Ready task into In Progress is allowed.
- Dragging an In Progress task into Done is allowed.

## 14. Keyboard Shortcuts

Suggested shortcuts:

| Shortcut | Action |
|---|---|
| Cmd+N | New task |
| Cmd+F | Search |
| Cmd+1 | Graph view |
| Cmd+2 | List view |
| Cmd+3 | Board view |
| Cmd+Plus | Zoom in |
| Cmd+Minus | Zoom out |
| Cmd+0 | Reset zoom |
| Space | Start selected task, if ready |
| Cmd+Return | Mark selected task Done |
| Delete | Delete selected task or dependency |
| Cmd+D | Duplicate task |
| Cmd+E | Edit selected task title |
| Esc | Clear selection |

## 15. Empty States

### 15.1 No Plans

```text
Create your first Flowplan
Map your tasks, connect dependencies, and see what is ready to start.
```

Button:

```text
New Plan
```

### 15.2 Empty Graph

```text
No tasks yet
Add a task to start building your plan.
```

Button:

```text
New Task
```

### 15.3 No Ready Tasks

```text
Nothing is ready to start
Complete blockers to unlock more tasks.
```

## 16. Error States and Validation Messages

### 16.1 Cycle Error

```text
Cannot create dependency
This dependency would create a cycle.
```

### 16.2 Self Dependency Error

```text
A task cannot depend on itself.
```

### 16.3 Start Blocked Task Error

```text
This task is blocked
Finish all dependencies before starting it.
```

### 16.4 Duplicate Dependency Error

```text
That dependency already exists.
```

## 17. Persistence

### 17.1 Local Documents

For MVP, Flowplan can store plans as local files.

Suggested extension:

```text
.flowplan
```

Internally the file can be JSON.

### 17.2 JSON Shape

```json
{
  "id": "UUID",
  "title": "Product Launch Plan",
  "createdAt": "2026-01-01T12:00:00Z",
  "updatedAt": "2026-01-01T12:00:00Z",
  "tasks": [
    {
      "id": "UUID",
      "title": "Define vision",
      "notes": "",
      "progress": "done",
      "category": "Planning",
      "tags": [],
      "priority": "high",
      "estimate": { "value": 1, "unit": "days" },
      "position": { "x": 100, "y": 120 },
      "createdAt": "2026-01-01T12:00:00Z",
      "updatedAt": "2026-01-01T12:00:00Z"
    }
  ],
  "dependencies": [
    {
      "id": "UUID",
      "prerequisiteTaskID": "UUID",
      "dependentTaskID": "UUID"
    }
  ]
}
```

## 18. Import and Export

### 18.1 MVP Export

Support exporting:

- JSON
- Markdown summary
- PNG image of graph

### 18.2 Markdown Export

Example:

```markdown
# Product Launch Plan

## Ready to Start

- Create wireframes
- Add dependency rules

## In Progress

- Design onboarding
- Implement sync engine

## Backlog

- Beta release
  - Blocked by: User testing, Polish interactions

## Done

- Define vision
- Research competitors
- Finalize architecture
```

### 18.3 Future Import

Potential import formats:

- Markdown task list
- CSV
- OPML
- Mermaid graph syntax
- Graphviz DOT

## 19. Sample Seed Data

Use this sample plan for development and previews.

### Tasks

| ID | Title | Progress |
|---|---|---|
| T1 | Define vision | Done |
| T2 | Research competitors | Done |
| T3 | Set up project | Not Started |
| T4 | Finalize architecture | Done |
| T5 | Create wireframes | Not Started |
| T6 | Design onboarding | In Progress |
| T7 | Add dependency rules | Not Started |
| T8 | Build task graph UI | In Progress |
| T9 | Implement sync engine | In Progress |
| T10 | User testing | Not Started |
| T11 | Polish interactions | Not Started |
| T12 | Beta release | Not Started |
| T13 | Launch v1 | Not Started |

### Dependencies

```text
T1 -> T2
T1 -> T3
T2 -> T3
T2 -> T4
T3 -> T5
T3 -> T6
T3 -> T7
T5 -> T8
T6 -> T8
T6 -> T9
T7 -> T10
T4 -> T10
T8 -> T11
T9 -> T11
T10 -> T11
T10 -> T12
T11 -> T12
T12 -> T13
```

### Expected Derived States

Depending on the progress values above:

- Done:
  - Define vision
  - Research competitors
  - Finalize architecture
- Ready to Start:
  - Set up project, if its dependencies are done
- In Progress:
  - Design onboarding
  - Build task graph UI
  - Implement sync engine
- Backlog:
  - Any task with unfinished dependencies

The exact expected states should be computed by the app rather than hardcoded.

## 20. Architecture Suggestion

### 20.1 Suggested Modules

```text
FlowplanApp
├── Models
│   ├── Plan.swift
│   ├── PlanTask.swift
│   ├── TaskDependency.swift
│   ├── TaskProgress.swift
│   └── TaskDisplayState.swift
├── Graph
│   ├── TaskGraph.swift
│   ├── GraphValidation.swift
│   ├── GraphLayout.swift
│   └── GraphQueries.swift
├── Views
│   ├── MainWindowView.swift
│   ├── SidebarView.swift
│   ├── GraphCanvasView.swift
│   ├── TaskCardView.swift
│   ├── DependencyEdgeView.swift
│   ├── InspectorView.swift
│   └── ListView.swift
├── Persistence
│   ├── PlanDocument.swift
│   ├── PlanStore.swift
│   └── JSONPlanCoder.swift
└── Utilities
    ├── Geometry.swift
    └── KeyboardShortcuts.swift
```

### 20.2 View Model

```swift
@Observable
final class PlanViewModel {
    var plan: Plan
    var selectedTaskID: UUID?
    var selectedDependencyID: UUID?
    var searchText: String = ""
    var activeFilters: Set<TaskDisplayState> = []
    var zoomScale: CGFloat = 1.0
    var canvasOffset: CGSize = .zero

    func createTask(title: String, at position: CGPoint)
    func deleteTask(_ taskID: UUID)
    func updateTaskProgress(_ taskID: UUID, progress: TaskProgress)
    func createDependency(from prerequisiteID: UUID, to dependentID: UUID) throws
    func deleteDependency(_ dependencyID: UUID)
    func displayState(for taskID: UUID) -> TaskDisplayState
    func blockers(for taskID: UUID) -> [PlanTask]
    func dependents(for taskID: UUID) -> [PlanTask]
}
```

## 21. Graph Validation Pseudocode

```swift
func wouldCreateCycle(
    prerequisiteID: UUID,
    dependentID: UUID,
    dependencies: [TaskDependency]
) -> Bool {
    // Adding prerequisite -> dependent creates a cycle if prerequisite
    // is already reachable from dependent.
    return isReachable(
        from: dependentID,
        to: prerequisiteID,
        dependencies: dependencies
    )
}

func isReachable(
    from startID: UUID,
    to targetID: UUID,
    dependencies: [TaskDependency]
) -> Bool {
    var visited = Set<UUID>()
    var stack = [startID]

    while let current = stack.popLast() {
        if current == targetID { return true }
        if visited.contains(current) { continue }
        visited.insert(current)

        let outgoing = dependencies
            .filter { $0.prerequisiteTaskID == current }
            .map { $0.dependentTaskID }

        stack.append(contentsOf: outgoing)
    }

    return false
}
```

## 22. Graph Rendering Notes for SwiftUI

The graph canvas can be implemented with:

- `Canvas` for edges
- normal SwiftUI views for task cards
- `GeometryReader` for layout
- gestures for drag, pan, and zoom

Suggested approach:

1. Render dependency edges behind cards.
2. Render task cards above edges.
3. Use stored task positions to determine card placement.
4. For each edge, compute start and end points from card frames.
5. Draw orthogonal or curved connector paths.
6. Draw arrowheads at the dependent task end.

For MVP, simple straight or elbow connectors are acceptable.

## 23. MVP Scope

### Must Have

- Create, edit, and delete tasks
- Create and delete dependencies
- Prevent cycles
- Four visible states: Backlog, Ready to Start, In Progress, Done
- Automatic derivation of Backlog and Ready to Start
- Graph view with draggable cards and arrows
- Inspector showing blockers and next tasks
- Local persistence
- Search
- Basic list view

### Should Have

- Zoom and pan
- Status legend
- Highlight selected task’s incoming and outgoing edges
- Toast when completing a task unlocks new tasks
- Export graph as PNG
- Export plan as Markdown

### Could Have Later

- Board view
- Auto layout
- iCloud sync
- Collaboration
- Due dates
- Recurring tasks
- Command palette
- Mermaid / Graphviz import-export
- Critical path analysis
- Timeline view
- Calendar integration
- GitHub/Jira/Linear import

## 24. Non-Goals for MVP

Do not build these in the first version:

- Team collaboration
- Real-time sync
- Comments or mentions
- Complex scheduling
- Gantt chart
- Full project management suite
- Time tracking
- Notifications
- Mobile companion app

## 25. Acceptance Criteria

### 25.1 Backlog Derivation

Given:

- Task B depends on Task A.
- Task A is not Done.
- Task B is Not Started.

Then:

- Task B is displayed as Backlog.
- Task B cannot be started.
- Inspector for Task B lists Task A as a blocker.

### 25.2 Ready Derivation

Given:

- Task B depends on Task A.
- Task A is Done.
- Task B is Not Started.

Then:

- Task B is displayed as Ready to Start.
- Task B can be started.

### 25.3 Unlocking

Given:

- Task C depends on Task A and Task B.
- Task A is Done.
- Task B is In Progress.
- Task C is Backlog.

When:

- Task B is marked Done.

Then:

- Task C becomes Ready to Start.
- The app should visually indicate that Task C was unlocked.

### 25.4 Cycle Prevention

Given:

```text
A -> B -> C
```

When the user tries to create:

```text
C -> A
```

Then:

- The app rejects the dependency.
- The app displays a cycle error.

### 25.5 Graph Editing

Given:

- A task card is visible on the graph.

When:

- The user drags it.

Then:

- The card moves.
- Connected arrows update.
- The new position is persisted.

## 26. Suggested Tagline

```text
Flowplan — See what’s blocked, ready, and next.
```

Alternative:

```text
Flowplan — Plan by dependencies, not just deadlines.
```
