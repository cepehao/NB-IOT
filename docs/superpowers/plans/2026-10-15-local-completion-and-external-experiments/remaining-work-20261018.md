# NB-IoT — исправления и оставшиеся этапы, редакция 18 октября 2026

**Активная коррекция 19.10 после независимой оценки:** T1/T2 были переоткрыты по `verification/local/independent-evaluation-20261019/review.md`. Владелец явно поручил выполнить разрешённую работу без промежуточных остановок. Точный request — `verification/local/independent-evaluation-20261019/execution-request.md`; исполняющая сессия — «Довести NB-IoT до требований ТЗ». Исправлены MATLAB bootstrap, mutable registry в frozen manifest, размещение candidate/acceptance и sanitation Windows-путей; bounded GREEN результаты и независимый code review сохранены. Важное замечание review — расхождение номеров исторических package snapshots в handoff/плане — исправлено в документах. Отдельные отрицательные тесты path-escape/symlink/overwrite ветвей копирования остаются возможным улучшением покрытия; дефект не обнаружен. Условия остановки нагрузки, научных решений, бюджета, фоновой очереди и защиты AmneziaVPN сохраняются.

**Состояние на 19 октября:** T1/T2 дефекты исправлены; P1-1 3/3, P1-2/P2-1 19/19 плюс process-only 1/1, P1-3 6/6, independent review PASS. Покрытие ветвей escape/symlink/overwrite неполное, функциональный дефект не выявлен. RED #022 выявил преждевременный T3/F12 PASS и статичный review path; генератор исправлен на pending и digest-specific link. Предыдущий package-only #025 прошёл 1/1 за 31,5687795 с и получил независимый `SPEC PASS / QUALITY PASS` без существенных расхождений. Reviewer сверил source digest `6312a7479b5069a62d7481e1a5c8213b5bab1383429cd3b70aa9b71d88e7d1c3`, ZIP SHA `9a31757ff26706778885fa04e71a51e70ffbe061c95620c3aa815c4a215a59b7` и handoff SHA `b82a1e2d43ff20789bd19678f8b8ad3976b3ba6eba43fab77c246fec538ffa87`; полный scope записан в `verification/local/runtime-review/T3/package-identity-review-6312a7479b50.md`. Это приёмка package identity/local engineering only. После каждого дальнейшего изменения manifest снова должен ждать независимого отчёта на тот же digest/hash. Readiness false; U3 answers не выводятся; новая нагрузочная серия остаётся остановленной. R4.12, визуальный gate и научные решения остаются открытыми.

> Для исполнителя: это карточки оставшейся работы единого [плана](../2026-10-15-local-completion-and-external-experiments.md), не новый параллельный проект. Применять executing-plans inline с SDD ledger; научные интерфейсы — в data-model.md. Исполнение по активной цели начато 18.10 с S0; проверки и внешние вычисления запускаются только в пределах карточек и утверждённых gate.

**Цель:** исправить выявленные дефекты, завершить доступную инженерную часть, проверить её как одну цепочку и подготовить передачу внешних экспериментов.

**Основание:** проверка `verification/local/progress-review-20261018/review.md`, исходный аудит F1–F12, runtime.md, data-model.md, ui-delivery.md и текущий ledger. Пути ниже считаются от `C:/PROJECTS/nbiot/github-v2-publication`.

**Архитектура:** сохранить физический симулятор, научные параметры, калибровку, RNG и форматы принятых контрактов. Допуск модели отделён от обучения и неизменяемого MAT. Один координатор отвечает за интеграцию, вычислительную очередь и готовность.

**Стек:** существующие MATLAB R2025b/toolbox, PowerShell и JSON/CSV/MAT; новых сервисов и зависимостей не требуется.

## Общие условия исполнения

