import Foundation
import SwiftSignalKit
import SGSimpleSettings

public func ayuGramBackgroundLeanSignal() -> Signal<Bool, NoError> {
    return Signal<Bool, NoError> { subscriber in
        subscriber.putNext(AyuGramBackgroundLean.isActive)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramBackgroundLean.didChange, object: nil, queue: nil, using: { _ in
            subscriber.putNext(AyuGramBackgroundLean.isActive)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}
