# standard_mir_eval.py
import warnings
warnings.filterwarnings("ignore", message=".*pkg_resources is deprecated.*")
warnings.filterwarnings("ignore", message=".*not a valid type 0 or type 1 MIDI file.*")

import pretty_midi
import numpy as np
import mir_eval
import sys

sys.setrecursionlimit(10000)

def extract_notes_and_metadata(midi_file):
    """
    Extracts pitches, intervals, and metadata from a MIDI file.
    Returns: (intervals, pitches, num_instruments, total_notes, duration)
    """
    midi_data = pretty_midi.PrettyMIDI(str(midi_file))
    intervals = []
    pitches = []
    total_notes = 0
    duration = midi_data.get_end_time()

    for instrument in midi_data.instruments:
        # Standard mir_eval usually ignores drum tracks for pitch evaluation
        if not instrument.is_drum:
            total_notes += len(instrument.notes)
            for note in instrument.notes:
                intervals.append([note.start, note.end])
                pitches.append(pretty_midi.note_number_to_hz(note.pitch))

    if not intervals:
        return np.empty((0, 2)), np.array([]), len(midi_data.instruments), total_notes, duration

    intervals, pitches = zip(*sorted(zip(intervals, pitches), key=lambda x: x[0][0]))
    return np.array(intervals), np.array(pitches), len(midi_data.instruments), total_notes, duration

def evaluate_midi(ref_file, est_file):
    """
    Computes standard mir_eval metrics and custom metadata.
    Returns a dictionary containing all metrics.
    """
    ref_inv, ref_pitch, ref_inst, ref_notes, ref_dur = extract_notes_and_metadata(ref_file)
    est_inv, est_pitch, est_inst, est_notes, est_dur = extract_notes_and_metadata(est_file)

    scores = mir_eval.transcription.evaluate(ref_inv, ref_pitch, est_inv, est_pitch)
    
    # Package everything into a structured dictionary for the main script to parse
    results = {
        "Metadata": {
            "Reference": {"Instruments": ref_inst, "Notes": ref_notes, "Duration_sec": ref_dur},
            "Prediction": {"Instruments": est_inst, "Notes": est_notes, "Duration_sec": est_dur}
        },
        "Scores": scores
    }
    return results