#!/bin/bash
#SBATCH --account yunglu
#SBATCH --partition=a10
#SBATCH --qos=standby
#SBATCH --ntasks=1 --cpus-per-task=16
#SBATCH --nodes=1 --gpus-per-node=1 
#SBATCH --mem=32G
#SBATCH --time=00:10:00
#SBATCH --job-name transkun_job
#SBATCH --output=/home/li5042/ondemand/data/sys/myjobs/projects/testing/transkun2/output/myjob.out
#SBATCH --error=/home/li5042/ondemand/data/sys/myjobs/projects/testing/transkun2/output/myjob.err

#===========================================
#run command: 
# sbatch "/home/li5042/ondemand/data/sys/myjobs/projects/testing/pythonJob/quickQueue.job.sh"

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

# ==========================================
# 1. VARIABLES & LOGGING SETUP
# ==========================================

WORKING_DIR="." 
OUTPUT_DIR="$WORKING_DIR/output"
MAESTRO_DIR="/depot/yunglu/data/transcription/maestro-v3.0.0"

VENV_DIR="$WORKING_DIR/venv"
ENV_FILE="environment.yml"

INSTALL_LOG="install.log" 
STATUS_LOG="$OUTPUT_DIR/job_status.log"
ERROR_LOG="$OUTPUT_DIR/error.log"  # <-- NEW

cd "$WORKING_DIR" || exit 1
mkdir -p "$OUTPUT_DIR" 

log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$STATUS_LOG"
}

echo "========================================" > "$STATUS_LOG"
# Initialize the error log so it exists even if empty
> "$ERROR_LOG"

log_msg "Starting Job $SLURM_JOB_ID"

# ==========================================
# 2. ENVIRONMENT SETUP
# ==========================================
# Notice the new --rebuild flag is included here! 
source setup_env.sh \
    --output-dir "$OUTPUT_DIR" \
    --venv-dir "$VENV_DIR" \
    --env-file "$ENV_FILE" \
    --install-log "$INSTALL_LOG" \
    --status-log "$STATUS_LOG" #\
#    --rebuild 

if [ $? -ne 0 ]; then
    log_msg "CRITICAL: Environment setup failed. Aborting job."
    # If setup fails, we still try to teardown gracefully
    source teardown_env.sh
    exit 1
fi

# ==========================================
# 3. DATASET VERIFICATION
# ==========================================
log_msg "Verifying dataset..."
if [ ! -d "$MAESTRO_DIR" ]; then
    log_msg "ERROR: Maestro dataset not found at $MAESTRO_DIR."
    source teardown_env.sh
    exit 1
fi

# ==========================================
# 4. EXECUTION
# ==========================================
log_msg "=== Executing Rapid Validation Script ==="

# WHAT: '>>' appends normal print statements to STATUS_LOG. '2>>' appends crashes to ERROR_LOG.
# WHY: Keeps your status log clean while securely trapping any Python tracebacks.
python test_pipeline.py >> "$STATUS_LOG" 2>> "$ERROR_LOG"

if [ $? -ne 0 ]; then
    log_msg "ERROR: Quick test pipeline failed. Check $ERROR_LOG for the Python traceback!"
    source teardown_env.sh
    exit 1
fi

log_msg "Job Completed Successfully."

# ==========================================
# 5. ENVIRONMENT TEARDOWN
# ==========================================
source teardown_env.sh