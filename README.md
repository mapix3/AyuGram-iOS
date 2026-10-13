# AyuGram for iOS

Unofficial, open-source Telegram client for iOS built on [Swiftgram](https://github.com/Swiftgram/Telegram-iOS), which is itself based on [Telegram for iOS](https://github.com/TelegramMessenger/Telegram-iOS).

Updates: [t.me/ayugramiosupdates](https://t.me/ayugramiosupdates)

## Features

- **Ghost mode** — hide read receipts, online status, typing, recording and story views, separately or all at once.
- **Message history** — keep deleted and edited messages from chosen chats on your device, with photos, videos, voice and round messages; save voice messages as M4A.
- **Content** — save and forward from restricted chats, allow screenshots.
- **Appearance** — themes, backgrounds and video wallpapers (Custom build).
- **Update notice** — tells you when a newer build is published and opens the channel.

Everything AyuGram stores stays on the device. The only request it makes on its own is downloading `update.json` from this repository to check for updates.

## Branches

| Branch | Build | Contents |
| --- | --- | --- |
| `main` | Standard | Swiftgram with the AyuGram features |
| `custom` | Custom | `main` plus the appearance options |
| `upstream` | — | Unmodified Swiftgram this project is based on |

The first commit on `main` is the unmodified Swiftgram source. Every change AyuGram makes is in the commits after it, so you can compare `upstream...main` (and `main...custom`) on GitHub to see exactly what is different.

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

Fetch the new upstream revision into the `upstream` branch, then merge `upstream` into `main` and `main` into `custom`, resolving any conflicts.

## Publishing an update

1. Build a new version. The build number is in `build-manifest.json` next to the IPA.
2. Post the IPA in the channel.
3. Edit `update.json` on `main`: set `build` to the new build number, `version` to the version you want to show, and `url` to the post link.

Everyone on an older build sees the update notice on the next launch. Only put a build number in `update.json` once that build is actually published.

## License

GPL-2.0, the same as Telegram for iOS and Swiftgram. See [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with Telegram or Swiftgram. It uses its own `api_id`, and the Telegram name and logo belong to their owners.
