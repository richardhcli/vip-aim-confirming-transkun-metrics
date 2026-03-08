#!/bin/bash
# ==============================================================================
# Script Name: setup_env.sh
# Description: A universal environment setup script for python using Conda and Pip.
#              It handles optional migration to a high-capacity SCRATCH directory,
#              in-place environment updates, and pip dependency fallback.
#              Leaves the environment activated for the parent process.
# Usage: source setup_env.sh [OPTIONS]
# Options:
#   -s, --scratch-dir PATH   Migrate execution to this SCRATCH path before setup.
#   -e, --env-file PATH      Path to the Conda environment.yml (Default: environment.yml)
#   -v, --venv-dir PATH      Path to build the virtual environment (Default: ./.venv)
#   -l, --install-log PATH   Path to write installation logs (Default: install.log)
#   -r, --req-file PATH      Path to the pip requirements.txt (Default: requirements.txt)
#   -h, --help               Display this help message and exit.
# Author: Li5042
# 
#
# WHAT IT DOES:
# 1. Argument Parsing: Reads user-defined paths or falls back to sensible defaults.
# 2. Scratch Migration (Optional): If a scratch directory is provided, it uses 
#    'rsync' to mirror the working directory to the scratch space, deliberately 
#    ignoring bulky hidden directories like .git or existing .venv folders.
# 3. Conda Setup: Evaluates the conda bash hook to allow subshell activation.
#    It then checks for an environment.yml. If found, it updates the local 
#    environment (--prune removes deleted packages). If not, it creates a base 
#    Python 3.10 environment.
# 4. Pip Setup: If a requirements.txt is found, it activates the new Conda 
#    environment and installs the remaining dependencies via pip.
#
# WHY THIS APPROACH:
# - Using 'rsync' instead of 'cp' prevents massive I/O bottlenecks on compute nodes.
# - Explicitly evaluating the conda bash hook prevents "conda activate" errors 
#   when this script is executed as a child process of a main SLURM job script.
#
# TIPS: 
# Live progress (stream the clean text to your terminal in real-time) command:
# run in a second terminal while your job is running:
#   tail -f output/install.log
# ==============================================================================

# --- 1. Define Defaults ---
SCRATCH_DIR=""
ENVIRONMENT_FILE="environment.yml"
VENV_DIR="./.venv"
SRC_DIR=$(pwd)
OUTPUT_DIR="./output"
INSTALL_LOG="install.log"
REQ_FILE="requirements.txt"
STATUS_LOG=""
REBUILD_ENV=false # Default to updating, not rebuilding

# Internal logging function
log_info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    if [ -n "$STATUS_LOG" ]; then
        echo "$msg" | tee -a "$STATUS_LOG"
    else
        echo "$msg"
    fi
}

# --- 2. Parse Arguments ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--scratch-dir) SCRATCH_DIR="$2"; shift 2 ;;
        -e|--env-file) ENVIRONMENT_FILE="$2"; shift 2 ;;
        -v|--venv-dir) VENV_DIR="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -l|--install-log) INSTALL_LOG="$2"; shift 2 ;;
        -t|--status-log) STATUS_LOG="$2"; shift 2 ;;
        -r|--req-file) REQ_FILE="$2"; shift 2 ;;
        -b|--rebuild) REBUILD_ENV=true; shift 1 ;; # <-- NEW FLAG
        -h|--help) 
            echo "Usage: source setup_env.sh [OPTIONS]"
            return 0 
            ;;
        *) 
            echo "Unknown parameter passed: $1"
            return 1 
            ;;
    esac
done

EXEC_DIR="$SRC_DIR"

# --- 3. Resolve Paths & Directories ---
mkdir -p "$OUTPUT_DIR"

# If INSTALL_LOG is relative, prepend OUTPUT_DIR
if [[ "$INSTALL_LOG" != /* ]]; then
    INSTALL_LOG="${OUTPUT_DIR}/${INSTALL_LOG}"
fi
> "$INSTALL_LOG" 

# --- 4. Optional: Migrate to SCRATCH ---
if [ -n "$SCRATCH_DIR" ]; then
    log_info "Migrating workspace to $SCRATCH_DIR..."
    mkdir -p "$SCRATCH_DIR"
    rsync -a --exclude='.venv' --exclude='.git' "$SRC_DIR/" "$SCRATCH_DIR/"
    EXEC_DIR="$SCRATCH_DIR"
    cd "$EXEC_DIR" || { log_info "CRITICAL: Failed to enter $EXEC_DIR"; return 1; }
fi

log_info "Initializing setup in $EXEC_DIR..."

# --- 5. Conda Initialization ---
module load anaconda
conda config --set solver libmamba
eval "$(conda shell.bash hook)"

# --- 6. Environment Synchronization ---

# WHAT: Deletes the existing virtual environment folder if the user requested it.
# WHY: Guarantees a completely clean slate, resolving corrupted module installations.
if [ "$REBUILD_ENV" = true ] && [ -d "$VENV_DIR" ]; then
    log_info "Rebuild flag detected. Nuking existing environment at $VENV_DIR..."
    rm -rf "$VENV_DIR"
fi

if [ -f "$ENVIRONMENT_FILE" ]; then
    log_info "Syncing conda environment with $ENVIRONMENT_FILE..."
    # --quiet prevents the spinning progress bar from breaking the text file
    conda env update --prefix "$VENV_DIR" --file "$ENVIRONMENT_FILE" --prune --quiet >> "$INSTALL_LOG" 2>&1
    
    if [ $? -ne 0 ]; then
        log_info "ERROR: Conda environment sync failed. Check $INSTALL_LOG"
        return 1
    fi
else
    log_info "Notice: $ENVIRONMENT_FILE not found. Creating base Python 3.10."
    conda create --yes --prefix "$VENV_DIR" python=3.10 --quiet >> "$INSTALL_LOG" 2>&1
fi

# --- 7. Pip Requirements Setup ---
if [ -f "$REQ_FILE" ]; then
    log_info "Installing pip dependencies from $REQ_FILE..."
    conda activate "$VENV_DIR"
    # --progress-bar off prevents pip's loading bar from spamming logs
    pip install -r "$REQ_FILE" --progress-bar off >> "$INSTALL_LOG" 2>&1
    
    if [ $? -ne 0 ]; then
        log_info "ERROR: Pip install failed. Check $INSTALL_LOG"
        conda deactivate
        return 1
    fi
    conda deactivate
fi

# --- 8. Final Activation ---
log_info "Activating finalized environment: $VENV_DIR"
conda activate "$VENV_DIR"

log_info "Environment setup completed successfully!"
return 0