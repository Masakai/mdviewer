import AppKit

struct ThumbnailItem: Identifiable {
    let id: UUID
    let pageNumber: Int
    let image: NSImage

    init(pageNumber: Int, image: NSImage) {
        self.id = UUID()
        self.pageNumber = pageNumber
        self.image = image
    }
}
