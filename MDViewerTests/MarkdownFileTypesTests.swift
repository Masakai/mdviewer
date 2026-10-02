import UniformTypeIdentifiers
import XCTest
@testable import MDViewer

final class MarkdownFileTypesTests: XCTestCase {
    // MARK: - markdownFileTypes

    func testMarkdownFileTypesIncludesMarkdownType() {
        XCTAssertTrue(UTType.markdownFileTypes.contains(.markdown))
    }

    /// 実行環境で `.md` / `.markdown` がどの型に解決されても、「開く」ダイアログで受け付けられること
    func testMarkdownExtensionsConformToAcceptedTypes() throws {
        for ext in ["md", "markdown"] {
            let type = try XCTUnwrap(UTType(filenameExtension: ext))
            XCTAssertTrue(
                UTType.markdownFileTypes.contains { type.conforms(to: $0) },
                "\(ext) が受け付ける型に含まれていない: \(type.identifier)"
            )
        }
    }

    func testMarkdownFileTypesHasNoDuplicates() {
        let types = UTType.markdownFileTypes
        XCTAssertEqual(types.count, Set(types).count)
    }

    // MARK: - Info.plist

    /// macOS 26 以前でも `.md` が Markdown 型として扱われるよう、アプリ自身が型を宣言していること
    func testInfoPlistImportsMarkdownType() throws {
        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations") as? [[String: Any]]
        )
        let markdown = try XCTUnwrap(
            declarations.first { $0["UTTypeIdentifier"] as? String == "net.daringfireball.markdown" }
        )
        let conformsTo = try XCTUnwrap(markdown["UTTypeConformsTo"] as? [String])
        XCTAssertTrue(conformsTo.contains("public.plain-text"))

        let tags = try XCTUnwrap(markdown["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try XCTUnwrap(tags["public.filename-extension"] as? [String])
        XCTAssertEqual(Set(extensions), ["md", "markdown"])
    }
}
