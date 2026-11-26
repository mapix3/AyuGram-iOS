import Foundation
import UIKit
import JavaScriptCore
import UserNotifications
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import UndoUI
import PromptUI
import ZipArchive
import SGSimpleSettings
import SGStrings

public let ayuGramPluginPermissions: [String] = ["messages.read", "messages.send", "messages.intercept", "account.basic", "ui.inject", "network.client", "notifications"]

public struct AyuGramPluginInfo: Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var author: String
    public var permissions: [String]
    public var domains: [String]
    public var enabled: Bool
    public var installedAt: Double
}

public struct AyuGramPluginMenuItem: Equatable {
    public let pluginId: String
    public let itemId: String
    public let title: String
    public let hookName: String
    public let locations: [String]
}

private let ayuGramPluginPrelude = """
(function(){
  var native = globalThis.__ayu;
  var handlers = {};
  var intercepts = {};
  var hooks = {};
  var pending = {};
  var seq = 0;
  var hid = 0;
  function call(m, a) {
    var r = native.call(m, JSON.stringify(a === undefined ? [] : a));
    if (r === undefined || r === null || r === "") { return undefined; }
    var o = JSON.parse(r);
    if (o.error) { throw new Error(o.error); }
    return o.value;
  }
  function callAsync(m, a) {
    return new Promise(function(resolve, reject) {
      var id = String(++seq);
      pending[id] = { resolve: resolve, reject: reject };
      native.callAsync(m, JSON.stringify(a === undefined ? [] : a), id);
    });
  }
  globalThis.__ayuResolve = function(id, json, err) {
    var p = pending[id];
    if (!p) { return; }
    delete pending[id];
    if (err) { p.reject(new Error(err)); } else { p.resolve(json ? JSON.parse(json).value : undefined); }
  };
  function match(pattern, name) {
    if (pattern === "*" || pattern === name) { return true; }
    if (pattern.slice(-2) === ".*") { return name.indexOf(pattern.slice(0, -1)) === 0; }
    if (pattern.slice(0, 2) === "*.") { return name.slice(-(pattern.length - 1)) === pattern.slice(1); }
    return false;
  }
  function report(e) {
    native.log("error", String(e && e.stack ? e.stack : e));
  }
  var events = {
    on: function(p, f) { var id = ++hid; (handlers[p] = handlers[p] || {})[id] = f; call("events.subscribe", [p]); return id; },
    once: function(p, f) { var id = events.on(p, function(e) { events.off(p, id); f(e); }); return id; },
    off: function(p, id) { if (!handlers[p]) { return; } if (id === undefined) { delete handlers[p]; } else { delete handlers[p][id]; } },
    emit: function(name, data) { call("events.emit", [String(name), data === undefined ? null : data]); }
  };
  globalThis.__ayuEmit = function(name, json) {
    var data = json ? JSON.parse(json) : {};
    for (var p in handlers) {
      if (!match(p, name)) { continue; }
      for (var id in handlers[p]) {
        try { var r = handlers[p][id](data); if (r && typeof r.catch === "function") { r.catch(report); } } catch (e) { report(e); }
      }
    }
  };
  var HookResult = {
    continue: function() { return { kind: "continue" }; },
    cancel: function(reason) { return { kind: "cancel", reason: reason || "" }; },
    modify: function(patch) { return { kind: "modify", patch: patch || {} }; },
    modifyFinal: function(patch) { return { kind: "modify", patch: patch || {}, final: true }; },
    replace: function(value) { return { kind: "modify", patch: value || {}, final: true }; }
  };
  function intercept(name, f, opts) {
    var list = intercepts[name] = intercepts[name] || [];
    list.push({ f: f, priority: (opts && opts.priority) || 0 });
    list.sort(function(a, b) { return b.priority - a.priority; });
    call("intercept.register", [String(name)]);
  }
  globalThis.__ayuIntercept = function(name, json) {
    var data = JSON.parse(json);
    var list = intercepts[name] || [];
    for (var i = 0; i < list.length; i++) {
      var r;
      try { r = list[i].f(data); } catch (e) { report(e); continue; }
      if (!r || r.kind === "continue") { continue; }
      if (r.kind === "cancel") { return JSON.stringify({ cancel: true, reason: r.reason || "" }); }
      if (r.kind === "modify") {
        var next = {};
        for (var k in data) { next[k] = data[k]; }
        for (var k2 in r.patch) { next[k2] = r.patch[k2]; }
        data = next;
        if (r.final) { break; }
      }
    }
    return JSON.stringify({ cancel: false, data: data });
  };
  globalThis.__ayuHook = function(name, json) {
    var f = hooks[name];
    if (!f) { return; }
    try { var r = f(json ? JSON.parse(json) : {}); if (r && typeof r.catch === "function") { r.catch(report); } } catch (e) { report(e); }
  };
  function line(args) {
    var out = [];
    for (var i = 0; i < args.length; i++) {
      var v = args[i];
      if (typeof v === "string") { out.push(v); } else { try { out.push(JSON.stringify(v)); } catch (e) { out.push(String(v)); } }
    }
    return out.join(" ");
  }
  globalThis.console = {
    log: function() { native.log("info", line(arguments)); },
    info: function() { native.log("info", line(arguments)); },
    warn: function() { native.log("warn", line(arguments)); },
    error: function() { native.log("error", line(arguments)); },
    debug: function() { native.log("debug", line(arguments)); }
  };
  var kv = {
    get: function(k) { return call("kv.get", [String(k)]); },
    set: function(k, v) { return call("kv.set", [String(k), v === undefined ? null : v]); },
    delete: function(k) { return call("kv.delete", [String(k)]); },
    keys: function(prefix) { return call("kv.keys", [prefix ? String(prefix) : ""]); },
    clear: function(prefix) { return call("kv.clear", [prefix ? String(prefix) : ""]); }
  };
  globalThis.wg = {
    version: "1.0",
    sdk: { version: function() { return "1.0"; }, host: function() { return "AyuGram"; }, pluginManifest: function() { return call("sdk.manifest", []); } },
    capabilities: { has: function(name) { return call("sdk.has", [String(name)]); } },
    events: events,
    intercept: intercept,
    HookResult: HookResult,
    on: function(name, f) { hooks[String(name)] = f; },
    kv: kv,
    storage: kv,
    messages: {
      send: function(peerId, text, opts) { return callAsync("messages.send", [String(peerId), String(text), opts || {}]); },
      getList: function(peerId, opts) { return callAsync("messages.getList", [String(peerId), opts || {}]); },
      currentChat: function() { return call("messages.currentChat", []); },
      openChat: function(peerId) { return call("messages.openChat", [String(peerId)]); }
    },
    accounts: { getMe: function() { return callAsync("accounts.getMe", []); } },
    tg: { myId: function() { return call("accounts.myId", []); } },
    menu: {
      addItem: function(item) { return call("menu.addItem", [item || {}]); },
      removeItem: function(id) { return call("menu.removeItem", [String(id)]); }
    },
    ui: {
      toast: function(text) { return call("ui.toast", [String(text)]); },
      alert: function(title, text) { return callAsync("ui.alert", [String(title || ""), String(text || "")]); },
      confirm: function(text) { return callAsync("ui.confirm", [String(text || "")]); },
      prompt: function(title, opts) { return callAsync("ui.prompt", [String(title || ""), opts || {}]); }
    },
    net: { fetch: function(url, opts) { return callAsync("net.fetch", [String(url), opts || {}]); } },
    notifications: { show: function(opts) { return callAsync("notifications.show", [opts || {}]); } },
    system: {
      clipboardGet: function() { return call("system.clipboardGet", []); },
      clipboardSet: function(text) { return call("system.clipboardSet", [String(text)]); },
      openURL: function(url) { return call("system.openURL", [String(url)]); },
      haptic: function(kind) { return call("system.haptic", [String(kind || "light")]); }
    },
    log: { write: function(level, tag, text) { native.log(String(level || "info"), "[" + String(tag || "") + "] " + String(text || "")); } }
  };
})();
"""