- Работать в существующей `work/local-completion-after-v3`, сохраняя dirty/untracked. P0 и принятые R1/R2/R3/D1/D2/D3/U1 повторно не реализовывать. U2 локальная часть и U4 сохраняются; U5 требует узкого исправления.
- Код, scientific MAT и старые результаты не менять ради статуса; main/v2/v3/tag/assets и публикации не трогать. Никаких reset/clean/stash, массового копирования или `git add .`. Новые commit/push в эту редакцию не включены.
- Исходный предел local-development: ≤10 UE, ≤300 секунд на файл/случай, ≤900 секунд на выбранный набор. Все **новые физические fixtures этой редакции — ≤2 UE на случай**; текущие 1-UE fixtures сохраняются. Синтетические таблицы/отрицательные preflight counts не являются разрешением физического запуска.
- MATLAB запускает только координатор через `verification/local/runBoundedChecks.ps1`. Один worker; исполнители замораживают вычислительные исходники/тесты, сохраняются before/after hashes и итоговый статус. Timeout/incomplete не считаются успехом. Точный перечень тестов проверять до старта, весь tests/ не запускать.
- Работать в фоне. Не разворачивать MATLAB/демо и не возвращать фокус владельцу навстречу. Очередь проверять по точной identity своего worker, terminal reports/cleanup и одному владельцу. Визуальные проверки — отдельно в согласованный момент. Недоступность свёрнутого окна не означает busy.
- Максимум координатор, два исполнителя с непересекающимися write sets и независимый reviewer. Общие App/ML/packaging файлы передавать последовательно по locks. Стандартный цикл: короткий request → bounded RED/GREEN → независимые SPEC/QUALITY → решение координатора. Дополнительный preflight нужен при конкретном новом риске или явном требовании карточки, а не как новая подпись на каждую команду.
- Повторять только затронутые/непокрытые проверки. После двух неудачных циклов разбирать общий источник сбоя и предположения об окружении, а не выпускать очередной пакет с одной догадкой.
- `awaiting-professor` блокирует научное решение, а не подготовку checker/runner/UI. Development/test-fixture никогда не становится scientific accepted.

## Маршрут и зависимости

| Порядок | Карточка | Проверяемый результат | Зависимость |
|---|---|---|---|
| 0 | S0 | Восстановлены актуальные владельцы и состояния | До любых правок кода |
| 1 | U5-R1 и D4-R1 | Исправлены график и metadata fixture | Допускаются параллельно по разным файлам |
| 2 | R4-close | Условия R4.1–11 сопоставлены свидетельствам; реальный остаток назван | Проверять изменения U4/U5 по влиянию |
| 3 | D4-F → D4-E | Заморозка выбора и независимая оценка как программные механизмы | D4-R1, принятые D2/D3 |
| 4 | D4-A → D4-I | Checker/admission и связность runtime/sweep/GUI | D4-F/E; научный PASS локально не создаётся |
| 5 | T1 | Переносимый комплект и preflight | Принятые D4/R4 runtime и U4/U5 |
| 6 | T2 | Поэтапные внешние команды и инструкция | T1, D4, runtime contracts |
| 7 | U3-refresh | Актуальная матрица буквального ТЗ и вопросов | После UI-исправления; можно параллельно другим файлам |
| 8 | T3 | Маленькая сквозная цепочка, финальный снимок и handoff | Все необходимые программные задачи и явные gates |
| Далее | E0–E5 | Настоящие внешние данные, модели, сравнение и научный отчёт | Отдельные решения и бюджет |

### S0 — статус и владение файлами

**Файлы:** `docs/current-state.md`, `.superpowers/sdd/2026-10-15-local-completion-and-external-experiments/{ledger.md,locks.json}`; текущие карточки.

- [x] Прочитать короткий актуальный checkpoint и последние решения reviewer; не перечитывать всю историю ради каждой команды. Источник: `verification/local/progress-review-20261018/review.md`.
- [x] Подтвердить отсутствие активных исполнителей/координаторского worker перед передачей locks. Снять новые точечные baseline/hash для изменяемых файлов; исторический P0 сохранить. Снимок: `.superpowers/sdd/2026-10-15-local-completion-and-external-experiments/S0-source-before.json`.
- [x] U5 отмечена как «основная реализация/тесты есть, correction U5-R1 открыта»; D4 phase contract оставлен ACCEPTED отдельно от полного D4; U2 external Adaptive зависит от D4-I.
- [x] Сохранить точный следующий request, source snapshot, reviewer verdict, блокеры и фактическое время реализации/проверки/ожидания в SDD ledger; обновлять после содержательного результата.

**Готово:** один актуальный checkpoint и один владелец каждого write set; не поменялись научные файлы и старые результаты.

**S0 принято 18.10:** текущий checkpoint обновлён; U5-R1 и D4-R1 переданы координатору по непересекающимся locks; reviewer findings и baseline приведены в ledger. На момент передачи вычисления/тесты не запускались.

### U5-R1 — восстановить таблицу и график сохранённых KPI

**Modify:** `apps/NBIoTApp.m`, `tests/TestNBIoTAppDialogs.m` (либо существующий `tests/TestSavedReportOverview.m`, если layout-регрессия точнее относится к нему); при изменении пользовательского поведения — `docs/gui-guide.md`. Один App-владелец; не менять оба теста ради одинаковой проверки.

**Дефект:** около строк 354–359 `savedAxesPanel` помещён во внешнюю строку 6, внутри него создан grid `[1 1]`, но ось повторно получает `Layout.Row=6`. Фиксированные высоты также оставляют таблице/оси слишком мало места.

