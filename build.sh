#!/usr/bin/env bash
#
# build.sh - Pox Kernel builder & variant manager for Samsung Galaxy M20 (m20lte)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ARCH=arm64
export PLATFORM_VERSION=11
export ANDROID_MAJOR_VERSION=r

TOOLCHAIN_BIN="$ROOT_DIR/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin"
if [ -d "$TOOLCHAIN_BIN" ]; then
    export CROSS_COMPILE="$TOOLCHAIN_BIN/aarch64-linux-android-"
    chmod +x "$TOOLCHAIN_BIN"/* 2>/dev/null || true
fi

ACTION="${1:-${VARIANT:-vanilla}}"

case "$ACTION" in
    clean|unvariant)
        echo "==> Restoring clean onyx tree..."
        git checkout -- .
        rm -rf KernelSU-Next drivers/kernelsu ksu-patches arch/arm64/configs/exynos7885-m20_apatch_defconfig arch/arm64/configs/exynos7885-m20_ksu_next_defconfig dist out
        echo "==> Clean complete."
        exit 0
        ;;
    apatch)
        echo "==> Applying APatch patch..."
        patch -p1 -N < "$ROOT_DIR/patches/apatch.patch" || true
        DEFCONFIG="exynos7885-m20_apatch_defconfig"
        EDITION="Onyx-APatch"
        ZIP_NAME="Pox-Kernel-1.0.0-Beta-Onyx-APatch-m20lte.zip"
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
        DEFCONFIG="exynos7885-m20_ksu_next_defconfig"
        EDITION="Onyx-KSUN"
        ZIP_NAME="Pox-Kernel-1.0.0-Beta-Onyx-KSUN-m20lte.zip"
        ;;
    vanilla|*)
        echo "==> Building clean Vanilla (Onyx)..."
        DEFCONFIG="exynos7885-m20_gsi_defconfig"
        EDITION="Onyx"
        ZIP_NAME="Pox-Kernel-1.0.0-Beta-Onyx-m20lte.zip"
        ;;
esac

echo "==> Building defconfig: $DEFCONFIG"
mkdir -p "$ROOT_DIR/out"
make ARCH=arm64 "$DEFCONFIG"
make ARCH=arm64 -j"$(nproc)" Image dtbs modules 2>&1 | tee "$ROOT_DIR/out/build.log"

if [ -f "$ROOT_DIR/tools/package_ak3.sh" ]; then
    echo "==> Packaging AnyKernel3 flashable zip..."
    bash "$ROOT_DIR/tools/package_ak3.sh" "$ACTION" "$EDITION" "$ZIP_NAME"
fi
