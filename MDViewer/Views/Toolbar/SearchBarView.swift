import AppKit
import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isVisible: Bool
    @ObservedObject var renderVM: RenderViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            // Return で次、Shift+Return で前の一致へ移る
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        renderVM.findPrevious()
                    } else {
                        renderVM.findNext()
                    }
                }

            if !searchText.isEmpty {
                matchCount

                Button {
                    renderVM.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help(Text("Previous Match"))
                .disabled((renderVM.searchStatus?.total ?? 0) == 0)

                Button {
                    renderVM.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .help(Text("Next Match"))
                .disabled((renderVM.searchStatus?.total ?? 0) == 0)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onChange(of: searchText) { _, newValue in
            renderVM.search(newValue)
        }
        // 閉じている間はハイライトを消すので、開き直したら同じ語で検索し直す
        .onAppear {
            if !searchText.isEmpty {
                renderVM.search(searchText)
            }
        }
        .onDisappear {
            renderVM.clearSearch()
        }
    }

    /// 「3/12」のように何件目か／全件数。結果が届くまでは何も出さない。
    @ViewBuilder
    private var matchCount: some View {
        if let status = renderVM.searchStatus {
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
