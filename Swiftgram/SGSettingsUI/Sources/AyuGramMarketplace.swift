import Foundation
import UIKit
import AVFoundation
import AVKit
import PhotosUI
import CryptoKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGSimpleSettings
import SGStrings

struct AyuGramMarketFinding: Equatable {
    let level: String
    let text: String
}

struct AyuGramMarketScan: Equatable {
    let verdict: String
    let findings: [AyuGramMarketFinding]
    let ai: String

    static func from(_ object: Any?) -> AyuGramMarketScan? {
        guard let object = object as? [String: Any], let verdict = object["verdict"] as? String else {
            return nil
        }
        let findings = (object["findings"] as? [[String: Any]] ?? []).compactMap { item -> AyuGramMarketFinding? in
            guard let level = item["level"] as? String, let text = item["text"] as? String else {
                return nil
            }
            return AyuGramMarketFinding(level: level, text: text)
        }
        let ai = ((object["ai"] as? [String: Any])?["summary"] as? String) ?? ""
        return AyuGramMarketScan(verdict: verdict, findings: findings, ai: ai)
    }
}

struct AyuGramMarketMedia: Equatable {
    let url: URL
    let isVideo: Bool
}

struct AyuGramMarketPlugin: Equatable {
    let slug: String
    let name: String
    let description: String
    let version: String
    let authorId: Int64
    let authorName: String
    let authorUsername: String
    let permissions: [String]
    let domains: [String]
    let downloads: Int
    let media: [AyuGramMarketMedia]
    let fileExt: String
    let fileSize: Int
    let sha256: String
    let downloadURL: URL?
    let pageURL: URL?
    let scan: AyuGramMarketScan?
    let about: String
    let changelog: String
    let status: String
    let pending: Bool

    static func from(_ object: Any?) -> AyuGramMarketPlugin? {
        guard let object = object as? [String: Any], let slug = object["slug"] as? String, let name = object["name"] as? String else {
            return nil
        }
        let author = object["author"] as? [String: Any] ?? [:]
        let file = object["file"] as? [String: Any] ?? [:]
        let media = (object["media"] as? [[String: Any]] ?? []).compactMap { item -> AyuGramMarketMedia? in
            guard let raw = item["url"] as? String, let url = URL(string: raw) else {
                return nil
            }
            return AyuGramMarketMedia(url: url, isVideo: (item["kind"] as? String) == "video")
        }
        return AyuGramMarketPlugin(
            slug: slug,
            name: name,
            description: object["description"] as? String ?? "",
            version: object["version"] as? String ?? "",
            authorId: Int64(author["id"] as? String ?? "") ?? 0,
            authorName: author["name"] as? String ?? "",
            authorUsername: author["username"] as? String ?? "",
            permissions: object["permissions"] as? [String] ?? [],
            domains: object["domains"] as? [String] ?? [],
            downloads: (object["downloads"] as? NSNumber)?.intValue ?? 0,
            media: media,
            fileExt: file["ext"] as? String ?? "js",
            fileSize: (file["size"] as? NSNumber)?.intValue ?? 0,
            sha256: file["sha256"] as? String ?? "",
            downloadURL: (object["downloadUrl"] as? String).flatMap(URL.init(string:)),
            pageURL: (object["pageUrl"] as? String).flatMap(URL.init(string:)),
            scan: AyuGramMarketScan.from(object["scan"]),
            about: object["about"] as? String ?? "",
            changelog: object["changelog"] as? String ?? "",
            status: object["status"] as? String ?? "live",
            pending: object["pending"] as? Bool ?? false
        )
    }

    var authorTitle: String {
        if !self.authorName.isEmpty {
            return self.authorName
        }
        if !self.authorUsername.isEmpty {
            return "@" + self.authorUsername
        }
        return "ID \(self.authorId)"
    }
}

struct AyuGramMarketSubmission: Equatable {
    let sid: String
    let slug: String
    let name: String
    let version: String
    let status: String
    let reason: String
    let createdAt: Double

    static func from(_ object: Any?, locale: String) -> AyuGramMarketSubmission? {
        guard let object = object as? [String: Any], let sid = object["sid"] as? String else {
            return nil
        }
        let russian = ["ru", "uk", "be", "kk"].contains(locale)
        let reason = (russian ? object["reason"] as? String : object["reasonEn"] as? String) ?? ""
        return AyuGramMarketSubmission(sid: sid, slug: object["slug"] as? String ?? "", name: object["name"] as? String ?? "", version: object["version"] as? String ?? "", status: object["status"] as? String ?? "", reason: reason, createdAt: (object["createdAt"] as? NSNumber)?.doubleValue ?? 0.0)
    }
}

enum AyuGramMarketInstalls {
    private static let key = "ayugram.market.installs"

    static func record(pluginId: String, slug: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[pluginId] = slug
        UserDefaults.standard.set(all, forKey: key)
    }

    static func installed(slug: String) -> AyuGramPluginInfo? {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return AyuGramPluginManager.shared.plugins.first(where: { all[$0.id] == slug || $0.id.lowercased() == slug })
    }

    static func hasUpdate(_ plugin: AyuGramMarketPlugin) -> Bool {
        guard let info = installed(slug: plugin.slug) else {
            return false
        }
        return ayuGramCompareVersions(plugin.version, info.version) > 0
    }
}

func ayuGramCompareVersions(_ a: String, _ b: String) -> Int {
    let split: (String) -> [Int] = { value in
        value.components(separatedBy: CharacterSet(charactersIn: ".-+")).map { Int($0.filter { $0.isNumber }) ?? 0 }
    }
    let left = split(a)
    let right = split(b)
    for index in 0 ..< max(left.count, right.count) {
        let l = index < left.count ? left[index] : 0
        let r = index < right.count ? right[index] : 0
        if l != r {
            return l > r ? 1 : -1
        }
    }
    return 0
}

private final class AyuGramMarketUploadDelegate: NSObject, URLSessionDataDelegate {
    var progress: ((Double) -> Void)?
    var completion: ((Int, [String: Any]) -> Void)?
    private var data = Data()

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else {
            return
        }
        let value = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.progress?(value)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = error == nil ? ((task.response as? HTTPURLResponse)?.statusCode ?? 0) : 0
        let object = (try? JSONSerialization.jsonObject(with: self.data)) as? [String: Any] ?? [:]
        let completion = self.completion
        self.completion = nil
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async {
            completion?(status, object)
        }
    }
}

