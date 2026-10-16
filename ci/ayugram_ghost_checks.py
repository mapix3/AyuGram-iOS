import json
import re
import subprocess
from pathlib import Path

NEW_KEYS = ['HeroGhostOn', 'HeroGhostOff', 'HeroHidden', 'GhostSubtitle', 'GhostFooter', 'HideSection', 'BehaviorSection',
            'OfflineAfterSending', 'OfflineAfterSendingInfo', 'ReadOnSend', 'ReadOnSendInfo', 'QuickToggle', 'QuickToggleInfo',
            'ContentSection', 'IgnoreProtection', 'IgnoreProtectionInfo', 'AllowScreenshots', 'AllowScreenshotsInfo', 'ContentFooter',
            'SaveDeletedInfo', 'OpenHistory', 'ClientSection', 'LocalPremiumInfo', 'GhostEnable', 'GhostDisable',
            'GhostEnabledToast', 'GhostDisabledToast', 'ChatListBackground', 'ConversationBackground', 'ChooseVideo', 'ShowBackground',
            'AddAccountHelp', 'HistorySubtitle', 'HistoryAll', 'HistoryEdited', 'HistoryNow', 'HistoryShowMessage', 'HistoryOpenChat',
            'HistoryStopSaving', 'HistoryNoChats', 'HistoryEmptyInfo', 'HistorySaveAudio', 'HistoryDeleteEntry',
            'SupportSection', 'SupportChannel', 'SupportDeveloper', 'CheckUpdates', 'UpToDate', 'UpdateAvailable',
            'UpdateAvailableInfo', 'UpdateIgnore', 'UpdateOpen',
            'NotificationsSection', 'BarkSetUp', 'BarkConnected', 'BarkFooter', 'BarkPrompt', 'BarkEnabled', 'BarkDisabled',
            'BarkInvalid', 'BarkFailed']


def check_strings(source: Path):
    locales = sorted((source / 'Swiftgram/SGStrings/Strings').glob('*.lproj/SGLocalizable.strings'))
    assert len(locales) == 37
    for file in locales:
        strings = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', file], text=True))
        missing = [key for key in NEW_KEYS if not strings.get('Ayu.' + key, '').strip()]
        assert not missing, (file, missing)
        assert strings['Ayu.HeroHidden'].count('%@') == 2, file
        assert strings['Ayu.BarkFailed'].count('%@') == 1, file
        assert '500' in strings['Ayu.AddAccountHelp'] or '۵۰۰' in strings['Ayu.AddAccountHelp'], file
        for key in NEW_KEYS:
            # i18n formats every string; a stray % would corrupt the text.
            assert '%' not in strings['Ayu.' + key].replace('%@', ''), (file, key)


