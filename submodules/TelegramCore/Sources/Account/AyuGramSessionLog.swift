import Foundation

public enum AyuGramSessionLog {
    private static let queue = DispatchQueue(label: "AyuGramSessionLog")
    private static let maxSize = 256 * 1024

    public static var path: String? {
        guard !Bundle.main.bundlePath.hasSuffix(".appex"), let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return library.appendingPathComponent("ayu-session.log").path
    }

    public static func lastAuthError() -> String {
        return UserDefaults.standard.string(forKey: "ayu.lastAuthError") ?? "-"
    }

    public static func log(_ text: String) {
        Logger.shared.log("AyuSession", text)
        guard let path = self.path else {
            return
        }
        let version = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) [\(version)] \(text)\n"
        self.queue.async {
            guard let data = line.data(using: .utf8) else {
                return
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                let size = handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
                if size > UInt64(self.maxSize), let current = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    try? current.suffix(self.maxSize / 2).write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }

    public static func read() -> String {
        guard let path = self.path, let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
