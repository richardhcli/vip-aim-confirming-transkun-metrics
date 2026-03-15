# ==============================================================================
# Script Name: transkun_eval_fork.py
# Description: A standalone, bug-fixed fork of Transkun's computeMetrics.py.
#              Fixes known KeyError and spelling bugs in the original source code
#              while maintaining mathematical parity.
# ==============================================================================

import os
import sys
import argparse
import pathlib
import collections
import warnings
import statistics
import random
import json
from multiprocessing import Pool

import torch
import numpy as np
import scipy.stats
import tqdm

# WHAT: Changed from relative to absolute imports.
# WHY: Allows this script to be run independently of the package source tree.
from transkun import Evaluation
from transkun import Data

#test this file: 
#mkdir -p testing/temp_est testing/temp_gt && cp testing/transkunEstDir/*_pred.mid testing/temp_est/test.mid && cp testing/transkunGroundTruthDir/*.mid testing/temp_gt/test.mid && python transkun_eval_fork.py testing/temp_est testing/temp_gt && rm -rf testing/temp_est testing/temp_gt

def eval_worker(args):
    path, estPath, gtPath, extendSustainPedal, computeDeviations, pedalOffset, alignOnset, dither, extendPedalEst, onsetTolerance = args
    audioName = str(path.relative_to(estPath))

    targetPath = gtPath / path.relative_to(estPath)
    
    notesEst = Data.parseMIDIFile(str(path), extendSustainPedal=extendPedalEst)
    notesGT = Data.parseMIDIFile(str(targetPath), extendSustainPedal=extendSustainPedal, pedal_ext_offset=pedalOffset)

    metrics = Evaluation.compareTranscription(
        notesEst, notesGT, 
        splitPedal=True, 
        computeDeviations=computeDeviations, 
        onset_tolerance=onsetTolerance
    )

    # WHAT: Added safe .get() access for deviations.
    # WHY: Prevents KeyError if Transkun fails to match any notes and skips deviation logic.
    deviations = metrics.get("deviations", [])
    
    if deviations:
        onsetDev = [d[1] for d in deviations]
        offsetDev = [d[2] for d in deviations]
        medianOnsetDev = statistics.median(onsetDev)
        maxDevOnset = max(max(onsetDev), -min(onsetDev))
    else:
        onsetDev, offsetDev = [], []
        medianOnsetDev, maxDevOnset = 0.0, 0.0

    if alignOnset and deviations:
        for n in notesGT:
            n.start += maxDevOnset - medianOnsetDev
            n.end += maxDevOnset - medianOnsetDev

        for n in notesEst:
            n.start += maxDevOnset 
            n.end += maxDevOnset 

    if dither != 0.0:
        for n in notesGT:
            n.start += dither
            n.end += dither 

        for n in notesEst:
            r = (random.random() * 2 - 1) * dither
            n.start += dither + r
            n.end += dither + r
        
        notesEst = Data.resolveOverlapping(notesEst)

        # recompute if dithered
        metrics = Evaluation.compareTranscription(
            notesEst, notesGT, 
            splitPedal=True, 
            computeDeviations=computeDeviations
        )

    return metrics, audioName
    
