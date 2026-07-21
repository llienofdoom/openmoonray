---
name: package-install
description: Package the compiled MoonRay-for-Houdini install into a dated, deployable zip (moonray-houdini-<os>-<YYYY-MM-DD>.zip) and move it to a destination the user gives. Use when asked to package, zip, bundle, snapshot, or ship the build for deploying to test machines or the render farm.
---

# Package the MoonRay-Houdini install for deployment

Bundles the locally-built MoonRay-for-Houdini `installs/` tree into a dated zip and
moves it to a destination the user specifies. Runs on either dev machine (macOS or
Rocky 9 Linux) — it auto-detects the OS.

## Usage

Run the helper with the destination directory as the only argument:

```bash
.claude/skills/package-install/package-installs.sh <destination-dir>
```

- **macOS** zips `/Applications/MoonRay/installs` → `moonray-houdini-macos-<YYYY-MM-DD>.zip`
- **Linux** zips `/opt/MoonRay/installs` → `moonray-houdini-linux-<YYYY-MM-DD>.zip`

The **destination is required and intentionally not hard-coded** — deploy locations are
personal / site-specific. Ask the user where to put it; never bake a path into the skill or
script. (To package the Linux build, run the script on the Linux box — over SSH is fine.)

## What it produces

- A zip whose root is **`MoonRay/installs/...`** (symlinks preserved). To deploy on a target:
  unzip it, then place the resulting `MoonRay/` folder at `/opt` (Linux) or `/Applications`
  (macOS), giving `/opt/MoonRay/installs` or `/Applications/MoonRay/installs`.
- The zip is staged on local disk first, then moved to the destination.

## Prerequisites & caveats

- Needs `zip` (present on macOS; on Rocky 9 `sudo dnf install -y zip` if missing) and a few
  GB of scratch in `$TMPDIR`/`/var/tmp` plus space at the destination.
- The tree must be deployed at the **same absolute path** it was built at (`/opt/MoonRay` or
  `/Applications/MoonRay`) — RUNPATHs are absolute.
- **The zip is only the compiled tree.** A target machine also needs, outside the zip:
  Houdini 20.5.939 at the same path, and **(Linux only) the dnf runtime packages** — the
  Linux `installs/` links ~90 system libraries and is *not* self-contained (macOS `installs/`
  is). See `docs/rocky9-houdini/rocky9/`.
