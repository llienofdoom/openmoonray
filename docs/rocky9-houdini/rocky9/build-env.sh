# MoonRay build/render environment (Rocky 9 / Houdini). Source this before any
# deps build, MoonRay build, shader_json export, or husk render on the box.
#
# Why this exists: the render box installs Houdini via /etc/profile.d/
# houdini-20.5.*.sh, which prepends /opt/hfs*/dsolib to LD_LIBRARY_PATH and
# /opt/hfs*/bin to PATH in EVERY login shell. Houdini's dsolib ships its own
# libcurl (built-in CA path points at a dead SideFX build-farm dir) and libtiff
# (unversioned symbols), which shadow the system libs and break the build:
#   - curl/git: "unable to get local issuer certificate" (github fetch fails)
#   - OpenImageIO link: undefined reference to TIFF...@LIBTIFF_4.0
#   - MoonRay execComp at render time would pick Houdini's libtiff too
# None of MoonRay's build/runtime needs Houdini on LD_LIBRARY_PATH: the deps are
# generic (NO_USD), husk self-locates its libs via RUNPATH ($ORIGIN/../dsolib),
# and hd_moonray.so carries /opt/hfs*/dsolib in its OWN RUNPATH for USD/pxr.
# So we scrub every /hfs* or houdini element from PATH and LD_LIBRARY_PATH.
#
# This changes nothing on the machine — it only edits the current shell's env.
# (The global profile.d files are a separate, machine-wide hygiene issue: they
# silently break curl/git and C++ builds for every user, not just this one.)
_scrub() {
    local out= p
    local IFS=:
    for p in $1; do
        case "$p" in
            *hfs*|*[Hh]oudini*) ;;
            "") ;;
            *) out="${out:+$out:}$p" ;;
        esac
    done
    printf '%s' "$out"
}
export PATH="$(_scrub "$PATH")"
export LD_LIBRARY_PATH="$(_scrub "${LD_LIBRARY_PATH:-}")"
unset -f _scrub

# Belt-and-suspenders: point curl/git at the real system CA bundle. Harmless
# once Houdini's libcurl is off LD_LIBRARY_PATH (system libcurl already uses it),
# but keeps github fetches working even if the scrub is ever bypassed.
export CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
export GIT_SSL_CAINFO=/etc/pki/tls/certs/ca-bundle.crt
export SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
