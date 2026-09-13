#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# tests/test-arch-npm-user-prefix.sh — npm globals live in the user-owned
# ~/.local prefix: installs and postinstalls run as the user, never root.
#
# A root-owned /usr prefix needs sudo for every install and runs postinstalls
# as root, which leaves opencode's fetched binary unusable for the user (the
# stub that dies with "postinstall script was not run"). So installs never
# use sudo; the only sudo npm calls left are the one-time sweep removing
# stale root-owned copies, pinned at --prefix=/usr.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_arm_cleanup

DOT="${TEST_ARCH_REPO_ROOT}/dot"
[[ -r ${DOT} ]] || test_arch_die 'dot missing'

# Installs never use sudo: no `sudo npm install` anywhere in dot.
if grep -Eq 'sudo npm install' "${DOT}"; then
  test_arch_die 'npm installs must run as the user, never with sudo'
fi

# Every remaining sudo npm call is a root-sweep removal pinned at the system
# tree (--prefix=/usr); a bare sudo npm call could read the user's ~/.npmrc
# and hit ~/.local instead.
while IFS= read -r line; do
  [[ ${line} == *'--prefix=/usr'* ]] \
    || test_arch_die "sudo npm call without --prefix=/usr: ${line}"
done < <(grep -F 'sudo npm' "${DOT}" || true)
grep -Fq 'sudo npm' "${DOT}" || test_arch_die 'expected the root-sweep sudo npm removals'

# The user prefix converges to ~/.local, without elevation.
test_arch_assert_contains "${DOT}" 'ensure_npm_user_prefix' 'user-prefix helper exists'
test_arch_assert_contains "${DOT}" 'npm config set prefix' 'prefix converges via npm config'
test_arch_assert_contains "${DOT}" 'HOME}/.local' 'prefix target is the user-owned home-local tree'

# Both install verbs route through the prefix helper; npm-scripts additionally
# repairs a stub left by an earlier scripts-disabled install.
test_arch_assert_eq 4 "$(grep -c 'ensure_npm_user_prefix' "${DOT}")" 'prefix helper defined once and run on batch installs and both npm verbs'
test_arch_assert_contains "${DOT}" 'npm_scripts_repair_stub' 'stub repair helper exists'
test_arch_assert_contains "${DOT}" 'postinstall script was not run' 'repair triggers on the stub marker'
test_arch_assert_contains "${DOT}" 'npm rebuild -g --allow-scripts=' 'repair re-runs scripts as the user'

# The batch install migrates stale root-owned globals before installing.
test_arch_assert_contains "${DOT}" 'migrate_npm_root_to_user' 'root-to-user migration exists'
test_arch_assert_contains "${DOT}" '/usr/lib/node_modules/' 'migration looks at the system tree'

# Doctor asserts the prefix so drift fails loudly.
test_arch_assert_contains "${DOT}" 'Checking npm global prefix' 'doctor checks the npm prefix'

# Policy is documented where the verbs are defined.
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/docs/usage.md" "user-owned" 'usage documents the user prefix'
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/docs/usage.md" '.local' 'usage names the local prefix'
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/AGENTS.md" 'sudo npm install' 'AGENTS.md forbids sudo npm installs'

test_arch_assert_no_live_paths 'npm user-prefix policy'
printf 'npm globals stay user-owned: no sudo installs, prefix converged, root swept.\n'
