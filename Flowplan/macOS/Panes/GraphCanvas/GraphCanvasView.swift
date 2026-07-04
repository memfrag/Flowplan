//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The central graph canvas: positioned task cards over a dotted grid, with dependency edges drawn
/// behind them. Supports pan, zoom, card dragging, drag-to-create-dependency, and selection.
struct GraphCanvasView: View {

    @Bindable var viewModel: PlanViewModel

    @State private var editingTitle: String = ""
    @State private var baseZoom: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    // Drag-to-create-dependency state.
    @State private var linkSource: PlanTask?
    @State private var linkPoint: CGPoint?
    @State private var hoveredTaskID: UUID?
    @State private var hoveredDependencyID: UUID?

    private let cardSize = GraphMetrics.cardSize

    private var tasks: [PlanTask] { viewModel.tasks }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GridBackground()

                canvasContent
                    .coordinateSpace(name: GraphMetrics.canvasSpaceName)
                    .scaleEffect(viewModel.zoomScale)
                    .offset(viewModel.canvasOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onTapGesture { viewModel.clearSelection() }
            .overlay(alignment: .top) { toastOverlay }
            .overlay { if tasks.isEmpty { EmptyGraphState(viewModel: viewModel, viewportCenter: viewportCenter(in: geo.size)) } }
            .onAppear { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: geo.size) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.canvasOffset) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.zoomScale) { viewModel.lastViewportCenter = viewportCenter(in: geo.size) }
            .onChange(of: viewModel.editingTaskID) { _, newValue in
                if let id = newValue, let task = viewModel.task(id: id) {
                    editingTitle = task.title
                }
            }
            .navigationTitle(viewModel.plan?.title ?? "Flowplan")
        }
    }

    // MARK: - Content

    private var canvasContent: some View {
        ZStack {
            edgesLayer
            ForEach(tasks) { task in
                cardContainer(for: task)
            }
            // Connector delete hotspots sit on top of the cards so they are always hoverable.
            edgeSelectionDots
        }
        .frame(width: GraphMetrics.canvasSize.width, height: GraphMetrics.canvasSize.height)
    }

    private var edgesLayer: some View {
        DependencyEdgesView(
            edges: edgeGeometry(),
            pendingLink: pendingLink()
        )
        .frame(width: GraphMetrics.canvasSize.width, height: GraphMetrics.canvasSize.height)
    }

    @ViewBuilder
    private var edgeSelectionDots: some View {
        ForEach(dependencyMidpoints(), id: \.id) { item in
            let isSelected = viewModel.selectedDependencyID == item.id
            let isHovered = hoveredDependencyID == item.id
            let isActive = isSelected || isHovered
            ZStack {
                // Large transparent hit area for reliable hover/click.
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                // Visible marker: faint dot at rest, red ✕ when active.
                Circle()
                    .fill(isActive ? Color.red : Color.secondary.opacity(0.45))
                    .frame(width: isActive ? 20 : 9, height: isActive ? 20 : 9)
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

    private func cardContainer(for task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        let isEditing = viewModel.editingTaskID == task.id
        let number = (tasks.firstIndex(where: { $0.id == task.id }) ?? 0) + 1
        let dimmed = shouldDim(task)

        // NOTE: interaction modifiers (hover, gestures) must be applied to the card-sized view
        // BEFORE `.position`, because `.position` expands the view to fill the whole canvas —
        // attaching `.onHover` after it would make every card's hover region cover the canvas.
        return TaskCardView(
            task: task,
            number: number,
            state: state,
            isSelected: viewModel.selectedTaskID == task.id,
            isDimmed: dimmed,
            isEditing: isEditing,
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
        .position(task.position ?? CGPoint(x: 200, y: 200))
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
        }

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
                if value.translation.width != 0 || value.translation.height != 0 {
                    task.position = value.location
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.width) > 2 || abs(value.translation.height) > 2
                if moved { viewModel.moveTask(task, to: value.location) }
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
                viewModel.canvasOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in baseOffset = viewModel.canvasOffset }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                viewModel.zoomScale = clampedZoom(baseZoom * value)
            }
            .onEnded { _ in baseZoom = viewModel.zoomScale }
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

    private func anchorStart(_ task: PlanTask) -> CGPoint {
        let p = task.position ?? .zero
        return CGPoint(x: p.x + cardSize.width / 2, y: p.y)
    }

    private func anchorEnd(_ task: PlanTask) -> CGPoint {
        let p = task.position ?? .zero
        return CGPoint(x: p.x - cardSize.width / 2, y: p.y)
    }

    private func edgeGeometry() -> [DependencyEdgesView.Edge] {
        guard let plan = viewModel.plan else { return [] }
        let selected = viewModel.selectedTaskID
        return plan.dependencies.compactMap { dependency in
            guard let from = plan.task(id: dependency.prerequisiteTaskID),
                  let to = plan.task(id: dependency.dependentTaskID) else { return nil }
            let highlighted = viewModel.selectedDependencyID == dependency.id
                || selected == from.id || selected == to.id
            return DependencyEdgesView.Edge(
                id: dependency.id,
                start: anchorStart(from),
                end: anchorEnd(to),
                isHighlighted: highlighted
            )
        }
    }

    private func dependencyMidpoints() -> [(id: UUID, point: CGPoint)] {
        guard let plan = viewModel.plan else { return [] }
        return plan.dependencies.compactMap { dependency in
            guard let from = plan.task(id: dependency.prerequisiteTaskID),
                  let to = plan.task(id: dependency.dependentTaskID) else { return nil }
            let start = anchorStart(from)
            let end = anchorEnd(to)
            return (dependency.id, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        }
    }

    private func pendingLink() -> (start: CGPoint, end: CGPoint)? {
        guard let linkSource, let linkPoint else { return nil }
        return (anchorStart(linkSource), linkPoint)
    }

    private func taskHit(at point: CGPoint, excluding excludedID: UUID) -> PlanTask? {
        tasks.first { task in
            guard task.id != excludedID, let p = task.position else { return false }
            let rect = CGRect(
                x: p.x - cardSize.width / 2, y: p.y - cardSize.height / 2,
                width: cardSize.width, height: cardSize.height
            )
            return rect.contains(point)
        }
    }

    private func shouldDim(_ task: PlanTask) -> Bool {
        let filtering = !viewModel.activeFilters.isEmpty
            || !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        return filtering && !viewModel.matchesFilters(task)
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

/// A subtle dotted grid behind the graph.
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
