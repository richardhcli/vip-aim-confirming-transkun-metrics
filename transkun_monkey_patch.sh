#!/bin/bash
# ==============================================================================
# Script Name: patch_transkun.sh
# Description: Surgically patches syntax and logic errors in the installed 
#              Transkun package inside the active virtual environment.
#              This script is idempotent (safe to run multiple times).
# ==============================================================================

# Locate the broken file within the local virtual environment
BROKEN_FILE=$(find .venv -name "computeMetrics.py" | head -n 1)

if [ -z "$BROKEN_FILE" ]; then
    echo "ERROR: computeMetrics.py not found. Is the environment built?"
    exit 1
fi

echo "Patching Transkun package at: $BROKEN_FILE"

# 1. Fix Typo: extendPedalEs -> extendPedalEst
# By including the comma in the search pattern, we ensure it only replaces the exact broken string.
sed -i 's/extendPedalEs,/extendPedalEst,/g' "$BROKEN_FILE"

# 2. Fix Typo: onsetTolerancet -> onsetTolerance
sed -i 's/onsetTolerancet)/onsetTolerance)/g' "$BROKEN_FILE"

# 3. Fix Logic Error: KeyError: 'deviations'
# Replaces direct dictionary access with a safe .get() fallback that returns an empty list if missing.
sed -i 's/metrics\["deviations"\]/metrics.get("deviations", [])/g' "$BROKEN_FILE"

echo "Patching complete. Environment is safe for transkunEval."