# Детальный план реализации симулятора NB-IoT

> План первоначально подготовлен для этапа проектирования. 2026-10-04 пользователь разрешил написать основные исходники без локального MATLAB для последующего переноса на другой ПК. Текущее состояние исходников и невыполненных проверок отражено в [implementation-status.md](implementation-status.md). Контрольные точки этого плана остаются требованиями к проверке в MATLAB.

**Цель:** ядро NB-IoT в MATLAB R2025b с LTE Toolbox, физической цепочкой RA/DT, постоянной политикой Static, воспроизводимыми KPI и датасетом.

**Архитектура:** `NBIoTSimulator` управляет временем и модулями `+nbiot`. Общий waveform поступает физическим приёмникам; UE и BS реагируют на сообщения и таймеры. Ground truth передаётся отдельно анализатору.

**Технологии:** MATLAB R2025b, LTE Toolbox, MATLAB Unit Test Framework. Последовательная версия не требует дополнительных Toolbox. Parallel Computing Toolbox — последующая необязательная оптимизация.

**Спецификации:** [архитектура](architecture.md), [профиль static-v1](model-profile.md), [ТЗ](../ТЗ_NB-IoT_обновленный.pdf).

**Статус:** основные исходники написаны без запуска MATLAB; совместимость среды и численные результаты ещё не проверены. Создание файлов не означает прохождение контрольных точек.

## Общие ограничения

- Одна WAVEFORM-модель; вероятности не заменяют детекцию и декодирование.
- Базовые значения: 5 s, 1 ms, 1000 UE, 200 bytes, очередь 10, максимум 8 фактических Msg1, seed 42.
- FDD, Standalone, Cat-NB1, Release 13; частота расчёта потерь 900 MHz; UL/DL по 180 kHz.
- NPRACH format 0, 12 индексов, 80 ms, start 8 ms, один повтор.
- NPUSCH: 15 kHz, три тона, QPSK; Msg3 88 bits/8 ms, Data 256 bits/32 ms, NRep 2.
- Один HARQ-процесс UE; четыре Data bundle с начальными RV 0/2/0/2, один Msg3 bundle на попытку RA. RV физических повторений внутри bundle определяется по §16.5.1.2 TS 36.213.
- Static P=1 и 10/90; окно 500 ms, отдельные UL/DL квоты по площади; без заимствования и переноса неиспользованной квоты.
- Наблюдения BS и ground truth раздельны. UE не получает мгновенно истинный CRC BS.
- Незавершённая работа на горизонте — unfinished. Доставка BS не отменяется потерей подтверждения.
- ML, адаптивное управление и GUI — следующий этап; сейчас интерфейс политики и датасет.

## Организация и зависимости

Последовательность: задачи 01–07 создают среду, данные и время; 08–10 — общий канал и Static; 11–15 — UL PHY; 16–18 — сообщения/DL/тайминг; 19–20 замыкают процедуру; 21–26 формируют результаты, проверки и серии.

Каждая задача имеет самостоятельный результат и контрольную точку. План перечисляет будущие проверки и ожидаемые результаты; их создание и выполнение относятся к этапу реализации с учётом поручения пользователя. PHY-задачи могут занимать несколько рабочих сессий. В системных проверках используются явные события, которые не становятся вторым радиоинтерфейсом для получения KPI.

Наличие Git-репозитория пока не подтверждено. Контрольные версии сохраняются при наличии репозитория; публикация и работа с ветками не входят в текущее планирование.

## Канонические контракты

Биты — столбцы `int8` 0/1; waveform — комплексный `double`; идентификаторы — `uint32`; время — `uint64`. Индексы стандарта нулевые, MATLAB единичные. Поля имеют суффиксы Tick/Sample/Hz/Dbm/Bits/Bytes. Общая ось отсчётов — 1.92 MHz, дробные задержки реализует канал.

| Тип | Поля и ограничения |
|---|---|
| Config | `simulation`, `cell`, `channel`, `traffic`, `ra`, `phy`, `policy`, `dataset`, `logging`; значения из профиля |
| Scenario | UE geometry/loss/CFO/timing, arrivals, UL/DL taps, externalRealizationId, randomManifest; неизменяемый после генерации |
| DeviceState | UE state, packet, attempt, token/RNTI, timers, HARQ; состояния BS отдельно |
| Event | readyTick, phase, sequence, kind, contextId, attemptId, payload; стабильная сортировка |
| ResourceRequest | requestId, phase, direction, channel, contextRnti, earliestTick, deadlineTick, phyProfileId, payloadRef, dependencyIds |
| Grant | Ресурсы/время/TBS/repetition/RV/NDI/DCI/RNTI/configVersion; внутренний grantId не является радио-подсказкой UE |
| Transmission | transmissionId, grantId, direction, waveform, sampleRateHz, startSample, activeRanges, txPowerDbm; связь с истинным UE доступна каналу и анализатору |
| RxWindow | waveform, sampleRateHz, startSample, knownConfig, monitoring; без истинных битов, коэффициентов канала и списка передатчиков |
| NprachDetection | occasionId, nInit, metric, threshold, delay/CFO estimates и качество |
| DecodeResult | Ресурсный контекст, readyTick, decodedBits, hasCrc, crcError, status и измерения; UCI hasCrc=false, crcError=NaN |
| ObservationWindow | windowId, [startTick,endTick), только BS features и схема |
| TruthWindow | windowId, targets/diagnostics и отдельная схема |
| Result | Metadata/config/logs/KPI/dataset/status/stopReason/profiling |

