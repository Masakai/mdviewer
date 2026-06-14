import AppKit
import SwiftUI

struct ContentView: View {
    var initialURL: URL?

    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var exportVM = ExportViewModel()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    @AppStorage("isEditorMode") private var isEditorMode: Bool = false

    var body: some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 400)
            },
            detail: {
                Group {
                    if documentVM.text.isEmpty, documentVM.fileURL == nil {
                        WelcomeView(documentVM: documentVM)
                    } else {
                        HSplitView {
                            // エディタペイン: isEditorMode時のみ表示
                            if isEditorMode {
                                MarkdownEditorView(documentVM: documentVM)
                                    .frame(minWidth: 250)
                            }
                            // プレビューペイン: 常にマウントしておく（破棄しない）
                            MarkdownRenderView(
                                documentVM: documentVM,
                                renderVM: renderVM,
                                sidebarVM: sidebarVM
                            )
                            .frame(minWidth: 250)
                        }
                    }
                }
            }
        )
        .background(WindowCloseInterceptor(documentVM: documentVM))
        .toolbar {
            MainToolbar(documentVM: documentVM, renderVM: renderVM, exportVM: exportVM, isEditorMode: isEditorMode)
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
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            documentVM.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorMode)) { _ in
            isEditorMode.toggle()
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

// MARK: - Window close interceptor

/// NSViewRepresentable that attaches an NSWindowDelegate to block window close when there are unsaved changes.
private struct WindowCloseInterceptor: NSViewRepresentable {
    let documentVM: DocumentViewModel

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.documentVM = documentVM
        DispatchQueue.main.async {
            nsView.window?.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var documentVM: DocumentViewModel

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        func windowShouldClose(_: NSWindow) -> Bool {
            guard documentVM.isDirty else { return true }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("unsaved_changes_title", comment: "")
            alert.informativeText = NSLocalizedString("unsaved_changes_message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("save_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("discard_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                documentVM.save()
                return documentVM.errorMessage == nil
            case .alertSecondButtonReturn:
                return true
            default:
                return false
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
    static let openFile = Notification.Name("MDViewer.openFile")
    static let reloadFile = Notification.Name("MDViewer.reloadFile")
    static let saveFile = Notification.Name("MDViewer.saveFile")
    static let toggleSidebar = Notification.Name("MDViewer.toggleSidebar")
    static let toggleEditorMode = Notification.Name("MDViewer.toggleEditorMode")
}
