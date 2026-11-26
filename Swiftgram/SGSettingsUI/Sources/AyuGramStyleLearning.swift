import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings
import SGStrings

enum AyuGramStyleLearning {
    private static let enabledKey = "ayugram.style.enabled"
    private static let samplesKey = "ayugram.style.samples"
    private static let notesKey = "ayugram.style.notes"
    private static let notesBaseKey = "ayugram.style.notesBase"
    private static let scanKey = "ayugram.style.scanned"
    private static let sampleLimit = 400
    private static var learning = false
    private static var scanning = false

    static var enabled: Bool {
        get {
            return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
        }
    }

    static var samples: [String] {
        return UserDefaults.standard.stringArray(forKey: samplesKey) ?? []
    }

    static var notes: String {
        get {
            return UserDefaults.standard.string(forKey: notesKey) ?? ""
        }
        set {
            let value = String(newValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(900))
            UserDefaults.standard.set(value, forKey: notesKey)
            UserDefaults.standard.set(self.samples.count, forKey: notesBaseKey)
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: samplesKey)
        UserDefaults.standard.removeObject(forKey: notesKey)
        UserDefaults.standard.removeObject(forKey: notesBaseKey)
        UserDefaults.standard.removeObject(forKey: scanKey)
        NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
    }

    private static func usable(_ text: String) -> String? {
        let flat = text.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }).joined(separator: " ")
        if flat.isEmpty || flat.count > 280 {
            return nil
        }
        let lower = flat.lowercased()
        if lower.hasPrefix("http") || lower.hasPrefix("/") || lower.contains("://") {
            return nil
        }
        if flat.unicodeScalars.filter({ $0.properties.isAlphabetic }).count < 2 {
            return nil
        }
        return flat
    }

    static func ingest(_ texts: [String]) {
        guard self.enabled, !texts.isEmpty else {
            return
        }
        var list = self.samples
        var known = Set(list)
        for text in texts {
            guard let value = usable(text), !known.contains(value) else {
                continue
            }
            list.append(value)
            known.insert(value)
        }
        if list.count > sampleLimit {
            list = Array(list.suffix(sampleLimit))
        }
        UserDefaults.standard.set(list, forKey: samplesKey)
    }

    static func scanIfNeeded(context: AccountContext, locale: String) {
        guard self.enabled, !self.scanning else {
            return
        }
        let last = UserDefaults.standard.double(forKey: scanKey)
        guard Date().timeIntervalSince1970 - last > 12.0 * 3600.0 else {
            self.learnIfNeeded(locale: locale)
            return
        }
        self.scanning = true
        let _ = (context.engine.ayuGramOwnRecentTexts(chats: 40, perChat: 25)
        |> deliverOnMainQueue).startStandalone(next: { texts in
            self.scanning = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: scanKey)
            self.ingest(texts)
            self.learnIfNeeded(locale: locale)
        })
    }

    static func learnIfNeeded(locale: String) {
        guard self.enabled, !self.learning else {
            return
        }
        let all = self.samples
        let base = UserDefaults.standard.integer(forKey: notesBaseKey)
        let fresh = self.notes.isEmpty ? all.count >= 20 : all.count - base >= 40 || (base > all.count && all.count >= 20)
        guard fresh else {
            return
        }
        self.learning = true
        let picked = Array(all.suffix(160))
        var budget = 9000
        var lines: [String] = []
        for text in picked.reversed() {
            if budget - text.count < 0 {
                break
            }
            budget -= text.count + 1
            lines.append(text)
        }
        let system = "You study how one person writes in a messenger, from messages they sent in many different chats. Write a compact style guide that another writer can follow to sound exactly like them. Cover: typical length, letter case, punctuation and how they end messages, favorite words, slang, filler words and abbreviations, swearing level, how they joke, how they agree, refuse and ask, tone with different people, emoji or emoticon habits, and typical typos they leave. Note the languages they use and how they mix them. Use short bullet points written in English, quote their real characteristic words in the original language, never quote private facts, names, addresses, numbers or secrets. At most 12 bullets, under 900 characters in total."
        if !self.notes.isEmpty {
            let previous = self.notes
            ayuGramAssistantComplete(system: system + " Update and improve this previous guide instead of starting over:\n" + previous, prompt: "Messages written by the person, newest first:\n" + lines.joined(separator: "\n"), maxTokens: 420, locale: locale, completion: { reply, _ in
                self.learning = false
                if let reply, !reply.isEmpty {
                    self.notes = reply
                }
            })
        } else {
            ayuGramAssistantComplete(system: system, prompt: "Messages written by the person, newest first:\n" + lines.joined(separator: "\n"), maxTokens: 420, locale: locale, completion: { reply, _ in
                self.learning = false
                if let reply, !reply.isEmpty {
                    self.notes = reply
                }
            })
        }
    }

    static func promptBlock(language: String) -> String {
        guard self.enabled else {
            return ""
        }
        var result = ""
        if !self.notes.isEmpty {
            result += "\nHow Me writes everywhere (learned from Me's own messages in many chats, follow it closely):\n" + self.notes
        }
        let examples = self.samples.suffix(80).filter({ $0.count >= 3 }).suffix(14)
        if !examples.isEmpty {
            result += "\nReal examples of Me's own messages from other chats, to copy the manner, never the content:\n" + examples.map({ "- " + $0 }).joined(separator: "\n")
        }
        if !result.isEmpty {
            result += "\nThe reply must still be written in " + language + "."
        }
        return result
    }
}
