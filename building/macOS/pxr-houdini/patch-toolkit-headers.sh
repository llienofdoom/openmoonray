#!/bin/bash
# patch-toolkit-headers.sh — Apply one-time patches to Houdini's USD 24.3 toolkit headers.
#
# PROBLEM
# =======
# USD 24.3 (bundled in Houdini 20.5) removed SdfChildren::Move and therefore
# removed SdfChildrenProxy::_Set. However, SdfChildrenProxy::_ValueProxy::operator=
# still calls _owner->_Set(). In USD 22.11, SdfChildrenProxy inherited from
# boost::equality_comparable (a dependent base), which deferred this name lookup to
# phase 2 (instantiation). USD 24.3 dropped boost so there is no dependent base
# class; clang performs a phase-1 eager lookup, finds no _Set, and errors immediately
# even though _ValueProxy::operator= is never actually called by hdMoonray.
#
# FIX
# ===
# Add a private _Set stub to SdfChildrenProxy in the toolkit childrenProxy.h.
# The stub satisfies the phase-1 lookup and emits a TF_CODING_ERROR at runtime
# if ever called (which should not happen in normal hdMoonray usage).
#
# USAGE
# =====
#   ./patch-toolkit-headers.sh [HOUDINI_INSTALL_DIR]
#
# HOUDINI_INSTALL_DIR defaults to /Applications/Houdini/Houdini20.5.939.

set -euo pipefail

HOUDINI_DIR="${1:-/Applications/Houdini/Houdini20.5.939}"
CHILDREN_PROXY="$HOUDINI_DIR/Frameworks/Houdini.framework/Versions/20.5/Resources/toolkit/include/pxr/usd/sdf/childrenProxy.h"

if [[ ! -f "$CHILDREN_PROXY" ]]; then
    echo "ERROR: childrenProxy.h not found: $CHILDREN_PROXY"
    echo "Check that HOUDINI_INSTALL_DIR is correct: $HOUDINI_DIR"
    exit 1
fi

# Idempotency check
if grep -q "_Set is not supported in USD 24.x" "$CHILDREN_PROXY"; then
    echo "childrenProxy.h already patched — nothing to do."
    exit 0
fi

# Verify expected anchor text is present
if ! grep -q "_Validate(CanErase) ? _PrimErase(key) : false;" "$CHILDREN_PROXY"; then
    echo "ERROR: Expected anchor text not found in $CHILDREN_PROXY"
    echo "The file may have changed. Review the patch manually."
    exit 1
fi

# Apply patch — insert _Set stub after _Erase
python3 - "$CHILDREN_PROXY" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

OLD = """\
    bool _Erase(const key_type& key)
    {
        return _Validate(CanErase) ? _PrimErase(key) : false;
    }

    bool _PrimCopy(const mapped_vector_type& values)"""

NEW = """\
    bool _Erase(const key_type& key)
    {
        return _Validate(CanErase) ? _PrimErase(key) : false;
    }

    // USD 24.x removed _Set (which called SdfChildren::Move, also removed).
    // _ValueProxy::operator= still references _Set, causing clang phase-1
    // errors when there is no dependent base class to defer the lookup.
    // This stub restores the symbol; calling it at runtime is unsupported.
    template <class U>
    bool _Set(const mapped_type&, const U&)
    {
        TF_CODING_ERROR("SdfChildrenProxy: _Set is not supported in USD 24.x; "
                        "use insert/erase instead");
        return false;
    }

    bool _PrimCopy(const mapped_vector_type& values)"""

if OLD not in content:
    print("ERROR: anchor text not found in file")
    sys.exit(1)

with open(path, 'w') as f:
    f.write(content.replace(OLD, NEW, 1))

print(f"Patched: {path}")
PYEOF

echo "Done. Verify with: grep -n '_Set' \"$CHILDREN_PROXY\""
