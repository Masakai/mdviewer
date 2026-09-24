import SwiftUI
import WebKit

struct MarkdownRenderView: View {
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var sidebarVM: SidebarViewModel

    @State private var isSearchVisible: Bool = false
    @State private var searchText: String = ""

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottomLeading) {
                WebRendererView(renderVM: renderVM, sidebarVM: sidebarVM)

                if !renderVM.hoveredURL.isEmpty {
                    Text(renderVM.hoveredURL)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .onReceive(documentVM.$text) { newText in
                if let fileURL = documentVM.fileURL {
                    renderVM.setBaseURL(fileURL.deletingLastPathComponent())
                }
                renderVM.renderMarkdown(newText)
                sidebarVM.extractTOC(from: newText)
            }
            .onChange(of: colorScheme) { _, newScheme in
                renderVM.applySystemAppearance(isDark: newScheme == .dark)
            }

            // Stacked so the banner and the search bar never overlap.
            VStack(spacing: 0) {
                if renderVM.isPreviewInterrupted {
                    PreviewInterruptedBanner {
                        renderVM.retryRendering(documentVM.text)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isSearchVisible {
                    SearchBarView(
                        searchText: $searchText,
                        isVisible: $isSearchVisible,
                        webView: renderVM.webView
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if documentVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSearchVisible)
        .animation(.easeInOut(duration: 0.15), value: renderVM.isPreviewInterrupted)
        .onAppear {
            renderVM.applyCurrentThemeAndFontSize()
            if !documentVM.text.isEmpty {
                renderVM.renderMarkdown(documentVM.text)
                sidebarVM.extractTOC(from: documentVM.text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearchBar)) { _ in
            withAnimation { isSearchVisible = true }
        }
    }
}

/// Native rather than drawn in the web view, so it still shows when the
/// renderer is dead or empty. Stays until a render succeeds, not when the
/// alert is dismissed or Try Again is pressed.
private struct PreviewInterruptedBanner: View {
    let onTryAgain: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)

            Text("preview_interrupted_message")
                .font(.callout)

            Spacer()

            Button("preview_try_again_button", action: onTryAgain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

extension Notification.Name {
    static let showSearchBar = Notification.Name("MDViewer.showSearchBar")
}
