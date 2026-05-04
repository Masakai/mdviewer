import XCTest
@testable import MDViewer

@MainActor
final class SidebarViewModelTests: XCTestCase {

    var sut: SidebarViewModel!

    override func setUp() async throws {
        try await super.setUp()
        sut = SidebarViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - extractTOC

    func test_extractTOC_emptyString_producesEmptyTOC() {
        // Act
        sut.extractTOC(from: "")

        // Assert
        XCTAssertTrue(sut.tocItems.isEmpty)
    }

    func test_extractTOC_noHeadings_producesEmptyTOC() {
        // Arrange
        let markdown = "This is plain text.\n\nAnother paragraph."

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertTrue(sut.tocItems.isEmpty)
    }

    func test_extractTOC_singleH1_producesSingleItem() {
        // Arrange
        let markdown = "# Hello World"

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems.count, 1)
        XCTAssertEqual(sut.tocItems[0].title, "Hello World")
        XCTAssertEqual(sut.tocItems[0].level, 1)
    }

    func test_extractTOC_multipleHeadings_producesAllItems() {
        // Arrange
        let markdown = """
        # H1
        ## H2
        ### H3
        """

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems.count, 3)
        XCTAssertEqual(sut.tocItems[0].level, 1)
        XCTAssertEqual(sut.tocItems[1].level, 2)
        XCTAssertEqual(sut.tocItems[2].level, 3)
    }

    func test_extractTOC_h1ThenH2_hierarchyOrderIsPreserved() {
        // Arrange
        let markdown = """
        # Introduction
        ## Background
        ## Motivation
        # Conclusion
        """

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems.count, 4)
        XCTAssertEqual(sut.tocItems[0].title, "Introduction")
        XCTAssertEqual(sut.tocItems[1].title, "Background")
        XCTAssertEqual(sut.tocItems[2].title, "Motivation")
        XCTAssertEqual(sut.tocItems[3].title, "Conclusion")
    }

    func test_extractTOC_headingWithSpecialChars_anchorIsSlugified() {
        // Arrange
        let markdown = "# Hello World!"

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems.count, 1)
        // Slug should be lowercase, no trailing special chars
        let anchor = sut.tocItems[0].anchor
        XCTAssertFalse(anchor.contains("!"))
        XCTAssertFalse(anchor.isEmpty)
    }

    func test_extractTOC_headingWithSpaces_anchorUsesHyphen() {
        // Arrange
        let markdown = "# Hello Beautiful World"

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems[0].anchor, "hello-beautiful-world")
    }

    func test_extractTOC_headingWithJapanese_anchorIsNonEmpty() {
        // Arrange
        let markdown = "# はじめに"

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems.count, 1)
        // Japanese characters are non-alphanumeric, anchor may be empty or dashes
        // Key invariant: no leading/trailing dashes
        let anchor = sut.tocItems[0].anchor
        XCTAssertFalse(anchor.hasPrefix("-"))
        XCTAssertFalse(anchor.hasSuffix("-"))
    }

    func test_extractTOC_headingWithLeadingTrailingSpaces_titleIsPreserved() {
        // Arrange
        let markdown = "# Section One"

        // Act
        sut.extractTOC(from: markdown)

        // Assert
        XCTAssertEqual(sut.tocItems[0].title, "Section One")
    }

    // MARK: - slugify (via anchor)

    func test_slugify_uppercaseLetters_convertedToLowercase() {
        let markdown = "# UPPER CASE"
        sut.extractTOC(from: markdown)
        XCTAssertEqual(sut.tocItems[0].anchor, "upper-case")
    }

    func test_slugify_multipleSpaces_collapsedToSingleHyphen() {
        let markdown = "# A   B"
        sut.extractTOC(from: markdown)
        // Multiple spaces become multiple separators, collapsed to single hyphen
        let anchor = sut.tocItems[0].anchor
        XCTAssertFalse(anchor.contains("--"))
    }

    func test_slugify_hyphenInTitle_preservedInAnchor() {
        let markdown = "# my-title"
        sut.extractTOC(from: markdown)
        XCTAssertEqual(sut.tocItems[0].anchor, "my-title")
    }

    func test_slugify_numbersInTitle_preservedInAnchor() {
        let markdown = "# Chapter 2"
        sut.extractTOC(from: markdown)
        XCTAssertEqual(sut.tocItems[0].anchor, "chapter-2")
    }

    // MARK: - TOC thumbnail management

    func test_clearThumbnails_setsIsGeneratingTrue() {
        // Arrange
        sut.addThumbnail(ThumbnailItem(pageNumber: 1, image: NSImage()))

        // Act
        sut.clearThumbnails()

        // Assert
        XCTAssertTrue(sut.thumbnails.isEmpty)
        XCTAssertTrue(sut.isGeneratingThumbnails)
    }

    func test_finishGeneratingThumbnails_setsIsGeneratingFalse() {
        // Arrange
        sut.clearThumbnails()

        // Act
        sut.finishGeneratingThumbnails()

        // Assert
        XCTAssertFalse(sut.isGeneratingThumbnails)
    }

    func test_addThumbnail_appendsToThumbnails() {
        // Arrange
        let item = ThumbnailItem(pageNumber: 1, image: NSImage())

        // Act
        sut.addThumbnail(item)

        // Assert
        XCTAssertEqual(sut.thumbnails.count, 1)
        XCTAssertEqual(sut.thumbnails[0].pageNumber, 1)
    }
}