- [x] Добавить регрессию на parent/строку saved axes и доступную область таблицы/графика после `drawnow`. Проверять фактические размеры/доступность прокрутки на 1280×900 и 1000×700, а не только наличие line data. Тест остаётся на реальном `NBIoTApp`; скрытое окно сохраняет расчёт viewport контейнера.
- [x] Доказать RED на текущем снимке (row=6, table/chart viewport 0 на обоих размерах). Удалено лишнее назначение `Row=6`; доступность таблицы ≥140 px, panel графика ≥200 px и scroll-путь проверены. Данные сохранённого запуска и chartAxes экспорта не менялись.
- [x] Выполнить только выбранный изменённый GUI-класс и `TestSavedReportOverview.m` через bounded runner с ≤300/900: 12/12 и 26/26, оба exit 0; before/after hashes совпали. Дополнительные export-тесты не затрагивались.
- [x] Получить независимый review diff и evidence: SPEC PASS / QUALITY PASS, findings нет. Review: `.superpowers/sdd/2026-10-15-local-completion-and-external-experiments/U5-R1-review/review-report.md`.
- [ ] В отдельный удобный момент открыть существующий 100 UE отчёт **без пересчёта** и сохранить снимки, где читаются и сводка, и таблица/график. До согласованного момента не поднимать окна; визуальный gate остаётся отдельно открытым.

**Review:** независимая SPEC/QUALITY проверка — PASS без замечаний; отчёт: `.superpowers/sdd/2026-10-15-local-completion-and-external-experiments/U5-R1-review/review-report.md`. Визуальный saved-100-UE gate не выполнен и ожидает согласованного момента.

**Готово:** график не в лишней строке, таблица и ось доступны на обоих размерах, связанные данные/контракты U4 сохранены, есть тест и review. Состояние исправления и визуального gate отражены раздельно.

### D4-R1 — актуальная fixture для метаданных Adaptive

**Modify:** `tests/TestResultMetadata.m`, по необходимости `tests/TestModelEvaluationMetrics.m`, `tests/TestLoadModels.m` только для безопасного извлечения общей fixture. **Create:** `tests/helpers/smallLoadTrainingFixture.m`, если она нужна повторно D4-F/E. Production reader `src/+nbiot/+ml/loadModelEvaluationMetrics.m` остаётся строгим; изменение его требований не является способом починить тест.

- [x] Зафиксировать воспроизведение: старый `writeTrainingMetrics` пишет manifest без `load-training-report-v2`, phase и проверяемого evidence, но assertion требует verified.
- [x] Переиспользовать проверенную маленькую development-fixture/настоящий writer либо собрать полную согласованную known-answer fixture нового evaluated-контракта. Все hashes, строки/IDs и phase должны соответствовать сохранённым файлам. Не подделывать candidate provenance/научный review.
- [x] Сохранить positive evaluated, negative missing/unknown phase/hash и selection → unavailable. Не заменять обязательный verified assertion на unavailable для заведомо валидного evaluated-пакета.
- [x] Bounded GREEN: `TestResultMetadata.m` и `TestModelEvaluationMetrics.m`; при извлечении shared fixture добавить затронутый `TestLoadModels.m` отдельным файлом. ≤300 на файл, ≤900 на набор; физические fixtures ≤2 UE. Итог: 4/4 + 14/14 + 20/20, exit 0; 10/10 D4 и 40/40 global hashes unchanged.
- [x] Независимое SPEC/QUALITY review: PASS без замечаний, `verification/local/runtime-review/D4/metadata-fixture-20261018/GREEN-002/review-report.md`. Production-дефектов не обнаружено; ML-контракт не менялся.

**Готово:** известный непройденный metadata test закрыт на актуальном контракте, строгая проверка и научные границы сохранены.

### R4-close — завершить приёмку управления расчётом

**Read:** runtime.md R4.1–12; `verification/local/runtime-review/R4/` accepted process/MATLAB summaries. **Create:** `verification/local/runtime-review/R4/remaining-acceptance-20261018.md`. **Modify:** runtime.md/ledger только по подтверждённому результату. Production/test write set — исключительно для конкретного найденного пробела из исходной карточки, с новым baseline/lock.

- [x] Свести R4.1–11 → точные условия → текущие исходники → сохранённые tests/reviewer decision. Учтены прежние принятые группы и corrected evidence map; blanket reruns не выполнялись.
- [x] Проверить изменения после evidence. Единственный затронутый сценарий — `TestLoadProbe.m` из-за U4-зависимостей; текущий bounded run прошёл 15/15, с 24/24 targeted и 40/40 global hashes unchanged.
- [x] Независимый reviewer принял R4.1–11: SPEC PASS / QUALITY PASS без замечаний. Отчёт: `verification/local/runtime-review/R4/remaining-acceptance-20261018/review-report.md`.
- [x] **R4.12 не читали и не применяли.** Записан статус `blocked-by-owner-scope`; completed/partial/MAT/registry не менялись.