UE восстанавливает назначение из принятых DCI/RAR, а не скрытого Grant передатчика. BS адресует процедуру через RNTI и декодированный token; истинный ueId не используется для выбора победителя Msg3. Имена общих интерфейсов в архитектуре конкретизируются сигнатурами этого плана.

## Задача 01 Среда и совместимость профиля

**Файлы:** `examples/checkEnvironment.m`, `docs/toolbox-compatibility.md`, `src/+nbiot/+phy/ProfileTables.m`.

**Вход:** профиль и локальная справка R2025b. **Выход:** сведения о среде и `msg3Profile(rarIndex)`, `ulTbs(mcs,iru,nsc)`, `dlTbs(mcs,isf)`, `n0Delay(index)`, `n1Delay(index,rmax)`.

- [ ] Найти matlab.exe; сохранить version/ver('lte')/ОС/путь Toolbox. Прочитать test.m, не считать его доказательством готовности.
- [ ] Проверить batch и наличие NPRACH, NPUSCH/NULSCH, NPDCCH, NPDSCH/NDLSCH, NRS, OFDM/SC-FDMA. Ошибку File system inconsistency локализовать до PHY-разработки.
- [ ] Проверить поля R2025b и Fs 1.92 MHz; TDD-поля R2026a не переносить.
- [ ] Перенести используемые таблицы Release 13, monitoring, RA-RNTI, TA и ACK resources; не придумывать отсутствующие функции NB TBS/DCI.
- [ ] Проверить пары: Msg3 RAR index 2 → 3 тона/1 RU/88 bits; MCS 4+IRU 3 →256 bits; DL MCS 6+ISF 0 →88 bits.

**Приёмка:** действующий MATLAB/LTE, таблицы со ссылками на стандарт, длительности 8/32/4 ms согласованы. Несовместимость исправляется минимально, с причиной и версией профиля.

## Задача 02 Конфигурация и ошибки входа

**Файлы:** `configs/baselineStatic.m`, `src/+nbiot/+config/defaultConfig.m`, `src/+nbiot/+config/validateConfig.m`, `tests/TestConfig.m`.

**Интерфейсы:** `cfg = defaultConfig()`; `cfg = validateConfig(cfg)`.

- [ ] Представить все параметры профиля именованными полями Config; отдельно хранить источник ТЗ/решение.
- [ ] Проверить N/radii/heights, probability и indoor [0,1], horizon кратный 1 ms, TBS/MCS/repetition по таблицам.
- [ ] Ввести ошибки `nbiot:config:InvalidValue`, `UnsupportedProfile`, `ResourceInfeasible` с полем/значением/причиной.
- [ ] Проверить каталоги сохранения и доступность зависимостей до генерации случайности.

**Приёмка:** baseline допустим; N=0, отрицательная очередь, NRep 3 и невозможные NPRACH/TBS отклоняются до запуска.

## Задача 03 Источники случайности

**Файлы:** `src/+nbiot/+randomness/RandomSources.m`, `src/+nbiot/+randomness/substreamKey.m`, `tests/TestRandomSources.m`.

**Интерфейсы:** `sources = RandomSources(masterSeed,realizationId)`; `stream = sources.stream(sourceName,direction,receiverId,blockId)`; `manifest = sources.manifest()`.

- [ ] Создавать выбранный поток через `RandStream.create('mrg32k3a','NumStreams',4096,'StreamIndices',realizationId+1,'Seed',masterSeed)`. Основные realizationId — 0–3999, калибровочные — 4000–4095.
- [ ] Закрепить sourceCode 1–11: layout, traffic, shadowing, channel, CFO, timing, noise, payload, access, backoff, token. Под-поток: `1 + blockId + 2^24*(receiverId + 2^16*(directionCode + 2*sourceCode))`; directionCode 0/1, receiverId 0–65535, blockId 0–16777215. Отклонять выход за пределы и нецелые ключи.
- [ ] Для статических величин blockId=0, для шума — абсолютный тик 1 ms; receiverId=0 для BS, ueId для UE. Трафик и payload генерировать отдельным потоком на UE за весь запуск. Для access использовать occasionId; для backoff/token — сквозной номер фактически начатой попытки данного UE за запуск. Каждый запрос ключа начинает чтение соответствующего под-потока с начала.
- [ ] Запретить неадресованные rand/randn и изменение глобального rng в вычислительных модулях; отдельные realizationId калибровки.

**Приёмка:** порядок запросов блоков и дополнительный вызов другого UE не меняют внешние значения; manifest воспроизводит сценарий.

