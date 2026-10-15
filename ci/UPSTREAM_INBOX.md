# Upstream inbox

This branch only exists to keep the inbox pull request open. `.github/workflows/upstream-watch.yml`
comments on that pull request when Telegram-iOS or Swiftgram publish a new release; the comment
wakes the Claude session subscribed to it, which merges the release (see `ci/UPSTREAM_SYNC.md`)
and builds the IPA. Do not merge this pull request.