private func ayuGramPluginJSON(_ value: Any?) -> String {
    let wrapped: [String: Any] = ["value": value ?? NSNull()]
    guard JSONSerialization.isValidJSONObject(wrapped), let data = try? JSONSerialization.data(withJSONObject: wrapped, options: [.fragmentsAllowed]) else {
        return "{\"value\":null}"
    }
    return String(decoding: data, as: UTF8.self)
}

private func ayuGramPluginError(_ text: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: ["error": text]) else {
        return "{\"error\":\"error\"}"
    }
    return String(decoding: data, as: UTF8.self)
}

private func ayuGramPluginParseArgs(_ json: String) -> [Any] {
    guard let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] else {
        return []
    }
    return value
}

private func ayuGramPluginEncode(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else {
        return "{}"
    }
    return String(decoding: data, as: UTF8.self)
}

private func ayuGramPluginPeerId(_ value: Any?) -> EnginePeer.Id? {
    if let text = value as? String, let raw = Int64(text) {
        return EnginePeer.Id(raw)
    }
    if let number = value as? NSNumber {
        return EnginePeer.Id(number.int64Value)
    }
    return nil
}

final class AyuGramPluginRuntime {
    let info: AyuGramPluginInfo
    let directory: URL
    let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()
    private var context: JSContext?
    private var interceptNames = Set<String>()
    private let interceptLock = NSLock()
    var intercepts: Set<String> {
        self.interceptLock.lock()
        defer {
            self.interceptLock.unlock()
        }
        return self.interceptNames
    }
    private(set) var subscriptions = Set<String>()
    private var kvStore: [String: Any] = [:]
    weak var manager: AyuGramPluginManager?

    init(info: AyuGramPluginInfo, directory: URL, manager: AyuGramPluginManager) {
        self.info = info
        self.directory = directory
        self.manager = manager
        self.queue = DispatchQueue(label: "ayugram.plugin." + info.id, qos: .userInitiated)
        self.queue.setSpecific(key: self.queueKey, value: true)
    }

    var isCurrentQueue: Bool {
        return DispatchQueue.getSpecific(key: self.queueKey) == true
    }

