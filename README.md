# ci-actions

The composite actions the iOS repos in this organisation share: `japa`,
`dose-app`, `lamp-and-line`.

They were duplicated in all three until a single session fixed two real bugs in
japa's copies — `sudo xcode-select` hanging a headless LaunchAgent, and a probe
that killed its own step under `-e -o pipefail` — and the other two kept both.
That is the tax this repo exists to remove.

## Using them

```yaml
- uses: Enlitened/ci-actions/select-xcode@main
  # with: { version: "26.6" }   # optional; defaults to 26.6

- uses: Enlitened/ci-actions/await-simulator@main
  with:
    device: iPhone 17 Pro
```

`@main` rather than a tag, deliberately: a fix should reach all three repos
without three commits. The trade is that a bad push here breaks all three at
once, which is tolerable while one person commits and a run takes a minute. If
that stops being true, tag releases and pin to the tag.

This repo is private, so every consumer depends on
**Settings → Actions → General → Access → "Accessible from repositories in the
organization"** being set. Without it the consuming workflow fails at the
`uses:` line with a checkout error, not an obvious permissions message.

## What is here

- **`select-xcode`** — resolves the pinned Xcode and exports `DEVELOPER_DIR`.
  Never uses `sudo`. Confirms the version by asking `xcodebuild` rather than by
  trusting the bundle name, because on a self-hosted runner `/Applications/Xcode.app`
  is whatever was installed there last. Probes in a subshell with `-e` and
  `pipefail` off, and retries, because the first `xcodebuild` after a runner
  service restart has been seen to abort with no output at all.

- **`await-simulator`** — waits until CoreSimulator has enumerated a named
  device, so a destination resolves. A cold service reports an empty device list
  rather than "not ready", which reads as a runner image that dropped a device.
