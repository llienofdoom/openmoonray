# Copyright 2023-2024 DreamWorks Animation LLC
# SPDX-License-Identifier: Apache-2.0

install(FILES setup.sh
    DESTINATION scripts)

# Cross-OS husk render + denoise helpers — installed to bin/ (executable).
install(PROGRAMS render-usd.sh
    DESTINATION bin
    RENAME render-usd)

install(PROGRAMS render-denoise.sh
    DESTINATION bin
    RENAME render-denoise)

install(FILES macOS/setupHoudini.sh
    DESTINATION scripts/macOS)

install(FILES Rocky9/setupHoudini.sh
    DESTINATION scripts/Rocky9)

