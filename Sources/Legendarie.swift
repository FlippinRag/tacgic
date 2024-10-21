@preconcurrency import Adwaita
import Foundation

/// Represents errors that can occur during Legendary operations.
public enum LegendaryError: Error {
    case noAuthCodeProvided
    case loginFailed(String)
}

/// Represents the platforms on which a game can be played.
/// - Note: This is only important for MacOS where you can play games on multiple platforms.
public enum Platform: String, Codable, Sendable {
    case Windows
    case Mac
    case Linux
}

/// Represents an image associated with a game.
public struct KeyImage: Codable, Sendable {
    public let alt: String?
    public let height: Int
    public let md5: String?
    public let size: Int
    public let type: String
    public let uploadedDate: Date
    /// The URL of the image and the only thing that's probably useful to us
    public let url: String
    public let width: Int
}

/// Represents data for a game.
public struct GameData: Codable, Sendable, Identifiable {
    public var id: String { appName ?? UUID().uuidString }

    /// The actual title of the game
    public var appTitle: String?
    /// The code-name used by Legendary
    public var appName: String?
    /// The platforms on which the game can be played(only important for MacOS)
    public var platforms: [Platform]?
    /// The image associated with the game
    public var keyImage: KeyImage?
    /// Whether the game is downloaded
    public var isDownloaded: Bool = false
    /// Whether the game requires an update
    public var requiresUpdate: Bool = false
}

/// A protocol defining the basic functionality for interacting with the Legendary.
/// - Note; This name sucks ik.
public protocol Legendable: Sendable {
    /// Checks if the user is logged in.
    func isLoggedIn() -> Bool
    /// Attempts to log in with the provided auth code.
    /// - Parameter authCode: The auth code to use for logging in.
    /// - Returns: A boolean indicating whether the login was successful.
    /// - Throws: An error if the login fails.
    func tryLogin(authCode: String?) async throws -> Bool
    /// Loads all game data.
    func loadAllGameData() async -> [GameData]?
    /// Refreshes the list of games.
    func loadList() async
    /// Gets the username of the logged in user.
    func getUserName() -> String?
    /// Logs out the user.
    func logout()
}

/// A concrete implementation of the `Legendable` protocol for Unix-like systems.
/// - Note; This implementation uses @Observable on MacOS to allow for DI via .environment.
#if os(macOS)
    @Observable
#endif
public final class Nix: Legendable {
    /// The directory where Legendary stores its configuration.
    private let configDir: URL
    /// The path to the Legendary binary.
    private let binaryPath: String

