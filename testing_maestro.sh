#!/bin/bash
# ==============================================================================
# Script Name: testing_maestro.sh
# Description: Wrapper to acquire MAESTRO to SCRATCH and run light evaluation.
# Usage:       source testing_maestro.sh
# ==============================================================================

#one test: 
# transkun /scratch/gilbreth/li5042/datasets/maestro_dataset/2004/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav.wav /scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav.mid --device cpu
# ==============================================================================

REDOWNLOAD_FLAG=false

# Ensure the required variables were passed from job.sh
if [ -z "$MAESTRO_DIR" ] || [ -z "$MAESTRO_DATASET_PREPROCESSED" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "CRITICAL: Missing required path variables."
    return 1
fi

log_msg "=== Phase 1: Dataset Acquisition ==="

if [ "$REDOWNLOAD_FLAG" = true ]; then
    log_msg "Redownload flag is set. Removing existing dataset at $MAESTRO_DATASET_PREPROCESSED"
    rm -rf "$MAESTRO_DATASET_PREPROCESSED"

    # Execute the download/symlink script, pointing the destination to SCRATCH
    python download_maestro.py \
        --source "$MAESTRO_DIR" \
        --dest "$MAESTRO_DATASET_PREPROCESSED" >> "$STATUS_LOG" 2>> "$ERROR_LOG"

    if [ $? -ne 0 ]; then
        log_msg "ERROR: Dataset acquisition failed. Check $ERROR_LOG."
        return 1
    fi

fi

log_msg "=== Phase 2: Light Evaluation Pipeline ==="

# Execute the light evaluation, pointing it to the newly prepared SCRATCH path
# (Note: To test on CPU, add '--device cpu' as an argument before the log redirections)
python -u evaluate_maestro_light.py \
    --maestro_dir "$MAESTRO_DATASET_PREPROCESSED" \
    --output_dir "$OUTPUT_DIR" >> "$STATUS_LOG" 2>> "$ERROR_LOG"

if [ $? -ne 0 ]; then
    log_msg "ERROR: Light evaluation failed. Check $ERROR_LOG."
    return 1
fi

log_msg "Testing pipeline completed successfully!"
return 0