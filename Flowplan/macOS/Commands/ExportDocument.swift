//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Flowplan plan document type (JSON-backed `.flowplan`).
    nonisolated static let flowplan = UTType(exportedAs: "io.apparata.flowplan", conformingTo: .json)
    /// A Mermaid diagram (`.mmd`).
    nonisolated static let mermaid = UTType(exportedAs: "io.apparata.flowplan.mermaid", conformingTo: .plainText)
    /// A Graphviz DOT graph (`.gv`).
    nonisolated static let graphviz = UTType(exportedAs: "io.apparata.flowplan.graphviz", conformingTo: .plainText)
}

/// A minimal `FileDocument` that writes pre-rendered `Data` for a chosen content type. Used for
/// exporting `.flowplan`/JSON, Markdown, PNG/PDF, and Mermaid/Graphviz of the graph (spec §18).
struct ExportDocument: FileDocument {

    static let readableContentTypes: [UTType] = [.flowplan, .json, .plainText, .png, .pdf, .mermaid, .graphviz]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
