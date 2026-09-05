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

## Adding a Mac

```sh
./bootstrap-runner.sh --check                 # will this machine do?
./bootstrap-runner.sh --tag mini Enlitened/japa Enlitened/dose-app Enlitened/lamp-and-line
```

Every runner labelled `self-hosted` is a candidate for every job, so GitHub
sends work to whichever is idle. A second Mac that is *nearly* right therefore
does not fail obviously — it fails at random, on whichever runs happen to land
on it, for reasons that look like the code. `--check` is what stops that, and
registration refuses to run when it fails: the pinned Xcode (read from
`select-xcode`, so there is one source of truth), the stock simulators the
per-runner clones are made from, and the tools these workflows assume the
machine provides.

`--tag` names the machine and keeps runner names unique across Macs — and with
them the simulators, since those are keyed on the runner. Pass it; the fallback
is a mangled hostname. Re-running is safe: a repo whose runner is already
configured is skipped.

## Checking a repo still holds the shape

```sh
./check-ios-ci.sh ~/dev/japa ~/dev/dose-app ~/dev/lamp-and-line
```

Fourteen checks, each one there because it was wrong once and cost a red run or
a bill: jobs pinned to a hosted image, a missing `CI_RUNNER`, a duplicated copy
of these actions, `sudo xcode-select`, a destination naming a literal device
rather than this runner's own, a result bundle never cleared on a persistent
runner, LFS bytes arriving as pointer files. It reads each checkout's own
remote, so it works on a clone called anything.

`FAIL` is something broken. `WARN` is something that only costs money, and only
on the hosted fallback — a 60-minute timeout is 600 billed minutes when a job
wedges, which is a third of a month. Exits non-zero on any `FAIL`.

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