def main():
    argParser = argparse.ArgumentParser(
        description="Compute metrics directly from MIDI files (Bug-Fixed Fork).\n"
                    "Note that estDIR should have the same folder structure as the groundTruthDIR.\n"
                    "Metrics outputted are ordered by precision, recall, f1, overlap.", 
        formatter_class=argparse.RawTextHelpFormatter
    )

    argParser.add_argument("estDIR")
    argParser.add_argument("groundTruthDIR")
    argParser.add_argument("--outputJSON", help="path to save the output file for detailed metrics per audio file")
    argParser.add_argument("--noPedalExtension", action='store_true', help="Do not perform pedal extension according to the sustain pedal for the ground truth")
    argParser.add_argument("--applyPedalExtensionOnEstimated", action='store_true', help="perform pedal extension for the estimated midi")
    argParser.add_argument("--nProcess", nargs="?", type=int, default=1, help="number of workers for multiprocessing")
    argParser.add_argument("--alignOnset", action='store_true', help="whether or not realign the onset.")
    argParser.add_argument("--dither", default=0.0, type=float, help="amount of noise added to the prediction.")
    argParser.add_argument("--pedalOffset", default=0.0, type=float, help="offset added to the groundTruth sustain pedal when extending notes")
    argParser.add_argument("--onsetTolerance", default=0.05, type=float)

    warnings.filterwarnings('ignore', module='mir_eval')

    args = argParser.parse_args()

    estPath = pathlib.Path(args.estDIR)
    gtPath = pathlib.Path(args.groundTruthDIR)

    outputJSON = args.outputJSON
    extendPedal = not args.noPedalExtension
    extendPedalEst = args.applyPedalExtensionOnEstimated
    computeDeviations = True
    nProcess = args.nProcess
    pedalOffset = args.pedalOffset
    alignOnset = args.alignOnset
    dither = args.dither
    onsetTolerance = args.onsetTolerance

    filenames = list(estPath.glob(os.path.join('**','*.midi'))) + list(estPath.glob(os.path.join('**','*.mid')))
    filenamesFiltered = []

    for filename in filenames:
        targetPath = gtPath / filename.relative_to(estPath)
        if targetPath.exists():
            filenamesFiltered.append(filename)

    filenames = filenamesFiltered

    if nProcess > 1:
        with Pool(nProcess) as p:
            metricsAll = list(
                tqdm.tqdm(
                    p.imap_unordered(eval_worker, [(_, estPath, gtPath, extendPedal, computeDeviations, pedalOffset, alignOnset, dither, extendPedalEst, onsetTolerance) for _ in filenames]),
                    total=len(filenames)
                )
            )
    else:
        # WHAT: Fixed the spelling errors (extendPedalEs -> extendPedalEst, onsetTolerancet -> onsetTolerance)
        metricsAll = list(
            tqdm.tqdm(
                map(eval_worker, [(_, estPath, gtPath, extendPedal, computeDeviations, pedalOffset, alignOnset, dither, extendPedalEst, onsetTolerance) for _ in filenames]),
                total=len(filenames)
            )
        )

    # aggregate
    aggDict = collections.defaultdict(list)

    for m, _ in metricsAll:
        for key in m:
            aggDict[key].append(m[key])


    #The massive block of text at the top of your output is a FutureWarning from SciPy. It is warning you that in future versions of Python, the scipy.stats.anderson() function will require a specific method parameter.
    #To fix this and keep the terminal perfectly clean, we will add a filter to ignore this specific warning.
    warnings.filterwarnings('ignore', module='mir_eval')
    # WHAT: Added a filter for the SciPy Anderson-Darling method warning
    # WHY: Keeps the log files clean from future-deprecation terminal spam
    warnings.filterwarnings('ignore', category=FutureWarning, module='scipy')

    resultAgg = dict()
    for key in aggDict:
        if key == "deviations":
            devAll = sum(aggDict[key], [])
            # WHAT: Added a safety check for the Anderson normality test.
            # WHY: scipy.stats.anderson physically crashes if given less than 4 data points.
            if len(devAll) >= 4:
                dev_onset = np.array([_[1] for _ in devAll])
                dev_offset = np.array([_[2] for _ in devAll])
                onset_result = scipy.stats.anderson(dev_onset)
                offset_result = scipy.stats.anderson(dev_offset)
                resultAgg["deviation_onset_normality"] = onset_result.statistic
                resultAgg["deviation_offset_normality"] = offset_result.statistic
            else:
                resultAgg["deviation_onset_normality"] = None
                resultAgg["deviation_offset_normality"] = None
        else:
            tmp = np.array(aggDict[key])
            resultAgg[key] = (np.mean(tmp, axis=0).tolist())
    
    for key in resultAgg:
        print("{}: {}".format(key, resultAgg[key]))

    if outputJSON is not None:
        resultList = [{"name": name, "metrics": m} for m, name in metricsAll]
        result = {"aggregated": resultAgg, "detailed": resultList}

        with open(outputJSON, 'w') as f:
            f.write(json.dumps(result, indent='\t'))

if __name__=="__main__":
    main()