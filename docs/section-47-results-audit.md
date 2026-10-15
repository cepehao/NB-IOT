# Проверка сохраняемых результатов по §47 ТЗ

Сверка по страницам 24–25 ТЗ и текущему коду. Это проверка структуры и коротких тестов, не научная приёмка расчётов.

| Требование §47 | Где сохраняется сейчас | Проверка | Что остаётся |
|---|---|---|---|
| Параметры опыта: сценарий, seed, длительность, шаг, число UE, трафик | Полный MAT содержит result.config и result.scenario; паспорт случая содержит хеши запуска | [TestRuntimeManifest](../tests/TestRuntimeManifest.m), 20/20; [TestExport](../tests/TestExport.m), 3/3 | Проверить фактические экспортированные серии на целевой машине |
| Параметры сети: частота, полоса, размещение, мощности, шум | Частота и общая полоса теперь явно сохраняются в `result.network.carrierFrequencyHz` и `result.network.bandwidthHz`; полоса берётся из общего link budget. Геометрия, мощности и шум есть в `result.config` / `result.scenario` | [TestResultMetadata](../tests/TestResultMetadata.m), 3/3; [TestLinkBudget](../tests/TestLinkBudget.m) | Подтвердить поля на итоговых внешних сериях; локально проверена структура, а не численный результат большой нагрузки |
| PHY: затухание, тени, потери в помещении, замирания, CFO, сдвиг времени, SNR/SINR | `result.scenario.ue` сохраняет `cfoHz` и `syncOffsetSeconds`; `result.scenario.linkBudget` хранит мощность и reference SNR до fast fading/помех. `result.radioReceptionLog` и `result.radioDiagnostics` хранят SINR, оценки NPRACH/NPUSCH и заданную истину отдельно. | [buildScenario](../src/+nbiot/+scenario/buildScenario.m), [evaluateLinks](../src/+nbiot/+channel/evaluateLinks.m), [detect](../src/+nbiot/+phy/+nprach/detect.m), [receive](../src/+nbiot/+phy/+npusch/receive.m), [radioDiagnostics](../src/+nbiot/+metrics/radioDiagnostics.m) | Reference SNR не равен мгновенному SINR. Истинная задержка приёма включает распространение и timing advance; для неоднозначных NPRACH-ключей заданная истина оценки остаётся `NaN`. MAT и CSV readback — задачи 3; внешняя физическая проверка — задача 7 |
| RA: попытки, обнаружения, столкновения, miss, capture, успешный доступ и повторы | `truthLog` содержит начало и исход каждой завершённой RA-попытки; `observedLog` хранит кандидатов; `radioReceptionLog` — интервалы компонентов и парные мощности. Итоговые числители и знаменатели находятся в `result.radioDiagnostics`, экспорт — `_radio.csv`; сводка и карточка UE читают эти поля. | [NBIoTSimulator](../src/+nbiot/NBIoTSimulator.m), [radioDiagnostics](../src/+nbiot/+metrics/radioDiagnostics.m), [TestRadioDiagnostics](../tests/TestRadioDiagnostics.m), [TestRadioDiagnosticsExport](../tests/TestRadioDiagnosticsExport.m) | Внешняя физическая приёмка остаётся задачей 7 |
| NPUSCH: передачи, успешные передачи, CRC, BLER, throughput | observedLog и phyLog содержат результаты декодирования; KPI сохраняют BLER и throughput. HARQ-журнал версии 2 добавляет ID пакета к фактическим передачам данных для точного живого счётчика уникальных пакетов | [TestRadioProtocol](../tests/TestRadioProtocol.m), [TestMetrics](../tests/TestMetrics.m), [TestHarqMetrics](../tests/TestHarqMetrics.m), [TestTransmittedPacketCount](../tests/TestTransmittedPacketCount.m) | Итоговые числа по независимым сериям ожидают внешних запусков |
| ML: модель, признаки, цель, метрики train/test и ошибка оценки | Adaptive-результат сохраняет имя/хеш модели, тип данных, признаки, цель, seed, ID разбиений, статус оценки и таблицу train/validation/test в `result.controllerModel`. Таблица добавляется только если манифест указывает выбранный файл и его SHA-256 совпадает | [TestResultMetadata](../tests/TestResultMetadata.m), 3/3; [TestModelEvaluationMetrics](../tests/TestModelEvaluationMetrics.m), 2/2; [TestLoadModels](../tests/TestLoadModels.m), 9/9 | В текущих примерах метрики учебные/development. Независимой оценки на реальных данных нет; отсутствие подтверждённых оценок явно записывается как `unavailable` |
| Контроллер: оценка нагрузки, решение, время и выбранная конфигурация | result.controllerLog и отдельный _controller.csv, схема журнала 1 | [TestController](../tests/TestController.m), [TestFullAdaptiveChain](../tests/TestFullAdaptiveChain.m) | Проверка на одном UE с development-моделью не подтверждает качество решений |
| KPI: успешность доступа, успешность доставки, throughput, столкновения, задержка, потери, занятость и очереди | `result.kpiSummary`/`result.kpiTimeSeries` для прежних метрик; `result.radioDiagnostics` для новой радиосводки | [TestMetrics](../tests/TestMetrics.m), [TestRadioDiagnostics](../tests/TestRadioDiagnostics.m) | UI и внешние агрегаты по независимым сериям остаются открытыми |
| Service outage and group KPI | Service outage is demand-bearing UEs with no delivered packet by the completed observation horizon; group dimensions are indoor/outdoor and coverageClass separately | `result.kpiSummary.service`, `result.groupKpi`, `_groups.csv`; retain H, availability, numerator/denominator counts, packet and RA counters | Task 2 known-answer, partial/no-demand, legacy compatibility, CSV readback and summary checks passed; fresh UI/CLI smoke Task 6; physical values Task 7/8 |
| Сравнение Static, Adaptive-P и Adaptive-RA/DT | Исполнитель формирует method-summary.csv и paired-comparison.csv | [TestComparisonSweep](../tests/TestComparisonSweep.m), dry-run 5/5 | Реальные парные сравнения ещё не запускались |
| Данные каждого UE: координаты, размещение, indoor/outdoor, радиопотери, мощность, SNR/SINR, CFO, класс покрытия, число попыток, состояние и исход обслуживания | `result.ueSummary` объединяет данные сценария, link budget, попытки доступа, итог пакетов и состояние UE; `result.radioDiagnostics.perAttempt` добавляет UE-связанные SINR и оценки приёмника. MAT и таблицы `_ue.csv`/`_radio.csv` сохраняют соответствующие наборы. | [TestPerUeSummary](../tests/TestPerUeSummary.m), [TestRadioDiagnosticsExport](../tests/TestRadioDiagnosticsExport.m), [TestCaseResume](../tests/TestCaseResume.m) | Опорный SNR не является мгновенным SINR. Полноту по §47 и независимые численные результаты ещё нужно подтвердить внешней приёмкой |
| Сохранение и проверка целостности | MAT содержит полный результат и новые диагностические журналы; новые случаи получают `_radio.csv` версии 3, старые таблицы версии 2 продолжают читаться | [TestRadioDiagnosticsExport](../tests/TestRadioDiagnosticsExport.m), [TestCaseResume](../tests/TestCaseResume.m) | Перепроверить итоговый комплект на другой машине; внешняя физическая приёмка остаётся открытой |