final class AyuGramMarketClient {
    static let shared = AyuGramMarketClient()
    static let base = AyuGramSecurity.relayURL + "/market"
    static let site = "https://relay.mapixdev.com/market"

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30.0
        self.session = URLSession(configuration: configuration)
    }

    private func request(_ path: String, method: String = "GET", accountId: Int64? = nil) -> URLRequest? {
        guard let url = URL(string: AyuGramMarketClient.base + path) else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !AyuGramProfileRelay.shared.authorize(&request, accountId: accountId) {
            return nil
        }
        return request
    }

    private func perform(_ request: URLRequest?, completion: @escaping (Int, [String: Any]) -> Void) {
        guard let request else {
            completion(0, [:])
            return
        }
        self.session.dataTask(with: request, completionHandler: { data, response, error in
            let status = error == nil ? ((response as? HTTPURLResponse)?.statusCode ?? 0) : 0
            let object = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            DispatchQueue.main.async {
                completion(status, object)
            }
        }).resume()
    }

    func list(query: String, sort: String, completion: @escaping ([AyuGramMarketPlugin]?) -> Void) {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "sort", value: sort)]
        self.perform(self.request("/api/plugins" + (components.percentEncodedQuery.map { "?" + $0 } ?? "")), completion: { status, object in
            guard status == 200 else {
                completion(nil)
                return
            }
            completion((object["items"] as? [Any] ?? []).compactMap { AyuGramMarketPlugin.from($0) })
        })
    }

    func detail(slug: String, completion: @escaping (AyuGramMarketPlugin?) -> Void) {
        let escaped = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        self.perform(self.request("/api/plugins/" + escaped), completion: { status, object in
            completion(status == 200 ? AyuGramMarketPlugin.from(object["plugin"]) : nil)
        })
    }

    func mine(accountId: Int64, locale: String, completion: @escaping (Int, Bool, [AyuGramMarketPlugin], [AyuGramMarketSubmission]) -> Void) {
        self.perform(self.request("/api/mine", accountId: accountId), completion: { status, object in
            let plugins = (object["plugins"] as? [Any] ?? []).compactMap { AyuGramMarketPlugin.from($0) }
            let submissions = (object["submissions"] as? [Any] ?? []).compactMap { AyuGramMarketSubmission.from($0, locale: locale) }
            completion(status, object["verified"] as? Bool ?? false, plugins, submissions)
        })
    }

    func remove(slug: String, accountId: Int64, completion: @escaping (Bool) -> Void) {
        let escaped = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        self.perform(self.request("/api/plugins/" + escaped, method: "DELETE", accountId: accountId), completion: { status, _ in
            completion(status == 200)
        })
    }

    func scan(data: Data, name: String, completion: @escaping (AyuGramMarketScan?) -> Void) {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "plugin.js"
        guard var request = self.request("/api/scan?name=" + escaped, method: "POST") else {
            completion(nil)
            return
        }
        request.timeoutInterval = 15.0
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        self.perform(request, completion: { status, object in
            completion(status == 200 ? AyuGramMarketScan.from(object["scan"]) : nil)
        })
    }

    func download(_ plugin: AyuGramMarketPlugin, completion: @escaping (URL?) -> Void) {
        guard let url = plugin.downloadURL else {
            completion(nil)
            return
        }
        self.session.downloadTask(with: url, completionHandler: { location, response, _ in
            guard let location, (response as? HTTPURLResponse)?.statusCode == 200, let data = try? Data(contentsOf: location) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard plugin.sha256.isEmpty || digest == plugin.sha256.lowercased() else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + plugin.slug + "." + (plugin.fileExt == "zip" ? "zip" : "js"))
            let saved = (try? data.write(to: target)) != nil
            DispatchQueue.main.async {
                completion(saved ? target : nil)
            }
        }).resume()
    }

    func submit(accountId: Int64, file: URL, meta: [String: Any], media: [(Data, String, String)], progress: @escaping (Double) -> Void, completion: @escaping (Int, [String: Any]) -> Void) {
        guard var request = self.request("/api/submit", method: "POST", accountId: accountId), let fileData = try? Data(contentsOf: file), let metaData = try? JSONSerialization.data(withJSONObject: meta) else {
            completion(0, [:])
            return
        }
        let boundary = "ayugram-" + UUID().uuidString
        var body = Data()
        func part(_ name: String, filename: String?, mime: String?, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            var disposition = "Content-Disposition: form-data; name=\"\(name)\""
            if let filename {
                disposition += "; filename=\"\(filename.replacingOccurrences(of: "\"", with: "_"))\""
            }
            body.append((disposition + "\r\n").data(using: .utf8)!)
            if let mime {
                body.append("Content-Type: \(mime)\r\n".data(using: .utf8)!)
            }
            body.append("\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        part("meta", filename: nil, mime: "application/json", data: metaData)
        part("file", filename: file.lastPathComponent, mime: "application/octet-stream", data: fileData)
        for (data, mime, name) in media {
            part("media", filename: name, mime: mime, data: data)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 300.0
        let delegate = AyuGramMarketUploadDelegate()
        delegate.progress = progress
        delegate.completion = completion
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.uploadTask(with: request, from: body).resume()
    }
}

private final class AyuGramMarketImages {
    static let shared = AyuGramMarketImages()
    private let cache = NSCache<NSURL, UIImage>()

    func load(_ media: AyuGramMarketMedia, completion: @escaping (UIImage?) -> Void) {
        if let image = self.cache.object(forKey: media.url as NSURL) {
            completion(image)
            return
        }
        if media.isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900.0, height: 900.0)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600))], completionHandler: { [weak self] _, image, _, result, _ in
                let poster = result == .succeeded ? image.map { UIImage(cgImage: $0) } : nil
                if let poster {
                    self?.cache.setObject(poster, forKey: media.url as NSURL)
                }
                DispatchQueue.main.async {
                    completion(poster)
                }
            })
            return
        }
        URLSession.shared.dataTask(with: media.url, completionHandler: { [weak self] data, _, _ in
            var image: UIImage?
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil) {
                let options: [String: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                    kCGImageSourceCreateThumbnailWithTransform as String: true,
                    kCGImageSourceThumbnailMaxPixelSize as String: 1200
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
            }
            if let image {
                self?.cache.setObject(image, forKey: media.url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }).resume()
    }
}

private func ayuMarketVerdictColor(_ verdict: String) -> UIColor {
    switch verdict {
    case "clean":
        return UIColor(red: 0.24, green: 0.81, blue: 0.56, alpha: 1.0)
    case "danger":
        return UIColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1.0)
    default:
        return UIColor(red: 0.96, green: 0.69, blue: 0.25, alpha: 1.0)
    }
}

private func ayuMarketVerdictText(_ verdict: String, locale: String) -> String {
    return i18n("Ayu.Market.Verdict." + (["clean", "warn", "danger"].contains(verdict) ? verdict : "warn"), locale)
}

func ayuGramMarketScanText(_ scan: AyuGramMarketScan, locale: String) -> String {
    var lines = [i18n("Ayu.Market.Check", locale) + ": " + ayuMarketVerdictText(scan.verdict, locale: locale)]
    for finding in scan.findings.filter({ $0.level != "info" }).prefix(8) {
        lines.append((finding.level == "danger" ? "⛔ " : "⚠️ ") + finding.text)
    }
    if !scan.ai.isEmpty {
        lines.append("🤖 " + scan.ai)
    }
    return lines.joined(separator: "\n")
}

private func ayuMarketErrorText(_ status: Int, _ object: [String: Any], locale: String) -> String {
    let code = object["error"] as? String ?? ""
    if status == 0 {
        return i18n("Ayu.Market.Error.Network", locale)
    }
    let known = ["unverified", "media_required", "slug_taken", "version_not_newer", "rate_limited", "bad_plugin", "bad_plugin_id", "file_too_large", "media_too_large", "too_many_media", "bad_description", "bad_name", "author_blocked", "plugin_blocked", "too_many_plugins", "unsupported_media", "bad_media", "storage_full", "banned", "too_large"]
    if known.contains(code) {
        if code == "version_not_newer", let current = object["current"] as? String {
            return i18n("Ayu.Market.Error.version_not_newer", locale) + " (" + current + ")"
        }
        return i18n("Ayu.Market.Error." + code, locale)
    }
    return i18n("Ayu.Market.Error.Server", locale)
}

private func ayuMarketAccountId(_ context: AccountContext) -> Int64 {
    return context.account.peerId.id._internalGetInt64Value()
}

private func ayuMarketOpenAuthor(context: AccountContext, plugin: AyuGramMarketPlugin) {
    guard plugin.authorId > 0 else {
        return
    }
    let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(plugin.authorId))
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).startStandalone(next: { peer in
        if let peer, let profile = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            (context.sharedContext.mainWindow?.viewController as? NavigationController)?.pushViewController(profile)
        } else if !plugin.authorUsername.isEmpty {
            ayuGramOpenLink(context: context, url: "https://t.me/" + plugin.authorUsername)
        } else {
            ayuGramOpenLink(context: context, url: "https://t.me/@id\(plugin.authorId)")
        }
    })
}

