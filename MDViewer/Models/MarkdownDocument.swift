import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")

    /// 「開く」ダイアログで Markdown として受け付ける型。
    /// macOS 26 以前にはシステム定義の Markdown 型がなく、他のアプリが `.md` を
    /// 別の型で宣言していたり、どのアプリも宣言せず動的型（dyn.*）になったりする。
    /// そのため実行時に拡張子から解決した型も含め、どの環境でも `.md` を選べるようにする。
    static var markdownFileTypes: [UTType] {
        var types: [UTType] = [.markdown]
        for ext in ["md", "markdown"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }
}

struct MarkdownDocument: FileDocument {
    var text: String

    static var readableContentTypes: [UTType] {
        [.markdown, .plainText]
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

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