## Проверки на текущей копии

13 октября 2026 года с жёстким лимитом времени завершились короткие проверки сохранения и метаданных. Для текущих полей: [TestResultMetadata](../verification/local/result-metadata-persisted-green-20261013/) — 3/3, включая повторную загрузку MAT; связанная проверка моделей, контроллера, Adaptive, UE-сводки, манифеста и CSV — 42/42 ([журнал](../verification/local/result-metadata-regression-20261013/)). Ранее прошли TestExport — 3/3, TestMetrics — 2/2, TestHarqMetrics — 16/16, TestLinkBudget — 3/3, TestLayout — 1/1, TestPerUeSummary — 2/2, TestRuntimeManifest — 20/20 и TestCaseResume — 15/15. Всё выполнялось на малых/искусственных случаях; большие UE-нагрузки не запускали.

## Следующее действие

ТЗ §47 требует, чтобы структура `result` содержала перечисленные сведения; отдельный CSV-сводный лист параметров сети не задан. Расчётный link budget сохраняется в `result.scenario.linkBudget` и `result.ueSummary` / `_ue.csv`; общая частота и полоса дополнительно доступны как `result.network`. Опорный SNR рассчитан для 180 кГц до fading и помех; это не измеренный SINR во время передачи. Метрики модели сохраняются только для совпадающего по хешу пакета и остаются development-оценками, пока не получены реальные независимые данные.

