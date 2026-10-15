# Bringing in a new Telegram or Swiftgram release

`.github/workflows/upstream-watch.yml` checks every hour and comments on the inbox PR
(`inbox_pr` in `ci/upstream.json`) when Telegram-iOS bumps `versions.json` or Swiftgram
publishes a newer tag. To merge it:

1. Fetch the source: `git fetch https://github.com/TelegramMessenger/Telegram-iOS master`
   (or the Swiftgram tag). Their histories are not connected to ours, so merge with an
   explicit base: `git merge-tree --write-tree --merge-base=<telegram_sha from ci/upstream.json> standard FETCH_HEAD`,
   read the tree into a worktree of `standard` and resolve every conflict, keeping both the
   upstream change and the AyuGram/Swiftgram behaviour. Commit it as one commit on top of
   `standard` (do not add the upstream history as a parent).
2. Check what the update changes in the build: `versions.json` (Xcode, Bazel), submodules
   and `.gitmodules`, `build-system/bazel-rules/rules_apple` (update the pinned
   `ios_rules.bzl` SHA-256 in `ci/ayugram_ci.py`), and APIs used by `Swiftgram/` and by
   the CI stubs in `ci/*.py`.
3. Update `ci/upstream.json` to the merged Telegram version/SHA and Swiftgram tag.
4. Run `python3 -m unittest discover -s ci/tests -p 'test_*.py'`, push `standard`, merge
   `standard` into `custom`, push, and run the AyuGram iOS workflow from `standard`.
   The build keeps going after errors, so one failed run lists every compile error.
