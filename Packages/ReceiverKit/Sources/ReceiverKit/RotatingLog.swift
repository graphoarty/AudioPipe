import Foundation

/// Appends a device's capture log to `<name>.log`, rotating to `.1`, `.2` … when
/// the file passes `maxBytes`. Also keeps the last lines in memory for the UI.
public final class RotatingLog: @unchecked Sendable {
    public let url: URL
    private let maxBytes: Int
    private let keep: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private var size = 0
    private var recent: [String] = []
    private let recentLimit = 200
    private var partial = ""

    public init(directory: URL, name: String, maxBytes: Int = 1_000_000, keep: Int = 3) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("\(name).log")
        self.maxBytes = maxBytes
        self.keep = keep
        open()
    }

    deinit { try? handle?.close() }

    private func open() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        let fm = FileManager.default
        for i in stride(from: keep - 1, through: 1, by: -1) {
            let src = url.appendingPathExtension("\(i)")
            let dst = url.appendingPathExtension("\(i + 1)")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
        let first = url.appendingPathExtension("1")
        try? fm.removeItem(at: first)
        try? fm.moveItem(at: url, to: first)
        open()
    }

    public func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if size + data.count > maxBytes { rotate() }
        try? handle?.write(contentsOf: data)
        size += data.count

        partial += String(decoding: data, as: UTF8.self)
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()
        recent.append(contentsOf: lines.filter { !$0.isEmpty })
        if recent.count > recentLimit { recent.removeFirst(recent.count - recentLimit) }
    }

    public func note(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        append(Data("[AudioPipe \(stamp)] \(message)\n".utf8))
    }

    public func recentLines(_ count: Int = 20) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(recent.suffix(count))
    }

    public func fullText(maxBytes: Int = 200_000) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data.suffix(maxBytes), as: UTF8.self)
    }
}
