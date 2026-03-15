import os
import shutil
import sys
import argparse
import subprocess
import tempfile
import pandas as pd
from pathlib import Path

# python "/scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/evaluate_maestro_light.py" --maestro_dir "/scratch/gilbreth/li5042/datasets/maestro_dataset" --output_dir /scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output

#testing this file:
#python evaluate_maestro_light.py --maestro_dir "/scratch/gilbreth/li5042/datasets/maestro_dataset" --output_dir /scratch/gilbreth/li5042/transkun/vip-aim-confirming-transkun-metrics/output

import os
import sys
import argparse
import subprocess
import pandas as pd
from pathlib import Path

from standard_mir_eval import evaluate_midi

def filter_and_route_errors(stderr_str, error_log_path, base_name, context):
    """
    Strips tqdm progress bars from the standard error stream.
    If actual warnings or errors remain, appends them to the error log.
    """
    if not stderr_str:
        return
        
    clean_err = "\n".join([
        line for line in stderr_str.split('\n') 
        if line.strip() and not ("it [" in line or "it/s]" in line)
    ])
    
    # If there is remaining text after stripping progress bars, it is a real error/warning
    if clean_err.strip():
        with open(error_log_path, "a") as f:
            f.write(f"=== {context} : {base_name} ===\n")
            f.write(f"{clean_err.strip()}\n\n")

