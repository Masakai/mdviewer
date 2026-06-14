import Markdown
import SwiftUI

enum SidebarMode: String, CaseIterable {
    case toc
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var mode: SidebarMode = .toc
    @Published var tocItems: [TOCItem] = []
    @AppStorage("sidebarMode") private var storedMode: String = SidebarMode.toc.rawValue

    init() {
        if let saved = SidebarMode(rawValue: storedMode) {
            mode = saved
        }
    }

    func setMode(_ newMode: SidebarMode) {
        mode = newMode
        storedMode = newMode.rawValue
    }

    /// Parse headings from raw Markdown using swift-markdown
    func extractTOC(from markdown: String) {
        let document = Document(parsing: markdown)
        var flat: [TOCItem] = []
        collectHeadings(markup: document, into: &flat)
        tocItems = buildHierarchy(from: flat)
    }

    private func collectHeadings(markup: some Markup, into items: inout [TOCItem]) {
        for child in markup.children {
            if let heading = child as? Heading {
                let title = heading.plainText
                let anchor = slugify(title)
                items.append(TOCItem(level: heading.level, title: title, anchor: anchor))
            } else {
                collectHeadings(markup: child, into: &items)
            }
        }
    }

    /// Build a tree from a flat heading list (H1 > H2 > H3...)
    private func buildHierarchy(from flat: [TOCItem]) -> [TOCItem] {
        var result: [TOCItem] = []
        var stack: [TOCItem] = []

        for item in flat {
            let node = item
            // Pop stack until we find a parent with lower level number
            while let last = stack.last, last.level >= item.level {
                stack.removeLast()
            }

            if stack.isEmpty {
                result.append(node)
                stack.append(node)
            } else {
                // Add as child of last stack item
                // Because TOCItem is a value type we must update by index
                appendChild(node, toStack: &stack, result: &result)
            }
        }

        return result
    }

    private func appendChild(_ child: TOCItem, toStack stack: inout [TOCItem], result: inout [TOCItem]) {
        // Walk back through result/stack to attach child to correct parent
        // For simplicity, store flat list with indentation level — hierarchy is visual only
        stack.append(child)
        result.append(child)
    }

    private func slugify(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted)
            .joined(separator: "-")
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Provide plainText on Heading
private extension Heading {
    var plainText: String {
        children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
    }
}
