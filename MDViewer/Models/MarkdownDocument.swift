import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    static let asciidoc = UTType(importedAs: "org.asciidoc.asciidoc")
}

struct MarkdownDocument: FileDocument {
    var text: String

    static var readableContentTypes: [UTType] {
        [.markdown, .asciidoc, .plainText]
    }

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
