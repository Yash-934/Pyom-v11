# Bundled proot binaries

Place proot static binaries here to bundle them inside the APK.
This is the MOST RELIABLE method — no network needed for proot step.

## How to add:

### Option A — Download from releases page (recommended):
1. Go to: https://github.com/proot-me/proot/releases/latest
2. Download `proot-aarch64` (for ARM64 phones) and/or `proot-x86_64` (for x86 emulators)
3. Rename and place them as:
   - assets/bin/proot-arm64     (for ARM64 devices - most phones)
   - assets/bin/proot-x86_64   (for x86/emulator)

### Option B — Build from source:
```
git clone https://github.com/proot-me/proot && cd proot
make -C src proot LDFLAGS=-static
```

### Option C — Use termux's proot:
Download from: https://packages.termux.dev/apt/termux-main/pool/stable/main/p/proot/
Extract the .deb and use the binary inside.

If these files are present, the app will use them instead of downloading.
If not present, the app will try to download from multiple sources automatically.
