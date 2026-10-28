#!/usr/bin/env bash
#
# package_ak3.sh - Package flashable AnyKernel3 zip for Samsung Galaxy M20 (m20lte)
#
set -euo pipefail

VARIANT="${1:-vanilla}"
EDITION="${2:-Onyx}"
ZIP_NAME="${3:-Pox-Kernel-1.0.0-Beta-Onyx-m20lte.zip}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

if [ ! -f "$ROOT_DIR/arch/arm64/boot/Image" ]; then
    echo "Error: $ROOT_DIR/arch/arm64/boot/Image not found!"
    exit 1
fi

cp "$ROOT_DIR/arch/arm64/boot/Image" "$DIST_DIR/Image-m20lte"
mkdir -p "$DIST_DIR/modules"
find "$ROOT_DIR" -maxdepth 4 -name "*.ko" -exec cp {} "$DIST_DIR/modules/" \; 2>/dev/null || true
[ -f "$ROOT_DIR/out/build.log" ] && cp "$ROOT_DIR/out/build.log" "$DIST_DIR/" || true
[ -f "$ROOT_DIR/.config" ] && cp "$ROOT_DIR/.config" "$DIST_DIR/defconfig_used" || true

AK_DIR="$ROOT_DIR/dist/AnyKernel3"
rm -rf "$AK_DIR" "$DIST_DIR/AnyKernel3-template"
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$DIST_DIR/AnyKernel3-template"
cp -r "$DIST_DIR/AnyKernel3-template" "$AK_DIR"
rm -rf "$AK_DIR/.git" "$AK_DIR/.github"