## Задача 04 Размещение и link budget

**Файлы:** `src/+nbiot/+scenario/buildScenario.m`, `src/+nbiot/+channel/evaluateLinks.m`, `tests/TestLayout.m`, `tests/TestLinkBudget.m`.

**Интерфейсы:** `scenario = buildScenario(cfg,sources)`; `links = evaluateLinks(cfg,scenario.ue)`.

- [ ] Радиус sqrt равномерной площади, угол равномерно; round(0.30*N) indoor.
- [ ] Рассчитать расстояния 2D/3D, потери log-distance с n=3.5, shadowing и penetration; сохранить составляющие отдельно.
- [ ] CFO rejection sampling ±200 Hz, sync ±2 µs, стационарные UL/DL Rayleigh taps с нормированной средней мощностью.
- [ ] Сохранить принимаемую мощность до fading, PSD шума, опорный SNR и CE0; SNR ресурса зависит от его полосы.

**Приёмка:** границы/число indoor; аналитические PLref≈51.53 dB, PL 1 km≈121.53 dB, BS noise 180 kHz≈−116.42 dBm. Это будущие checks формул, не результаты запуска.

## Задача 05 Трафик и payload

**Файлы:** `src/+nbiot/+traffic/generateArrivals.m`, `src/+nbiot/+traffic/generatePayload.m`, `configs/trafficPeriodic.m`, `configs/trafficPoisson.m`, `tests/TestTraffic.m`.

**Интерфейсы:** `arrivals = generateArrivals(cfg,sources)`; `bits = generatePayload(packetId,sizeBytes,sources)`.

- [ ] Burst 1000–1100 ms один пакет всем UE; periodic 1 s с random phase; Poisson 0.2/s без принудительного arrival в t 0.
- [ ] Округлить arrival вверх к тику; исключить t>=5000, стабилизировать одинаковые времена.
- [ ] Сформировать 1600 payload bits независимым источником; сохранить непрерывное время, tick и packet sequence.
- [ ] Параметризовать rate/period/group/start/duration; записать arrivals до применения политики.

**Приёмка:** повторяемые arrivals/bits; точные periodic intervals; Poisson rate проверяется большой независимой выборкой.

## Задача 06 Пакеты очередь и фрагментация

**Файлы:** `src/+nbiot/+traffic/PacketStore.m`, `src/+nbiot/+traffic/segmentPacket.m`, `src/+nbiot/+traffic/reassemblePacket.m`, `tests/TestPacketStore.m`.

**Интерфейсы:** `enqueue(arrival)`, `head(ueId)`, `markReceived(packetId,fragmentIdx,bits,tick)`, `markTerminal(packetId,status,reason,tick)`; `[blocks,map] = segmentPacket(packetBits,packetSeq)`.

- [ ] FIFO/drop-tail, 10 локально незавершённых UE packets, включая обслуживаемый/ожидающий receipt. Доставка BS отдельно от освобождения UE.
- [ ] Назначить уникальный packetId и 16-bit sequence; неоднозначное переполнение sequence в версии v1 отклонить.
- [ ] 48-bit header, 8×256 bit TB; payload 208×7+144, последний padding 64.
- [ ] CRC-pass fragment принять один раз; valid length/count проверить, дубль не увеличивает bytes.
- [ ] Lifetime 10 s и причины overflow/ra_limit/harq_limit/service_timeout/lifetime; потеря receipt не отменяет доставку.

**Приёмка:** FIFO/overflow, точная сборка 1600 bits, отсутствующий fragment не доставляет пакет, дубль и malformed header обрабатываются корректно.

## Задача 07 Время события и состояния

**Файлы:** `src/+nbiot/+engine/EventQueue.m`, `src/+nbiot/+devices/DeviceStore.m`, `src/+nbiot/+devices/advanceDevices.m`, `src/+nbiot/NBIoTSimulator.m`, `tests/TestEngine.m`.

**Интерфейсы:** `sim=NBIoTSimulator(cfg,scenario)`; `step/run(untilTick)/snapshot/stop(reason)/result`; `[state,requests]=advanceDevices(state,protocolEvents,now)`.

- [ ] Состояния ТЗ плюс phase/status для receipt/HARQ; BS state отдельно.
- [ ] Stable readyTick/phase/sequence; RX готов через ceil(endSample/Fs*1000)+1 tick; порядок фаз из архитектуры.
- [ ] Сообщение на дедлайне раньше timeout; после горизонта никаких стартов; arrival t 5000 исключён.
- [ ] Проверять attemptId/contextId/configVersion устаревших событий; snapshot не меняет state/randomness.

**Приёмка:** run=последовательность step, deadline race, устаревшая попытка, одновременные события и stop посреди bundle.

## Задача 08 Общий канал на отсчётах

**Файлы:** `src/+nbiot/+channel/RadioChannel.m`, `src/+nbiot/+channel/fractionalDelay.m`, `src/+nbiot/+channel/normalizePower.m`, `tests/TestWaveformChannel.m`.

