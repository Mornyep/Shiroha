import SwiftUI

/// A continuation of the collection's poster, paper and sand visual language.
struct PanelHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var coverPath: String? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let coverPath {
                CoverImage(path: coverPath, title: subtitle)
                    .frame(width: 38, height: 57)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: .black.opacity(0.16), radius: 7, x: 2, y: 4)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(Color(red: 0.29, green: 0.36, blue: 0.32))
                    .frame(width: 38, height: 57).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 25, weight: .medium)).tracking(-0.6)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct PanelTabs: View {
    let items: [String]
    var values: [String]? = nil
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                let value = values?[index] ?? title
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { selection = value }
                } label: {
                    VStack(spacing: 9) {
                        Text(title).font(.system(size: 14, weight: selection == value ? .semibold : .regular))
                            .foregroundStyle(selection == value ? Color.primary : Color.secondary)
                        Capsule().fill(selection == value ? Color(red: 0.28, green: 0.37, blue: 0.31) : Color.clear)
                            .frame(width: 18, height: 2)
                    }.padding(.horizontal, 3).padding(.top, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func editorSurface(coverPath: String? = nil) -> some View {
        self.background {
            GameBackdrop(path: coverPath, intensity: 0.60)
                .overlay(Color.white.opacity(0.22))
        }.tint(Color(red: 0.28, green: 0.37, blue: 0.31))
    }
    func panelSection() -> some View {
        self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.65), lineWidth: 0.5) }
    }
}
