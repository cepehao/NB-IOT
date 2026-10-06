# R2: UCI alias and stale receive events

MATLAB R2025b reproduced the known physical alias: default ACK bit 1/RNTI 100 and foreign NACK bit 0/RNTI 2103 at tick 40 yield identical 7680-sample waveforms, max absolute difference 0. Both decode as ACK under the RNTI-100 grant with both coherences equal to 1. No CRC is present. The PHY adapter still delegates Control coding, scrambling, DRS and modulation to the actual LTE Toolbox APIs; no truth-based decision or invented identifier was introduced.

Evidence: `o5-radio-characterization/uci-alias/uci-alias.mat` and `.json`; deterministic regression `TestUciAlias.knownNoiselessAliasHasIdenticalWaveform`. The remaining valid-resource ambiguity is documented in the candidate's `docs/uci-ambiguity.md`. It cannot be eliminated by a threshold, and the patch does not claim to do so.

Two independent logical violations were reproduced in a real simulator event queue: an obsolete Msg4 ACK completion changed a context after its state had changed, and after its current ACK grant had been superseded. Before the fix, the four new tests gave 2 expected failures/2 passes; see `r2-context-red.txt/.mat`.

`receiveAtBs` now requires the expected BS state and exact current public grant before RF decoding. The same guard covers Msg3, Data, Msg4 ACK and receipt ACK; terminal states already reject completions. The decision uses only public BS state/schedule. Context IDs/RNTIs are not recycled in a simulation.

After the fix: complete suite **75/75**, 0 failed/incomplete (`r2-context-green.txt/.mat`). A new real single-UE run exactly matches the protected separate-process baseline in **26/26** checks, including all event/payload/KPI/dataset comparisons and all six CSV hashes (`r2-equivalence.json/.mat`, `r2-context-equivalence.txt`). Candidate source snapshot for that run: `500138cd27921f2ad0f0222bd172b699e23ec0ae39e653f08e687c8a21ee825b`; documentation added later is outside that run snapshot.

Original source/documentation audit: **103 files, 0 differences** (`r2-original-integrity.json`). All source changes remain in the candidate. Broader physical ACK/noise/foreign-signal and end-to-end loss evidence must be mapped before final scientific acceptance; this report closes the reproduced context bug and preserves the alias limitation explicitly.

## Свежий конечный UCI holdout

После исправления завершены20000испытаний за723.7s на2process workers. Noise/ForeignACK/ForeignNACK каждый0falseACK/6000и0falsePresence; точная двухсторонняя95%upper0.000614624 соответствует конечному gate PFA≤0.001. OwnACK/OwnNACK каждый1000/1000correct-present (upper95failure0.003682084). Независимые realization3800/keyed substreams, random foreignRNTI1..65535 except100, Rayleigh3tap/CFO±200Hz, conditional receive20dB, residualpost-TA±4.34samples. Это не покрывает любой NPRACH timing error и не устраняет exactalias. CFO RMSE0.240..0.260Hz, timing RMSE0.661..0.829samples. Данные:uci-fading-holdout/report.mat,summary.csv,raw per-condition arrays. Physical ACK/receipt loss passed TestRadioProtocol12/12; текущий полный suite112/112passed. Предыдущее утверждение о необходимости broader noise/fading mapping закрыто этим конечным holdout; полная научная серия остаётся отдельным пунктом.