**Интерфейсы:** `[rxWindows,truth]=propagateBatch(txBatch,sampleRange,receiverContexts)`; `x=normalizePower(x,activeRanges,powerDbm)`.

- [ ] Active power в W, loss/FIR taps/delay/CFO по абсолютному времени.
- [ ] Fractional delay 65 taps с памятью; физический delay отдельно от группового.
- [ ] Сумма всех UL каналов на BS, один noise vector; DL отдельный канал/noise каждого UE.
- [ ] Noise 1 ms блоки, согласованность окон; RxWindow не получает truth. DL обработка batches≤128 UE.

**Приёмка:** аналитическая мощность/CFO/delay; отсутствие удвоения шума; блочная и непрерывная обработки совпадают с относительной погрешностью≤1 e−10 в double.

## Задача 09 Календари и квоты

**Файлы:** `src/+nbiot/+scheduler/ResourceCalendar.m`, `src/+nbiot/+scheduler/buildDlMask.m`, `src/+nbiot/+scheduler/QuotaLedger.m`, `tests/TestCalendar.m`.

**Интерфейсы:** `canReserve(plan)`, `reserveTransaction(plan)`, `releaseUnstarted(ids)`, `area(phase,windowId,kind)`.

- [ ] UL 3.75 kHz×0.5 ms, DL 180 kHz×1 ms; обязательные NPBCH/NPSS/NSSS/SIB1 маски.
- [ ] Available area A каждого окна; RA=floor(0.1*A/quantum)*quantum, DT=A−RA. Без carry/borrowing.
- [ ] NPRACH 45 kHz×6 ms заранее в RA; остаток RA другим сообщениям.
- [ ] Учитывать каждое затронутое окно; occupancy union при collision.
- [ ] Atomic control/data/feedback reservation; освобождать только не начатые ресурсы.

**Приёмка:** бюджет A не превышен, mandatory excluded, boundary crossing, rollback транзакции и отсутствие двойной occupancy.

## Задача 10 Static и Scheduler

**Файлы:** `src/+nbiot/+policy/StaticPolicy.m`, `src/+nbiot/+scheduler/schedule.m`, `src/+nbiot/+scheduler/buildGrantPlan.m`, `tests/TestScheduler.m`.

**Интерфейсы:** `decision=decide(observation,currentConfig,now)`; `[grants,pending,expired]=schedule(requests,calendar,decision,now)`.

- [ ] Постоянные P=1 и профиль static-v1, журнал решений; observations не меняют Static.
- [ ] EDF, enqueue time и sequence; равный deadline — cyclic context cursor.
- [ ] DCI/RAR поля описывают реальное назначение; перебрать разрешённые delay indices при занятости.
- [ ] Half-duplex и monitoring guards; RAR невозможен без Msg3, N1 без NPDSCH/ACK.
- [ ] Нехватка даёт pending/expired, не изменение MCS/repetitions/quota.

**Приёмка:** дефицит RA при свободном DT, отсутствие borrowing, fairness, невозможный ACK, постоянство policy.

## Задача 11 Передатчик NPRACH

**Файлы:** `src/+nbiot/+phy/+nprach/buildTransmission.m`, `src/+nbiot/+phy/+nprach/TemplateBank.m`, `tests/TestNprachTx.m`.

**Интерфейсы:** `tx=buildTransmission(cfg,occasion,nInit)`; `templates=TemplateBank(cfg)`.

- [ ] Все 12 template из lteNPRACH; hopping/CP/activeRanges из metadata.
- [ ] Anchor периода/StartTime/active waveform отдельно; нули не занимают 80 ms ресурса.
- [ ] Кэш шаблона без UE channel; реальные передачи проходят общий RadioChannel.
- [ ] Привязать nInit/opportunity/profile и random access выбор.

**Приёмка:** разные hopping, одинаковые входы воспроизводимы; active power 23 dBm; период/активная часть согласованы.

## Задача 12 Приёмник NPRACH и порог

**Файлы:** `src/+nbiot/+phy/+nprach/receive.m`, `src/+nbiot/+phy/+nprach/correlateCandidates.m`, `experiments/calibrateNprachThreshold.m`, `tests/TestNprachRx.m`.

**Интерфейсы:** `[detections,measurements]=receive(rxWindow,templates,detectorProfile)`; `detectorProfile=calibrateNprachThreshold(cfg,calibrationSources)`.

- [ ] Одиночный loopback и эталон lteNPRACHDetect, сравнить NInit/timing.
- [ ] FFT correlation всех 12 NInit: CFO−200:25:200 Hz, delay−8..20 µs; нормировка по RX/template энергии, нулевая энергия безопасна.
- [ ] Один лучший peak на индекс, timing parabola и CFO refinement по повторяющимся символам; запрещён truth shortlist.
- [ ] 20000 noise calibration windows target PFA 0.0005; независимые 20000 для проверки, Wilson 95% interval без Statistics Toolbox.
- [ ] Если upper PFA>0.001, повысить threshold и перепроверить на новой validation; сохранять историю. Проверить interference от соседнего NPUSCH отдельно.

