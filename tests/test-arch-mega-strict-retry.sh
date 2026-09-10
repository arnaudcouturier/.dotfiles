#!/usr/bin/env bash
# First install and retry must run with errexit enabled, like dot init.
# shellcheck disable=SC1091
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${TEST_DIR}/lib/test-arch-isolation.sh"
test_arch_make_sandbox
source "${TEST_ARCH_REPO_ROOT}/lib/arch-mega.sh"
log_ok() { :; }
log_warn() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null || die "Missing $1"; }
# Trust already succeeded before an interrupted first config write.
arch_mega_key_trusted() { return 0; }
uname() { printf 'x86_64\n'; }
# Only sandbox file copies are permitted; never invoke real sudo/network.
sudo() {
  case "$1" in cp | install) ;; *) die "Unexpected sudo command: $*" ;; esac
  [[ ${*: -1} == "${TEST_ARCH_SANDBOX}/"* ]] || die 'Non-sandbox destination'
  "$@"
}
curl() { die 'Unexpected network'; }
# sudo is itself a shell stub above and rejects gpg before dispatch.
# shellcheck disable=SC2032
gpg() { die 'Unexpected keyring access'; }
config="${TEST_ARCH_SANDBOX}/pacman.conf"
printf '[options]\n[core]\n' >"${config}"
cp -- "${config}" "${config}.original"
# Do not wrap setup in an if/|| or disable errexit: that hid the failure.
arch_mega_setup_vendor_repo "${config}"
arch_mega_vendor_repo_configured "${config}"
cp -- "${config}" "${config}.once"
arch_mega_setup_vendor_repo "${config}"
cmp -- "${config}" "${config}.once"
cmp -- "${config}.original" "${config}.dotfiles-backup"
printf 'MEGA first config write and retry pass under strict errexit.\n'
