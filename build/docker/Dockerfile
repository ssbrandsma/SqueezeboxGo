# Squeezebox RG35XX H image-build container (Agent 1).
# Pinned base (digest resolved 2026-11-15; refresh deliberately, never float).
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc

ENV DEBIAN_FRONTEND=noninteractive \
    SOURCE_DATE_EPOCH=1794334272 \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu-

# Layer 1: cross toolchain + kernel/u-boot build deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu build-essential bc bison flex swig python3-dev \
    libssl-dev device-tree-compiler u-boot-tools \
    git curl ca-certificates file python3 \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: image assembly tooling. NOTE (WP2): ext4 byte-repro comes from
# mke2fs >= 1.47.1 + SOURCE_DATE_EPOCH + pinned hash_seed, NOT libfaketime
# (measured: faketime double-shifts -d source times; see build/image/README).
# TODO: e2fsprogs >= 1.47.1 (bookworm ships 1.46.x) for byte-identical images.
RUN apt-get update && apt-get install -y --no-install-recommends \
    dosfstools mtools e2fsprogs fdisk util-linux parted gdisk \
    fakeroot libfaketime shellcheck \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 builder && mkdir -p /work/repo && chown builder:builder /work/repo
USER builder
WORKDIR /work/repo

# Default: show the assembly preflight. Mount the repo at /work/repo:
#   docker run --rm -v "$PWD":/work/repo -w /work/repo squeezebox-image
CMD ["./build/image/assemble-image.sh", "--check-deps"]
