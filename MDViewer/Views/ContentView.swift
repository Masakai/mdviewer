import SwiftUI

struct ContentView: View {
    var initialURL: URL? = nil

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var exportVM = ExportViewModel()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true

    var body: some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 400)
            },
            detail: {
                Group {
                    if documentVM.text.isEmpty && documentVM.fileURL == nil {
                        WelcomeView(documentVM: documentVM)
                    } else {
                        MarkdownRenderView(
                            documentVM: documentVM,
                            renderVM: renderVM,
                            sidebarVM: sidebarVM
                        )
                    }
                }
            }
        )
        .toolbar {
            MainToolbar(documentVM: documentVM, renderVM: renderVM, exportVM: exportVM)
        }
        .onOpenURL { url in
            documentVM.load(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            documentVM.openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            documentVM.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            // NavigationSplitView handles its own sidebar toggle
        }
        // Keyboard shortcuts via Commands are declared in MDViewerApp
        .navigationTitle(documentVM.fileURL?.lastPathComponent ?? "MDViewer")
        .frame(minWidth: 800, minHeight: 600)
        .alert("Error", isPresented: Binding(
            get: { documentVM.errorMessage != nil },
            set: { if !$0 { documentVM.errorMessage = nil } }
        )) {
            Button("OK") { documentVM.errorMessage = nil }
        } message: {
            Text(documentVM.errorMessage ?? "")
        }
        .onAppear {
            if let url = initialURL {
                documentVM.load(url: url)
            } else {
                documentVM.restoreLastOpened()
            }
        }
    }
}

// MARK: - Welcome screen

struct WelcomeView: View {
    let documentVM: DocumentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("MDViewer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Open a Markdown file to get started")
                .foregroundColor(.secondary)

            Button("Open File…") {
                documentVM.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.markdown, .plainText, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    documentVM.load(url: url)
                }
            }
            return true
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openFile    = Notification.Name("MDViewer.openFile")
    static let reloadFile  = Notification.Name("MDViewer.reloadFile")
    static let toggleSidebar = Notification.Name("MDViewer.toggleSidebar")
}