func ayuGramMarketInstall(context: AccountContext, plugin: AyuGramMarketPlugin, present: @escaping (ViewController) -> Void, finished: @escaping (Bool) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let fail = {
        finished(false)
        present(textAlertController(context: context, title: nil, text: i18n("Ayu.Market.DownloadFailed", locale), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }
    AyuGramMarketClient.shared.download(plugin, completion: { url in
        guard let url, let package = try? ayuGramReadPluginPackage(at: url) else {
            fail()
            return
        }
        finished(false)
        let notice = plugin.scan.map { ayuGramMarketScanText($0, locale: locale) }
        ayuGramPresentPluginInstall(context: context, package: package, notice: notice, present: present, completion: {
            AyuGramMarketInstalls.record(pluginId: package.info.id, slug: plugin.slug)
            finished(true)
        })
    })
}

private final class AyuGramMarketCell: UITableViewCell {
    let cover = UIImageView()
    let title = UILabel()
    let subtitle = UILabel()
    let meta = UILabel()
    let dot = UIView()
    let state = UILabel()
    var mediaURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.cover.contentMode = .scaleAspectFill
        self.cover.clipsToBounds = true
        self.cover.layer.cornerRadius = 12.0
        self.cover.layer.cornerCurve = .continuous
        self.title.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.subtitle.font = UIFont.systemFont(ofSize: 14.0)
        self.subtitle.numberOfLines = 2
        self.meta.font = UIFont.systemFont(ofSize: 12.0)
        self.dot.layer.cornerRadius = 4.0
        self.state.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.state.textAlignment = .right
        for view in [self.cover, self.title, self.subtitle, self.meta, self.dot, self.state] as [UIView] {
            self.contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 16.0
        let height = self.contentView.bounds.height
        self.cover.frame = CGRect(x: inset, y: 12.0, width: 64.0, height: 64.0)
        let left = self.cover.frame.maxX + 12.0
        let stateWidth: CGFloat = self.state.text?.isEmpty == false ? min(110.0, self.state.intrinsicContentSize.width) : 0.0
        let right = self.contentView.bounds.width - 16.0
        self.state.frame = CGRect(x: right - stateWidth, y: 12.0, width: stateWidth, height: 20.0)
        self.title.frame = CGRect(x: left, y: 10.0, width: max(0.0, right - left - stateWidth - (stateWidth > 0.0 ? 8.0 : 0.0)), height: 22.0)
        let subtitleSize = self.subtitle.sizeThatFits(CGSize(width: right - left, height: 40.0))
        self.subtitle.frame = CGRect(x: left, y: 33.0, width: right - left, height: min(38.0, subtitleSize.height))
        self.dot.frame = CGRect(x: left, y: height - 20.0, width: 8.0, height: 8.0)
        self.meta.frame = CGRect(x: left + 14.0, y: height - 26.0, width: right - left - 14.0, height: 18.0)
    }
}

private final class AyuGramMarketListController: ViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    private let tableView = UITableView(frame: CGRect(), style: .insetGrouped)
    private let segment = UISegmentedControl()
    private let searchBar = UISearchBar()
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let refresh = UIRefreshControl()
    private var plugins: [AyuGramMarketPlugin] = []
    private var minePlugins: [AyuGramMarketPlugin] = []
    private var mineSubmissions: [AyuGramMarketSubmission] = []
    private var mineVerified = true
    private var mineLoaded = false
    private var sort = "popular"
    private var query = ""
    private var loading = false
    private var searchTimer: Foundation.Timer?
    private var pluginsObserver: NSObjectProtocol?

    private var locale: String {
        return self.presentationData.strings.baseLanguageCode
    }

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = i18n("Ayu.Market.Title", self.presentationData.strings.baseLanguageCode)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.updateBarButtons()
        self.pluginsObserver = NotificationCenter.default.addObserver(forName: AyuGramPluginManager.didChange, object: nil, queue: .main, using: { [weak self] _ in
            self?.tableView.reloadData()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let pluginsObserver = self.pluginsObserver {
            NotificationCenter.default.removeObserver(pluginsObserver)
        }
        self.searchTimer?.invalidate()
    }

    private func updateBarButtons() {
        let color = self.presentationData.theme.rootController.navigationBar.accentTextColor
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(self.submitPressed))
        add.tintColor = color
        let sortActions = [("popular", "Ayu.Market.Sort.Popular"), ("new", "Ayu.Market.Sort.New"), ("updated", "Ayu.Market.Sort.Updated")].map { key, title in
            UIAction(title: i18n(title, self.locale), state: self.sort == key ? .on : .off, handler: { [weak self] _ in
                guard let self else {
                    return
                }
                self.sort = key
                self.updateBarButtons()
                self.reload()
            })
        }
        let web = UIAction(title: i18n("Ayu.Market.OpenSite", self.locale), image: UIImage(systemName: "safari"), handler: { [weak self] _ in
            guard let self else {
                return
            }
            ayuGramOpenLink(context: self.context, url: AyuGramMarketClient.site)
        })
        let more = UIBarButtonItem(title: nil, image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: nil, menu: UIMenu(children: [UIMenu(options: .displayInline, children: sortActions), web]))
        more.tintColor = color
        self.navigationItem.rightBarButtonItems = [add, more]
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(AyuGramMarketCell.self, forCellReuseIdentifier: "plugin")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "text")
        self.tableView.separatorColor = theme.list.itemBlocksSeparatorColor
        self.tableView.keyboardDismissMode = .onDrag
        self.refresh.addTarget(self, action: #selector(self.refreshPulled), for: .valueChanged)
        self.tableView.refreshControl = self.refresh
        self.segment.insertSegment(withTitle: i18n("Ayu.Market.Catalog", self.locale), at: 0, animated: false)
        self.segment.insertSegment(withTitle: i18n("Ayu.Market.Mine", self.locale), at: 1, animated: false)
        self.segment.selectedSegmentIndex = 0
        self.segment.addTarget(self, action: #selector(self.segmentChanged), for: .valueChanged)
        self.searchBar.placeholder = i18n("Ayu.Market.Search", self.locale)
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.tintColor = theme.list.itemAccentColor
        self.searchBar.searchTextField.textColor = theme.list.itemPrimaryTextColor
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.textAlignment = .center
        self.spinner.color = theme.list.itemSecondaryTextColor
        for view in [self.tableView, self.segment, self.emptyLabel, self.spinner] as [UIView] {
            self.displayNode.view.addSubview(view)
        }
        self.updateHeader()
        self.reload()
    }

    private func updateHeader() {
        if self.segment.selectedSegmentIndex == 0 {
            self.searchBar.frame = CGRect(x: 0.0, y: 0.0, width: self.tableView.bounds.width, height: 52.0)
            self.tableView.tableHeaderView = self.searchBar
        } else {
            self.tableView.tableHeaderView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 8.0))
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let side = layout.safeInsets.left
        self.segment.frame = CGRect(x: side + 16.0, y: top + 8.0, width: layout.size.width - side * 2.0 - 32.0, height: 32.0)
        let tableTop = self.segment.frame.maxY + 6.0
        self.tableView.frame = CGRect(x: 0.0, y: tableTop, width: layout.size.width, height: layout.size.height - tableTop)
        self.tableView.contentInset.bottom = layout.intrinsicInsets.bottom
        if self.searchBar.frame.width != layout.size.width {
            self.updateHeader()
        }
        self.emptyLabel.frame = CGRect(x: side + 32.0, y: tableTop + 120.0, width: layout.size.width - side * 2.0 - 64.0, height: 80.0)
        self.spinner.center = CGPoint(x: layout.size.width / 2.0, y: tableTop + 100.0)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.isNodeLoaded {
            self.tableView.reloadData()
        }
    }

    @objc private func refreshPulled() {
        self.reload()
    }

    @objc private func segmentChanged() {
        self.updateHeader()
        self.searchBar.resignFirstResponder()
        self.tableView.reloadData()
        self.updateEmpty()
        if self.segment.selectedSegmentIndex == 1 && !self.mineLoaded {
            self.reload()
        }
    }

    @objc private func submitPressed() {
        self.push(ayuGramMarketSubmitController(context: self.context, completed: { [weak self] in
            self?.mineLoaded = false
            self?.segment.selectedSegmentIndex = 1
            self?.segmentChanged()
        }))
    }

    private func reload() {
        self.loading = true
        if self.refresh.isRefreshing == false && (self.segment.selectedSegmentIndex == 0 ? self.plugins.isEmpty : !self.mineLoaded) {
            self.spinner.startAnimating()
        }
        self.updateEmpty()
        if self.segment.selectedSegmentIndex == 0 {
            AyuGramMarketClient.shared.list(query: self.query, sort: self.sort, completion: { [weak self] items in
                guard let self else {
                    return
                }
                self.loading = false
                self.spinner.stopAnimating()
                self.refresh.endRefreshing()
                if let items {
                    self.plugins = items
                    self.emptyLabel.tag = 0
                } else {
                    self.emptyLabel.tag = 1
                }
                self.tableView.reloadData()
                self.updateEmpty()
            })
        } else {
            AyuGramMarketClient.shared.mine(accountId: ayuMarketAccountId(self.context), locale: self.locale, completion: { [weak self] status, verified, plugins, submissions in
                guard let self else {
                    return
                }
                self.loading = false
                self.spinner.stopAnimating()
                self.refresh.endRefreshing()
                if status == 200 {
                    self.mineLoaded = true
                    self.mineVerified = verified
                    self.minePlugins = plugins
                    self.mineSubmissions = submissions
                    self.emptyLabel.tag = 0
                } else {
                    self.emptyLabel.tag = 1
                }
                self.tableView.reloadData()
                self.updateEmpty()
            })
        }
    }

    private func updateEmpty() {
        let isCatalog = self.segment.selectedSegmentIndex == 0
        let empty = isCatalog ? self.plugins.isEmpty : (self.mineLoaded && self.minePlugins.isEmpty && self.mineSubmissions.isEmpty && self.mineVerified)
        if self.loading {
            self.emptyLabel.isHidden = true
        } else if self.emptyLabel.tag == 1 && (isCatalog ? self.plugins.isEmpty : !self.mineLoaded) {
            self.emptyLabel.text = i18n("Ayu.Market.Error.Network", self.locale)
            self.emptyLabel.isHidden = false
        } else {
            self.emptyLabel.text = isCatalog ? (self.query.isEmpty ? i18n("Ayu.Market.Empty", self.locale) : i18n("Ayu.Market.NothingFound", self.locale)) : i18n("Ayu.Market.MineEmpty", self.locale)
            self.emptyLabel.isHidden = !empty
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchTimer?.invalidate()
        self.searchTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false, block: { [weak self] _ in
            guard let self else {
                return
            }
            self.query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.reload()
        })
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private enum MineRow {
        case verify
        case plugin(AyuGramMarketPlugin)
        case submission(AyuGramMarketSubmission)
    }

    private var mineSections: [[MineRow]] {
        var sections: [[MineRow]] = []
        if !self.mineVerified {
            sections.append([.verify])
        }
        if !self.minePlugins.isEmpty {
            sections.append(self.minePlugins.map { .plugin($0) })
        }
        if !self.mineSubmissions.isEmpty {
            sections.append(self.mineSubmissions.map { .submission($0) })
        }
        return sections
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.segment.selectedSegmentIndex == 0 ? 1 : self.mineSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.segment.selectedSegmentIndex == 0 ? self.plugins.count : self.mineSections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard self.segment.selectedSegmentIndex == 1, section < self.mineSections.count, let first = self.mineSections[section].first else {
            return nil
        }
        switch first {
        case .verify:
            return nil
        case .plugin:
            return i18n("Ayu.Market.MyPlugins", self.locale)
        case .submission:
            return i18n("Ayu.Market.MySubmissions", self.locale)
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if self.segment.selectedSegmentIndex == 1, case .submission = self.mineSections[indexPath.section][indexPath.row] {
            return UITableView.automaticDimension
        }
        if self.segment.selectedSegmentIndex == 1, case .verify = self.mineSections[indexPath.section][indexPath.row] {
            return UITableView.automaticDimension
        }
        return 88.0
    }

    private func configure(_ cell: AyuGramMarketCell, plugin: AyuGramMarketPlugin, mine: Bool) {
        let theme = self.presentationData.theme
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.title.textColor = theme.list.itemPrimaryTextColor
        cell.subtitle.textColor = theme.list.itemSecondaryTextColor
        cell.meta.textColor = theme.list.itemSecondaryTextColor
        cell.cover.backgroundColor = theme.list.itemBlocksSeparatorColor
        cell.title.text = plugin.name
        cell.subtitle.text = plugin.description
        var meta = ["v" + plugin.version]
        if mine {
            meta.append(i18n(plugin.status == "live" ? "Ayu.Market.Status.Live" : plugin.status == "draft" ? "Ayu.Market.Status.Draft" : "Ayu.Market.Status.Hidden", self.locale))
            if plugin.pending {
                meta.append(i18n("Ayu.Market.Status.UpdatePending", self.locale))
            }
        } else {
            meta.append(plugin.authorTitle)
        }
        meta.append(i18n("Ayu.Market.Downloads", self.locale, "\(plugin.downloads)"))
        cell.meta.text = meta.joined(separator: " · ")
        cell.dot.backgroundColor = ayuMarketVerdictColor(plugin.scan?.verdict ?? "warn")
        cell.dot.isHidden = plugin.scan == nil
        if AyuGramMarketInstalls.hasUpdate(plugin) {
            cell.state.text = i18n("Ayu.Market.UpdateAvailable", self.locale)
            cell.state.textColor = theme.list.itemAccentColor
        } else if AyuGramMarketInstalls.installed(slug: plugin.slug) != nil {
            cell.state.text = i18n("Ayu.Market.Installed", self.locale)
            cell.state.textColor = theme.list.itemSecondaryTextColor
        } else {
            cell.state.text = ""
        }
        cell.accessoryType = .disclosureIndicator
        cell.cover.image = UIImage(systemName: "puzzlepiece.extension.fill")?.withTintColor(theme.list.itemSecondaryTextColor, renderingMode: .alwaysOriginal)
        cell.cover.contentMode = .center
        let media = plugin.media.first(where: { !$0.isVideo }) ?? plugin.media.first
        cell.mediaURL = media?.url
        if let media {
            AyuGramMarketImages.shared.load(media, completion: { [weak cell] image in
                guard let cell, cell.mediaURL == media.url, let image else {
                    return
                }
                cell.cover.contentMode = .scaleAspectFill
                cell.cover.image = image
            })
        }
        cell.setNeedsLayout()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = self.presentationData.theme
        if self.segment.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "plugin", for: indexPath) as! AyuGramMarketCell
            self.configure(cell, plugin: self.plugins[indexPath.row], mine: false)
            return cell
        }
        switch self.mineSections[indexPath.section][indexPath.row] {
        case let .plugin(plugin):
            let cell = tableView.dequeueReusableCell(withIdentifier: "plugin", for: indexPath) as! AyuGramMarketCell
            self.configure(cell, plugin: plugin, mine: true)
            return cell
        case .verify:
            let cell = tableView.dequeueReusableCell(withIdentifier: "text", for: indexPath)
            cell.backgroundColor = theme.list.itemBlocksBackgroundColor
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.textColor = theme.list.itemAccentColor
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15.0)
            cell.textLabel?.text = i18n("Ayu.Market.VerifyNeeded", self.locale)
            cell.accessoryType = .disclosureIndicator
            return cell
        case let .submission(submission):
            let cell = tableView.dequeueReusableCell(withIdentifier: "text", for: indexPath)
            cell.backgroundColor = theme.list.itemBlocksBackgroundColor
            cell.accessoryType = .none
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15.0)
            let status: String
            switch submission.status {
            case "approved":
                status = "✅ " + i18n("Ayu.Market.Sub.Approved", self.locale)
            case "rejected":
                status = "❌ " + i18n("Ayu.Market.Sub.Rejected", self.locale) + (submission.reason.isEmpty ? "" : ": " + submission.reason)
            case "superseded":
                status = "♻️ " + i18n("Ayu.Market.Sub.Superseded", self.locale)
            default:
                status = "⏳ " + i18n("Ayu.Market.Sub.Pending", self.locale)
            }
            let text = NSMutableAttributedString(string: submission.name + " v" + submission.version + "\n", attributes: [.font: UIFont.systemFont(ofSize: 16.0, weight: .semibold), .foregroundColor: theme.list.itemPrimaryTextColor])
            text.append(NSAttributedString(string: status, attributes: [.font: UIFont.systemFont(ofSize: 14.0), .foregroundColor: theme.list.itemSecondaryTextColor]))
            cell.textLabel?.attributedText = text
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if self.segment.selectedSegmentIndex == 0 {
            self.push(AyuGramMarketDetailController(context: self.context, slug: self.plugins[indexPath.row].slug, preview: self.plugins[indexPath.row]))
            return
        }
        switch self.mineSections[indexPath.section][indexPath.row] {
        case let .plugin(plugin):
            if plugin.status == "live" {
                self.push(AyuGramMarketDetailController(context: self.context, slug: plugin.slug, preview: plugin))
            }
        case .verify:
            AyuGramProfileRelay.shared.startVerification(accountId: ayuMarketAccountId(self.context), completion: { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                case let .success(verification):
                    self.present(textAlertController(context: self.context, title: i18n("Ayu.ProfileExtras.Verify.Title", self.locale), text: i18n("Ayu.Market.VerifyCode", self.locale, verification.code), actions: [TextAlertAction(type: .defaultAction, title: i18n("Ayu.ProfileExtras.Verify.Action", self.locale), action: { [weak self] in
                        guard let self else {
                            return
                        }
                        self.mineLoaded = false
                        ayuGramOpenLink(context: self.context, url: verification.url.absoluteString)
                    })]), in: .window(.root))
                case .failure:
                    self.present(textAlertController(context: self.context, title: nil, text: i18n("Ayu.Market.Error.Server", self.locale), actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                }
            })
        case .submission:
            break
        }
    }

}

private final class AyuGramMarketDetailController: ViewController {
    private let context: AccountContext
    private let slug: String
    private var presentationData: PresentationData
    private var plugin: AyuGramMarketPlugin?
    private let scrollView = UIScrollView()
    private let gallery = UIScrollView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let metaLabel = UILabel()
    private let authorButton = UIButton(type: .system)
    private let installButton = UIButton(type: .system)
    private let installSpinner = UIActivityIndicatorView(style: .medium)
    private let shareButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let bodyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var galleryViews: [UIImageView] = []
    private var validLayout: ContainerViewLayout?
    private var observer: NSObjectProtocol?

    private var locale: String {
        return self.presentationData.strings.baseLanguageCode
    }

    init(context: AccountContext, slug: String, preview: AyuGramMarketPlugin?) {
        self.context = context
        self.slug = slug
        self.plugin = preview
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = preview?.name ?? i18n("Ayu.Market.Title", self.presentationData.strings.baseLanguageCode)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.observer = NotificationCenter.default.addObserver(forName: AyuGramPluginManager.didChange, object: nil, queue: .main, using: { [weak self] _ in
            self?.apply()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.plainBackgroundColor
        self.scrollView.alwaysBounceVertical = true
        self.gallery.showsHorizontalScrollIndicator = false
        self.gallery.clipsToBounds = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 26.0, weight: .bold)
        self.titleLabel.numberOfLines = 0
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.descriptionLabel.font = UIFont.systemFont(ofSize: 16.0)
        self.descriptionLabel.numberOfLines = 0
        self.descriptionLabel.textColor = theme.list.itemSecondaryTextColor
        self.metaLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.metaLabel.numberOfLines = 0
        self.metaLabel.textColor = theme.list.itemSecondaryTextColor
        self.authorButton.contentHorizontalAlignment = .leading
        self.authorButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.authorButton.tintColor = theme.list.itemAccentColor
        self.authorButton.addTarget(self, action: #selector(self.authorPressed), for: .touchUpInside)
        self.installButton.backgroundColor = theme.list.itemAccentColor
        self.installButton.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.installButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.installButton.layer.cornerRadius = 14.0
        self.installButton.layer.cornerCurve = .continuous
        self.installButton.addTarget(self, action: #selector(self.installPressed), for: .touchUpInside)
        self.installSpinner.color = theme.list.itemCheckColors.foregroundColor
        self.installSpinner.hidesWhenStopped = true
        self.installButton.addSubview(self.installSpinner)
        self.shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        self.shareButton.tintColor = theme.list.itemAccentColor
        self.shareButton.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.shareButton.layer.cornerRadius = 14.0
        self.shareButton.layer.cornerCurve = .continuous
        self.shareButton.addTarget(self, action: #selector(self.sharePressed), for: .touchUpInside)
        self.removeButton.setTitle(i18n("Ayu.Market.RemoveMine", self.locale), for: .normal)
        self.removeButton.tintColor = theme.list.itemDestructiveColor
        self.removeButton.addTarget(self, action: #selector(self.removePressed), for: .touchUpInside)
        self.bodyLabel.numberOfLines = 0
        self.spinner.color = theme.list.itemSecondaryTextColor
        self.displayNode.view.addSubview(self.scrollView)
        for view in [self.gallery, self.titleLabel, self.descriptionLabel, self.metaLabel, self.authorButton, self.installButton, self.shareButton, self.bodyLabel, self.removeButton] as [UIView] {
            self.scrollView.addSubview(view)
        }
        self.displayNode.view.addSubview(self.spinner)
        self.apply()
        if self.plugin == nil {
            self.spinner.startAnimating()
        }
        AyuGramMarketClient.shared.detail(slug: self.slug, completion: { [weak self] plugin in
            guard let self else {
                return
            }
            self.spinner.stopAnimating()
            if let plugin {
                self.plugin = plugin
                self.title = plugin.name
                self.apply()
            } else if self.plugin == nil {
                self.bodyLabel.attributedText = NSAttributedString(string: i18n("Ayu.Market.NotFound", self.locale), attributes: [.font: UIFont.systemFont(ofSize: 16.0), .foregroundColor: self.presentationData.theme.list.itemSecondaryTextColor])
                self.relayout()
            }
        })
    }

    private func apply() {
        guard self.isNodeLoaded, let plugin = self.plugin else {
            return
        }
        let theme = self.presentationData.theme
        self.titleLabel.text = plugin.name
        self.descriptionLabel.text = plugin.description
        self.metaLabel.text = ["v" + plugin.version, i18n("Ayu.Market.Downloads", self.locale, "\(plugin.downloads)"), plugin.fileSize > 0 ? ByteCountFormatter.string(fromByteCount: Int64(plugin.fileSize), countStyle: .file) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        self.authorButton.setTitle(i18n("Ayu.Market.Author", self.locale) + " " + plugin.authorTitle + (plugin.authorUsername.isEmpty || plugin.authorName.isEmpty ? "" : " · @" + plugin.authorUsername), for: .normal)
        let installed = AyuGramMarketInstalls.installed(slug: plugin.slug)
        if AyuGramMarketInstalls.hasUpdate(plugin) {
            self.installButton.setTitle(i18n("Ayu.Market.Update", self.locale, plugin.version), for: .normal)
            self.installButton.isEnabled = true
            self.installButton.alpha = 1.0
        } else if installed != nil {
            self.installButton.setTitle(i18n("Ayu.Market.Installed", self.locale), for: .normal)
            self.installButton.isEnabled = false
            self.installButton.alpha = 0.5
        } else {
            self.installButton.setTitle(i18n("Ayu.Market.Install", self.locale), for: .normal)
            self.installButton.isEnabled = true
            self.installButton.alpha = 1.0
        }
        self.removeButton.isHidden = plugin.authorId != ayuMarketAccountId(self.context)
        let body = NSMutableAttributedString()
        let heading: (String) -> Void = { text in
            body.append(NSAttributedString(string: (body.length > 0 ? "\n\n" : "") + text + "\n", attributes: [.font: UIFont.systemFont(ofSize: 17.0, weight: .semibold), .foregroundColor: theme.list.itemPrimaryTextColor]))
        }
        let paragraph: (String, UIColor) -> Void = { text, color in
            body.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15.0), .foregroundColor: color]))
        }
        if let scan = plugin.scan {
            heading(i18n("Ayu.Market.Check", self.locale))
            body.append(NSAttributedString(string: "● ", attributes: [.font: UIFont.systemFont(ofSize: 15.0), .foregroundColor: ayuMarketVerdictColor(scan.verdict)]))
            var lines = [ayuMarketVerdictText(scan.verdict, locale: self.locale)]
            for finding in scan.findings {
                lines.append((finding.level == "danger" ? "⛔ " : "⚠️ ") + finding.text)
            }
            if !scan.ai.isEmpty {
                lines.append("🤖 " + scan.ai)
            }
            paragraph(lines.joined(separator: "\n"), theme.list.itemPrimaryTextColor)
        }
        if !plugin.about.isEmpty {
            heading(i18n("Ayu.Market.About", self.locale))
            paragraph(plugin.about, theme.list.itemPrimaryTextColor)
        }
        if !plugin.changelog.isEmpty {
            heading(i18n("Ayu.Market.Changes", self.locale) + " · v" + plugin.version)
            paragraph(plugin.changelog, theme.list.itemPrimaryTextColor)
        }
        heading(i18n("Ayu.Plugins.Requests", self.locale))
        paragraph(plugin.permissions.isEmpty ? i18n("Ayu.Plugins.NoPermissions", self.locale) : plugin.permissions.map { "• " + i18n("Ayu.Plugins.Perm." + $0, self.locale) }.joined(separator: "\n"), theme.list.itemPrimaryTextColor)
        heading(i18n("Ayu.Plugins.Domains", self.locale))
        paragraph(plugin.domains.isEmpty ? "—" : plugin.domains.joined(separator: ", "), theme.list.itemSecondaryTextColor)
        if !plugin.sha256.isEmpty {
            paragraph("\n\nsha256 " + plugin.sha256, theme.list.itemSecondaryTextColor)
        }
        self.bodyLabel.attributedText = body
        if self.galleryViews.count != plugin.media.count {
            for view in self.galleryViews {
                view.removeFromSuperview()
            }
            self.galleryViews = plugin.media.enumerated().map { index, media in
                let view = UIImageView()
                view.contentMode = .scaleAspectFill
                view.clipsToBounds = true
                view.layer.cornerRadius = 14.0
                view.layer.cornerCurve = .continuous
                view.backgroundColor = theme.list.itemBlocksBackgroundColor
                view.isUserInteractionEnabled = true
                view.tag = index
                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.mediaTapped(_:))))
                if media.isVideo {
                    let play = UIImageView(image: UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44.0)))
                    play.tintColor = .white
                    play.tag = 99
                    view.addSubview(play)
                }
                AyuGramMarketImages.shared.load(media, completion: { [weak self, weak view] image in
                    view?.image = image
                    self?.relayout()
                })
                self.gallery.addSubview(view)
                return view
            }
        }
        self.relayout()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollView.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: layout.size.height - top)
        self.spinner.center = CGPoint(x: layout.size.width / 2.0, y: top + 120.0)
        self.relayout()
    }

    private func relayout() {
        guard let layout = self.validLayout else {
            return
        }
        let side = layout.safeInsets.left + 16.0
        let width = layout.size.width - side * 2.0
        var y: CGFloat = 16.0
        let mediaHeight: CGFloat = self.galleryViews.isEmpty ? 0.0 : min(380.0, max(220.0, layout.size.height * 0.42))
        if !self.galleryViews.isEmpty {
            self.gallery.frame = CGRect(x: 0.0, y: y, width: layout.size.width, height: mediaHeight)
            var x = side
            for view in self.galleryViews {
                let image = view.image
                let ratio = image.map { $0.size.width / max(1.0, $0.size.height) } ?? 0.5625
                let itemWidth = min(width, max(140.0, mediaHeight * ratio))
                view.frame = CGRect(x: x, y: 0.0, width: itemWidth, height: mediaHeight)
                if let play = view.viewWithTag(99) {
                    play.frame = CGRect(x: (itemWidth - 56.0) / 2.0, y: (mediaHeight - 56.0) / 2.0, width: 56.0, height: 56.0)
                }
                x += itemWidth + 10.0
            }
            self.gallery.contentSize = CGSize(width: x - 10.0 + side, height: mediaHeight)
            y += mediaHeight + 18.0
        } else {
            self.gallery.frame = .zero
        }
        let fit: (UILabel) -> CGFloat = { label in
            ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }
        let titleHeight = fit(self.titleLabel)
        self.titleLabel.frame = CGRect(x: side, y: y, width: width, height: titleHeight)
        y += titleHeight + 6.0
        let descriptionHeight = fit(self.descriptionLabel)
        self.descriptionLabel.frame = CGRect(x: side, y: y, width: width, height: descriptionHeight)
        y += descriptionHeight + 8.0
        let metaHeight = fit(self.metaLabel)
        self.metaLabel.frame = CGRect(x: side, y: y, width: width, height: metaHeight)
        y += metaHeight + 4.0
        self.authorButton.frame = CGRect(x: side, y: y, width: width, height: 32.0)
        y += 40.0
        self.shareButton.frame = CGRect(x: side + width - 50.0, y: y, width: 50.0, height: 50.0)
        self.installButton.frame = CGRect(x: side, y: y, width: width - 60.0, height: 50.0)
        self.installSpinner.center = CGPoint(x: self.installButton.bounds.midX, y: self.installButton.bounds.midY)
        y += 68.0
        let bodyHeight = fit(self.bodyLabel)
        self.bodyLabel.frame = CGRect(x: side, y: y, width: width, height: bodyHeight)
        y += bodyHeight + 20.0
        if !self.removeButton.isHidden {
            self.removeButton.frame = CGRect(x: side, y: y, width: width, height: 44.0)
            y += 52.0
        }
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: y + layout.intrinsicInsets.bottom + 20.0)
    }

    @objc private func mediaTapped(_ recognizer: UITapGestureRecognizer) {
        guard let plugin = self.plugin, let index = recognizer.view?.tag, index < plugin.media.count else {
            return
        }
        let media = plugin.media[index]
        if media.isVideo {
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: media.url)
            self.context.sharedContext.mainWindow?.presentNative(player)
            player.player?.play()
        } else if let image = (recognizer.view as? UIImageView)?.image {
            let viewer = UIViewController()
            viewer.view.backgroundColor = .black
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.frame = viewer.view.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.isUserInteractionEnabled = true
            viewer.view.addSubview(imageView)
            let close = UITapGestureRecognizer(target: viewer, action: #selector(UIViewController.ayuMarketDismissSelf))
            imageView.addGestureRecognizer(close)
            viewer.modalPresentationStyle = .fullScreen
            viewer.modalTransitionStyle = .crossDissolve
            self.context.sharedContext.mainWindow?.presentNative(viewer)
            AyuGramMarketImages.shared.load(AyuGramMarketMedia(url: media.url, isVideo: false), completion: { full in
                if let full {
                    imageView.image = full
                }
            })
        }
    }

    @objc private func authorPressed() {
        if let plugin = self.plugin {
            ayuMarketOpenAuthor(context: self.context, plugin: plugin)
        }
    }

    @objc private func sharePressed() {
        guard let plugin = self.plugin else {
            return
        }
        let link = URL(string: AyuGramMarketClient.site + "/p/" + plugin.slug) ?? plugin.pageURL
        guard let link else {
            return
        }
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = self.shareButton
            popover.sourceRect = self.shareButton.bounds
        }
        self.context.sharedContext.mainWindow?.presentNative(activity)
    }

    @objc private func installPressed() {
        guard let plugin = self.plugin else {
            return
        }
        self.installButton.isEnabled = false
        self.installButton.setTitle("", for: .normal)
        self.installSpinner.startAnimating()
        ayuGramMarketInstall(context: self.context, plugin: plugin, present: { [weak self] controller in
            self?.present(controller, in: .window(.root))
        }, finished: { [weak self] _ in
            self?.installSpinner.stopAnimating()
            self?.apply()
        })
    }

    @objc private func removePressed() {
        guard let plugin = self.plugin else {
            return
        }
        self.present(textAlertController(context: self.context, title: nil, text: i18n("Ayu.Market.RemoveConfirm", self.locale), actions: [
            TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: i18n("Ayu.Plugins.Delete", self.locale), action: { [weak self] in
                guard let self else {
                    return
                }
                AyuGramMarketClient.shared.remove(slug: plugin.slug, accountId: ayuMarketAccountId(self.context), completion: { [weak self] done in
                    guard let self else {
                        return
                    }
                    if done {
                        (self.navigationController as? NavigationController)?.popViewController(animated: true)
                    } else {
                        self.present(textAlertController(context: self.context, title: nil, text: i18n("Ayu.Market.Error.Server", self.locale), actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    }
                })
            })
        ]), in: .window(.root))
    }
}

