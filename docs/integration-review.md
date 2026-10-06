# Static integration review — 2026-10-04

Scope: `offline-contracts.md`, `model-profile.md`, simulator orchestration, device/RA/packet state, scheduler reconstruction, datasets, metrics/results, and experiment/example entry points. This is source inspection only. MATLAB, numerical receiver performance, and runtime acceptance were not exercised. PHY algorithm internals were reviewed separately.

Follow-up disposition: all four findings below are resolved in the current source by static inspection. The event-queue rename was also inspected for consistent references. No remaining blocker was identified in this scoped follow-up; this is not runtime verification.

## Findings

### 1. Msg4 ACK loss made retransmission miss its own deadline — high

Evidence: `src/+nbiot/NBIoTSimulator.m`, `receiveAtBs`, originally lines 426–428, applied `receiptTimeoutTicks=512` to both Msg4 and receipt ACK failures. `advanceTimers`, originally lines 465–467, retained the original contention deadline for Msg4. `schedulePending` expires a pending context after that deadline. The pp16 contention window is approximately sixteen 32 ms search spaces from Msg3; waiting another 512 ms after the first Msg4 ACK reception therefore puts the retry beyond that window. A UE that received Msg4 already considers RA successful, but the BS cannot advance to data after the lost ACK.

Fix: make Msg4 eligible for another transaction as soon as ACK failure is observed, within the existing contention deadline. Apply the model's 512 ms retry interval only to final receipt. Parent applied this correction during review; the current Msg4 ACK failure branch explicitly restores `MSG4_PENDING`.

Resolved in source: `src/+nbiot/NBIoTSimulator.m:437` sets `MSG4_PENDING` and `pending=true`. The retransmission limit still applies first; the existing deadline is retained, and the 512 ms wait is confined to the receipt branch.

### 2. DL reservations could be accepted despite missing the UE deadline — high

Evidence: `src/+nbiot/+scheduler/Scheduler.m:55` originally compared only `payload.endTick` with `deadlineTick`. `NBIoTSimulator.receiveControl` queues payload reception at `endTick + processingTicks + 1`, while UE timers expire at their stored deadline. A payload whose physical end is at the deadline was thus reserved and sent but could never be accepted by the waiting UE.

Fix: require `payload.endTick + cfg.phy.processingTicks + 1 <= deadlineTick` before reserving the transaction. Parent applied this correction during review; line 55 now includes that latency. The extra tick is the current receiver-window guard convention; this review does not independently validate that PHY convention.

### 3. Public step/stop operations could return a stale result — medium

Evidence: `src/+nbiot/NBIoTSimulator.m:128` returns `resultCache` immediately, while the initial implementation invalidated it only at the end of `run()`. Therefore `result(); step(); result()` retained old time, logs and metrics, and `result(); stop(); result()` retained the previous status and reason.

Fix: invalidate the cache whenever `step()` or `stop()` changes exported state. Resolved in current source at `src/+nbiot/NBIoTSimulator.m:79` and line 125. The step guard returns before invalidation only when it also performs no state change.

### 4. Lifetime expiration leaves an active RA attempt incorrectly censored — medium

Evidence: the original `src/+nbiot/NBIoTSimulator.m:85–88` expired packets and reset their devices without closing a currently started attempt. `result()` converts every remaining `started` attempt to `unfinished`. `src/+nbiot/+metrics/summarizeKpi.m:11–15` consequently counted that attempt as unfinished and excluded it from the completed-attempt denominator, even if the packet lifetime expired well before the simulation horizon. Supported configurations with `traffic.lifetimeTicks` shorter than the RAR/contention wait expose this; the default 10000 ms lifetime hides it in a 5000 ms run.

Fix: before resetting a device whose packet expired, terminate its active `started` attempt at the current tick, using `failure` or an explicit expired terminal state included in completed-attempt accounting. Resolved in `src/+nbiot/NBIoTSimulator.m:89–91`: the guard checks a positive attempt ID and `started` status, then assigns `failure` and `endTick=now` before device reset. Already successful/failed attempts retain their outcome, and BS contexts are not modified by this local expiration.

## Event queue identifier follow-up

`src/+nbiot/+engine/EventQueue.m:4` uses `entries` for storage and line 13 uses `ready` for the returned batch. `src/+nbiot/NBIoTSimulator.m:22` uses `receiveQueue`; construction, event pushes, ready-event reads, and snapshot counts consistently use that name. No old `obj.events` reference remains in those files. Stable ordering by tick then sequence is retained. This confirms the source rename; MATLAB parser execution was not performed by this reviewer.

## Other integration observations

- UE grant reconstruction uses decoded DCI/RAR plus public timing/profile tables through `reconstructUplink`, `reconstructDownlink`, `reconstructMsg3`, and `reconstructAck`. The reviewed receive path does not copy a BS payload grant into UE state.
- The scheduler's RA contexts contain decoded token/sequence, measured preamble delay, protocol state, and public resource information. No direct true-collision or true-channel field was found driving scheduling.
- `analyzeDelivery` maps decoded fragments into ground-truth packet accounting after the BS validates the wire header; its return value does not decide BS scheduling progress.
- BS dataset observations have an event whitelist and explicitly reject UE decoder outcomes. True arrivals, collision labels, device backlog, and packet delivery are used in truth/target accounting, not observation construction.
- Receive events are processed before timers at the same tick; the horizon tick processes ready receptions. Partial `result()` copies packet/attempt statuses without finalizing resumable state.
- The calibration version-field mismatch was already known and handled separately by the parent. No additional entry-point field mismatch was confirmed in this review.

Before claiming runtime correctness, the target MATLAB environment still needs execution of the actual receiver/protocol paths, including lost Msg4 ACK, completion exactly at a deadline, lifetime expiration during RA, and result export between public steps. This review makes no numerical acceptance claim.
