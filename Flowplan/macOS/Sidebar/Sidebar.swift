//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

struct Sidebar: View {

    @Bindable var viewModel: PlanViewModel

    @Environment(PlanStore.self) private var store
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @State private var selection: SidebarSelection? = .mode(.graph)
    @State private var isInspectorPresented: Bool = true

    var body: some View {
        NavigationSplitView {
            sidebarList
                .listStyle(.sidebar)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
        } detail: {
            detail
                .inspector(isPresented: $isInspectorPresented) {
                    TaskInspectorPanel(viewModel: viewModel)
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search tasks…")
        .onChange(of: selection) { _, newValue in apply(newValue) }
        .alert(
            viewModel.activeAlert?.title ?? "",
            isPresented: alertPresented,
            presenting: viewModel.activeAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Sidebar list

    private var sidebarList: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: SidebarSelection.overview) {
                    Label("Overview", systemImage: "square.grid.2x2")
                }
            }

            Section("Views") {
                NavigationLink(value: SidebarSelection.mode(.graph)) {
                    Label("Graph View", systemImage: PlanViewMode.graph.systemImage)
                }
                NavigationLink(value: SidebarSelection.mode(.list)) {
                    Label("List View", systemImage: PlanViewMode.list.systemImage)
                }
                Label("Board View", systemImage: "rectangle.split.3x1")
                    .foregroundStyle(.tertiary)
                    .help("Coming later")
            }

            Section("Focus") {
                focusRow(.backlog, title: "Backlog")
                focusRow(.readyToStart, title: "Ready")
                focusRow(.inProgress, title: "In Progress")
                focusRow(.done, title: "Done")
            }

            Section("Projects") {
                ForEach(plans) { plan in
                    projectRow(plan)
                }
                Button {
                    let plan = store.createPlan()
                    viewModel.plan = plan
                } label: {
                    Label("Add Plan", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func focusRow(_ state: TaskDisplayState, title: String) -> some View {
        NavigationLink(value: SidebarSelection.focus(state)) {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(viewModel.count(of: state))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: state.systemImage).foregroundStyle(state.color)
            }
        }
    }

    private func projectRow(_ plan: Plan) -> some View {
        let isActive = viewModel.plan?.id == plan.id
        return Button {
            viewModel.plan = plan
            viewModel.clearSelection()
        } label: {
            Label(plan.title, systemImage: "folder")
                .fontWeight(isActive ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .contextMenu {
            Button("Delete Plan", role: .destructive) {
                store.deletePlan(plan)
                if viewModel.plan?.id == plan.id { viewModel.plan = plans.first { $0.id != plan.id } }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if viewModel.plan == nil {
            EmptyPlansState { _ = store.createPlan() }
        } else {
            switch viewModel.viewMode {
            case .graph: GraphCanvasView(viewModel: viewModel)
            case .list: PlanListView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.viewMode = .graph
                _ = viewModel.createTask(at: CGPoint(x: 400, y: 300))
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .disabled(viewModel.plan == nil)

            Button {
                viewModel.autoLayout()
            } label: {
                Label("Auto Layout", systemImage: "wand.and.stars")
            }
            .disabled(viewModel.plan == nil || viewModel.viewMode != .graph)

            zoomControls

            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.trailing")
            }
        }
    }

    @ViewBuilder
    private var zoomControls: some View {
        if viewModel.viewMode == .graph {
            Button { setZoom(viewModel.zoomScale - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(viewModel.zoomScale * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42)
            Button { setZoom(viewModel.zoomScale + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
        }
    }

    private func setZoom(_ value: CGFloat) {
        viewModel.zoomScale = min(max(value, GraphMetrics.minZoom), GraphMetrics.maxZoom)
    }

    // MARK: - Selection handling

    private func apply(_ selection: SidebarSelection?) {
        switch selection {
        case .overview:
            viewModel.activeFilters = []
            viewModel.viewMode = .graph
        case .mode(let mode):
            viewModel.viewMode = mode
            viewModel.activeFilters = []
        case .focus(let state):
            viewModel.activeFilters = [state]
            viewModel.viewMode = .graph
        case nil:
            break
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeAlert != nil },
            set: { if !$0 { viewModel.activeAlert = nil } }
        )
    }
}

/// Empty-state shown when there are no plans (spec §15.1).
private struct EmptyPlansState: View {
    var createPlan: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Create your first Flowplan")
                .font(.title3.weight(.semibold))
            Text("Map your tasks, connect dependencies, and see what is ready to start.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: createPlan) {
                Label("New Plan", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
