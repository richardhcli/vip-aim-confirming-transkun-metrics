# import os
# import sys
# import argparse
# import subprocess
# import pandas as pd
# from pathlib import Path

# #example run: 
# import warnings
# warnings.filterwarnings("ignore", message=".*pkg_resources is deprecated.*")
# warnings.filterwarnings("ignore", message=".*not a valid type 0 or type 1 MIDI file.*")

# import pretty_midi
# import numpy as np
# import argparse
# import mir_eval
# import sys

# sys.setrecursionlimit(10000)

# def extract_custom_data(midi_file):
#     """Extracts intervals, pitches, and custom metadata."""
#     midi_data = pretty_midi.PrettyMIDI(midi_file)
#     intervals = []
#     pitches = []
    
#     total_notes = 0
#     duration = midi_data.get_end_time()

#     for instrument in midi_data.instruments:
#         total_notes += len(instrument.notes)
#         for note in instrument.notes:
#             intervals.append([note.start, note.end])
#             pitches.append(pretty_midi.note_number_to_hz(note.pitch))

#     if not intervals:
#         intervals_arr, pitches_arr = np.empty((0, 2)), np.array([])
#     else:
#         intervals, pitches = zip(*sorted(zip(intervals, pitches), key=lambda x: x[0][0]))
#         intervals_arr, pitches_arr = np.array(intervals), np.array(pitches)
        
#     return intervals_arr, pitches_arr, len(midi_data.instruments), total_notes, duration

# def main():
#     parser = argparse.ArgumentParser(description="Custom Scorer with Metadata.")
#     parser.add_argument("--reference", required=True)
#     parser.add_argument("--transcription", required=True)
#     args = parser.parse_args()

#     ref_inv, ref_pitch, ref_inst, ref_notes, ref_dur = extract_custom_data(args.reference)
#     est_inv, est_pitch, est_inst, est_notes, est_dur = extract_custom_data(args.transcription)

#     scores = mir_eval.transcription.evaluate(ref_inv, ref_pitch, est_inv, est_pitch)

#     print("--- Custom Metadata ---")
#     print(f"Reference: {ref_inst} Instruments | {ref_notes} Notes | {ref_dur:.2f} Seconds")
#     print(f"Prediction: {est_inst} Instruments | {est_notes} Notes | {est_dur:.2f} Seconds")
#     print("\n--- Custom Scores ---")
#     for key, value in scores.items():
#         print(f"{key}: {value:.6f}")

# if __name__ == "__main__":
#     main()