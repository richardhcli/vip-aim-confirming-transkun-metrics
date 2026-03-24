#!/bin/bash
# ==============================================================================
# Script Name: setup_env.sh
# Description: Universal, resilient environment setup for Conda and Pip.
#              Designed to be SOURCED into a parent script, not executed directly.
#
# Core Responsibilities:
#   1. Environment Sandboxing: Temporarily hijacks the $HOME variable during setup 
#      to force all hidden dot-folders (.conda, .cache) into a designated target 
#      directory, protecting user storage quotas on HPC clusters.
#   2. Dynamic Resolution: Automatically maps configuration files (environment.yml) 
#      and output logs relative to the specified working directory.
#   3. Fault Tolerance: Implements retry loops for network timeouts during package sync.
#   4. Diagnostic Validation: Probes the final environment to confirm hardware (GPU) 
#      and framework (PyTorch/TensorFlow) bindings.
#
# Usage: source setup_env.sh [OPTIONS]
#
# Options & Default Dependencies:
#   -w, --working-dir PATH   The root project path. (Default: Current Directory)
#                            -> Influences defaults for -v, -o, -e, and -r.
#   -h, --home-dir PATH      The target directory for .conda and .cache storage.
#                            (Default: The system's actual $HOME variable).
#                            *Tip: Set this to a SCRATCH drive on HPC clusters!
#   -v, --venv-dir PATH      Path to build the virtual env. (Default: WORKING_DIR/.venv)
#   -o, --output-dir PATH    Directory for logs. (Default: WORKING_DIR/output)
#   -e, --env-file PATH      Path to environment config. (Default: WORKING_DIR/environment.yml)
#   -r, --req-file PATH      Path to requirements. (Default: WORKING_DIR/requirements.txt)
#   -l, --install-log PATH   Name of the verbose log file. (Default: OUTPUT_DIR/install.log)
#   -b, --rebuild            Force removal and recreation of the Conda environment.
#   --help                   Display this help message and return.
# ==============================================================================

# ==========================================
# Phase 1: Argument Parsing & Initialization
# ==========================================

# Initialize defaults based on the immediate execution context
WORKING_DIR=$(pwd)
HOME_DIR="$HOME"
CACHE_DIR=""
VENV_DIR=""
OUTPUT_DIR=""
INSTALL_LOG="install.log"
ENVIRONMENT_FILE=""
REQ_FILE=""

REBUILD_ENV=false
UPDATE_ENV=true #default to true: if environment.yml exists, we update/sync the environment. If false, we skip syncing and just create the env if it doesn't exist. This allows for faster iterations when we're sure the env is already in good shape and just want to reuse it without checking for updates.


while [[ "$#" -gt 0 ]]; do
    case $1 in
        -w|--working-dir) WORKING_DIR="$2"; shift 2 ;;
        -h|--home-dir) HOME_DIR="$2"; shift 2 ;;
        -v|--venv-dir) VENV_DIR="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -e|--env-file) ENVIRONMENT_FILE="$2"; shift 2 ;;
        -r|--req-file) REQ_FILE="$2"; shift 2 ;;
        -l|--install-log) INSTALL_LOG="$2"; shift 2 ;;
        -b|--is-rebuild) REBUILD_ENV=$2; shift 2 ;;
        --is-update-env) UPDATE_ENV=$2; shift 2 ;;
        --help) grep '^#' "$0" | sed 's/^# \?//' | head -n 35; return 0 2>/dev/null || exit 0 ;;
        *) echo "Unknown parameter passed: $1"; return 1 2>/dev/null || exit 1 ;;
    esac
done

# Cascade defaults for unsupplied arguments based on the resolved WORKING_DIR
VENV_DIR="${VENV_DIR:-$WORKING_DIR/.venv}"
OUTPUT_DIR="${OUTPUT_DIR:-$WORKING_DIR/output}"
ENVIRONMENT_FILE="${ENVIRONMENT_FILE:-$WORKING_DIR/environment.yml}"
REQ_FILE="${REQ_FILE:-$WORKING_DIR/requirements.txt}"

