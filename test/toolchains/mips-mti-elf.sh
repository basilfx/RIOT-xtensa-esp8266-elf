# shellcheck shell=bash disable=SC2034
#
# Smoke test configuration of the MIPS toolchain, sourced by smoke-test.sh.
# Besides the common checks, it checks that the little-endian, soft-float
# multilibs are selected, that the hardware abstraction layer and boot code of
# libgloss are available, and that programs link for both the PIC32MX (MIPS32)
# and PIC32MZ (microMIPS) devices.
#
# The program is compiled and linked like RIOT does for the PIC32MX, using the
# UHI linker script and boot code of libgloss.

TOOLS+=(g++)

TARGET_CFLAGS=(-EL -mabi=32 -msoft-float -march=m4k -DTEST_CXX
               -DTEST_PRINTF_FLOAT -DTEST_PRINTF_LONG_LONG)

SOURCES=(main.c syscalls.c cxx.cpp mips.c)

NEWLIB_DEFINES=(_RETARGETABLE_LOCKING _WANT_REENT_SMALL _WANT_IO_LONG_LONG
                _WANT_IO_C99_FORMATS)

MACHINE="MIPS R3000"

GDB_REGISTER="ra"

# The startup code of libgloss provides the entry point. The exception handler
# of the boot context is not used, like RIOT does.
link_program() {
    local output="$1"
    shift

    "${BIN}-g++" "${TARGET_CFLAGS[@]}" -Wl,--gc-sections \
        -Wl,--defsym,__use_excpt_boot=0 -T uhi32.ld -T bootcode.ld \
        "$@" -lm -o "${output}"
}

toolchain_checks() {
    local elf="$1"

    check_output "multilib is little-endian soft-float" "^el/sof$" \
        "${BIN}-gcc" "${TARGET_CFLAGS[@]}" -print-multi-directory
    check_output "output is little-endian" "Data: +2's complement, little endian" \
        "${BIN}-readelf" -h "${elf}"
    check_output "output uses soft-float ABI" "FP ABI: +Soft float" \
        "${BIN}-readelf" -A "${elf}"

    check_output "floating point formatting is linked" " _dtoa_r$" \
        "${BIN}-nm" "${elf}"
    check_output "malloc uses retargetable locks" \
        " __retarget_lock_acquire_recursive$" "${BIN}-nm" "${elf}"
    check_output "boot code is linked" " __reset_vector$" \
        "${BIN}-nm" "${elf}"
    check_output "exception handler is linked" " __exception_entry$" \
        "${BIN}-nm" "${elf}"

    # The PIC32MZ has a microAptiv core, which RIOT runs in microMIPS mode.
    local CFLAGS=("${CFLAGS[@]/#-march=*/-march=m5101}" -mmicromips)
    local TARGET_CFLAGS=("${TARGET_CFLAGS[@]/#-march=*/-march=m5101}"
                         -mmicromips)

    check_output "multilib is microMIPS little-endian soft-float" \
        "^micromips/el/sof$" \
        "${BIN}-gcc" "${TARGET_CFLAGS[@]}" -print-multi-directory

    build_program "microMIPS" "${WORK_DIR}/micromips"

    check_output "output uses microMIPS" "Flags: .*, micromips" \
        "${BIN}-readelf" -h "${WORK_DIR}/micromips/test.elf"
}
