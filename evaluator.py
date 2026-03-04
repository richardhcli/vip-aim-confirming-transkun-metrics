import os
import json
import shutil
import subprocess

def evaluate_maestro_subset(audio_files, ground_truth_midis, output_dir="transkun_output"):
    """
    Evaluates a subset of audio files against ground truth MIDIs using the Transkun model.
    
    Args:
        audio_files (list): List of paths to the target.wav audio files.
        ground_truth_midis (list): List of paths to the corresponding ground truth.mid files.
        output_dir (str): The root directory where estimated and staged ground truth files will be saved.
        
    Returns:
        dict: A dictionary containing the accumulated evaluation metrics.
    """
    est_dir = os.path.join(output_dir, "estDIR")
    gt_dir = os.path.join(output_dir, "groundTruthDIR")
    
    # Create flat directories to store paired files for evaluation
    os.makedirs(est_dir, exist_ok=True)
    os.makedirs(gt_dir, exist_ok=True)

    print(f"Starting transcription for {len(audio_files)} files...")
    
    for audio_path, gt_midi in zip(audio_files, ground_truth_midis):
        # Generate a flat filename to ensure exact matching between estimation and ground truth folders
        base_name = audio_path.replace('/', '_').replace('.wav', '')
        est_midi = os.path.join(est_dir, f"{base_name}.mid")
        gt_dest = os.path.join(gt_dir, f"{base_name}.mid")

        # Copy the ground truth MIDI to the flat directory structure
        shutil.copy(gt_midi, gt_dest)

        # Transcribe using Transkun CLI if not already transcribed
        if not os.path.exists(est_midi):
            print(f"Transcribing: {audio_path}")
            # Calls the default Transkun CLI with CUDA support
            subprocess.run(['transkun', audio_path, est_midi, '--device', 'cuda'], check=True) 
        else:
            print(f"Skipping {audio_path}, already transcribed.")

    json_output_path = os.path.join(output_dir, "metrics.json")
    
    print("Evaluating transcribed files against ground truth...")
    
    # Run transkunEval to accumulate metrics and save to JSON [1]
    subprocess.run(['transkunEval', est_dir, gt_dir, '--outputJSON', json_output_path, '--computeDeviations'], check=True)

    # Load and return the generated metrics back to the main script
    with open(json_output_path, 'r') as f:
        metrics = json.load(f)
    
    return metrics