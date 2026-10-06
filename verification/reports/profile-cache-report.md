# Immutable PHY profile cache

O5 profiling measured15.17million ProfileTables.profile calls and270.29s self-time in the100UEprofile. Following completion/rejection of the separate GPU prototype, a small CPU-only constant-struct cache was evaluated sequentially.

Only five immutable profile values are cached. Case normalization, all13aliases, field order/types, Msg3 overrides, errors and MATLAB value/copy-on-write semantics are preserved. Nogrant/calendar/channel/RNG/state is cached. Protected old source:ProfileTables-before-cache.m.

Pre/post tests3/3 each. Realtimeit benchmark20000calls rotating five canonical profiles:0.258312761→0.056204539s,4.595941× for this function only. Complete post-patch suite112/112passed,0failed/incomplete. New full1UE5000tick run:14.193170s;17result fields exact versus the pre-patch radio-final-single, config exact after outputFolder normalization, all6CSV SHA exact. Both delivered1packet/1600bits. A single elapsed time does not establish a general system speedup.

The fresh100/1000/5000load pilot is running with source SHA d67fc6cac7ac9f27852177b4a1baee2c70f98b3bfe5de2fa3507397d93d2ff46. Radio receiver/validator dependency files are unchanged. No new calibration is required for this exact immutable-value change.

Evidence:profile-cache-before-verified.txt/.mat,profile-cache-system.txt/.mat,full-suite-profile-cache.mat; final-load-pilot/identity.json.