    func has(_ permission: String) -> Bool {
        return self.info.permissions.contains(permission)
    }

    func start(source: String) {
        self.queue.async {
            self.loadStore()
            let context: JSContext = JSContext()
            context.name = self.info.name
            context.exceptionHandler = { [weak self] _, exception in
                self?.manager?.appendLog(pluginId: self?.info.id ?? "", level: "error", text: exception?.toString() ?? "exception")
            }
            let native = JSValue(newObjectIn: context)
            let callBlock: @convention(block) (String, String) -> String = { [weak self] method, args in
                guard let self else {
                    return ayuGramPluginError("unloaded")
                }
                return self.callSync(method: method, args: ayuGramPluginParseArgs(args))
            }
            let asyncBlock: @convention(block) (String, String, String) -> Void = { [weak self] method, args, callbackId in
                self?.callAsync(method: method, args: ayuGramPluginParseArgs(args), callbackId: callbackId)
            }
            let logBlock: @convention(block) (String, String) -> Void = { [weak self] level, text in
                guard let self else {
                    return
                }
                self.manager?.appendLog(pluginId: self.info.id, level: level, text: text)
            }
            native?.setObject(callBlock, forKeyedSubscript: "call" as NSString)
            native?.setObject(asyncBlock, forKeyedSubscript: "callAsync" as NSString)
            native?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
            context.setObject(native, forKeyedSubscript: "__ayu" as NSString)
            context.evaluateScript(ayuGramPluginPrelude)
            self.context = context
            context.evaluateScript(source, withSourceURL: self.directory.appendingPathComponent("main.js"))
        }
    }

    func stop() {
        self.queue.async {
            self.context = nil
            self.interceptLock.lock()
            self.interceptNames.removeAll()
            self.interceptLock.unlock()
            self.subscriptions.removeAll()
        }
    }

    func emit(name: String, payload: [String: Any]) {
        let json = ayuGramPluginEncode(payload)
        self.queue.async {
            guard let context = self.context, self.subscriptions.contains(where: { ayuGramPluginPatternMatches($0, name) }) else {
                return
            }
            context.objectForKeyedSubscript("__ayuEmit")?.call(withArguments: [name, json])
        }
    }

    func hook(name: String, payload: [String: Any]) {
        let json = ayuGramPluginEncode(payload)
        self.queue.async {
            self.context?.objectForKeyedSubscript("__ayuHook")?.call(withArguments: [name, json])
        }
    }

