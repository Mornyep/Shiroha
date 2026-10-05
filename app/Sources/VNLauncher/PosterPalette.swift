import AppKit
import ImageIO
import SwiftUI
import VNCore

/// Small quantized histogram: poster colors only, never scene pixels in the backdrop.
actor PosterPalette {
    static let shared = PosterPalette()
    private var cache: [String: [[Double]]] = [:]
    func colors(_ path: String?) -> [[Double]] {
        let fallback = [[0.43, 0.49, 0.46], [0.64, 0.57, 0.45]]
        guard let path else { return fallback }
        if let cached = cache[path] { return cached }
        guard let data = try? FileSafety.read(URL(fileURLWithPath: path), limit: 20 * 1024 * 1024),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 48]
                    as CFDictionary)
        else { return fallback }
        var pixels = [UInt8](repeating: 0, count: 48 * 48 * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 192,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 48, height: 48))
            return true
        }
        guard rendered else { return fallback }
        var bins: [Int: (count: Double, rgb: [Double])] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] > 200 else { continue }
            let c = (0..<3).map { Double(pixels[i + $0]) / 255 }
            let hi = c.max()!
            let lo = c.min()!
            guard hi > 0.12, lo < 0.91 else { continue }
            let key = (Int(c[0] * 5) * 36) + (Int(c[1] * 5) * 6) + Int(c[2] * 5)
            let weight = 0.25 + hi - lo
            let old = bins[key] ?? (0, [0, 0, 0])
            bins[key] = (old.count + weight, zip(old.rgb, c).map { $0 + $1 * weight })
        }
        let sorted = bins.sorted {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }
        var chosen: [[Double]] = []
        for entry in sorted {
            let c = entry.value.rgb.map { $0 / entry.value.count }
            if chosen.allSatisfy({ previous in zip(previous, c).reduce(0.0) { $0 + abs($1.0 - $1.1) } > 0.38 }) {
                chosen.append(c)
            }
            if chosen.count == 2 { break }
        }
        if chosen.isEmpty { chosen = fallback }
        if chosen.count == 1 { chosen.append(chosen[0].map { min(1, $0 + 0.16) }) }
        if cache.count > 40 { cache.removeAll(keepingCapacity: true) }
        cache[path] = chosen
        return chosen
    }
}

struct GameBackdrop: View {
    let path: String?
    var intensity: Double = 0.6
    @State private var colors = [Color(red: 0.43, green: 0.49, blue: 0.46), Color(red: 0.64, green: 0.57, blue: 0.45)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.95, green: 0.945, blue: 0.93)
                if !reduceTransparency {
                    LinearGradient(
                        colors: [colors[0].opacity(0.32), colors[1].opacity(0.16)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        for layer in 0..<4 {
                            let t = CGFloat(layer) * 0.13
                            var dune = Path()
                            dune.move(to: CGPoint(x: -w * 0.1, y: h * (0.30 + t)))
                            dune.addCurve(
                                to: CGPoint(x: w * 1.1, y: h * (0.65 - t)),
                                control1: CGPoint(x: w * 0.40, y: h * (1.18 + t)),
                                control2: CGPoint(x: w * 0.56, y: -h * (0.42 - t)))
                            dune.addLine(to: CGPoint(x: w * 1.1, y: h * 1.2))
                            dune.addLine(to: CGPoint(x: -w * 0.1, y: h * 1.2))
                            dune.closeSubpath()
                            context.fill(
                                dune,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        colors[layer % 2].opacity(0.23), .white.opacity(0.40),
                                        colors[(layer + 1) % 2].opacity(0.24),
                                    ]), startPoint: CGPoint(x: 0, y: h * 0.2), endPoint: CGPoint(x: w, y: h)))
                        }
                    }.blur(radius: 12)
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear, .white.opacity(0.35)], startPoint: .top,
                        endPoint: .bottom)
                }
            }.overlay(Color.white.opacity(1 - min(1, max(0, intensity))))
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.task(id: path) {
            let palette = await PosterPalette.shared.colors(path)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                colors = palette.map { Color(red: $0[0], green: $0[1], blue: $0[2]) }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
