#!/usr/bin/env bash
# Isolation helpers for the Arch desktop test suite. Sourced, not executed.
# Every test calls test_arch_make_sandbox first: HOME points at a temp dir,
# a stub bin directory leads PATH, and every stub logs its invocations so
# tests can prove no sudo, network, or live-path mutation happened.
#
# Tests need only bash and coreutils. Live /etc, /boot, and the real HOME
# are never touched: implementation seams under test must take explicit
# paths (never hardcoded live roots) and perform no elevation internally.

# Guard against double-sourcing.
[[ -n ${TEST_ARCH_ISOLATION_LOADED:-} ]] && return 0
TEST_ARCH_ISOLATION_LOADED=1

TEST_ARCH_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ARCH_REPO_ROOT="$(cd -- "${TEST_ARCH_LIB_DIR}/../.." && pwd)"
readonly TEST_ARCH_LIB_DIR TEST_ARCH_REPO_ROOT
export TEST_ARCH_REPO_ROOT TEST_ARCH_LIB_DIR TEST_ARCH_LIVE_HOME

# The real HOME, captured before any sandboxing. Tests fail if HOME still
# equals this after test_arch_make_sandbox.
TEST_ARCH_LIVE_HOME="${HOME}"
readonly TEST_ARCH_LIVE_HOME

TEST_ARCH_SANDBOX=''
TEST_ARCH_HOME=''
TEST_ARCH_BIN=''

test_arch_die() {
  printf 'test-arch-isolation: %s\n' "$*" >&2
  exit 1
}

# Create the sandbox: fresh temp root, HOME, and stub bin. Must be the
# first call in every test file.
test_arch_make_sandbox() {
  [[ -z ${TEST_ARCH_SANDBOX} ]] || test_arch_die 'sandbox already created'
  TEST_ARCH_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/arch-desktop-test.XXXXXX")" \
    || test_arch_die 'cannot create sandbox dir'
  TEST_ARCH_HOME="${TEST_ARCH_SANDBOX}/home"
  TEST_ARCH_BIN="${TEST_ARCH_SANDBOX}/bin"
  mkdir -p -- "${TEST_ARCH_HOME}" "${TEST_ARCH_BIN}" \
    || test_arch_die 'cannot create sandbox subdirs'
  : >"${TEST_ARCH_SANDBOX}/calls.log"
  export HOME="${TEST_ARCH_HOME}"
  export PATH="${TEST_ARCH_BIN}:${PATH}"
  test_arch_arm_cleanup
}

# (Re)arm sandbox cleanup on EXIT. Sourcing ./dot replaces the EXIT trap
# (its own cleanup_dot), so tests that source anything after
# test_arch_make_sandbox must call this again once sourcing is done.
test_arch_arm_cleanup() {
  [[ -n ${TEST_ARCH_SANDBOX} ]] || test_arch_die 'no sandbox to protect'
  # shellcheck disable=SC2064
  trap "rm -rf -- '${TEST_ARCH_SANDBOX}'" EXIT
}

test_arch_calls_log() {
  printf '%s/calls.log' "${TEST_ARCH_SANDBOX}"
}

# Create a stub executable NAME. The stub appends "NAME args..." to the
# calls log, then exits with TEST_ARCH_STUB_EXIT (default 99) so an
# unexpected privileged or mutating call fails the test loudly instead of
# running the real command.
test_arch_stub_command() {
  local name=$1
  [[ -n ${TEST_ARCH_SANDBOX} ]] || test_arch_die 'make the sandbox before stubbing'
  # The log path is baked in, so the stub needs no runtime environment.
  cat >"${TEST_ARCH_BIN}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "${name}" "\$*" >>"$(test_arch_calls_log)"
exit \${TEST_ARCH_STUB_EXIT:-99}
EOF
  chmod 755 -- "${TEST_ARCH_BIN}/${name}"
}

# Turn an existing stub into one that prints OUTPUT then exits 0, still
# logging the call. Used for lspci, findmnt, systemctl query stubs.
test_arch_stub_output() {
  local name=$1 output_file=$2
  cat >"${TEST_ARCH_BIN}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "${name}" "\$*" >>"$(test_arch_calls_log)"
cat -- "${output_file}"
EOF
  chmod 755 -- "${TEST_ARCH_BIN}/${name}"
}

# Pass-through sudo stub: logs the call, then executes the command as the
# current user. Use only with temp paths: it proves elevation routing
# (every privileged write goes through sudo) without touching live roots.
test_arch_stub_passthrough_sudo() {
  [[ -n ${TEST_ARCH_SANDBOX} ]] || test_arch_die 'make the sandbox before stubbing'
  cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exec "\$@"
EOF
  chmod 755 -- "${TEST_ARCH_BIN}/sudo"
}

test_arch_assert_eq() {
  local expected=$1 actual=$2 label=$3
  [[ ${expected} == "${actual}" ]] \
    || test_arch_die "${label}: expected <${expected}>, got <${actual}>"
}

test_arch_assert_contains() {
  local file=$1 literal=$2 label=$3
  grep -Fq -- "${literal}" "${file}" \
    || test_arch_die "${label}: <${file}> lacks <${literal}>"
}

test_arch_assert_not_called() {
  local name=$1 label=$2
  grep -q -- "^${name} " "$(test_arch_calls_log)" \
    && test_arch_die "${label}: stub ${name} was called but must not be"
  return 0
}

# Prove the sandbox held: HOME is temp, and no stub saw a live root path
# (/etc/, /boot, or the real HOME) in its arguments.
test_arch_assert_no_live_paths() {
  local label=$1 log content stripped hit
  log="$(test_arch_calls_log)"
  [[ ${HOME} != "${TEST_ARCH_LIVE_HOME}" ]] \
    || test_arch_die "${label}: HOME still points at the live home"
  [[ ${HOME} == "${TEST_ARCH_SANDBOX}"/* ]] \
    || test_arch_die "${label}: HOME is outside the sandbox"
  # Reading repo templates is legitimate; strip those paths before
  # hunting for live /etc, /boot, or real-HOME arguments.
  content="$(cat -- "${log}")"
  stripped="${content//${TEST_ARCH_REPO_ROOT}/REPO}"
  hit="$(grep -E -- '(^| )(/(etc|boot)(/|$)|'"${TEST_ARCH_LIVE_HOME}"')' <<<"${stripped}" | head -n 3 || true)"
  [[ -z ${hit} ]] || test_arch_die "${label}: a stub saw a live path: ${hit}"
  return 0
}

# Skip helper for seams that do not exist yet. Prints the seam name on
# stdout (the runner shows it) and exits 3.
test_arch_skip_unless_seam() {
  local seam_file=$1 seam_desc=$2
  if [[ ! -r ${seam_file} ]]; then
    printf 'SEAM PENDING: %s (needs %s)\n' "${seam_desc}" "${seam_file}"
    exit 3
  fi
}
