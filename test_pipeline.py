import os
import pandas as pd
import json
from evaluator import evaluate_maestro_subset

def test_pipeline():
    """
    Executes a quick test of the transcription pipeline using only 2 files from the dataset.
    """
    csv_path = 'maestro-v3.0.0/maestro-v3.0.0.csv'
    if not os.path.exists(csv_path):
        raise FileNotFoundError("MAESTRO metadata CSV not found. Ensure the dataset is downloaded and unzipped.")

    df = pd.read_csv(csv_path)
    
    # Take only the first 2 files from the test split for a rapid system validation
    test_df = df[df['split'] == 'test'].head(2)

    audio_paths = [os.path.join('maestro-v3.0.0', row['audio_filename']) for _, row in test_df.iterrows()]
    midi_paths = [os.path.join('maestro-v3.0.0', row['midi_filename']) for _, row in test_df.iterrows()]

    print(f"Running quick pipeline validation on {len(audio_paths)} files...")
    
    # Call the evaluator function
    metrics = evaluate_maestro_subset(audio_paths, midi_paths, output_dir="maestro_quick_test_results")

    # Save the output metrics for user review
    with open("quick_test_metrics.json", "w") as f:
        json.dump(metrics, f, indent=4)
        
    print("Quick test complete! Output data generated successfully. The system is functioning properly.")

if __name__ == "__main__":
    test_pipeline()