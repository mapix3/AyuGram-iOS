import Foundation

@main
struct UpdateManifestTests {
    static func expect(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text) }
    static func data(_ json: String) -> Data { json.data(using: .utf8)! }

    static func main() {
        let newer = AyuGramUpdates.parse(data(#"{"build": 200301, "version": "12.6", "url": "https://t.me/ayugramiosupdates/5"}"#), currentBuild: 200201)
        expect(newer == AyuGramUpdateInfo(build: 200301, version: "12.6", url: "https://t.me/ayugramiosupdates/5"), "A newer build is offered")
        expect(AyuGramUpdates.parse(data(#"{"build": 200201, "url": "https://t.me/x"}"#), currentBuild: 200201) == nil, "The same build is not offered")
        expect(AyuGramUpdates.parse(data(#"{"build": 100, "url": "https://t.me/x"}"#), currentBuild: 200201) == nil, "An older build is not offered")
        expect(AyuGramUpdates.parse(data(#"{"build": 300000, "url": "http://t.me/x"}"#), currentBuild: 1) == nil, "Only https links are accepted")
        expect(AyuGramUpdates.parse(data(#"{"build": "300000", "url": "https://t.me/x"}"#), currentBuild: 1)?.version == "300000", "A string build works and names the version")
        expect(AyuGramUpdates.parse(data("not json"), currentBuild: 1) == nil, "A broken manifest is ignored")
        let installable = AyuGramUpdates.parse(data(#"{"build": 300000, "url": "https://t.me/x", "ipa": {"standard": "https://github.com/a.ipa", "custom": "http://insecure/b.ipa"}}"#), currentBuild: 1)
        expect(installable?.ipa == ["standard": "https://github.com/a.ipa"], "IPA links are read per variant, https only")
        print("Update manifest: newer builds only, https links only")
    }
}
