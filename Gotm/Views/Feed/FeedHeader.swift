import SwiftUI

struct FeedHeader: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Collected Thoughts")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .kerning(-0.3)
                    .padding(.leading, 2)

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            viewModel.showSearch.toggle()
                            if !viewModel.showSearch { viewModel.searchText = "" }
                        }
                    } label: {
                        Image(systemName: viewModel.showSearch ? "xmark" : "magnifyingglass")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Settings — placeholder
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    TextField("Search notes…", text: $viewModel.searchText)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                    if !viewModel.searchText.isEmpty {
                        Button { viewModel.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
