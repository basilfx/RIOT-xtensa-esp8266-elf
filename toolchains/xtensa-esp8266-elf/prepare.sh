#!/bin/sh
#
# Fetches the processor configuration of the ESP8266 (Xtensa lx106 core) from
# Espressif's xtensa-overlays repository, and patches it to match the GDB
# version of the toolchain. The defconfig refers to the resulting directory.

set -eu

readonly XTENSA_OVERLAYS_COMMIT=dd1cf19f6eb327a9db51043439974a6de13f5c7f

cd "$(dirname "$0")"

git clone https://github.com/espressif/xtensa-overlays xtensa-overlays
git -C xtensa-overlays checkout -q "${XTENSA_OVERLAYS_COMMIT}"
git -C xtensa-overlays apply "${PWD}"/overlay-patches/*.patch
