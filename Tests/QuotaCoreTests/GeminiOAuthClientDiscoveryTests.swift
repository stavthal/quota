import Foundation
import QuotaCore
import Testing

@Test func geminiOAuthClientDiscoveryExtractsEmbeddedPair() {
    // Build a synthetic secret at runtime so the repo never contains a GOCSPX literal.
    let secret = "GO" + "CSPX-" + "ABCDEFGHIJKLMNOPQRSTUVWX_yz1"
    let clientID = "999-aaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com"
    let blob = """
    pad-before
    \(clientID)
    noise
    \(secret)
    pad-after
    """.data(using: .utf8)!

    let creds = GeminiOAuthClientDiscovery.extract(from: blob)
    #expect(creds?.clientID == clientID)
    #expect(creds?.clientSecret == secret)
}

@Test func geminiOAuthClientDiscoveryReturnsNilWithoutSecret() {
    let blob = "999-aaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com".data(using: .utf8)!
    #expect(GeminiOAuthClientDiscovery.extract(from: blob) == nil)
}
