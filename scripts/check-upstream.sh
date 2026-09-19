#!/bin/bash
# Reports when SidecarLauncher has moved past the commit install.sh pins.
#
#   scripts/check-upstream.sh [--pin SHA] [--open-issue]
#
# The pin is deliberate: an install always builds code that was reviewed here. Nothing
# updates it automatically, so without this check an upstream fix could go unnoticed for
# months. Run weekly by CI. Exit 0 when current, 3 when behind, 1 or 2 when the check itself
# could not run.
set -euo pipefail

UPSTREAM="Ocasio-J/SidecarLauncher"
UPSTREAM_URL="https://github.com/Ocasio-J/SidecarLauncher"
BRANCH="main"
TITLE="Upstream: SidecarLauncher has moved past the pinned commit"
PIN=""
OPEN_ISSUE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pin) PIN="${2:?--pin needs a value}"; shift 2 ;;
    --open-issue) OPEN_ISSUE=1; shift ;;
    -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
if [ -z "$PIN" ]; then
  # shellcheck disable=SC2016  # the ${...} is literal text being matched, not an expansion
  PIN="$(sed -n 's/^UPSTREAM_REF="${SIDECARLAUNCHER_REF:-\([0-9a-f]\{40\}\)}"$/\1/p' install.sh)"
fi
case "$PIN" in
  *[!0-9a-f]*|"") echo "could not read a 40-character pin from install.sh" >&2; exit 2 ;;
esac
[ "${#PIN}" -eq 40 ] || { echo "pin is not a full commit SHA: $PIN" >&2; exit 2; }

compare="$(gh api "repos/$UPSTREAM/compare/$PIN...$BRANCH" 2>/dev/null)" \
  || { echo "could not compare $PIN with $UPSTREAM@$BRANCH" >&2; exit 1; }
status="$(jq -r '.status' <<<"$compare")"
ahead="$(jq -r '.ahead_by' <<<"$compare")"
head_sha="$(jq -r '.commits[-1].sha // empty' <<<"$compare")"

say() { echo "$1"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; return 0; }

if [ "$status" = identical ]; then
  say "SidecarLauncher pin ${PIN:0:12} is current with $UPSTREAM@$BRANCH."
  exit 0
fi
if [ "$status" = behind ] || [ "$ahead" -eq 0 ]; then
  # The pin is newer than the branch: unusual, but not a reason to act.
  say "SidecarLauncher pin ${PIN:0:12} is not behind $UPSTREAM@$BRANCH (status: $status)."
  exit 0
fi

commits="$(jq -r --arg u "$UPSTREAM_URL" '.commits[] | "- [`\(.sha[0:7])`](\($u)/commit/\(.sha)) \(.commit.message | split("\n")[0])"' <<<"$compare")"
say "SidecarLauncher is $ahead commit(s) ahead of the pinned ${PIN:0:12} (status: $status)."
say ""
say "$commits"

if [ "$OPEN_ISSUE" -eq 1 ]; then
  # Keyed on the upstream commit, and closed issues count: deciding not to take an update is
  # a decision, and repeating the same notice every week would train everyone to ignore it.
  # A later upstream commit is a different key, so a genuinely new change is still reported.
  marker="<!-- upstream-head: $head_sha -->"
  said="$(gh issue list --state all --limit 100 --json number,body \
    --jq "map(select(.body != null and (.body | contains(\"$marker\")))) | .[0].number // empty")"
  if [ -n "$said" ]; then
    echo "Already reported in issue #$said; saying nothing further."
  else
    body="$(cat <<BODY
\`install.sh\` pins [\`${PIN:0:12}\`]($UPSTREAM_URL/commit/$PIN) of [$UPSTREAM]($UPSTREAM_URL).
That branch is now **$ahead commit(s)** ahead.

$commits

The pin is deliberate, so nothing here changes by itself. To take the update: read the diff
above, set \`UPSTREAM_REF\` in \`install.sh\` to \`${head_sha:-the new commit}\`, run
\`make check\`, and release as usual. The Homebrew formula follows the pin on its own.

Closing this without changing the pin is a fine outcome. This check will not raise the same
commit again, whether or not the issue stays open; it speaks up again when upstream moves
further.

<sub>Opened by \`scripts/check-upstream.sh\` from the weekly CI run.</sub>
$marker
BODY
)"
    gh issue create --title "$TITLE (${ahead} behind)" --body "$body" >/dev/null && echo "Opened an issue."
  fi
fi
exit 3
