omr_install_dir=/Applications/MoonRay/installs/openmoonray-houdini
install_root=/Applications/MoonRay/installs
houdini_resources=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/Current/Resources/houdini

source "${omr_install_dir}/scripts/setup.sh"

# Remove standalone USD Python bindings from PYTHONPATH — they are built against
# Python 3.9 and will crash Houdini's Python 3.11 if left on the path.
# Houdini provides its own pxr Python bindings compiled against Python 3.11.
export PYTHONPATH=$(echo "${PYTHONPATH}" | tr ':' '\n' | grep -v "^${install_root}/lib/python$" | grep -v "^${install_root}/lib64/python3.9" | tr '\n' ':' | sed 's/:$//')

export REL="${omr_install_dir}"
export RDL2_DSO_PATH="${omr_install_dir}/rdl2dso.proxy:${omr_install_dir}/rdl2dso"
export MOONRAY_CLASS_PATH="${omr_install_dir}/shader_json"
export ARRAS_SESSION_PATH="${omr_install_dir}/sessions"

prepend_unique_path() {
    local add_path="$1"
    local current="${2:-}"
    case ":${current}:" in
        *":${add_path}:"*) echo "${current}" ;;
        *)
            if [ -n "${current}" ]; then
                echo "${add_path}:${current}"
            else
                echo "${add_path}"
            fi
            ;;
    esac
}

# Set both env vars Houdini uses for USD plugin search paths (Houdini version
# dependent — set both to be safe across upgrades).
export PXR_PLUGINPATH_NAME="$(prepend_unique_path "${omr_install_dir}/plugin/pxr" "${PXR_PLUGINPATH_NAME:-}")"
export PXR_PLUGIN_PATH="$(prepend_unique_path "${omr_install_dir}/plugin/pxr" "${PXR_PLUGIN_PATH:-}")"

# Layer MoonRay paths onto HOUDINI_PATH. If HOUDINI_PATH is already set
# (e.g. user sourced houdini_setup), we prepend without clobbering.
# Otherwise include the Houdini resources path directly so Houdini can
# find its own packages.
if [ -n "${HOUDINI_PATH:-}" ]; then
    export HOUDINI_PATH="$(prepend_unique_path "${omr_install_dir}/plugin/houdini" "${HOUDINI_PATH}")"
    export HOUDINI_PATH="$(prepend_unique_path "${omr_install_dir}/houdini" "${HOUDINI_PATH}")"
else
    export HOUDINI_PATH="${omr_install_dir}/houdini:${omr_install_dir}/plugin/houdini:${houdini_resources}"
fi