**Приёмка:** все 12 ideal singles, два разных одновременных кандидата, один index не раскрывает число UE, upper PFA≤0.001. Непройденная физическая проверка не обходится вероятностной моделью.

## Задача 13 Разметка коллизий и near-far

**Файлы:** `src/+nbiot/+phy/+nprach/analyzeTruth.m`, `experiments/nprachReceiverStudy.m`, `tests/TestCollisionLabels.m`.

**Интерфейс:** `labels=analyzeTruth(transmissionTruth,detections,raOutcomes)`.

- [ ] Группы occasion/profile/NInit; раздельные logical collision/overlap/detection/miss/false alarm/RA capture.
- [ ] Miss на occupied index и false alarm на empty; counts attempts≠candidates.
- [ ] Matrix:1/2/4/8 UE, одинаковые и разные индексы, deltaP 0/3/6/10/20 dB, CFO 0/50/200 Hz, delay 0/2/6 µs, SNR−20:5:10 dB.
- [ ] Начать 100 независимых случаев на выбранную комбинацию, сохранить CI. Полную декартову матрицу расширять после оценки стоимости.

**Приёмка:** truth labels известной схемы точны; изменение анализатора не меняет receiver; capture устанавливается только после Msg3/Msg4.

## Задача 14 Передатчик UL и кодек TB

**Файлы:** `src/+nbiot/+phy/+npusch/buildTransmission.m`, `src/+nbiot/+phy/+npusch/buildGrid.m`, `tests/TestNpuschTx.m`.

**Интерфейс:** `[tx,state]=buildTransmission(cfg,grant,payloadBits,encoderState)`.

- [ ] Преобразовать Msg3 RAR index 2 в QPSK/3 tones/1 RU/TBS 88; остальные конфигурации из таблиц.
- [ ] G из lteNPUSCHIndices, lteNULSCH, lteNPUSCH по слотам.
- [ ] DM-RS через lteNPUSCHDRS/Indices, SC-FDMA полной grid.
- [ ] Сохранять состояния кодера, абсолютные frame/slot, NDI и длительность bundle. RV повторений внутри bundle вычислять по §16.5.1.2 TS 36.213; начальный RV bundle брать из HARQ-профиля.

**Приёмка:** RE/slots/G согласованы; 8/32/4 ms; вход receiver — waveform, не исходные symbols.

## Задача 15 Приёмник UL и буфер HARQ

**Файлы:** `src/+nbiot/+phy/+npusch/receive.m`, `src/+nbiot/+phy/+npusch/estimateSync.m`, `src/+nbiot/+phy/+npusch/HarqBuffer.m`, `tests/TestNpuschRx.m`.

**Интерфейс:** `[decode,harqState]=receive(rxWindow,knownGrant,harqState)`.

- [ ] DM-RS residual delay/CFO, SC-FDMA demod, channel/noise estimate, MMSE.
- [ ] NPUSCHDecode/NULSCHDecode с корректным EndOfTx; blkCRC 0 означает success.
- [ ] Разделить объединение физических повторений и полных bundle; использовать соответствующий RV каждого повторения. Ключ буфера — UEcontext/TB, сброс при новом NDI.
- [ ] UCI ACK/NACK/confidence, hasCrc=false, crcErrorNaN; никаких ground truth bit comparisons для рабочего решения.
- [ ] BLER sweep SNR−20:5:10 dB, reps 1/2/8, pilot 100 TB/точка; исследовательский baseline reps 2 постоянен.

**Приёмка:** точное восстановление битов в идеальном канале, ошибки при низком SNR, отклонение фрагмента при ошибочном CRC, объединение без смешивания чужих буферов, UCI без фиктивного CRC.

## Задача 16 Битовые протокольные сообщения

**Файлы:** `src/+nbiot/+ra/encodeMessage.m`, `src/+nbiot/+ra/decodeMessage.m`, `src/+nbiot/+phy/+npdcch/packDci.m`, `src/+nbiot/+phy/+npdcch/unpackDci.m`, `tests/TestProtocolCodec.m`.

**Интерфейсы:** `bits=encodeMessage(kind,fields)`; `fields=decodeMessage(kind,bits)`; `packDci(format,fields)`, `unpackDci(format,bits)`.

- [ ] RAR real RAPID/TA/15 bit grant/TemporaryRNTI/BI; Msg4 identity 48; receipt поля профиля.
- [ ] N0/N1 стандартные fields/bit order MSB-first/lengths TS 36.212; grantId/ueId не добавлять как скрытую подсказку.
- [ ] Msg3 token 48 уникален на попытку, BS узнаёт из bits.
- [ ] Проверить padding/reserved/ranges/length; malformed не даёт успех.

**Приёмка:** round-trip всех видов, golden RAR/DCI examples, reserved/malformed rejection и уникальный token.

## Задача 17 Передатчик и приёмник DL

