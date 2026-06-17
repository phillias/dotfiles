#!/bin/bash

echo ""
echo "=== Change Summary ==="
echo ""

chezmoi diff --verbose 2>&1 | awk '
/^diff --git/ {
    if (file && (added > 0 || removed > 0)) {
        print file ": +" added " -" removed
    }
    file = $3
    added = 0
    removed = 0
}
/^\+/ { added++ }
/^-/ { removed++ }
END {
    if (file && (added > 0 || removed > 0)) {
        print file ": +" added " -" removed
    }
}
'

echo ""
