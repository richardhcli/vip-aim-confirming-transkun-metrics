#!/bin/bash
#SBATCH --job-name=transkun_eval
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=32
#SBATCH --time=12:00:00

# Load modules and activate environment
module load ffmpeg
module load parallel
source activate transkun_env

echo "=== 1. Downloading and Unzipping Full MAESTRO Dataset ==="
# Download the full dataset containing both audio and MIDI (~120GB)
wget --progress=bar:force -O maestro-v3.0.0.zip https://storage.googleapis.com/magentadata/datasets/maestro/v3.0.0/maestro-v3.0.0.zip
unzip -q maestro-v3.0.0.zip
rm maestro-v3.0.0.zip

echo "=== 2. Resampling Audio to 44100 Hz ==="
# Transkun strictly assumes a 44100 Hz sampling rate. 
# We only need to resample the 2017 and 2018 folders.
find maestro-v3.0.0/2017 maestro-v3.0.0/2018 -type f -name "*.wav" | parallel -j 32 '
    ffmpeg -loglevel error -y -i {} -ar 44100 {}_tmp.wav && mv {}_tmp.wav {}
'
echo "Resampling complete."

echo "=== 3. Transcribing the Test Split ==="
# Run the python script to parse the CSV, filter the test set, and transcribe
python3 transcribe_test_split.py

echo "=== 4. Evaluating Metrics and Saving Results ==="
# Evaluate the estimated MIDIs against the ground truth
# This command calculates precision, recall, and F1 scores, and saves detailed JSON logs
transkunEval estDIR groundTruthDIR \
    --outputJSON maestro_test_metrics.json \
    --computeDeviations

echo "Evaluation complete. Summary metrics printed above. Detailed data saved to maestro_test_metrics.json"