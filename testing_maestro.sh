#!/bin/bash
# ==============================================================================
# Script Name: testing_maestro.sh
# Description: Wrapper to acquire MAESTRO to SCRATCH and run light evaluation.
# Usage:       source testing_maestro.sh
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
python evaluate_maestro_light.py \
    --maestro_dir "$MAESTRO_DATASET_PREPROCESSED" \
    --output_dir "$OUTPUT_DIR" >> "$STATUS_LOG" 2>> "$ERROR_LOG"

if [ $? -ne 0 ]; then
    log_msg "ERROR: Light evaluation failed. Check $ERROR_LOG."
    return 1
fi

log_msg "Testing pipeline completed successfully!"
return 0