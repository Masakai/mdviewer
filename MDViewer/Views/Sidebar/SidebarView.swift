import SwiftUI

struct SidebarView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    @ObservedObject var renderVM: RenderViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggle
            Picker("", selection: Binding(
                get: { sidebarVM.mode },
                set: { sidebarVM.setMode($0) }
            )) {
                Label("TOC", systemImage: "list.bullet.indent")
                    .tag(SidebarMode.toc)
                Label("Pages", systemImage: "doc.richtext")
                    .tag(SidebarMode.thumbnails)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch sidebarVM.mode {
            case .toc:
                TableOfContentsView(sidebarVM: sidebarVM) { anchor in
                    renderVM.scrollToAnchor(anchor)
                }
            case .thumbnails:
                ThumbnailGridView(sidebarVM: sidebarVM) { page in
                    let yOffset = Double(page - 1) * 1100
                    renderVM.webView?.evaluateJavaScript("window.scrollTo(0, \(yOffset))", completionHandler: nil)
                }
            }
        }
    }
}
