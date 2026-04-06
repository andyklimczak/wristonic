import Foundation

enum AppPaths {
    static func baseDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("wristonic", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func downloadsDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager).appendingPathComponent("downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func playbackCacheDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager).appendingPathComponent("playback-cache", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func coverArtCacheDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager).appendingPathComponent("cover-art-cache", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func storeFile(named name: String, fileManager: FileManager = .default) throws -> URL {
        try baseDirectory(fileManager: fileManager).appendingPathComponent(name, isDirectory: false)
    }
}
