import os
import sys
import argparse
import subprocess
import pandas as pd
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Light Batch Evaluate Transkun on 5 MAESTRO files")
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
        print(f"ERROR: Metadata CSV not found at {csv_path}")
        sys.exit(1)
    
    df = pd.read_csv(csv_path)
    
    # 2. Filter for Test Split and limit to exactly 5 files
    test_df = df[df['split'] == 'test'].head(5)
    print(f"Loaded MAESTRO test split. Running light evaluation on {len(test_df)} files...\n")

    metrics_log = out_path / "metrics_light.log"
    
    # Clear previous light log
    open(metrics_log, 'w').close()

    # 3. Batch Processing Loop
    # WHAT: Added enumerate(..., start=1) to create a clean 1-to-5 counter
    for i, (index, row) in enumerate(test_df.iterrows(), start=1):
        audio_rel_path = row['audio_filename']
        midi_rel_path = row['midi_filename']
        
        audio_full_path = maestro_path / audio_rel_path
        ground_truth_midi = maestro_path / midi_rel_path
        
        base_name = Path(audio_rel_path).stem
        predicted_midi = pred_midi_dir / f"{base_name}_pred.mid"

        print(f"--- Processing [{i}/5]: {base_name} ---")

        # --- TRANSCRIPTION ---
        if not predicted_midi.exists():
            transcribe_cmd = [
                "transkun", 
                str(audio_full_path),
                str(predicted_midi),
                "--device", args.device
            ]
            try:
                print("  -> Transcribing audio to MIDI...")
                # WHAT: Replaced DEVNULL with capture_output=True and text=True
                # WHY: Traps the specific Transkun/PyTorch crash logs as readable text
                result = subprocess.run(transcribe_cmd, check=True, capture_output=True, text=True)
                
            except subprocess.CalledProcessError as e:
                print(f"  -> ERROR: Transcription failed for {base_name}.")
                # Print the exact stderr from the child process
                print(f"  -> TRANSKUN CRASH LOG:\n{e.stderr}")
                continue
        else:
            print("  -> Prediction exists. Skipping transcription.")
            
        # --- TRANSKUN BUILT-IN EVALUATION ---
        eval_cmd = [
            "transkunEval",
            str(ground_truth_midi),
            str(predicted_midi)
        ]
        
        try:
            print("  -> Running transkunEval metrics...")
            transkun_result = subprocess.run(eval_cmd, check=True, capture_output=True, text=True)
            transkun_output = transkun_result.stdout
        except subprocess.CalledProcessError as e:
            transkun_output = f"Transkun Eval Error: {e.stderr}"

        # --- CUSTOM SCORING.PY EVALUATION ---
        custom_eval_cmd = [
            sys.executable, # Uses the python executable from the active Conda environment
            "scoring.py",
            "--reference", str(ground_truth_midi),
            "--transcription", str(predicted_midi)
        ]

        try:
            print("  -> Running custom scoring.py metrics...")
            custom_result = subprocess.run(custom_eval_cmd, check=True, capture_output=True, text=True)
            custom_output = custom_result.stdout
        except subprocess.CalledProcessError as e:
            custom_output = f"Custom Scoring Error: {e.stderr}"

        # --- LOGGING TO FILE ---
        print("  -> Saving results to log...")
        with open(metrics_log, "a") as f:
            f.write(f"========================================\n")
            f.write(f"FILE: {base_name}\n")
            f.write(f"========================================\n\n")
            
            f.write(f"--- TRANSKUN EVAL METRICS ---\n")
            f.write(transkun_output.strip() + "\n\n")
            
            f.write(f"--- CUSTOM SCORING.PY METRICS ---\n")
            f.write(custom_output.strip() + "\n\n\n")

    print(f"\nLight batch evaluation complete! Full metrics saved to: {metrics_log}")

if __name__ == "__main__":
    main()