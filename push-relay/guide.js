export const GUIDE_VERSION = 12;

export const GUIDE = `AyuGram for iOS: where things are. Answer questions about the app only from this list; if something is not here, say you are not sure instead of inventing menus.

Main menu: Telegram Settings > AyuGram. At the top: Ghost Mode state and how many things are hidden.

Ghost Mode: AyuGram > Ghost Mode. Turns on every "Hide" switch below while keeping their own values. Quick switch: hold the Chats tab (needs "Switch in the Chats tab" on).
Hide: read receipts, online status, typing, recording voice/video, uploading, story views (AyuGram > Hide).
Behavior (AyuGram > Behavior): Offline after sending; Read chat when replying; Silent sending (off / in Ghost Mode / always); Send as scheduled while in Ghost Mode; Confirm sending a read receipt.
Content: Bypass copy protection (save, copy, forward protected content); Allow screenshots of protected and secret content.

Deleted and edited messages: deleted messages stay in the chat where they were, marked as deleted; "Dim deleted messages" (AyuGram > Chats) makes them semi-transparent. Edit and deletion history: AyuGram > Message history > Open history (only chosen chats, 30 days, up to 200 entries, no secret chats or one-time media). Chats deleted as a whole: AyuGram > Message history > Open history > Deleted chats.
Chats section: Disable ads, Disable link warning, Disable greeting sticker, Dim deleted messages, "Repeat" in the message menu, Confirm sending stickers, Confirm sending GIFs. These are local only.

In a chat:
- AI analysis: the round ghost button at the top right under the avatar. Tap it: analysis of the chat plus one quick reply (tap inserts it, hold copies), and a field to ask about the chat. Switch: AyuGram > AI > AI hints in chats.
- Export chat: open the chat profile > More (three dots) > Export chat. Works for private chats, groups, channels and secret chats; text only or with media; the archive can be imported back.
- Open in floating window: chat profile > More > Open in floating window. The window floats over the whole app, shows live messages and lets you reply; drag by the header, "-" minimizes to a bubble, double tap on the header opens the full chat. Only inside AyuGram.
- Peek online: user profile > More > Peek online.
Import chat: AyuGram > Chat import (ZIP or TXT from WhatsApp, LINE, KakaoTalk or AyuGram export).

AI: AyuGram > AI. AI assistant (also the sparkles button in the chat list), Search engine, Assistant button in the chat list, AI hints in chats, AI provider (AyuGram free, Pollinations, Groq, Google Gemini, OpenRouter), API key and model for the chosen provider. Gemini switches to another model by itself when one is overloaded, and questions that need the internet go through the AyuGram provider. Answer language and Personalization (tell the assistant about yourself and how to answer) are in the same section. The assistant has chats on the left (the sidebar button at the top right), history is saved.

Supporter badge: AyuGram > Client > Supporter badge, above Local Premium. For a $3 donation you get your own badge next to your name that every AyuGram user sees on any build: tap "Support", the app gets personal Crypto Bot and xRocket invoices and a TON amount with a code for the comment; all three are confirmed automatically within a couple of minutes (even with the app closed); then a badge editor opens there (icon or emoji, shape, color). Tapping a badge in a profile shows what it means.
Client: Local Premium (premium features shown locally), Disable Liquid Glass (after an app restart brings back the classic pre-Liquid-Glass Telegram interface: flat navigation bar, classic tab bar, classic chat input panel, menus and lists).
Security: Report a scam (with screenshots or videos), Anonymous stats.
Support: AyuGram channel, developer, AyuGram log, Check for updates. Donate is at the very bottom of AyuGram (Crypto Bot, xRocket, TON wallet with QR codes).

Video settings: AyuGram > Video > Video settings (just above Client). Round videos: Quality (Standard 480p or Maximum 640p; Telegram delivers anything larger than 640 as a regular video), Frame rate (30, 60 or 120 fps; falls back to the closest lower rate the camera supports, 60 fps records with one camera at a time), Bitrate (Auto or 2, 4, 6, 8, 10 Mbit/s), HEVC (H.265; sharper at the same bitrate, falls back to H.264 if the phone cannot encode it), Round video from gallery (on by default). Experimental: "1080p disguised as 640p" adds 720p and 1080p to Quality; the video keeps the real resolution but is declared as 640x640 so it stays a round video (Telegram may stop accepting it or deliver it as a regular video, files are much bigger). Zoom in round videos: spread two fingers to zoom in, pinch them together to zoom out down to 0.5x on the back camera of phones with an ultra-wide lens (iPhone 11 and newer, not SE); the front camera already shows its full width, and the default framing is the same as before. Quality, bitrate, HEVC and the experimental option apply both to recorded round videos and to round videos made from gallery. Videos: Always best quality (sends up to 1080p by default) and Higher bitrate. Regular videos keep their original frame rate up to 60 fps.
Round video from gallery: in a chat (Saved Messages too) open the attachment menu, select exactly one video, hold the send button and choose "Send as Round Video"; the same item is in the send menu when a single video is opened full screen from the attachment menu; then drag and pinch to choose the part of the frame inside the circle, pick the fragment start and length (up to 60 seconds) and tap Send.

Visual effects (custom build only, the standard build has none of these): Telegram Settings > Appearance > Effects, also AyuGram > Client > Effects and at the bottom of AyuGram > Client > Appearance. A master switch turns all of them off at once; they pause by themselves with Reduce Motion or Low Power Mode.
- Chat background: particles over the wallpaper (snow, stars, fireflies, petals, bubbles) with density and speed sliders and "React to touch"; Aurora gradient (more drifting colours on gradient wallpapers); Grain slider (film grain on gradient wallpapers); Deep parallax (gradient and pattern move at different depths when you tilt the phone); Water ripple (tap or drag on empty background).
- Bubbles: Glow around your own bubbles; Glass bubbles (translucent, the wallpaper shows through).
- Animations: Delete style (standard, dust, burn, shatter, implode); Send style (standard, spring, sparkles, warp; sparkles and warp only for messages from the text field); Incoming text reveal (new incoming messages appear word by word).
- Interface: Avatar rings (rotating gradient ring around avatars of people who are online, in the chat list).

Custom build only: AyuGram > Client > Appearance: your own background image or video for the chat list and chats with dim and blur, row opacity, particles (snow and others, seasonal), drift, fireworks, parallax, New Year mode. At the bottom of Appearance, "Font and badge": Font (system styles: rounded, serif, monospaced; iOS fonts like Avenir Next, Futura, Georgia; or import your own .ttf/.otf; applies after restarting the app) and App badge (the AYUGRAM pill under the Dynamic Island: your own text, picture and colors).

Profile extras (custom build only): AyuGram > Client > Profile extras. Everything here is decoration that every AyuGram user sees on your profile; it is not real and other Telegram apps do not show it.
- Fake NFTs: add up to 30 collectible gifts, either a real gift by its link or slug (like PlushPepe-1) or your own (collection, model, backdrop, pattern, number); drag to reorder and pin up to 6 to the top of the profile, like pinned gifts in Telegram. Tapping one always shows a "Fake NFT" label; they cannot be transferred, sold, upgraded or opened as real gifts.
- Fake usernames: up to 10 extra collectible-style usernames (4-32 letters, digits or underscores, names like telegram, support or admin are not allowed). Tapping one always shows "Fake username"; they are not real Telegram usernames, nobody can find or message you by them.
- Profile bubbles: a switch that shows your pinned fake NFTs as floating bubbles around the avatar in the profile header.
- Profile background: your own photo (JPEG, PNG or HEIC up to 1.5 MB) or video (MP4 or MOV up to 8 MB and 15 seconds) behind the profile header; up to 8 uploads a day. Remove it or all extras with Delete.
Before the first change you confirm that the Telegram account is yours: tap Verify ownership in Profile extras, the AyuGram bot opens, tap Start and then Confirm (the code in the bot matches the one in the app), go back to AyuGram and editing unlocks by itself. The link works for 10 minutes, only from the same Telegram account and only once; never confirm a link someone else sent you. Your extras are then tied to this install, so nobody else can change them; verifying again from a new install of the same account moves them there. Backgrounds are checked by the AyuGram team and can be removed.

Updates come from the @ayugramiosupdates channel; the IPA is installed with a signing app.`;
