import AppKit
import CryptoKit
import Foundation

func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--fixture" {
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 1024,
        bitsPerPixel: 32)!
    var value: UInt32 = 0x17a4b389
    for i in 0..<(256 * 128) {
        for channel in 0..<3 {
            value = value &* 1664525 &+ 1013904223;
            image.bitmapData![i * 4 + channel] = UInt8(truncatingIfNeeded: value >> 24)
        }
        image.bitmapData![i * 4 + 3] = 255
    }
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}
let board = NSPasteboard.general
// Preserve all original formats only in this process's memory, never on disk.
let original = (board.pasteboardItems ?? []).map { item in
    item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
}
var expected = Set<String>()
func currentMatches(_ hashes: Set<String>) -> Bool {
    if let png = board.data(forType: .png), hashes.contains(hash(png)) { return true }
    return board.string(forType: .string).map { hashes.contains(hash(Data($0.utf8))) } ?? false
}
func restore() -> Bool {
    guard currentMatches(expected) else { return false }
    board.clearContents()
    let items = original.map { values -> NSPasteboardItem in
        let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
    }
    if !items.isEmpty { board.writeObjects(items) }; return true
}
func response(_ object: [String: Any]) {
    print(String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!); fflush(stdout)
}
response(["ready": true])
while let line = readLine() {
    guard let data = line.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let command = object["command"] as? String
    else { break }
    switch command {
    case "configure": expected = Set(object["hashes"] as? [String] ?? []); response(["ok": true])
    case "setText":
        board.clearContents(); board.setString(object["text"] as? String ?? "", forType: .string);
        response(["ok": true])
    case "setImage":
        if let path = object["path"] as? String, let png = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            board.clearContents(); board.setData(png, forType: .png); response(["ok": true])
        } else {
            response(["ok": false])
        }
    case "matches": response(["matches": currentMatches(Set([object["sha256"] as? String ?? ""]))])
    case "restore": response(["restored": restore()]); exit(0)
    default: response(["ok": false])
    }
}
_ = restore()
