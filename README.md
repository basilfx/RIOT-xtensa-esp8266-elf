# RIOT toolchains

Toolchains specifically built for [RIOT](https://github.com/RIOT-OS/RIOT), for
architectures that lack an up-to-date prebuilt toolchain that suits RIOT.

## Toolchains
The toolchains are built from source using
[crosstool-NG](https://crosstool-ng.github.io/), with the following versions
of their components:

| Toolchain            | Architecture           | GCC    | binutils | newlib         | GDB  |
|----------------------|------------------------|--------|----------|----------------|------|
| `xtensa-esp8266-elf` | ESP8266 (Xtensa lx106) | 14.4.0 | 2.43.1   | 4.4.0.20231231 | 15.2 |

Each toolchain has its own directory in [toolchains/](toolchains/), named
after its target triplet:

* `defconfig` is the crosstool-NG configuration.
* `patches/` contains patches for the components, which crosstool-NG applies
  after its own patches (optional).
* `prepare.sh` prepares additional sources before building (optional).

The toolchain-specific parts of the smoke test are in
[test/toolchains/](test/toolchains/).

The toolchains are linked dynamically against the C library of the build
image (Ubuntu 24.04). A static toolchain would make GDB load the gconv and NSS
modules of the host, which crashes when the C library versions differ. The
toolchains therefore require glibc 2.38 or newer. GDB additionally requires
`libstdc++.so.6`, `libncursesw.so.6` and `libtinfo.so.6`.

### xtensa-esp8266-elf
The processor configuration is taken from Espressif's
[xtensa-overlays](https://github.com/espressif/xtensa-overlays). Existing
prebuilt ESP8266 toolchains are either outdated, or ship a C library tailored
to the Arduino ESP8266 core (for example without `malloc()`). This toolchain
uses an unmodified upstream newlib, configured for RIOT:

* The full C library, including memory allocation, with formatted I/O that
  supports floating point, C99 formats and `long long` values.
* Retargetable locking, so that RIOT can protect the C library with its own
  mutexes.
* Small reentrancy structures, to limit the memory used per thread.
* No libgloss, board support or simulator libraries, since RIOT provides the
  system calls and startup code itself. Libgloss also assumes the windowed
  ABI, whereas the lx106 core only supports the call0 ABI.

Newlib 4.5 is not used, since its release tarball does not install the Xtensa
core configuration headers and the overlay targets the directory layout used
up to newlib 4.4. The GDB part of the overlay is patched to match the
interface of GDB 13 and newer.

## Building
The toolchains are built in a container. The `TOOLCHAIN` build argument
selects the toolchain. Building takes roughly half an hour to an hour,
depending on the machine.

```sh
docker build --platform linux/amd64,linux/arm64 --build-arg TOOLCHAIN=xtensa-esp8266-elf --target build .
```

Each toolchain is built to be installed in the directory of its `defconfig`
(`/opt/esp/xtensa-esp8266-elf`). Use
`--build-arg TOOLCHAIN_PREFIX=...` to change the installation directory. The
archive then extracts to a directory named after the last component of that
path.

## Packaging
The `artifact` target packages the toolchain into an archive and exports it
to `dist/`, together with a SHA-256 checksum file:

```sh
docker build --platform linux/amd64,linux/arm64 --build-arg TOOLCHAIN=xtensa-esp8266-elf --target artifact --output type=local,dest=dist .
```

The artifacts will be placed in the `dist/` directory, named
`<toolchain>-<architecture>-linux-gnu.tar.xz`.

The platform argument is optional, but it allows building the toolchain for
multiple architectures in one go. The build is done in emulation mode, which is
slow.

## Testing
The test is part of the `test` target, which installs the packaged archive on
a clean installation of the base image (without the build dependencies) and
runs the smoke test there. The build fails if any of the tests fail:

```sh
docker build --platform linux/amd64,linux/arm64 --build-arg TOOLCHAIN=xtensa-esp8266-elf --target test .
```

The smoke test can also be run on an installed toolchain directly:

```sh
test/smoke-test.sh xtensa-esp8266-elf /opt/esp/xtensa-esp8266-elf
```

## License
The build scripts in this repository are licensed under the MIT license, see
[LICENSE.md](LICENSE.md).

The toolchain components keep their own licenses.