def main():
    parser = argparse.ArgumentParser(description="Light Batch Evaluate Transkun on MAESTRO")
    parser.add_argument("--maestro_dir", required=True, help="Path to MAESTRO dataset root")
    parser.add_argument("--output_dir", required=True, help="Directory to save predicted MIDIs and logs")
    parser.add_argument("--device", default="cuda", help="Inference device")
    args = parser.parse_args()

    maestro_path = Path(args.maestro_dir)
    out_path = Path(args.output_dir)
    
    pred_midi_dir = out_path / "predicted_midis"
    pred_midi_dir.mkdir(parents=True, exist_ok=True)

    # Define the master error log explicitly
    error_log = out_path / "error.log"

    csv_path = maestro_path / "maestro-v3.0.0.csv"
    if not csv_path.exists():
        print(f"ERROR: Metadata CSV not found at {csv_path}")
        sys.exit(1)
    
    df = pd.read_csv(csv_path)
    test_df = df[df['split'] == 'test'].head(5)
    print(f"Loaded MAESTRO test split. Running light evaluation on {len(test_df)} files...\n")

    metrics_log = out_path / "metrics_light.log"
    open(metrics_log, 'w').close()

    for i, (index, row) in enumerate(test_df.iterrows(), start=1):
        audio_rel_path = row['audio_filename']
        midi_rel_path = row['midi_filename']
        
        audio_full_path = maestro_path / audio_rel_path
        ground_truth_midi = maestro_path / midi_rel_path
        base_name = Path(audio_rel_path).stem
        predicted_midi = pred_midi_dir / f"{base_name}_pred.mid"

        print(f"--- Processing [{i}/5]: {base_name} ---")

        # Dynamic Extension Fallback (.midi -> .mid)
        if not ground_truth_midi.exists() and ground_truth_midi.suffix == '.midi':
            fallback_path = ground_truth_midi.with_suffix('.mid')
            if fallback_path.exists():
                ground_truth_midi = fallback_path
            else:
                print(f"  -> CRITICAL: Ground truth missing. Check error.log.")
                with open(error_log, "a") as f:
                    f.write(f"=== DATASET ERROR : {base_name} ===\nGround truth file not found at {ground_truth_midi}\n\n")
                continue

        # --- TRANSCRIPTION ---
        if not predicted_midi.exists():
            transcribe_cmd = ["transkun", str(audio_full_path), str(predicted_midi), "--device", args.device]
            try:
                print("  -> Transcribing audio to MIDI...")
                result = subprocess.run(transcribe_cmd, check=True, capture_output=True, text=True)
                # Route non-fatal warnings (like PyTorch weights_only) to error.log
                filter_and_route_errors(result.stderr, error_log, base_name, "TRANSCRIPTION WARNING")
            except subprocess.CalledProcessError as e:
                print(f"  -> ERROR: Transcription failed. Check error.log.")
                filter_and_route_errors(e.stderr, error_log, base_name, "TRANSCRIPTION CRASH")
                sys.exit(1) 
        else:
            print("  -> Prediction exists. Skipping transcription.")

        # --- EVAL 1: TRANSKUN BUILT-IN (Via Standalone Fork) ---
        try:
            print("  -> Running transkun_eval_fork.py...")
            
            # WHAT: Create the directory sandbox
            with tempfile.TemporaryDirectory() as temp_est, tempfile.TemporaryDirectory() as temp_gt:
                
                # Force identical filenames to satisfy the directory parser
                temp_est_file = Path(temp_est) / "eval_match.mid"
                temp_gt_file = Path(temp_gt) / "eval_match.mid"
                
                shutil.copy(predicted_midi, temp_est_file)
                shutil.copy(ground_truth_midi, temp_gt_file)
                
                # WHAT: Call your custom fork instead of the broken CLI command
                eval_cmd = [
                    sys.executable, 
                    "transkun_eval_fork.py", 
                    str(temp_est), 
                    str(temp_gt)
                ]
                
                transkun_result = subprocess.run(eval_cmd, check=True, capture_output=True, text=True)
                
                # Filter out the tqdm progress bars
                combined = transkun_result.stdout + "\n" + transkun_result.stderr
                clean_lines = [
                    line for line in combined.split('\n') 
                    if line.strip() and not ("it [" in line or "it/s]" in line)
                ]
                
                if clean_lines:
                    transkun_output = "\n".join(clean_lines)
                else:
                    transkun_output = "Error: No metrics found in output. Check error.log."
                    
        except subprocess.CalledProcessError as e:
            transkun_output = "Transkun Eval Fork Error. Check error.log."
            filter_and_route_errors(e.stderr, error_log, base_name, "TRANSKUN EVAL FORK CRASH")
        except Exception as e:
            transkun_output = "Transkun Eval Sandbox Error. Check error.log."
            with open(error_log, "a") as f:
                f.write(f"=== TRANSKUN EVAL SANDBOX CRASH : {base_name} ===\n{str(e)}\n\n")
                
                
        # --- EVAL 2: STANDARD MIR_EVAL (Imported Helper) ---
        try:
            print("  -> Running standard_mir_eval helper module...")
            eval_data = evaluate_midi(ground_truth_midi, predicted_midi)
            
            meta = eval_data["Metadata"]
            scores = eval_data["Scores"]
            
            helper_output = "--- Custom Metadata ---\n"
            helper_output += f"Reference : {meta['Reference']['Instruments']} Inst | {meta['Reference']['Notes']} Notes | {meta['Reference']['Duration_sec']:.2f}s\n"
            helper_output += f"Prediction: {meta['Prediction']['Instruments']} Inst | {meta['Prediction']['Notes']} Notes | {meta['Prediction']['Duration_sec']:.2f}s\n\n"
            helper_output += "--- Custom Scores ---\n"
            for k, v in scores.items():
                helper_output += f"{k}: {v:.6f}\n"
                
        except Exception as e:
            helper_output = "Standard mir_eval Error. Check error.log."
            with open(error_log, "a") as f:
                f.write(f"=== STANDARD MIR_EVAL CRASH : {base_name} ===\n{str(e)}\n\n")

        # --- LOGGING TO MASTER FILE ---
        print("  -> Saving results to log...")
        with open(metrics_log, "a") as f:
            f.write(f"========================================\n")
            f.write(f"FILE: {base_name}\n")
            f.write(f"========================================\n\n")
            
            f.write(f"--- 1. TRANSKUN EVAL METRICS ---\n")
            f.write(transkun_output + "\n\n\n")
            
            f.write(f"--- 2. STANDARD MIR_EVAL METRICS ---\n")
            f.write(helper_output.strip() + "\n\n\n")

    print(f"\nLight batch evaluation complete! Full metrics saved to: {metrics_log}")

if __name__ == "__main__":
    main()