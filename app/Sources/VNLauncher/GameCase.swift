import SwiftUI

/// The same matte poster participates in shelf/detail geometry and pointer lighting.
struct GameCase: View {
    let path: String?
    let title: String
    /// Normalized coordinates supplied by the shelf's native input surface.
    var pointer: CGPoint? = nil
    var tracksLocalPointer = true
    @State private var localPointer: CGPoint?
    @State private var lastLight = CGPoint(x: 0.5, y: 0.35)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var light: CGPoint? { pointer ?? (tracksLocalPointer ? localPointer : nil) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color(red: 0.22, green: 0.23, blue: 0.22)
                CoverImage(path: path, title: title).padding(.leading, 3)
                LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing).frame(
                    width: 9)
                if !reduceTransparency {
                    let point = reduceMotion ? CGPoint(x: 0.5, y: 0.35) : (light ?? lastLight)
                    RadialGradient(
                        colors: [.white.opacity(0.27), .white.opacity(0.07), .clear],
                        center: UnitPoint(x: point.x, y: point.y), startRadius: 0, endRadius: geometry.size.width * 0.90
                    )
                    .blendMode(.screen)
                    .opacity(light == nil ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: light == nil)
                    .allowsHitTesting(false)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 2))
                .onContinuousHover { phase in
                    guard tracksLocalPointer else { return }
                    switch phase {
                    case .active(let location):
                        guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                        localPointer = CGPoint(
                            x: min(1, max(0, location.x / geometry.size.width)),
                            y: min(1, max(0, location.y / geometry.size.height)))
                    case .ended: localPointer = nil
                    }
                }
        }.shadow(color: .black.opacity(0.12), radius: 14, x: 2, y: 10)
            .onChange(of: light) { _, point in if let point { lastLight = point } }
            .onDisappear { localPointer = nil }
    }
}
