import Foundation

actor JSONFileStore<Value: Codable> {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let data = try encoder.encode(value)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func deleteFile() throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}
