#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# MEGA repo hook integration (dot-side only): the vendor module file belongs
# to the arch-apps agent, so this test never creates it. Covers the lazy
# Arch-gated hook on every package pathway (one install_packages seam plus
# the package-add gate), read-only arch-check registration with no doctor
# mutation, Fedora zero-effect, and no sudo from the hook itself.
# Live-key evidence lives in the module contract, not here: no network, no
# keyring writes, sudo fail-closed.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_command sudo

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
test_arch_arm_cleanup

# --- Helpers exist with the contracted three-function vocabulary. ---
for fn in arch_mega_is_loaded arch_source_mega_quiet bundle_requests_mega_repo ensure_mega_vendor_repo arch_mega_ensure_for_package; do
  declare -F "${fn}" >/dev/null 2>&1 || test_arch_die "missing hook helper ${fn}"
done
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/dot" 'ARCH_MEGA_MODULE=' 'dot must pin the module path'
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/dot" 'arch_mega_setup_vendor_repo' 'dot must call the setup API'
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/dot" 'arch_mega_verify_vendor_repo' 'dot must call the verify API'

# --- Fedora: zero effect before any sourcing, sudo, or network. ---
export DISTRO=fedora
ensure_mega_vendor_repo >/dev/null
arch_mega_ensure_for_package repo megasync >/dev/null
test_arch_assert_not_called sudo 'Fedora hook path never elevates'

# --- Arch module presence: missing warn-skips; landed pins the API. ---
export DISTRO=arch
if [[ ! -r ${TEST_ARCH_REPO_ROOT}/lib/arch-mega.sh ]]; then
  # Transitional: module not yet landed.
  ensure_out="$(ensure_mega_vendor_repo 2>&1)"
  grep -Fq 'has not landed' <<<"${ensure_out}" \
    || test_arch_die 'missing module must warn-skip naming the fix'
  test_arch_assert_not_called sudo 'missing-module skip never elevates'
else
  # Landed (apps-owned, read-only here): pin the contracted API and prove
  # the real file sources cleanly with no side effects.
  MEGA_MOD="${TEST_ARCH_REPO_ROOT}/lib/arch-mega.sh"
  for fn in arch_mega_vendor_repo_configured arch_mega_setup_vendor_repo arch_mega_verify_vendor_repo; do
    grep -Eq "^${fn}[(][)]" "${MEGA_MOD}" \
      || test_arch_die "module API drift: missing ${fn}"
  done
  grep -Fq 'megasync thunar-megasync' "${MEGA_MOD}" \
    || test_arch_die 'module package list drifted from the gated names'
  grep -Fq 'B01C811880480C854C73EC7E1A664B787094A482' "${MEGA_MOD}" \
    || test_arch_die 'module key fingerprint drifted'
  (
    unset -f arch_mega_setup_vendor_repo arch_mega_verify_vendor_repo 2>/dev/null || true
    arch_source_mega_quiet >/dev/null || exit 1
    arch_mega_is_loaded || exit 1
  ) || test_arch_die 'real module must source cleanly with no side effects'
  test_arch_assert_not_called sudo 'module sourcing never elevates'
fi

# --- Arch, module present (stubbed interface): setup runs, hook adds no sudo. ---
arch_mega_setup_vendor_repo() {
  printf 'mega-setup\n' >>"$(test_arch_calls_log)"
}
arch_mega_verify_vendor_repo() {
  printf 'mega-verify\n' >>"$(test_arch_calls_log)"
  return 0
}
arch_mega_is_loaded || test_arch_die 'stubbed interface must count as loaded'
ensure_mega_vendor_repo >/dev/null
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  || test_arch_die 'ensure did not call the module setup'
test_arch_assert_not_called sudo 'hook itself never elevates (module owns sudo)'

# --- Package-add gate: only the two vendor names trigger setup. ---
: >"$(test_arch_calls_log)"
arch_mega_ensure_for_package repo megasync >/dev/null
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  || test_arch_die 'megasync single-add must ensure the repo'
: >"$(test_arch_calls_log)"
arch_mega_ensure_for_package repo thunar-megasync >/dev/null
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  || test_arch_die 'thunar-megasync single-add must ensure the repo'
: >"$(test_arch_calls_log)"
arch_mega_ensure_for_package repo fish >/dev/null
arch_mega_ensure_for_package aur megasync >/dev/null
test_arch_assert_not_called sudo 'unrelated adds stay silent'
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  && test_arch_die 'unrelated package names must not trigger repo setup'
export DISTRO=fedora
arch_mega_ensure_for_package repo megasync >/dev/null
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  && test_arch_die 'Fedora package adds must not trigger repo setup'
export DISTRO=arch

