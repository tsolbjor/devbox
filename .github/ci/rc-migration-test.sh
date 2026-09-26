#!/usr/bin/env bash
# Regression test for moving an existing machine onto ~/.config/devbox:
# ensure_devbox_shell_config against rc files shaped the way older setups left
# them (fixtures/legacy.*). The fresh-machine CI run never has such lines, so this
# is the only thing exercising migrate_rc_to_devbox_config.
#
#   bash .github/ci/rc-migration-test.sh           # compare against fixtures/expected.*
#   bash .github/ci/rc-migration-test.sh --update  # rewrite fixtures/expected.* (review the diff!)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
fixtures="$here/fixtures"
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

cp "$fixtures/legacy.zshrc" "$home/.zshrc"
cp "$fixtures/legacy.bashrc" "$home/.bashrc"

# Load setup's parameters and functions without running it: everything above RUN.
run_config() {
  HOME="$home" bash -c '
    set -euo pipefail
    . <(sed -n "1,/^# RUN$/p" "$1")
    ensure_devbox_shell_config
  ' _ "$repo/setup-ubuntu.sh"
}

status=0
fail() { echo "✗ $*"; status=1; }

run_config > "$home/run1.log"
run_config > "$home/run2.log"
cat "$home/run1.log"

if grep -nE '^[[:space:]]*→' "$home/run2.log"; then
  fail "second run took action — the migration is not idempotent"
fi
for rc in zshrc bashrc; do
  [[ -f "$home/.$rc.pre-devbox-config.bak" ]] || fail "no backup of .$rc was left"
  cmp -s "$home/.$rc.pre-devbox-config.bak" "$fixtures/legacy.$rc" || fail ".$rc backup is not the original"
done

if [[ "${1:-}" == "--update" ]]; then
  cp "$home/.zshrc" "$fixtures/expected.zshrc"
  cp "$home/.bashrc" "$fixtures/expected.bashrc"
  echo "→ fixtures/expected.* rewritten — review with: git diff $fixtures"
else
  for rc in zshrc bashrc; do
    if ! diff -u "$fixtures/expected.$rc" "$home/.$rc"; then
      fail ".$rc after migration differs from fixtures/expected.$rc"
    fi
  done
fi

bash -n "$home/.bashrc" "$home/.config/devbox/bashrc" || fail "bash rejects the migrated or generated bashrc"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$home/.zshrc" || fail "zsh rejects the migrated .zshrc"
  zsh -n "$home/.config/devbox/zshrc" || fail "zsh rejects the generated zshrc"
fi

[[ $status -eq 0 ]] && echo "✓ legacy rc files migrate cleanly and idempotently"
exit $status
