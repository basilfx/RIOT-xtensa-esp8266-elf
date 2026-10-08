#!/usr/bin/env bash
#
# Smoke test of a toolchain. It checks that the host tools execute, that a
# minimal program compiles and links against newlib, that the output targets
# the right architecture and that GDB can read the result.
#
# The toolchain-specific parts are defined in test/toolchains/<TOOLCHAIN>.sh,
# which is sourced by this script. See the defaults below for the variables
# and functions it can define.
#
# Usage: smoke-test.sh TOOLCHAIN TOOLCHAIN_DIR

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 TOOLCHAIN TOOLCHAIN_DIR" >&2
    exit 2
fi

readonly TARGET="$1"
readonly TOOLCHAIN_DIR="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly SOURCE_DIR="${ROOT_DIR}/test/src"
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

# Checks that the output of a command does not contain the given pattern.
check_no_output() {
    local description="$1"
    local pattern="$2"
    local output
    shift 2

    if ! output="$("$@" 2>&1)"; then
        fail "${description}"
        details "${output}"
    elif grep -qE -- "${pattern}" <<< "${output}"; then
        fail "${description}"
        details "$(grep -E -- "${pattern}" <<< "${output}" | head -n 10)"
    else
        pass "${description}"
    fi
}

# Prints the path of a file of the compiler, for example a startup file.
compiler_file() {
    "${BIN}-gcc" "${TARGET_CFLAGS[@]}" -print-file-name="$1"
}

# Compiles the sources of the test program into the given directory, and links
# them into test.elf in that directory. The label distinguishes the checks if
# the program is built more than once.
build_program() {
    local label="${1:+ ($1)}"
    local output_dir="$2"
    local objects=()
    local source
    local object

    mkdir -p "${output_dir}"

    for source in "${SOURCES[@]}"; do
        object="${output_dir}/${source%.*}.o"
        objects+=("${object}")

        case "${source}" in
            *.cpp)
                check "compile ${source}${label}" "${BIN}-g++" "${CFLAGS[@]}" \
                    -std=c++17 -fno-exceptions -fno-rtti \
                    -c "${SOURCE_DIR}/${source}" -o "${object}"
                ;;
            *)
                check "compile ${source}${label}" "${BIN}-gcc" "${CFLAGS[@]}" \
                    -std=c11 -c "${SOURCE_DIR}/${source}" -o "${object}"
                ;;
        esac
    done

    # The linker reports some errors without failing, for example errors in
    # the debug information. These are treated as failures as well.
    check_no_output "link against newlib${label}" "error:" link_program \
        "${output_dir}/test.elf" "${objects[@]}"
}

# Defaults, which test/toolchains/<TOOLCHAIN>.sh may override.

# Host tools that are expected to execute.
TOOLS=(gcc cpp as ld ar nm objcopy objdump readelf size strip gdb)

# Compiler flags that select the target, and macros for main.c.
TARGET_CFLAGS=()

# Sources of test/src that make up the test program.
SOURCES=(main.c syscalls.c)

# Macros that newlib.h is expected to define.
NEWLIB_DEFINES=()

# Machine type of the program, as reported by readelf.
MACHINE=""

# Name of a register that GDB is expected to know.
GDB_REGISTER=""

# Links the objects of the test program into the given output file.
link_program() {
    local output="$1"
    shift

    "${BIN}-gcc" "${TARGET_CFLAGS[@]}" -Wl,--gc-sections "$@" -lm \
        -o "${output}"
}

# Runs additional checks on the linked test program.
toolchain_checks() {
    :
}

# shellcheck source=/dev/null
source "${ROOT_DIR}/test/toolchains/${TARGET}.sh"

CFLAGS=(-Os -g -ffunction-sections -fdata-sections -Wall -Wextra -Werror
        "${TARGET_CFLAGS[@]}")

echo "Testing ${TARGET} toolchain in ${TOOLCHAIN_DIR}"

# Host tools
for tool in "${TOOLS[@]}"; do
    check "${tool} executes" "${BIN}-${tool}" --version
done

check_output "gcc targets ${TARGET}" "^${TARGET}\$" "${BIN}-gcc" -dumpmachine

# Newlib configuration
NEWLIB_H="${TOOLCHAIN_DIR}/${TARGET}/include/newlib.h"

for define in "${NEWLIB_DEFINES[@]}"; do
    check_output "newlib defines ${define}" "^#define ${define} 1" \
        cat "${NEWLIB_H}"
done

# Compiling and linking
build_program "" "${WORK_DIR}"

if [ ! -f "${WORK_DIR}/test.elf" ]; then
    echo "Skipping remaining tests, since linking failed" >&2
    exit 1
fi

# Output
check_output "output targets ${MACHINE}" "Machine: +${MACHINE}\$" \
    "${BIN}-readelf" -h "${WORK_DIR}/test.elf"

toolchain_checks "${WORK_DIR}/test.elf"

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
check_output "gdb knows register ${GDB_REGISTER}" "^ +${GDB_REGISTER} +[0-9]+ " \
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
