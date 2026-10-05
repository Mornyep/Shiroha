import Foundation

public struct PEInfo: Codable, Equatable, Sendable {
    public let architecture: String
    public let imports: [String]
    public let delayed: [String]
}
public enum PEReader {
    public static func parse(_ data: Data) throws -> PEInfo {
        let b = [UInt8](data)
        func uint(_ p: Int, _ n: Int) throws -> UInt64 {
            guard p >= 0, n > 0, p <= b.count, n <= b.count - p else { throw VNError.message("PE 偏移越界") }
            return (0..<n).reduce(0) { $0 | UInt64(b[p + $1]) << ($1 * 8) }
        }
        func u16(_ p: Int) throws -> Int { Int(try uint(p, 2)) }
        func u32(_ p: Int) throws -> Int { Int(try uint(p, 4)) }
        guard try u16(0) == 0x5a4d else { throw VNError.message("不是有效 MZ 文件") }
        let pe = try u32(0x3c)
        guard try u32(pe) == 0x4550 else { throw VNError.message("不是有效 PE 文件") }
        let machine = try u16(pe + 4)
        let count = try u16(pe + 6)
        let size = try u16(pe + 20)
        let opt = pe + 24
        guard count > 0, count <= 96, size >= 96, opt <= b.count, size <= b.count - opt else {
            throw VNError.message("PE 头不完整")
        }
        let magic = try u16(opt)
        guard magic == 0x10b || magic == 0x20b else { throw VNError.message("未知 PE 格式") }
        let plus = magic == 0x20b
        let dir = opt + (plus ? 112 : 96)
        guard size >= (plus ? 112 : 96) else { throw VNError.message("可选头不完整") }
        let nDirs = try u32(opt + (plus ? 108 : 92))
        let imageBase = try uint(opt + (plus ? 24 : 28), plus ? 8 : 4)
        let headerSize = try u32(opt + 60)
        var sections: [(rva: Int, raw: Int, size: Int)] = []
        for i in 0..<count {
            let s = opt + size + i * 40
            _ = try uint(s + 39, 1)
            sections.append((try u32(s + 12), try u32(s + 20), try u32(s + 16)))
        }
        func offset(_ rva: Int) throws -> Int {
            if rva < headerSize && rva < b.count { return rva }
            for s in sections where rva >= s.rva && rva - s.rva < s.size {
                let p = s.raw + rva - s.rva
                if p < b.count { return p }
            }
            throw VNError.message("PE RVA 无法解析")
        }
        func name(_ rva: Int) throws -> String {
            let p = try offset(rva)
            guard let end = b[p..<min(p + 256, b.count)].firstIndex(of: 0), end > p,
                let s = String(bytes: b[p..<end], encoding: .ascii),
                s.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }), !s.contains("/"), !s.contains("\\"), !s.contains(":")
            else { throw VNError.message("PE 依赖名无效") }
            return s.lowercased()
        }
        func table(_ index: Int, delay: Bool) throws -> [String] {
            guard nDirs > index else { return [] }
            guard dir + index * 8 + 8 <= opt + size else { throw VNError.message("数据目录超出可选头") }
            let rva = try u32(dir + index * 8)
            let length = try u32(dir + index * 8 + 4)
            if rva == 0 { return [] }
            let start = try offset(rva)
            let stride = delay ? 32 : 20
            guard length >= stride, length <= 1024 * 1024 else { throw VNError.message("导入表大小无效") }
            var names: [String] = []
            for i in 0..<min(length / stride, 4096) {
                let p = start + i * stride
                let fields = try (0..<(stride / 4)).map { try u32(p + $0 * 4) }
                if fields.allSatisfy({ $0 == 0 }) { return Array(Set(names)).sorted() }
                var target = fields[delay ? 1 : 3]
                if delay && fields[0] & 1 == 0 {
                    guard UInt64(target) >= imageBase else { throw VNError.message("延迟导入 VA 无效") }
                    target -= Int(imageBase)
                }
                names.append(try name(target))
            }
            throw VNError.message("导入表缺少终止项或达到上限")
        }
        return PEInfo(
            architecture: [0x14c: "x86", 0x8664: "x64", 0xaa64: "arm64"][machine] ?? "unknown",
            imports: try table(1, delay: false), delayed: try table(13, delay: true))
    }
}