**Итог R4-close:** административная сверка R4.1–11 завершена и принята. Полный R4 остаётся открытым из-за R4.12; `localReady=false`.

**Решение владельца, когда потребуется закрывать полную приёмку:** разрешить конкретный read-only preview либо явно исключить historical accounting из принимаемого объёма. Разрешение preview не разрешает Apply/resume. Не выдавать ограниченный runtime PASS за закрытый R4.12.

### D4-F — заморозка выбора модели и политики

**Create:** `src/+nbiot/+controller/policySha256.m`, `experiments/freezeLoadModelSelection.m`, `tests/TestFrozenModelSelection.m`; общая fixture из D4-R1. **Interfaces:** `freeze=freezeLoadModelSelection(options)` с `selectionFolder,datasetFile,policyFile,protocolFile,registryFile,policyTuningIds,outputFile`; точная schema/ошибки — data-model.md D4. `nbiot.controller.policySha256(policy)` создаётся и принимается **здесь до записи freeze**, поскольку freeze уже содержит этот digest; D4-E/A/I/T1 используют тот же helper, без локальных дубликатов.

- [x] RED и отрицательные проверки для missing/altered manifest, test overlap, evaluated вместо selection, отсутствующих criteria/approval, неизвестных options и повторного output; RED-001 зафиксировал отсутствие entrypoints до реализации.
- [x] Реализовать единый canonical policy digest по фиксированному порядку полей adaptiveDefaults и row-vector нормализации; тест проверяет перестановку полей/ориентацию векторов и изменение digest при изменении threshold. Byte hash policyFile хранится отдельно.
- [x] Реализовать selection → freeze без fit/predict/test: проверить фазу, роли/ID и provenance, artifacts, четыре MAT/sidecars/metrics, policy/approved protocol/registry; выбор по validation с фиксированным tie-break.
- [x] Записать новый freeze JSON через temporary/readback/rename с вычисленным evidenceKind и всеми digests. Selection artifacts байтово неизменны; существующий output отвергается.
- [x] Малый fixture GREEN + неизменность hashes + независимый review. GREEN-005: 5/5, exit 0; 11/11 D4 и 40/40 global paths unchanged; SPEC/QUALITY PASS без замечаний (`verification/local/runtime-review/D4/frozen-selection-20261018/GREEN-005/`). Protocol и результат остаются `test-fixture`, не утверждением преподавателя или научным допуском.

### D4-E — оценка замороженных моделей

**Create:** `experiments/evaluateFrozenLoadModels.m`, `tests/TestFrozenModelEvaluation.m`. **Modify:** только phase/manifest helpers, перечисленные D4, если нужен единый evaluated writer. **Interface:** `report=evaluateFrozenLoadModels(options)` с обязательными `freezeFile,datasetFile,modelFolder,protocolFile,policyFile,registryFile,outputFolder`. Freeze хранит hashes policy/registry без файловых путей, поэтому evaluator принимает их источники явно и сверяет все hashes.

- [x] RED на подмену freeze/protocol/model/data, неразрешённый повтор и попытку сменить победителя по test. Добавлены отдельные регрессии на копию registry, несоответствие caseKey/ID/split до MAT и повтор через копию evaluated dataset; RED-006 и RED-008 воспроизвели два новых обхода.
- [x] Реализовать единственное место test predict с frozen transforms/model/policy; без нового fit. Output — отдельный evaluated-пакет с неизменными MAT/sidecars, metrics, manifest, freeze refs и началом/окончанием открытия test.
- [x] Сохранять выбранную по validation модель. Completed повтор с теми же hashes читает verified существующее evidence; mismatch отказывает; incomplete не accepted. Повтор того же пакета проверен.
- [x] Проверить на development-fixtures положительные пути и подмены; scientific test IDs локально не потреблять. GREEN-010: 13/13, exit 0; 13/13 D4 и 40/40 global paths unchanged; независимый review PASS (`verification/local/runtime-review/D4/frozen-evaluation-20261018/`). Кандидатные/научные test IDs не открывались.

### D4-A — evidence checker и явный научный допуск

**Create:** `src/+nbiot/+ml/checkModelAcceptanceEvidence.m`, `src/+nbiot/+ml/validateModelAcceptance.m`, `experiments/prepareModelAcceptance.m`, `experiments/publishModelAcceptance.m`, `tests/TestModelAcceptance.m`, `docs/model-acceptance-contract.md`. **Consumes:** принятый `nbiot.controller.policySha256(policy)` из D4-F; повторно helper не создавать и его write lock без новой причины не забирать.

