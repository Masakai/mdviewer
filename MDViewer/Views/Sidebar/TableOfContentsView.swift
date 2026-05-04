import SwiftUI

struct TableOfContentsView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    let onSelect: (String) -> Void

    var body: some View {
        if sidebarVM.tocItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No headings found")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(sidebarVM.tocItems, id: \.id) { item in
                Button {
                    onSelect(item.anchor)
                } label: {
                    HStack(spacing: 0) {
                        // Indent proportional to heading level
                        Spacer()
                            .frame(width: CGFloat((item.level - 1) * 12))

                        Text(item.title)
                            .font(fontForLevel(item.level))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
        }
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .headline
        case 2: return .subheadline
        default: return .caption
        }
    }
}
