#!/usr/bin/env bash
# Run the Arch desktop test suite. Every tests/test-*.sh file runs in its own
# process with a sandboxed HOME and stubbed executables, so no test can touch
# live /etc, /boot, or the real HOME. No test uses sudo, the network, or any
# path outside its temp sandbox and this repo checkout: a fresh clone is
# sufficient, with no /tmp assets, reports, or downloads.
#
# Dependencies (all default Fedora Workstation helpers, nothing to build):
#   bash 5+, git, jq, stow, python3 (stdlib only, strict patch emulation),
#   plus coreutils/findutils (mktemp, find, sort, sha256sum, cmp, realpath).
# Missing pieces fail fast below with an install hint; individual tests
# additionally SKIP with a SEAM PENDING line naming what is absent.
set -euo pipefail

TESTS_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
readonly TESTS_DIR

missing=()
for dep in git jq stow python3; do
  command -v "${dep}" >/dev/null 2>&1 || missing+=("${dep}")
done
if ((${#missing[@]} > 0)); then
  printf 'tests/run.sh: missing test dependencies: %s\n' "${missing[*]}" >&2
  printf 'install them, then rerun (Fedora: sudo dnf install -y %s)\n' "${missing[*]}" >&2
  exit 2
fi

pass=0
fail=0
skip=0
failed_names=()
skipped_names=()

while IFS= read -r test_file; do
  name="$(basename -- "${test_file}")"
  # Each test owns its process: one test's exports or traps never leak.
  set +e
  "${test_file}" >"${test_file}.out" 2>&1
  status=$?
  set -e
  if ((status == 0)); then
    pass=$((pass + 1))
    printf 'PASS %s\n' "${name}"
  elif ((status == 3)); then
    skip=$((skip + 1))
    skipped_names+=("${name}")
    printf 'SKIP %s (%s)\n' "${name}" "$(head -n 1 "${test_file}.out")"
  else
    fail=$((fail + 1))
    failed_names+=("${name}")
    printf 'FAIL %s (exit %d)\n' "${name}" "${status}"
    cat -- "${test_file}.out"
  fi
  rm -f -- "${test_file}.out"
done < <(find "${TESTS_DIR}" -maxdepth 1 -name 'test-*.sh' | sort)

printf '\n%d passed, %d failed, %d skipped\n' "${pass}" "${fail}" "${skip}"
if ((${#skipped_names[@]} > 0)); then
  printf 'skipped: %s\n' "${skipped_names[*]}"
fi
if ((fail > 0)); then
  printf 'failed: %s\n' "${failed_names[*]}"
  exit 1
fi
