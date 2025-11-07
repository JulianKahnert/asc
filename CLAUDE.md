# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ASC is a Swift command-line tool for managing App Store Connect versions. It provides functionality to create versions, update release notes in multiple languages (German/English), and manage credentials securely in the macOS Keychain.

## Build & Run

```bash
# Build the project
swift build

# Run the executable
.build/debug/asc <command>

# Build and run in one step
swift run asc <command>
```

## Testing

Currently no test suite is configured. Consider adding tests in the future.

## Architecture

The application uses Swift ArgumentParser to provide a command-line interface with four main commands:

### Command Structure

- **ASC.swift**: Main entry point defining the ArgumentParser configuration with all subcommands
- **Commands/**: Each command is a separate struct conforming to `AsyncParsableCommand`
  - `InitCommand`: Stores App Store Connect API credentials in keychain
  - `VersionCommand`: Complex workflow for creating/updating versions and localizations
  - `ListAppsCommand`: Lists all apps in the account
  - `ClearCommand`: Removes stored credentials from keychain
- **KeychainHelper.swift**: Centralized keychain operations with static service identifier `"de.JulianKahnert.asc"`

### Key Dependencies

- **AppStoreConnect-Swift-SDK**: Provides `APIProvider`, `APIConfiguration`, and all App Store Connect API endpoints
- **ArgumentParser**: Command-line interface structure

### Credential Flow

1. User runs `init` command with `--issuerID`, `--keyID`, and `--privateKeyFile` parameters
2. Private key file (.p8) is read and PEM headers/footers are stripped (SDK expects only base64 content)
3. All three credentials are stored in macOS Keychain under service `"de.JulianKahnert.asc"`
4. Other commands retrieve credentials from keychain and create `APIConfiguration` + `APIProvider`

### Version Command Workflow

The `version` command handles complex scenarios:

1. **App ID Resolution**: Accepts either numeric App ID or Bundle ID (e.g., "com.example.app"). If Bundle ID is provided, it's resolved to App ID via API.

2. **Dual Platform Version Creation**: Creates/finds versions for both iOS and macOS simultaneously.

3. **Version Creation with Conflict Handling**:
   - Attempts to create new version via `createVersion()`
   - If 409 DUPLICATE error: finds and returns existing version via `findExistingVersion()`
   - If 409 "cannot create in current state" error: finds active version via `findActiveVersion()`, then updates its version number via `updateVersionNumber()`
   - Active states considered: `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`

4. **Localization Updates**: For each platform version, creates or updates localizations for both `de-DE` and `en-US` locales via `updateOrCreateLocalization()`.

### Async/Await Bridging

The App Store Connect SDK uses callback-based APIs. All async operations use `withCheckedThrowingContinuation` to bridge callbacks to Swift's async/await:

```swift
try await withCheckedThrowingContinuation { continuation in
    provider.request(endpoint) { result in
        switch result {
        case .success(let response):
            continuation.resume(returning: response.data.id)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
```

## Platform Requirements

- macOS 15.0+ (specified in Package.swift)
- Swift 6.2+ (swift-tools-version)
- Uses macOS Keychain for credential storage (not portable to Linux)
