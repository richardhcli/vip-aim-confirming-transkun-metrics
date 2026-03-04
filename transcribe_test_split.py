# import os
# import pandas as pd
# import subprocess
# import shutil

# def main():
#     # Load MAESTRO metadata
#     csv_path = 'maestro-v3.0.0/maestro-v3.0.0.csv'
#     df = pd.read_csv(csv_path)
    
#     # Filter for only the test split to replicate the paper's evaluation
#     test_df = df[df['split'] == 'test']

#     # Create flat directories for the evaluation script to compare
#     os.makedirs('estDIR', exist_ok=True)
#     os.makedirs('groundTruthDIR', exist_ok=True)

#     total_files = len(test_df)
#     print(f"Found {total_files} files in the test split.")

#     for index, row in test_df.iterrows():
#         audio_path = os.path.join('maestro-v3.0.0', row['audio_filename'])
#         midi_path = os.path.join('maestro-v3.0.0', row['midi_filename'])

#         # Create a safe, flat filename to match estimated and ground truth files
#         base_name = row['audio_filename'].replace('/', '_').replace('.wav', '')
#         est_midi = os.path.join('estDIR', f"{base_name}.mid")
#         gt_midi = os.path.join('groundTruthDIR', f"{base_name}.mid")

#         # Copy ground truth MIDI to the flat directory
#         shutil.copy(midi_path, gt_midi)

#         # Skip transcription if it was already processed (useful if the job restarts)
#         if not os.path.exists(est_midi):
#             print(f"Transcribing ({index+1}/{total_files}): {audio_path}...")
#             # Execute the Transkun model
#             subprocess.run(['transkun', audio_path, est_midi, '--device', 'cuda'], check=True)
#         else:
#             print(f"Skipping {audio_path}, already transcribed.")

# if __name__ == "__main__":
#     main()