extension UIViewController {
    @objc func ayuMarketDismissSelf() {
        self.dismiss(animated: true)
    }
}

private struct AyuGramMarketDraftMedia: Equatable {
    let id: String
    let data: Data
    let mime: String
    let isVideo: Bool

    static func == (lhs: AyuGramMarketDraftMedia, rhs: AyuGramMarketDraftMedia) -> Bool {
        return lhs.id == rhs.id
    }
}

private struct AyuGramMarketDraft: Equatable {
    var fileURL: URL?
    var info: AyuGramPluginInfo?
    var scan: AyuGramMarketScan?
    var scanning = false
    var name = ""
    var description = ""
    var about = ""
    var changelog = ""
    var media: [AyuGramMarketDraftMedia] = []
    var preparing = 0
    var busy = false
    var progress: Double = 0.0
    var authorName = ""
    var authorUsername = ""
}

private final class AyuGramMarketSubmitArguments {
    let pickFile: () -> Void
    let update: ((inout AyuGramMarketDraft) -> Void) -> Void
    let addMedia: () -> Void
    let removeMedia: (String) -> Void
    let submit: () -> Void

    init(pickFile: @escaping () -> Void, update: @escaping ((inout AyuGramMarketDraft) -> Void) -> Void, addMedia: @escaping () -> Void, removeMedia: @escaping (String) -> Void, submit: @escaping () -> Void) {
        self.pickFile = pickFile
        self.update = update
        self.addMedia = addMedia
        self.removeMedia = removeMedia
        self.submit = submit
    }
}

