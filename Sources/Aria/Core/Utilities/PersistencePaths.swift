import Foundation

/// Centralized filesystem fallbacks for persisted app data.
enum PersistencePaths {
    /// Choose a writable Application Support base directory for Aria.
    /// Falls back to the temporary directory if the system lookup returns nothing.
    static func applicationSupportBaseDirectory(
        appName: String = "Aria",
        applicationSupportURLs: [URL] = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask),
        fileManager: FileManager = .default
    ) -> URL {
        let root = applicationSupportURLs.first ?? fileManager.temporaryDirectory
        let base = root.appendingPathComponent(appName, isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