mkdir -p "$OUTPUT_DIR"
if [[ "$INSTALL_LOG" != /* ]]; then INSTALL_LOG="${OUTPUT_DIR}/${INSTALL_LOG}"; fi
> "$INSTALL_LOG"

# Helper function to dual-route logs to console and the dedicated log file
log_info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$INSTALL_LOG"
}

log_info "Initializing environment setup for project: $WORKING_DIR"

# ==========================================
# Phase 2: Environment Sandboxing
# ==========================================
# Hijack the environment's conception of "home" to force poorly-behaved solvers 
# (like libmamba) and Python tools to cache their downloads in the parameterized HOME_DIR.

export ORIGINAL_HOME="$HOME"
export HOME="$HOME_DIR"

export XDG_CACHE_HOME="$HOME_DIR/.cache"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"

export CONDARC="$HOME_DIR/.condarc"
export CONDA_PKGS_DIRS="$HOME_DIR/.conda/pkgs"
export PIP_CACHE_DIR="$XDG_CACHE_HOME/pip"
export TORCH_HOME="$XDG_CACHE_HOME/torch"
export HF_HOME="$XDG_CACHE_HOME/huggingface"
export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"

mkdir -p "$CONDA_PKGS_DIRS" "$PIP_CACHE_DIR" "$TORCH_HOME" "$HF_HOME" "$MPLCONFIGDIR"
log_info "Sandboxed environment. Caches routed to: $HOME_DIR"

# ==========================================
# Phase 3: Conda Activation & Synchronization
# ==========================================

# Ensure Conda module is available if running on an HPC system
if command -v module &> /dev/null; then
    #module purge # Clear any pre-loaded modules to prevent conflicts
    #module purge does not work: unloads conda and conda fails...
    module load anaconda 2>/dev/null || true
fi

conda config --set solver libmamba >> "$INSTALL_LOG" 2>&1
eval "$(conda shell.bash hook)"


# Handle explicit rebuild requests to prevent corrupted metadata
if [ "$REBUILD_ENV" = true ] && [ -d "$VENV_DIR" ]; then
    log_info "Rebuild requested. Removing existing environment at $VENV_DIR..."
    conda env remove -y --prefix "$VENV_DIR" >> "$INSTALL_LOG" 2>&1
    rm -rf "$VENV_DIR"
fi

if ([ "$REBUILD_ENV" = true ] || [ -f "$ENVIRONMENT_FILE" ]) && ([ "$UPDATE_ENV" = true ]); then
    
    MAX_ATTEMPTS=3
    ENV_SUCCESS=false

    if [ -f "$ENVIRONMENT_FILE" ]; then
        for ((i=1; i<=MAX_ATTEMPTS; i++)); do
            log_info "Syncing Conda environment (Attempt $i/$MAX_ATTEMPTS)..."
            if conda env update --prefix "$VENV_DIR" --file "$ENVIRONMENT_FILE" --prune --quiet >> "$INSTALL_LOG" 2>&1; then
                ENV_SUCCESS=true
                break
            elif [[ $i -lt $MAX_ATTEMPTS ]]; then
                log_info "Warning: Environment sync failed (likely network timeout). Retrying in 5 seconds..."
                sleep 5
            fi
        done
    else
        log_info "Notice: No environment.yml found. Creating base Python 3.10."
        conda create --yes --prefix "$VENV_DIR" python=3.10 --quiet >> "$INSTALL_LOG" 2>&1
        ENV_SUCCESS=true
    fi

    if [ "$ENV_SUCCESS" = false ]; then
        log_info "CRITICAL: Failed to build Conda environment. Check $INSTALL_LOG"
        export HOME="$ORIGINAL_HOME"
        return 1 2>/dev/null || exit 1
    fi
fi

if [ "$UPDATE_ENV" == false ]; then 
    log_info "Update flag set to false. Skipping environment.yml sync. "
fi

# ==========================================
# Phase 4: Pip Dependency Synchronization
# ==========================================
# Pip dependencies are installed second to respect the "Conda-First" dependency resolution rule.

if [ -f "$REQ_FILE" ]; then
    log_info "Installing Pip dependencies from requirements.txt..."
    conda activate "$VENV_DIR"
    if ! pip install -r "$REQ_FILE" --progress-bar off >> "$INSTALL_LOG" 2>&1; then
        log_info "CRITICAL: Pip installation failed. Check $INSTALL_LOG"
        conda deactivate
        export HOME="$ORIGINAL_HOME"
        return 1 2>/dev/null || exit 1
    fi
    conda deactivate
fi

# ==========================================
# Phase 5: Diagnostic Framework Validation
# ==========================================
# This step is read-only. It does not install anything. It probes the resulting 
# environment to provide a clear log of what hardware bindings are active.

log_info "Validating environment framework bindings..."
conda activate "$VENV_DIR"

PYTHON_CMD="$VENV_DIR/bin/python"
PY_VER=$($PYTHON_CMD -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo "unknown")

if command -v nvidia-smi &>/dev/null && nvidia-smi -L | grep -q "GPU"; then
    log_info "Hardware Validation: GPU detected on system via nvidia-smi."
else
    log_info "Hardware Validation: No GPU detected. ML frameworks will default to CPU."
fi

if $PYTHON_CMD -c "import torch" 2>/dev/null; then
    PT_VER=$($PYTHON_CMD -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")
    CUDA_AVAIL=$($PYTHON_CMD -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "False")
    log_info "Framework Validation: Python $PY_VER | PyTorch $PT_VER | CUDA Available: $CUDA_AVAIL"
elif $PYTHON_CMD -c "import tensorflow as tf" 2>/dev/null; then
    TF_VER=$($PYTHON_CMD -c "import tensorflow as tf; print(tf.__version__)" 2>/dev/null || echo "unknown")
    log_info "Framework Validation: Python $PY_VER | TensorFlow $TF_VER"
else
    log_info "Framework Validation: Python $PY_VER | No deep learning frameworks installed."
fi

# ==========================================
# Phase 6: Cleanup
# ==========================================
# Restore the original home directory to ensure the parent shell remains unaltered.
export HOME="$ORIGINAL_HOME"

log_info "Environment setup completed successfully!"
return 0 2>/dev/null || exit 0