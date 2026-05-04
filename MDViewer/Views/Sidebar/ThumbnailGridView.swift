import SwiftUI

struct ThumbnailGridView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    let onSelect: (Int) -> Void  // page number (1-based)

    private let columns = [GridItem(.flexible(), spacing: 8)]

    var body: some View {
        if sidebarVM.isGeneratingThumbnails && sidebarVM.thumbnails.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Generating thumbnails…")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sidebarVM.thumbnails.isEmpty {
            // No file open yet — show nothing
            Color.clear
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sidebarVM.thumbnails) { item in
                        Button {
                            onSelect(item.pageNumber)
                        } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: item.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                    )

                                Text("Page \(item.pageNumber)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}
