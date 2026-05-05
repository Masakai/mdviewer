import SwiftUI

struct SidebarView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    @ObservedObject var renderVM: RenderViewModel

    var body: some View {
        TableOfContentsView(sidebarVM: sidebarVM) { anchor in
            renderVM.scrollToAnchor(anchor)
        }
    }
}
