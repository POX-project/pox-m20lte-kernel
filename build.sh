#!/usr/bin/env bash
#
# build.sh - Pox Kernel builder & variant manager for Samsung Galaxy M20 (m20lte)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ARCH=arm64
export PLATFORM_VERSION=11
export ANDROID_MAJOR_VERSION=r

CLANG_BIN=""
if [ -d "$HOME/clang-r536225/bin" ]; then
    CLANG_BIN="$HOME/clang-r536225/bin"
elif command -v clang >/dev/null 2>&1; then
    CLANG_BIN="$(dirname "$(command -v clang)")"
fi

if [ -n "$CLANG_BIN" ]; then
    export PATH="$CLANG_BIN:$PATH"
    export CC="clang"
    export CLANG_TRIPLE="aarch64-linux-gnu-"
fi

if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    export CROSS_COMPILE="aarch64-linux-gnu-"
fi

ACTION="${1:-${VARIANT:-vanilla}}"

case "$ACTION" in
    clean|unvariant)
        echo "==> Restoring clean onyx tree..."
        git checkout -- .
        rm -rf KernelSU-Next drivers/kernelsu ksu-patches dist out
        echo "==> Clean complete."
        exit 0
        ;;
    apatch)
        echo "==> Applying APatch patch..."
        patch -p1 -N < "$ROOT_DIR/patches/apatch.patch" || true
        DEFCONFIG="m20lte_defconfig"
        EDITION="Onyx-APatch"
        ZIP_NAME="Pox-Kernel-2.1-Onyx-APatch-m20lte.zip"
        ;;
    ksu-next|ksu)
        echo "==> Applying KernelSU-Next patch..."
        patch -p1 -N < "$ROOT_DIR/patches/ksu.patch" || true
        if [ ! -d "$ROOT_DIR/KernelSU-Next" ]; then
            git clone --depth=1 --branch legacy https://github.com/KernelSU-Next/KernelSU-Next.git "$ROOT_DIR/KernelSU-Next"
        fi
        ln -sf ../KernelSU-Next/kernel "$ROOT_DIR/drivers/kernelsu"
        if [ -f "$ROOT_DIR/ksu-patches/0001-sepolicy-exynos-flex-array.patch" ]; then
            (cd "$ROOT_DIR/KernelSU-Next" && patch -p1 -N < "$ROOT_DIR/ksu-patches/0001-sepolicy-exynos-flex-array.patch" || true)
        fi
        DEFCONFIG="m20lte_defconfig"
        EDITION="Onyx-KSUN"
        ZIP_NAME="Pox-Kernel-2.1-Onyx-KSUN-m20lte.zip"
        ;;
    vanilla|*)
        echo "==> Building clean Vanilla (Onyx)..."
        DEFCONFIG="m20lte_defconfig"
        EDITION="Onyx"
        ZIP_NAME="Pox-Kernel-2.1-Onyx-m20lte.zip"
        ;;
esac

echo "==> Building defconfig: $DEFCONFIG"
mkdir -p "$ROOT_DIR/out"
make ARCH=arm64 "$DEFCONFIG"

MAKE_ARGS=(ARCH=arm64 -j"$(nproc)")
if [ -n "${CC:-}" ]; then
    MAKE_ARGS+=(CC="$CC" CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}")
fi
if [ -n "${CROSS_COMPILE:-}" ]; then
    MAKE_ARGS+=(CROSS_COMPILE="$CROSS_COMPILE")
fi

make "${MAKE_ARGS[@]}" Image dtbs modules 2>&1 | tee "$ROOT_DIR/out/build.log"

if [ -f "$ROOT_DIR/tools/package_ak3.sh" ]; then
    echo "==> Packaging AnyKernel3 flashable zip..."
    bash "$ROOT_DIR/tools/package_ak3.sh" "$ACTION" "$EDITION" "$ZIP_NAME"
fi
