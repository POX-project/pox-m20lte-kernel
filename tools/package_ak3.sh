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
echo "Ensuring Pox Kernel Manager release package is bundled..."
PKM_FOUND=0

# 1. First check local candidates (cached or compiled)
for candidate in "$ROOT_DIR/../pox-begoker/pox-manager/app/build/outputs/apk/debug/app-debug.apk" \
                 "$ROOT_DIR/../pox-begoker/Pox-Kernel-Manager-v2.0.0-M20LTE.apk" \
                 "$ROOT_DIR/../pox-begoker/pox-manager/app/build/outputs/apk/release/app-release-unsigned.apk" \
                 "/tmp/pkm_release/Pox-Kernel-Manager-v2.0.1.apk" \
                 "$ROOT_DIR/PoxKernelManager.apk" \
                 "$ROOT_DIR/dist/PoxKernelManager.apk" \
                 "$ROOT_DIR/../begoker/pox-kernel-manager/app/build/outputs/apk/release/app-release.apk" \
                 "$ROOT_DIR/../begoker/pox-kernel-manager/app/build/outputs/apk/debug/app-debug.apk"; do
    if [ -s "$candidate" ]; then
        if unzip -t "$candidate" >/dev/null 2>&1; then
            echo "Using verified local PoxKernelManager APK from $candidate"
            cp -f "$candidate" "$AK_DIR/PoxKernelManager.apk"
            PKM_FOUND=1
            break
        fi
    fi
done

