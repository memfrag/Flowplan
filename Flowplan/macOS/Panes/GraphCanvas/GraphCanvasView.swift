//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The central graph canvas: positioned task cards over a dotted grid, with dependency edges drawn
/// behind them. Supports pan (drag or trackpad scroll), zoom, card dragging,
/// drag-to-create-dependency, and selection.
struct GraphCanvasView: View {

    @Bindable var viewModel: PlanViewModel

    @State private var editingTitle: String = ""

    // Pan/zoom gesture baselines, seeded at the start of each gesture so they compose with
    // trackpad scroll/pinch that write the offset/scale directly.
    @State private var panStartOffset: CGSize?
    @State private var zoomStart: CGFloat?

    // Drag-to-create-dependency state.
    @State private var linkSource: PlanTask?
    @State private var linkPoint: CGPoint?
    @State private var hoveredTaskID: UUID?
    @State private var hoveredDependencyID: UUID?

    // Transient card-drag state. During a drag we keep the translation here and apply it visually,
    // committing to the model (SwiftData) only on drop — so we don't write `task.position` every frame.
    @State private var draggingTaskID: UUID?
    @State private var dragTranslation: CGSize = .zero

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
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onTapGesture { viewModel.clearSelection() }
            .contextMenu { canvasContextMenu }
            .overlay(alignment: .top) { toastOverlay }
            .overlay {
                if snapshot.orderedTasks.isEmpty {
                    EmptyGraphState(viewModel: viewModel, viewportCenter: viewportCenter(in: geo.size))
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
        let edges = edgeGeometry(snapshot: snapshot)
        let pending = pendingLink()

        return ZStack {
            DependencyEdgesView(
                edges: edges,
                pendingLink: pending,
                frameRect: edgesRect(edges: edges, pending: pending, size: size)
            )

            let linkTarget = currentLinkTarget()
            ForEach(snapshot.orderedTasks) { task in
                cardContainer(for: task, snapshot: snapshot, linkTarget: linkTarget)
            }

            // Connector delete hotspots sit on top of the cards so they are always hoverable.
            edgeSelectionDots(snapshot: snapshot)
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
        linkTarget: (id: UUID, isValid: Bool)?
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
            isSelected: viewModel.selectedTaskID == task.id,
            isDimmed: shouldDim(task, snapshot: snapshot),
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
                // Fires on press (translation == .zero) → select instantly; move only once dragged.
                if viewModel.selectedTaskID != task.id { viewModel.selectTask(task.id) }
                guard value.translation.width != 0 || value.translation.height != 0 else { return }
                draggingTaskID = task.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                if draggingTaskID == task.id {
                    let base = task.position ?? value.startLocation
                    viewModel.moveTask(task, to: CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    ))
                }
                draggingTaskID = nil
                dragTranslation = .zero
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

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let base = panStartOffset ?? viewModel.canvasOffset
                if panStartOffset == nil { panStartOffset = base }
                viewModel.canvasOffset = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in panStartOffset = nil }
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
        guard task.id == draggingTaskID else { return base }
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

    private func edgeGeometry(snapshot: PlanViewModel.RenderSnapshot) -> [DependencyEdgesView.Edge] {
        guard let plan = viewModel.plan else { return [] }
        let selected = viewModel.selectedTaskID
        return plan.dependencies.compactMap { dependency in
            guard let from = snapshot.taskByID[dependency.prerequisiteTaskID],
                  let to = snapshot.taskByID[dependency.dependentTaskID] else { return nil }
            let fromP = effectivePosition(of: from)
            let toP = effectivePosition(of: to)
            let highlighted = viewModel.selectedDependencyID == dependency.id
                || selected == from.id || selected == to.id
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

    private func shouldDim(_ task: PlanTask, snapshot: PlanViewModel.RenderSnapshot) -> Bool {
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
