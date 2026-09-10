#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# install_packages re-asserts the pinned [DEB_Arch_Extra] section AFTER the
# repo transaction. MEGA's own megasync package rewrites pacman.conf from its
# post_install, replacing the pinned block with its weaker
# 'SigLevel = Required TrustedOnly'; the pre-transaction setup alone would
# leave a single init/arch-setup drifted and arch-check red. This exercises
# the real module writer through the real install_packages with a stubbed
# pacman that performs exactly the vendor's rewrite. No network, no live
# pacman.conf: the setup seam points at a sandbox copy.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_passthrough_sudo
test_arch_stub_command yay

# Stub pacman: log, and on -Syu reproduce the vendor post_install byte for
# byte on the sandbox config, then succeed.
pacman_stub="${TEST_ARCH_BIN}/pacman"
cat >"${pacman_stub}" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\${1:-}" == -Syu ]]; then
  conf="${TEST_ARCH_SANDBOX}/pacman.conf"
  sed -n '1h;1!H;\${g;s/\n###REPO for MEGA###\n.*###END REPO for MEGA###//;p;}' -i "\${conf}"
  printf '\n###REPO for MEGA###\n[DEB_Arch_Extra]\nSigLevel = Required TrustedOnly\nServer = https://mega.nz/linux/repo/Arch_Extra/\$arch\n###END REPO for MEGA###\n' >>"\${conf}"
fi
EOF
chmod 755 -- "${pacman_stub}"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
test_arch_arm_cleanup
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-mega.sh"

export DISTRO=arch
BUNDLE_FILE="${TEST_ARCH_SANDBOX}/arch.bundle"
printf 'repo "megasync"\nrepo "thunar-megasync"\n' >"${BUNDLE_FILE}"

conf="${TEST_ARCH_SANDBOX}/pacman.conf"
printf '[options]\nColor\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"${conf}"

# The module's setup takes the config path as its optional test seam; the
# dot hook calls it with the production default, so route it at the sandbox.
eval "$(declare -f arch_mega_setup_vendor_repo | sed '1s/arch_mega_setup_vendor_repo/arch_mega_setup_vendor_repo_real/')"
arch_mega_setup_vendor_repo() { arch_mega_setup_vendor_repo_real "${conf}"; }
# Trust already established: this path must do no network or gpg work.
arch_mega_key_trusted() { return 0; }

install_packages >/dev/null

arch_mega_vendor_repo_configured "${conf}" \
  || test_arch_die 'a single install_packages run must leave the pinned MEGA section'
grep -q 'SigLevel = Required DatabaseRequired' "${conf}" \
  || test_arch_die 'the vendor replacement must be re-converged to the pinned SigLevel'
grep -q 'SigLevel = Required TrustedOnly' "${conf}" \
  && test_arch_die 'the vendor weaker SigLevel survived the run'
test_arch_assert_eq 1 "$(grep -cE '^\[DEB_Arch_Extra\][[:space:]]*$' "${conf}")" 'exactly one pinned section'
test_arch_assert_eq 1 "$(grep -cF '###REPO for MEGA###' "${conf}")" 'exactly one vendor begin marker'

# The repo transaction ran between the two setup passes.
grep -q '^pacman -Syu ' "$(test_arch_calls_log)" \
  || test_arch_die 'the sandbox transaction must have run'
# Idempotent: a converged machine rewrites nothing on the next run.
cp -- "${conf}" "${conf}.once"
install_packages >/dev/null
cmp -s -- "${conf}" "${conf}.once" \
  || test_arch_die 'a converged install_packages run must be a fixed point'

test_arch_assert_no_live_paths 'mega post-install convergence'
printf 'A single install run leaves the MEGA vendor section pinned despite the vendor post_install.\n'
