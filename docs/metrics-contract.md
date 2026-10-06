# Stage 1 metrics and runtime contract

This contract is written before production changes. It implements specification
§20, §27, §42 and §47 for the existing Static WAVEFORM model.

## KPI definitions

The horizon is `H = actualTick`, in ticks of `config.simulation.tickSeconds`.
Arrivals and starts occupy `[0,H)`; receiver completions at `H` are included.
Empty denominators produce NaN. Unfinished work is censored, never a loss.
Partial, stopped and failed run status remains part of every result.

| KPI | Numerator / denominator | Units / horizon |
| --- | --- | --- |
| Primary access success | RA attempts successfully completed / attempts started | probability; unfinished attempts remain in denominator |
| Primary user packet delivery | packets with all fragments received with CRC and valid decoded headers / created packets | probability; includes censored denominator |
| Primary useful throughput | unique delivered user payload bits / actual elapsed simulation seconds | bit/s; retransmissions and protocol overhead excluded |
| Collision probability | same-occasion same-preamble colliding RA attempts / RA attempts | analyzer collision label only, never a receiver decision |
| Mean RA attempts | total RA starts / created packets | attempts/packet, including zero-attempt and censored packets |
| Mean and p95 delay | delivered-packet completion minus arrival | ticks and seconds; delivered sample count retained; p95 interpolates sorted samples at rank 1+(n-1)*0.95 |
| Packet loss | dropped packets / created packets | probability; unfinished reported separately |
| Delivered fraction | delivered / created | same primary delivery numerator |
| Existing `dataBler` | failed Data CRC decodes / all Data CRC decodes | probability across ALL attempts, preserved |
| Existing `msg3Bler` | failed Msg3 CRC decodes / all Msg3 CRC decodes | probability across ALL attempts, preserved |
| First Data HARQ BLER | failed CRC on first actual UE emission / first emitted attempts decoded by H | probability per transport block; emitted receptions pending at H counted separately |
| First receiver HARQ BLER | failed CRC on first scheduled reception / first scheduled attempts decoded by H | probability; includes lost N0/noise reception, explicitly distinct from first emission |
| Post-HARQ outcome | accepted blocks / started blocks; exhausted/terminated blocks / started blocks | probability; censored blocks separate; retries are attempt ordinal > 1 |
| UL occupancy | union of actual allocation units / 48 frequency bins times two slots times H | fraction; overlapping UE counted once |
| DL occupancy | union of actual DL ticks excluding mandatory signals / available nonmandatory ticks | fraction |
| NPRACH occupancy | union of transmitted NPRACH allocation envelopes / 12 bins times two slots times H | full 45 kHz occasion envelope fraction; includes reserved hopping band rather than instantaneous active tone |
| Mean and maximum UE queue length | integral of actual UE queue length / UE-ticks; maximum queue at any sampled tick | packets/UE; includes head packet until local finish, including receipt waiting after BS delivery; excludes rejected arrivals |
| Mean and maximum BS pending requests | sum of observed pending request counts / sampled ticks; maximum | requests; observes BS state |
| Controller decisions / configuration switches | unavailable | explicit `applicable=false`, counts NaN, reason `controller-not-implemented` |

Existing CSV columns, order, values and window semantics are retained. New
window fields are appended. Arrival cohorts are classified at the export
horizon; completion intervals remain `(start,end]`.

## `harqSummary(journal, actualTick)`

Input is a separate append-only analyzer journal (schema 1), never receiver
truth. Records have `tick`, `kind`, `fields`. Fields identify `contextId`,
`packetSequence`, zero-based `blockIndex`, one-based `attempt`, plus start,
end and receiver-ready ticks for scheduled records. `decoded` records contain
real CRC and header acceptance; `emitted` records are appended immediately
after waveform insertion into the channel with event time at waveform start;
`terminal` records contain the resulting BS
state. No waveform/grant or RNG input is changed.