private enum AyuGramMarketSubmitEntry: ItemListNodeEntry {
    case header(Int, Int32, String)
    case pickFile(Int, String, String)
    case text(Int, Int32, String)
    case name(Int, String, String)
    case multiline(Int, Int32, String, String, Int, Int)
    case media(Int, String, String, String)
    case addMedia(Int, String, Bool)
    case submit(Int, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .text(_, section, _), let .multiline(_, section, _, _, _, _):
            return section
        case .pickFile:
            return 0
        case .name:
            return 1
        case .media, .addMedia:
            return 2
        case .submit:
            return 4
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _), let .pickFile(id, _, _), let .text(id, _, _), let .name(id, _, _), let .multiline(id, _, _, _, _, _), let .media(id, _, _, _), let .addMedia(id, _, _), let .submit(id, _, _):
            return id
        }
    }

    static func < (lhs: AyuGramMarketSubmitEntry, rhs: AyuGramMarketSubmitEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! AyuGramMarketSubmitArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .pickFile(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.pickFile()
            })
        case let .text(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .name(_, value, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: value, placeholder: placeholder, maxLength: 60, sectionId: self.section, textUpdated: { text in
                args.update { $0.name = text }
            }, action: {})
        case let .multiline(id, _, value, placeholder, limit, _):
            return ItemListMultilineInputItem(presentationData: presentationData, text: value, placeholder: placeholder, maxLength: ItemListMultilineInputItemTextLimit(value: limit, display: true), sectionId: self.section, style: .blocks, textUpdated: { text in
                args.update { draft in
                    switch id {
                    case 11:
                        draft.description = text
                    case 12:
                        draft.about = text
                    default:
                        draft.changelog = text
                    }
                }
            })
        case let .media(_, mediaId, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.removeMedia(mediaId)
            })
        case let .addMedia(_, title, enabled):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.addMedia()
            })
        case let .submit(_, title, enabled):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: enabled ? .generic : .disabled, alignment: .center, sectionId: self.section, style: .blocks, action: {
                args.submit()
            })
        }
    }
}

