#!/bin/bash
# ==============================================================================
# Script Name: testing_maestro.sh
# Description: Wrapper to acquire MAESTRO to SCRATCH and run light evaluation.
# Usage:       source testing_maestro.sh
# ==============================================================================

#one test: 
# transkun /scratch/gilbreth/li5042/datasets/maestro_dataset/2004/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav.wav /scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav.mid --device cpu
# ==============================================================================

# Ensure the required variables were passed from job.sh
if [ -z "$MAESTRO_DIR" ] || [ -z "$MAESTRO_DATASET_PREPROCESSED" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "CRITICAL: Missing required path variables."
    return 1
fi

log_msg "=== Phase 1: Dataset Acquisition ==="

# Execute the download/symlink script, pointing the destination to SCRATCH
python download_maestro.py \
    --source "$MAESTRO_DIR" \
    --dest "$MAESTRO_DATASET_PREPROCESSED" >> "$STATUS_LOG" 2>> "$ERROR_LOG"

if [ $? -ne 0 ]; then
    log_msg "ERROR: Dataset acquisition failed. Check $ERROR_LOG."
    return 1
fi

log_msg "=== Phase 2: Light Evaluation Pipeline ==="

# Execute the light evaluation, pointing it to the newly prepared SCRATCH path
# WHAT: Added the -u flag to the python call.
# WHY: Forces Python to flush every single print() statement instantly to the 
# log file, ensuring you see real-time updates and crash traces.
python -u evaluate_maestro_light.py \   
    --maestro_dir "$MAESTRO_DATASET_PREPROCESSED" \
    --output_dir "$OUTPUT_DIR" \
    --device cpu \   #ONLY DO THIS FOR TESTING -CPU IS VERY SLOW. Remove this line for GPU execution.
    >> "$STATUS_LOG" 2>> "$ERROR_LOG"


if [ $? -ne 0 ]; then
    log_msg "ERROR: Light evaluation failed. Check $ERROR_LOG."
    return 1
fi

log_msg "Testing pipeline completed successfully!"
return 0