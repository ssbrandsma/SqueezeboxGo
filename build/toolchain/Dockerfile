# Pinned aarch64 toolchain container (WP1 Core)
#
# Build contract: aarch64-linux-gnu, -march=armv8-a+crc -mtune=cortex-a53,
# glibc, PREFIX=/opt/squeezeplay. Pinned to Ubuntu 24.04 (noble) + dated
# snapshot package versions for reproducibility.
#
# Build:
#   docker build -f build/toolchain/Dockerfile -t squeezeplay-toolchain:wp1 .
# Use:
#   docker run --rm -v "$PWD:/work" -w /work squeezeplay-toolchain:wp1 \
#     make -C <squeezeplay-src> -f Makefile.linux-aarch64

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    SOURCE_DATE_EPOCH=0

# Pinned toolchain + target sysroot headers/libs (arm64).
# Versions current as of 2026-11-15; bump only with Lead approval.
RUN dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential=12.10ubuntu1 \
      gcc-aarch64-linux-gnu=4:13.2.0-7ubuntu1 \
      g++-aarch64-linux-gnu=4:13.2.0-7ubuntu1 \
      binutils-aarch64-linux-gnu=2.42-4ubuntu2.10 \
      libc6-dev-arm64-cross=2.39-0ubuntu8cross1 \
      libasound2-dev:arm64=1.2.11-1ubuntu0.3 \
      zlib1g-dev:arm64=1:1.3.dfsg-3.1ubuntu2.3 \
      ca-certificates=20260816ubuntu0.24.04.2 \
      git=1:2.43.0-1ubuntu7.4 \
      patch=2.7.6-7build3 \
      make=4.3-4.1build2 \
      autoconf=2.71-3 \
      automake=1:1.16.5-1.3ubuntu1 \
      libtool=2.4.7-7build1 \
      pkg-config=1.8.1-2build1 \
      file=1:5.45-3build1 \
      binutils=2.42-4ubuntu2.10 \
      qemu-user=1:8.2.2+ds-0ubuntu1.18 \
      python3=3.12.3-0ubuntu2.1 \
      xz-utils=5.6.1+really5.4.5-1ubuntu0.4 \
    && rm -rf /var/lib/apt/lists/*

# Sanity: cross compiler present and targeting aarch64 by default.
RUN aarch64-linux-gnu-gcc -dumpmachine | grep -q '^aarch64-linux-gnu$' && \
    echo '#include <alsa/asoundlib.h>' | \
      aarch64-linux-gnu-gcc -E -x c - -o /dev/null && \
    echo "toolchain OK"

WORKDIR /work
