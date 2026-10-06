# Physical40dBData failure: reproduced and isolated

Four real5000-tick two-UE waveform cases completed. Same/different first NInit, nominal path loss difference0/40dB, Rayleigh3tap/CFO/sync retained, deterministic distance-only geometry, burst0..1ms. Independent external IDs3346(same) and3300(different); these four are diagnostic controls, not a statistical capture curve.

Same-NInit equal nominal loss: UE2's Msg3 token and corresponding Msg4 win the first occasion; UE1 succeeds on a later attempt. At40dB UE1 wins first. Different NInit: both first Msg3/Msg4 succeed at0and40dB. At40dB UE1 is delivered; UE2 drops after actual Data CRC failures. Final per-case delivered counts:2,2,2,1. No unknown decoded first Msg3 tokens and no CRC-passed protocol-header failures.

Initial analyzer erroneously searched only post-step MSG4_PENDING; a step can also schedule Msg4 immediately and end in MSG4_ACK. The corrected analyzer uses the public decoded token after MSG3_RX and asserts every first Msg4 success has the corresponding first accepted Msg3. Both raw analysis logs remain; current analysis.mat/cases.csv are corrected.

## Public HARQ trace and RX replay

At different-NInit40dB, UE2 Data fragment3 remains NDI1 and uses RV0/2/0/2. Public grants start362/426/491/555ticks, end394/458/523/587, frequencies0/0/90000/45000Hz. All four decodes fail CRC; packet later reports progress_timeout. This is not a skipped fragment/NDI toggle or false protocol-header acceptance.

The first failure has an actual matching UE2 Data transmission. Selected received samples were captured after real reception, with public grant/previous soft buffer only; truth remains separate. Replay reproduces CRC failure and estimates delay−26samples versus offline true post-TA residual1.1748, CFO11.635Hz versus true34.119Hz.

Offline channel isolation, using truth only to generate explicit diagnostic TX/channel inputs:

|Input to unchanged production receiver|CRC|Exact actual payload|Timing/CFO|
|---|---|---|---|
|Full received signal+noise|fail|no|−26samples/11.635Hz|
|Full received signal, noise removed|fail|no|−26samples/11.753Hz|
|Desired UE signal+same noise|pass|yes|3samples/34.092Hz|
|Desired UE signal, noise removed|pass|yes|4samples/34.121Hz|
|Desired signal, flat channel, no noise|pass|yes|3samples/34.120Hz|

The0dB case has the same qualitative isolation: full signal fails with53sample timing estimate; desired-only signal decodes exactly with0samples and CFO−23.65Hz (true−23.64Hz). Other channel transmissions therefore perturb the existing first-slot DM-RS timing estimate in these windows. The saved experiment identifies a physical multiuser-interference failure of this receiver, not a logical HARQ grant bug. It does not prove every40dBtimeout has this cause or that every other-user component was separately identified.

Both selected capture bundles passed actual byte budget, marker hashes and replay; total1,920,145bytes, under2MiB. First-versus-all Data CRC denominators are derived from public pre-decode HARQ state and matched to actual BS phy_decode events, never guessed from true payload.

Evidence:capture-smoke/analysis.mat,cases.csv,failures.csv,failure-diagnosis.mat,ul-isolation.mat/.csv; receiver.mat and truth.mat in each selected private capture folder; capture-smoke-analysis-corrected.txt,capture-smoke-failure-diagnosis.txt,capture-smoke-ul-isolation.txt.
