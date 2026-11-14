#!/usr/bin/env bash
#
# package_ak3.sh - Package flashable AnyKernel3 zip for Samsung Galaxy M20 (m20lte)
#
set -euo pipefail

VARIANT="${1:-vanilla}"
EDITION="${2:-Onyx}"
ZIP_NAME="${3:-Pox-Kernel-2.1-Onyx-m20lte.zip}"

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

# Fetch and bundle Pox Kernel Manager APK for ALL variants
echo "Fetching latest Pox Kernel Manager release package..."
PKM_URL=$(curl -sL --max-time 15 https://api.github.com/repos/POX-project/pox-kernel-manager/releases/latest 2>/dev/null | grep "browser_download_url.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
if [ -z "$PKM_URL" ]; then
    PKM_URL="https://github.com/POX-project/pox-kernel-manager/releases/latest/download/Pox-Kernel-Manager.apk"
fi
curl -sL --max-time 30 "$PKM_URL" -o "$AK_DIR/PoxKernelManager.apk" || true
if [ ! -s "$AK_DIR/PoxKernelManager.apk" ]; then
    for candidate in "$ROOT_DIR/../begoker/pox-kernel-manager/app/build/outputs/apk/release/app-release.apk" \
                     "$ROOT_DIR/../begoker/pox-kernel-manager/app/build/outputs/apk/debug/app-debug.apk" \
                     "$ROOT_DIR/../pox-begoker/Pox-Kernel-Manager-v2.0.0-M20LTE.apk" \
                     "/tmp/pkm_release/Pox-Kernel-Manager-v2.0.1.apk"; do
        if [ -s "$candidate" ]; then
            echo "Using cached/compiled PoxKernelManager APK from $candidate"
            cp -f "$candidate" "$AK_DIR/PoxKernelManager.apk"
            break
        fi
    done
fi
if [ -s "$AK_DIR/PoxKernelManager.apk" ]; then
    echo "Bundled PoxKernelManager package: $(ls -lh "$AK_DIR/PoxKernelManager.apk" 2>/dev/null || true)"
else
    echo "Warning: PoxKernelManager package download did not succeed."
fi

if [ "$VARIANT" = "apatch" ] || [ "$VARIANT" = "folkpatch" ]; then
    echo "Fetching latest FolkPatch release package..."
    FP_URL=$(curl -sL --max-time 15 https://api.github.com/repos/LyraVoid/FolkPatch/releases/latest 2>/dev/null | grep "browser_download_url.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
    if [ -z "$FP_URL" ]; then
        FP_URL="https://github.com/LyraVoid/FolkPatch/releases/latest/download/FolkPatch.apk"
    fi
    curl -sL --max-time 30 "$FP_URL" -o "$AK_DIR/FolkPatch.apk" || true
    if [ -s "$AK_DIR/FolkPatch.apk" ]; then
        echo "Bundled FolkPatch package: $(ls -lh "$AK_DIR/FolkPatch.apk" 2>/dev/null || true)"
    else
        echo "Warning: FolkPatch package download did not succeed."
    fi

    # Fetch kptools-linux for build-time kernel patching
    KPTOOLS="$ROOT_DIR/tools/kptools-linux"
    if [ ! -f "$KPTOOLS" ]; then
        curl -sL --max-time 20 https://github.com/bmax121/KernelPatch/releases/download/0.13.9/kptools-linux -o "$KPTOOLS" || true
        chmod +x "$KPTOOLS" 2>/dev/null || true
    fi

    # Bundle kptools-android into AnyKernel3 tools/arm64 as recovery fallback patcher
    mkdir -p "$AK_DIR/tools/arm64"
    KPTOOLS_ARM64="$AK_DIR/tools/arm64/kptools"
    curl -sL --max-time 20 https://github.com/bmax121/KernelPatch/releases/download/0.13.9/kptools-android -o "$KPTOOLS_ARM64" || true
    chmod +x "$KPTOOLS_ARM64" 2>/dev/null || true

    PATCHED=0
    if [ -s "$AK_DIR/FolkPatch.apk" ]; then
        echo "Extracting kpimg from FolkPatch package..."
        unzip -p "$AK_DIR/FolkPatch.apk" assets/kpimg > "$DIST_DIR/kpimg" 2>/dev/null || true
        if [ -s "$DIST_DIR/kpimg" ]; then
            # Bundle kpimg into AnyKernel3 root for recovery auto-patcher
            cp -f "$DIST_DIR/kpimg" "$AK_DIR/kpimg"
            if [ -x "$KPTOOLS" ]; then
                echo "Pre-patching kernel Image with KernelPatch (SuperKey: poxkernel)..."
                if "$KPTOOLS" -p -i "$DIST_DIR/Image-m20lte" -k "$DIST_DIR/kpimg" -s "poxkernel" -o "$AK_DIR/zImage"; then
                    echo "Successfully pre-patched kernel with KernelPatch."
                    PATCHED=1
                fi
            fi
            rm -f "$DIST_DIR/kpimg"
        fi
    fi

    if [ "$PATCHED" -eq 0 ]; then
        echo "Using raw Image for AnyKernel3 (recovery will patch via kptools)."
        cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
    fi
else
    cp "$DIST_DIR/Image-m20lte" "$AK_DIR/zImage"
fi

cat > "$AK_DIR/anykernel.sh" << EOS
# AnyKernel3 Ramdisk Mod Script
# Pox Kernel 2.1-${EDITION} for Samsung Galaxy M20 (m20lte) by txorav

### AnyKernel setup
properties() { '
kernel.string=Pox Kernel 2.1-${EDITION} for Samsung Galaxy M20 (m20lte) by txorav
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
ui_print "   POX KERNEL 2.1 [${EDITION}]        ";
ui_print "   Samsung Galaxy M20 (universal7885)        ";
ui_print " ============================================";
ui_print "  * Engine       : Zero Frame-Drop Gaming Core";
ui_print "  * Kprofiles    : Tri-State LCD Auto-Governor";
ui_print "  * Health Engine: OPP Dynamic Silicon Guard ";
ui_print "  * Battery Care : Bypass & Current Limiting ";
ui_print "  * Display Mode : iOS D65 Calibrated Reference";
ui_print "  * Root Flavor  : ${EDITION}";
EOS

if [ "$VARIANT" = "apatch" ] || [ "$VARIANT" = "folkpatch" ]; then
    cat >> "$AK_DIR/anykernel.sh" << 'EOS'
ui_print "  * Root Method  : FolkPatch / KernelPatch Embedded";
ui_print "  * SuperKey     : poxkernel";
EOS
fi

cat >> "$AK_DIR/anykernel.sh" << 'EOS'
ui_print " --------------------------------------------";

# Auto-patch kernel image in recovery if unpatched and kptools is present
if [ -f "$AKHOME/kpimg" ]; then
    KP_BIN="$AKHOME/tools/arm64/kptools"
    [ -x "$KP_BIN" ] || KP_BIN="$AKHOME/tools/kptools"
    if [ -x "$KP_BIN" ]; then
        if "$KP_BIN" -p -i "$AKHOME/zImage" -k "$AKHOME/kpimg" -s "poxkernel" -o "$AKHOME/zImage-patched" 2>/dev/null; then
            mv -f "$AKHOME/zImage-patched" "$AKHOME/zImage";
            ui_print " [*] Applied FolkPatch (KernelPatch) to kernel.";
        fi;
    fi;
fi;

dump_boot;
write_boot;
EOS

if [ "$VARIANT" = "apatch" ] || [ "$VARIANT" = "folkpatch" ]; then
    cat >> "$AK_DIR/anykernel.sh" << 'EOS'

## FolkPatch Auto-Installation & Staging
if [ -f "$AKHOME/FolkPatch.apk" ]; then
    ui_print " [*] Configuring FolkPatch auto-install...";

    # Ensure /data and /system are accessible
    mount /data 2>/dev/null || true;
    mount -o rw /system 2>/dev/null || mount -o rw /system_root 2>/dev/null || true;

    # 1. Direct System Priv-App install if /system is writable
    INSTALLED_SYS=0;
    for priv in /system/priv-app /system_root/system/priv-app; do
        if [ -d "$priv" ] && [ -w "$priv" ]; then
            mkdir -p "$priv/FolkPatch" 2>/dev/null;
            if cp -f "$AKHOME/FolkPatch.apk" "$priv/FolkPatch/FolkPatch.apk" 2>/dev/null; then
                chmod 0755 "$priv/FolkPatch" 2>/dev/null;
                chmod 0644 "$priv/FolkPatch/FolkPatch.apk" 2>/dev/null;
                chcon u:object_r:system_file:s0 "$priv/FolkPatch/FolkPatch.apk" 2>/dev/null || true;
                ui_print " [*] Pre-installed FolkPatch to $priv/FolkPatch";
                INSTALLED_SYS=1;
                break;
            fi;
        fi;
    done;

    # 2. Stage to /data/local/tmp and /data/adb
    mkdir -p /data/local/tmp /data/adb/service.d /data/adb/post-fs-data.d /data/adb/ap/service.d 2>/dev/null;
    cp -f "$AKHOME/FolkPatch.apk" /data/local/tmp/FolkPatch.apk 2>/dev/null;
    cp -f "$AKHOME/FolkPatch.apk" /data/adb/FolkPatch.apk 2>/dev/null;
    chmod 0644 /data/local/tmp/FolkPatch.apk /data/adb/FolkPatch.apk 2>/dev/null;

    # 3. Boot-Time Auto-Installer Service (installs silently via Android Package Manager)
    cat << 'EOF' > /data/adb/service.d/install_folkpatch.sh
#!/system/bin/sh
# Wait for Android Package Manager to become fully ready
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 3

APK="/data/local/tmp/FolkPatch.apk"
[ -f "$APK" ] || APK="/data/adb/FolkPatch.apk"

if [ -f "$APK" ]; then
    # Install APK silently with all permissions granted
    if pm install -r -g "$APK"; then
        rm -f /data/local/tmp/FolkPatch.apk /data/adb/FolkPatch.apk
        rm -f /data/adb/service.d/install_folkpatch.sh /data/adb/ap/service.d/install_folkpatch.sh
    fi
fi
EOF
    chmod 0755 /data/adb/service.d/install_folkpatch.sh 2>/dev/null;
    cp -f /data/adb/service.d/install_folkpatch.sh /data/adb/ap/service.d/install_folkpatch.sh 2>/dev/null;
    chmod 0755 /data/adb/ap/service.d/install_folkpatch.sh 2>/dev/null;

    # 4. Storage fallback copy
    for dest in /sdcard /data/media/0; do
        if [ -d "$dest" ]; then
            cp -f "$AKHOME/FolkPatch.apk" "$dest/FolkPatch.apk" 2>/dev/null;
            chmod 0644 "$dest/FolkPatch.apk" 2>/dev/null;
        fi;
    done;

    ui_print " [*] FolkPatch auto-install configured (SuperKey: poxkernel).";
fi;
EOS
fi

cat >> "$AK_DIR/anykernel.sh" << 'EOS'

## Pox Kernel Manager Auto-Installation & Root Pre-Granting (All Variants)
if [ -f "$AKHOME/PoxKernelManager.apk" ]; then
    ui_print " [*] Configuring Pox Kernel Manager auto-install...";

    # Ensure /data and /system are accessible
    mount /data 2>/dev/null || true;
    mount -o rw /system 2>/dev/null || mount -o rw /system_root 2>/dev/null || true;

    # 1. Direct System Priv-App install if /system is writable
    INSTALLED_SYS=0;
    for priv in /system/priv-app /system_root/system/priv-app; do
        if [ -d "$priv" ] && [ -w "$priv" ]; then
            mkdir -p "$priv/PoxKernelManager" 2>/dev/null;
            if cp -f "$AKHOME/PoxKernelManager.apk" "$priv/PoxKernelManager/PoxKernelManager.apk" 2>/dev/null; then
                chmod 0755 "$priv/PoxKernelManager" 2>/dev/null;
                chmod 0644 "$priv/PoxKernelManager/PoxKernelManager.apk" 2>/dev/null;
                chcon u:object_r:system_file:s0 "$priv/PoxKernelManager/PoxKernelManager.apk" 2>/dev/null || true;
                ui_print " [*] Pre-installed Pox Kernel Manager to $priv/PoxKernelManager";
                INSTALLED_SYS=1;
                break;
            fi;
        fi;
    done;

    # 2. Stage fallback APK to /data/local/tmp and /data/adb
    mkdir -p /data/local/tmp /data/adb/service.d /data/adb/post-fs-data.d /data/adb/ap/service.d /data/adb/ksu/service.d 2>/dev/null || true;
    cp -f "$AKHOME/PoxKernelManager.apk" /data/local/tmp/PoxKernelManager.apk 2>/dev/null || true;
    cp -f "$AKHOME/PoxKernelManager.apk" /data/adb/PoxKernelManager.apk 2>/dev/null || true;
    chmod 0644 /data/local/tmp/PoxKernelManager.apk /data/adb/PoxKernelManager.apk 2>/dev/null || true;

    # 3. Storage fallback copies (internal & external)
    for dest in /sdcard /data/media/0 /sdcard1; do
        if [ -d "$dest" ]; then
            cp -f "$AKHOME/PoxKernelManager.apk" "$dest/PoxKernelManager.apk" 2>/dev/null || true;
            chmod 0644 "$dest/PoxKernelManager.apk" 2>/dev/null || true;
        fi;
    done;

    # 4. Boot-Time Service: Auto-install & Universal Root Pre-Grant across all managers
    cat << 'EOF' > /data/adb/service.d/install_pox_manager.sh
#!/system/bin/sh
# Pox Kernel Manager Auto-Installer & Universal Root Pre-Grant Service

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 3

PKG="com.pox.kernelmanager"
APK="/data/local/tmp/PoxKernelManager.apk"
[ -f "$APK" ] || APK="/data/adb/PoxKernelManager.apk"
[ -f "$APK" ] || APK="/sdcard1/PoxKernelManager.apk"
[ -f "$APK" ] || APK="/sdcard/PoxKernelManager.apk"

if ! pm list packages 2>/dev/null | grep -q "^package:$PKG$"; then
    if [ -f "$APK" ]; then
        pm install -r -g "$APK" 2>/dev/null || pm install -r "$APK" 2>/dev/null
    fi
fi

# Discover app UID
APP_UID=""
for i in $(seq 1 15); do
    APP_UID=$(pm list packages -U 2>/dev/null | grep "^package:$PKG " | sed -E 's/.*uid:([0-9]+).*/\1/')
    [ -n "$APP_UID" ] && break
    APP_UID=$(dumpsys package "$PKG" 2>/dev/null | grep "userId=" | head -1 | sed -E 's/.*userId=([0-9]+).*/\1/')
    [ -n "$APP_UID" ] && break
    if [ -d "/data/data/$PKG" ]; then
        APP_UID=$(stat -c %u "/data/data/$PKG" 2>/dev/null)
        [ -n "$APP_UID" ] && break
    fi
    sleep 2
done

# Universal Root Pre-Grant Across All Managers:

# 1. Magisk (/data/adb/magisk.db policies)
# policy: 2=ALLOW, 1=DENY, 0=INTERACTIVE
if [ -d "/data/adb" ]; then
    MAGISK_DB="/data/adb/magisk.db"
    if [ -n "$APP_UID" ]; then
        SQL_CMD="INSERT OR REPLACE INTO policies (uid, package_name, policy, until, logging, notification) VALUES ($APP_UID, '$PKG', 2, 0, 1, 1);"
        if command -v magisk >/dev/null 2>&1; then
            magisk --sqlite "$SQL_CMD" 2>/dev/null || true
        elif [ -x "/data/adb/magisk/sqlite3" ]; then
            /data/adb/magisk/sqlite3 "$MAGISK_DB" "$SQL_CMD" 2>/dev/null || true
        elif command -v sqlite3 >/dev/null 2>&1; then
            sqlite3 "$MAGISK_DB" "$SQL_CMD" 2>/dev/null || true
        fi
    fi
fi

# 2. KernelSU / KernelSU-Next / BakaSU / SukiSU
if [ -d "/data/adb/ksu" ]; then
    if command -v ksud >/dev/null 2>&1; then
        ksud profile set "$PKG" root true 2>/dev/null || true
    elif [ -x "/data/adb/ksu/bin/ksud" ]; then
        /data/adb/ksu/bin/ksud profile set "$PKG" root true 2>/dev/null || true
    fi

    KSU_PROFILE="/data/adb/ksu/profile.toml"
    if [ -f "$KSU_PROFILE" ]; then
        if ! grep -q "\[$PKG\]" "$KSU_PROFILE"; then
            printf "\n[%s]\nroot = true\nnon_root = false\n" "$PKG" >> "$KSU_PROFILE"
        fi
    else
        printf "[%s]\nroot = true\nnon_root = false\n" "$PKG" > "$KSU_PROFILE"
    fi
    chmod 0600 "$KSU_PROFILE" 2>/dev/null || true
fi

# 3. APatch / FolkPatch / KernelPatch
for AP_DIR in /data/adb/ap /data/adb/apatch; do
    if [ -d "$AP_DIR" ]; then
        AP_CONFIG="$AP_DIR/package_config"
        if [ -n "$APP_UID" ]; then
            if [ -f "$AP_CONFIG" ]; then
                if ! grep -q "$PKG" "$AP_CONFIG"; then
                    echo "$PKG 1" >> "$AP_CONFIG"
                    echo "$APP_UID 1" >> "$AP_CONFIG"
                fi
            else
                echo "$PKG 1" > "$AP_CONFIG"
                echo "$APP_UID 1" >> "$AP_CONFIG"
            fi
            chmod 0600 "$AP_CONFIG" 2>/dev/null || true
        fi
    fi
done

if pm list packages 2>/dev/null | grep -q "^package:$PKG$"; then
    rm -f /data/local/tmp/PoxKernelManager.apk /data/adb/PoxKernelManager.apk
fi
EOF
    chmod 0755 /data/adb/service.d/install_pox_manager.sh 2>/dev/null || true;
    mkdir -p /data/adb/ap/service.d /data/adb/ksu/service.d 2>/dev/null || true;
    cp -f /data/adb/service.d/install_pox_manager.sh /data/adb/ap/service.d/install_pox_manager.sh 2>/dev/null || true;
    cp -f /data/adb/service.d/install_pox_manager.sh /data/adb/ksu/service.d/install_pox_manager.sh 2>/dev/null || true;
    chmod 0755 /data/adb/ap/service.d/install_pox_manager.sh /data/adb/ksu/service.d/install_pox_manager.sh 2>/dev/null || true;

    ui_print " [*] Pox Kernel Manager auto-install & root grants configured.";
fi;
EOS

(cd "$AK_DIR" && zip -r9 -y "$DIST_DIR/$ZIP_NAME" . -x .git/\* .github/\*)
rm -rf "$AK_DIR" "$DIST_DIR/AnyKernel3-template"
ls -lh "$DIST_DIR/$ZIP_NAME"
echo "Flashable Package: $DIST_DIR/$ZIP_NAME"
