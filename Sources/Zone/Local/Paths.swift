import Foundation

enum FokusPaths {
    /// All saved data. FOKUS_DATA_DIR points it elsewhere, which keeps demos and tests away from real data.
    static var data: URL {
        if let custom = ProcessInfo.processInfo.environment["FOKUS_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fokus")
    }
}
