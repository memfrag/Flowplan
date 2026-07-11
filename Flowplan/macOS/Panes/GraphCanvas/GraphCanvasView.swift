//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

/// The central graph canvas: positioned task cards over a dotted grid, with dependency edges drawn
/// behind them. Supports pan (drag or trackpad scroll), zoom, card dragging,
/// drag-to-create-dependency, marquee multi-selection, and selection.
struct GraphCanvasView: View {

    @Bindable var viewModel: PlanViewModel

    @State private var editingTitle: String = ""

    // Zoom gesture baseline, seeded at the start of the gesture so it composes with trackpad pinch
    // that writes the scale directly.
    @State private var zoomStart: CGFloat?

    // Drag-to-create-dependency state.
    @State private var linkSource: PlanTask?
    @State private var linkPoint: CGPoint?
    @State private var hoveredTaskID: UUID?
    @State private var hoveredDependencyID: UUID?

    // Transient card-drag state. During a drag we keep the translation here and apply it visually,
    // committing to the model (SwiftData) only on drop — so we don't write `task.position` every frame.
    // A drag started on a card that is part of a multi-selection moves the whole selection at once,
    // so this is a set rather than a single id.
    @State private var draggingTaskIDs: Set<UUID> = []
    @State private var dragTranslation: CGSize = .zero

    // Empty-canvas drag is handled by two simultaneous gestures (pan + marquee). Each independently
    // decides — from the shift key on its own first event — whether it owns the current drag, so they
    // never depend on each other's state. `nil` = not yet decided this drag.
    @State private var panActive: Bool?
    @State private var panBaseOffset: CGSize = .zero

    // Marquee (shift-drag) selection state, in canvas content coordinates.
    @State private var marqueeActive: Bool?
    @State private var marqueeRect: CGRect?
    @State private var marqueeBaseSelection: Set<UUID> = []

    // Latest pointer location in canvas content coordinates, used to place a right-click "New Task".
    @State private var hoverLocation: CGPoint?

    private let cardSize = GraphMetrics.cardSize

