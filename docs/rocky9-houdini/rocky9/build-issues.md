# Rocky 9 Houdini build — issues & fixes

Linux-specific build/render issues hit during the Rocky 9 bring-up of the fork
(2026-07-21). Numbered `L#` to distinguish from the macOS `docs/macos-houdini/
macos/build-issues.md`. Both were the *same underlying theme* — Houdini's own
bundled libraries shadowing the ones MoonRay expects — surfacing at two layers.

---

## Issue L1 — Houdini's `dsolib` on the global `LD_LIBRARY_PATH` breaks fetch + link

### Symptoms (two, initially looked unrelated)
1. `git clone` / `curl https://github.com` from the box:
   `SSL certificate problem: unable to get local issuer certificate`.
2. Later, the deps build failed linking OpenImageIO:
   `undefined reference to TIFFSetDirectory@LIBTIFF_4.0` (and ~40 more).

### Root cause
The box installs Houdini via `/etc/profile.d/houdini-20.5.584.sh` and
`…-20.5.939.sh`, which prepend `/opt/hfs*/dsolib` to `LD_LIBRARY_PATH` and
`/opt/hfs*/bin` to `PATH` for **every** login shell. Houdini's `dsolib` ships:

- **`libcurl.so.4`** whose compiled-in default CA path is a dead SideFX
  build-farm dir (`/home/prisms/builder-new/.../local/ssl/cert.pem`). `curl`/
  `git` load it (not the system libcurl) and can't find any CA → cert error.
  The github chain itself is the genuine public Sectigo/USERTrust chain and
  verifies fine against the box's own `/etc/pki/tls/certs/ca-bundle.crt`
  (`openssl … -CAfile` returns `Verify return code: 0`). **It was never TLS
  interception** — just Houdini's libcurl with a broken default.
- **`libtiff.so.5`** (Houdini's 5.2.5) with *unversioned* symbols. It shadows
  the system `/usr/lib64/libtiff.so` (5.8.0, symbols version-noded `LIBTIFF_4.0`),
  so OIIO — which recorded versioned symbols — fails to link.

### Fix
Scrub every `/hfs*`/`houdini` element from `PATH` and `LD_LIBRARY_PATH` for the
build/render shells: **`docs/rocky9-houdini/rocky9/build-env.sh`** (source it
before every step). Nothing MoonRay builds needs Houdini on `LD_LIBRARY_PATH` —
the deps are generic (`NO_USD`), `husk` self-locates its libs via
`RUNPATH=$ORIGIN/../dsolib`, and `hd_moonray.so` carries `$HFS/dsolib` in its
*own* RUNPATH for USD/pxr. `render-usd.sh` scrubs inline for the same reason
(keeps Houdini's libtiff out of the MoonRay `execComp`/`mcrt` process).

No machine change was made. **Machine-hygiene note (owner's call, needs root):**
those two global `profile.d` files silently break `curl`/`git`/C++ builds for
*every* user on the box; the stale `…-584.sh` also sets GPU OpenCL vars that are
meaningless on a CPU farm node. The clean end-state is to remove both and source
Houdini only when launching it (`cd $HFS && source houdini_setup`). Left as-is
per the "tell me before changing the machine" constraint.

---

## Issue L2 — Houdini's OpenVDB 11 headers shadow the dnf OpenVDB 9.1 → link mismatch

### Symptom
MoonRay build reached 100% compile then failed linking `librendering_geom.so`
and `librendering_shading.so`:
`undefined reference to openvdb::v11_0_sesi::io::…` (and many more).

### Root cause
`v11_0_sesi` is **Houdini's** OpenVDB 11 (SideFX inline namespace). Those two
libs were *compiled* against Houdini's OpenVDB 11 headers but *linked* against
the dnf **OpenVDB 9.1** (`v9_1` namespace) → the versioned symbols don't exist.

Why: the Houdini preset adds `-isystem $HFS/toolkit/include` (needed for USD).
On Linux Makefiles the per-target dep includes land *before* it, so
`installs/include` wins the header race — which is correct for every dep that
lives there (OpenEXR, OIIO, Imath, TBB…). **OpenVDB was the sole exception**:
Rocky 9 took it from the dnf package (`/usr/include`, searched last), so
`<openvdb/…>` missed `installs/include` and fell through to Houdini's v11
headers. Meanwhile the preset's `OpenVDB_ROOT=$DEPS_ROOT` pointed at `installs`
(where OpenVDB wasn't), so the linker grabbed dnf's 9.1. macOS never hit this
because `building/macOS/CMakeLists.txt` **source-builds OpenVDB into `installs`**.

### Fix
Match macOS: source-build OpenVDB 9.1 into `installs` on Rocky 9 too —
`ExternalProject_Add(OpenVDB …)` in `building/Rocky9/CMakeLists.txt`
(+ the portable `OpenVDB.patch`, a `eval` → `eval<>` template fix). Blosc/Boost/
zlib come from dnf (`/usr`); TBB/Imath from `installs`. Now
`installs/include/openvdb` holds 9.1, the already-first `-isystem
installs/include` wins the header race, and `OpenVDB_ROOT=installs` is finally
correct — compile and link agree on 9.1.

Note this also needs a clean MoonRay rebuild after the OpenVDB change: Make
tracks the *old* (Houdini) header paths as `.o` dependencies and won't rebuild
the affected TUs just because a header now resolves elsewhere — wipe
`/opt/MoonRay/build`, reconfigure, rebuild.