private func ayuMarketSubmitEntries(_ draft: AyuGramMarketDraft, locale: String) -> [AyuGramMarketSubmitEntry] {
    var entries: [AyuGramMarketSubmitEntry] = []
    entries.append(.header(0, 0, i18n("Ayu.Market.Form.File", locale)))
    if let info = draft.info {
        entries.append(.pickFile(1, info.name + " " + info.version, i18n("Ayu.Market.Form.Change", locale)))
        var lines = ["ID: " + info.id.lowercased()]
        lines.append(info.permissions.isEmpty ? i18n("Ayu.Plugins.NoPermissions", locale) : info.permissions.map { i18n("Ayu.Plugins.Perm." + $0, locale) }.joined(separator: ", "))
        if draft.scanning {
            lines.append(i18n("Ayu.Market.Form.Scanning", locale))
        } else if let scan = draft.scan {
            lines.append(ayuGramMarketScanText(scan, locale: locale))
        }
        entries.append(.text(2, 0, lines.joined(separator: "\n")))
    } else {
        entries.append(.pickFile(1, i18n("Ayu.Market.Form.PickFile", locale), ""))
        entries.append(.text(2, 0, i18n("Ayu.Market.Form.FileHint", locale)))
    }
    entries.append(.header(9, 1, i18n("Ayu.Market.Form.Info", locale)))
    entries.append(.name(10, draft.name, i18n("Ayu.Market.Form.Name", locale)))
    entries.append(.multiline(11, 1, draft.description, i18n("Ayu.Market.Form.Description", locale), 300, 0))
    entries.append(.multiline(12, 1, draft.about, i18n("Ayu.Market.Form.About", locale), 4000, 0))
    entries.append(.multiline(13, 1, draft.changelog, i18n("Ayu.Market.Form.Changelog", locale), 1000, 0))
    entries.append(.header(20, 2, i18n("Ayu.Market.Form.Media", locale)))
    for (index, item) in draft.media.enumerated() {
        let kind = i18n(item.isVideo ? "Ayu.Market.Form.Video" : "Ayu.Market.Form.Photo", locale)
        entries.append(.media(21 + index, item.id, kind + " \(index + 1) · " + ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file), i18n("Ayu.Market.Form.Remove", locale)))
    }
    if draft.preparing > 0 {
        entries.append(.text(29, 2, i18n("Ayu.Market.Form.Preparing", locale)))
    }
    entries.append(.addMedia(30, i18n("Ayu.Market.Form.AddMedia", locale), draft.media.count + draft.preparing < 4))
    entries.append(.text(31, 2, i18n("Ayu.Market.Form.MediaHint", locale)))
    entries.append(.header(39, 3, i18n("Ayu.Market.Form.Author", locale)))
    let author = draft.authorName + (draft.authorUsername.isEmpty ? "" : " · @" + draft.authorUsername)
    entries.append(.text(40, 3, i18n("Ayu.Market.Form.AuthorHint", locale, author)))
    let ready = draft.info != nil && !draft.busy && draft.preparing == 0 && draft.description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 && draft.scan?.verdict != "danger"
    let title = draft.busy ? i18n("Ayu.Market.Form.Sending", locale, "\(Int(draft.progress * 100.0))") : i18n("Ayu.Market.Form.Submit", locale)
    entries.append(.submit(50, title, ready))
    entries.append(.text(51, 4, i18n("Ayu.Market.Form.Rules", locale)))
    return entries
}

