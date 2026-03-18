import AppStoreConnect_Swift_SDK

extension Platform {
    /// Human-readable display name for CLI output.
    var name: String {
        switch self {
        case .ios: "iOS"
        case .macOs: "macOS"
        default: rawValue
        }
    }
}
