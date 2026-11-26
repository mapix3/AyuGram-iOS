import Foundation

public enum AyuGramPluginSendDecision {
    case keep
    case replace(String)
    case cancel
}

public enum AyuGramPluginHooks {
    public static var beforeSend: ((Int64, String) -> AyuGramPluginSendDecision)?
    public static var didSend: ((Int64, String) -> Void)?
}
