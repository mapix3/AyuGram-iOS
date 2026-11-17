# AyuGram for iOS

Unofficial, open-source Telegram client for iOS built on [Swiftgram](https://github.com/Swiftgram/Telegram-iOS), which is itself based on [Telegram for iOS](https://github.com/TelegramMessenger/Telegram-iOS).

Updates: [t.me/ayugramiosupdates](https://t.me/ayugramiosupdates)

## Features

- **Ghost mode** — hide read receipts, online status, typing, recording and story views, separately or all at once.
- **Message history** — keep deleted and edited messages from chosen chats on your device, with photos, videos, voice and round messages; save voice messages as M4A.
- **Content** — save and forward from restricted chats, allow screenshots.
- **Appearance** — themes, backgrounds and video wallpapers (Custom build).
- **Update notice** — tells you when a newer build is published and opens the channel.

Saved messages, history and settings stay on the device. AyuGram also talks to its own relay (`ayugram-push.ayugram-status.workers.dev`) and to GitHub:

- **Every launch:** `update.json` from this repository, and the `integrity.json` of the installed build from its release, to tell an official build from a patched one.
- **Every launch:** a moderation check on the relay with a random install id, the build, its signing source and bundle id, and SHA-256 hashes of the logged-in Telegram account ids. These hashes are not salted, so whoever runs the relay can match them to known Telegram ids; this check does not depend on the anonymous statistics switch.
- **Anonymous statistics** (can be turned off): build, variant, signing team, iOS version and device model.
- **Notifications through the relay** (opt-in): the relay decrypts each push to show it, so it sees the notification text.
- **AI assistant and Copilot** (with the AyuGram provider): your question, or the analysed messages, go through the relay to Gemini or Groq. Other providers are called directly with your own key.
- **Supporter badge and scam reports** (when used): the account id, the payment code, or the report with its attachments.

## Branches

| Branch | Build | Contents |
| --- | --- | --- |
| `standard` | Standard | Swiftgram with the AyuGram features |
| `custom` | Custom | `standard` plus the appearance options |
| `upstream` | — | Unmodified Swiftgram this project is based on |

The first commit on `standard` is the unmodified Swiftgram source. Every change AyuGram makes is in the commits after it, so you can compare `upstream...standard` (and `standard...custom`) on GitHub to see exactly what is different.

## Building

The app is built by GitHub Actions as unsigned IPAs. Sign them with your own certificate (AltStore, SideStore, Sideloadly, ESign, Feather, …) or run them in LiveContainer.

1. Fork or clone this repository.
2. In **Settings → Secrets and variables → Actions**, add:
   - `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` — your own, from [my.telegram.org](https://my.telegram.org)
   - `APPLE_TEAM_ID` — your 10-character Apple team ID
   - `APP_BUNDLE_ID` — the bundle identifier to build with
3. Open **Actions → AyuGram iOS → Run workflow** and choose the variant.
4. Download the IPA from the run's artifacts.

`ci/` contains the build driver and the checks that run before the full build.

## Updating to a new Swiftgram or Telegram version

Fetch the new upstream revision into the `upstream` branch, then merge `upstream` into `standard` and `standard` into `custom`, resolving any conflicts.

## Publishing an update

1. Build a new version. The build number is in `build-manifest.json` next to the IPA.
2. Post the IPA in the channel.
3. Edit `update.json` on `standard`: set `build` to the new build number, `version` to the version you want to show, and `url` to the post link.

Everyone on an older build sees the update notice on the next launch. Only put a build number in `update.json` once that build is actually published.

## License

GPL-2.0, the same as Telegram for iOS and Swiftgram. See [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with Telegram or Swiftgram. It uses its own `api_id`, and the Telegram name and logo belong to their owners.
