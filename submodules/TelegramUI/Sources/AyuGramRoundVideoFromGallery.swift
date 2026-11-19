import Foundation
import UIKit
import Photos
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import MediaEditor
import ChatMediaSend
import LocalMediaResources
import SGSettingsUI
import SGSimpleSettings
import SGStrings

extension ChatControllerImpl {
    func ayuRoundVideoFromGalleryHandler() -> (title: String, action: (PHAsset) -> Void)? {
        guard AyuGramSettings.shared.video.roundFromGallery else {
            return nil
        }
        if case .scheduledMessages = self.presentationInterfaceState.subject {
            return nil
        }
        let locale = self.presentationData.strings.baseLanguageCode
        return (i18n("Ayu.Video.SendAsRound", locale), { [weak self] asset in
            self?.ayuOpenRoundVideoEditor(asset: asset)
        })
    }

    func ayuOpenRoundVideoEditor(asset: PHAsset) {
        self.attachmentController?.dismiss(animated: true)
        Queue.mainQueue().after(0.35) { [weak self] in
            guard let self else {
                return
            }
            let controller = ayuGramRoundVideoEditorController(context: self.context, asset: asset, completion: { [weak self] selection in
                self?.ayuSendRoundVideo(selection: selection)
            })
            self.push(controller)
        }
    }

    func ayuSendRoundVideo(selection: AyuGramRoundVideoSelection) {
        let pixelDimensions = PixelDimensions(width: Int32(selection.dimensions.width), height: Int32(selection.dimensions.height))
        var values = chatMediaEditorValues(peerId: self.context.account.peerId, originalDimensions: pixelDimensions, qualityPreset: .videoMessage)
        values = values.withUpdatedCrop(rect: selection.cropRect, rotation: 0.0, orientation: nil, mirroring: false, perspective: .zero)
        values = values.withUpdatedVideoTrimRange(selection.start ..< (selection.start + selection.duration))
        guard let adjustments = chatMediaEditorVideoAdjustments(values: values) else {
            return
        }
        let resource = VideoLibraryMediaResource(localIdentifier: selection.asset.localIdentifier, conversion: .compress(adjustments))
        let exportConfiguration = recommendedVideoExportConfiguration(values: values, duration: selection.duration, frameRate: 30.0)
        let exportWidth = (exportConfiguration.videoSettings[AVVideoWidthKey] as? Int) ?? AyuGramVideoSettings.roundDeclaredMaximumSide
        let exportHeight = (exportConfiguration.videoSettings[AVVideoHeightKey] as? Int) ?? AyuGramVideoSettings.roundDeclaredMaximumSide
        let declaredSize = AyuGramVideoSettings.roundDeclaredSize(width: exportWidth, height: exportHeight)
        let outputDimensions = PixelDimensions(width: Int32(declaredSize.width), height: Int32(declaredSize.height))

        var previewRepresentations: [TelegramMediaImageRepresentation] = []
        if let thumbnail = selection.thumbnail {
            let thumbnailSize = CGSize(width: 320.0, height: 320.0)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let scaled = UIGraphicsImageRenderer(size: thumbnailSize, format: format).image { _ in
                thumbnail.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            }
            if let data = scaled.jpegData(compressionQuality: 0.5) {
                let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                self.context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: data)
                previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            }
        }

        let media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: [.FileName(fileName: "video.mp4"), .Video(duration: selection.duration, size: outputDimensions, flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])

        let replyMessageSubject = self.presentationInterfaceState.interfaceState.replyMessageSubject
        let message: EnqueueMessage = .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: self.chatLocation.threadId, replyToMessageId: replyMessageSubject?.subjectModel, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])

        self.updateChatPresentationInterfaceState(animated: true, interactive: false, {
            $0.updatedInterfaceState { $0.withUpdatedReplyMessageSubject(nil) }
        })
        let transformed = self.transformEnqueueMessages([message], silentPosting: self.presentationInterfaceState.interfaceState.silentPosting)
        self.sendMessages(transformed)
    }
}
