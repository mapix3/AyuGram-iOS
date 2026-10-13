import Foundation

// Keyed container is required by PreferencesEntry's Postbox Codable adapter.
struct AyuLocalPinnedChats: Codable {
    var ids: [Int64]
}
