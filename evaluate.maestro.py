import os
import argparse
import subprocess
import pandas as pd
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Batch Evaluate Transkun on MAESTRO")
    parser.add_argument("--maestro_dir", required=True, help="Path to MAESTRO dataset root")
    parser.add_argument("--output_dir", required=True, help="Directory to save predicted MIDIs and logs")
    parser.add_argument("--device", default="cuda", help="Inference device")
    args = parser.parse_args()

    maestro_path = Path(args.maestro_dir)
    out_path = Path(args.output_dir)
    pred_midi_dir = out_path / "predicted_midis"
    pred_midi_dir.mkdir(parents=True, exist_ok=True)

    # 1. Load MAESTRO Metadata
    csv_path = maestro_path / "maestro-v3.0.0.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"Metadata CSV not found at {csv_path}")
    
    print(f"Loading metadata from {csv_path}...")
    df = pd.read_csv(csv_path)
    
    # 2. Filter for Test Split
    test_df = df[df['split'] == 'test']
    print(f"Found {len(test_df)} files in the test split.")

    metrics_log = out_path / "transkun_metrics.log"

    # 3. Batch Processing Loop
    for index, row in test_df.iterrows():
        audio_rel_path = row['audio_filename']
        midi_rel_path = row['midi_filename']
        
        audio_full_path = maestro_path / audio_rel_path
        ground_truth_midi = maestro_path / midi_rel_path
        
        # Generate output filename based on original audio name
        base_name = Path(audio_rel_path).stem
        predicted_midi = pred_midi_dir / f"{base_name}_pred.mid"

        print(f"\n--- Processing: {base_name} ---")

        # --- TRANSCRIPTION ---
        if not predicted_midi.exists():
            transcribe_cmd = [
                "transkun",  # Exposed by pip install from setup.py
                str(audio_full_path),
                str(predicted_midi),
                "--device", args.device
            ]
            try:
                print("Transcribing...")
                # subprocess is acceptable here ONLY because the CLI handles the model 
                # loading internally. (Ideally, we'd import the Python API directly 
                # to keep the model in memory, but this mimics your original goal safely).
                subprocess.run(transcribe_cmd, check=True)
            except subprocess.CalledProcessError as e:
                print(f"Transcription failed for {base_name}: {e}")
                continue
        else:
            print(f"Prediction already exists. Skipping transcription.")

        # --- EVALUATION ---
        eval_cmd = [
            "transkunEval", # Built-in evaluation script from setup.py
            str(ground_truth_midi),
            str(predicted_midi)
        ]
        
        try:
            print("Evaluating...")
            # Capture output so we can append it cleanly to a master log
            result = subprocess.run(eval_cmd, check=True, capture_output=True, text=True)
            
            # Write metrics to terminal and log file
            print(result.stdout)
            with open(metrics_log, "a") as f:
                f.write(f"=== Metrics for {base_name} ===\n")
                f.write(result.stdout)
                f.write("\n")
                
        except subprocess.CalledProcessError as e:
            print(f"Evaluation failed for {base_name}: {e.stderr}")

    print(f"\nBatch evaluation complete. Full metrics saved to {metrics_log}")

if __name__ == "__main__":
    main()