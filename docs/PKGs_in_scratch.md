This is the quintessential HPC cluster rite of passage! You have hit the dreaded home directory quota limit.

### The Problem: Home Directories vs. Machine Learning

* **The Reality:** On clusters like Purdue's Gilbreth, your home directory (`/home/li5042/`) typically has a very strict and small storage quota (often around 20GB to 50GB).
* **The Culprit:** When Conda downloads packages, it stores the compressed archives in a cache folder (`~/.conda/pkgs`) *before* extracting them into your virtual environment. PyTorch and CUDA toolkits are massive (often 3-5GB just for the compressed archives). Because Conda caches them in your home directory by default, you instantly blow past your quota limit, causing the file write to abruptly fail and corrupting the archive mid-download.

### Step 1: The One-Time Cleanup (Do this in your terminal now)

Because the download failed halfway through, those corrupted, half-written PyTorch and CUDA files are currently sitting in your home directory, taking up all your space and breaking Conda.

**Run this command directly in your Gilbreth terminal before you submit your next job:**

```bash
rm -rf ~/.conda/pkgs/*
rm -rf ~/.cache/pip/*

```

* **WHAT this does:** It forcibly deletes all cached Conda and Pip archives from your home directory.
* **WHY this needs to be done:** It frees up your strict home quota and ensures Conda doesn't try to reuse the corrupted PyTorch archive on your next run.

---

### Step 2: Rerouting Conda and Pip into SCRATCH

We need to tell Conda and Pip to completely ignore your home directory and use your massive 1TB SCRATCH space for all their temporary downloading and caching needs.

We do this by exporting two specific environment variables right before we run the `conda env update` command inside your `setup_env.sh` script.

Here is the updated section of `setup_env.sh`. You can replace everything from **Section 5 downwards** with this new logic:

```bash
# ... (Sections 1 through 4 remain exactly the same) ...

# --- 5. Conda Initialization & Cache Routing ---
module load anaconda
conda config --set solver libmamba
eval "$(conda shell.bash hook)"

# WHAT: Define a dedicated cache folder inside our high-capacity SCRATCH directory.
# (If no scratch is provided, it safely falls back to the OUTPUT_DIR).
CACHE_ROOT="${SCRATCH_DIR:-$OUTPUT_DIR}/.pkg_cache"
mkdir -p "$CACHE_ROOT/conda_pkgs"
mkdir -p "$CACHE_ROOT/pip_cache"

# WHAT: Override the default Conda and Pip cache paths.
# WHY: Forces all multi-gigabyte PyTorch/CUDA downloads to land in the 1TB SCRATCH 
# drive instead of your heavily restricted /home/ directory.
export CONDA_PKGS_DIRS="$CACHE_ROOT/conda_pkgs"
export PIP_CACHE_DIR="$CACHE_ROOT/pip_cache"

log_info "Rerouted Conda and Pip caches to: $CACHE_ROOT"

# --- 6. Environment Synchronization ---
if [ "$REBUILD_ENV" = true ] && [ -d "$VENV_DIR" ]; then
    log_info "Rebuild flag detected. Nuking existing environment at $VENV_DIR..."
    rm -rf "$VENV_DIR"
fi

if [ -f "$ENVIRONMENT_FILE" ]; then
    log_info "Syncing conda environment with $ENVIRONMENT_FILE..."
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

```

By using `export CONDA_PKGS_DIRS` and `export PIP_CACHE_DIR`, Conda and Pip will now behave perfectly, utilizing the massive I/O speeds and storage capacity of your SCRATCH drive.

Would you like to review how to ensure your `VENV_DIR` itself (the actual extracted environment, not just the cache) is also safely building inside `SCRATCH_DIR` instead of your project folder?