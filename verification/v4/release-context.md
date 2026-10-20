# V4 release context — 20 October 2026

Owner authorized a new GitHub release of the current functionality, updated README and simplest possible installation/startup. Owner selected Windows with installed MATLAB R2025b and LTE Toolbox. Version: v4.0.0, branch: v4. Preserve main/v2/v3 and previous releases.

Accepted source: local completion digest 5d1de302ade85cfbdeb3e89c5625b648748fc95a424f7fe63f0bda785467a3b1. Source copied into this isolated worktree; original dirty workspace stays unchanged. V3 saved 1/100 UE reports are preserved as historical demonstrations, with their original checksums and dates.

Scope: add double-click Windows launcher, automatic component checks, self-contained public commands, current short README/install/status/release notes, reproducible ZIP and checksums. No new physics, training, load series, Stage 2, R4.12, scientific admission or external messaging. All scientific readiness flags remain false. Never touch AmneziaVPN or security/network configuration.

Checks: launcher discovery and paths; explicit bounded MATLAB tests (10 UE maximum, 300 seconds per selection, 900 seconds per set), one worker at a time; test hidden windows only. Test extracted ZIP in a path with spaces, without original checkout on the MATLAB path. Compare source/calibration and saved-report identities. Independent read-only code/package review before publishing. Preserve evidence outside the final input tree when it would create a checksum cycle.

Next: write release acceptance tests first, then launcher/docs; run bounded checks, freeze manifest, independent review, build/unpack/test, commit/tag/push v4 and publish release assets. Set v4 as default branch so the GitHub landing page shows the current instructions. Do not rewrite older refs/assets.

Runtime correction: the real public demo smoke exposed reentrant updates of the same live diagnostics accumulator. RED: checks-release-green/test-1 failed MATLAB:sizeDimensionsMustMatch. A temporary diagnostic run confirmed nested updateDepth=2 at ticks 39/79; temporary instrumentation was then removed by restoring the accepted accumulator bytes. NBIoTSimulator.liveRadioDiagnostics now guards the complete read/update/cursor transaction and returns its last coherent presentation-only cache on reentry. No scientific algorithm, RNG, export schema or checkpoint state is changed. This is a new source identity requiring independent review; the original 19.10 digest is only historical baseline.
