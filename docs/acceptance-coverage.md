# Карта приёмки Static/WAVEFORM —2026-10-06

В поставке v2.0.0 свежие результаты проверок сохранены в [verification/v2-validation.json](../verification/v2-validation.json). Изменение при упаковке ограничено двумя путями необязательного GPU-бенчмарка и добавлением его входного MAT-файла; основное ядро и радиоприёмники сохранены побайтово. Исторические ссылки на optimization-evidence ниже не означают зависимость штатного запуска от той папки.

Статус относится к отдельному optimization-candidate. Исходный проект и архив сохранены. Названия задач ниже взяты из implementation-plan.md; фактические реализации ряда прежних предполагаемых модулей находятся в NBIoTSimulator.m. Исторические контрольные точки не помечаются пройденными только по наличию файлов.

Последняя полная проверка:112/112passed,0failed,0incomplete в чистой перенесённой папке по новому README, 2026-10-06; readme-fresh-suite.mat. Также прошли проверка среды, одиночная доставка1600bits, три независимых малых случая, verifyCase и повторный resume без нового расчёта. Это тот же Windows/R2025b ПК; перенос на другие машины ещё не проверен. Кэш постоянных PHY-профилей ранее подтвердил17/17result fields exact (config нормализован только по outputFolder) и6/6CSV SHA exact. Прототип DL pruning отклонён: полный100UE сравнил одинаковые config/KPI/PHY decisions, но нашёл различия в observedLog и dataset; верхнеуровневые проверки сохранены в optimization-evidence. Вложенное сравнение остаётся открытым.

Отчётность первой HARQ попытки и новый source-manifest helper подготовлены в optimization-evidence/reporting-staged, но ещё не перенесены в принятый кандидат и не проверены полным MATLAB suite. Большие нагрузки, независимая capture-серия и portable release остаются открыты.

## Соответствие задачам01–26

| Задача | Выполненная проверка | Открытое условие / граница |
|---|---|---|
|01 Среда/таблицы | checkEnvironment/verifyRoundtrips, TestPhyTables, TestPhyWaveforms; настоящий R2025b/LTE; MATLAB работает вне sandbox | Ошибка sandbox не является отказом установки MATLAB |
|02 Конфигурация | TestConfig; NaN calibration fail TestRadioProtocol | Изменение нормативного профиля потребует новой валидации |
|03 Случайность | TestRandomSources; O4 exact sequence/1/2/3workers/reverse order | Повтор ID не увеличивает независимое n |
|04 Геометрия/link budget | TestLayout; независимые физические channel/layout streams | Профиль канала исследовательский; не измеренная полевая модель |
|05 Трафик/payload | TestTraffic; реальные200bytes/1600bits; второй packet и новый sequence TestRadioProtocol | Системный pilot сейчас использует burst100ms |
|06 Очередь/фрагменты | TestPacketStore; physical intermediate/last TB retry; второй packet | Доставка считается по уникальным полезным битам |
|07 Время/состояния | TestEngine; run/step exact, partial export/resume exact; границы message-before-timeout | Сохранённый case resume повторяет незавершённый case; snapshot engine checkpoint не заявляется |
|08 Общий канал | TestWaveformChannel; все UE суммируются по отсчётам; negative tests отменяют реальную волну | Ground truth используется только каналом/анализатором |
|09 Календарь/квоты | TestCalendar, TestDlCalendarIndex, TestMonitoringTickIndex; CPU exact26/26 | Квоты/mandatory mask не менялись |
|10 Static/Scheduler | TestScheduler, TestSchedulingFairness; EDF и finite requeue contention | Общая fairness не доказывается двумя конечными fixtures |
|11 NPRACH TX | Все12indices TestPhyWaveforms;900окон сохранённых mixed-waveform fixtures | Один принятый presence index не равен числу UE |
|12 NPRACH RX/threshold | TestNprachInterference5/5; свежий noise0/20000;6interference rows×20000; upper PFA95≤.001 | Near-far40dB может терять weak index/давать timing error; конечный gate |
|13 Коллизии/capture | Truth attempt collision отдельно от RX; near-far development n100/ratio с CI;4full2UEdiagnostic cases | Независимые10повторов/условие готовятся; presence не является Msg3 winner |
|14 UL TX/TB | Реальный NPUSCH/NULSCH roundtrip; корректные RV/NDI TestRadioProtocol | Табличная/кодековая проверка не заменяет BLER-кривую |
|15 UL RX/HARQ | TestUciPresence, физические HARQ/retry/loss tests; четыреData bundles, RV0/2/0/2 | UCI безCRC; finite fading/noise/foreign gate описан отдельно; неполный произвольный timing envelope |
|16 Битовые сообщения | TestProtocolCodec, golden/malformed/range fixtures; decoded token связываетBS context | Нестандартные hidden IDs/CRC не добавлялись |
|17 DL RX/TX | TestDownlinkTiming, TestDownlinkMultipath8/8;18fresh20dBrows×500:0CRC/0wrong; SNR−20..30dB |41CP candidates стоят CPU; beyond-profile delay только rejection regression |
|18 Мониторинг/таймеры | Calendar/monitoring tests; Msg4 RX at deadline и finalData/lifetime boundary;8RA limit | Стандартные physical deadlines сохранены |
|19 Полная RA | Одиночный accepted-calibration run RA1success; Msg4ACK physical loss idempotence; stale grant/context reject | Полная независимая collision/capture статистика ещё не завершена |
|20 Data/доставка | TestRadioProtocol12/12;40dBData CRC failure воспроизведён и изолирован | Full/noiseless signal fails, desired-only exactpayload passes;4RV0/2/0/2,NDI1,0header failures. Один случай не определяет причины всех timeout |
|21 Журналы/finalization | TestEndToEnd; stop/failed/partial; captureFailure4/4, byte budget/readback/hash, separate truth | Явно выбранные последние128ticks; не запись всех waveform |
|22 KPI/когорты | TestMetrics: censored denominators/unique bits/union occupancy; balances verifyCase | First-HARQ BLER не выделен в текущем kpiSummary; при анализе серии нужен публичныйHARQ trace, не подмена all-bundle BLER |
|23 Dataset/MAT/CSV | TestDataset/TestOptimizationEquivalence; MAT+6CSV schema/SHA/readback; malformed marker.tables reject | Изменение feature schema требует отдельной версии |
|24 Полная короткая цепочка |112/112suite принятого source SHA d67...; physical1UE delivered; noTraffic; determinism; O4 process equivalence | Общий suite не заменяет load/capture научную приёмку |
|25 Серии/CI | TestExport3/3; plotSweepSummary12metrics, outer-run Student-t/counts/NaN; coordinator UUID/resume |10independent100/1000 runs и полный capture pilot ещё не завершены;100runs не разрешаются автоматически |
|26 Производительность/перенос | O2 1000UE6.72%saved exact; O4 small3workers; O5 profile; GPU full1UE rejected; обновлённые docs | Свежие100/1000/5000 время/aggregatepeak выполняются; переносимый ZIP/hash ещё не подготовлен |

