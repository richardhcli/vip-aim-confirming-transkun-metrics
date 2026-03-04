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

#run command: 
# sbatch "/home/li5042/ondemand/data/sys/myjobs/projects/testing/pythonJob/quickQueue.job.sh"


# ==========================================
# 1. VARIABLES
# ==========================================
WORKING_DIR=/home/li5042/ondemand/data/sys/myjobs/projects/testing/transkun2
OUTPUT_DIR=$WORKING_DIR/output
VENV_DIR=$WORKING_DIR/venv
ENV_FILE="environment.yml"
INSTALL_LOG="$OUTPUT_DIR/install.log"

cd $WORKING_DIR
# Ensure output directory exists before writing logs
mkdir -p $OUTPUT_DIR 
echo "* Starting Job $SLURM_JOB_ID"
echo "--- Install Log ---" > $INSTALL_LOG

# ==========================================
# 2. CONDA INIT
# ==========================================
module load conda
conda config --set solver libmamba

# ==========================================
# 3. ENVIRONMENT SYNC
# ==========================================
# Option A: Call the modularized script to handle the environment sync
bash setup_env.sh $VENV_DIR $ENV_FILE $INSTALL_LOG

# Option B: (Commented out just in case) Inline environment update without hashing
# echo -e "\t* Syncing environment inline..."
# conda env update --prefix $VENV_DIR --file $ENV_FILE --prune >> $INSTALL_LOG 2>&1

# Activate the synced environment for the execution phase
source activate $VENV_DIR

# ==========================================
# 4. DATASET VERIFICATION
# ==========================================
echo -e "\t* Verifying dataset..."
if [! -d "maestro-v3.0.0" ]; then
    echo "ERROR: maestro-v3.0.0 directory not found in $WORKING_DIR."
    exit 1
fi

# ==========================================
# 5. EXECUTION
# ==========================================
echo "=== Executing Rapid Validation Script ==="
# Run the test script on 2 files to ensure the pipeline is functioning properly
python full_evaluate_against_maestro.py

# Check if the quick test was successful before committing to the main run
if [ $? -ne 0 ]; then
    echo "ERROR: Quick test pipeline failed. Halting job."
    exit 1
fi

# echo "=== Executing Main Evaluation Script ==="
# # If the quick validation succeeds, run the full test dataset
# python main.py

# echo "* Job Completed Successfully."