private final class AyuGramMarketMediaPicker: NSObject, PHPickerViewControllerDelegate {
    let picked: ([NSItemProvider]) -> Void
    var keepAlive: AyuGramMarketMediaPicker?

    init(picked: @escaping ([NSItemProvider]) -> Void) {
        self.picked = picked
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        self.picked(results.map { $0.itemProvider })
        self.keepAlive = nil
    }
}

private func ayuMarketPrepareMedia(_ provider: NSItemProvider, completion: @escaping (AyuGramMarketDraftMedia?) -> Void) {
    let finish: (AyuGramMarketDraftMedia?) -> Void = { value in
        DispatchQueue.main.async {
            completion(value)
        }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier, completionHandler: { url, _ in
            guard let url else {
                finish(nil)
                return
            }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension))
            guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else {
                finish(nil)
                return
            }
            let size = ((try? FileManager.default.attributesOfItem(atPath: copy.path))?[.size] as? NSNumber)?.intValue ?? Int.max
            let limit = 20 * 1024 * 1024
            if size <= limit, let data = try? Data(contentsOf: copy) {
                try? FileManager.default.removeItem(at: copy)
                finish(AyuGramMarketDraftMedia(id: UUID().uuidString, data: data, mime: copy.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime", isVideo: true))
                return
            }
            let presets = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540]
            func attempt(_ index: Int) {
                guard index < presets.count, let session = AVAssetExportSession(asset: AVURLAsset(url: copy), presetName: presets[index]) else {
                    try? FileManager.default.removeItem(at: copy)
                    finish(nil)
                    return
                }
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                session.outputURL = output
                session.outputFileType = .mp4
                session.shouldOptimizeForNetworkUse = true
                session.exportAsynchronously(completionHandler: {
                    let exported = ((try? FileManager.default.attributesOfItem(atPath: output.path))?[.size] as? NSNumber)?.intValue ?? Int.max
                    if session.status == .completed, exported <= limit, let data = try? Data(contentsOf: output) {
                        try? FileManager.default.removeItem(at: output)
                        try? FileManager.default.removeItem(at: copy)
                        finish(AyuGramMarketDraftMedia(id: UUID().uuidString, data: data, mime: "video/mp4", isVideo: true))
                    } else {
                        try? FileManager.default.removeItem(at: output)
                        attempt(index + 1)
                    }
                })
            }
            attempt(0)
        })
        return
    }
    guard provider.canLoadObject(ofClass: UIImage.self) else {
        finish(nil)
        return
    }
    provider.loadObject(ofClass: UIImage.self, completionHandler: { object, _ in
        guard let image = object as? UIImage else {
            finish(nil)
            return
        }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 2560.0 ? 2560.0 / longest : 1.0
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var quality: CGFloat = 0.85
        var data = rendered.jpegData(compressionQuality: quality)
        while let current = data, current.count > 5 * 1024 * 1024, quality > 0.35 {
            quality -= 0.15
            data = rendered.jpegData(compressionQuality: quality)
        }
        guard let data else {
            finish(nil)
            return
        }
        finish(AyuGramMarketDraftMedia(id: UUID().uuidString, data: data, mime: "image/jpeg", isVideo: false))
    })
}

