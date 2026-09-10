#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Tailscale installs from official extra, never the AUR, and its daemon is
# enabled opportunistically in lib/arch-system.sh. Tailscale's Arch docs
# (https://tailscale.com/docs/install/arch, validated Jan 2026) prescribe
# `pacman -S tailscale` then `systemctl enable --now tailscaled`; the bundle
# owns the package and arch-setup owns the unit. Drives the real
# install_packages over a repo-only copy of the real bundle with stubbed
# pacman/sudo: no network, no live pacman, no AUR prompt.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Logging passthrough sudo plus a pacman stub that records the exact
# transaction argv and succeeds; nothing real is queried or installed.
test_arch_stub_passthrough_sudo
pacman_stub="${TEST_ARCH_BIN}/pacman"
cat >"${pacman_stub}" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${pacman_stub}"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
test_arch_arm_cleanup
# MEGA convergence has its own transaction tests; keep the vendor seam inert.
ensure_mega_vendor_repo() { :; }

BUNDLE="${TEST_ARCH_REPO_ROOT}/packages/arch.bundle"
SYSTEM_LIB="${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
[[ -r ${BUNDLE} ]] || test_arch_die 'packages/arch.bundle missing'

# --- Route: exactly one official-repo entry, filed as repo. ---
test_arch_assert_eq 1 "$(grep -cE '^repo "tailscale"(#| |$)' "${BUNDLE}")" \
  'bundle must carry exactly one repo "tailscale" entry'
if grep -Eq '^aur "tailscale"' "${BUNDLE}"; then
  test_arch_die 'tailscale must install from official extra, not the AUR'
fi

# --- Service: opportunistic enable in lib, no package-specific dot surface. ---
grep -Fq 'for service in tailscaled.service docker.service; do' "${SYSTEM_LIB}" \
  || test_arch_die 'tailscaled must stay in the opportunistic service loop'
# shellcheck disable=SC2016 # the expansion is the literal source text under test
grep -Fq 'arch_enable_system_unit "${service}" optional' "${SYSTEM_LIB}" \
  || test_arch_die 'tailscaled enable must stay optional (deselectable package)'
if grep -q 'tailscale' "${TEST_ARCH_REPO_ROOT}/dot"; then
  test_arch_die 'tailscale wiring stays in lib/arch-system.sh (no dot surface)'
fi

# --- Install: the real bundle's repo entries reach one pacman transaction. ---
# Repo-only copy: aur/appimage pathways have their own tests and would need
# network or yay, and this test is about the official-package install.
grep -E '^repo ' "${BUNDLE}" >"${TEST_ARCH_SANDBOX}/arch.bundle"
export DISTRO=arch
BUNDLE_FILE="${TEST_ARCH_SANDBOX}/arch.bundle"
grep -Eq '^repo "tailscale"' "${BUNDLE_FILE}" \
  || test_arch_die 'the repo-only derivation lost the tailscale entry'
install_packages >/dev/null
pacman_line="$(grep -m1 '^pacman -Syu ' "$(test_arch_calls_log)")"
[[ -n ${pacman_line} ]] || test_arch_die 'no pacman transaction ran'
grep -Eq '(^|[[:space:]])tailscale([[:space:]]|$)' <<<"${pacman_line}" \
  || test_arch_die 'the pacman transaction must install tailscale'

test_arch_assert_no_live_paths 'tailscale bundle route'
printf 'Tailscale stays an extra-package install with an opportunistic tailscaled enable.\n'