**Interfaces:** `report=checkModelAcceptanceEvidence(acceptance,rootFolder)` возвращает `passed,errors,evidenceDigest`; `metadata=validateModelAcceptance(path,modelFile,policy,execution,comparisonIds,cfg)` — публичный допуск с обязательным шестым `cfg`. Сигнатуры prepare/publish, schema и immutable refs брать из полного data-model.md D4, не вводить альтернативный формат.

- [x] Сначала RED: path escape, missing/altered bytes, неполные/пересекающиеся split/role IDs, fixture под scientific label, policy/source/calibration mismatch, protocol после test, stale review, out-of-scope cfg.
- [x] Реализовать чистый checker, policy digest по фиксированному field order, создание candidate metadata и публичный validator. `evidenceKind` выводится из provenance, а не пользовательского флага; candidate/fixture не accepted.
- [x] Publish принимает только явный review accepted/rejected, связанный с тем же evidenceDigest/protocol и реальными scientific evidence. Не переписывает MAT/policy/candidate; нет force/skipScientificReview. Локально реализовать механизм и отрицательные scientific проверки, не публиковать scientific accepted из fixture.
- [x] Подтвердить positive structural/development проверки и обязательные отказы public scientific admission; bounded GREEN-008 и independent review PASS. Реальные thresholds/review/качество ML остаются внешними; D4-A принят только в programming/development-fixture scope.

### D4-I — связность runtime/sweep/GUI, завершение зависимой части U2

**Modify:** `src/+nbiot/+controller/prepareRuntime.m`, `experiments/runComparisonSweep.m`, `src/+nbiot/+experiments/runComparisonCase.m`, `src/+nbiot/+experiments/runtimeManifest.m`, `src/+nbiot/+experiments/validateComparisonAcceptanceScope.m`, `tests/TestComparisonSweep.m`, `tests/TestAdaptiveIntegration.m`, `tests/TestRuntimeManifest.m`; затем по передаче lock `apps/NBIoTApp.m`, `src/+nbiot/+ui/SimulationSession.m`, `tests/TestExternalGuiProfile.m`.

**Итог, 18.10:** независимый reviewer сопоставил все 22 текущих исходных/тестовых пути со снимком и вынес SPEC PASS / QUALITY PASS без замечаний. bounded GREEN: TestExternalGuiProfile.m 10/10 и связанный TestAdaptiveIntegration.m 5/5. D4-I принят в программной/development-fixture области; полный D4, реальные научные свидетельства и external admission остаются открыты.

- [x] Передать `modelAcceptanceFile` и полный `controllerPolicy` через существующие интерфейсы; whitelist не расширять чужими флагами. Внешний actual-run проходит admission до runner/PHY/registry, даже с injected runner. Предусмотренный планом обход `runExperimentFcn` удалён; local development injection сохранён как тестовый транспорт.
- [x] Включить acceptance/policy/evidence hashes в runtime identity до reuse/resume. Изменение допуска запрещает повторное использование старого результата.
- [x] Сохранить local development с явным allowDevelopmentModel и пределом 10 UE; fixtures ≤2 UE. External candidate/fixture/missing evidence остаются закрытыми; GUI opt-in не предоставляет external capability.
- [x] GUI передаёт полный допуск; неполный external budget отклоняется до создания factory; нормализованные active IDs проходят без изменения. Положительный local-development и отрицательные external пути проверены без научного допуска.
- [x] Bounded GUI/integration selections прошли; независимая SPEC/QUALITY review полного 22-путевого снимка — PASS без замечаний (verification/local/runtime-review/D4/runtime-integration-20261018/final-stage2-review-001/review-report.md). При отсутствии approved real evidence внешняя capability остаётся blocked; научная приёмка не создаётся локально.

### T1 — переносимый комплект и preflight

**Modify:** `experiments/prepareExternalRun.m`, `tests/TestExternalRunPackage.m`. **Create:** `verification/external/validateExternalPreflight.m`, `tests/TestExternalPreflight.m`.

**Итог, 19.10:** T1 принят по независимому ревью (**SPEC PASS / QUALITY PASS**, без находок). Итоговые bounded fixtures: `TestExternalPreflight.m` 13/13 и `TestExternalRunPackage.m` 17/17; программная приёмка не означает scientific acceptance, `localReady` или разрешение внешнего запуска. Отчёт: `.superpowers/sdd/2026-10-15-local-completion-and-external-experiments/T1-review-report-final-20261019.md`.

