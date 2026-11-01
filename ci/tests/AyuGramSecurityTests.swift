import Foundation

@main
struct SecurityTests {
    static func expect(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text) }
    static func data(_ json: String) -> Data { json.data(using: .utf8)! }

    static func main() {
        let rules = AyuGramBlockRules.parse(data(#"{"build": 1, "block": {"teams": ["scam123456", " "], "builds": [207301, "207401"], "modified": true, "message": "Scam"}}"#))
        expect(rules.teams == ["SCAM123456"], "Team IDs are compared case-insensitively")
        expect(rules.builds == [207301, 207401], "Builds may be numbers or strings")
        expect(rules.message == "Scam", "A custom message is kept")
        expect(rules.matches(teamId: "Scam123456", build: 1, status: .official), "A blocked team is blocked")
        expect(rules.matches(teamId: "", build: 207401, status: .official), "A blocked build is blocked")
        expect(rules.matches(teamId: "OWN1234567", build: 1, status: .modified), "Modified builds are blocked when asked")
        expect(!rules.matches(teamId: "OWN1234567", build: 1, status: .unknown), "An unverified build is not blocked")
        expect(AyuGramBlockRules.parse(data(#"{"build": 1}"#)) == AyuGramBlockRules(), "No block list blocks nothing")
        expect(!AyuGramBlockRules().matches(teamId: "", build: 0, status: .modified), "Modified builds are not blocked by default")

        let remote = ["Telegram": "aa", "Frameworks/TelegramUIFramework.framework/TelegramUIFramework": "bb", "Frameworks/libswiftCore.dylib": "cc"]
        expect(AyuGramSecurity.compare(local: ["Telegram": "aa", "Frameworks/TelegramUIFramework.framework/TelegramUIFramework": "bb"], remote: remote) == .official, "Matching code is official")
        expect(AyuGramSecurity.compare(local: ["Telegram": "aa", "Frameworks/TelegramUIFramework.framework/TelegramUIFramework": "b0"], remote: remote) == .modified, "Changed code is modified")
        expect(AyuGramSecurity.compare(local: ["Telegram": "aa", "Frameworks/inject.dylib": "dd"], remote: remote) == .modified, "An injected library is modified")
        expect(AyuGramSecurity.compare(local: [:], remote: remote) == .modified, "Nothing to compare is not official")
        expect(AyuGramSecurity.parseFingerprint(data(#"{"build": 5, "images": {"Telegram": "aa"}}"#), build: 5) == ["Telegram": "aa"], "A fingerprint of this build is read")
        expect(AyuGramSecurity.parseFingerprint(data(#"{"build": 4, "images": {"Telegram": "aa"}}"#), build: 5) == nil, "Another build's fingerprint is refused")

        expect(AyuGramSecurity.isFingerprintedImage("Telegram", executable: "Telegram"), "The executable is checked")
        expect(AyuGramSecurity.isFingerprintedImage("Frameworks/TelegramUIFramework.framework/TelegramUIFramework", executable: "Telegram"), "Frameworks are checked")
        expect(AyuGramSecurity.isFingerprintedImage("Frameworks/libswift_Concurrency.dylib", executable: "Telegram"), "Bundled dylibs are checked")
        expect(AyuGramSecurity.isFingerprintedImage("inject.dylib", executable: "Telegram"), "A dylib anywhere in the app is checked")
        expect(!AyuGramSecurity.isFingerprintedImage("PlugIns/Share.appex/Share", executable: "Telegram"), "Extensions are not checked")
        expect(!AyuGramSecurity.isFingerprintedImage("Frameworks/A.framework/Frameworks/B.framework/B", executable: "Telegram"), "Only top-level frameworks match the CI fingerprint")

        let profile = Data("garbage<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>TeamName</key><string>Evil LLC</string><key>ProvisionedDevices</key><array><string>a</string><string>b</string></array></dict></plist>tail".utf8)
        let plist = AyuGramSecurity.provisioningPlist(profile)
        expect(plist?["TeamName"] as? String == "Evil LLC", "The plist is cut out of the signed profile")
        expect(AyuGramSecurity.provisioningPlist(Data("no plist".utf8)) == nil, "A missing plist is nil")

        let own = AyuGramSigningInfo(teamId: "OWN1234567", teamName: "Ivan", certificate: "Apple Development: Ivan", profileName: "", source: .sideload, devices: 1)
        expect(!own.identifiesDistributor(status: .official), "An official sideload with a personal certificate stays anonymous")
        expect(!own.identifiesDistributor(status: .unknown), "An unverified personal install stays anonymous")
        expect(own.identifiesDistributor(status: .modified), "A modified build reports its certificate")
        var paid = own
        paid.devices = 40
        expect(paid.identifiesDistributor(status: .official), "A profile with many devices reports its certificate")
        var store = own
        store.source = .testflight
        expect(store.identifiesDistributor(status: .official), "TestFlight installs report their certificate")
        print("Security: block list, code fingerprints and anonymous signing info")
    }
}
