import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let titles = ["夜の向こう", "春の書架", "物語のある日", "夏のまぼろし", "夕日の先で"]
let colors: [NSColor] = [
    .init(srgbRed: 0.17, green: 0.25, blue: 0.4, alpha: 1), .init(srgbRed: 0.76, green: 0.73, blue: 0.64, alpha: 1),
    .init(srgbRed: 0.84, green: 0.62, blue: 0.62, alpha: 1), .init(srgbRed: 0.40, green: 0.42, blue: 0.65, alpha: 1),
    .init(srgbRed: 0.80, green: 0.51, blue: 0.34, alpha: 1),
]
var games: [[String: Any]] = []
for i in 0..<5 {
    let image = NSImage(size: NSSize(width: 800, height: 800))
    image.lockFocus()
    colors[i].setFill()
    NSRect(x: 0, y: 0, width: 800, height: 800).fill()
    NSColor.white.withAlphaComponent(0.15).setFill()
    NSBezierPath(ovalIn: NSRect(x: 260, y: 340, width: 480, height: 480)).fill()
    let text = titles[i] as NSString
    text.draw(
        at: NSPoint(x: 65, y: 200),
        withAttributes: [.font: NSFont.systemFont(ofSize: 62, weight: .light), .foregroundColor: NSColor.white])
    ("UI FIXTURE 0\(i+1)" as NSString).draw(
        at: NSPoint(x: 65, y: 120),
        withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular), .foregroundColor: NSColor.white,
        ])
    ("合成界面测试 · 非真实游戏" as NSString).draw(
        at: NSPoint(x: 65, y: 70),
        withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white])
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let cover = root.appendingPathComponent("cover-\(i).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: cover)
    let exe = root.appendingPathComponent("测试ゲーム \(i).exe")
    try Data("Not executable: UI test fixture".utf8).write(to: exe)
    games.append([
        "id": UUID().uuidString, "title": titles[i], "alias": "界面演示 · 非真实游戏", "executable": exe.path,
        "workingDirectory": root.path, "coverPath": cover.path, "favorite": i == 2, "state": "未开始", "kind": "独立 EXE",
        "steamAppID": "", "arguments": [], "source": "合成 UI 测试数据",
    ])
}
try JSONSerialization.data(withJSONObject: ["version": 1, "games": games], options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("library.json"))