- [x] RED на одиночный переименованный MAT без sidecar и на недоступные/подменённые обязательные refs.
- [x] Копировать полный D2/D4 evidence по refs с исходными basename, включая model/sidecar/metrics/manifest/freeze/evaluation/acceptance/policy/protocol/registry/source/calibration. Static draft разрешён без модели; большие данные — проверяемый явно подключённый каталог.
- [x] Все нормализованные refs остаются внутри package root. Вычислительные `.m` сохранять байтово: sanitation только generated configs/docs, без незаметного изменения accepted source.
- [x] Preflight возвращает `passed,readiness,errors,sourceDigest,inputDigests`; раздельны software-ready, stage-ready, scientific-accepted. Read-only не резервирует IDs и не запускает расчёт.
- [x] Переместить в temp путь с пробелами, убрать старый checkout из test path; проверить refs/digests и tamper отказ до runner. Bounded GREEN + независимый review. Полный реальный маленький путь проверяется дополнительно в T3.

### T2 — внешние этапы без самопроизвольного запуска

**Create:** `verification/external/runExternalStages.ps1`, `verification/external/testExternalStages.ps1`, `verification/external/external-stages.schema.json`, `verification/external/runExternalStage.m`, `tests/TestExternalStageDispatch.m`, `docs/external-runbook.md`. **Modify:** `experiments/prepareExternalRun.m` только после T1 handoff.

- [x] Реализовать whitelist команд/args, `stages.json`, hashes входов/выходов, dependency/budget/worker gates. Default inspect/no-execute; один Execute — одна стадия, без автоматического перехода к следующей и без второго scheduler.
- [x] Поддержать validate → pilot → data → assemble → train selection-only → freeze → evaluate → admit → compare → summarize. validate/pilot не требуют уже выполненного pilot; data/compare требуют измеренные ресурсы и явный бюджет. admit не вызывается автоматически из evaluate.
- [x] Completed повтор при тех же входах — no-op; изменённые входы — stale с новым output, старое не стирать. Interrupted использует разрешённый R4 путь, не ручную правку JSON. Реестр резервируется только после Execute/preflight.
- [x] Process-only stub tests ≤30 с/сценарий и ≤300 с/файл, MATLAB dispatch tests через bounded runner; проверить bootstrap, missing budget/dependency, stale hashes, active worker, incomplete marker, repeat, fixture rejection и общую scenario identity методов. Дополнительно закрыты повторные вызовы downstream после того, как pilot/admit уже стали stale.
- [x] Runbook простыми словами: необходимые входы, команды, inspect/cancel/resume, критерии завершения и перечень возвращаемых преподавателем файлов. Для UTC identity указан `pwsh` / PowerShell 7.5+. Самому ничего не отправлять и большие стадии не запускать.

**Итог T2, 19.10:** независимые **SPEC PASS / QUALITY PASS**, находок нет. Итоговая bounded-процессная проверка — 36/36 PASS; PowerShell parser — 2/2. Независимый отчёт и snapshot 11 файлов: `verification/local/runtime-review/T2/external-stages-20261019/review-report-stale-transitive-final-20261019.md`. Проверки используют process stubs; реальные внешние стадии и MATLAB в рамках финального review не запускались. T2 исходники переданы в read-only freeze.

### U3-refresh — решения по буквальному ТЗ

**Modify:** `docs/requirements-decisions.md`, относящаяся матрица `docs/section-50-readiness.md`; UI source только после отдельного принятого решения U3a.

- [x] После принятия U1/U2/U4/U5 сверить фактически готовые поля/функции с требованиями профиля и App Designer по текущему GUI и конфигурациям.
- [x] Обновить вопросы о допустимости программного `uifigure` вместо `.mlapp`, доступности полей, масштабе профиля и фиксированных PHY параметрах; решения, ответы и источники не подставлять.
- [x] Сохранить остальные вопросы о численных thresholds/selection protocol, матрице/повторах/IDs, обязательности 5000 UE, внешнем компьютере и бюджете как `awaiting-professor`.
- [x] UI source не менять до отдельного принятого решения U3a. Владелец 19.10 подтвердил оставить вариант 2 остановленным; не возобновлять его по этому плану.

**Итог U3-refresh, 19.10:** `requirements-decisions.md` и `section-50-readiness.md` пересверены по текущему исходнику и после U1/U2/U4/U5. Локальные лимиты, базовый профиль, доступные/фиксированные UI поля и формат `uifigure` описаны; визуальный осмотр экрана и четыре решения преподавателя остаются открытыми. Сообщений преподавателю не отправляли, GUI-код не меняли.

### T3 — короткая настоящая цепочка и один итоговый комплект

