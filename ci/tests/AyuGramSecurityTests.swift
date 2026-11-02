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
        expect(AyuGramSecurity.accountHash(555) == "14889594e3540dc6d0be9892f83f3d98", "Account hashes match the push relay")
        expect(AyuGramSecurity.accountHash(555) != AyuGramSecurity.accountHash(556), "Accounts hash apart")

        let sealed: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 109, 10, 241, 195, 64, 182, 31, 148, 33, 104, 191, 35, 8, 197, 90, 170, 30, 169, 186, 224, 136, 194, 176, 164, 215, 168, 0, 214, 224, 97, 61, 142, 69, 160, 68, 206, 70, 40, 215, 129, 202, 248, 14, 88, 159, 147, 49, 67, 92, 52, 3, 175, 27, 64, 129, 14, 236, 207, 74, 9, 158, 151, 177, 219, 217, 33, 172, 191, 227, 6, 192, 108, 76, 21, 121, 236, 28, 13, 132, 225, 111, 67, 140, 133, 51, 33, 82, 156, 145, 109, 38, 69, 159, 151, 100, 221, 66, 234, 31, 170, 91, 212, 53, 98, 64, 62, 186, 123, 55, 112, 47, 20, 178, 126, 172, 248, 10, 190, 185, 208, 58, 200, 197, 237, 162, 29, 231, 80, 64, 41, 128, 191, 222, 48, 62, 128, 22, 114, 254, 15, 54, 156, 51, 255, 196, 3, 65, 46, 248, 36, 124, 217, 31, 187, 135, 182, 82, 160, 17, 187, 102, 89, 51, 53]
        let origin = AyuGramOrigin.open(sealed)
        expect(origin == AyuGramOrigin(repository: "mapix3/AyuGram-iOS", build: 208301, variant: "custom", commit: "d2abe71e6863", run: "41384897111", bundle: "7196821efee31af21d991a4edfb58722", platform: "github", server: "https://github.com"), "The CI seal opens with where it was built")
        var broken = sealed
        broken[20] ^= 0xff
        expect(AyuGramOrigin.open(broken) == nil, "A damaged seal is refused")
        expect(AyuGramOrigin.open([]) == nil, "No seal is no origin")
        expect(AyuGramSecurity.signature("org.example.app") == "7196821efee31af21d991a4edfb58722", "Signatures match the CI seal")
        expect(AyuGramSecurity.signature("") == "", "Nothing has no signature")
        expect(AyuGramSecurity.copyKind(origin: nil, status: .official, signing: own) == "fork", "A build without our seal is a fork")
        var foreign = origin!
        foreign.repository = "scammer/AyuGram-iOS"
        expect(AyuGramSecurity.copyKind(origin: foreign, status: .official, signing: own) == "fork", "Another repository is a fork")
        expect(AyuGramSecurity.copyKind(origin: origin, status: .modified, signing: own) == "modified", "Changed code is a copy")
        expect(AyuGramSecurity.copyKind(origin: origin, status: .official, signing: own) == nil, "Our build signed for yourself is fine")
        expect(AyuGramSecurity.copyKind(origin: origin, status: .unknown, signing: AyuGramSigningInfo(teamId: "EVIL123456", teamName: "", certificate: "", profileName: "", source: .enterprise, devices: 0)) == "distributor", "Enterprise signing is a distributor")
        expect(AyuGramSecurity.copyKind(origin: origin, status: .official, signing: paid) == "distributor", "Many devices is a distributor")
        print("Security: block list, code fingerprints and anonymous signing info")
    }
}
