import AppKit
import SwiftUI

/// エディタとプレビューの両方を同じ語で検索する。件数と移動は target の側に効かせ、
/// もう一方は一致を強調するだけにする。置換はエディタが対象のときだけ出す。
struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var isVisible: Bool
    let target: SearchTarget
    /// ⌘F が押された回数。開いたまま押し直したときに、検索欄へ入力を戻す。
    let focusRequest: Int
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var editorSearch: EditorSearchController

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                // Return で次、Shift+Return で前の一致へ移る
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        if NSEvent.modifierFlags.contains(.shift) {
                            findPrevious()
                        } else {
                            findNext()
                        }
                    }

                if !searchText.isEmpty {
                    matchCount

                    Button {
                        findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .help(Text("Previous Match"))
                    .disabled(total == 0)

                    Button {
                        findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .help(Text("Next Match"))
                    .disabled(total == 0)

                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Done") {
                    withAnimation { isVisible = false }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            if target == .editor {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundColor(.secondary)

                    TextField("Replace With", text: $replaceText)
                        .textFieldStyle(.plain)

                    Button("Replace") {
                        editorSearch.replaceCurrent(with: replaceText)
                    }
                    .disabled(total == 0)

                    Button("Replace All") {
                        editorSearch.replaceAll(with: replaceText)
                    }
                    .disabled(total == 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: searchText) { _, newValue in
            renderVM.searchAsTyped(newValue, scroll: target == .preview)
            editorSearch.search(newValue, selecting: target == .editor)
        }
        // ⌘F を押し直して対象が変わったら、件数と移動を新しい対象で数え直す
        .onChange(of: target) { _, newTarget in
            guard !searchText.isEmpty else { return }
            renderVM.search(searchText, scroll: newTarget == .preview)
            editorSearch.search(searchText, selecting: newTarget == .editor)
        }
        // 閉じている間はハイライトを消すので、開き直したら同じ語で検索し直す
        .onAppear {
            isSearchFieldFocused = true
            if !searchText.isEmpty {
                renderVM.search(searchText, scroll: target == .preview)
                editorSearch.search(searchText, selecting: target == .editor)
            }
        }
        .onDisappear {
            renderVM.clearSearch()
            editorSearch.clear()
        }
        .onChange(of: focusRequest) { _, _ in
            isSearchFieldFocused = true
        }
    }

    private var status: RenderViewModel.SearchStatus? {
        target == .editor ? editorSearch.status : renderVM.searchStatus
    }

    private var total: Int {
        status?.total ?? 0
    }

    private func findNext() {
        switch target {
        case .editor: editorSearch.findNext()
        case .preview: renderVM.findNext()
        }
    }

    private func findPrevious() {
        switch target {
        case .editor: editorSearch.findPrevious()
        case .preview: renderVM.findPrevious()
        }
    }

    /// 「3/12」のように何件目か／全件数。結果が届くまでは何も出さない。
    @ViewBuilder
    private var matchCount: some View {
        if let status {
            Group {
                if status.total == 0 {
                    Text("No Matches")
                } else {
                    Text(verbatim: "\(status.current)/\(status.total)")
                }
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