    var body: some View {
        GeometryReader { geo in
            let snapshot = viewModel.renderSnapshot()
            let size = contentSize(for: snapshot, viewport: geo.size)

            ZStack {
                GridBackground()

                canvasContent(snapshot: snapshot, size: size)
                    .coordinateSpace(name: GraphMetrics.canvasSpaceName)
                    .scaleEffect(viewModel.zoomScale)
                    .offset(viewModel.canvasOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(scrollCatcher)
            .contentShape(Rectangle())
            .gesture(zoomGesture)
            .onTapGesture { viewModel.clearSelection() }
            .contextMenu { canvasContextMenu }
            .overlay {
                if snapshot.orderedTasks.isEmpty {
                    EmptyGraphState(viewModel: viewModel, viewportCenter: viewportCenter(in: geo.size))
                } else if isShowingEmptyReadyFocus {
                    noReadyTasksState
                }
            }
            .onAppear { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: geo.size) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.canvasOffset) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.zoomScale) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.editingTaskID) { _, newValue in
                if let id = newValue, let task = viewModel.task(id: id) {
                    editingTitle = task.title
                }
            }
        }
        // Attached to the GeometryReader (always exactly the visible pane) rather than the inner
        // ZStack, whose oversized canvas content distorts overlay alignment.
        .overlay(alignment: .top) { toastOverlay }
        .overlay(alignment: .top) { criticalPathBanner }
        .overlay(alignment: .bottomLeading) { statusLegend }
    }

    // MARK: - Critical path banner

    @ViewBuilder
    private var criticalPathBanner: some View {
        if viewModel.showCriticalPath {
            let result = viewModel.criticalPathResult()
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(.orange)
                if result.isEmpty {
                    Text("No critical path — add dependencies and estimates.")
                } else {
                    Text("Critical path: \(result.orderedPath.count) tasks · ~\(PlanViewModel.formatDurationHours(result.totalDuration))")
                        .fontWeight(.medium)
                }
                Button {
                    viewModel.showCriticalPath = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary))
            .padding(.top, 12)
        }
    }

    // MARK: - Trackpad scrolling

    private var scrollCatcher: some View {
        TrackpadScrollCatcher(
            onScroll: { delta in
                viewModel.canvasOffset = CGSize(
                    width: viewModel.canvasOffset.width + delta.width,
                    height: viewModel.canvasOffset.height + delta.height
                )
            }
        )
    }

    // MARK: - Content

    private func canvasContent(snapshot: PlanViewModel.RenderSnapshot, size: CGSize) -> some View {
        let criticalIDs = viewModel.showCriticalPath ? viewModel.criticalPathResult().criticalTaskIDs : nil
        let edges = edgeGeometry(snapshot: snapshot, criticalIDs: criticalIDs)
        let pending = pendingLink()

        return ZStack {
            // A transparent hit layer behind everything: empty-canvas drags land here and either pan
            // (plain drag, in stable screen space) or draw a marquee selection (shift-drag, in canvas
            // content space). Split into two gestures so pan never reads the moving content space.
            // The hit shape extends far past the content plane (the plane is only as big as the
            // tasks' bounding box + margin), so panning/marqueeing still works when the viewport
            // has been panned beyond the content. The *frame* must stay plane-sized — enlarging it
            // would inflate the ZStack and shift every card's coordinates.
            Color.white.opacity(0.001)
                .contentShape(Rectangle().inset(by: -25_000))
                .onTapGesture { viewModel.clearSelection() }
                .gesture(canvasPanGesture)
                .simultaneousGesture(canvasMarqueeGesture(snapshot: snapshot))

            DependencyEdgesView(
                edges: edges,
                pendingLink: pending,
                frameRect: edgesRect(edges: edges, pending: pending, size: size)
            )

            let linkTarget = currentLinkTarget()
            ForEach(snapshot.orderedTasks) { task in
                cardContainer(for: task, snapshot: snapshot, linkTarget: linkTarget, criticalIDs: criticalIDs)
            }

            // Connector delete hotspots sit on top of the cards so they are always hoverable.
            edgeSelectionDots(snapshot: snapshot)

            marqueeOverlay
        }
        .frame(width: size.width, height: size.height)
        // Track the pointer in content coordinates so a right-click "New Task" lands where clicked.
        .onContinuousHover(coordinateSpace: .named(GraphMetrics.canvasSpaceName)) { phase in
            if case .active(let location) = phase { hoverLocation = location }
        }
    }

    @ViewBuilder
    private var canvasContextMenu: some View {
        Button {
            _ = viewModel.createTask(at: hoverLocation ?? viewModel.lastViewportCenter)
        } label: {
            Label("New Task Here", systemImage: "plus")
        }
        .disabled(viewModel.plan == nil)

        Divider()

        Button {
            viewModel.autoLayout()
        } label: {
            Label("Auto Layout", systemImage: "wand.and.stars")
        }
        Button {
            viewModel.zoomScale = 1
        } label: {
            Label("Reset Zoom", systemImage: "1.magnifyingglass")
        }
    }

    /// The region the edge Canvas must cover — always at least the content frame, expanded to
    /// include any connector endpoints (or the pending link) that fall above/left of the origin,
    /// so nothing is clipped.
    private func edgesRect(
        edges: [DependencyEdgesView.Edge],
        pending: (start: CGPoint, end: CGPoint)?,
        size: CGSize
    ) -> CGRect {
        var minX: CGFloat = 0, minY: CGFloat = 0
        var maxX = size.width, maxY = size.height
        func include(_ p: CGPoint) {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        for edge in edges { include(edge.start); include(edge.end) }
        if let pending { include(pending.start); include(pending.end) }
        let margin: CGFloat = 40
        return CGRect(x: minX - margin, y: minY - margin,
                      width: (maxX - minX) + margin * 2, height: (maxY - minY) + margin * 2)
    }

    @ViewBuilder
    private func edgeSelectionDots(snapshot: PlanViewModel.RenderSnapshot) -> some View {
        ForEach(dependencyMidpoints(snapshot: snapshot), id: \.id) { item in
            let isSelected = viewModel.selectedDependencyID == item.id
            let isHovered = hoveredDependencyID == item.id
            let isActive = isSelected || isHovered
            // Only reveal (and enable) the delete dot when the pointer is over this connector.
            let isNear = isActive || (hoverLocation.map { item.bounds.contains($0) } ?? false)
            ZStack {
                // Large transparent hit area for reliable hover/click.
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                // Visible marker: faint dot when near, red ✕ when active.
                Circle()
                    .fill(isActive ? Color.red : Color.secondary.opacity(0.5))
                    .frame(width: isActive ? 20 : 10, height: isActive ? 20 : 10)
                    .overlay(Circle().strokeBorder(.background, lineWidth: isActive ? 1.5 : 0))
                if isActive {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .help("Remove dependency")
            .opacity(isNear ? 1 : 0)
            .allowsHitTesting(isNear)
            .onHover { hovering in
                if hovering { hoveredDependencyID = item.id }
                else if hoveredDependencyID == item.id { hoveredDependencyID = nil }
            }
            .onTapGesture {
                viewModel.selectDependency(item.id)
                viewModel.deleteSelectedTaskOrDependency()
            }
            .position(item.point)
        }
    }

    private func cardContainer(
        for task: PlanTask,
        snapshot: PlanViewModel.RenderSnapshot,
        linkTarget: (id: UUID, isValid: Bool)?,
        criticalIDs: Set<UUID>?
    ) -> some View {
        let state = snapshot.displayState(of: task)
        let isEditing = viewModel.editingTaskID == task.id
        let highlight: TaskCardView.LinkTargetHighlight = {
            guard let linkTarget, linkTarget.id == task.id else { return .none }
            return linkTarget.isValid ? .valid : .invalid
        }()

        // NOTE: interaction modifiers (hover, gestures) must be applied to the card-sized view
        // BEFORE `.position`, because `.position` expands the view to fill the whole canvas —
        // attaching `.onHover` after it would make every card's hover region cover the canvas.
        return TaskCardView(
            task: task,
            number: snapshot.number(of: task),
            state: state,
            isSelected: viewModel.isSelected(task.id),
            isDimmed: shouldDim(task, snapshot: snapshot, criticalIDs: criticalIDs),
            isEditing: isEditing,
            linkTarget: highlight,
            editingTitle: $editingTitle,
            onCommitEdit: { commitEdit(task) }
        )
        .overlay(alignment: .trailing) { dependencyHandle(for: task) }
        .contentShape(Rectangle())
        // Select immediately on press (via the drag gesture) so highlighting is instant.
        .gesture(cardDragGesture(for: task))
        .contextMenu { cardContextMenu(for: task, state: state) }
        .onHover { hovering in
            if hovering { hoveredTaskID = task.id }
            else if hoveredTaskID == task.id { hoveredTaskID = nil }
        }
        .position(effectivePosition(of: task))
    }

    /// A small handle on the card's right edge; dragging from it to another card creates a dependency.
    /// Revealed on hover (and while dragging) so the gesture is discoverable.
    private func dependencyHandle(for task: PlanTask) -> some View {
        let isVisible = hoveredTaskID == task.id || linkSource?.id == task.id
        return Circle()
            .fill(Color.accentColor)
            .frame(width: 18, height: 18)
            .overlay(Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            .offset(x: -2)
            .opacity(isVisible ? 1 : 0.001)
            .help("Drag to another task to create a dependency")
            .gesture(linkDragGesture(from: task))
    }

    // MARK: - Context menu

    @ViewBuilder
    private func cardContextMenu(for task: PlanTask, state: TaskDisplayState) -> some View {
        // When this card is part of a multi-selection, act on the whole selection instead.
        if viewModel.selectedTaskIDs.count > 1, viewModel.isSelected(task.id) {
            multiSelectionContextMenu()
        } else {
            singleCardContextMenu(for: task, state: state)
        }
    }

    @ViewBuilder
    private func multiSelectionContextMenu() -> some View {
        let count = viewModel.selectedTaskIDs.count
        Section("\(count) tasks selected") {
            Button("Mark In Progress") { viewModel.setProgressForSelected(.inProgress) }
            Button("Mark Done") { viewModel.setProgressForSelected(.done) }
            Button("Mark Not Started") { viewModel.setProgressForSelected(.notStarted) }
            Button("Close") { viewModel.setProgressForSelected(.closed) }
        }

        Divider()

        Button("Auto Layout") { viewModel.autoLayout() }

        Divider()

        Button("Delete \(count) Tasks", role: .destructive) {
            viewModel.deleteSelectedTaskOrDependency()
        }
    }

    @ViewBuilder
    private func singleCardContextMenu(for task: PlanTask, state: TaskDisplayState) -> some View {
        Button("Rename") {
            viewModel.selectTask(task.id)
            beginEdit(task)
        }

        Divider()

        switch state {
        case .readyToStart:
            Button("Start") { viewModel.start(task) }
            Button("Mark Done") { viewModel.markDone(task) }
        case .inProgress:
            Button("Mark Done") { viewModel.markDone(task) }
            Button("Mark Not Started") { viewModel.reopen(task) }
        case .done:
            Button("Reopen") { viewModel.reopen(task) }
        case .backlog:
            Button("Start") { viewModel.start(task) }
        case .closed:
            Button("Reopen") { viewModel.reopen(task) }
        }

        Button("Close") { viewModel.close(task) }

        Divider()

        Button("Duplicate") {
            viewModel.selectTask(task.id)
            viewModel.duplicateSelectedTask()
        }
        Button("Delete", role: .destructive) {
            viewModel.selectTask(task.id)
            viewModel.deleteSelectedTaskOrDependency()
        }
    }

    // MARK: - Gestures

    private func cardDragGesture(for task: PlanTask) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(GraphMetrics.canvasSpaceName))
            .onChanged { value in
                let moving = value.translation.width != 0 || value.translation.height != 0
                if !moving {
                    // Press with no movement yet: update the selection.
                    if NSEvent.modifierFlags.contains(.shift) {
                        viewModel.toggleSelection(task.id)
                    } else if !viewModel.isSelected(task.id) {
                        // Plain click on an unselected card → single-select. A plain press on a card
                        // that's already part of a multi-selection keeps the selection, so it can be
                        // dragged as a group.
                        viewModel.selectTask(task.id)
                    }
                    return
                }
                // Movement: begin (or continue) a drag. Decide once which cards move — the whole
                // selection if this card is part of a multi-selection, otherwise just this card.
                if draggingTaskIDs.isEmpty {
                    if viewModel.isSelected(task.id), viewModel.selectedTaskIDs.count > 1 {
                        draggingTaskIDs = viewModel.selectedTaskIDs
                    } else {
                        if !viewModel.isSelected(task.id) { viewModel.selectTask(task.id) }
                        draggingTaskIDs = [task.id]
                    }
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                for id in draggingTaskIDs {
                    guard let moved = viewModel.task(id: id) else { continue }
                    let base = moved.position ?? value.startLocation
                    viewModel.moveTask(moved, to: CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    ))
                }
                draggingTaskIDs = []
                dragTranslation = .zero
            }
    }

    /// Empty-canvas pan. Runs in the stable global (screen) space — never the canvas content space,
    /// which moves as we change the offset and would feed back into the gesture as jitter.
    private var canvasPanGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if panActive == nil {
                    // This drag is a pan unless shift is held (then the marquee gesture owns it).
                    panActive = !NSEvent.modifierFlags.contains(.shift)
                    // The first event already carries the `minimumDistance` the pointer moved to start
                    // the drag. Fold it into the baseline so the canvas doesn't jump by that threshold.
                    panBaseOffset = CGSize(
                        width: viewModel.canvasOffset.width - value.translation.width,
                        height: viewModel.canvasOffset.height - value.translation.height
                    )
                }
                guard panActive == true else { return }
                viewModel.canvasOffset = CGSize(
                    width: panBaseOffset.width + value.translation.width,
                    height: panBaseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in panActive = nil }
    }

    /// Shift-drag marquee selection. Runs in canvas content coordinates so the marquee rectangle and
    /// the card rects share one frame (no manual zoom/offset math); the offset doesn't change during
    /// a marquee, so this space stays stable.
    private func canvasMarqueeGesture(snapshot: PlanViewModel.RenderSnapshot) -> some Gesture {
        DragGesture(coordinateSpace: .named(GraphMetrics.canvasSpaceName))
            .onChanged { value in
                if marqueeActive == nil {
                    // This drag is a marquee only when shift is held (otherwise the pan gesture owns it).
                    marqueeActive = NSEvent.modifierFlags.contains(.shift)
                    if marqueeActive == true { marqueeBaseSelection = viewModel.selectedTaskIDs }
                }
                guard marqueeActive == true else { return }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marqueeRect = rect
                viewModel.setSelectedTasks(marqueeBaseSelection.union(tasksIntersecting(rect, snapshot: snapshot)))
            }
            .onEnded { _ in
                if marqueeActive == true {
                    marqueeRect = nil
                    marqueeBaseSelection = []
                }
                marqueeActive = nil
            }
    }

    /// The tasks whose card rectangle intersects a content-space rectangle (used by the marquee).
    private func tasksIntersecting(_ rect: CGRect, snapshot: PlanViewModel.RenderSnapshot) -> Set<UUID> {
        var result: Set<UUID> = []
        for task in snapshot.orderedTasks {
            let p = effectivePosition(of: task)
            let cardRect = CGRect(
                x: p.x - cardSize.width / 2, y: p.y - cardSize.height / 2,
                width: cardSize.width, height: cardSize.height
            )
            if cardRect.intersects(rect) { result.insert(task.id) }
        }
        return result
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let rect = marqueeRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    private func linkDragGesture(from task: PlanTask) -> some Gesture {
        DragGesture(coordinateSpace: .named(GraphMetrics.canvasSpaceName))
            .onChanged { value in
                linkSource = task
                linkPoint = value.location
            }
            .onEnded { value in
                defer { linkSource = nil; linkPoint = nil }
                guard let target = taskHit(at: value.location, excluding: task.id) else { return }
                viewModel.createDependency(from: task, to: target)
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let base = zoomStart ?? viewModel.zoomScale
                if zoomStart == nil { zoomStart = base }
                viewModel.zoomScale = clampedZoom(base * value)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, GraphMetrics.minZoom), GraphMetrics.maxZoom)
    }

    // MARK: - Editing

    private func beginEdit(_ task: PlanTask) {
        editingTitle = task.title
        viewModel.editingTaskID = task.id
        viewModel.selectTask(task.id)
    }

    private func commitEdit(_ task: PlanTask) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            task.title = trimmed
            task.touch()
            viewModel.store?.save()
        }
        viewModel.editingTaskID = nil
    }

    // MARK: - Geometry helpers

    /// A task's canvas position, including any in-progress drag translation.
    private func effectivePosition(of task: PlanTask) -> CGPoint {
        let base = task.position ?? CGPoint(x: 200, y: 200)
        guard draggingTaskIDs.contains(task.id) else { return base }
        return CGPoint(x: base.x + dragTranslation.width, y: base.y + dragTranslation.height)
    }

    /// The content plane is sized to the tasks' bounding box (+ margin), never larger than needed,
    /// so the edge `Canvas` backing store stays small instead of a fixed 4000×3000.
    private func contentSize(for snapshot: PlanViewModel.RenderSnapshot, viewport: CGSize) -> CGSize {
        let margin: CGFloat = 400
        var maxX = viewport.width
        var maxY = viewport.height
        for task in snapshot.orderedTasks {
            let p = effectivePosition(of: task)
            maxX = max(maxX, p.x + cardSize.width / 2)
            maxY = max(maxY, p.y + cardSize.height / 2)
        }
        return CGSize(width: maxX + margin, height: maxY + margin)
    }

    private func edgeGeometry(snapshot: PlanViewModel.RenderSnapshot, criticalIDs: Set<UUID>?) -> [DependencyEdgesView.Edge] {
        guard let plan = viewModel.plan else { return [] }
        return plan.dependencies.compactMap { dependency in
            guard let from = snapshot.taskByID[dependency.prerequisiteTaskID],
                  let to = snapshot.taskByID[dependency.dependentTaskID] else { return nil }
            let fromP = effectivePosition(of: from)
            let toP = effectivePosition(of: to)
            // On the critical path, only its edges are highlighted; otherwise selection drives it.
            let highlighted: Bool
            if let criticalIDs {
                highlighted = criticalIDs.contains(from.id) && criticalIDs.contains(to.id)
            } else {
                highlighted = viewModel.selectedDependencyID == dependency.id
                    || viewModel.isSelected(from.id) || viewModel.isSelected(to.id)
            }
            return DependencyEdgesView.Edge(
                id: dependency.id,
                start: CGPoint(x: fromP.x + cardSize.width / 2, y: fromP.y),
                end: CGPoint(x: toP.x - cardSize.width / 2, y: toP.y),
                isHighlighted: highlighted
            )
        }
    }

    private func dependencyMidpoints(snapshot: PlanViewModel.RenderSnapshot) -> [(id: UUID, point: CGPoint, bounds: CGRect)] {
        guard let plan = viewModel.plan else { return [] }
        return plan.dependencies.compactMap { dependency in
            guard let from = snapshot.taskByID[dependency.prerequisiteTaskID],
                  let to = snapshot.taskByID[dependency.dependentTaskID] else { return nil }
            let fromP = effectivePosition(of: from)
            let toP = effectivePosition(of: to)
            let start = CGPoint(x: fromP.x + cardSize.width / 2, y: fromP.y)
            let end = CGPoint(x: toP.x - cardSize.width / 2, y: toP.y)
            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            // Bounding box of the connector (the curve stays within its endpoints' span), padded
            // for hover tolerance. The delete dot only appears while the pointer is inside this.
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ).insetBy(dx: -14, dy: -14)
            return (dependency.id, midpoint, rect)
        }
    }

    private func pendingLink() -> (start: CGPoint, end: CGPoint)? {
        guard let linkSource, let linkPoint else { return nil }
        let p = effectivePosition(of: linkSource)
        return (CGPoint(x: p.x + cardSize.width / 2, y: p.y), linkPoint)
    }

    /// The task the in-progress dependency drag is currently pointing at, and whether dropping there
    /// would be a valid dependency (no self/duplicate/cycle). `nil` when no link drag is active or the
    /// pointer isn't over a card. Computed once per frame and shared across all cards.
    private func currentLinkTarget() -> (id: UUID, isValid: Bool)? {
        guard let linkSource, let linkPoint,
              let target = taskHit(at: linkPoint, excluding: linkSource.id) else { return nil }
        let isValid = viewModel.plan.map {
            (try? $0.graph.validateNewDependency(from: linkSource.id, to: target.id)) != nil
        } ?? false
        return (target.id, isValid)
    }

    private func taskHit(at point: CGPoint, excluding excludedID: UUID) -> PlanTask? {
        viewModel.tasks.first { task in
            guard task.id != excludedID else { return false }
            let p = effectivePosition(of: task)
            let rect = CGRect(
                x: p.x - cardSize.width / 2, y: p.y - cardSize.height / 2,
                width: cardSize.width, height: cardSize.height
            )
            return rect.contains(point)
        }
    }

    private func shouldDim(_ task: PlanTask, snapshot: PlanViewModel.RenderSnapshot, criticalIDs: Set<UUID>?) -> Bool {
        // Critical-path mode dims everything off the path.
        if let criticalIDs {
            return !criticalIDs.contains(task.id)
        }
        let filtering = !viewModel.activeFilters.isEmpty
            || !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        guard filtering else { return false }
        return !viewModel.matches(task, displayState: snapshot.displayState(of: task))
    }

    private func viewportCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: (size.width / 2 - viewModel.canvasOffset.width) / viewModel.zoomScale,
            y: (size.height / 2 - viewModel.canvasOffset.height) / viewModel.zoomScale
        )
    }

    // MARK: - Status legend

    /// A compact legend of the states drawn on the graph (spec §23 should-have). Closed tasks are
    /// hidden from the canvas, so they are not listed.
    private var statusLegend: some View {
        HStack(spacing: 12) {
            ForEach([TaskDisplayState.backlog, .readyToStart, .inProgress, .done]) { state in
                HStack(spacing: 4) {
                    Image(systemName: state.systemImage)
                        .foregroundStyle(state.color)
                        .font(.caption2)
                    Text(state.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .padding(12)
        .allowsHitTesting(false)
    }

    // MARK: - No Ready empty state (spec §15.3)

    /// Whether the Ready focus filter is active but nothing is ready to start.
    private var isShowingEmptyReadyFocus: Bool {
        viewModel.activeFilters == [.readyToStart] && viewModel.count(of: .readyToStart) == 0
    }

    private var noReadyTasksState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nothing is ready to start")
                .font(.title3.weight(.semibold))
            Text("Complete blockers to unlock more tasks.")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .allowsHitTesting(false)
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = viewModel.toastMessage {
            Label(message, systemImage: "sparkles")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// A subtle dotted grid behind the graph. Rendered into a cached layer so its dot-drawing loop
/// isn't re-run on every canvas update.
private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let dot = Color.secondary.opacity(0.12)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                    context.fill(Path(ellipseIn: rect), with: .color(dot))
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

/// Empty-state shown when the active plan has no tasks (spec §15.2).
private struct EmptyGraphState: View {
    let viewModel: PlanViewModel
    let viewportCenter: CGPoint

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No tasks yet")
                .font(.title3.weight(.semibold))
            Text("Add a task to start building your plan.")
                .foregroundStyle(.secondary)
            Button {
                _ = viewModel.createTask(at: viewportCenter)
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
    }
}
