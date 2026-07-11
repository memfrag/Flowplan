//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

/// File ▸ Export menu: `.flowplan`/JSON, Markdown summary, and PNG of the graph (spec §18).
struct FlowplanExportCommands: Commands {

    @FocusedValue(\.planViewModel) private var viewModel

    @State private var document = ExportDocument(data: Data())
    @State private var contentType: UTType = .flowplan
    @State private var filename: String = "Plan"
    @State private var isExporting = false

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Section {
                Button("Export as Flowplan…") { export(.flowplan) }
                Button("Export as Markdown…") { export(.markdown) }
                Button("Export Graph as PNG…") { export(.png) }
                Button("Export Graph as PDF…") { export(.pdf) }
                Button("Export Graph as Mermaid…") { export(.mermaid) }
                Button("Export Graph as Graphviz…") { export(.graphviz) }
            }
            .disabled(viewModel?.plan == nil)
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: contentType,
                defaultFilename: filename
            ) { result in
                if case .failure(let error) = result {
                    viewModel?.activeAlert = PlanAlert(title: "Export failed", message: error.localizedDescription)
                }
            }
        }
    }

    private enum ExportKind { case flowplan, markdown, png, pdf, mermaid, graphviz }

    private func export(_ kind: ExportKind) {
        guard let plan = viewModel?.plan else { return }
        let base = plan.title.isEmpty ? "Plan" : plan.title

        switch kind {
        case .flowplan:
            guard let data = try? PlanDTO(plan: plan).jsonData() else { return }
            document = ExportDocument(data: data)
            contentType = .flowplan
            filename = base
        case .markdown:
            let markdown = PlanDTO(plan: plan).markdownSummary()
            document = ExportDocument(data: Data(markdown.utf8))
            contentType = UTType(filenameExtension: "md") ?? .plainText
            filename = base
        case .png:
            guard let data = renderPNG(for: plan) else { return }
            document = ExportDocument(data: data)
            contentType = .png
            filename = base
        case .pdf:
            guard let data = renderPDF(for: plan) else { return }
            document = ExportDocument(data: data)
            contentType = .pdf
            filename = base
        case .mermaid:
            let text = PlanDTO(plan: plan).mermaidGraph()
            document = ExportDocument(data: Data(text.utf8))
            contentType = .mermaid
            filename = base
        case .graphviz:
            let text = PlanDTO(plan: plan).dotGraph()
            document = ExportDocument(data: Data(text.utf8))
            contentType = .graphviz
            filename = base
        }
        isExporting = true
    }

    @MainActor
    private func renderPNG(for plan: Plan) -> Data? {
        let renderer = ImageRenderer(content: GraphSnapshotView(plan: plan))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Renders the graph as a single-page **vector** PDF (crisp at any zoom), by drawing the same
    /// SwiftUI snapshot into a PDF `CGContext`.
    @MainActor
    private func renderPDF(for plan: Plan) -> Data? {
        let renderer = ImageRenderer(content: GraphSnapshotView(plan: plan))
        let data = NSMutableData()
        var didRender = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            pdfContext.beginPDFPage(nil)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            didRender = true
        }
        return didRender ? (data as Data) : nil
    }
}