**Файлы:** `src/+nbiot/+phy/+npdcch/buildTransmission.m`, `src/+nbiot/+phy/+npdcch/receive.m`, `src/+nbiot/+phy/+npdsch/buildTransmission.m`, `src/+nbiot/+phy/+npdsch/receive.m`, `src/+nbiot/+phy/buildDlGrid.m`, `tests/TestDownlinkPhy.m`.

**Интерфейсы:** `[tx,state]=buildTransmission(cfg,grant,bits,state)`; `[decode,state]=receive(rxWindow,monitoringConfig,state)`.

- [ ] DCI CRC/маскирование CRC идентификатором RNTI/convolutional/rate-match средствами Toolbox; проверить generic DCIEncode/Decode explicit length/E. Если overload не подходит, собрать публичными CRC/convolutional/rate-match функциями.
- [ ] NPDCCH/Indices/NRS grid; NPDSCH NDLSCH→NPDSCH/Indices→OFDM, control 88 bits/NSF 1/reps 2.
- [ ] Mandatory signals/NPBCH/SIB1 по маске; принятый DL общий до индивидуальных каналов UE.
- [ ] UE ищет кандидаты известных RNTI/пространствам поиска, декодирует control и затем NPDSCH; scheduler grant truth не подаётся напрямую.
- [ ] Оценивать канал, CFO и время по NRS/полученным сигналам; различать пропуск управляющего сообщения и ошибку CRC транспортного блока.

**Приёмка:** RAR/Msg4/grant/receipt по отсчётам, чужой RNTI отвергнут, потерянное управление не назначает ресурс, один RAR могут принять несколько UE.

## Задача 18 Мониторинг и таймеры

**Файлы:** `src/+nbiot/+ra/ProtocolTimers.m`, `src/+nbiot/+phy/MonitoringCalendar.m`, `tests/TestProtocolTiming.m`.

**Интерфейсы:** `startRar(attempt,physicalEnd)`, `startContention(context,msg3End)`, `expired=advance(now,monitoringEvents)`.

- [ ] RAR start: last preamble subframe+4, а не конец 80 ms буфера; pp10 по мониторируемым подкадрам NPDCCH.
- [ ] Msg3 k0=12, N0 delays 8/16/32/64 и N1/ACK timing по таблицам.
- [ ] Contention pp16 от Msg3 end; monitoring count не заменять wall-time.
- [ ] BACKOFF равномерно 0–256 ms с ceil, следующий eligible occasion; тайм-аут прогресса DT 1024 ms, receipt 512 ms, lifetime 10 s.

**Приёмка:** mandatory пропуски корректно меняют timeout wall-time; grant delays соблюдены; boundary message раньше timeout; ожидание не увеличивает Msg1 counter.

## Задача 19 Полная Random Access

**Файлы:** `src/+nbiot/+ra/RaContextStore.m`, `src/+nbiot/+ra/handleRaEvents.m`, изменения `advanceDevices.m`, `tests/TestRandomAccess.m`.

**Интерфейс:** `[bsState,requests,protocolEvents]=handleRaEvents(bsState,rxEvents,now)`.

- [ ] Detection создаёт BS context occasion/NInit/tempRNTI, без числа конкурентов; RAR+Msg3 транзакция.
- [ ] Все UE с соответствующим RAR передают собственный Msg3 на общем grant.
- [ ] Msg3 успешный CRC даёт token; Msg4 token принимает только соответствующий UE, остальные ждут timeout.
- [ ] UE фиксирует успех RA по соответствующему Msg4; BS подтверждает процедуру отдельно по ACK Msg4. Потеря ACK вызывает повтор Msg4 с идемпотентной реакцией UE.
- [ ] Ложное обнаружение расходует реальные RAR ресурсы, но не создаёт реальный UE; пропуск и ошибка запускают ожидание таймеров; после восьмой неуспешной попытки dropped.

**Приёмка:** один UE, два разные NInit, одинаковый NInit равные мощности и near-far; победитель не задаётся заранее, access не выдаётся по detection.

## Задача 20 Data и доставка

**Файлы:** `src/+nbiot/+devices/HarqProcessStore.m`, `src/+nbiot/+ra/handleDataEvents.m`, изменения PacketStore/NBIoTSimulator, `tests/TestDataService.m`.

**Интерфейс:** `[state,requests]=handleDataEvents(state,decodeEvents,now)`; радио grants/receipt идут через общий PHY.

- [ ] Последовательные 8 TB, новый NDI для нового TB, прежний NDI и следующий RV для повтора; один процесс на UE.
- [ ] UE не передаёт без декодированного N0; пустой назначенный RX выявляется приёмом, не скрытый флаг UE.
- [ ] После успешного CRC всех фрагментов фиксировать deliveredAtBs один раз; после физического приёма receipt завершать локальный контекст UE.
- [ ] До доставки harq_limit/progress_timeout дают drop; после доставки confirmation_timeout не меняет статус пакета.
- [ ] Следующий packet новый RA; дубль последнего TB не увеличивает throughput.

**Приёмка:** повтор промежуточного TB, потеря grant, потеря receipt, повтор TB, четыре неуспешных bundles, второй packet; скрытый CRC не уведомляет UE.

