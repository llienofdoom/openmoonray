# Building the MoonRay fork on Rocky Linux 9 (headless, CPU-only, Houdini)

Companion to the macOS build (`docs/macos-houdini/macos/macos-build.md`). Same
shared branch (`macos-houdini`), same Houdini front-end (hdMoonray delegate),
built against **Houdini 20.5.939 / Python 3.11 / USD 24.3**. Target is a
**headless, CPU-only render server** — no Qt/GUI, no CUDA/OptiX. USD comes from
Houdini (`NO_USD` deps). Render sign-off validated on `luma@…` (Rocky 9.x, 8
cores), 2026-07-21.

Layout mirrors macOS but rooted at **`/opt/MoonRay`** instead of
`/Applications/MoonRay`:

```
/opt/MoonRay/{source,build-deps,build,installs}
             installs/openmoonray-houdini   <- CMAKE_INSTALL_PREFIX (delegate + runtime)
/opt/hfs20.5.939                            <- Houdini
```

## 0. The one non-obvious gotcha: scrub Houdini from the build shell

The box installs Houdini via `/etc/profile.d/houdini-20.5.*.sh`, which forces
`/opt/hfs*/dsolib` onto `LD_LIBRARY_PATH` and `/opt/hfs*/bin` onto `PATH` in
**every** login shell. Houdini's `dsolib` ships its own `libcurl` (dead CA path)
and `libtiff` (unversioned symbols) that shadow the system libs and break the
build (github fetch fails; OpenImageIO fails to link). **Source `build-env.sh`
before every build/render step** — it scrubs Houdini out of the shell (nothing
we build needs it there; see `build-issues.md` Issue L1). Copy it to the box:

```bash
cp docs/rocky9-houdini/rocky9/build-env.sh /opt/MoonRay/build-env.sh
```

## 1. Packages (dnf) — headless, no CUDA

```bash
cd /opt/MoonRay/source/openmoonray
sudo bash building/Rocky9/install_packages.sh --noqt --nocuda
```

`--noqt` drops Qt5 (no GUI). `--nocuda` is safe because the Houdini preset sets
`MOONRAY_USE_OPTIX=NO`. (`install_packages.sh` also `wget`s a CMake tarball
unconditionally — skip it if the box already has cmake ≥ 3.23.1; this box has
3.26.5.)

## 2. Dependencies from source (NO_USD)

```bash
source /opt/MoonRay/build-env.sh
cd /opt/MoonRay/build-deps
cmake -DNO_USD=1 ../source/openmoonray/building/Rocky9
cmake --build . -- -j $(nproc)
```

Fetches from github (works once Houdini's libcurl is scrubbed). USD is skipped —
Houdini provides it. **OpenVDB 9.1 is now source-built here** (added for the
Houdini build — see `build-issues.md` Issue L2); it lands in
`installs/{include/openvdb,lib64/libopenvdb.so.9.1}`.

## 3. Configure + build + install MoonRay

```bash
source /opt/MoonRay/build-env.sh
cd /opt/MoonRay/source/openmoonray
cmake --preset rocky9-houdini-release          # BUILD_QT_APPS=NO, BUILD_TESTING=OFF, MOONRAY_USE_OPTIX=NO
cmake --build --preset rocky9-houdini-release -- -j $(nproc)
cmake --build --preset rocky9-houdini-release --target install -- -j $(nproc)
```

Installs the delegate (`plugin/hd_moonray.so`, `plugin/pxr/hd_moonray/`), the
MoonRay runtime, and the Arras render path (`execComp`, `mcrt_*`) to
`installs/openmoonray-houdini`.

## 4. Generate shader_json (one-time)

```bash
source /opt/MoonRay/build-env.sh
OMR=/opt/MoonRay/installs/openmoonray-houdini
source $OMR/scripts/setup.sh
export RDL2_DSO_PATH=$OMR/rdl2dso
$OMR/bin/rdl2_json_exporter --out $OMR/shader_json --sparse
```

## 5. Render sign-off (husk)

The render helper is the cross-OS `scripts/render-usd.sh`, installed to
`$OMR/bin/render-usd` by the build (first arg = input USD; remaining args pass
through to husk). On Linux it scrubs Houdini's `dsolib` itself and sets the
minimal husk env (never source `setup.sh` for husk — its PYTHONPATH crashes it).

```bash
export HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla   # optional: dump the translated RDL2 scene
$OMR/bin/render-usd \
    moonray/hydra/hdMoonray/testSuite/geometry/two_triangles_delta/scene.usd \
    --frame 1 --output /tmp/out.exr
```

Verified: exit 0, non-black EXR (avg ≈0.22, max ≈2.69), RDL2 dump with
`RdlMeshGeometry` + `PerspectiveCamera` + `UsdPreviewSurface` + `DistantLight`,
arras/mcrt on CPU.

**OIDN denoise on CPU** (the CPU-only payoff): the delegate auto-selects OIDN
because OptiX is compiled out (`MOONRAY_USE_OPTIX=NO` ⇒ `HDMOONRAY_NO_OPTIX`;
hdMoonray `ArrasSettings.cc:302`). Verify:

```bash
export HDMOONRAY_ENABLE_DENOISE=true     # deliberately DON'T set _OIDN — exercises the auto-select
$OMR/bin/render-usd .../two_triangles_delta/scene.usd --frame 1 --output /tmp/denoise.exr
```

Confirmed: render succeeds with **no** `"Optix mode not supported in this build"`
abort — proving the Phase-1 guard + `MOONRAY_USE_OPTIX=NO` path works headless.