    /// Initializes a new instance of `Nix`.
    /// - Parameters:
    ///   - configDir: The directory where Legendary stores its configuration.
    ///   - binaryPath: The path to the Legendary binary.
    /// - Note: If `configDir` is not provided, the default directory is `~/.config/legendary`.
    /// - Note: If `binaryPath` is not provided, it is assumed that the `legendary` binary is in the system's PATH.
    public init(configDir: URL? = nil, binaryPath: String? = nil) {
        self.configDir =
            configDir
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                ".config/legendary")
        self.binaryPath = binaryPath ?? "legendary"
    }

    /// Checks if the user is logged in.
    /// - Returns: A boolean indicating whether the user is logged in.
    /// - Note: This is done by checking for the existence of the `user.json` file in the configuration directory.
    public func isLoggedIn() -> Bool {
        let userFile = configDir.appendingPathComponent("user.json")
        print("Checking for user.json at \(userFile.path)")
        return FileManager.default.fileExists(atPath: userFile.path)
    }

    /// Attempts to log in with the provided auth code.
    /// - Parameter authCode: The auth code to use for logging in.
    /// - Returns: A boolean indicating whether the login was successful.
    /// - Throws: An error if the login fails.
    /// - Note: This is done by running the `legendary auth --code` command with the provided auth code.
    public func tryLogin(authCode: String?) async throws -> Bool {
        guard let authCode = authCode else {
            throw LegendaryError.noAuthCodeProvided
        }

        let userFile = configDir.appendingPathComponent("user.json")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binaryPath, "auth", "--code", authCode]
        process.currentDirectoryPath = configDir.path

        var env = ProcessInfo.processInfo.environment
        env["LEGENDARY_CONFIG_PATH"] = configDir.path
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)

        print("Output: \(output ?? "No output")")

        if FileManager.default.fileExists(atPath: userFile.path) {
            return true
        } else {
            throw LegendaryError.loginFailed(output ?? "Unknown error")
        }
    }

    /// Loads all game data.
    /// - Returns: An array of `GameData` objects representing the game data.
    /// - Note: This is done by extracting the game data from the metadata files in the `metadata` directory.
    public func loadAllGameData() async -> [GameData]? {
        guard isLoggedIn() else { return nil }

        let installedGames = await loadInstalledGames()
        let directory = configDir.appendingPathComponent("metadata")

        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return nil }

        var gameDataList: [GameData] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else { continue }

            print("Processing file: \(fileURL.lastPathComponent)")

            if var data = await extractGameDataFromFile(at: fileURL) {
                if let appName = data.appName, !(data.platforms?.isEmpty ?? true) {
                    data.isDownloaded = installedGames.keys.contains(appName)
                    if data.isDownloaded {
                        if let installedVersion = installedGames[appName] {
                            data.requiresUpdate = await checkIfGameIsUpdated(
                                appName: appName, installedVersion: installedVersion)
                        }
                    }
                    gameDataList.append(data)
                    print(
                        "Added game: \(data.appTitle ?? "Unknown"), KeyImage: \(data.keyImage?.url ?? "None")"
                    )
                } else {
                    print("Skipped game due to missing appName or platforms")
                }
            } else {
                print("Failed to extract game data from file")
            }
        }

        print("Total games loaded: \(gameDataList.count)")

        return gameDataList.sorted {
            ($0.appTitle ?? "").localizedCaseInsensitiveCompare($1.appTitle ?? "")
                == .orderedAscending
        }
    }

    /// Loads all installed games.
    /// - Returns: A dictionary containing the installed games and their versions.
    /// - Note: This is done by reading the `installed.json` file in the configuration directory and comparing it with the metadata files.
    private func loadInstalledGames() async -> [String: String] {
        let installedJsonPath = configDir.appendingPathComponent("installed.json")
        guard let data = try? Data(contentsOf: installedJsonPath) else { return [:] }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: [String: Any]]
            {
                var installedGames: [String: String] = [:]
                for (appName, details) in json {
                    if let version = details["version"] as? String {
                        installedGames[appName] = version
                    }
                }
                return installedGames
            }
        } catch {
            print("Error parsing installed.json: \(error)")
        }

        return [:]
    }

    /// Checks if a game is updated.
    /// - Parameters:
    ///   - appName: The name of the game to check.
    ///   - installedVersion: The version of the game that is installed.
    /// - Returns: A boolean indicating whether the game is updated.
    /// - Note: This is done by comparing the installed version with the version in the metadata file.
    private func checkIfGameIsUpdated(appName: String, installedVersion: String) async -> Bool {
        let metadataPath = configDir.appendingPathComponent("metadata").appendingPathComponent(
            "\(appName).json")
        guard let data = try? Data(contentsOf: metadataPath) else { return false }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: Any],
                let assetInfos = json["asset_infos"] as? [String: Any],
                let buildVersion = assetInfos["build_version"] as? String
            {
                return installedVersion != buildVersion
            }
        } catch {
            print("Error checking update for \(appName): \(error)")
        }

        return false
    }

    /// Extracts the platforms from the asset infos.
    /// - Parameter assetInfos: The asset infos dictionary.
    /// - Returns: An array of `Platform` objects.
    /// - Note: This is done by iterating over the asset infos and extracting the platform information.
    private func extractGameDataFromFile(at path: URL) async -> GameData? {
        guard let data = try? Data(contentsOf: path) else { return nil }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: Any]
            {
                var gameData = GameData()
                gameData.appTitle = json["app_title"] as? String
                gameData.appName = json["app_name"] as? String

                if let assetInfos = json["asset_infos"] as? [String: Any] {
                    gameData.platforms = extractPlatforms(from: assetInfos)
                }

                if let metadata = json["metadata"] as? [String: Any] {
                    extractMetadata(from: metadata, into: &gameData)
                }

                return gameData
            }
        } catch {
            print("Error parsing JSON for file \(path.lastPathComponent): \(error)")
        }

        return nil
    }

    /// Extracts the platforms from the asset infos.
    /// - Parameter assetInfos: The asset infos dictionary.
    /// - Returns: An array of `Platform` objects.
    /// - Note: This is done by iterating over the asset infos and extracting the platform information.
    private func extractPlatforms(from assetInfos: [String: Any]) -> [Platform] {
        var platforms: [Platform] = []
        for key in assetInfos.keys {
            if let platform = Platform(rawValue: key) {
                platforms.append(platform)
            }
        }
        return platforms
    }

    /// Extracts the latest metadata from the json file.
    /// - Parameters:
    ///   - metadata: The metadata dictionary.
    ///   - gameData: The game data object to store the metadata.
    /// - Note: This is done by iterating over the metadata and extracting the key images.
    ///         The last valid key image is stored in the game data object.
    private func extractMetadata(from metadata: [String: Any], into gameData: inout GameData) {
        if let keyImages = metadata["keyImages"] as? [[String: Any]] {
            var lastValidKeyImage: KeyImage?
            for image in keyImages {
                if let type = image["type"] as? String,
                    type == "DieselGameBox" || type == "DieselGameBoxTall"
                        || type == "DieselGameBoxLogo" || type == "Thumbnail",
                    let url = image["url"] as? String,
                    let width = image["width"] as? Int,
                    let height = image["height"] as? Int
                {
                    // Create a KeyImage with the available data
                    lastValidKeyImage = KeyImage(
                        alt: image["alt"] as? String,
                        height: height,
                        md5: image["md5"] as? String,
                        size: image["size"] as? Int ?? 0,
                        type: type,
                        uploadedDate: ISO8601DateFormatter().date(
                            from: image["uploadedDate"] as? String ?? "") ?? Date(),
                        url: url,
                        width: width
                    )

                    // If we find a DieselGameBox or DieselGameBoxTall, we can break the loop
                    if type == "DieselGameBox" || type == "DieselGameBoxTall" {
                        break
                    }
                }
            }
            gameData.keyImage = lastValidKeyImage
        }

        // Print debug information
        print("Extracted metadata for game: \(gameData.appTitle ?? "Unknown")")
        print("KeyImage: \(gameData.keyImage?.url ?? "No KeyImage")")
    }

    /// Refreshes the list of games.
    /// - Note: This is done by running 'legendary list --third-party'
    public func loadList() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binaryPath, "list", "--third-party"]
        process.currentDirectoryPath = configDir.path

        var env = ProcessInfo.processInfo.environment
        env["LEGENDARY_CONFIG_PATH"] = configDir.path
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)

        print("Output: \(output ?? "No output")")
    }

    /// Gets the user name from the user.json file.
    /// - Returns: The user name or nil if it could not be read.
    /// - Note: This is done by reading the user.json file and extracting the display name.
    ///         If the file could not be read or the JSON could not be parsed, nil is returned.
    public func getUserName() -> String? {
        let userFile: URL = configDir.appendingPathComponent("user.json")

        guard let data = try? Data(contentsOf: userFile) else {
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: Any],
                let displayName = json["displayName"] as? String
            {
                return displayName
            }
        } catch {
            print("Error parsing JSON: \(error)")
        }

        return nil
    }

    /// Logs out the user by removing the user.json file.
    public func logout() {
        let userFile = configDir.appendingPathComponent("user.json")
        try? FileManager.default.removeItem(at: userFile)

        let userFileLock = configDir.appendingPathComponent("user.json.lock")
        try? FileManager.default.removeItem(at: userFileLock)
    }
}
