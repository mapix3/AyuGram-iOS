import Foundation
import Display
import AccountContext

/// Custom build: the AyuGram screen links to background customization.
let ayuGramHasAppearanceEntry = true

func ayuGramAppearanceEntryController(context: AccountContext) -> ViewController? {
    return ayuGramAppearanceController(context: context)
}
