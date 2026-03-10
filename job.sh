#!/bin/bash
#SBATCH --account yunglu
#SBATCH --partition=a10
#SBATCH --qos=standby
#SBATCH --ntasks=1 --cpus-per-task=16
#SBATCH --nodes=1 --gpus-per-node=1 
#SBATCH --mem=32G
#SBATCH --time=00:20:00
#SBATCH --job-name transkun_job
#SBATCH --output=/scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output/myjob.out
#SBATCH --error=/scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output/myjob.err

#===========================================
#run command: 
# sbatch "/scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/job.sh"

#===========================================

#info: 
# at least 16G for conda env setup and package installation

# Examples:
# # #!/bin/bash
# # SBATCH -A yunglu
# # SBATCH -p a100-80gb
# # SBATCH --qos=standby
# # SBATCH --nodes=1
# # SBATCH --ntasks-per-node=1
# # SBATCH --gres=gpu:1
# # SBATCH --cpus-per-task=32
# # SBATCH --mem=160G
# # SBATCH --time=00:10:00


#===========================================
# ==========================================

#README:
#this is the entrance point for the job. 
#for modularity and maintainability, we will call other scripts from this main job script.

#===========================================
#===========================================
# ==========================================
# 1. VARIABLES & LOGGING SETUP
# ==========================================
WORKING_DIR=$(pwd)
OUTPUT_DIR="$WORKING_DIR/output"

# Dataset Paths (Required by testing_maestro.sh)
MAESTRO_DIR="/depot/yunglu/data/transcription/maestro-v3.0.0"
HOME_DIR_ENV="/scratch/gilbreth/$USER" #/${SLURM_JOB_ID:-interactive_test}
MAESTRO_DATASET_PREPROCESSED="$HOME_DIR_ENV/datasets/maestro_dataset"

# Logging Paths
STATUS_LOG="$OUTPUT_DIR/job_status.log"
ERROR_LOG="$OUTPUT_DIR/error.log"

mkdir -p "$OUTPUT_DIR" 

log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$STATUS_LOG"
}

echo "========================================" > "$STATUS_LOG"
> "$ERROR_LOG"
log_msg "Starting Job $SLURM_JOB_ID"

# ==========================================
# 2. RUN-TIME CACHE ROUTING (ML WEIGHTS)
# ==========================================
# WHAT: Explicitly routes machine learning caches to the SCRATCH drive.
# WHY: setup_env.sh safely restores the original $HOME variable when it finishes. 
# We must explicitly export these variables so PyTorch and HuggingFace download 
# their massive model weights into SCRATCH during inference.
export XDG_CACHE_HOME="$HOME_DIR_ENV/.cache"
export XDG_CONFIG_HOME="$HOME_DIR_ENV/.config"
export TORCH_HOME="$XDG_CACHE_HOME/torch"
export HF_HOME="$XDG_CACHE_HOME/huggingface"
export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"

# ==========================================
# 3. ENVIRONMENT SETUP
# ==========================================
# WHAT: Calls our universal setup script with minimal overrides.
# WHY: Relying on the script's internal defaults (for venv, logs, reqs) 
# keeps this file pristine. We only need to pass the custom scratch directory 
# to be used as the caching home-dir.
source setup_env.sh --home-dir "$HOME_DIR_ENV"

if [ $? -ne 0 ]; then
    log_msg "CRITICAL: Environment setup failed. Aborting job."
    source teardown_env.sh 2>/dev/null
    return 1 2>/dev/null || exit 1
fi

# ==========================================
# 4. EXECUTION PIPELINE
# ==========================================
log_msg "Initiating testing pipeline..."

source testing_maestro.sh

if [ $? -ne 0 ]; then
    log_msg "ERROR: Pipeline halted due to previous errors. Check $ERROR_LOG."
    source teardown_env.sh 2>/dev/null
    return 1 2>/dev/null || exit 1
fi

# ==========================================
# 5. ENVIRONMENT TEARDOWN
# ==========================================
source teardown_env.sh 2>/dev/null
log_msg "Job completed successfully."