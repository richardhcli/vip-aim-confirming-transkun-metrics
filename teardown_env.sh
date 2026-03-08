#!/bin/bash
# ==============================================================================
# Script Name: teardown_env.sh
# Description: Safely deactivates the Conda environment and performs cleanup.
# Usage:       source teardown_env.sh
# ==============================================================================

# Internal logging function
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_info "Initiating environment teardown..."

# WHAT: Instructs Conda to step out of the currently active virtual environment.
# WHY: Prevents dependency bleed-over into subsequent tasks or your local terminal session.
conda deactivate

# Additional cleanup steps (like moving scratch data back) can go here later.

log_info "Environment deactivated successfully."
return 0