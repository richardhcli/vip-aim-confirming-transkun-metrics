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

#README:
#this is the entrance point for the job. 
#for modularity and maintainability, we will call other scripts from this main job script.

#===========================================
#===========================================

#!/bin/bash
# ==========================================
# 1. VARIABLES & LOGGING SETUP
# ==========================================

WORKING_DIR="." 
OUTPUT_DIR="$WORKING_DIR/output"

# Original Depot Data
MAESTRO_DIR="/depot/yunglu/data/transcription/maestro-v3.0.0"

# Scratch and Dataset Paths
SCRATCH_DIR="/scratch/gilbreth/$USER/$SLURM_JOB_ID"
MAESTRO_DATASET_PREPROCESSED="$SCRATCH_DIR/datasets/maestro_dataset"

# Leave empty for in-place execution, or define a path to migrate code execution
MIGRATE_DIR=""

VENV_DIR="$WORKING_DIR/venv"
ENV_FILE="environment.yml"
INSTALL_LOG="install.log" 
STATUS_LOG="$OUTPUT_DIR/job_status.log"
ERROR_LOG="$OUTPUT_DIR/error.log"

cd "$WORKING_DIR" || { echo "Failed to enter working directory."; return 1 2>/dev/null || exit 1; }
mkdir -p "$OUTPUT_DIR" 

log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$STATUS_LOG"
}

echo "========================================" > "$STATUS_LOG"
> "$ERROR_LOG"

log_msg "Starting Job $SLURM_JOB_ID"

# ==========================================
# 2. ENVIRONMENT SETUP
# ==========================================
source setup_env.sh \
    --scratch-dir "$SCRATCH_DIR" \
    --migrate-dir "$MIGRATE_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --venv-dir "$VENV_DIR" \
    --env-file "$ENV_FILE" \
    --install-log "$INSTALL_LOG" \
    --status-log "$STATUS_LOG"

if [ $? -ne 0 ]; then
    log_msg "CRITICAL: Environment setup failed. Aborting job."
    source teardown_env.sh
    # Safely halt: keeps terminal open if sourced, exits if run via sbatch
    return 1 2>/dev/null || exit 1
fi

# ==========================================
# 3. EXECUTION PIPELINE
# ==========================================
log_msg "Initiating testing pipeline..."

source testing_maestro.sh

if [ $? -ne 0 ]; then
    log_msg "ERROR: Pipeline halted due to previous errors. Check $ERROR_LOG."
    source teardown_env.sh
    # Safely halt: keeps terminal open if sourced, exits if run via sbatch
    return 1 2>/dev/null || exit 1
fi

# ==========================================
# 4. ENVIRONMENT TEARDOWN
# ==========================================
source teardown_env.sh