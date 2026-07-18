# Copyright 2023-2024 DreamWorks Animation LLC
# SPDX-License-Identifier: Apache-2.0

# setup environment variables to use release

sourcedir="$(realpath $( dirname -- "${BASH_SOURCE[0]:-$0}"))"
omr_root="$(realpath ${sourcedir}/..)"

# Walk up to find the top-level install dir where the dependencies are installed
install_root=${omr_root}
while [ "$(basename ${install_root})" != "installs" ]
do
    install_root=$(dirname ${install_root})
done

echo "Found install root at ${install_root}"
echo "Setting up release in ${omr_root}"

# NB required for Arras to function (it needs to find execComp)
export PATH=${omr_root}/bin:${PATH}

# need python modules for the USD interface and for the RATS tests
export PYTHONPATH=${install_root}/lib/python:/usr/local/lib/python:${install_root}/lib64/python3.9/site-packages/:${PYTHONPATH}


# tell moonray where to find dsos
export RDL2_DSO_PATH=${omr_root}/rdl2dso

# tell moonray where to find shaders file for XPU mode.
# it will look for ${REZ_MOONRAY_ROOT}/shaders/GPUShaders.ptx
export REZ_MOONRAY_ROOT=${omr_root}

# tell Arras where to find session files
export ARRAS_SESSION_PATH=${omr_root}/sessions

# tell Hydra Ndr plugins where to find shader descriptions
export MOONRAY_CLASS_PATH=${omr_root}/shader_json

# add Hydra plugins to path
export PXR_PLUGINPATH_NAME=${omr_root}/plugin/pxr:${PXR_PLUGINPATH_NAME}
export PXR_PLUGIN_PATH=${omr_root}/plugin/pxr:${PXR_PLUGIN_PATH} # for legacy DWA USD builds

# Qt platform and image-format plugins are in installs/plugins/ alongside the
# Qt frameworks in installs/lib/. Without these paths moonray_gui aborts
# immediately with "Could not find the Qt platform plugin cocoa".
export QT_QPA_PLATFORM_PLUGIN_PATH=${install_root}/plugins/platforms
export QT_PLUGIN_PATH=${install_root}/plugins

# create shader descriptions if they don't exist
if [ ! -d "${omr_root}/shader_json" ]
then
    echo "Building shader descriptions..."
    ${omr_root}/bin/rdl2_json_exporter --out ${omr_root}/shader_json/ --sparse
    echo "...done"
fi
