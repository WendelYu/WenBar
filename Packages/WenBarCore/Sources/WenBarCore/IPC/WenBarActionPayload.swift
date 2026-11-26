import Foundation

public enum WenBarActionKind: String, Codable, Sendable {
    case compressZip
    case compressCustom
    case extractSmart
    case extractSubfolder
    case cleanDSStore
}

/// Shared payload passed between `WenBarFinderSync` and `WenBar.app` via `wenbar://action?...`.
public struct WenBarActionPayload: Codable, Sendable, Equatable {
    public let kind: WenBarActionKind
    public let paths: [String]
    public let targetDirectory: String?

    public init(kind: WenBarActionKind, paths: [String], targetDirectory: String? = nil) {
        self.kind = kind
        self.paths = paths
        self.targetDirectory = targetDirectory
    }

    public func encodeBase64URLSafe() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decodeBase64URLSafe(_ encoded: String) throws -> WenBarActionPayload {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw NSError(domain: "WenBarActionPayload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 payload"])
        }
        return try JSONDecoder().decode(WenBarActionPayload.self, from: data)
    }

    public func makeURL(pasteboardFallbackName: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "wenbar"
        components.host = "action"

        if let pbName = pasteboardFallbackName {
            components.queryItems = [URLQueryItem(name: "pb", value: pbName)]
            return components.url
        }

        if let encoded = try? encodeBase64URLSafe() {
            components.queryItems = [URLQueryItem(name: "payload", value: encoded)]
            return components.url
        }
        return nil
    }
}
