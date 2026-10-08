# Builds one of the toolchains in toolchains/ using crosstool-NG. The toolchain
# is selected with the TOOLCHAIN build argument, which is the name of its
# directory and equals the target triplet of the toolchain.
#
# The toolchain is linked dynamically against the C library of the build
# image. A statically linked toolchain is not used, since GDB then loads the
# gconv and NSS modules of the host at runtime, which crashes if the host C
# library differs from the one GDB was linked against. Programs linked against
# an older C library run on newer ones, so the oldest supported distribution
# is used as base image.
ARG BASE_IMAGE=docker.io/library/ubuntu:noble

# Name of the toolchain to build, for example xtensa-esp8266-elf.
ARG TOOLCHAIN

# Installation directory of the toolchain. If empty, the default of the
# defconfig of the toolchain is used. The packaged archive extracts to a
# directory with the same name as the last component of this path.
ARG TOOLCHAIN_PREFIX

FROM ${BASE_IMAGE} AS build

ARG TOOLCHAIN
ARG TOOLCHAIN_PREFIX

ARG CROSSTOOL_NG_VERSION=1.29.0
ARG CROSSTOOL_NG_SHA256=1e0c5efcf2af674993b74a1783fe78727c8d34b500ebab07eb1bb0a45c8fcc87

RUN \
    test -n "${TOOLCHAIN}" || \
    { echo 'The TOOLCHAIN build argument is required' >&2; exit 1; }

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

# crosstool-NG refuses to run as root. The files of the toolchain are copied to
# /home/build/toolchain, which the defconfig files refer to.
RUN useradd -m build

COPY --chown=build:build toolchains/${TOOLCHAIN}/ /home/build/toolchain/

# The installation directory is resolved from the defconfig, which is a shell
# script, and stored for the later stages.
RUN \
    PREFIX="$(. /home/build/toolchain/defconfig && echo "${CT_PREFIX_DIR}")" && \
    echo "${PREFIX}" > /etc/toolchain-prefix && \
    mkdir -p "${PREFIX}" && \
    chown build:build "${PREFIX}"

USER build
WORKDIR /home/build

# Toolchains may provide a script that prepares additional sources.
RUN \
    if [ -x toolchain/prepare.sh ]; then \
        echo "Preparing ${TOOLCHAIN} toolchain" >&2 && \
        toolchain/prepare.sh; \
    fi

RUN \
    echo "Building ${TOOLCHAIN} toolchain" >&2 && \
    DEFCONFIG=toolchain/defconfig ct-ng defconfig && \
    ct-ng build.$(nproc) && \
    rm -rf .build src && \
    cd "$(cat /etc/toolchain-prefix)" && \
    echo 'Removing documentation and unneeded files' >&2 && \
    rm -rf build.log.bz2 share/doc share/info share/man \
        "bin/${TOOLCHAIN}-lto-dump" && \
    echo 'Deduplicating binaries' >&2 && \
    cd "${TOOLCHAIN}/bin" && \
    for f in *; do \
        test -f "../../bin/${TOOLCHAIN}-$f" && \
        ln -f "../../bin/${TOOLCHAIN}-$f" "$f"; \
    done; \
    true

# Packages the toolchain into an archive that extracts to the last component of
# the installation directory, with a checksum file next to it.
FROM build AS package

ARG TOOLCHAIN

USER root

RUN \
    echo "Packaging ${TOOLCHAIN} toolchain" >&2 && \
    PREFIX="$(cat /etc/toolchain-prefix)" && \
    ARCHIVE="${TOOLCHAIN}-$(uname -m)-linux-gnu.tar.xz" && \
    mkdir /dist && \
    tar -C "$(dirname "${PREFIX}")" \
        --sort=name --owner=0 --group=0 --numeric-owner \
        -cf - "$(basename "${PREFIX}")" | \
        xz -T0 -9 > "/dist/${ARCHIVE}" && \
    cd /dist && \
    sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256"

# Tests the packaged toolchain on a clean installation of the base image, which
# does not contain the build dependencies. This verifies the archive as it is
# distributed, including the libraries it requires from the host.
FROM ${BASE_IMAGE} AS test

ARG TOOLCHAIN

RUN \
    apt-get update && \
    apt-get -y --no-install-recommends install xz-utils && \
    rm -rf /var/lib/apt/lists/*

COPY --from=package /dist/ /dist/
COPY --from=package /etc/toolchain-prefix /etc/toolchain-prefix
COPY test/ /tmp/smoke-test/test/

RUN \
    echo "Testing ${TOOLCHAIN} toolchain" >&2 && \
    PREFIX="$(cat /etc/toolchain-prefix)" && \
    cd /dist && \
    sha256sum -c *.sha256 && \
    mkdir -p "$(dirname "${PREFIX}")" && \
    tar -C "$(dirname "${PREFIX}")" -xJf *.tar.xz && \
    /tmp/smoke-test/test/smoke-test.sh "${TOOLCHAIN}" "${PREFIX}"

# Contains only the archive, so it can be exported using the --output option.
# The archive is taken from the test stage, so it is only exported if the
# tests pass.
FROM scratch AS artifact

COPY --from=test /dist/ /