## Задача 21 Журналы и завершение

**Файлы:** `src/+nbiot/+results/EventLog.m`, `src/+nbiot/+results/finalizeResult.m`, изменения NBIoTSimulator, `tests/TestFinalization.m`.

**Интерфейсы:** `append(event)`; `result=finalizeResult(state,logs,stopReason,actualTick)`.

- [ ] Буферы с ростом, UE/packet/attempt/TB/grant/context IDs; по умолчанию без полных waveform.
- [ ] t 5000 готовые результаты RX завершаются, новые не стартуют; недоставленные unfinished.
- [ ] Delivered ожидающие receipt экспорт отдельно; stop/failed/stage/error/time/context сохранены.
- [ ] Диагностическое сохранение waveforms по фильтру и бюджету; трассировка не меняет случайные воздействия.

**Приёмка:** created=delivered+dropped+unfinished, частичный запуск не completed, stop не вызывает искусственный drop.

## Задача 22 KPI и когорты

**Файлы:** `src/+nbiot/+metrics/MetricAccumulator.m`, `src/+nbiot/+metrics/summarizeKpi.m`, `tests/TestMetrics.m`.

**Интерфейсы:** `consume(event)`, `closeWindow(startTick,endTick)`; `summary=summarizeKpi(logs,actualDuration)`.

- [ ] Основная вероятность RA: успешные попытки / все начатые Msg1, плюс оценка только завершённых попыток и число цензурированных; Data delivered/все созданные пакеты, плюс оценка только завершённых пакетов.
- [ ] BLER по завершённым bundle decodes отдельно Msg3/Data/first/все HARQ-передачи; UCI не BLER по CRC.
- [ ] Throughput unique полезные биты / фактическая длительность, без headers/padding/CRC; средняя задержка / p95 delivered/count.
- [ ] Queue интеграл по времени; occupancy union UL/DL; collision probabilities attempts/resources отдельно; observed/trueNPRACH раздельно.
- [ ] Zero denominator→NaN/count 0; window successes не делить на несопоставимые начала в другом окне.

**Приёмка:** вручную заданный журнал с тремя пакетами, повтором, коллизией и незавершённой работой даёт точные формулы; p95 без Statistics Toolbox.

## Задача 23 Датасет и экспорт

**Файлы:** `src/+nbiot/+dataset/featureSchema.m`, `src/+nbiot/+dataset/closeWindow.m`, `src/+nbiot/+dataset/buildManifest.m`, `src/+nbiot/+results/saveResult.m`, `tests/TestDataset.m`, `tests/TestExport.m`.

**Интерфейсы:** `[obs,truth]=closeWindow(observedLog,truthLog,startTick,endTick)`; `manifest=buildManifest(runIds)`; `saveResult(result,folder)`.

- [ ] Окна 500 ms, включая пустые; features detections/energy/peaks/CRC/grants/известные BS очереди, каждому source/unit/availability/aggregation.
- [ ] Targets интеграл UE в RA и активных UE и фактические Msg1; скрытая очередь/collision counts не входят features.
- [ ] Whitelist источников features, policy получает obs без truth; split 70/15/15 целыми идентификаторами реализаций.
- [ ] MAT/CSV/schema/manifest/environment/источники случайности; v7.3 большие массивы, отсутствие Git явно.

**Приёмка:** 10 окон baseline, пустые включены, target не features, MAT/CSV читаются обратно, realization не в нескольких splits.

## Задача 24 Полная проверка цепочки

**Файлы:** `tests/TestEndToEnd.m`, `examples/runBaseline.m`, `docs/validation-report.md`, `src/+nbiot/runExperiment.m`.

**Интерфейс:** `result=nbiot.runExperiment(cfg,scenario)`; если scenario отсутствует, он создаётся по cfg.

- [ ] WAVEFORM scenarios N1/2/10/100, no traffic/только шум, заданные коллизии/near-far, RAR/Msg4 loss/stop.
- [ ] Два идентичных runs: сравнить logs/KPI/dataset, исключить время исполнения и каталог сохранения.
- [ ] Инварианты: успех после окончания приёма; отсутствие передачи без grant; обнаружение не завершает RA; один фрагмент не доставляет пакет; квоты соблюдены.
- [ ] Отчёт содержит версию среды, команды, фактические результаты и графики физических зависимостей; успех заявлять только после выполнения.

**Приёмка:** детерминированные проверки пройдены, физически объяснимые зависимости и реальные результаты отчёта.

## Задача 25 Серии и статистика

**Файлы:** `experiments/runStaticSweep.m`, `experiments/profileBaseline.m`, `src/+nbiot/+results/aggregateRuns.m`, `src/+nbiot/+results/plotSummary.m`.

**Интерфейсы:** `manifest=runStaticSweep(sweepConfig)`; `summary=aggregateRuns(results)`.

