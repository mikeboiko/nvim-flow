#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"
if [ -z "$staged_files" ]; then
  echo "Skipping VHS demo recording: no staged files."
  exit 0
fi

needs_demo_refresh=0
while IFS= read -r file; do
  case "$file" in
    .lefthook.yml|README.md|lua/*|plugin/*|vhs/*)
      if [ "$file" != "vhs/nvim-flow-demo.gif" ]; then
        needs_demo_refresh=1
        break
      fi
      ;;
  esac
done <<EOF
$staged_files
EOF

if [ "$needs_demo_refresh" -ne 1 ]; then
  echo "Skipping VHS demo recording: no staged demo-impacting files."
  exit 0
fi

if ! command -v vhs >/dev/null 2>&1; then
  echo "vhs is required to refresh vhs/nvim-flow-demo.gif" >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "perl is required to rewrite the README demo URL" >&2
  exit 1
fi

echo "Recording demo GIF with VHS..."
rm -f "$repo_root/nvim-flow-demo.gif"
cd "$repo_root/vhs"
vhs nvim-flow-demo.tape
echo "Publishing demo GIF..."
publish_url="$(vhs publish -q nvim-flow-demo.gif | tail -n 1 | tr -d '\r')"
case "$publish_url" in
  https://vhs.charm.sh/*.gif) ;;
  *)
    echo "Unexpected VHS publish URL: $publish_url" >&2
    exit 1
    ;;
esac

cd "$repo_root"
README_VHS_URL="$publish_url" perl -0pi -e 's{!\[\]\(https://vhs\.charm\.sh/[^)]+\.gif\)}{![]($ENV{README_VHS_URL})}' README.md
git add README.md

echo "Refreshed local demo GIF at vhs/nvim-flow-demo.gif"
echo "Updated README demo URL to $publish_url"
