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
#!/bin/bash
# ==============================================================================
# Script Name: setup_env.sh
# Description: Resilient environment setup with shared caching and hardware validation.
# ==============================================================================

# --- 1. Define Defaults ---
SCRATCH_DIR=$SCRATCH
MIGRATE_DIR=""
ENVIRONMENT_FILE="environment.yml"
VENV_DIR="./.venv"
SRC_DIR=$(pwd)
OUTPUT_DIR="./output"
INSTALL_LOG="install.log"
REQ_FILE="requirements.txt"
STATUS_LOG=""
REBUILD_ENV=false

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
        -m|--migrate-dir) MIGRATE_DIR="$2"; shift 2 ;;
        -e|--env-file) ENVIRONMENT_FILE="$2"; shift 2 ;;
        -v|--venv-dir) VENV_DIR="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -l|--install-log) INSTALL_LOG="$2"; shift 2 ;;
        -t|--status-log) STATUS_LOG="$2"; shift 2 ;;
        -r|--req-file) REQ_FILE="$2"; shift 2 ;;
        -b|--rebuild) REBUILD_ENV=true; shift 1 ;;
        -h|--help) echo "Usage: source setup_env.sh [OPTIONS]"; return 0 ;;
        *) echo "Unknown parameter passed: $1"; return 1 ;;
    esac
done

EXEC_DIR="$SRC_DIR"

# --- 3. Resolve Paths & Optional Migration ---
mkdir -p "$OUTPUT_DIR"
if [[ "$INSTALL_LOG" != /* ]]; then INSTALL_LOG="${OUTPUT_DIR}/${INSTALL_LOG}"; fi
> "$INSTALL_LOG" 

if [ -n "$MIGRATE_DIR" ]; then
    log_info "Migrating workspace to $MIGRATE_DIR..."
    mkdir -p "$MIGRATE_DIR"
    rsync -a --exclude='.venv' --exclude='.git' "$SRC_DIR/" "$MIGRATE_DIR/"
    EXEC_DIR="$MIGRATE_DIR"
    cd "$EXEC_DIR" || { log_info "CRITICAL: Failed to enter $EXEC_DIR"; return 1 2>/dev/null || exit 1; }
fi

log_info "Initializing setup in $EXEC_DIR..."

# --- 4. Global Shared Cache Initialization & Routing ---

# WHAT: Extract the user's root scratch directory from the provided SCRATCH_DIR.
USER_SCRATCH_ROOT=$(echo "$SCRATCH_DIR" | cut -d'/' -f1-4) 

# WHAT: Load the Anaconda module BEFORE setting our variables.
# WHY: HPC modules often execute internal setup scripts that reset paths. 
# Loading it first prevents Gilbreth from undoing our scratch rerouting.
module load anaconda

# WHAT: The "Nuclear Option" for Linux directory routing (XDG standard).
# WHY: Forces libmamba, Python, and other hidden tools to build their 
# system .cache, .config, and .local folders in the scratch drive.
export XDG_CACHE_HOME="$USER_SCRATCH_ROOT/.cache"
export XDG_CONFIG_HOME="$USER_SCRATCH_ROOT/.config"
export XDG_DATA_HOME="$USER_SCRATCH_ROOT/.local/share"

# Reroute tool-specific caches directly into our new XDG cache home
export CONDARC="$USER_SCRATCH_ROOT/.condarc"
export CONDA_PKGS_DIRS="$USER_SCRATCH_ROOT/.conda/pkgs"
export PIP_CACHE_DIR="$XDG_CACHE_HOME/pip"
export TORCH_HOME="$XDG_CACHE_HOME/torch"
export HF_HOME="$XDG_CACHE_HOME/huggingface"

# Create the standard folder hierarchies if they do not exist yet
mkdir -p "$CONDA_PKGS_DIRS"
mkdir -p "$PIP_CACHE_DIR"
mkdir -p "$TORCH_HOME"
mkdir -p "$HF_HOME"

log_info "Mounted overarching XDG and Conda directories at: $USER_SCRATCH_ROOT"

# --- 5. Conda Initialization ---
module load anaconda
conda config --set solver libmamba
eval "$(conda shell.bash hook)"

# --- 6. Environment Synchronization (With Retry Logic) ---
if [ "$REBUILD_ENV" = true ] && [ -d "$VENV_DIR" ]; then
    log_info "Rebuild requested. Removing existing environment..."
    conda env remove -y --prefix "$VENV_DIR" >/dev/null 2>&1
    rm -rf "$VENV_DIR"
fi

MAX_ATTEMPTS=3
ENV_SUCCESS=false

if [ -f "$ENVIRONMENT_FILE" ]; then
    for ((i=1; i<=MAX_ATTEMPTS; i++)); do
        log_info "Syncing conda environment (Attempt $i/$MAX_ATTEMPTS)..."
        
        if conda env update --prefix "$VENV_DIR" --file "$ENVIRONMENT_FILE" --prune --quiet >> "$INSTALL_LOG" 2>&1; then
            ENV_SUCCESS=true
            break
        elif [[ $i -lt $MAX_ATTEMPTS ]]; then
            log_info "WARN: Env sync failed. Retrying in 5 seconds..."
            sleep 5
        fi
    done
else
    log_info "Notice: $ENVIRONMENT_FILE not found. Creating base Python 3.10."
    conda create --yes --prefix "$VENV_DIR" python=3.10 --quiet >> "$INSTALL_LOG" 2>&1
    ENV_SUCCESS=true
fi

if [ "$ENV_SUCCESS" = false ]; then
    log_info "ERROR: Failed to build Conda environment after $MAX_ATTEMPTS attempts."
    return 1 2>/dev/null || exit 1
fi

# --- 7. Pip Requirements Setup ---
if [ -f "$REQ_FILE" ]; then
    log_info "Installing pip dependencies..."
    conda activate "$VENV_DIR"
    pip install -r "$REQ_FILE" --progress-bar off >> "$INSTALL_LOG" 2>&1
    if [ $? -ne 0 ]; then
        log_info "ERROR: Pip install failed."
        conda deactivate
        return 1 2>/dev/null || exit 1
    fi
    conda deactivate
fi

# --- 8. Hardware & Framework Validation ---
log_info "Validating environment configuration..."
conda activate "$VENV_DIR"

PYTHON_CMD="$VENV_DIR/bin/python"
PY_VER=$($PYTHON_CMD -c 'import sys; print(sys.version.split()[0])')

if command -v nvidia-smi &>/dev/null && nvidia-smi -L | grep -q "GPU"; then
    log_info "Hardware: GPU detected via nvidia-smi."
else
    log_info "WARN: No GPU detected. PyTorch will fallback to CPU."
fi

if $PYTHON_CMD -c "import torch" 2>/dev/null; then
    PT_VER=$($PYTHON_CMD -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")
    CUDA_AVAIL=$($PYTHON_CMD -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "unknown")
    log_info "Framework: Python $PY_VER | PyTorch $PT_VER | CUDA Available: $CUDA_AVAIL"
else
    log_info "Framework: Python $PY_VER | PyTorch not detected."
fi

log_info "Environment setup completed successfully!"
return 0