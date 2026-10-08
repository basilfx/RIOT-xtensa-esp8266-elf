#!/usr/bin/env bash
#
# Smoke test of the ESP8266 toolchain. It checks that the host tools execute,
# that a minimal C and C++ program compiles and links against newlib and
# libstdc++, that the output targets the call0 ABI of the lx106 core and that
# GDB can read the result.
#
# Usage: smoke-test.sh [TOOLCHAIN_DIR]
#
# TOOLCHAIN_DIR defaults to /opt/esp/xtensa-esp8266-elf.

set -euo pipefail

readonly TARGET="xtensa-esp8266-elf"
readonly TOOLCHAIN_DIR="${1:-/opt/esp/${TARGET}}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src"
readonly SOURCE_DIR
readonly BIN="${TOOLCHAIN_DIR}/bin/${TARGET}"

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
trap 'rm -rf "${WORK_DIR}"' EXIT

FAILURES=0

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1" >&2
    FAILURES=$((FAILURES + 1))
}

# Prints the details of a failure, indented below the failure itself.
details() {
    local line

    while IFS= read -r line; do
        echo "       ${line}" >&2
    done <<< "$1"
}

# Runs a command quietly, and prints its output only if it fails.
check() {
    local description="$1"
    local output
    shift

    if output="$("$@" 2>&1)"; then
        pass "${description}"
    else
        fail "${description}"
        details "${output}"
    fi
}

# Checks that the output of a command contains the given pattern.
check_output() {
    local description="$1"
    local pattern="$2"
    local output
    shift 2

    if output="$("$@" 2>&1)" && grep -qE -- "${pattern}" <<< "${output}"; then
        pass "${description}"
    else
        fail "${description}"
        details "${output}"
    fi
}

echo "Testing toolchain in ${TOOLCHAIN_DIR}"

# Host tools
for tool in gcc g++ cpp as ld ar nm objcopy objdump readelf size strip gdb; do
    check "${tool} executes" "${BIN}-${tool}" --version
done

check_output "gcc targets ${TARGET}" "^${TARGET}\$" "${BIN}-gcc" -dumpmachine

# Newlib configuration
NEWLIB_H="${TOOLCHAIN_DIR}/${TARGET}/include/newlib.h"

for define in _RETARGETABLE_LOCKING _WANT_REENT_SMALL _WANT_IO_LONG_LONG \
              _WANT_IO_C99_FORMATS; do
    check_output "newlib defines ${define}" "^#define ${define} 1" \
        cat "${NEWLIB_H}"
done

# Compiling and linking
CFLAGS=(-Os -g -mlongcalls -ffunction-sections -fdata-sections -Wall -Wextra
        -Werror)

check "compile C" "${BIN}-gcc" "${CFLAGS[@]}" -std=c11 \
    -c "${SOURCE_DIR}/main.c" -o "${WORK_DIR}/main.o"
check "compile C system call stubs" "${BIN}-gcc" "${CFLAGS[@]}" -std=c11 \
    -c "${SOURCE_DIR}/syscalls.c" -o "${WORK_DIR}/syscalls.o"
check "compile C++" "${BIN}-g++" "${CFLAGS[@]}" -std=c++17 -fno-exceptions \
    -fno-rtti -c "${SOURCE_DIR}/cxx.cpp" -o "${WORK_DIR}/cxx.o"

# The default startup files and libraries of the compiler belong to the Xtensa
# simulator, which is not part of the toolchain. Therefore, the program is
# linked with its own entry point, but with the GCC startup files that provide
# the C++ runtime support.
crt() {
    "${BIN}-gcc" -print-file-name="$1"
}

check "link against newlib and libstdc++" "${BIN}-g++" -nostdlib \
    -Wl,--gc-sections -Wl,-e,_start \
    "$(crt crti.o)" "$(crt crtbegin.o)" \
    "${WORK_DIR}/main.o" "${WORK_DIR}/cxx.o" "${WORK_DIR}/syscalls.o" \
    -Wl,--start-group -lstdc++ -lc -lm -lgcc -Wl,--end-group \
    "$(crt crtend.o)" "$(crt crtn.o)" \
    -o "${WORK_DIR}/test.elf"

if [ ! -f "${WORK_DIR}/test.elf" ]; then
    echo "Skipping remaining tests, since linking failed" >&2
    exit 1
fi

# Output
check_output "output targets Xtensa" "Machine: +Tensilica Xtensa" \
    "${BIN}-readelf" -h "${WORK_DIR}/test.elf"
check_output "floating point formatting is linked" " _dtoa_r$" \
    "${BIN}-nm" "${WORK_DIR}/test.elf"
check_output "malloc uses retargetable locks" " __retarget_lock_acquire_recursive$" \
    "${BIN}-nm" "${WORK_DIR}/test.elf"

# The lx106 core does not support register windows, so the windowed ABI
# instructions must not appear in the compiled code nor in the libraries.
if "${BIN}-objdump" -d "${WORK_DIR}/test.elf" | \
        grep -qwE 'entry|retw(\.n)?|callx?(4|8|12)'; then
    fail "code uses call0 ABI"
else
    pass "code uses call0 ABI"
fi

# Debugger
GDB=("${BIN}-gdb" -nx -batch)

check_output "gdb reads line information" "Line [0-9]+ of \".*main\\.c\"" \
    "${GDB[@]}" -ex "info line main" "${WORK_DIR}/test.elf"
check_output "gdb sets breakpoints" "Breakpoint 1 at 0x[0-9a-f]+: file .*main\\.c" \
    "${GDB[@]}" -ex "break main" "${WORK_DIR}/test.elf"
check_output "gdb resolves types" "type = long" \
    "${GDB[@]}" -ex "ptype int32_t" "${WORK_DIR}/test.elf"
check_output "gdb disassembles code" "<\\+[0-9]+>:" \
    "${GDB[@]}" -ex "disassemble main" "${WORK_DIR}/test.elf"
check_output "gdb knows the lx106 registers" "^ +a15 +15 " \
    "${GDB[@]}" -ex "maintenance print registers" "${WORK_DIR}/test.elf"

# Host dependencies
if command -v ldd > /dev/null; then
    dependencies="$(
        find "${TOOLCHAIN_DIR}/bin" "${TOOLCHAIN_DIR}/libexec" -type f \
            -perm -u+x -exec ldd {} \; 2> /dev/null | grep '=>' || true
    )"
    unexpected="$(
        awk '{ print $1 }' <<< "${dependencies}" |
        grep -vE '^(linux-vdso|libc|libm|libstdc\+\+|libgcc_s|libncursesw|libtinfo)\.so' |
        sort -u || true
    )"
    missing="$(grep 'not found' <<< "${dependencies}" | sort -u || true)"

    if [ -z "${unexpected}" ]; then
        pass "host tools only depend on common libraries"
    else
        fail "host tools only depend on common libraries"
        details "${unexpected}"
    fi

    if [ -z "${missing}" ]; then
        pass "host libraries are present"
    else
        fail "host libraries are present"
        details "${missing}"
    fi
fi

if [ "${FAILURES}" -ne 0 ]; then
    echo "${FAILURES} test(s) failed" >&2
    exit 1
fi

echo "All tests passed"
