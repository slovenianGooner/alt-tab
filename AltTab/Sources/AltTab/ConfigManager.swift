import Foundation

struct AltTabConfig: Codable {
    var isVertical: Bool = false
    var fontSize: Double = 11.0
}

class ConfigManager {
    static let shared = ConfigManager()

    private let configURL: URL
    private(set) var config: AltTabConfig

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/alt-tab")
        configURL = dir.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AltTabConfig.self, from: data) {
            config = loaded
        } else {
            config = AltTabConfig()
        }
    }

    func update(_ block: (inout AltTabConfig) -> Void) {
        block(&config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }
}