## Принятые радио-свидетельства

NPRACH threshold0.005: noise realization4005, interference4004; calibration SHA1068f3daaa8c2fb8d62bc34671f63e1462b6f2b81da9f1b8cf75820c013216e4. Все6верхних95%PFA≤0.000512. Старый failed holdout0.004 хранится как development; threshold выбирался до свежих данных.13receiver/validator dependencies совпали до/после.

UCI fresh realization3800: Noise/ForeignACK/ForeignNACK0/6000falseACK каждый (upper95=.0006146), OwnACK/OwnNACK1000/1000correct каждый. Conditional receiveSNR20dB, Rayleigh3tap, CFO±200Hz, post-TA delay±4.34samples. Exact RNTI100/ACK1=RNTI2103/NACK0 waveform alias остаётся известным ограничением. Нельзя заявлять универсальное foreign rejection.

DL fresh IDs2000–2499:500независимых каналов на каждую из18строк; pairedCFO/delay/control/data условия не объединяются в n9000. Upper95BLER=.007351 при20dB. SNR curve:24rows×100 independent channels/row,655CRC failures,0wrongaccepted;0..30dB повтор прежней неизменённой выборки не увеличиваетn.

## Что требуется до завершения проекта

1. Закончить новый full-horizon load pilot100/1000 и5000UE; записать фактические время/память/статусы/полноту экспорта.
2. Выполнить независимые физические collision/capture повторы и объяснить наблюдённые40dB Data failures через waveform/grants/HARQ trace.
3. Выполнить10внешних реализаций согласованных нагрузок100/1000burst100ms; пересчитать стоимость и precision CI. Отдельное решение по100и расширению до15условий.
4. Закрыть оставшийся отчётный first-HARQ контракт без изменения radio decision и без ложного all-bundle denominator.
5. Проверить переносимую папку/ZIP по хешам, сохранить команды/выбранные доказательства и повторно сверить исходный проект.

Эти пункты открыты. Pilot не называется основной научной серией; новая радио-версия не объявляется полностью принятой до завершения указанных проверок.
