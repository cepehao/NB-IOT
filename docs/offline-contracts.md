# Контракты реализации без локального MATLAB

## Текущее выполнение (2026-10-06)

Ниже сохранены исторические offline-контракты. На этом ПК MATLAB R2025b и LTE Toolbox реально выполняются; текущие доказательства в [performance-report.md](performance-report.md).

Новые явные интерфейсы:

- saveResult(result,folder,metadata): UUID case/staging, MAT+6 CSV, SHA/schema/readback и последний case-complete.json. Legacy двухаргументный export сохранён.
- verifyCase(caseFolder,expected): проверяет целостность и version/config/calibration metadata перед resume.
- runStaticSweepParallel(options): явно включённые отдельные process workers, private cases и coordinator-only manifest; sequential runStaticSweep доступен независимо.
- calibrateNprach(cfg,path,options): можно задать fitRealizationId/validationRealizationIds; повтор тех же ID является reproduction, а не новой независимой выборкой.
- captureFailure(sim,options): logging.saveWaveforms=true разрешает явный выбранный RX capture; start/end sample, direction/receiver, byteBudget, outputFolder обязательны. Retention128ticks, hard фактический размер, receiver/truth раздельно, marker-last.
- plotSweepSummary(manifestOrCsv,outputFolder): verified completed independent runs, counts и Student-t CI; audit всех неполных/невалидных rows, finite samples отдельно, смешанные source/calibration и duplicate realization отвергаются.

## Исторические контракты

Авторизация: пользователь 2026-10-04 поручил написать основные исходники для последующего переноса на ПК с MATLAB. Локальные выполнения MATLAB, лицензия и численные результаты не подтверждаются. Исходный профиль — model-profile.md, последовательность — implementation-plan.md.

Время: tick — целое число миллисекунд с нуля; интервал [startTick,endTick). Отсчёты с нуля; Fs=1920000, 1920 samples/tick. MATLAB-индексы массивов с единицы. Биты int8, комплексные отсчёты double, мощность W.

Общий Config: simulation (durationTicks,tickSeconds,sampleRateHz,numUE,seed,realizationId); cell (radiusM,minDistanceM,bsHeightM,ueHeightM,indoorFraction,cellId); channel (carrierHz,referenceDistanceM,pathLossExponent,shadowOutdoorDb,shadowIndoorDb,penetrationIndoorDb,uePowerDbm,bsPowerDbm,bsNoiseFigureDb,ueNoiseFigureDb,temperatureK,cfoSigmaHz,cfoLimitHz,syncLimitSeconds,tapDelaysSeconds,tapPowersDb,fractionalFilterLength); traffic (kind,packetBytes,queueLimit,periodTicks,poissonRatePerSecond,burstStartTick,burstDurationTicks,lifetimeTicks); ra (maxAttempts,backoffTicks,periodTicks,startOffsetTicks,numSubcarriers,format,repetitions,rarPp,contentionPp); phy (processingTicks,cellId,sampleRateHz,msg3,data,ack,downlink,npdcch,maxHarqTransmissions,rvSequence,decoderIterations,progressTimeoutTicks,receiptTimeoutTicks,maxReceiptTransmissions,nprachThreshold,nprachCfoGridHz); policy (name,accessProbability,raShare,windowTicks); dataset (windowTicks); logging (saveWaveforms,outputFolder).

RandomSources(masterSeed,realizationId).stream(sourceName,direction,receiverId,blockId) returns a reset keyed stream; .manifest(). Direction numeric 0 UL/1 DL. Source and key mapping in profile; keys may be named UL/DL by caller only after explicit conversion.

Scenario: ue struct array with ueId,xM,yM,indoor,distanceM,pathLossDb,cfoHz,syncOffsetSeconds,tapsUl,tapsDl; arrivals struct array packetId,ueId,createdTick,sequence,payloadBits. Scenario also randomManifest,externalRealizationId.

PacketStore(cfg): enqueue(arrival)->accepted; head(ueId)->packetId (0 if empty); get(packetId)->packet struct; queueLength(ueId); localFinish(packetId,tick,confirmed); markTerminal(packetId,status,reason,tick); markReceived(packetId,fragmentIndex,bits,tick)->newlyDelivered; finalize(tick)->struct array. Packet fields include blocks cell, map.validPayloadBits, received cell, status, reason, createdTick,deliveredTick,terminalTick,attemptCount,ueConfirmed. markReceived accepts the entire decoded 256-bit TB and validates its header, sequencing and length. delivered status is irreversible. localFinish frees local queue separately. Queued/current packets are unfinished at horizon; queue overflow counts as dropped.

