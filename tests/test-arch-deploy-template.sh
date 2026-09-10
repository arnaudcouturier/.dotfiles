#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_deploy_system_template (lib/arch-guard.sh) deploys through sudo,
# skips identical targets, refuses symlinks, and backs up once. Uses a
# pass-through sudo stub so every privileged write lands on temp paths.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"

test_arch_make_sandbox
test_arch_stub_passthrough_sudo

WORK="${TEST_ARCH_SANDBOX}/deploy dir with spaces"
mkdir -p -- "${WORK}/etc/greetd"
TEMPLATE="${TEST_ARCH_REPO_ROOT}/system/arch/greetd/config.toml"
[[ -r ${TEMPLATE} ]] || test_arch_die 'missing system/arch/greetd/config.toml template'
TARGET="${WORK}/etc/greetd/config.toml"

# Fresh deploy lands byte-identical, routed through sudo.
arch_deploy_system_template "${TEMPLATE}" "${TARGET}" >/dev/null
cmp -s -- "${TEMPLATE}" "${TARGET}" || test_arch_die 'fresh deploy differs from template'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo install' 'deploy elevates through sudo'

# Identical redeploy is a no-op: no backup, no reinstall.
: >"$(test_arch_calls_log)"
arch_deploy_system_template "${TEMPLATE}" "${TARGET}" >/dev/null
[[ ! -e ${TARGET}.dotfiles-backup ]] || test_arch_die 'identical redeploy created a backup'
if grep -q 'sudo install.*config.toml$' "$(test_arch_calls_log)"; then
  test_arch_die 'identical redeploy rewrote the target'
fi

# A diverged target is backed up exactly once, then replaced.
printf '# local login-screen tweak\n' >>"${TARGET}"
arch_deploy_system_template "${TEMPLATE}" "${TARGET}" >/dev/null
test_arch_assert_contains "${TARGET}.dotfiles-backup" 'local login-screen tweak' 'backup keeps replaced contents'
printf '# second tweak\n' >>"${TARGET}"
arch_deploy_system_template "${TEMPLATE}" "${TARGET}" >/dev/null
test_arch_assert_contains "${TARGET}.dotfiles-backup" 'local login-screen tweak' 'first backup is never overwritten'
cmp -s -- "${TEMPLATE}" "${TARGET}" || test_arch_die 'redeploy differs from template'

# A symlinked target is refused, never followed.
ln -s -- "${TARGET}" "${WORK}/linked.toml"
set +e
( arch_deploy_system_template "${TEMPLATE}" "${WORK}/linked.toml" >/dev/null 2>&1 )
linked_status=$?
set -e
((linked_status != 0)) || test_arch_die 'deploy followed a symlinked target'

# A symlinked parent directory is refused too.
mkdir -p -- "${WORK}/real.d"
ln -s -- "${WORK}/real.d" "${WORK}/link.d"
set +e
( arch_deploy_system_template "${TEMPLATE}" "${WORK}/link.d/config.toml" >/dev/null 2>&1 )
parent_status=$?
set -e
((parent_status != 0)) || test_arch_die 'deploy wrote through a symlinked parent'

# A relative target is refused: system paths must be absolute.
set +e
( arch_deploy_system_template "${TEMPLATE}" 'etc/greetd/config.toml' >/dev/null 2>&1 )
relative_status=$?
set -e
((relative_status != 0)) || test_arch_die 'deploy accepted a relative target'

# A missing template dies before touching the target.
set +e
( arch_deploy_system_template "${WORK}/no-such-template.toml" "${WORK}/etc/greetd/other.toml" >/dev/null 2>&1 )
missing_status=$?
set -e
((missing_status != 0)) || test_arch_die 'deploy accepted a missing template'
[[ ! -e ${WORK}/etc/greetd/other.toml ]] || test_arch_die 'missing template created a target'

test_arch_assert_no_live_paths 'template deploy'
printf 'Template deploy is idempotent, symlink-safe, and backs up once.\n'
