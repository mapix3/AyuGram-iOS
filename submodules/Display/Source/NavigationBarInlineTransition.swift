import Foundation
import UIKit
import AsyncDisplayKit

public protocol NavigationBarInlineTransitionParticipant: AnyObject {
    func updateInlineTransition(counterpart: NavigationBar, role: NavigationBarTransitionRole, progress: CGFloat)
    func animateInlineTransition(counterpart: NavigationBar, role: NavigationBarTransitionRole, progresses: [CGFloat], timing: NavigationKeyframeTiming)
    func endInlineTransition()
}