**Create:** `tests/TestLocalCompletionPipeline.m`, `verification/local/implementation-20261015/local-completion.json`, `docs/local-completion-handoff.md`; дополнительные bounded stage-классы только если одна цепочка не укладывается в 300 с. **Modify:** `docs/current-state.md`, `docs/section-50-readiness.md`, относящиеся команды `README.md`.

- [x] Перед стартом сверить все приёмочные условия, статус R4.12 и решение по принимаемому объёму. Не исключать обязательное условие молча ради true. Проверено 19.10: R4.12 остаётся обязательным и `blocked-by-owner-scope`; условия из объёма не исключены, readiness будет сохранён как `false`.
- [x] Выполнить три маленьких настоящих Static случая с тремя различными разрешёнными development IDs → export/verify → D3 dataset. Сделать отдельно помеченный производный development-fixture с целыми IDs по train/validation/test; сохранить provenance и перечень тестовых преобразований, исходные cases/registry не подменять. T3 core GREEN: 1/1, 3 кейса, IDs 1037–1039, diagnostics complete; отчёт `T3c19/pipeline-report.json`, последнее core evidence `verification/local/runtime-review/T3/GREEN-core-010-20261019/`.
- [x] Fixture обучение → local Adaptive с явным разрешением → перенос комплекта/проверка reader/preflight; fixture отклонён external admission. Package-only GREEN 1/1: `verification/local/runtime-review/T3/GREEN-package-only-004-20261019/`; пакет и перемещённая копия сверены по manifest. Без больших нагрузок, настоящей научной оценки или замены PHY заглушкой.
- [x] При разбиении на bounded файлы стадии связаны одной identity и hashes; итоговые изменения документации проверяются package-only без повторной симуляции или обучения. Runner reports относятся к сохранённым запускам, а не к текущему запуску.
- [x] Свести F1–F12 и тематически относящиеся к ним требования исходного аудита к реализации/тесту/reviewer/оставшемуся решению. Crosswalk записан в completion manifest и помечен как тематический вывод; прямые §22 для F8 и §§11/30/46 для F10 цитируются из аудита. Отдельные статусы всех 27 условий §50 сохранены. Не проводился ещё один полный аудит с нуля.
- [x] Финализировать документацию передачи, пересобрать portable package по source digest и проверить перемещённую/распакованную копию через bounded package-only. Фактические путь, digest, hashes и отчёт находятся в completion manifest; не переупаковывать ради даты.
- [x] Получить независимый read-only follow-up на исправленные документы и package snapshot: **SPEC PASS / QUALITY PASS**, без новых замечаний (`verification/local/runtime-review/T3/final-review-20261019/review-report-addendum.md`). Ограничения научного/внешнего допуска остаются явно записанными; актуальные хеши находятся в completion manifest.
- [x] Сверить комплект с первоисточником и упаковать карту трассировки: package-only #009 подтвердил 27 source-manifest файлов, JSON-аудит и его hash в ZIP/transfer copy, reader PASS; отчёт `verification/local/runtime-review/T3/GREEN-package-only-009-20261019/package-verification.json`. PDF остаётся в корне рабочей копии и указан по SHA-256, но не входит в portable execution package.
- [x] Проверить итоговую редакцию handoff-документов и переносимый набор: package-only #011 — 1/1 за 38,91 с; 27 source-manifest entries, 470 payload + manifest, transfer reader PASS; source digest `cfd5f62d3c10816f768b76640d21619f83516771264d2813c0ef09afb1a07302`, ZIP SHA-256 `16e820501d2dc590ab4e52b6ddf8918ffe73b5330434cc2d401c80ff784bbb9b`, handoff SHA-256 `39265904840184031f2b7c6be097f91c489025c0c803b4e92faf9414dd7acbdf`. Полный отчёт `verification/local/runtime-review/T3/GREEN-package-only-011-20261019/package-verification.json`.
- [x] Независимый reviewer принял integration, трассировку и передачу: **SPEC PASS / QUALITY PASS**, открытых findings нет. 27/27 исходных entries, 458 non-MAT files, 65/65 разделов, 27/27 критериев §50; 12 MAT не читались и отдельно не хешировались. Отчёт `verification/local/runtime-review/T3/final-review-post-audit-20261019/review-report.md`. `localReady=false` и научные gates сохранены.
- [x] После RED #022 исправлена проверка нормализации абсолютного evidence path; package-only #024 прошёл 1/1 за 31,0417108 с. Независимый reviewer подтвердил точный source digest `0704db2b473ed2795e076703abee144229310625044504c8b70a46a1321b1f20`, ZIP SHA `40c0aeb824eaf5cf81649ea17237993297df50771bc54855125955bbfe98c6cd`, handoff SHA `6c14604782cc61cafd163bad24ac7daf1c5e714c61d991062d96593ef51b3ea5`, 27/27 manifest entries, package membership, non-MAT hashes, unchanged core evidence и pending-review assertions: `SPEC PASS / QUALITY PASS`, существенных findings нет. Отчёт `verification/local/runtime-review/T3/package-identity-review-0704db2b473e.md`. Приёмка относится к #024 и не закрывает полный ТЗ; все четыре readiness-флага остаются false.
- [x] После дополнительной сверки материалов package-only #025 прошёл 1/1 за 31,5687795 с. Независимый reviewer подтвердил source digest `6312a7479b5069a62d7481e1a5c8213b5bab1383429cd3b70aa9b71d88e7d1c3`, ZIP SHA `9a31757ff26706778885fa04e71a51e70ffbe061c95620c3aa815c4a215a59b7`, handoff SHA `b82a1e2d43ff20789bd19678f8b8ad3976b3ba6eba43fab77c246fec538ffa87`, 27/27 manifest entries, 384 codeFiles, 459 non-MAT hashes, 65/65 разделов и 27/27 критериев §50: `SPEC PASS / QUALITY PASS`, существенных расхождений нет. Отчёт `verification/local/runtime-review/T3/package-identity-review-6312a7479b50.md`. Readiness остаётся false; эта package-only приёмка не закрывает полный ТЗ.