# --- Demand coupling: validate first, configure only when requested. ---
OLD_BUNDLE_FILE=${BUNDLE_FILE:-}
BAD_BUNDLE="${TEST_ARCH_SANDBOX}/bad.bundle"
printf 'frobnicate "nope"\n' >"${BAD_BUNDLE}"
BUNDLE_FILE="${BAD_BUNDLE}"
: >"$(test_arch_calls_log)"
set +e
( install_packages >/dev/null 2>&1 )
bad_status=$?
set -e
((bad_status != 0)) || test_arch_die 'invalid bundle installed silently'
grep -q '^mega-setup$' "$(test_arch_calls_log)" \
  && test_arch_die 'invalid bundle mutated the vendor repo before validation'

GOOD_BUNDLE="${TEST_ARCH_SANDBOX}/good.bundle"
printf 'repo "fish"\n' >"${GOOD_BUNDLE}"
BUNDLE_FILE="${GOOD_BUNDLE}"
parse_bundle
if bundle_requests_mega_repo; then
  test_arch_die 'plain bundle must not request the vendor repo'
fi
printf 'repo "fish"\nrepo "megasync"\n' >"${GOOD_BUNDLE}"
parse_bundle
bundle_requests_mega_repo >/dev/null \
  || test_arch_die 'megasync bundle must request the vendor repo'
printf 'repo "thunar-megasync"\n' >"${GOOD_BUNDLE}"
parse_bundle
bundle_requests_mega_repo >/dev/null \
  || test_arch_die 'thunar-megasync bundle must request the vendor repo'
printf 'aur "megasync"\n' >"${GOOD_BUNDLE}"
parse_bundle
if bundle_requests_mega_repo; then
  test_arch_die 'AUR verb must not request the vendor repo'
fi
BUNDLE_FILE="${OLD_BUNDLE_FILE}"

# --- Seams (static, narrow): validated bundle gates setup before the
# --- read-only check registration, and no doctor mutation. ---
dot_src="${TEST_ARCH_REPO_ROOT}/dot"
# Demand-gated order inside install_packages: parse/validate, then setup
# only when requested, then the first repo transaction.
python3 - "${dot_src}" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
fn = src.split('install_packages()', 1)[1].split(chr(10) + '}' + chr(10), 1)[0]
parse_i = fn.index('parse_bundle')
gate_i = fn.index('bundle_requests_mega_repo')
setup_i = fn.index('ensure_mega_vendor_repo')
syu_i = fn.index('pacman -Syu --needed --noconfirm')
assert parse_i < gate_i < setup_i < syu_i, (parse_i, gate_i, setup_i, syu_i)
# The vendor's megasync post_install rewrites [DEB_Arch_Extra] during the
# transaction, so the setup must also run AFTER it: one convergence before
# (so pacman can resolve the packages) and one after (repairing the
# vendor's weaker replacement) leave a single init run converged.
reassert_i = fn.rindex('ensure_mega_vendor_repo')
assert syu_i < reassert_i, (syu_i, reassert_i)
PYEOF
grep -Fq 'if bundle_requests_mega_repo; then' "${dot_src}" \
  || test_arch_die 'install_packages must gate repo setup on parsed demand'
# shellcheck disable=SC2016 # single quotes are intentional: literal ${verb}/${name} match against dot source
grep -q 'arch_mega_ensure_for_package "${verb}" "${name}"' "${dot_src}" \
  || test_arch_die 'package add must gate MEGA names before install'
# The check registration lives in the system step and stays read-only.
grep -Fq 'arch_mega_verify_vendor_repo || failed=1' "${dot_src}" \
  || test_arch_die 'arch-check must report mega verify status'
awk '/^cmd_doctor\(\)/,/^cmd_package_add\(\)/' "${dot_src}" | grep -q 'arch_mega' \
  && test_arch_die 'doctor must not gain MEGA mutation surface'
awk '/^cmd_arch_check\(\)/,/^main\(\)/' "${dot_src}" | grep -q 'arch_mega_setup_vendor_repo' \
  && test_arch_die 'arch-check must never run repo setup (read-only)'

test_arch_assert_not_called sudo 'mega hook integration never elevates directly'
test_arch_assert_no_live_paths 'mega hook integration'
printf 'MEGA hook stays lazy, Arch-gated, ordered before installs, and read-only in checks.\n'
