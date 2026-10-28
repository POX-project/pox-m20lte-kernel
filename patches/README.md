# Patch Sets (`patches/`)

`onyx` is the single source branch for Samsung Galaxy M20 (`m20lte` / `universal7885`). Root flavors are patch sets applied **at build time** — no per-variant branches, no merge conflicts when upstream updates land.

## Roots

| Variant | Kernel side | Manager / flashing |
| --- | --- | --- |
| `vanilla` | none (onyx base, `exynos7885-m20_gsi_defconfig`) | none (strict stock Play Integrity) |
| `apatch` | `apatch.patch` (`exynos7885-m20_apatch_defconfig`) | latest FolkPatch APK bundled, auto-flashed during AnyKernel3 flash |
| `ksu-next` | `ksu.patch` (KernelSU-Next legacy hooks + Samsung Exynos SELinux flex_array fix + `exynos7885-m20_ksu_next_defconfig`) | KernelSU-Next Manager |

## Selecting a variant

Local:

```bash
# Vanilla (clean Onyx)
./build.sh vanilla

# APatch / FolkPatch
./build.sh apatch

# KernelSU-Next
./build.sh ksu-next

# Clean / restore onyx tree
./build.sh clean
```

GitHub Actions: **Build Pox Kernel for Samsung Galaxy M20 (m20lte)** builds all 3 variants (`vanilla`, `apatch`, `ksu-next`) in parallel using a build matrix on every push to `onyx`.

## Patch sets

| Patch | Files | Notes |
| --- | --- | --- |
| `apatch.patch` | `arch/arm64/configs/exynos7885-m20_apatch_defconfig` | Enables `CONFIG_KALLSYMS_ALL`, `CONFIG_KPROBES` for APatch / KernelPatch |
| `ksu.patch` | Exynos manual syscall hooks (`fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/namespace.c`, `drivers/input/input.c`, `kernel/reboot.c`), SELinux SEC flex_array fix, `exynos7885-m20_ksu_next_defconfig` | Connects KernelSU-Next legacy engine to Samsung Exynos 7885/7904 |
