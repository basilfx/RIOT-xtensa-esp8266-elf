# xtensa-esp8266-elf

Toolchain for the ESP8266 (Xtensa lx106 core) specifically built for
[RIOT](https://github.com/RIOT-OS/RIOT).



## Toolchain
The toolchain is built from source using
[crosstool-NG](https://crosstool-ng.github.io/) and the processor configuration 
from Espressif's
[xtensa-overlays](https://github.com/espressif/xtensa-overlays). It is built
with the following versions of its components:

| Component | Version        |
|-----------|----------------|
| GCC       | 14.4.0         |
| binutils  | 2.43.1         |
| newlib    | 4.4.0.20231231 |
| GDB       | 15.2           |

Notable configuration choices:

* Newlib is built with retargetable locking, so RIOT can map the locks of the
  C library to its own mutexes.
* Libgloss is disabled, since it assumes the windowed ABI, whereas the lx106
  core only supports the call0 ABI.
* Newlib 4.5 is not used, since its release tarball does not install the
  Xtensa core configuration headers and the overlay targets the directory
  layout used up to newlib 4.4.
* The GDB part of the overlay is patched to match the interface of GDB 13 and
  newer.
* The toolchain is linked dynamically against the C library of the build
  image (Ubuntu 24.04). A static toolchain would make GDB load the gconv and
  NSS modules of the host, which crashes when the C library versions differ.
* The toolchain requires glibc 2.38 or newer. GDB additionally requires 
  `libstdc++.so.6`, `libncursesw.so.6` and `libtinfo.so.6`.

## RIOT-specific configuration
Existing prebuilt ESP8266 toolchains are either outdated, or ship a C library
tailored to the Arduino ESP8266 core (for example without `malloc()`). This
toolchain uses an unmodified upstream newlib, configured for RIOT:

* The full C library, including memory allocation, with formatted I/O that
  supports floating point, C99 formats and `long long` values.
* Retargetable locking, so that RIOT can protect the C library with its own
  mutexes.
* Small reentrancy structures, to limit the memory used per thread.
* No libgloss, board support or simulator libraries, since RIOT provides the
  system calls and startup code itself.

## Building
The toolchain is built in a container. Building takes roughly half an hour to
an hour, depending on the machine.

```sh
docker build --platform linux/amd64,linux/arm64 --target build .
```

The toolchain is built to be installed in `/opt/esp/xtensa-esp8266-elf` by
default. Use `--build-arg TOOLCHAIN_PREFIX=...` to change the installation
directory. The archive then extracts to a directory named after the last
component of that path.

## Packaging
The `artifact` target packages the toolchain into an archive and exports it
to `dist/`, together with a SHA-256 checksum file:

```sh
docker build --platform linux/amd64,linux/arm64 --target artifact --output type=local,dest=dist .
```

The artifacts will be placed in the `dist/` directory, roughly 25-30 MiB each.

The platform argument is optional, but it allows building the toolchain for 
multiple architectures in one go. The build is done in emulation mode, which is
slow.

## Testing
The test is part of the `test` target, which installs the packaged archive on
a clean installation of the base image (without the build dependencies) and
runs the script there. The build fails if any of the tests fail:

```sh
docker build --platform linux/amd64,linux/arm64 --target test .
```

## License
The build scripts in this repository are licensed under the MIT license, see
[LICENSE.md](LICENSE.md). 

The toolchain components keep their own licenses.
