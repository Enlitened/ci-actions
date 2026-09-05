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

This repo is public so that private repos can consume it. Sharing a *private*
repo's actions across an organisation is a GitHub Team feature; the API refuses
the `organization` access level on Free with *"Only 'none' and 'user' access
levels are allowed for this repository"*. Public is the free route to the same
end, and there is nothing here worth keeping back: two composite actions, no
credentials, no project code.

**Nothing in this repo should ever run on a self-hosted runner.** It is public,
so anyone can fork it and open a pull request; a workflow here with
`runs-on: self-hosted` would be an invitation to run a stranger's code on the
Mac that builds the apps. This repo deliberately has no workflows at all. The
runners are registered against the three iOS repos individually, never to the
organisation, for the same reason.

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