if [ "$VARIANT" = "apatch" ]; then
    echo "Fetching latest FolkPatch release package..."
    FP_URL=$(curl -sL https://api.github.com/repos/LyraVoid/FolkPatch/releases/latest | grep "browser_download_url.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
    if [ -n "$FP_URL" ]; then
        curl -sL "$FP_URL" -o "$AK_DIR/folkpatch.zip" || true
        echo "Bundled FolkPatch package: $(ls -lh "$AK_DIR/folkpatch.zip" 2>/dev/null || true)"
    fi

    # Fetch kptools-linux to pre-patch kernel with KernelPatch kpimg at build time
    KPTOOLS="$ROOT_DIR/tools/kptools-linux"
    if [ ! -f "$KPTOOLS" ]; then
        curl -sL https://github.com/bmax121/KernelPatch/releases/download/0.13.9/kptools-linux -o "$KPTOOLS" || true
        chmod +x "$KPTOOLS" 2>/dev/null || true
    fi

    if [ -x "$KPTOOLS" ] && [ -f "$AK_DIR/folkpatch.zip" ]; then
        echo "Extracting kpimg from FolkPatch package..."
        unzip -p "$AK_DIR/folkpatch.zip" assets/kpimg > "$DIST_DIR/kpimg" 2>/dev/null || true
        if [ -s "$DIST_DIR/kpimg" ]; then
            echo "Pre-patching kernel Image with KernelPatch (SuperKey: poxkernel)..."
            if "$KPTOOLS" -p -i "$DIST_DIR/Image-m20lte" -k "$DIST_DIR/kpimg" -s "poxkernel" -o "$AK_DIR/zImage"; then
                echo "Successfully pre-patched kernel with KernelPatch."
            else
                echo "Warning: kptools pre-patching failed, falling back to raw Image (recovery installer will patch)."
                cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
            fi
            rm -f "$DIST_DIR/kpimg"
        else
            cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
        fi
    else
        cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
    fi
else
    cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
fi

cat > "$AK_DIR/anykernel.sh" << EOS
# AnyKernel3 Ramdisk Mod Script
# Pox Kernel 1.0.0-Beta-${EDITION} for Samsung Galaxy M20 (m20lte) by txorav

### AnyKernel setup
properties() { '
kernel.string=Pox Kernel 1.0.0-Beta-${EDITION} for Samsung Galaxy M20 (m20lte) by txorav
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=m20lte
device.name2=m20ltedd
device.name3=m20
device.name4=universal7885
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

boot_attributes() {
set_perm_recursive 0 0 755 644 \$RAMDISK/*;
set_perm_recursive 0 0 750 750 \$RAMDISK/init* \$RAMDISK/sbin;
}

BLOCK=auto;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

## Ensure /dev/block/by-name/boot exists for Samsung Exynos (uppercase BOOT)
if [ ! -e /dev/block/by-name/boot ]; then
    for b in /dev/block/by-name/BOOT /dev/block/platform/*/by-name/BOOT; do
        if [ -e "\$b" ]; then
            ln -sf "\$b" /dev/block/by-name/boot;
            break;
        fi;
    done;
fi;

. tools/ak3-core.sh;

ui_print " ";
ui_print " ============================================";
ui_print "   POX KERNEL 1.0.0-BETA [${EDITION}]        ";
ui_print "   Samsung Galaxy M20 (universal7885)        ";
ui_print " ============================================";
ui_print "  * Engine       : Zero Frame-Drop Gaming Core";
ui_print "  * Kprofiles    : Tri-State LCD Auto-Governor";
ui_print "  * Health Engine: OPP Dynamic Silicon Guard ";
ui_print "  * Battery Care : Bypass & Current Limiting ";
ui_print "  * Display Mode : iOS D65 Calibrated Reference";
ui_print "  * Root Flavor  : ${EDITION}";
EOS

if [ "$VARIANT" = "apatch" ]; then
    cat >> "$AK_DIR/anykernel.sh" << 'EOS'
ui_print "  * Root Method  : KernelPatch Embedded";
ui_print "  * SuperKey     : poxkernel";
EOS
fi

cat >> "$AK_DIR/anykernel.sh" << 'EOS'
ui_print " --------------------------------------------";

dump_boot;
write_boot;
EOS

if [ "$VARIANT" = "apatch" ]; then
    cat >> "$AK_DIR/anykernel.sh" << 'EOS'

## Stage FolkPatch manager APK to storage for easy installation
for dest in /data/system /data/local/tmp /sdcard; do
    [ -d "$dest" ] || continue;
    if cp -f "$AKHOME/folkpatch.zip" "$dest/FolkPatch.apk" 2>/dev/null; then
        chmod 0644 "$dest/FolkPatch.apk" 2>/dev/null;
        ui_print " [*] Staged FolkPatch manager APK to $dest/FolkPatch.apk";
    fi;
done;

## Auto-flash bundled FolkPatch package as secondary fallback
FP_SRC="";
for fp in "$AKHOME/folkpatch.zip" "folkpatch.zip"; do
    [ -f "$fp" ] && { FP_SRC="$fp"; break; };
done;
if [ -n "$FP_SRC" ]; then
    ui_print " ";
    ui_print " ============================================";
    ui_print "   Flashing bundled FolkPatch (KernelPatch)   ";
    ui_print " ============================================";
    sync;
    FP_INSTALL=/dev/tmp/install;
    rm -rf "$FP_INSTALL";
    mkdir -p "$FP_INSTALL";
    unzip -o "$FP_SRC" "assets/*" "lib/*" -d "$FP_INSTALL" >/dev/null 2>&1;
    if [ -f "$FP_INSTALL/assets/InstallAP.sh" ]; then
        chmod -R 755 "$FP_INSTALL/assets" "$FP_INSTALL/lib" 2>/dev/null;
        ( cd "$FP_INSTALL" && sh assets/InstallAP.sh 3 "$OUTFD" "$FP_SRC" ) || true;
        ui_print " [*] FolkPatch (KernelPatch) installation complete.";
    else
        ui_print " [!] FolkPatch installer not found; skipping root step.";
    fi;
fi;
EOS
fi

(cd "$AK_DIR" && zip -r9 "$DIST_DIR/$ZIP_NAME" . -x .git/\* .github/\*)
rm -rf "$AK_DIR" "$DIST_DIR/AnyKernel3-template"
ls -lh "$DIST_DIR/$ZIP_NAME"
echo "Flashable Package: $DIST_DIR/$ZIP_NAME"
