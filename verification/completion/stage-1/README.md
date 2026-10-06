# Stage 1 verification evidence

Checkout: `codex/2026-10-06-project-completion`, based on v2.0.0
`2eb4848bb1acc0a1fd17797907b0a84a291c02f7`.
MATLAB: `D:\MATLAB\bin\matlab.exe`, version
`25.2.0.2998904 (R2025b)`, release `2025b`.

All commands ran from this checkout. MATLAB runs used the authorized
outside-sandbox path because the baseline sandbox startup failed with
`System Error: File system inconsistency`.

## Reproduce

```powershell
$stageActive = @(Get-Process matlab -ErrorAction SilentlyContinue)
if ($stageActive.Count -gt 0) { throw 'MATLAB already active' }
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1Targeted.m')" -logfile verification/completion/stage-1/targeted-green-accepted.log
```

Final full suite uses the same guard:

```powershell
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1FullSuite.m')" -logfile verification/completion/stage-1/full-suite-final.log
```

`full-suite-final.log`: **143/143 passed**, 0 failed/incomplete, exit 0.
The full suite was executed once after the accepted focused GREEN run.

The scripts print version, counts and assert success. Matching `*-status.txt`
files record the observed process exit code. Baseline-suite files are preserved
unchanged; their SHA-256 values are recorded in `evidence-index.json`.

## Focused tests and TDD

`targeted-green-accepted.log`: **30/30 passed**, 0 failed/incomplete, exit 0.
`targeted-green-final.log`: **28/28 then 32/32 regression passed**, exit 0,
followed by the fresh physical equivalence comparison. The two later focused
regressions cover sparse/complex storage identities and scheduling at H.

RED logs retain the expected missing-module/field failures, unsupported new
emission records, model-resume collision, canonical-field-order collision,
closure-input collision, schema downgrade and ignored supplied scenario.
`targeted-storage-horizon-red.log` shows 28 passed and exactly those two final
regressions failed before correction. The two initial `targeted-red*` harness
failures are preserved as failed launches and are not TDD acceptance evidence;
`targeted-red-confirmed.log` is the first valid RED run.

## Physical comparison

Clean baseline was extracted with:

```powershell
git archive --format=zip --output=.superpowers/sdd/stage1-v2.zip 2eb4848bb1acc0a1fd17797907b0a84a291c02f7
Expand-Archive -LiteralPath .superpowers/sdd/stage1-v2.zip -DestinationPath .superpowers/sdd/stage1-v2
$env:STAGE1_SOURCE_ROOT = (Resolve-Path .superpowers/sdd/stage1-v2).Path
$env:STAGE1_LABEL = 'baseline'
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1Physical.m')" -logfile verification/completion/stage-1/baseline-physical.log
Remove-Item Env:STAGE1_SOURCE_ROOT, Env:STAGE1_LABEL
```

Candidate and comparison command (also included after the 32 regressions in
`targeted-green-final.log`):

```powershell
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1Physical.m'); run('verification/completion/stage-1/stage1Compare.m')" -logfile verification/completion/stage-1/candidate-physical-equivalence.log
```

Single deterministic diagnostic UE, 1200 ticks: one 200-byte packet delivered,
1600 useful bits, 8 CRC-successful TBs. Candidate: 8 HARQ blocks accepted,
first emission BLER 0, no retries/censoring. This diagnostic threshold is not a
system calibration or a statistical KPI acceptance experiment.

All old result fields match exactly after projecting away added fields/KPI
columns and wall-clock `profiling.elapsedSeconds`. This includes packet/RA/
observed/truth/PHY journals, scenario/randomness, environment, resource usage,
dataset, the 35 pre-existing summary fields and all six CSV column prefixes.
Both global RNG snapshots match. The saved physical MAT files and export CSVs
allow independent readback; neither the release nor the original checkout was
edited. Existing physical-loss tests cover recovery, exhaustive failures,
multiple fragments/packets and CRC completion at the horizon.

## Review and scope

Independent read-only review found and corrected first receiver versus first
actual emission, closure state hashing, ignored supplied scenarios, marker
downgrade, and sparse numeric identity issues. NPRACH occupancy is explicitly
the union of transmitted 45 kHz allocation envelopes, with its denominator and
definition exported. It is not instantaneous hopping-tone occupancy.

No large statistical series ran. Controller counters remain explicitly
not-applicable. External runner dependency declarations are caller-owned;
unregistered runners/hooks/captured values and unreadable dependencies fail
closed. Legacy manifested packages remain verifiable, but cannot satisfy a
new runtime identity for resume.

During final focused work, a second small test process briefly overlapped the
previous session's completion because the initial process check only printed
PIDs. The prior run completed successfully. Subsequent launches use a hard
guard and the full suite was launched once. Wall-clock elapsed time is excluded
from the scientific equivalence claim.
