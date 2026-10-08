# shellcheck shell=bash disable=SC2034
#
# Smoke test configuration of the ESP8266 toolchain, sourced by
# smoke-test.sh. Besides the common checks, it checks that C++ code links
# against libstdc++, that newlib supports the formatting of floating point and
# long long values, and that the output targets the call0 ABI of the lx106
# core.

TOOLS+=(g++)

TARGET_CFLAGS=(-mlongcalls -DTEST_CXX -DTEST_PRINTF_FLOAT
               -DTEST_PRINTF_LONG_LONG)

SOURCES=(main.c syscalls.c start.c cxx.cpp)

NEWLIB_DEFINES=(_RETARGETABLE_LOCKING _WANT_REENT_SMALL _WANT_IO_LONG_LONG
                _WANT_IO_C99_FORMATS)

MACHINE="Tensilica Xtensa Processor"

GDB_REGISTER="a15"

# The default startup files and libraries of the compiler belong to the Xtensa
# simulator, which is not part of the toolchain. Therefore, the program is
# linked with its own entry point, but with the GCC startup files that provide
# the C++ runtime support.
link_program() {
    local output="$1"
    shift

    "${BIN}-g++" -nostdlib -Wl,--gc-sections -Wl,-e,_start \
        "$(compiler_file crti.o)" "$(compiler_file crtbegin.o)" \
        "$@" \
        -Wl,--start-group -lstdc++ -lc -lm -lgcc -Wl,--end-group \
        "$(compiler_file crtend.o)" "$(compiler_file crtn.o)" \
        -o "${output}"
}

toolchain_checks() {
    local elf="$1"

    check_output "floating point formatting is linked" " _dtoa_r$" \
        "${BIN}-nm" "${elf}"
    check_output "malloc uses retargetable locks" \
        " __retarget_lock_acquire_recursive$" "${BIN}-nm" "${elf}"

    # The lx106 core does not support register windows, so the windowed ABI
    # instructions must not appear in the compiled code nor in the libraries.
    check_no_output "code uses call0 ABI" \
        $'\t(entry|retw(\\.n)?|callx?(4|8|12))\\b' \
        "${BIN}-objdump" -d "${elf}"
}
