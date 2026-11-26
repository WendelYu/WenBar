import Foundation

public struct SemanticVersion: Comparable, Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let mainPart = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        let parts = mainPart.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var stringValue: String {
        "\(major).\(minor).\(patch)"
    }
}

public struct GitHubReleaseAsset: Codable, Sendable, Equatable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }

    public init(name: String, browserDownloadURL: URL, size: Int64) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
    }
}

public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlURL: URL
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case prerelease
        case draft
        case assets
    }

    public init(
        tagName: String,
        name: String,
        body: String,
        htmlURL: URL,
        prerelease: Bool,
        draft: Bool,
        assets: [GitHubReleaseAsset]
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.prerelease = prerelease
        self.draft = draft
        self.assets = assets
    }
}

public enum ReleaseUpdatePlanner {
    public static func isNewer(remoteTag: String, currentVersion: String) -> Bool {
        guard let remote = SemanticVersion(remoteTag),
              let current = SemanticVersion(currentVersion) else {
            return false
        }
        return remote > current
    }

    /// Prefers `.zip` (fast ditto extraction) and falls back to `.dmg` containing `WenBar`.
    public static func selectBestAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        if let zip = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".zip") && lower.contains("wenbar")
        }) {
            return zip
        }
        if let dmg = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".dmg") && lower.contains("wenbar")
        }) {
            return dmg
        }
        return assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Generates an atomic `/bin/sh` self-swap script that replaces the running `.app` bundle,
    /// clears `com.apple.quarantine`, re-registers FinderSync, and relaunches WenBar cleanly.
    public static func buildInstallScript(
        oldPID: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRoot: String
    ) -> String {
        let qStaged = shellQuote(stagedAppPath)
        let qTarget = shellQuote(targetAppPath)
        let qStaging = shellQuote(stagingRoot)
        let qBackup = shellQuote(targetAppPath + ".wenbar-backup")

        return """
        #!/bin/sh
        OLD_PID=\(oldPID)
        STAGED=\(qStaged)
        TARGET=\(qTarget)
        BACKUP=\(qBackup)
        STAGING_ROOT=\(qStaging)

        # Wait up to 30 seconds for the old process to exit cleanly
        COUNT=0
        while kill -0 "$OLD_PID" 2>/dev/null; do
          COUNT=$((COUNT + 1))
          if [ "$COUNT" -ge 150 ]; then
            kill -9 "$OLD_PID" 2>/dev/null || true
            break
          fi
          sleep 0.2
        done

        rm -rf "$BACKUP"
        if [ -e "$TARGET" ]; then
          mv "$TARGET" "$BACKUP" || exit 1
        fi

        if /usr/bin/ditto "$STAGED" "$TARGET"; then
          rm -rf "$BACKUP"
        else
          rm -rf "$TARGET"
          if [ -e "$BACKUP" ]; then
            mv "$BACKUP" "$TARGET" || true
          fi
          exit 1
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

        APPEX="$TARGET/Contents/PlugIns/WenBarFinderSync.appex"
        if [ -d "$APPEX" ]; then
          /usr/bin/pluginkit -a "$APPEX" 2>/dev/null || true
          /usr/bin/pluginkit -e use -i com.wenbar.app.FinderSync 2>/dev/null || true
        fi

        rm -rf "$STAGING_ROOT"
        /usr/bin/open -n "$TARGET"
        """
    }
}
