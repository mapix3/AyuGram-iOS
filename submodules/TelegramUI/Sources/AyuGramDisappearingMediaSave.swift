import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import SaveToCameraRoll
import ConvertOpusToAAC
import UndoUI
import TelegramPresentationData
import SGStrings

enum AyuGramDisappearingMedia {
    case image(TelegramMediaImage)
    case video(TelegramMediaFile)
    case voice(TelegramMediaFile)
}

func ayuGramDisappearingMedia(_ message: Message) -> AyuGramDisappearingMedia? {
    guard message.containsSecretMedia, message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat else {
        return nil
    }
    for media in message.media {
        if let image = media as? TelegramMediaImage, largestImageRepresentation(image.representations) != nil {
            return .image(image)
        }
        if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return .voice(file)
            }
            if file.isVideo || file.isInstantVideo {
                return .video(file)
            }
        }
    }
    return nil
}

func ayuGramDisappearingMediaSaveTitle(_ media: AyuGramDisappearingMedia, strings: PresentationStrings) -> String {
    switch media {
    case .image:
        return strings.Gallery_SaveImage
    case .video:
        return strings.Gallery_SaveVideo
    case .voice:
        return i18n("Ayu.HistorySaveAudio", strings.baseLanguageCode)
    }
}

/// Saves disappearing media without opening it, so nothing is reported to the sender:
/// photos and videos go to the photo library, voice messages are shared as M4A.
func ayuGramSaveDisappearingMedia(context: AccountContext, message: Message, presentOverlay: @escaping (ViewController) -> Void, presentShare: @escaping (UIViewController) -> Void) {
    guard let media = ayuGramDisappearingMedia(message) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let userLocation: MediaResourceUserLocation = .peer(message.id.peerId)
    let saved: (Bool) -> Void = { isVideo in
        Queue.mainQueue().after(0.2) {
            presentOverlay(UndoOverlayController(presentationData: presentationData, content: .mediaSaved(text: isVideo ? presentationData.strings.Gallery_VideoSaved : presentationData.strings.Gallery_ImageSaved), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return true }))
        }
    }
    switch media {
    case let .image(image):
        let _ = (saveToCameraRoll(context: context, userLocation: userLocation, mediaReference: ImageMediaReference.message(message: MessageReference(message), media: image).abstract)
        |> deliverOnMainQueue).startStandalone(completed: {
            saved(false)
        })
    case let .video(file):
        let _ = (saveToCameraRoll(context: context, userLocation: userLocation, mediaReference: FileMediaReference.message(message: MessageReference(message), media: file).abstract)
        |> deliverOnMainQueue).startStandalone(completed: {
            saved(true)
        })
    case let .voice(file):
        let _ = (fetchMediaData(context: context, userLocation: userLocation, mediaReference: FileMediaReference.message(message: MessageReference(message), media: file).abstract)
        |> mapToSignal { state, _ -> Signal<String, NoError> in
            if case let .data(data) = state, data.isComplete {
                return .single(data.path)
            }
            return .complete()
        }
        |> take(1)
        |> mapToSignal { path -> Signal<String, NoError> in
            let temp: () -> String = { NSTemporaryDirectory() + "ayu-voice-\(Int64.random(in: 0 ... Int64.max)).m4a" }
            return convertOpusToAAC(sourcePath: path, allocateTempFile: temp)
            |> map { output -> String in
                return output ?? path
            }
        }
        |> deliverOnMainQueue).startStandalone(next: { path in
            let activity = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
            presentShare(activity)
        })
    }
}
