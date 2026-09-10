#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_limine_apply_appearance_to_config (lib/arch-limine.sh) preserves
# every boot entry and is byte-for-byte idempotent. Pass-through sudo lets
# the real findmnt answer for temp paths; nothing live is mounted or read.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-limine.sh"

test_arch_make_sandbox
test_arch_stub_passthrough_sudo

WORK="${TEST_ARCH_SANDBOX}/limine with spaces"
mkdir -p -- "${WORK}"
APPEARANCE="${TEST_ARCH_REPO_ROOT}/system/arch/limine/appearance.conf"
[[ -r ${APPEARANCE} ]] || test_arch_die 'missing system/arch/limine/appearance.conf template'
cat >"${WORK}/limine.conf" <<'EOF'
# Timeout
timeout: 5
term_foreground: deadbe

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID-aaa rw

/Arch Linux (fallback)
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=UUID-aaa rw initrd=fallback
EOF
CONFIG="${WORK}/limine.conf"
test_arch_assert_eq 2 "$(arch_limine_count_boot_entries "${CONFIG}")" 'fixture carries two boot entries'

arch_limine_apply_appearance_to_config "${CONFIG}" "${APPEARANCE}" >/dev/null
cp -- "${CONFIG}" "${WORK}/after-first.conf"
arch_limine_apply_appearance_to_config "${CONFIG}" "${APPEARANCE}" >/dev/null

# Idempotent: the second run changes nothing.
cmp -s -- "${WORK}/after-first.conf" "${CONFIG}" \
  || test_arch_die 'second appearance run was not byte-identical'
# Boot entries preserved; stale keys replaced by the palette block.
test_arch_assert_eq 2 "$(arch_limine_count_boot_entries "${CONFIG}")" 'boot entry count preserved'
test_arch_assert_contains "${CONFIG}" 'path: boot():/vmlinuz-linux' 'kernel path preserved'
test_arch_assert_contains "${CONFIG}" 'root=UUID-aaa' 'cmdline preserved'
test_arch_assert_contains "${CONFIG}" '# >>> dotfiles appearance >>>' 'managed block marked'
if grep -q 'term_foreground: deadbe' "${CONFIG}"; then
  test_arch_die 'stale appearance key survived outside the managed block'
fi
# One backup of the first write, never rewritten.
[[ -f ${CONFIG}.dotfiles-backup ]] || test_arch_die 'first write kept no backup'
test_arch_assert_contains "${CONFIG}.dotfiles-backup" 'term_foreground: deadbe' 'backup keeps pre-palette contents'

# A linked config is refused, never followed.
ln -s -- "${CONFIG}" "${WORK}/linked.conf"
set +e
( arch_limine_apply_appearance_to_config "${WORK}/linked.conf" "${APPEARANCE}" >/dev/null 2>&1 )
linked_status=$?
set -e
((linked_status != 0)) || test_arch_die 'appearance applied through a symlink'

# An appearance that smuggles boot-entry lines is refused, not deployed.
printf '/Evil Entry\n' >"${WORK}/evil-appearance.conf"
cp -- "${WORK}/after-first.conf" "${WORK}/evil.conf"
set +e
( arch_limine_apply_appearance_to_config "${WORK}/evil.conf" "${WORK}/evil-appearance.conf" >/dev/null 2>&1 )
evil_status=$?
set -e
((evil_status != 0)) || test_arch_die 'entry-smuggling appearance was deployed'
if grep -q 'Evil Entry' "${WORK}/evil.conf"; then
  test_arch_die 'refused run still modified the config'
fi

# Pure entry parsers: old File(...) and current bare-path renderings.
OLD_ENTRY='Boot0001* Limine HD(1,GPT,8a27-0000,0x800,0x200000)/File(\EFI\BOOT\BOOTX64.EFI)'
NEW_ENTRY='Boot0002* Arch Linux Limine Bootloader HD(1,GPT,8a27-0000,0x800,0x200000)/\EFI\BOOT\BOOTX64.EFI'
test_arch_assert_eq '\EFI\BOOT\BOOTX64.EFI' "$(arch_limine_entry_path "${OLD_ENTRY}")" 'old File() path parsed'
test_arch_assert_eq '\EFI\BOOT\BOOTX64.EFI' "$(arch_limine_entry_path "${NEW_ENTRY}")" 'new bare path parsed'
test_arch_assert_eq 'Limine' "$(arch_limine_entry_label "${OLD_ENTRY}")" 'label parsed without device path'
test_arch_assert_eq 'Arch Linux Limine Bootloader' "$(arch_limine_entry_label "${NEW_ENTRY}")" 'archinstall label parsed'

# No remounts happened (tmpfs sandbox is already rw) and no live paths.
test_arch_assert_not_called mount 'no remount on a writable mount'
test_arch_assert_not_called efibootmgr 'theming never touches firmware entries'
test_arch_assert_no_live_paths 'limine theming'
printf 'Limine theming is idempotent and preserves boot entries.\n'
