# R1: accepted finite NPRACH profile

Candidate only; original receiver/calibration untouched. The old nine mixed-waveform cases were reproduced exactly900/900before the patch. Legacy threshold0.0013808158865320679 admitted false starting-tone indices for strong own signals and closest-neighbor NPUSCH interferers.

Presence now uses all12public tone templates, four symbol groups, joint quadratic envelope regression and a min-group partial-energy statistic. Timing/CFO for accepted indices uses public-template SIC fitted to received samples. No true UE list, channel taps, payload, transmitter identity or chosen collision winner enters the production RX.

## Fresh acceptance fixed before data

Threshold0.005; receiver group-partial-quadratic-v2, parameter estimator sic-public-template-v1. Noise realization4005:0/20000, exact two-sided95%upperPFA0.000184426964. Independent interference realization4004 uses3tap Rayleigh/CFO±200Hz, fullULroundtrip2d/c plus sync±2us, closest legal neighboring band45kHz. The six20000-window cases are:

| Interferer/sampleSNRdB | False windows | Upper95%PFA |
|---|---:|---:|
|Data20|2|0.000361187203|
|Data40|1|0.000278550332|
|Msg320|3|0.000438300453|
|Msg340|4|0.000511999534|
|Control20|0|0.000184426964|
|Control40|0|0.000184426964|

All six meet predeclared upperPFA≤0.001. Interference elapsed2276.902s.13dependency hashes were unchanged across the gate. Waveforms of every false case and batch identities are preserved. Earlier failed0.004holdout4003 became development and was not reused as independent acceptance.

Composite accepted calibration SHA1068f3daaa8c2fb8d62bc34671f63e1462b6f2b81da9f1b8cf75820c013216e4 is now candidate results/nprach-calibration.mat. Previous calibration is nprach-calibration-legacy-v1.mat. Source/control/environment/calibration versions accompany new system cases.

## Sensitivity and remaining limits

Final development fixtures:900windows, all intended true indices found,0extra/0miss at0.005. The fixed40dBweak timing regression improved error14.959→4.576samples viaSIC. Tests5/5passed.

Independent-channel development sweep used100trials/ratio paired across0/6/12/20/30/40dB and tested thresholds. Strong conditional sampleSNR20dB: weak detections100/100through30dB,95/100at40dB with95%CI[.887165,.983568]. At40dB,10/95detections have timing error>8samples and1/95CFO error>50Hz. This is finite sensitivity evidence, not the fresh PFA gate, a universal robustness claim or a full Msg3 capture curve.

Same-NInit UE share a presence index; physical Msg3/Msg4 decides the winner. Full independent two-UE capture repeats and40dBData traces remain open. No weak-UE success is imposed from truth.

Final accepted-calibration full1UE case:completed16.846s,1RA success,1delivered/1600bits,Data8decodes/0CRCfail,delay612ticks. After the separate immutable-profile cache it still exactly matches17result fields and6CSV hashes, elapsed14.193s. These timings are single observed runs, not a speedup guarantee.

Evidence: r1-floor005-prevalidation.md; r1-noise-calibration-floor005.txt; r1-interference-holdout-floor005/report.mat and summary.csv; r1-floor005-dependencies-start/finish.json; r1-final-development005; r1-nearfar-sensitivity-v2; radio-final-single; profile-cache-system.mat.
