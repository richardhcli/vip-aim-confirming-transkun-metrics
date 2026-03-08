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

#!/bin/bash
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

cd "$WORKING_DIR" || exit 1
mkdir -p "$OUTPUT_DIR" 

# Create logging function (Writes to terminal AND appends to file)
log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$STATUS_LOG"
}

# Initialize fresh status log for this run
echo "========================================" > "$STATUS_LOG"
log_msg "Starting Job $SLURM_JOB_ID"

# ==========================================
# 2. ENVIRONMENT SETUP
# ==========================================
source setup_env.sh \
    --output-dir "$OUTPUT_DIR" \
    --venv-dir "$VENV_DIR" \
    --env-file "$ENV_FILE" \
    --install-log "$INSTALL_LOG" \
    --status-log "$STATUS_LOG"

if [ $? -ne 0 ]; then
    log_msg "CRITICAL: Environment setup failed. Aborting job."
    exit 1
fi

# ==========================================
# 3. DATASET VERIFICATION
# ==========================================
log_msg "Verifying dataset..."
if [ ! -d "$MAESTRO_DIR" ]; then
    log_msg "ERROR: Maestro dataset not found at $MAESTRO_DIR."
    exit 1
fi

# ==========================================
# 4. EXECUTION
# ==========================================
log_msg "=== Executing Rapid Validation Script ==="
python test_pipeline.py

if [ $? -ne 0 ]; then
    log_msg "ERROR: Quick test pipeline failed. Halting job."
    exit 1
fi

# log_msg "=== Executing Main Evaluation Script ==="
# python main.py

log_msg "Job Completed Successfully."