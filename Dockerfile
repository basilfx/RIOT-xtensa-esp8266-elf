# Builds the ESP8266 toolchain (xtensa-esp8266-elf) using crosstool-NG.
#
# The toolchain is linked dynamically against the C library of the build
# image. A statically linked toolchain is not used, since GDB then loads the
# gconv and NSS modules of the host at runtime, which crashes if the host C
# library differs from the one GDB was linked against. Programs linked against
# an older C library run on newer ones, so the oldest supported distribution
# is used as base image.
ARG BASE_IMAGE=docker.io/library/ubuntu:noble

# Installation directory of the toolchain. The packaged archive extracts to a
# directory with the same name as the last component of this path.
ARG TOOLCHAIN_PREFIX=/opt/esp/xtensa-esp8266-elf

FROM ${BASE_IMAGE} AS build

ARG TOOLCHAIN_PREFIX

ARG CROSSTOOL_NG_VERSION=1.29.0
ARG CROSSTOOL_NG_SHA256=1e0c5efcf2af674993b74a1783fe78727c8d34b500ebab07eb1bb0a45c8fcc87
ARG XTENSA_OVERLAYS_COMMIT=dd1cf19f6eb327a9db51043439974a6de13f5c7f

RUN \
    apt-get update && \
    apt-get -y --no-install-recommends install \
        autoconf automake bison bzip2 ca-certificates curl file flex g++ \
        gawk gcc git help2man libncurses-dev libtool-bin make patch \
        pkg-config python3 python3-dev rsync texinfo unzip wget xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN \
    echo 'Installing crosstool-NG' >&2 && \
    curl -sSL -o /tmp/crosstool-ng.tar.xz https://github.com/crosstool-ng/crosstool-ng/releases/download/crosstool-ng-${CROSSTOOL_NG_VERSION}/crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.xz && \
    echo "${CROSSTOOL_NG_SHA256} /tmp/crosstool-ng.tar.xz" | sha256sum -c && \
    tar -C /tmp -xJf /tmp/crosstool-ng.tar.xz && \
    cd /tmp/crosstool-ng-${CROSSTOOL_NG_VERSION} && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/crosstool-ng*

COPY patches/xtensa-overlays/ /tmp/patches/

RUN \
    echo 'Fetching Xtensa overlays' >&2 && \
    git clone https://github.com/espressif/xtensa-overlays /opt/xtensa-overlays && \
    git -C /opt/xtensa-overlays checkout -q ${XTENSA_OVERLAYS_COMMIT} && \
    git -C /opt/xtensa-overlays apply /tmp/patches/*.patch && \
    rm -rf /tmp/patches

# crosstool-NG refuses to run as root
RUN \
    useradd -m build && \
    mkdir -p "${TOOLCHAIN_PREFIX}" && \
    chown build:build "${TOOLCHAIN_PREFIX}"

COPY esp8266.defconfig /home/build/defconfig

USER build
WORKDIR /home/build

RUN \
    echo 'Building ESP8266 toolchain' >&2 && \
    DEFCONFIG=defconfig ct-ng defconfig && \
    ct-ng build.$(nproc) && \
    rm -rf .build src && \
    cd "${TOOLCHAIN_PREFIX}" && \
    echo 'Removing documentation and unneeded files' >&2 && \
    rm -rf build.log.bz2 share/doc share/info share/man \
        bin/xtensa-esp8266-elf-lto-dump && \
    echo 'Deduplicating binaries' >&2 && \
    cd xtensa-esp8266-elf/bin && \
    for f in *; do \
        test -f "../../bin/xtensa-esp8266-elf-$f" && \
        ln -f "../../bin/xtensa-esp8266-elf-$f" "$f"; \
    done; \
    true

ENV PATH=${TOOLCHAIN_PREFIX}/bin:$PATH

# Packages the toolchain into an archive that extracts to the last component of
# the installation directory, with a checksum file next to it.
FROM build AS package

ARG TOOLCHAIN_PREFIX

USER root

RUN \
    echo 'Packaging ESP8266 toolchain' >&2 && \
    ARCHIVE="xtensa-esp8266-elf-$(uname -m)-linux-gnu.tar.xz" && \
    mkdir /dist && \
    tar -C "$(dirname "${TOOLCHAIN_PREFIX}")" \
        --sort=name --owner=0 --group=0 --numeric-owner \
        -cf - "$(basename "${TOOLCHAIN_PREFIX}")" | \
        xz -T0 -9 > "/dist/${ARCHIVE}" && \
    cd /dist && \
    sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256"

# Tests the packaged toolchain on a clean installation of the base image, which
# does not contain the build dependencies. This verifies the archive as it is
# distributed, including the libraries it requires from the host.
FROM ${BASE_IMAGE} AS test

ARG TOOLCHAIN_PREFIX

RUN \
    apt-get update && \
    apt-get -y --no-install-recommends install xz-utils && \
    rm -rf /var/lib/apt/lists/*

COPY --from=package /dist/ /dist/
COPY test/ /tmp/test/

RUN \
    echo 'Testing ESP8266 toolchain' >&2 && \
    cd /dist && \
    sha256sum -c *.sha256 && \
    mkdir -p "$(dirname "${TOOLCHAIN_PREFIX}")" && \
    tar -C "$(dirname "${TOOLCHAIN_PREFIX}")" -xJf *.tar.xz && \
    /tmp/test/smoke-test.sh "${TOOLCHAIN_PREFIX}"

# Contains only the archive, so it can be exported using the --output option.
# The archive is taken from the test stage, so it is only exported if the
# tests pass.
FROM scratch AS artifact

COPY --from=test /dist/ /