func ayuGramMarketSubmitController(context: AccountContext, completed: @escaping () -> Void) -> ViewController {
    let statePromise = ValuePromise(AyuGramMarketDraft(), ignoreRepeated: true)
    let stateValue = Atomic(value: AyuGramMarketDraft())
    let updateState: ((inout AyuGramMarketDraft) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var next = current
            f(&next)
            return next
        })
    }
    var presentImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var pickFileImpl: (() -> Void)?
    var addMediaImpl: (() -> Void)?
    var submitImpl: (() -> Void)?
    let arguments = AyuGramMarketSubmitArguments(pickFile: {
        pickFileImpl?()
    }, update: { f in
        updateState(f)
    }, addMedia: {
        addMediaImpl?()
    }, removeMedia: { id in
        updateState { $0.media.removeAll(where: { $0.id == id }) }
    }, submit: {
        submitImpl?()
    })
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)) |> deliverOnMainQueue).startStandalone(next: { peer in
        guard let peer else {
            return
        }
        updateState { draft in
            draft.authorName = peer.compactDisplayTitle
            draft.authorUsername = peer.addressName ?? ""
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, draft -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let locale = presentationData.strings.baseLanguageCode
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Ayu.Market.Form.Title", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuMarketSubmitEntries(draft, locale: locale), style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    dismissImpl = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    let alert: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }
    pickFileImpl = {
        let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        var types: [UTType] = [.javaScript, .zip, .plainText]
        if let plugin = UTType(filenameExtension: "plugin") {
            types.append(plugin)
        }
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let delegate = AyuGramPluginPickerDelegate(picked: { url in
            guard let package = try? ayuGramReadPluginPackage(at: url) else {
                alert(i18n("Ayu.Plugins.BadFile", locale))
                return
            }
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            if size > 2 * 1024 * 1024 {
                alert(i18n("Ayu.Market.Error.file_too_large", locale))
                return
            }
            updateState { draft in
                draft.fileURL = url
                draft.info = package.info
                draft.scan = nil
                draft.scanning = true
                if draft.name.isEmpty {
                    draft.name = package.info.name
                }
                if draft.description.isEmpty {
                    draft.description = package.info.description
                }
            }
            if let data = try? Data(contentsOf: url) {
                AyuGramMarketClient.shared.scan(data: data, name: url.lastPathComponent, completion: { scan in
                    updateState { draft in
                        guard draft.fileURL == url else {
                            return
                        }
                        draft.scanning = false
                        draft.scan = scan
                    }
                })
            }
        })
        delegate.keepAlive = delegate
        picker.delegate = delegate
        context.sharedContext.mainWindow?.presentNative(picker)
    }
    addMediaImpl = {
        let current = stateValue.with { $0 }
        let remaining = 4 - current.media.count - current.preparing
        guard remaining > 0 else {
            return
        }
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = remaining
        configuration.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: configuration)
        let delegate = AyuGramMarketMediaPicker(picked: { providers in
            guard !providers.isEmpty else {
                return
            }
            updateState { $0.preparing += providers.count }
            for provider in providers {
                ayuMarketPrepareMedia(provider, completion: { media in
                    updateState { draft in
                        draft.preparing = max(0, draft.preparing - 1)
                        if let media, draft.media.count < 4 {
                            draft.media.append(media)
                        }
                    }
                    if media == nil {
                        let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
                        alert(i18n("Ayu.Market.Error.media_too_large", locale))
                    }
                })
            }
        })
        delegate.keepAlive = delegate
        picker.delegate = delegate
        context.sharedContext.mainWindow?.presentNative(picker)
    }
    submitImpl = {
        let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let draft = stateValue.with { $0 }
        guard let fileURL = draft.fileURL, !draft.busy else {
            return
        }
        updateState { draft in
            draft.busy = true
            draft.progress = 0.0
        }
        let meta: [String: Any] = [
            "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            "about": draft.about.trimmingCharacters(in: .whitespacesAndNewlines),
            "changelog": draft.changelog.trimmingCharacters(in: .whitespacesAndNewlines),
            "author": ["name": draft.authorName, "username": draft.authorUsername]
        ]
        let media = draft.media.enumerated().map { index, item in
            (item.data, item.mime, "media\(index)." + (item.mime == "image/jpeg" ? "jpg" : item.mime == "video/mp4" ? "mp4" : "mov"))
        }
        AyuGramMarketClient.shared.submit(accountId: ayuMarketAccountId(context), file: fileURL, meta: meta, media: media, progress: { value in
            updateState { $0.progress = value }
        }, completion: { status, object in
            updateState { $0.busy = false }
            if status == 200 {
                let submission = object["submission"] as? [String: Any]
                let rejected = (submission?["status"] as? String) == "rejected"
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentImpl?(textAlertController(context: context, title: nil, text: i18n(rejected ? "Ayu.Market.Form.AutoRejected" : "Ayu.Market.Form.Sent", locale), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
                    if !rejected {
                        dismissImpl?()
                        completed()
                    }
                })]))
                return
            }
            if (object["error"] as? String) == "unverified" {
                AyuGramProfileRelay.shared.startVerification(accountId: ayuMarketAccountId(context), completion: { result in
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    if case let .success(verification) = result {
                        presentImpl?(textAlertController(context: context, title: i18n("Ayu.ProfileExtras.Verify.Title", locale), text: i18n("Ayu.Market.VerifyCode", locale, verification.code), actions: [
                            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                            TextAlertAction(type: .defaultAction, title: i18n("Ayu.ProfileExtras.Verify.Action", locale), action: {
                                ayuGramOpenLink(context: context, url: verification.url.absoluteString)
                            })
                        ]))
                    } else {
                        alert(i18n("Ayu.Market.Error.unverified", locale))
                    }
                })
                return
            }
            alert(ayuMarketErrorText(status, object, locale: locale))
        })
    }
    return controller
}

public func ayuGramMarketController(context: AccountContext) -> ViewController {
    return AyuGramMarketListController(context: context)
}

public func ayuGramMarketPluginController(context: AccountContext, slug: String) -> ViewController {
    return AyuGramMarketDetailController(context: context, slug: slug.lowercased(), preview: nil)
}
