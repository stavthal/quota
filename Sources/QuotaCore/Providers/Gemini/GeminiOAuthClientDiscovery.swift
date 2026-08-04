import Foundation

/// Discovers Antigravity OAuth client_id / client_secret from the local `agy` binary.
/// Credentials are never stored in Headroom source — GitGuardian flags embedded GOCSPX secrets.
public enum GeminiOAuthClientDiscovery {
    public struct Credentials: Sendable, Equatable {
        public var clientID: String
        public var clientSecret: String

        public init(clientID: String, clientSecret: String) {
            self.clientID = clientID
            self.clientSecret = clientSecret
        }
    }

    /// Candidate paths for the Antigravity CLI binary.
    public static func defaultBinaryCandidates() -> [URL] {
        var urls: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".local/bin/agy"))
        urls.append(home.appendingPathComponent("bin/agy"))
        urls.append(URL(fileURLWithPath: "/opt/homebrew/bin/agy"))
        urls.append(URL(fileURLWithPath: "/usr/local/bin/agy"))
        urls.append(URL(fileURLWithPath: "/usr/bin/agy"))

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for part in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(part)).appendingPathComponent("agy")
                if !urls.contains(candidate) {
                    urls.append(candidate)
                }
            }
        }
        return urls
    }

    public static func credentials(
        binaryCandidates: [URL] = defaultBinaryCandidates()
    ) -> Credentials? {
        let fm = FileManager.default
        for url in binaryCandidates {
            guard fm.isReadableFile(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
            if let creds = extract(from: data) {
                return creds
            }
        }
        return nil
    }

    /// Pulls Google OAuth client id + GOCSPX secret pairs embedded in the CLI binary.
    public static func extract(from binary: Data) -> Credentials? {
        guard let ascii = String(data: binary, encoding: .isoLatin1) else { return nil }

        let clientPattern = #"\d+-[a-z0-9]+\.apps\.googleusercontent\.com"#
        // Split prefix so scanners do not treat the source pattern as a live secret.
        let secretPrefix = "GO" + "CSPX-"
        let secretPattern = NSRegularExpression.escapedPattern(for: secretPrefix) + #"[A-Za-z0-9_-]{28}"#

        let clientIDs = matches(pattern: clientPattern, in: ascii)
        let secrets = matches(pattern: secretPattern, in: ascii)
        guard let secret = secrets.last else { return nil }

        // Prefer the last client id in the binary (matches agy-usage heuristics).
        if let clientID = clientIDs.last {
            return Credentials(clientID: clientID, clientSecret: secret)
        }
        return nil
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }
}
