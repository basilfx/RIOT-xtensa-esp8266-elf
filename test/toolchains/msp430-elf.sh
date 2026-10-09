# shellcheck shell=bash disable=SC2034
#
# Smoke test configuration of the MSP430 toolchain, sourced by
# smoke-test.sh. Besides the common checks, it checks that the C library
# calls the reentrant system calls, that the startup code disables the
# watchdog timer and that programs link for both the MSP430 and MSP430X CPU.
#
# The program is compiled like RIOT compiles code for MSP430, including DWARF 2
# debug information. Floating point formatting is linked like the RIOT module
# printf_float does.

TARGET_CFLAGS=(-mmcu=msp430f1611 -gdwarf-2 -DTEST_PRINTF_FLOAT)

NEWLIB_DEFINES=(_NANO_FORMATTED_IO _NANO_MALLOC _WANT_REENT_SMALL _LITE_EXIT)

MACHINE="Texas Instruments msp430 microcontroller"

GDB_REGISTER="r15"

# The device linker scripts of TI are not part of the toolchain, so the program
# is linked using the linker script of the simulator. The address of the
# watchdog timer register is normally provided by the device linker script.
link_program() {
    local output="$1"
    shift

    "${BIN}-gcc" "${TARGET_CFLAGS[@]}" -msim -Wl,--defsym=WDTCTL=0x0120 \
        -Wl,--gc-sections -u _printf_float "$@" -lm -o "${output}"
}

toolchain_checks() {
    local elf="$1"

    check_output "floating point formatting is linked" " _dtoa_r$" \
        "${BIN}-nm" "${elf}"

    # Newlib provides the POSIX system calls, which call the reentrant system
    # calls of RIOT, but not the reentrant system calls themselves.
    check_output "C library provides read()" " T read$" \
        "${BIN}-nm" "$(compiler_file libc.a)"
    check_no_output "C library does not provide _read_r()" " T _read_r$" \
        "${BIN}-nm" "$(compiler_file libc.a)"

    check_output "startup code disables the watchdog timer" \
        "mov[[:space:]]+#23168,[[:space:]]+&0x0120" \
        "${BIN}-objdump" -d "${elf}"

    # The msp430f2618 has the MSP430X CPU, which uses a different multilib.
    local CFLAGS=("${CFLAGS[@]/#-mmcu=*/-mmcu=msp430f2618}")
    local TARGET_CFLAGS=("${TARGET_CFLAGS[@]/#-mmcu=*/-mmcu=msp430f2618}")

    build_program "MSP430X" "${WORK_DIR}/msp430x"
}
