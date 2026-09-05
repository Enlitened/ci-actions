#!/bin/bash
# Audit an iOS repo's CI against the shape these repos were moved to when the
# organisation's GitHub Actions allowance ran out four days into a month.
#
#   ./check-ios-ci.sh ~/dev/japa ~/dev/dose-app ~/dev/lamp-and-line
#
# Exits non-zero if any repo has a FAIL, so it can gate something later. WARN is
# for things that cost only money, and only on the hosted fallback.
#
# Each check is here because it was once wrong and cost a red run or a bill; see
# the README for the failures behind them.

# The action these repos are expected to share. A path, not a full slug, so a
# fork under another organisation still passes.
SHARED=ci-actions/select-xcode@

overall=0
for D in "$@"; do
  W="$D/.github/workflows/ci.yml"
  fails=0

  # The GitHub repo from the checkout's own remote, rather than guessing it from
  # the directory name — a clone can be called anything.
  SLUG=$(git -C "$D" remote get-url origin 2>/dev/null \
         | sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s#\.git$##')
  echo; echo "═══ ${SLUG:-$(basename "$D")} ═══"
  [ -n "$SLUG" ] || { echo "  FAIL  not a git checkout with an origin"; overall=1; continue; }

  say() { printf '  %-5s %s\n' "$1" "$2"; [ "$1" = "FAIL" ] && fails=$((fails+1)); return 0; }
  has() { grep -q "$1" "$W" 2>/dev/null; }

  [ -f "$W" ] || { say FAIL "no .github/workflows/ci.yml"; overall=1; continue; }

  njobs=$(ruby -ryaml -e "puts YAML.safe_load(File.read('$W'))['jobs'].size" 2>/dev/null)
  nrunner=$(grep -c 'runs-on:.*vars.CI_RUNNER' "$W")
  [ "$nrunner" = "$njobs" ] \
    && say OK   "all $njobs jobs use vars.CI_RUNNER" \
    || say FAIL "$nrunner/$njobs jobs use vars.CI_RUNNER (rest are pinned to a hosted image)"

  v=$(gh variable list --repo "$SLUG" 2>/dev/null | awk '$1=="CI_RUNNER"{print $2}')
  [ "$v" = "self-hosted" ] \
    && say OK   "CI_RUNNER=self-hosted" \
    || say WARN "CI_RUNNER is '${v:-unset}' — runs bill GitHub minutes at 10x"

  st=$(gh api "/repos/$SLUG/actions/runners" --jq '.runners[]|.status' 2>/dev/null | head -1)
  if [ "$v" = "self-hosted" ]; then
    [ "$st" = "online" ] && say OK "runner online" || say FAIL "runner is '${st:-none registered}'"
  fi

  [ -d "$D/.github/actions" ] \
    && say FAIL "still has local .github/actions — should use the shared ones" \
    || say OK   "no duplicated local actions"

  has "$SHARED" \
    && say OK   "uses the shared select-xcode" \
    || say FAIL "does not reference $SHARED"

  # `sudo` in a headless LaunchAgent waits for a password nobody types.
  grep -rq 'sudo xcode-select' "$D/.github" 2>/dev/null \
    && say FAIL "sudo xcode-select present — hangs a headless LaunchAgent" \
    || say OK   "no sudo xcode-select"

  # A literal device name means every runner on the machine drives the same
  # simulator; the shared action hands back one per runner instead.
  grep -qE "name=(iPhone|iPad|Apple Watch)[^\$]*'" "$W" \
    && say FAIL "a destination names a literal device — use the await-simulator output" \
    || say OK   "destinations use the per-runner device"

  has 'contents: read' && say OK "read-only token" || say WARN "no 'permissions: contents: read'"
  has 'cancel-in-progress: true' && say OK "supersedes in-progress runs" || say WARN "cancel-in-progress not unconditionally true"

  bad=$(ruby -ryaml -e "
    YAML.safe_load(File.read('$W'))['jobs'].each{|k,v|
      t=v['timeout-minutes']; puts \"#{k}=#{t||'unset'}\" if t.nil? || t>30 }" 2>/dev/null | tr '\n' ' ')
  [ -z "$bad" ] && say OK "all timeouts <= 30m" || say WARN "long/absent timeouts: $bad (a timeout is billed in full)"

  if has '\-resultBundlePath'; then
    has 'rm -rf.*xcresult' \
      && say OK   "clears stale result bundle" \
      || say FAIL "writes -resultBundlePath but never rm -rf's it (a persistent runner will refuse)"
  fi

  if [ -n "$(git -C "$D" lfs ls-files 2>/dev/null)" ]; then
    has 'lfs: true' \
      && say OK   "LFS tracked and checkout asks for it" \
      || say FAIL "repo uses LFS but no 'lfs: true' — steps reading those bytes get pointer files"
  fi

  id=$(gh run list --repo "$SLUG" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
  if [ -n "$id" ]; then
    c=$(gh run view "$id" --repo "$SLUG" --json conclusion --jq .conclusion 2>/dev/null)
    b=$(gh api "/repos/$SLUG/actions/runs/$id/timing" --jq '.billable|tostring' 2>/dev/null)
    [ "$c" = "success" ] && say OK "last run: success" || say FAIL "last run: $c"
    [ "$b" = "{}" ] && say OK "last run billed nothing" || say WARN "last run billable: $b"
  fi

  [ "$fails" -gt 0 ] && overall=1
  echo "  → $fails failing check(s)"
done
exit $overall