def check_sources(source: Path, variant: str):
    settings = (source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramSettings.swift').read_text()
    key = re.search(r'allowScreenshotsDefaultsKey = "([^"]+)"', settings).group(1)
    objc = (source / 'submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m').read_text()
    assert '@"' + key + '"' in objc, 'Screenshot protection reads the mirrored option'
    player = (source / 'submodules/MediaPlayer/Sources/MediaPlayerNode.swift').read_text()
    assert '"' + key + '"' in player, 'Video layers read the mirrored option'
    enqueue = (source / 'submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift').read_text()
    assert 'ayuPrepareProtectedForwards(account: account, peerId: peerId, messages: messages)' in enqueue
    pending = (source / 'submodules/TelegramCore/Sources/State/PendingMessageManager.swift').read_text()
    assert pending.count('_internal_ayuAfterSending(') == 2 and '_internal_ayuReportReadAfterSending(' not in pending
    settings_action = (source / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift').read_text()
    assert 'ayuGramSettingsScreen(context: self.context)' in settings_action
    chat_list = (source / 'submodules/ChatListUI/Sources/ChatListController.swift').read_text()
    assert 'AyuGramSettings.shared.setGhostMode(!ghostEnabled)' in chat_list
    assert '//Swiftgram/SGStrings:SGStrings' in (source / 'submodules/ChatListUI/BUILD').read_text()
    accounts = (source / 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift').read_text()
    assert 'i18n("Ayu.AddAccountHelp"' in accounts and 'Settings_AddAnotherAccount_PremiumHelp' not in accounts
    limit = (source / 'submodules/AccountUtils/Sources/AccountUtils.swift').read_text()
    assert 'maximumSwiftgramNumberOfAccounts = 500' in limit, 'Account limit text matches the actual limit'
    screen = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramSettingsScreen.swift').read_text()
    # switchTintColor exists only after the Custom-only patch 09; the screen is shared.
    assert 'switchTintColor' not in screen, 'Shared settings screen uses only APIs present in both variants'
    retained = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramRetainedMessages.swift').read_text()
    assert 'areMediaArraysEqual' not in retained, 'Reactions and refreshed file references are not edits'
    bubble = (source / 'submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift').read_text()
    assert 'ayuHistory' not in bubble, 'The version before an edit is shown only in Message history'
    validation = (source / 'submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift').read_text()
    validate = validation.split('private func validatePeerReadState(', 1)[1].split('private func pushPeerReadState(', 1)[0]
    assert 'return .retry' not in validate, 'Local reads ahead of the server never restart validation forever'
    manager = (source / 'submodules/TelegramCore/Sources/State/ManagedSynchronizePeerReadStates.swift').read_text()
    assert 'strongSelf.queue.after(1.0' in manager, 'Read state retries back off'
    history = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryController.swift').read_text()
    cards = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryCardItem.swift').read_text()
    assert 'public func ayuGramHistoryController(context: AccountContext, messageId: MessageId? = nil)' in history, 'Message context menu keeps its entry point'
    assert 'AyuGramHistoryHeroItem(' in history and 'filter.set(value)' in history, 'History summary filters records'
    assert 'case let .day(' in history and 'AyuGramHistoryEmptyItem(' in history, 'Records are grouped by day with an empty state'
    for token in ['final class AyuGramHistoryHeroItem', 'final class AyuGramHistoryEmptyItem', 'final class AyuGramHistoryCardItem', 'ayuGramPreviewCache']:
        assert token in cards, token
    for key in re.findall(r'i18n\("Ayu\.([A-Za-z]+)"', history + cards):
        assert key in NEW_KEYS or key in ('History', 'SaveMedia', 'HistoryInfo', 'ClearHistory', 'EmptyHistory', 'BeforeEdit', 'Deleted'), key
    kept = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramRetainedMessages.swift').read_text()
    assert 'recorded.contains(id) || (keepAll && ayuGramIsRetainable(transaction: transaction, id: id))' in kept, 'Deleted messages stay in every chat, not only the history chats'
    assert 'avatarNode.setPeer(context: item.context' in cards and 'peersById[' in history, 'History cards show real avatars'
    assert 'initialSelectedPeers' not in history, 'The chat picker preselects once; initialSelectedPeers toggles chats again and duplicates tokens'
    manager = (source / 'submodules/TelegramCore/Sources/State/AccountStateManager.swift').read_text()
    assert 'ayuGramPrefetchHistoryMedia(postbox: self.postbox, ids: events.addedIncomingMessageIds)' in manager, 'Media in history chats is downloaded on arrival'
    assert 'file.isAnimated ? "gif"' in (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramMessageHistory.swift').read_text(), 'GIFs and pictures sent as files are previewed'
    autoremove = (source / 'submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift').read_text()
    assert 'ayuGramRecordHistory' not in autoremove, 'One-time and timer media are never archived'
    core_h = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramMessageHistory.swift').read_text()
    assert 'AutoremoveTimeoutMessageAttribute' in core_h.split('func ayuGramIsHistoryCandidate', 1)[1].split('return', 1)[0], 'History excludes one-time and timer media'
    core = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramMessageHistory.swift').read_text()
    assert 'if file.isVoice { return "ogg" }' in core and 'file.isInstantVideo ? "round" : file.isVoice ? "voice"' in core, 'Voice and round messages keep a playable type'
    assert 'avatarNode.frame = avatar.frame' in cards, 'The avatar node is sized through its own frame'
    delegate = (source / 'submodules/TelegramUI/Sources/AppDelegate.swift').read_text()
    assert 'let maybeAppGroupUrl = sgAppGroupContainerURL(appGroupName)' in delegate, 'Sideloaded installs without the app group still start'
    group = (source / 'Swiftgram/SGAppGroupIdentifier/Sources/SGAppGroupIdentifier.swift').read_text()
    assert 'public func sgAppGroupContainerURL(' in group and '".appex"' in group, 'Only the main app falls back to a private container'
    entry = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramAppearanceEntry.swift').read_text()
    assert ('= true' in entry) == (variant == 'custom'), 'Appearance link matches the variant'
    if variant == 'custom':
        backdrop = (source / 'submodules/Display/Source/AyuGramBackdropView.swift').read_text()
        assert 'AVPlayer' not in backdrop and 'AVQueuePlayer' not in backdrop, 'Wallpaper video must not use AVPlayer'
        assert 'AyuGramSilentVideoRenderer' in backdrop
        assert 'rowTint' in backdrop and 'backdrop.rowTint' in (source / 'submodules/ChatListUI/Sources/ChatListControllerNode.swift').read_text(), 'Header and rows share one shade'
        video = (source / 'submodules/Display/Source/AyuGramSilentVideo.swift').read_text()
        assert 'decodedFrames >= 3' in video, 'Wallpaper decoding is paced per tick'
        tick = video.split('    private func tick()', 1)[1].split('    private func display(', 1)[0]
        assert 'self.layer.' not in tick, 'The decode loop never touches the display layer'
        display = video.split('    private func display(', 1)[1]
        assert display.index('DispatchQueue.main.async') < display.index('self.layer.enqueue'), 'Layer updates happen on the main thread'


def check_ghost_and_content(source: Path, variant: str):
    check_strings(source)
    check_sources(source, variant)
    print('Ghost Mode, content protection and settings strings validated in all 37 languages', flush=True)