Локальные расчёты link budget, объединение счётчиков в `_ue.csv`, сохранение `result.network` и связка модели с train/test-метриками проверены на малых случаях. Проверки захвата перекрывающихся передач и научная приёмка остаются отдельной частью внешних физических испытаний.

**Статус §47: частично.** Явная полоса сети и проверенные train/test-метрики модели теперь сохраняются в MAT-результате. Полнота остальных групп, численные физические серии и итоговая сверка на другой машине остаются открытыми.

### Service outage and grouped results

The resolved definitions are in [metrics-contract.md](metrics-contract.md).
The service KPI distinguishes UE-level outage by H from packet loss and from an
SNR-threshold radio outage. Group rows aggregate indoor/outdoor and coverageClass
separately from the existing per-UE summary. Empty denominators remain NaN with
their zero counters preserved. MAT/CSV and final-summary integration, including
legacy no-data display, passed targeted Task 2 checks. Fresh UI/CLI integration
is Task 6; physical values and Stage 2 acceptance remain Tasks 7–8.

## Радиодиагностика, добавленная планом завершения

ТЗ §47 требует сохранять для UE и результата мощность/SNR/SINR, timing, CFO,
miss, capture и столкновения. Link budget остаётся источником только для
опорных мощности и SNR; он не подменяет SINR приёма. `result.radioDiagnostics`
содержит агрегаты и оценки, `result.radioReceptionLog` — скалярные измерения
компонентов/приёмника, а `_radio.csv` предназначен для анализа этих полей.

| Новое поле результата | Источник и единицы | Сохранение / отображение | Проверка |
|---|---|---|---|
| Miss / false alarm, detection counts/rates | Truth и receiver candidates по `(occasionId,nInit)`; числители, знаменатели и доля (0–1) | `result.radioDiagnostics` и `_radio.csv`; итоговая сводка показывает числа и доли | Синтетические случаи и граница окна — 14/14; MAT/CSV readback — задача 3 пройдена; физическая приёмка — задача 7 |
| Logical collision / physical overlap / capture | Truth попыток, принятые интервалы, парные мощности; группы, пары, попытки и доли | Диагностическая сводка + `radioReceptionLog` в MAT и `_radio.csv`; итог показывает группы/пары; capture только по общему интервалу | Known-answer fixtures — 14/14; физическая матрица остаётся задачей 7 |
| Received power / instantaneous SINR | Мощности сигнала, помех и шума в одной полосе и на одном интервале; W и dB | MAT/CSV отдельно от reference SNR и с пометкой `diagnosticTruth`; итог показывает число значений, карточка UE — свои попытки | Известные мощности и короткий пример проверены; полная физическая приёмка внешняя |
| Estimated delay/CFO and errors | Receiver estimate минус заданная эффективная задержка пути/CFO; секунды и Hz | NPRACH/NPUSCH estimate и truth раздельно в MAT/CSV; карточка UE показывает оценки выбранного устройства после завершения | Знак, разделение truth/estimate и round-trip пройдены; физический sweep — задача 7 |
| Outage | ТЗ §46.13 называет KPI, но не указывает порог/формулу; выбран service-level показатель по demand UE без доставки к H, не radio outage | `result.kpiSummary.service` хранит definition, H, available, demand/outage/unfinished counts и вероятность; итоговая сводка получает их из результата | Известные числа, partial/no-demand и отображение прошли Task 2; UI/CLI smoke — Task 6, Stage 2 physical acceptance — Task 7 |

Отношения сохраняют числитель и знаменатель; при нулевом знаменателе — `NaN`
вместе со счётчиками. Группы UE по indoor/outdoor и coverageClass закреплены по
существующим полям `ueSummary`; это отдельные измерения, без новых категорий.
