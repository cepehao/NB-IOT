# Foundation static review

Reviewed 2026-10-04: `src/+nbiot/+config`, `+randomness`, `+scenario`,
`+traffic`, and `configs`, against `docs/model-profile.md`,
`docs/offline-contracts.md`, and `docs/foundation-report.md`.

MATLAB was unavailable. This is source inspection only; no syntax acceptance,
test pass, statistical acceptance, or LTE Toolbox compatibility is claimed.

## Findings

No actionable P0/P1/P2 defect was established in the completed foundation
modules. No code changes are requested by this review.

## Checks supporting that assessment

- `RandomSources.m:13-15` intentionally constructs a fresh stream for each
  request, as the offline contract specifies. Callers in scenario and traffic
  retain that stream for successive draws. `substreamKey.m:4-7` bounds all
  components before calculating the key. The largest supported key is
  `24*2^40`, below the exact integer limit of double; the mixed radix mapping
  does not collide within its declared component ranges.
- `generateArrivals.m:15` rounds continuous arrival times upward and excludes
  resulting ticks at or beyond the horizon. Periodic and Poisson generation do
  not force an arrival at zero. Traffic and payload sources have distinct keys;
  the standalone payload generator uses receiver zero while generated UE
  payloads use positive UE identifiers.
- `segmentPacket.m` and `reassemblePacket.m` agree on the 48-bit header,
  zero-based fragment index, 208-bit payload capacity, and final padding.
  The default 1600-bit packet therefore has seven 208-bit payload fragments
  and one 144-bit fragment.
- `PacketStore.m:29` retains overflow packets as dropped records without
  putting them in the queue. `PacketStore.m:52-69` separates local queue release
  from delivery and preserves delivered status across a later local timeout.
  `PacketStore.m:75-90` validates header and padding, reassembles decoded
  fragments, and counts delivery once. It does not compare decoded payload
  contents with the transmitted payload. CRC gating remains the caller's
  responsibility, as explicitly documented in the foundation report.
- `validateConfig.m:31-32` rejects changes to unsupported PHY tables and the
  fixed HARQ sequence. This is consistent with static-v1, rather than evidence
  of an inability to author meaningful foundation tests: UE count, traffic,
  queue size, horizon, lifetime, geometry, slow losses, CFO, synchronization,
  tap delays/powers, thresholds, and noise parameters remain configurable.

## Remaining review boundary

These modules expose scenario truth and packet truth for simulation bookkeeping.
Whether receiver and UE call sites improperly use that information requires
review of the channel, PHY, and protocol integration. Foundation inspection
alone cannot establish truth isolation across those components. Likewise, this
review does not establish that RandStream accepts every documented boundary key
at runtime; that acceptance remains a MATLAB execution check.
