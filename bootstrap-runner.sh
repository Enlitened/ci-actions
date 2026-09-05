#!/bin/bash
# Register this Mac as a self-hosted runner for the iOS repos.
#
#   ./bootstrap-runner.sh --check                       # prerequisites only
#   ./bootstrap-runner.sh --tag mini Enlitened/japa ...  # register and start
#
# Every machine that runs these repos must be able to build them. GitHub sends a
# job to whichever runner labelled `self-hosted` is idle, so a second Mac that
# is *nearly* right does not fail half the time in an obvious way — it fails
# half the time at random, on whichever runs land on it. That is what --check is
# for, and why registration refuses to proceed when it fails.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAG=""; CHECK_ONLY=0; REPOS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --tag)   TAG="$2"; shift 2 ;;
    -*)      echo "unknown flag: $1" >&2; exit 2 ;;
    *)       REPOS+=("$1"); shift ;;
  esac
done

# The pin lives in select-xcode and nowhere else; read it rather than repeat it.
WANT_XCODE=$(ruby -ryaml -e "puts YAML.safe_load(File.read('$HERE/select-xcode/action.yml'))['inputs']['version']['default']")

ok=0; bad=0
say() { printf '  %-5s %s\n' "$1" "$2"; [ "$1" = FAIL ] && bad=$((bad+1)) || ok=$((ok+1)); return 0; }

echo "Prerequisites for a runner that builds these repos"

# Xcode: the exact pin, found the way select-xcode finds it.
found=""
for c in "/Applications/Xcode_${WANT_XCODE}.app" /Applications/Xcode.app; do
  [ -d "$c/Contents/Developer" ] || continue
  v=$(DEVELOPER_DIR="$c/Contents/Developer" xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
  [ "$v" = "$WANT_XCODE" ] && { found=$c; break; }
done
[ -n "$found" ] && say OK "Xcode $WANT_XCODE at $found" \
                || say FAIL "Xcode $WANT_XCODE not installed — CI pins it, and a different compiler turns unrelated pushes red"

# The stock devices every per-runner clone is made from.
for d in "iPhone 17 Pro" "Apple Watch Series 11 (46mm)"; do
  xcrun simctl list devices available 2>/dev/null | grep -qE "^ *$(sed 's/[()]/\\&/g' <<<"$d") \(" \
    && say OK "simulator: $d" \
    || say FAIL "no '$d' simulator — install the runtime in Xcode"
done

# Tools the workflows and actions assume the machine provides.
for t in xcbeautify:"every build step pipes through it" \
         git-lfs:"checkouts ask for lfs; without it assets arrive as pointer files" \
         python3:"await-simulator resolves devices with it" \
         ruby:"check-ios-ci.sh parses the workflow with it" \
         gh:"registration talks to GitHub with it"; do
  cmd=${t%%:*}; why=${t#*:}
  command -v "$cmd" >/dev/null && say OK "$cmd" || say FAIL "$cmd missing — $why"
done

gh auth status >/dev/null 2>&1 && say OK "gh is authenticated" || say FAIL "gh not authenticated — run: gh auth login"

echo "  → $ok ok, $bad missing"
[ "$bad" -gt 0 ] && { echo; echo "Fix the above before registering: a runner that cannot build is worse than no runner,"; echo "because jobs land on it at random and fail for reasons that look unrelated."; exit 1; }
[ "$CHECK_ONLY" = 1 ] && exit 0
[ ${#REPOS[@]} -gt 0 ] || { echo; echo "usage: $0 [--tag <name>] <owner/repo>..."; exit 2; }

# A tag that is this machine, so runner names stay unique across Macs — and so
# the simulators each runner creates stay distinct too.
[ -n "$TAG" ] || TAG=$(hostname -s | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-16)
echo; echo "Registering as '<repo>-$TAG'"

V=$(gh api /repos/actions/runner/releases/latest --jq .tag_name | tr -d v)
for slug in "${REPOS[@]}"; do
  name=${slug##*/}
  DIR=$HOME/actions-runner-$name
  if [ -f "$DIR/.runner" ]; then echo "  $slug: already configured at $DIR — skipping"; continue; fi

  mkdir -p "$DIR"
  curl -fsSL -o "$DIR/r.tar.gz" \
    "https://github.com/actions/runner/releases/download/v${V}/actions-runner-osx-arm64-${V}.tar.gz"
  tar xzf "$DIR/r.tar.gz" -C "$DIR" && rm "$DIR/r.tar.gz"

  token=$(gh api -X POST "/repos/$slug/actions/runners/registration-token" --jq .token)
  ( cd "$DIR" && ./config.sh --url "https://github.com/$slug" --token "$token" \
      --name "$name-$TAG" --labels self-hosted,macOS,ARM64 --work _work --unattended --replace >/dev/null )

  # config.sh snapshots the PATH of whatever shell ran it, which in an agent
  # session contains temp directories that will not exist later.
  printf '/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin\n' > "$DIR/.path"

  ( cd "$DIR" && ./svc.sh install >/dev/null && ./svc.sh start >/dev/null )
  echo "  $slug: $name-$TAG registered and started"
done

echo
echo "Runners are LaunchAgents: they work while this Mac is awake and logged in."
echo "Manage one with: cd ~/actions-runner-<repo> && ./svc.sh status|stop|start"
