#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_snapshots_setup (lib/arch-snapshots.sh): clean skip on non-btrfs,
# full tooling path on btrfs. findmnt, sudo, and systemctl answer from
# fixtures; the live root and live systemd are never touched.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-snapshots.sh"

test_arch_make_sandbox

# findmnt prints the fixture fstype; every privileged call is scripted.
cat >"${TEST_ARCH_BIN}/findmnt" <<EOF
#!/usr/bin/env bash
printf 'findmnt %s\n' "\$*" >>"$(test_arch_calls_log)"
printf '%s\n' "\${TEST_FINDMNT_FSTYPE:-ext4}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/findmnt"
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$*" in
  'snapper -c root get-config') exit "\${TEST_SNAPPER_CONFIG:-1}" ;;
  'pacman -Syu --needed --noconfirm -- btrfs-progs snapper snap-pac') exit 0 ;;
  'snapper -c root create-config /') exit 0 ;;
  'systemctl enable --now -- snapper-'*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"
cat >"${TEST_ARCH_BIN}/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl"

# --- Non-btrfs roots skip cleanly: exit 0, names the fstype, no sudo. ---
for fstype in ext4 xfs; do
  export TEST_FINDMNT_FSTYPE="${fstype}"
  : >"$(test_arch_calls_log)"
  skip_out="$(arch_snapshots_setup 2>&1)"
  printf '%s\n' "${skip_out}" >"${TEST_ARCH_SANDBOX}/skip-${fstype}.txt"
  test_arch_assert_contains "${TEST_ARCH_SANDBOX}/skip-${fstype}.txt" "${fstype}" "skip names ${fstype}"
  test_arch_assert_contains "${TEST_ARCH_SANDBOX}/skip-${fstype}.txt" 'skipped' 'skip says skipped'
  test_arch_assert_not_called sudo "skip on ${fstype} never elevates"
  test_arch_assert_not_called pacman "skip on ${fstype} installs nothing"
done

# --- btrfs without a root config: tooling, config, both timers. ---
export TEST_FINDMNT_FSTYPE=btrfs TEST_SNAPPER_CONFIG=1
if [[ -e /.snapshots ]]; then
  # An orphan snapshots dir on the test host exercises the refusal path:
  # unexpected existing state must die loudly, never be adopted.
  set +e
  ( arch_snapshots_setup >/dev/null 2>&1 )
  orphan_status=$?
  set -e
  ((orphan_status != 0)) || test_arch_die 'orphan /.snapshots was adopted silently'
  printf 'orphan /.snapshots refused as decided.\n'
else
  : >"$(test_arch_calls_log)"
  arch_snapshots_setup >/dev/null
  test_arch_assert_contains "$(test_arch_calls_log)" \
    'sudo pacman -Syu --needed --noconfirm -- btrfs-progs snapper snap-pac' 'btrfs installs snapper tooling'
  test_arch_assert_contains "$(test_arch_calls_log)" 'sudo snapper -c root create-config /' \
    'missing root config is created'
  test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable --now -- snapper-timeline.timer' \
    'timeline timer enabled'
  test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable --now -- snapper-cleanup.timer' \
    'cleanup timer enabled'
fi

# --- btrfs with an existing root config: no create-config, timers still ensured. ---
export TEST_SNAPPER_CONFIG=0
: >"$(test_arch_calls_log)"
arch_snapshots_setup >/dev/null
if grep -q 'create-config' "$(test_arch_calls_log)"; then
  test_arch_die 'existing root config was recreated'
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable --now -- snapper-timeline.timer' \
  'existing config still ensures timers'

test_arch_assert_no_live_paths 'snapshot planning'
printf 'Snapshots stay btrfs-only and refuse orphan state.\n'