**Правила готовности:** успешная маленькая цепочка сама по себе не закрывает обязательные открытые R4/D4/T1/T2 условия. `engineeringCoreReady=true` — только после всех обязательных инженерных проверок принятого объёма. Если R4.12 остаётся обязательным и запрещённым, сохранить false и назвать причину; альтернативное исключение из объёма требует решения владельца. При одном pending U3 инженерное ядро может быть готово, но `localReady=false`. Научный finalAcceptance не становится true от fixtures.

## Что делать после локальных исправлений — внешний маршрут

Эти пункты входят в будущую передачу, **не являются разрешением на запуск здесь**.

| Этап | Действие и проверяемый выход | Кто/что разрешает |
|---|---|---|
| E0 | Утвердить профиль/GUI по ТЗ, матрицу/ID/повторы, научные thresholds/selection protocol, компьютер и бюджет; вернуть решения в журнал | Владелец/преподаватель; без выдуманных значений |
| E1 | На целевом ПК свежие source/toolbox/preflight/Stage2 → ограниченный resource pilot; сохранить фактические время/память и новый budget | Явно разрешённый внешний validate/pilot, без переноса старого лимита 16 часов |
| E2 | По принятой матрице завершённые cases и реестр → D3 assemble с проверяемым происхождением/диагностикой | Доступный утверждённый внешний бюджет и независимые ID |
| E3 | Selection-only train/validation, настройка policy только на разрешённых IDs, freeze модели/policy/protocol → одно независимое test evaluation | Protocol утверждён до открытия test; изменение после test требует нового научного цикла/IDs |
| E4 | Научный review реальных evidence → явный accepted/rejected acceptance без изменения MAT; при rejection compare закрыт | Научный руководитель/ответственный человек, не технический reviewer |
| E5 | Static/Adaptive-P/Adaptive-RA/DT на согласованных независимых final-comparison IDs и общих scenarios → интервалы неопределённости/ограничения → научный отчёт и сдача | Accepted evidence, scope и бюджет; публикация/отправка отдельно разрешаются владельцем |

После внешнего этапа вернуть не только графики, но dataset/artifacts/registry manifests, source/calibration digests, freeze/evaluation/acceptance/review, сравнения и отчёт. Только тогда обсуждать научную завершённость; существующий пример 100 UE с 6 доставками сам по себе её не доказывает.

## Первая команда будущего исполнения

> Продолжи редакцию 18.10 единого плана по remaining-work-20261018.md. Сначала S0, затем U5-R1 и D4-R1 по непересекающимся locks; старые принятые задачи не повторяй. После точечных исправлений сведи R4 и выполни полный D4, T1, T2, T3 по зависимостям. Сохраняй фоновый режим, лимиты, независимый review и различие инженерного PASS/научного допуска. R4.12 не читать/Apply/resume без отдельного решения; U3/научные ответы не подставлять. Заверши доступную проверяемую работу и честно зафиксируй обязательные gates.

Подготовка плана завершена. **Владелец 19.10 дал команду запустить исполнение и доделать ТЗ:** продолжать с ближайшего незакрытого результата, не ждать ещё одного разрешения на обычные изменения и bounded-проверки. Не начинать сначала и не завершать новую команду отчётом о старой подготовке плана. Материальные внешние действия и решения выполняются только в сохранённых границах выше.