    func interceptSync(name: String, payload: [String: Any], timeout: Double) -> [String: Any]? {
        guard self.intercepts.contains(name), !self.isCurrentQueue else {
            return nil
        }
        let json = ayuGramPluginEncode(payload)
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        self.queue.async {
            result = self.context?.objectForKeyedSubscript("__ayuIntercept")?.call(withArguments: [name, json])?.toString()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            self.manager?.appendLog(pluginId: self.info.id, level: "warn", text: name + " took too long and was skipped")
            return nil
        }
        guard let result, let data = result.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func resolve(_ callbackId: String, value: Any?, error: String?) {
        let json = error == nil ? ayuGramPluginJSON(value) : ""
        self.queue.async {
            self.context?.objectForKeyedSubscript("__ayuResolve")?.call(withArguments: [callbackId, json, error ?? ""])
        }
    }

    private var storeURL: URL {
        return self.directory.appendingPathComponent("kv.json")
    }

    private func loadStore() {
        guard let data = try? Data(contentsOf: self.storeURL), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        self.kvStore = object
    }

    private func saveStore() {
        guard JSONSerialization.isValidJSONObject(self.kvStore), let data = try? JSONSerialization.data(withJSONObject: self.kvStore) else {
            return
        }
        try? data.write(to: self.storeURL, options: .atomic)
    }

    private func requirement(_ method: String) -> String? {
        switch method {
        case "messages.getList", "messages.currentChat":
            return "messages.read"
        case "messages.send":
            return "messages.send"
        case "intercept.register":
            return "messages.intercept"
        case "accounts.getMe", "accounts.myId":
            return "account.basic"
        case "menu.addItem", "menu.removeItem":
            return "ui.inject"
        case "net.fetch":
            return "network.client"
        case "notifications.show":
            return "notifications"
        default:
            return nil
        }
    }

    private func callSync(method: String, args: [Any]) -> String {
        if let permission = self.requirement(method), !self.has(permission) {
            return ayuGramPluginError("permission " + permission + " is not granted")
        }
        switch method {
        case "sdk.manifest":
            return ayuGramPluginJSON(["id": self.info.id, "name": self.info.name, "version": self.info.version, "author": self.info.author, "permissions": self.info.permissions, "domains": self.info.domains])
        case "sdk.has":
            let name = args.first as? String ?? ""
            let known = ["events", "intercept", "kv", "messages.send", "messages.getList", "menu", "ui.toast", "ui.alert", "ui.confirm", "ui.prompt", "net.fetch", "notifications", "accounts.getMe"]
            return ayuGramPluginJSON(known.contains(where: { name == $0 || name.hasPrefix($0) }))
        case "events.subscribe":
            if let pattern = args.first as? String {
                if (pattern.hasPrefix("message.") || pattern == "*") && !self.has("messages.read") {
                    return ayuGramPluginError("permission messages.read is not granted")
                }
                self.subscriptions.insert(pattern)
            }
            return ayuGramPluginJSON(true)
        case "events.emit":
            if let name = args.first as? String {
                let payload = args.count > 1 ? args[1] : NSNull()
                self.manager?.broadcast(name: "plugin." + self.info.id + "." + name, payload: ["data": payload])
            }
            return ayuGramPluginJSON(true)
        case "intercept.register":
            if let name = args.first as? String {
                self.interceptLock.lock()
                self.interceptNames.insert(name)
                self.interceptLock.unlock()
            }
            return ayuGramPluginJSON(true)
        case "kv.get":
            return ayuGramPluginJSON(self.kvStore[args.first as? String ?? ""])
        case "kv.set":
            guard let key = args.first as? String else {
                return ayuGramPluginError("bad key")
            }
            if args.count > 1, !(args[1] is NSNull) {
                self.kvStore[key] = args[1]
            } else {
                self.kvStore.removeValue(forKey: key)
            }
            self.saveStore()
            return ayuGramPluginJSON(true)
        case "kv.delete":
            self.kvStore.removeValue(forKey: args.first as? String ?? "")
            self.saveStore()
            return ayuGramPluginJSON(true)
        case "kv.keys":
            let prefix = args.first as? String ?? ""
            return ayuGramPluginJSON(self.kvStore.keys.filter { prefix.isEmpty || $0.hasPrefix(prefix) }.sorted())
        case "kv.clear":
            let prefix = args.first as? String ?? ""
            for key in self.kvStore.keys where prefix.isEmpty || key.hasPrefix(prefix) {
                self.kvStore.removeValue(forKey: key)
            }
            self.saveStore()
            return ayuGramPluginJSON(true)
        case "messages.currentChat":
            return ayuGramPluginJSON(self.manager?.currentChat.map { String($0.toInt64()) })
        case "messages.openChat":
            guard let peerId = ayuGramPluginPeerId(args.first) else {
                return ayuGramPluginError("bad peer id")
            }
            DispatchQueue.main.async {
                self.manager?.openChat(peerId: peerId)
            }
            return ayuGramPluginJSON(true)
        case "accounts.myId":
            return ayuGramPluginJSON(self.manager?.accountPeerId.map { String($0.toInt64()) })
        case "menu.addItem":
            guard let item = args.first as? [String: Any], let id = item["id"] as? String, let title = item["title"] as? String else {
                return ayuGramPluginError("menu item needs id and title")
            }
            let hookName = item["hookName"] as? String ?? id
            let locations = item["locations"] as? [String] ?? ["message"]
            self.manager?.setMenuItem(AyuGramPluginMenuItem(pluginId: self.info.id, itemId: id, title: String(title.prefix(60)), hookName: hookName, locations: locations))
            return ayuGramPluginJSON(true)
        case "menu.removeItem":
            self.manager?.removeMenuItem(pluginId: self.info.id, itemId: args.first as? String ?? "")
            return ayuGramPluginJSON(true)
        case "ui.toast":
            let text = String((args.first as? String ?? "").prefix(300))
            DispatchQueue.main.async {
                self.manager?.toast(text)
            }
            return ayuGramPluginJSON(true)
        case "system.clipboardGet":
            var text: String?
            DispatchQueue.main.sync {
                text = UIPasteboard.general.string
            }
            return ayuGramPluginJSON(text)
        case "system.clipboardSet":
            let text = args.first as? String ?? ""
            DispatchQueue.main.async {
                UIPasteboard.general.string = text
            }
            return ayuGramPluginJSON(true)
        case "system.openURL":
            if let text = args.first as? String, let url = URL(string: text), ["http", "https", "tg"].contains(url.scheme?.lowercased() ?? "") {
                DispatchQueue.main.async {
                    self.manager?.openURL(url)
                }
                return ayuGramPluginJSON(true)
            }
            return ayuGramPluginError("only http, https and tg links can be opened")
        case "system.haptic":
            let kind = args.first as? String ?? "light"
            DispatchQueue.main.async {
                switch kind {
                case "success":
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case "warning":
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case "error":
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                case "selection":
                    UISelectionFeedbackGenerator().selectionChanged()
                case "heavy":
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                case "medium":
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                default:
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            return ayuGramPluginJSON(true)
        default:
            return ayuGramPluginError("unknown method " + method)
        }
    }

    private func callAsync(method: String, args: [Any], callbackId: String) {
        if let permission = self.requirement(method), !self.has(permission) {
            self.resolve(callbackId, value: nil, error: "permission " + permission + " is not granted")
            return
        }
        guard let manager = self.manager else {
            self.resolve(callbackId, value: nil, error: "unloaded")
            return
        }
        switch method {
        case "messages.send":
            guard let peerId = ayuGramPluginPeerId(args.first), let text = args.count > 1 ? args[1] as? String : nil, !text.isEmpty else {
                self.resolve(callbackId, value: nil, error: "bad arguments")
                return
            }
            let options = args.count > 2 ? args[2] as? [String: Any] : nil
            manager.send(peerId: peerId, text: String(text.prefix(4096)), silent: options?["silent"] as? Bool ?? false, completion: { [weak self] id in
                self?.resolve(callbackId, value: id.map { ["peerId": String(peerId.toInt64()), "id": $0] }, error: id == nil ? "not sent" : nil)
            })
        case "messages.getList":
            guard let peerId = ayuGramPluginPeerId(args.first) else {
                self.resolve(callbackId, value: nil, error: "bad peer id")
                return
            }
            let options = args.count > 1 ? args[1] as? [String: Any] : nil
            let limit = max(1, min(200, (options?["limit"] as? NSNumber)?.intValue ?? 50))
            manager.messages(peerId: peerId, limit: limit, completion: { [weak self] list in
                self?.resolve(callbackId, value: list, error: nil)
            })
        case "accounts.getMe":
            manager.me(completion: { [weak self] me in
                self?.resolve(callbackId, value: me, error: me == nil ? "no account" : nil)
            })
        case "ui.alert":
            let title = args.first as? String ?? ""
            let text = args.count > 1 ? args[1] as? String ?? "" : ""
            DispatchQueue.main.async {
                manager.alert(title: self.info.name + (title.isEmpty ? "" : " · " + title), text: text, confirm: false, completion: { [weak self] _ in
                    self?.resolve(callbackId, value: true, error: nil)
                })
            }
        case "ui.confirm":
            let text = args.first as? String ?? ""
            DispatchQueue.main.async {
                manager.alert(title: self.info.name, text: text, confirm: true, completion: { [weak self] value in
                    self?.resolve(callbackId, value: value, error: nil)
                })
            }
        case "ui.prompt":
            let title = args.first as? String ?? ""
            let options = args.count > 1 ? args[1] as? [String: Any] : nil
            DispatchQueue.main.async {
                manager.prompt(title: self.info.name + (title.isEmpty ? "" : " · " + title), value: options?["value"] as? String, placeholder: options?["placeholder"] as? String, completion: { [weak self] value in
                    self?.resolve(callbackId, value: value, error: nil)
                })
            }
        case "net.fetch":
            guard let text = args.first as? String, let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), ayuGramPluginDomainAllowed(host: host, domains: self.info.domains) else {
                self.resolve(callbackId, value: nil, error: "this address is not in the plugin domains")
                return
            }
            let options = args.count > 1 ? args[1] as? [String: Any] ?? [:] : [:]
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: min(60.0, (options["timeout"] as? NSNumber)?.doubleValue ?? 30.0))
            request.httpMethod = (options["method"] as? String)?.uppercased() ?? "GET"
            if let headers = options["headers"] as? [String: Any] {
                for (key, value) in headers {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
            if let body = options["body"] {
                if let string = body as? String {
                    request.httpBody = string.data(using: .utf8)
                } else if JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) {
                    request.httpBody = data
                    if request.value(forHTTPHeaderField: "Content-Type") == nil {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
            }
            URLSession.shared.dataTask(with: request, completionHandler: { [weak self] data, response, error in
                guard let self else {
                    return
                }
                if let error {
                    self.resolve(callbackId, value: nil, error: error.localizedDescription)
                    return
                }
                let http = response as? HTTPURLResponse
                var headers: [String: String] = [:]
                for (key, value) in http?.allHeaderFields ?? [:] {
                    headers["\(key)".lowercased()] = "\(value)"
                }
                let body = data.flatMap { String(data: $0.prefix(4 * 1024 * 1024), encoding: .utf8) } ?? ""
                self.resolve(callbackId, value: ["status": http?.statusCode ?? 0, "headers": headers, "body": body], error: nil)
            }).resume()
        case "notifications.show":
            let options = args.first as? [String: Any] ?? [:]
            let content = UNMutableNotificationContent()
            content.title = String((options["title"] as? String ?? self.info.name).prefix(120))
            content.body = String((options["body"] as? String ?? "").prefix(600))
            if options["sound"] as? Bool ?? true {
                content.sound = .default
            }
            let delay = max(1.0, (options["delay"] as? NSNumber)?.doubleValue ?? 1.0)
            let identifier = "ayugram.plugin." + self.info.id + "." + UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { [weak self] error in
                self?.resolve(callbackId, value: error == nil ? identifier : nil, error: error?.localizedDescription)
            })
        default:
            self.resolve(callbackId, value: nil, error: "unknown method " + method)
        }
    }
}

func ayuGramPluginPatternMatches(_ pattern: String, _ name: String) -> Bool {
    if pattern == "*" || pattern == name {
        return true
    }
    if pattern.hasSuffix(".*") {
        return name.hasPrefix(String(pattern.dropLast()))
    }
    if pattern.hasPrefix("*.") {
        return name.hasSuffix(String(pattern.dropFirst()))
    }
    return false
}

func ayuGramPluginDomainAllowed(host: String, domains: [String]) -> Bool {
    for domain in domains {
        let rule = domain.lowercased()
        if rule.hasPrefix("*.") {
            let base = String(rule.dropFirst(2))
            if host == base || host.hasSuffix("." + base) {
                return true
            }
        } else if host == rule {
            return true
        }
    }
    return false
}

public struct AyuGramPluginPackage {
    public let info: AyuGramPluginInfo
    public let source: String
    public let files: URL?
}

public enum AyuGramPluginParseError: Error {
    case notPlugin
    case noSource
}

public func ayuGramParsePluginSource(_ source: String, fallbackName: String) -> AyuGramPluginInfo {
    var fields: [String: String] = [:]
    for raw in source.components(separatedBy: .newlines).prefix(60) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("//") else {
            if line.isEmpty || line.hasPrefix("/*") || line.hasPrefix("*") {
                continue
            }
            break
        }
        let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("@") else {
            continue
        }
        let parts = body.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            fields[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
    let name = fields["name"] ?? fallbackName
    let split: (String?) -> [String] = { value in
        return (value ?? "").components(separatedBy: CharacterSet(charactersIn: ", ")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    let rawId = fields["id"] ?? name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    let id = String((rawId.isEmpty ? UUID().uuidString : rawId).filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }.prefix(80))
    return AyuGramPluginInfo(id: id.isEmpty ? UUID().uuidString : id, name: String(name.prefix(60)), version: fields["version"] ?? "1.0", description: String((fields["description"] ?? "").prefix(300)), author: fields["author"] ?? "", permissions: split(fields["permissions"]).filter { ayuGramPluginPermissions.contains($0) }, domains: split(fields["domains"]).filter { $0.contains(".") }, enabled: true, installedAt: Date().timeIntervalSince1970)
}

public func ayuGramReadPluginPackage(at url: URL) throws -> AyuGramPluginPackage {
    let lower = url.pathExtension.lowercased()
    if lower == "js" || lower == "txt" {
        guard let source = try? String(contentsOf: url, encoding: .utf8), !source.isEmpty else {
            throw AyuGramPluginParseError.noSource
        }
        return AyuGramPluginPackage(info: ayuGramParsePluginSource(source, fallbackName: url.deletingPathExtension().lastPathComponent), source: source, files: nil)
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ayugram-plugin-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    guard SSZipArchive.unzipFile(atPath: url.path, toDestination: temporary.path) else {
        throw AyuGramPluginParseError.notPlugin
    }
    var root = temporary
    if !FileManager.default.fileExists(atPath: root.appendingPathComponent("plugin.json").path), let items = try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil), items.count == 1 {
        root = items[0]
    }
    var manifest: [String: Any] = [:]
    if let data = try? Data(contentsOf: root.appendingPathComponent("plugin.json")), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        manifest = object
    }
    let entry = (manifest["main"] as? String) ?? ((manifest["entryPoints"] as? [String: Any])?["main"] as? String) ?? "main.js"
    guard !entry.contains(".."), let source = try? String(contentsOf: root.appendingPathComponent(entry), encoding: .utf8) else {
        throw AyuGramPluginParseError.noSource
    }
    var info = ayuGramParsePluginSource(source, fallbackName: url.deletingPathExtension().lastPathComponent)
    if let id = manifest["id"] as? String, !id.isEmpty {
        info.id = String(id.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }.prefix(80))
    }
    if let name = manifest["name"] as? String {
        info.name = String(name.prefix(60))
    }
    if let version = manifest["version"] as? String {
        info.version = version
    }
    if let description = manifest["description"] as? String {
        info.description = String(description.prefix(300))
    }
    if let author = manifest["author"] as? String {
        info.author = author
    }
    if let permissions = manifest["permissions"] as? [Any] {
        info.permissions = permissions.compactMap { item -> String? in
            if let text = item as? String {
                return text
            }
            return (item as? [String: Any])?["id"] as? String
        }.filter { ayuGramPluginPermissions.contains($0) }
    }
    if let domains = manifest["domains"] as? [String] {
        info.domains = domains.filter { $0.contains(".") }
    }
    return AyuGramPluginPackage(info: info, source: source, files: root)
}

public final class AyuGramPluginManager {
    public static let shared = AyuGramPluginManager()
    public static let didChange = Notification.Name("AyuGramPluginsDidChange")

    private weak var context: AccountContext?
    private var runtimes: [String: AyuGramPluginRuntime] = [:]
    public private(set) var plugins: [AyuGramPluginInfo] = []
    private var menuItems: [AyuGramPluginMenuItem] = []
    private var logs: [String: [String]] = [:]
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []
    private let incomingDisposable = MetaDisposable()
    private(set) var currentChat: EnginePeer.Id?
    private var started = false

    var accountPeerId: EnginePeer.Id? {
        return self.context?.account.peerId
    }

    static var baseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ayugram-plugins", isDirectory: true)
    }

    private static var indexURL: URL {
        return baseDirectory.appendingPathComponent("plugins.json")
    }

    private init() {
        if let data = try? Data(contentsOf: AyuGramPluginManager.indexURL), let list = try? JSONDecoder().decode([AyuGramPluginInfo].self, from: data) {
            self.plugins = list
        }
    }

    public func start(context: AccountContext) {
        self.context = context
        if !self.started {
            self.started = true
            self.observers = [
                NotificationCenter.default.addObserver(forName: Notification.Name("AyuGramChatOpened"), object: nil, queue: .main, using: { [weak self] notification in
                    guard let self, let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id else {
                        return
                    }
                    self.currentChat = peerId
                    self.broadcast(name: "chat.didOpen", payload: ["peerId": String(peerId.toInt64())])
                }),
                NotificationCenter.default.addObserver(forName: Notification.Name("AyuGramChatClosed"), object: nil, queue: .main, using: { [weak self] notification in
                    guard let self, let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id else {
                        return
                    }
                    if self.currentChat == peerId {
                        self.currentChat = nil
                    }
                    self.broadcast(name: "chat.didClose", payload: ["peerId": String(peerId.toInt64())])
                }),
                NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
                    self?.broadcast(name: "app.foreground", payload: [:])
                }),
                NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
                    self?.broadcast(name: "app.background", payload: [:])
                })
            ]
            AyuGramPluginHooks.beforeSend = { [weak self] peerId, text in
                return self?.beforeSend(peerId: peerId, text: text) ?? .keep
            }
            AyuGramPluginHooks.didSend = { [weak self] peerId, text in
                self?.broadcast(name: "message.sent", payload: ["peerId": String(peerId), "text": text])
            }
        }
        let accountPeerId = context.account.peerId
        self.incomingDisposable.set((context.account.stateManager.notificationMessages
        |> deliverOnMainQueue).startStrict(next: { [weak self] list in
            guard let self else {
                return
            }
            for (messages, _, _, _) in list {
                for message in messages where message.flags.contains(.Incoming) && message.author?.id != accountPeerId {
                    self.broadcast(name: "message.received", payload: ["peerId": String(message.id.peerId.toInt64()), "id": Int(message.id.id), "text": message.text, "date": Int(message.timestamp), "authorId": message.author.map { String($0.id.toInt64()) } ?? ""])
                }
            }
        }))
        for plugin in self.plugins where plugin.enabled && self.runtimes[plugin.id] == nil {
            self.launch(plugin)
        }
    }

    private func pluginDirectory(_ id: String) -> URL {
        return AyuGramPluginManager.baseDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private func launch(_ plugin: AyuGramPluginInfo) {
        let directory = self.pluginDirectory(plugin.id)
        guard let source = try? String(contentsOf: directory.appendingPathComponent("main.js"), encoding: .utf8) else {
            self.appendLog(pluginId: plugin.id, level: "error", text: "main.js is missing")
            return
        }
        let runtime = AyuGramPluginRuntime(info: plugin, directory: directory, manager: self)
        self.lock.lock()
        self.runtimes[plugin.id] = runtime
        self.lock.unlock()
        runtime.start(source: source)
    }

    private func saveIndex() {
        try? FileManager.default.createDirectory(at: AyuGramPluginManager.baseDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self.plugins) {
            try? data.write(to: AyuGramPluginManager.indexURL, options: .atomic)
        }
        NotificationCenter.default.post(name: AyuGramPluginManager.didChange, object: nil)
    }

    public func install(_ package: AyuGramPluginPackage) {
        let directory = self.pluginDirectory(package.info.id)
        self.stopRuntime(package.info.id)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let files = package.files, let items = try? FileManager.default.contentsOfDirectory(at: files, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.copyItem(at: item, to: directory.appendingPathComponent(item.lastPathComponent))
            }
        }
        try? package.source.write(to: directory.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        var info = package.info
        info.enabled = true
        info.installedAt = Date().timeIntervalSince1970
        self.plugins.removeAll(where: { $0.id == info.id })
        self.plugins.append(info)
        self.saveIndex()
        if self.context != nil {
            self.launch(info)
        }
    }

    private func stopRuntime(_ id: String) {
        self.lock.lock()
        let runtime = self.runtimes.removeValue(forKey: id)
        self.lock.unlock()
        runtime?.stop()
        self.menuItems.removeAll(where: { $0.pluginId == id })
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        guard let index = self.plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        self.plugins[index].enabled = enabled
        self.saveIndex()
        if enabled {
            if self.runtimes[id] == nil, self.context != nil {
                self.launch(self.plugins[index])
            }
        } else {
            self.stopRuntime(id)
        }
    }

    public func reload(_ id: String) {
        guard let plugin = self.plugins.first(where: { $0.id == id }), plugin.enabled else {
            return
        }
        self.stopRuntime(id)
        self.launch(plugin)
    }

    public func remove(_ id: String) {
        self.stopRuntime(id)
        self.plugins.removeAll(where: { $0.id == id })
        try? FileManager.default.removeItem(at: self.pluginDirectory(id))
        self.lock.lock()
        self.logs.removeValue(forKey: id)
        self.lock.unlock()
        self.saveIndex()
    }

    func appendLog(pluginId: String, level: String, text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = formatter.string(from: Date()) + " " + level.uppercased() + " " + String(text.prefix(2000))
        self.lock.lock()
        var list = self.logs[pluginId] ?? []
        list.append(line)
        if list.count > 200 {
            list.removeFirst(list.count - 200)
        }
        self.logs[pluginId] = list
        self.lock.unlock()
    }

    public func log(_ id: String) -> [String] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.logs[id] ?? []
    }

    func broadcast(name: String, payload: [String: Any]) {
        self.lock.lock()
        let runtimes = Array(self.runtimes.values)
        self.lock.unlock()
        for runtime in runtimes {
            if name.hasPrefix("message.") && !runtime.has("messages.read") {
                continue
            }
            runtime.emit(name: name, payload: payload)
        }
    }

    private func beforeSend(peerId: Int64, text: String) -> AyuGramPluginSendDecision {
        self.lock.lock()
        let runtimes = Array(self.runtimes.values)
        self.lock.unlock()
        var current = text
        for runtime in runtimes where runtime.has("messages.intercept") && runtime.intercepts.contains("message.beforeSend") {
            guard let result = runtime.interceptSync(name: "message.beforeSend", payload: ["peerId": String(peerId), "text": current], timeout: 0.8) else {
                continue
            }
            if result["cancel"] as? Bool == true {
                return .cancel
            }
            if let data = result["data"] as? [String: Any], let updated = data["text"] as? String {
                current = String(updated.prefix(4096))
            }
        }
        return current == text ? .keep : .replace(current)
    }

    func setMenuItem(_ item: AyuGramPluginMenuItem) {
        DispatchQueue.main.async {
            self.menuItems.removeAll(where: { $0.pluginId == item.pluginId && $0.itemId == item.itemId })
            if self.menuItems.filter({ $0.pluginId == item.pluginId }).count < 8 {
                self.menuItems.append(item)
            }
        }
    }

    func removeMenuItem(pluginId: String, itemId: String) {
        DispatchQueue.main.async {
            self.menuItems.removeAll(where: { $0.pluginId == pluginId && $0.itemId == itemId })
        }
    }

    public func menuItems(location: String) -> [AyuGramPluginMenuItem] {
        return self.menuItems.filter { $0.locations.contains(location) && self.runtimes[$0.pluginId] != nil }
    }

    public func menuTapped(_ item: AyuGramPluginMenuItem, payload: [String: Any]) {
        self.runtimes[item.pluginId]?.hook(name: item.hookName, payload: payload)
    }

    func openChat(peerId: EnginePeer.Id) {
        guard let context = self.context else {
            return
        }
        context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peerId, messageId: nil)
    }

    func openURL(_ url: URL) {
        guard let context = self.context else {
            return
        }
        context.sharedContext.applicationBindings.openUrl(url.absoluteString)
    }

    func toast(_ text: String) {
        guard let context = self.context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return true }), on: .root)
    }

    func alert(title: String, text: String, confirm: Bool, completion: @escaping (Bool) -> Void) {
        guard let context = self.context else {
            completion(false)
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var actions: [TextAlertAction] = []
        if confirm {
            actions.append(TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                completion(false)
            }))
        }
        actions.append(TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
            completion(true)
        }))
        context.sharedContext.mainWindow?.present(textAlertController(context: context, title: title, text: String(text.prefix(2000)), actions: actions), on: .root)
    }

    func prompt(title: String, value: String?, placeholder: String?, completion: @escaping (String?) -> Void) {
        guard let context = self.context else {
            completion(nil)
            return
        }
        context.sharedContext.mainWindow?.present(promptController(context: context, text: title, value: value, placeholder: placeholder, characterLimit: 4000, apply: { value in
            completion(value)
        }), on: .root)
    }

    func send(peerId: EnginePeer.Id, text: String, silent: Bool, completion: @escaping (Int?) -> Void) {
        guard let context = self.context else {
            completion(nil)
            return
        }
        var attributes: [MessageAttribute] = []
        if silent {
            attributes.append(NotificationInfoMessageAttribute(flags: .muted))
        }
        let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
        |> deliverOnMainQueue).startStandalone(next: { ids in
            completion(ids.first.flatMap { $0 }.map { Int($0.id) })
        })
    }

    func messages(peerId: EnginePeer.Id, limit: Int, completion: @escaping ([[String: Any]]) -> Void) {
        guard let context = self.context else {
            completion([])
            return
        }
        let accountPeerId = context.account.peerId
        let _ = (context.engine.ayuGramRecentMessages(peerId: peerId, limit: limit)
        |> take(1)).startStandalone(next: { list in
            completion(list.map { message -> [String: Any] in
                return ["id": Int(message.id.id), "peerId": String(peerId.toInt64()), "text": message.text, "date": Int(message.timestamp), "isOutgoing": !message.flags.contains(.Incoming) || message.author?.id == accountPeerId, "authorId": message.author.map { String($0.id.toInt64()) } ?? ""]
            })
        })
    }

    func me(completion: @escaping ([String: Any]?) -> Void) {
        guard let context = self.context else {
            completion(nil)
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> take(1)).startStandalone(next: { peer in
            guard let peer, case let .user(user) = peer else {
                completion(nil)
                return
            }
            completion(["id": String(user.id.toInt64()), "firstName": user.firstName ?? "", "lastName": user.lastName ?? "", "username": user.addressName ?? "", "isPremium": peer.isPremium])
        })
    }
}