For `scheduled` records, `tick` is the reservation time and `fields.startTick`
is the grant's actual receiver start. `startTick` must be a finite real numeric
scalar, a nonnegative integer. A reservation counts as a started receiver
attempt only when both its journal tick and actual start are strictly before H.
Reservations for starts at or after H contribute no started/pending attempt or
started/censored block, even when reserved before H.

Identity is `(contextId, packetSequence, blockIndex)`. RaContextStore allocates
monotone IDs without reuse, Msg3 fixes sequence/token once, and a context
handles a single packet. Fragment changes follow decoded valid headers;
HARQ ordinal changes only on failure. Sequence alone can wrap, so is not a
global key. Actual emissions map to the unique current public context and
grant; unmatched emissions are explicitly counted. No global truth packet ID
is used as KPI identity. Scheduled receiver attempts are counted even when the UE misses
N0: the receiver still performs a real CRC decode, but that attempt is excluded
from the first actual transmission denominator. A successful CRC with an
invalid protocol header is a CRC success but an unaccepted block.

Algorithm: select events through H; group by explicit identity; count scheduled
attempts and real decoded CRCs; evaluate first actual emitted ordinal and first
receiver ordinal separately; derive
accepted/failed/censored blocks from explicit BS transitions. A first decode
at H counts; a receiver starting before H with a receiver-ready tick after H
remains pending and its unfinished block is censored. Legacy results
without this journal have `available=false`; no RNTI/time inference is used.
Tests: first success, recovered retry, exhausted retries, multiple blocks and
packets, CRC success but invalid header, pending retry, exact-H completion,
post-H exclusion, early reservation for starts at/after H (including retries),
legacy unavailable and malformed identity/start-tick rejection.

## `runtimeManifest(cfg, options)`

Options register project root, calibration file, model files, policy files,
external input files, supplied scenario and optional runner with its source
files. An external runner requires `runnerDependenciesDeclared=true` and its
defining file in `runnerFiles`. Captured workspace values require complete
`runnerInputs` registration matching the handle workspace and are hashed;
self-references to the same handle are ignored, other dynamic handles rejected.
This declaration is a caller assertion that
all result-affecting files/inputs are listed; undeclared dependencies fail
closed. Missing files, anonymous/dynamic runners, or unregistered runner source
are errors. Unknown external hooks and unsnapshotable object/function inputs
are rejected. Static production runner is registered by default; a supplied
scenario is passed to it, as well as hashed.

Algorithm: recursively canonicalize struct field order and encode numeric
class, shape, sparse/full and real/complex storage, and exact real/imaginary bytes (including complex channel taps);
hash UTF-8 canonical JSON and file bytes with SHA-256. Code hash covers production `src`, selected
experiment entry points and setup, excluding tests/docs/results. Runtime,
result schema, calibration, model, policy, runner and input identities are
separate. Code changes invalidate resume; README changes do not. Policy hash
includes configuration policy and registered policy files. Model/input hashes
include contents of registered external files. Case key hashes method,
canonical configuration including P and RA/DT share, traffic/scenario,
external realization, calibration and registered model/policy/runner/input
identities; output folder is excluded. Configuration snapshots keep the
original legacy hash for reading schema-1 bundles.

New results use result schema 2 and marker schema 2, runtime identity schema 1.
Marker/MAT identity must agree; unsupported versions and malformed/damaged
metadata/files return rejected reports. Schema-1 manifested bundles remain
verifiable and legacy save/load exports remain readable. They cannot satisfy
a schema-2 runtime resume expectation. The MATLAB/LTE environment is retained.

Tests: canonical order/output relocation, P/RA-share/method/traffic/realization
separation, README stability, source changes, calibration replacement, external
model/policy/input mutations, registered runner source mutation, unregistered
runner rejection, new calculate/verify/resume lifecycle, incompatible and
damaged marker rejection, legacy readability and no reuse as a new identity.
