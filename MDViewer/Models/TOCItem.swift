import Foundation

struct TOCItem: Identifiable, Hashable {
    let id: UUID
    let level: Int       // H1 = 1, H2 = 2, ...
    let title: String
    let anchor: String   // Slugified id used in HTML

    var children: [TOCItem]

    init(level: Int, title: String, anchor: String) {
        self.id = UUID()
        self.level = level
        self.title = title
        self.anchor = anchor
        self.children = []
    }
}