# 2. If not found locally, download from official GitHub release v2.0.1 or latest release
if [ "$PKM_FOUND" -eq 0 ]; then
    echo "Downloading Pox Kernel Manager v2.0.1 official release..."
    PKM_OFFICIAL_URL="https://github.com/POX-project/pox-kernel-manager/releases/download/v2.0.1/Pox-Kernel-Manager-v2.0.1.apk"
    if curl -f -sL --max-time 45 "$PKM_OFFICIAL_URL" -o "$AK_DIR/PoxKernelManager.apk" 2>/dev/null && unzip -t "$AK_DIR/PoxKernelManager.apk" >/dev/null 2>&1; then
        echo "Successfully downloaded Pox Kernel Manager v2.0.1."
        PKM_FOUND=1
    else
        echo "Fetching latest Pox Kernel Manager release URL from GitHub API..."
        PKM_API_URL=$(curl -sL --max-time 15 https://api.github.com/repos/POX-project/pox-kernel-manager/releases/latest 2>/dev/null | grep "browser_download_url.*Pox-Kernel-Manager.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
        if [ -z "$PKM_API_URL" ]; then
            PKM_API_URL=$(curl -sL --max-time 15 https://api.github.com/repos/POX-project/pox-kernel-manager/releases/latest 2>/dev/null | grep "browser_download_url.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
        fi
        if [ -n "$PKM_API_URL" ]; then
            curl -f -sL --max-time 45 "$PKM_API_URL" -o "$AK_DIR/PoxKernelManager.apk" 2>/dev/null || true
            if unzip -t "$AK_DIR/PoxKernelManager.apk" >/dev/null 2>&1; then
                echo "Successfully downloaded Pox Kernel Manager from $PKM_API_URL."
                PKM_FOUND=1
            fi
        fi
    fi
fi

# 3. If obtained, ensure cached copy at /tmp/pkm_release
if [ "$PKM_FOUND" -eq 1 ] && [ -s "$AK_DIR/PoxKernelManager.apk" ]; then
    mkdir -p /tmp/pkm_release 2>/dev/null || true
    if [ ! -s "/tmp/pkm_release/Pox-Kernel-Manager-v2.0.1.apk" ]; then
        cp -f "$AK_DIR/PoxKernelManager.apk" "/tmp/pkm_release/Pox-Kernel-Manager-v2.0.1.apk" 2>/dev/null || true
    fi
    echo "Bundled PoxKernelManager package: $(ls -lh "$AK_DIR/PoxKernelManager.apk" 2>/dev/null || true)"
else
    echo "Error: Failed to obtain valid PoxKernelManager APK package."
    exit 1
fi

if [ "$VARIANT" = "apatch" ] || [ "$VARIANT" = "folkpatch" ]; then
    echo "Fetching latest FolkPatch release package..."
    FP_FOUND=0
    for cand in "/tmp/ak3_device/FolkPatch.apk" \
                "$ROOT_DIR/FolkPatch.apk" \
                "$ROOT_DIR/dist/FolkPatch.apk"; do
        if [ -s "$cand" ] && unzip -t "$cand" >/dev/null 2>&1; then
            echo "Using local FolkPatch package from $cand"
            cp -f "$cand" "$AK_DIR/FolkPatch.apk"
            FP_FOUND=1
            break
        fi
    done
    if [ "$FP_FOUND" -eq 0 ]; then
        FP_URL=$(curl -sL --max-time 15 https://api.github.com/repos/LyraVoid/FolkPatch/releases/latest 2>/dev/null | grep "browser_download_url.*apk" | head -1 | cut -d : -f 2,3 | tr -d '"' | tr -d ' ')
        if [ -z "$FP_URL" ]; then
            FP_URL="https://github.com/LyraVoid/FolkPatch/releases/latest/download/FolkPatch.apk"
        fi
        curl -f -sL --max-time 30 "$FP_URL" -o "$AK_DIR/FolkPatch.apk" || true
    fi
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

    if [ "$PATCHED" -eq 1 ]; then
        # Already pre-patched at build time. Clean up kpimg to prevent recovery double-patching.
        rm -f "$AK_DIR/kpimg" "$AK_DIR/tools/arm64/kptools"
    else
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

    # 3. Boot-Time Auto-Installer Service (installs silently in background via Android Package Manager)
    cat << 'EOF' > /data/adb/service.d/install_folkpatch.sh
#!/system/bin/sh
(
# Wait in background until sys.boot_completed=1
TIMEOUT=180
ELAPSED=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    [ "$ELAPSED" -ge "$TIMEOUT" ] && break
done
sleep 3

# Disable package verifier so APK installation never freezes
settings put global verifier_verify_adb_installs 0 2>/dev/null || true
settings put global package_verifier_enable 0 2>/dev/null || true
settings put global package_verifier_user_consent -1 2>/dev/null || true
settings put global upload_apk_enable 0 2>/dev/null || true

APK="/data/local/tmp/FolkPatch.apk"
[ -f "$APK" ] || APK="/data/adb/FolkPatch.apk"

if [ -f "$APK" ]; then
    # Install APK silently with all permissions granted
    if pm install -r -g "$APK" 2>/dev/null || pm install -r "$APK" 2>/dev/null; then
        rm -f /data/local/tmp/FolkPatch.apk /data/adb/FolkPatch.apk
        rm -f /data/adb/service.d/install_folkpatch.sh /data/adb/ap/service.d/install_folkpatch.sh
    fi
fi
) &
EOF
    chmod 0755 /data/adb/service.d/install_folkpatch.sh 2>/dev/null;
    cp -f /data/adb/service.d/install_folkpatch.sh /data/adb/ap/service.d/install_folkpatch.sh 2>/dev/null;
    chmod 0755 /data/adb/ap/service.d/install_folkpatch.sh 2>/dev/null;

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
    for priv in /system/priv-app /system_root/system/priv-app /system_root/priv-app /system/system/priv-app; do
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
    mkdir -p /data/local/tmp /data/adb /data/adb/service.d /data/adb/post-fs-data.d /data/adb/ap/service.d /data/adb/ksu/service.d 2>/dev/null || true;
    cp -f "$AKHOME/PoxKernelManager.apk" /data/local/tmp/PoxKernelManager.apk 2>/dev/null || true;
    cp -f "$AKHOME/PoxKernelManager.apk" /data/adb/PoxKernelManager.apk 2>/dev/null || true;
    chmod 0644 /data/local/tmp/PoxKernelManager.apk /data/adb/PoxKernelManager.apk 2>/dev/null || true;

    # 3. Boot-Time Service: Auto-install & Universal Root Pre-Grant across all managers
    cat << 'EOF' > /data/adb/service.d/install_pox_manager.sh
#!/system/bin/sh
# Pox Kernel Manager Auto-Installer & Universal Root Pre-Grant Service

(
# Wait in background until sys.boot_completed=1
TIMEOUT=180
ELAPSED=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    [ "$ELAPSED" -ge "$TIMEOUT" ] && break
done
sleep 3

# Disable package verifier checks so installation never freezes
settings put global verifier_verify_adb_installs 0 2>/dev/null || true
settings put global package_verifier_enable 0 2>/dev/null || true
settings put global package_verifier_user_consent -1 2>/dev/null || true
settings put global upload_apk_enable 0 2>/dev/null || true

APK="/data/local/tmp/PoxKernelManager.apk"
[ -f "$APK" ] || APK="/data/adb/PoxKernelManager.apk"

PKGS="com.pox.kernelmanager com.pox.kernelmanager.debug"

# Install APK if neither variant is already installed
ANY_INSTALLED=0
for P in $PKGS; do
    if pm list packages 2>/dev/null | grep -q "^package:$P$"; then
        ANY_INSTALLED=1
        break
    fi
done

if [ "$ANY_INSTALLED" -eq 0 ] && [ -f "$APK" ]; then
    pm install -r -g "$APK" 2>/dev/null || pm install -r "$APK" 2>/dev/null || true
fi

# Discover UIDs and Pre-Grant Root Across All Root Managers
for PKG in $PKGS; do
    APP_UID=""
    for i in $(seq 1 10); do
        APP_UID=$(pm list packages -U 2>/dev/null | grep "$PKG" | sed -n 's/.*uid:\([0-9]*\).*/\1/p' | head -1)
        [ -n "$APP_UID" ] && break
        APP_UID=$(dumpsys package "$PKG" 2>/dev/null | grep "userId=" | head -1 | sed -n 's/.*userId=\([0-9]*\).*/\1/p')
        [ -n "$APP_UID" ] && break
        if [ -d "/data/data/$PKG" ]; then
            APP_UID=$(stat -c %u "/data/data/$PKG" 2>/dev/null)
            [ -n "$APP_UID" ] && break
        fi
        if [ -d "/data/user/0/$PKG" ]; then
            APP_UID=$(stat -c %u "/data/user/0/$PKG" 2>/dev/null)
            [ -n "$APP_UID" ] && break
        fi
        sleep 1
    done

    # a) Magisk: If /data/adb/magisk.db exists, insert or replace into policies
    if [ -d "/data/adb" ]; then
        MAGISK_DB="/data/adb/magisk.db"
        if [ -f "$MAGISK_DB" ] || [ -d "/data/adb/magisk" ]; then
            if [ -n "$APP_UID" ]; then
                SQL_INIT="CREATE TABLE IF NOT EXISTS policies (uid INTEGER, package_name TEXT, policy INTEGER, until INTEGER, logging INTEGER, notification INTEGER, PRIMARY KEY(uid));"
                SQL_CMD="$SQL_INIT INSERT OR REPLACE INTO policies (uid, package_name, policy, until, logging, notification) VALUES ($APP_UID, '$PKG', 2, 0, 1, 1);"
                if command -v magisk >/dev/null 2>&1; then
                    magisk --sqlite "$SQL_CMD" 2>/dev/null || true
                elif [ -x "/data/adb/magisk/magisk" ]; then
                    /data/adb/magisk/magisk --sqlite "$SQL_CMD" 2>/dev/null || true
                elif [ -x "/data/adb/magisk/sqlite3" ]; then
                    /data/adb/magisk/sqlite3 "$MAGISK_DB" "$SQL_CMD" 2>/dev/null || true
                elif command -v sqlite3 >/dev/null 2>&1; then
                    sqlite3 "$MAGISK_DB" "$SQL_CMD" 2>/dev/null || true
                fi
            fi
        fi
    fi

    # b) KernelSU / KernelSU-Next / BakaSU / SukiSU: Write profile.toml & invoke ksud profile set
    if [ -d "/data/adb/ksu" ] || [ -d "/data/adb" ]; then
        KSU_DIR="/data/adb/ksu"
        mkdir -p "$KSU_DIR" 2>/dev/null || true
        KSU_PROFILE="$KSU_DIR/profile.toml"
        if [ -f "$KSU_PROFILE" ]; then
            if ! grep -q "\[$PKG\]" "$KSU_PROFILE" 2>/dev/null; then
                printf "\n[%s]\nroot = true\nnon_root = false\n" "$PKG" >> "$KSU_PROFILE"
            fi
        else
            printf "[%s]\nroot = true\nnon_root = false\n" "$PKG" > "$KSU_PROFILE"
        fi
        chmod 0600 "$KSU_PROFILE" 2>/dev/null || true

        if command -v ksud >/dev/null 2>&1; then
            ksud profile set "$PKG" root true 2>/dev/null || ksud profile set --root "$PKG" 2>/dev/null || ksud profile set "$PKG" 2>/dev/null || true
        elif [ -x "/data/adb/ksud" ]; then
            /data/adb/ksud profile set "$PKG" root true 2>/dev/null || /data/adb/ksud profile set --root "$PKG" 2>/dev/null || /data/adb/ksud profile set "$PKG" 2>/dev/null || true
        elif [ -x "/data/adb/ksu/bin/ksud" ]; then
            /data/adb/ksu/bin/ksud profile set "$PKG" root true 2>/dev/null || /data/adb/ksu/bin/ksud profile set --root "$PKG" 2>/dev/null || /data/adb/ksu/bin/ksud profile set "$PKG" 2>/dev/null || true
        fi
    fi

    # c) APatch / FolkPatch: Ensure entry in package_config (both CSV and legacy format)
    for AP_DIR in /data/adb/ap /data/adb/apatch; do
        if [ -d "$AP_DIR" ] || [ -d "/data/adb" ]; then
            mkdir -p "$AP_DIR" 2>/dev/null || true
            AP_CONFIG="$AP_DIR/package_config"
            touch "$AP_CONFIG" 2>/dev/null || true
            if [ -n "$APP_UID" ]; then
                # APatch CSV format: pkg,exclude,allow,uid,to_uid,sctx
                if ! grep -q "^$PKG," "$AP_CONFIG" 2>/dev/null; then
                    echo "$PKG,0,1,$APP_UID,0,u:r:magisk:s0" >> "$AP_CONFIG"
                fi
                if ! grep -q "^$APP_UID 1$" "$AP_CONFIG" 2>/dev/null; then
                    echo "$APP_UID 1" >> "$AP_CONFIG"
                fi
            fi
            if ! grep -q "^$PKG 1$" "$AP_CONFIG" 2>/dev/null; then
                echo "$PKG 1" >> "$AP_CONFIG"
            fi
            chmod 0600 "$AP_CONFIG" 2>/dev/null || true
        fi
    done
done

# Clean up staged APKs once installed
for P in $PKGS; do
    if pm list packages 2>/dev/null | grep -q "^package:$P$"; then
        rm -f /data/local/tmp/PoxKernelManager.apk /data/adb/PoxKernelManager.apk
        break
    fi
done
) &
EOF
    chmod 0755 /data/adb/service.d/install_pox_manager.sh 2>/dev/null || true;
    mkdir -p /data/adb/ap/service.d /data/adb/ksu/service.d 2>/dev/null || true;
    cp -f /data/adb/service.d/install_pox_manager.sh /data/adb/ap/service.d/install_pox_manager.sh 2>/dev/null || true;
    cp -f /data/adb/service.d/install_pox_manager.sh /data/adb/ksu/service.d/install_pox_manager.sh 2>/dev/null || true;
    chmod 0755 /data/adb/ap/service.d/install_pox_manager.sh /data/adb/ksu/service.d/install_pox_manager.sh 2>/dev/null || true;

    # 4. Hardware Video Scaler Fix for scrcpy & HW Encoding (All Root Flavors)
    for pdir in /data/adb/post-fs-data.d /data/adb/service.d /data/adb/ap/post-fs-data.d /data/adb/ap/service.d /data/adb/ksu/post-fs-data.d /data/adb/ksu/service.d; do
        mkdir -p "$pdir" 2>/dev/null || true
        cat << 'SCALER_EOF' > "$pdir/00-m2m1shot-scaler.sh"
#!/system/bin/sh
if [ ! -e /dev/m2m1shot_scaler1 ] && [ -e /dev/m2m1shot_scaler0 ]; then
    ln -sf /dev/m2m1shot_scaler0 /dev/m2m1shot_scaler1
    chmod 0660 /dev/m2m1shot_scaler0 /dev/m2m1shot_scaler1 2>/dev/null || true
    chown mediacodec:drmrpc /dev/m2m1shot_scaler1 2>/dev/null || true
fi
SCALER_EOF
        chmod 0755 "$pdir/00-m2m1shot-scaler.sh" 2>/dev/null || true
    done

    # 5. Overclock & Zero-Lag Performance Tuning Service (All Variants)
    cat << 'EOF' > /data/adb/service.d/99-pox-overclock-maxperf.sh
#!/system/bin/sh
# Pox Kernel Onyx Overclock & Zero-Lag Tuning Service
(
# Ensure m2m1shot_scaler1 symlink exists for hardware video encoding & scrcpy
if [ ! -e /dev/m2m1shot_scaler1 ] && [ -e /dev/m2m1shot_scaler0 ]; then
    ln -sf /dev/m2m1shot_scaler0 /dev/m2m1shot_scaler1
    chmod 0660 /dev/m2m1shot_scaler0 /dev/m2m1shot_scaler1 2>/dev/null || true
    chown mediacodec:drmrpc /dev/m2m1shot_scaler1 2>/dev/null || true
fi

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 2

# 1. CPU Interactive Governor Max Clocks & Instant Ramp
for p in /sys/devices/system/cpu/cpu0/cpufreq/interactive /sys/devices/system/cpu/cpu6/cpufreq/interactive /sys/devices/system/cpu/cpufreq/interactive; do
    if [ -d "$p" ]; then
        echo 1 > "$p/boost" 2>/dev/null || true
        echo 1 > "$p/io_is_busy" 2>/dev/null || true
        echo 15 > "$p/go_hispeed_load" 2>/dev/null || true
        echo 25 > "$p/target_loads" 2>/dev/null || true
        echo 19000 > "$p/timer_rate" 2>/dev/null || true
        echo 19000 > "$p/timer_slack" 2>/dev/null || true
        echo 20000 > "$p/min_sample_time" 2>/dev/null || true
    fi
done
[ -f /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq ] && echo 1586000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq 2>/dev/null || true
[ -f /sys/devices/system/cpu/cpu6/cpufreq/interactive/hispeed_freq ] && echo 2184000 > /sys/devices/system/cpu/cpu6/cpufreq/interactive/hispeed_freq 2>/dev/null || true

# 2. HMP Zero-Lag Fast Big Core Scheduling
if [ -d /sys/kernel/hmp ]; then
    echo 1 > /sys/kernel/hmp/aggressive_up_migration 2>/dev/null || true
    echo 0 > /sys/kernel/hmp/packing_enable 2>/dev/null || true
    echo 1 > /sys/kernel/hmp/family_boost 2>/dev/null || true
    echo 1 > /sys/kernel/hmp/selective_boost 2>/dev/null || true
    echo 1 > /sys/kernel/hmp/semiboost 2>/dev/null || true
    echo 8 > /sys/kernel/hmp/load_avg_period_ms 2>/dev/null || true
    echo 8 > /sys/kernel/hmp/sb_load_avg_period_ms 2>/dev/null || true
    echo 100 > /sys/kernel/hmp/up_threshold 2>/dev/null || true
    echo 40 > /sys/kernel/hmp/down_threshold 2>/dev/null || true
    echo 100 > /sys/kernel/hmp/sb_up_threshold 2>/dev/null || true
    echo 40 > /sys/kernel/hmp/sb_down_threshold 2>/dev/null || true
fi

# 3. Mali-G71 GPU 1100 MHz Overclock Lock & DVFS Retention
MALI=/sys/devices/platform/11500000.mali
if [ -d "$MALI" ]; then
    echo 1 > "$MALI/dvfs" 2>/dev/null || true
    echo Interactive > "$MALI/dvfs_governor" 2>/dev/null || true
    echo 1100000 > "$MALI/highspeed_clock" 2>/dev/null || true
    echo 10 > "$MALI/highspeed_load" 2>/dev/null || true
    echo 0 > "$MALI/highspeed_delay" 2>/dev/null || true
    echo always_on > "$MALI/power_policy" 2>/dev/null || true
fi

# 3b. Display & Compositor Big Core Affinity (SurfaceFlinger & Hardware Composer)
for cset in /dev/cpuset; do
    if [ -d "$cset" ]; then
        echo 0-7 > "$cset/system-background/cpus" 2>/dev/null || true
        echo 0-7 > "$cset/foreground/cpus" 2>/dev/null || true
        echo 0-7 > "$cset/top-app/cpus" 2>/dev/null || true
        echo 1 > "$cset/top-app/selective_boost" 2>/dev/null || true
        echo 1 > "$cset/top-app/prio_pinning" 2>/dev/null || true
    fi
done
SF_PID=\$(pidof surfaceflinger)
[ -n "\$SF_PID" ] && taskset -ap ff "\$SF_PID" 2>/dev/null || true
HWC_PID=\$(pidof android.hardware.composer.hwc3-service.slsi)
[ -n "\$HWC_PID" ] && taskset -ap ff "\$HWC_PID" 2>/dev/null || true

# 4. Devfreq Memory Bus (MIF) & Interconnect (INT) Ceiling
for dm in /sys/devices/platform/17000000.exynos-dm/exynos_dm; do
    if [ -d "$dm" ]; then
        [ -f "$dm/dm_mif/min_freq" ] && echo 1794000 > "$dm/dm_mif/min_freq" 2>/dev/null || true
        [ -f "$dm/dm_int/min_freq" ] && echo 533000 > "$dm/dm_int/min_freq" 2>/dev/null || true
    fi
done

# 5. eMMC Flash Storage Zero-Latency Queue
for blk in /sys/block/mmcblk0/queue; do
    if [ -d "$blk" ]; then
        echo noop > "$blk/scheduler" 2>/dev/null || true
        echo 512 > "$blk/read_ahead_kb" 2>/dev/null || true
        echo 0 > "$blk/iostats" 2>/dev/null || true
        echo 0 > "$blk/add_random" 2>/dev/null || true
    fi
done

# 6. Memory & LMK Contention Elimination
setprop sys.lmk.minfree_levels "25600:0,38400:100,51200:200,64000:250,89600:800,115200:900"
echo "25600,38400,51200,64000,89600,115200" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null || true
echo 60 > /proc/sys/vm/swappiness 2>/dev/null || true
echo 60 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true
echo 0 > /proc/sys/vm/page-cluster 2>/dev/null || true
echo 10 > /proc/sys/vm/dirty_ratio 2>/dev/null || true
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true

# 7. Pox Core Engine Engagement
[ -f /proc/perfmgr/gaming_mode ] && echo 2 > /proc/perfmgr/gaming_mode 2>/dev/null || true
[ -f /sys/kernel/gaming_mode ] && echo 2 > /sys/kernel/gaming_mode 2>/dev/null || true
[ -f /sys/kernel/kprofiles/kp_mode ] && echo 3 > /sys/kernel/kprofiles/kp_mode 2>/dev/null || true
[ -f /sys/kernel/sched_bore/sched_bore ] && echo 1 > /sys/kernel/sched_bore/sched_bore 2>/dev/null || true
) &
EOF
    chmod 0755 /data/adb/service.d/99-pox-overclock-maxperf.sh 2>/dev/null || true;
    cp -f /data/adb/service.d/99-pox-overclock-maxperf.sh /data/adb/ap/service.d/99-pox-overclock-maxperf.sh 2>/dev/null || true;
    cp -f /data/adb/service.d/99-pox-overclock-maxperf.sh /data/adb/ksu/service.d/99-pox-overclock-maxperf.sh 2>/dev/null || true;
    chmod 0755 /data/adb/ap/service.d/99-pox-overclock-maxperf.sh /data/adb/ksu/service.d/99-pox-overclock-maxperf.sh 2>/dev/null || true;

    ui_print " [*] Pox Kernel Manager auto-install & overclock tuning configured.";
fi;
EOS

(cd "$AK_DIR" && zip -r9 -y "$DIST_DIR/$ZIP_NAME" . -x .git/\* .github/\*)
rm -rf "$AK_DIR" "$DIST_DIR/AnyKernel3-template"
ls -lh "$DIST_DIR/$ZIP_NAME"
echo "Flashable Package: $DIST_DIR/$ZIP_NAME"
