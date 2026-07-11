//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Flowplan plan document type (JSON-backed `.flowplan`).
    nonisolated static let flowplan = UTType(exportedAs: "io.apparata.flowplan", conformingTo: .json)
}

/// A minimal `FileDocument` that writes pre-rendered `Data` for a chosen content type. Used for
/// exporting `.flowplan`/JSON, Markdown, and PNG/PDF of the graph (spec §18).
struct ExportDocument: FileDocument {

    static let readableContentTypes: [UTType] = [.flowplan, .json, .plainText, .png, .pdf]

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
