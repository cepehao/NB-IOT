# Foundation source implementation (offline)

Implemented configuration, keyed randomness, immutable scenario generation, traffic,
fragmentation/reassembly, and a packet store. No MATLAB execution was available;
the authored unit tests are pending execution in MATLAB R2025b. No numerical
acceptance or test pass is claimed.

## Interfaces

- `nbiot.config.defaultConfig()` / `validateConfig(cfg)` return the complete
  static-v1 configuration. Validation uses MATLAB core only and accepts a NaN
  NPRACH threshold to mean **calibration required**, not permission to detect.
- `RandomSources(seed,realizationId).stream(name,direction,receiverId,blockId)`
  constructs a fresh mrg32k3a stream for every key. Source codes and exact numeric
  formula are recorded in `manifest()`; directions must be numeric 0/1.
- `buildScenario(cfg,sources)` saves per-UE geometry, shared slow losses, CFO,
  synchronization, independent UL/DL static taps, and all arrivals and payloads.
  Arrivals are sorted by tick, UE and sequence; continuous times are retained.
- `generateArrivals` uses one traffic and one payload stream per UE; standalone
  `generatePayload(packetId,sizeBytes,sources)` uses a separate receiver-0 key.
- `segmentPacket` and `reassemblePacket` use MSB-first 48-bit headers and
  **zero-based fragment indices**. The default payload yields eight 256-bit TBs.
- `PacketStore` provides `enqueue`, `head`, `get`, `queueLength`,
  `incrementAttempt`, `expireLifetime`, `markReceived`, `markTerminal`, `localFinish`, `finalize`,
  and readable `packets`/`counters`. `markReceived` accepts full decoded TBs;
  callers must invoke it only after successful PHY CRC. It validates the wrapper,
  padding and duplicate consistency, never compares decoded payload to truth.
  Delivery is irreversible and local queue occupancy persists until localFinish.
  Finalization labels pending packets unfinished and preserves delivered packets
  still awaiting receipt. Every created packet, including overflow, is retained.

## Pending acceptance

Tests cover configuration rejection, stream replay and boundary keys, stable
traffic/horizon behavior, geometry, fragmentation, queue overflow, duplicate
reception, missing fragments and receipt loss. Core syntax/API compatibility,
RandStream behavior, statistical distributions and the complete integration
require MATLAB execution. Static validation rejects unsupported PHY profile
changes rather than inventing alternative table values. File destination
validation catches file paths but does not create folders or probe permissions.
