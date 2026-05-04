import Foundation

enum HTMLBuilder {
    // Returns the URL of renderer.html in the app bundle's Web resources.
    static func rendererURL() -> URL? {
        Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")
    }

    // Returns the root directory containing all Web resources (vendor, themes, etc.).
    static func webResourcesDirectory() -> URL? {
        Bundle.main.resourceURL.map { $0.appendingPathComponent("Web") }
    }
}
