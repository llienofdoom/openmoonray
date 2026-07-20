omr_install_dir=/opt/MoonRay/installs/openmoonray-houdini
houdini_install_dir=/opt/hfs20.5.939

# save/restore PYTHONPATH: setup.sh prepends the standalone Python module paths,
# which crash Houdini's bundled Python 3.11. Restore the pre-setup value so none
# of them leak into husk/Houdini (the delegate is C++; it needs no moonray py).
OLDPP=${PYTHONPATH:-}
source ${omr_install_dir}/scripts/setup.sh
export PYTHONPATH=${OLDPP}

export REL=${omr_install_dir}
export RDL2_DSO_PATH=${omr_install_dir}/rdl2dso.proxy:${omr_install_dir}/rdl2dso
export MOONRAY_CLASS_PATH=${omr_install_dir}/shader_json
export ARRAS_SESSION_PATH=${omr_install_dir}/sessions
# Set BOTH plugin-path env vars Houdini uses (the name varies across versions),
# and EXPORT them — the previous version left PXR_PLUGINPATH_NAME unexported.
export PXR_PLUGINPATH_NAME=${omr_install_dir}/plugin/pxr
export PXR_PLUGIN_PATH=${omr_install_dir}/plugin/pxr
export HOUDINI_PATH=${houdini_install_dir}/houdini:${omr_install_dir}/houdini/:${omr_install_dir}/plugin/houdini
