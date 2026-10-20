# NB-IoT v4

Release checkout: branch v4, tag v4.0.0. Start with README.md, docs/v4-install.md and docs/v4-status.md. Preserve previous branches/tags/assets and original saved-report bytes.

MATLAB R2025b and LTE Toolbox are required; keep startup self-contained. No network/security/VPN settings are changed. Never stop, restart, reconnect or reconfigure AmneziaVPN, its processes/services/adapter/protection/routes.

Ordinary verification is bounded: at most 10 UE, 300 seconds per test file/case, 900 seconds per selected set through verification/local/runBoundedChecks.ps1. Run explicit selections, one batch worker at a time. Use -NoFigureWindows for background checks; never bring applications to foreground without an agreed visual check.

No new large load series, Stage 2, real training/admission/comparisons or protected R4.12 inspection/resume is authorized by preparing this release. Development fixtures are not scientific evidence. Keep all full-TZ/scientific readiness flags false unless actual prerequisites are met. docs/current-state.md is retained engineering history; release-specific truth is verification/v4/validation.json and docs/v4-status.md.

The owner explicitly authorized publication of v4.0.0 with current features and simplest startup using installed MATLAB. Independent read-only review and extracted-archive checks precede publication. Do not overwrite or delete other users' settings or data.
