import Foundation
import TelegramCore
import AccountContext
import TelegramPresentationData

public func ayuGramFakeNftViewScreen(context: AccountContext, gift: StarGift.UniqueGift) -> GiftViewScreen {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return GiftViewScreen(
        context: context,
        subject: .uniqueGift(gift.withResellAmounts(nil), nil),
        customAction: GiftViewScreen.CustomAction(title: presentationData.strings.Common_Close, action: {}),
        ayuFakeNft: true
    )
}
