# Stage 1 scheduled receiver horizon follow-up

Base commit: `a197074df9ab8b2322455eaa05914e09d1bbd990` on
`codex/2026-10-06-project-completion`.
MATLAB: `D:\MATLAB\bin\matlab.exe`, `25.2.0.2998904 (R2025b)`, release `2025b`.

`queueBsUl` records a `scheduled` event at reservation time in `journal.tick`;
the physical receiver grant starts at `fields.startTick`. The summary now
requires both ticks to precede `H = actualTick`. The same validated selection
drives block and attempt counts. Scheduled start ticks must be finite real
numeric nonnegative integer scalars; invalid or missing values are rejected.

Regression evidence:

| Run | Total | Passed | Failed | Incomplete | Process exit |
| --- | ---: | ---: | ---: | ---: | ---: |
| `reservation-horizon-red.log` | 34 | 30 | 4 | 0 | 1 |
| `reservation-horizon-green.log` | 34 | 34 | 0 | 0 | 0 |
| `reservation-horizon-full-suite.log` | 147 | 147 | 0 | 0 | 0 |

The RED run used the base production source and the added tests. It failed
specifically on early reservations with actual starts at H and after H,
reserved retries starting at/after H, and invalid scheduled start ticks.
The strengthened existing boundary test passed even in RED: reservation at 8,
start at 9 and readiness at 11 with H=10 counts as started/pending/censored;
a separate decode completed at H remains included.

The full suite ran once after focused GREEN. Every launch used a fresh hard
process guard; all three `*-status.txt` files record `MATLAB_PID_COUNT=0`, the
launch timestamp and the observed process exit code. Runs used the authorized
outside-sandbox MATLAB path, as with the earlier Stage 1 verification.

Reproduce the focused GREEN and full suite from the checkout:

```powershell
$horizonActive = @(Get-Process -Name MATLAB -ErrorAction SilentlyContinue)
if ($horizonActive.Count -gt 0) { throw 'MATLAB already active' }
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1Targeted.m')" -logfile verification/completion/stage-1/reservation-horizon-green.log
$LASTEXITCODE

$horizonActive = @(Get-Process -Name MATLAB -ErrorAction SilentlyContinue)
if ($horizonActive.Count -gt 0) { throw 'MATLAB already active' }
& 'D:\MATLAB\bin\matlab.exe' -batch "run('verification/completion/stage-1/stage1FullSuite.m')" -logfile verification/completion/stage-1/reservation-horizon-full-suite.log
$LASTEXITCODE
```

`reservation-horizon-evidence.json` records counts, exact commands and SHA-256
identities of the final source, tests, contract, harnesses and evidence files.