- [ ] N100/500/1000/2500/5000×burst 10/100/500 ms; periodic/Poisson дополнительные.
- [ ] Pilot 3 runs/комбинацию →10 →100 при достаточных ресурсах согласно ТЗ; стоимость измерить.
- [ ] Atomic save temp/readback/rename, манифест с возможностью продолжения, каждый run externalRealizationId.
- [ ] Mean/SE/CI по независимым runs, объединённая вероятность с counts отдельно; окна не независимы.
- [ ] Графики load/RA/delivery/throughput/delay/BLER/occupancy/queue/drops/unfinished.

**Приёмка:** воспроизводимая серия с возможностью продолжения; фактическое число запусков/CI/условия; нет требования доставить все пакеты 5000 UE за 5 s.

## Задача 26 Производительность и документация

**Файлы:** profiler-выявленные модули, `docs/performance-report.md`, `README.md`, `examples/runBaseline.m`.

**Выход:** измеренные затраты и инструкция воспроизведения.

- [ ] Измерить время и память для N=100 и N=1000, выполнить один запуск N=5000; сохранить характеристики ПК и доли затрат по модулям.
- [ ] RX buffers 10 ms, группы до 128 UE для DL, state bundle между блоками; рабочая память 1 GiB как ориентир, превышение объяснить измерением.
- [ ] Кэш templates/FFT/vectorization/буферы журналов только в узких местах; не хранить все waveforms 5000 UE за 5 s.
- [ ] Пропуск пустых тиков или параллельные запуски допускаются после подтверждения эквивалентности журналов, таймеров и случайных воздействий; последовательная версия остаётся доступной.
- [ ] README installation/config/одиночный запуск/sweep/export/KPI/assumptions/расширение политики.

**Приёмка:** baseline 1000 и фактический 5000, измерения, сохранение эквивалентности и понятная инструкция.

## Примеры будущих проверок контрактов

Это фрагменты для тестов при реализации; сейчас они не добавляются в исходники.

```matlab
cfg = nbiot.config.defaultConfig();
cfg = nbiot.config.validateConfig(cfg);
assert(cfg.simulation.durationTicks == 5000);
assert(cfg.ra.maxAttempts == 8);
assert(cfg.policy.raShare == 0.10);
[blocks,map] = nbiot.traffic.segmentPacket(zeros(1600,1,'int8'),uint16(1));
assert(numel(blocks) == 8);
assert(all(cellfun(@numel,blocks) == 256));
assert(sum(map.validPayloadBits) == 1600);
r = nbiot.runExperiment(cfg);
assert(r.kpiSummary.created == r.kpiSummary.delivered + ...
       r.kpiSummary.dropped + r.kpiSummary.unfinished);
assert(height(r.dataset.observations) == 10);
```

Будущие команды из корня проекта:

```matlab
addpath('src','configs');
run('examples/checkEnvironment.m');
testResults = runtests('tests','IncludeSubfolders',true);
assertSuccess(testResults);
run('examples/runBaseline.m');
```

## Покрытие ТЗ

| Требование | Задачи |
|---|---|
| §10 размещение | 03–04 |
| §11 трафик/очереди | 05–06 |
| §12 состояния | 07,18–20 |
| §13 link budget/канал | 04,08 |
| §14–17 NPRACH/collisions/CFO/timing | 08,11–13,19 |
| §18 RA/BACKOFF | 09–10,16–19 |
| §19 DL | 09,16–18 |
| §20 Data/CRC/BLER | 06,14–15,20–22 |
| §22 dataset | 23 |
| §26 Static | 09–10 |
| §27 KPI | 21–22 |
| §28–30,42–43 серии/случайность | 03,24–26 |
| §31–39 проверки | Проверки 02–24 |
| §45,47 модули/сохранение | Контракты,07,21–23 |
| §62–65 единая модель/внешние условия | 03,08,24 |

ML/Controller/Adaptive/GUI из полного ТЗ относятся к следующей версии. Интерфейс policy.decide и датасет предусмотрены; обученная модель и адаптивные сравнения не являются результатом текущего объёма.

## Риски и действия

| Риск | Действие |
|---|---|
| MATLAB не запускается | Диагностика 01, до неё не заявлять работающий PHY |
| NPRACH sidepeaks/near-far | Карты/threshold/CFO в 12–13, корректировка receiver внутри интерфейса |
| Дискретные ресурсы не помещаются | Pending/deadline/явная причина, квоту не менять |
| DL ограничивает доступ | Показать занятость DL/latency/unfinished, сохранить физический RAR |
| Нужен дополнительный Toolbox | Базовые FIR/randomness/CI/quantiles в MATLAB/LTE; зависимость обосновать |
| Потеря receipt | доставка BS отдельно от подтверждения UE, не отменять доставку/не дублировать throughput |
| Дорогая серия 100 runs | Pilot/измеренная оценка/resume/оптимизация; фактический объём указывать явно |

## Завершение планирования

Параметры и алгоритмы определены требованиями ТЗ либо проектными решениями. План содержит 26 задач, зависимости, интерфейсы, будущие файлы, проверки и критерии. Реализация начнётся по отдельному указанию пользователя; ответов о недостающих параметрах для начала не требуется.
