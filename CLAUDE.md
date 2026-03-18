# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ASC is a Swift command-line tool for managing App Store Connect. It provides functionality to create versions, update release notes in multiple languages (German/English), manage credentials securely in the macOS Keychain, and interact with Xcode Cloud workflows.

## Build & Run

```bash
# Build the project (codesign required for Keychain access on macOS)
swift build && codesign --force --sign "Apple Development" .build/debug/asc

# Run the executable
.build/debug/asc <command>
```

## Testing

Run tests with `swift test`. Tests use mock API responses (no live App Store Connect credentials required).

## Architecture

The application uses Swift ArgumentParser to provide a command-line interface.

### Command Structure

Commands use a resource-based noun-verb pattern, grouped by resource:

```
asc init / clear                          # Credential management
asc apps list                             # App listing
asc versions create / show / select-build / submit  # Version lifecycle
asc workflows list / trigger / status     # Xcode Cloud workflows
```

- **ASC.swift**: Main entry point registering command groups
- **Commands/**: Flat directory with prefixed filenames (e.g., `VersionCreateCommand.swift`, `WorkflowsTriggerCommand.swift`). Command groups (e.g., `VersionsCommand.swift`) register their subcommands.
- **KeychainHelper.swift**: Centralized keychain operations with static service identifier `"de.JulianKahnert.asc"`

### Key Dependencies

- **AppStoreConnect-Swift-SDK**: Provides `APIProvider`, `APIConfiguration`, and all App Store Connect API endpoints
- **ArgumentParser**: Command-line interface structure

### Credential Flow

1. User runs `init` command with `--issuerID`, `--keyID`, and `--privateKeyFile` parameters
2. Private key file (.p8) is read and PEM headers/footers are stripped (SDK expects only base64 content)
3. All three credentials are stored in macOS Keychain under service `"de.JulianKahnert.asc"`
4. Other commands retrieve credentials from keychain and create `APIConfiguration` + `APIProvider`

### Version Create Workflow

The `version create` command handles complex scenarios:

1. **App ID Resolution**: Accepts either numeric App ID or Bundle ID (e.g., "com.example.app"). If Bundle ID is provided, it's resolved to App ID via API.

2. **Dual Platform Version Creation**: Creates/finds versions for both iOS and macOS simultaneously.

3. **Version Creation with Conflict Handling**:
   - Attempts to create new version via `createVersion()`
   - If 409 DUPLICATE error: finds and returns existing version via `findExistingVersion()`
   - If 409 "cannot create in current state" error: finds active version via `findActiveVersion()`, then updates its version number via `updateVersionNumber()`
   - Active states considered: `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`

4. **Localization Updates**: For each platform version, creates or updates localizations for both `de-DE` and `en-US` locales via `updateOrCreateLocalization()`.

### Workflows Commands

The `workflows` group uses App Store Connect CI endpoints:

- **list**: Gets CI product for app, then lists workflows with name/enabled/ID
- **trigger**: Resolves workflow by name, finds branch git reference, posts `CiBuildRunCreateRequest`
- **status**: Lists recent build runs per workflow with progress/completion status

## Platform Requirements

- macOS 15.0+ (specified in Package.swift)
- Swift 6.2+ (swift-tools-version)
- Uses macOS Keychain for credential storage (not portable to Linux)
