# Patch Sets (`patches/`)

`onyx` is the single source branch for Samsung Galaxy M20 (`m20lte` / `universal7904` / `universal7885`) running Android 15 (LineageOS 22.2 base). Root flavors are patch sets applied **at build time** — no per-variant branches, no merge conflicts when upstream updates land.

## Roots

| Variant | Kernel side | Manager / flashing |
| --- | --- | --- |
| `vanilla` | none (clean Onyx base, `m20lte_defconfig`) | none (strict stock Play Integrity) |
| `apatch` | `apatch.patch` (`m20lte_defconfig` with `-Pox-2.1.0-Onyx-APatch`) | KernelPatch pre-patched Image via `kptools`, FolkPatch APK bundled |

## Selecting a variant

Local:

```bash
# Vanilla (clean Onyx)
./build.sh vanilla

# APatch / FolkPatch
./build.sh apatch

# Clean / restore onyx tree
./build.sh clean
```

GitHub Actions: **Build Pox Kernel for Samsung Galaxy M20 (m20lte)** builds both variants (`vanilla`, `apatch`) in parallel using a build matrix on every push to `onyx`.
