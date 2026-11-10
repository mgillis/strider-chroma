import Foundation
import StriderKit

/// Reads and writes the saved setting on disk.
enum StateFile {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/strider-chroma/state.json")
    }

    /// Returns an empty state if nothing has been saved yet.
    static func load() throws -> SavedState {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return SavedState()
        }
        do {
            return try JSONDecoder().decode(SavedState.self, from: data)
        } catch {
            throw DeviceError(description: "\(url.path) is not a valid saved setting. Delete it and set the lighting again")
        }
    }

    static func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

extension StriderDevice {
    func send(_ reports: [RazerReport]) throws {
        for report in reports { try send(report) }
    }
}

func describe(_ state: SavedState) -> String {
    var parts: [String] = []
    if let effect = state.effect { parts.append(effect.description) }
    if let brightness = state.brightness { parts.append("brightness \(Brightness.percent(fromByte: brightness))%") }
    return parts.isEmpty ? "nothing set yet" : parts.joined(separator: ", ")
}
