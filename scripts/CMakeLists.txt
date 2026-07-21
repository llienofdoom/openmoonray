# Copyright 2023-2024 DreamWorks Animation LLC
# SPDX-License-Identifier: Apache-2.0

install(FILES setup.sh
    DESTINATION scripts)

# Cross-OS husk render helper — installed to bin/ as `render-usd` (executable).
install(PROGRAMS render-usd.sh
    DESTINATION bin
    RENAME render-usd)

install(FILES macOS/setupHoudini.sh
    DESTINATION scripts/macOS)

install(FILES Rocky9/setupHoudini.sh
    DESTINATION scripts/Rocky9)