Grant: grantId,kind,phase,direction,startTick,endTick,ticks (explicit physical subframe list for DL),frequencyStartHz,bandwidthHz,rnti,ndi,rv,profile. UE reconstructs a grant from decoded DCI/RAR and public profile/timing tables, never from a BS grant object.

Transmission: grantId,direction,waveform,sampleRateHz,startSample,activeRanges,txPowerDbm,ueId (channel-side only),kind. full 180 kHz at Fs. RxWindow: waveform,sampleRateHz,startSample; no truth.

RadioChannel(cfg,scenario,sources): add(tx); receive(direction,receiverId,startSample,endSample)->RxWindow; discardBefore(sample). receiverId=0 BS UL, ueId UE DL. Independent per-tick noise keyed by absolute tick. Individual loss,CFO,delay,fading, fractional FIR; noise once per receiver. Transmissions retain their true UE privately to channel. Timing advance tx.timingAdvanceSeconds optionally subtracts UL delay.

ResourceCalendar(cfg): reserveTransaction(plans)->ok; plans struct array direction,phase,ticks,frequencyStartHz,bandwidthHz,grantId. releaseUnstarted(grantIds,now); canReserve(plans); usage()->table; isFree(plan). Mandatory DL mask excluded from budgets. Overlapping UL tx of colliding UE are one scheduled resource reservation. NPRACH entire occasion is reserved ahead under RA. UL .5 ms x 3.75 kHz, DL whole 1 ms x 180 kHz, separate per-window quotas, no borrowing.

Scheduler(cfg,calendar): reserveNprach(); downlink(kind,phase,earliestTick,deadlineTick,rnti)->schedule struct or empty; uplink(kind,phase,earliestTick,deadlineTick,rnti,ndi,rv)->schedule struct or empty. Schedule: controlGrant,payloadGrant,ackGrant (empty where not applicable),dci struct. Reserve all dependent resources atomically. downlink handles NPDCCH N1 + NPDSCH + ACK; uplink handles NPDCCH N0 + NPUSCH. Msg3 resources are allocated as part of RAR transaction, not a separate N0. RAR's schedule.msg3Grant holds the reserved Msg3 resource and its real assignment/delay fields are encoded in RAR. No ACK for RAR. N0 delays chosen from 8/16/32/64; NPDCCH monitoring Rmax4,G8,offset0, two reps. Export detailed usage, never guess capture.

PHY: ProfileTables static methods msg3Profile(rarIndex),ulTbs(mcs,iru,nsc),dlTbs(mcs,isf),n0Delay(index),n1Delay(index,rmax),profile(kind),nprachDurationTicks(),encode/decode resource mappings.

nbiot.phy.nprach.buildTransmission(cfg,occasion,nInit) with occasion.startTick true active preamble start, occasionId; detect(cfg,rxWindow,occasion)->array nInit,metric,delaySeconds,cfoHz,threshold,readyTick (no UE labels).
nbiot.phy.npusch.buildTransmission(cfg,grant,payloadBits,encoderState)->tx,state; receive(cfg,rxWindow,knownGrant,harqState)->decode,state. decode.decodedBits,hasCrc,crcError,status,measurements; CRC==0 success. UCI hasCrc=false and ACK must be obtained from decoder. Real pilots/channel estimation, never channel tap truth.
nbiot.phy.npdcch.buildTransmission(cfg,grant,dci)->tx; receive(cfg,rxWindow,monitoringGrant)->decode struct with dci and crcError; monitoringGrant includes only search-space ticks, format and candidate RNTI. packDci/unpackDci real TS36.212 bit layout.
nbiot.phy.npdsch.buildTransmission(cfg,grant,bits,state)->tx,state; receive(cfg,rxWindow,knownGrant,state)->decode,state. Standard LTE Toolbox CRC/NDLSCH, NB-IoT half-subcarrier-shift modulation using lteSCFDMAModulate/Demodulate and NRS equalization. knownGrant reconstructed at UE from decoded DCI. No synthetic success fallback.

Protocol codecs encodeMessage/decodeMessage(kind,bits) real RAR/Msg3/Msg4, custom final receipt explicitly versioned. All receive events run before deadline expiration at same tick; processing latency applied after physical end; invalid/old attempt events ignored. Packet IDs and UE IDs never sent as scheduler metadata through a hidden interface.

Ruling: unavailable MATLAB defers execution and numerical acceptance, but does not block writing source, scripts and meaningful tests. No Git repository exists; source stays in the explicitly authorized project directory. No fake BLER, receiver success or performance results will be produced.
