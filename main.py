import os
import pandas as pd
import json
from evaluator import evaluate_maestro_subset

def main():
    """
    Main execution script to evaluate the entire MAESTRO test split using the Transkun model.
    """
    csv_path = 'maestro-v3.0.0/maestro-v3.0.0.csv'
    if not os.path.exists(csv_path):
        raise FileNotFoundError("MAESTRO metadata CSV not found. Ensure the dataset is downloaded and unzipped.")

    # Load metadata
    df = pd.read_csv(csv_path)
    
    # Isolate only the test split data
    test_df = df[df['split'] == 'test']

    # Generate lists mapping the audio and MIDI files
    audio_paths = [os.path.join('maestro-v3.0.0', row['audio_filename']) for _, row in test_df.iterrows()]
    midi_paths = [os.path.join('maestro-v3.0.0', row['midi_filename']) for _, row in test_df.iterrows()]

    print(f"Loaded {len(audio_paths)} files from the test split.")
    
    # Call the modularized evaluator function over all test data
    metrics = evaluate_maestro_subset(audio_paths, midi_paths, output_dir="maestro_full_test_results")

    # Save the consolidated final results 
    with open("final_test_metrics.json", "w") as f:
        json.dump(metrics, f, indent=4)
        
    print("Successfully evaluated all test data. Results saved to final_test_metrics.json.")

if __name__ == "__main__":
    main()