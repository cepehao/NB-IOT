# D1–D4: данные, модель и проверяемый допуск

> **For agentic workers:** выполнять по `superpowers:subagent-driven-development` или `superpowers:executing-plans`, с отдельной проверкой reviewer. Этот файл — план, не разрешение запускать MATLAB. Все MATLAB-запуски передавать coordinator как запрос с командой и ожидаемым результатом.

**Goal:** закрыть F6/F7/F8/F4 программно, сохранив независимость научной приёмки от технической исправности.

**Architecture:** каноническая схема задаётся кодом; dataset хранит признаки отдельно от истины и диагностики. Обученный MAT и его sidecar неизменяемы; отдельный acceptance JSON связывает модель, исходные данные, критерии, политику и человеческую рецензию. Не добавлять сервисы реестра моделей.

**Tech Stack:** существующие MATLAB tables/MAT/JSON, Statistics and Machine Learning Toolbox, PowerShell bounded runner.

**Spec:** `docs/project-audit-2026-10-15.md` F4/F6/F7/F8; основной план в соседнем `.md`; ТЗ §21–26,40–41.

## Общие ограничения и фактические точки входа

- Прочитать корневой `AGENTS.md`; исторический вариант 2 остановлен. Только coordinator запускает MATLAB; ≤10 UE, ≤300 s/case, ≤900 s/suite, `local-development`, `hard-stop`.
- Не менять физику, 500 ms окна, текущие 15 predictor features или научные параметры ради срока теста.
- Все перечисленные ниже новые функции помечены «создать». Остальные вызовы существуют на 15 октября: `nbiot.dataset.featureSchema(version)`, `assembleLoadDataset(resultFiles,splitManifest)`, `nbiot.ml.trainLoadModels(data,options)`, `validateModelBundle(bundleOrFile,schema)`, `loadModelEvaluationMetrics(modelFile,bundle)`, `nbiot.controller.prepareRuntime(cfg,execution,options)`, `runComparisonSweep(options)`, `nbiot.experiments.runComparisonCase(cfg,method,caseFolder,options)`.
- Реальный конструктор — `nbiot.NBIoTSimulator(cfg,scenario,execution,controllerOptions)`. Функции `configureAdaptive` в текущем коде нет; не создавать параллельный способ конфигурации.
- `validateExecutionBudget` не принимает произвольные поля: evidence context не добавлять внутрь execution. `prepareRuntime` получает cfg отдельно; проверку scope проводить по cfg, а проверку всех comparison IDs — перед sweep.
- На исправление D1, затем D2 выделить одного исполнителя: оба меняют `trainLoadModels.m`. D3 начинается после R1 и D1: общие точки — metrics-contract и TestLoadDataset; после этого D3 можно выполнять параллельно D2 без совместного редактирования файлов. D4 начинается после D2, а его интеграционная приёмка — после D3 artifacts/diagnostics. D4 получает исключительное владение ML reader/writer и их тестами от D2; интеграцию с упаковкой выполняет один назначенный владелец файла. Reviewer не редактирует файлы исполнителя.
- Активное время: D1 2–3 ч; D2 4–5 ч; D3 5–7 ч; D4 10–14 ч; независимая рецензия 2–3 ч. Итого 23–32 agent-hours, без ожидания MATLAB и внешней науки. Это оценка труда, не длительность физического эксперимента.

## D1 — каноническая схема, F6 (2–3 ч)

**Modify:** `src/+nbiot/+dataset/featureSchema.m`, `src/+nbiot/+ml/trainLoadModels.m`, `src/+nbiot/+ml/validateModelBundle.m`.

**Test:** `tests/TestLoadModels.m`, `tests/TestLoadDataset.m`.

**Контракт:** `featureSchema('bs-known-v2.0')` возвращает дополнительные поля `keyNames=observationNames(1:4)`, `inputNames=observationNames(5:end)`, `targetName='meanRaUe'`. Старый `static-v1.0` остаётся читаемым dataset, но не принимается для нового обучения/импорта текущего predictor. Никакие поля переданного `data.schema` или второго аргумента `validateModelBundle` не могут расширять whitelist.

Точный порядок входов:

```matlab
{'detectedCandidates','meanPeakMetric','maxPeakMetric','meanRxEnergyW', ...
 'ulTbDecodes','ulCrcFailures','rarSent','grantsSent','pendingRequestsMean', ...
 'ulRaOccupancy','ulDtOccupancy','dlRaOccupancy','dlDtOccupancy', ...
 'accessProbability','raShare'}
```

- [ ] Добавить тест непосредственно в `TestLoadModels`, где уже есть локальный helper `smallTrainingFixture()`:

```matlab
function cannotAuthorizeTruthByRewritingSchema(t)
    data=smallTrainingFixture();
    data.features.trueCollision=zeros(height(data.features),1);
    data.schema.inputNames=[data.schema.inputNames,{'trueCollision'}];
    t.verifyError(@() nbiot.ml.trainLoadModels(data,mlTrainingDefaults()), ...
        'nbiot:ml:FeatureSchema');
end
```

- [ ] Добавить отрицательные варианты в этот же класс: переставлены 2 канонические колонки и схема; добавлен `realizationId` одновременно в features/schema; удалена одна колонка одновременно в обоих местах; `keyNames` подменён на `{'windowId'}`. Все должны отказать `nbiot:ml:FeatureSchema` до fit.
- [ ] В существующем тесте `fourModelsTrainUseTrainOnlyTransformsAndReload` после обучения взять первый bundle, заменить `featureNames{1}='trueCollision'`, одновременно заменить `schema.inputNames{1}`; `validateModelBundle(bundle,schema)` обязан отказать `nbiot:ml:FeatureSchema`. Не обучать новые четыре модели для каждого варианта.
- [ ] Coordinator выполняет RED request для `TestLoadModels.m`; сохранить точную ошибку, не считать toolbox absence ожидаемым RED.
- [ ] Убрать доверие к переданной схеме: получить canonical из `featureSchema()`, проверить equality version/keyNames/inputNames/targetName; при неизвестной версии отказать. Сравнивать нормализованные row-cellstr; затем назначать локальную schema=canonical. Второй аргумент `validateModelBundle` оставить совместимым, но рассматривать как утверждение, которое надо проверить против canonical.
- [ ] В `manifestMatches` дополнить обязательное сравнение `dataKind` для нового sidecar writer из D2. Для старого sidecar без поля не выдавать новый provenance: старый development импорт возможен по старому контракту, но admission запрещён.
- [ ] Проверить, что `predictLoad` продолжает выбирать только canonical входы; не давать diagnostics попасть в `data.features`.
- [ ] Coordinator GREEN request:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestLoadModels.m','tests/TestLoadDataset.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** одновременная подмена metadata + таблицы не обходит whitelist; текущая модель переоткрывается; historical dataset читается без выдуманных шести новых полей. **Escalate:** реальные старые fixtures полагаются на неканонический порядок — исправить fixtures, не ослаблять проверку; MATLAB/toolbox timeout передать coordinator без увеличения бюджета.

## D2 — целостность оценок и происхождение, F7 (4–5 ч)

**Modify:** `src/+nbiot/+ml/trainLoadModels.m`, `src/+nbiot/+ml/loadModelEvaluationMetrics.m`, `experiments/trainLoadModels.m`, `configs/mlTrainingDefaults.m`.

**Test:** `tests/TestModelEvaluationMetrics.m`, `tests/TestLoadModels.m`, `tests/TestModelInfoFormatting.m`.

**Новый training manifest:** `formatVersion='load-training-report-v2'`; прежние поля сохраняются. D2 реализует `phase='evaluated'` для текущего трёхгруппового development пути. D4 после передачи владения добавляет `phase='selection'` по контракту ниже; три score splits обязательны только для evaluated, а не selection. Добавить `metricsFile='metrics.csv'`, `metricsSha256`, `metricsRowCount`; `splitEvidence` — массив ровно из трёх объектов `{split, ids, sampleCount, idCount}`. Значения вычислять из реально переданных `data.rowInfo`, а не из options. IDs — целые 0..3999, отсортированные, уникальные; `idCount=numel(ids)`, `sampleCount` — число строк группы. Группы строго train/validation/test, без пересечений. Таблица metrics содержит ровно одну строку на каждую пару (model,split), включая baseline trainMean; неизвестные split/дубликаты — весь результат unavailable.

**Происхождение:** в `mlTrainingDefaults` добавить `datasetFile=''`. Wrapper `experiments/trainLoadModels.m` принудительно ставит этот путь в trainingOptions после выбора datasetFile. Core перед fit повторно загружает этот файл и проверяет `isequaln(loaded.data,data)`, если путь задан; запрещает candidate-training без пути. Из файла получать байтовый SHA-256; не хешировать сериализованный MATLAB struct и не доверять полю внутри data. Добавить в report/manifest `datasetFile` (basename), `datasetSha256`, `datasetManifestFile='dataset-manifest.json'`, `datasetManifestSha256`, `sourceSha256`, `calibrationSha256`, `allocationsVerified`, `dataKind`. Копировать исходный `manifest.json` dataset в output как `dataset-manifest.json`; сверить его assignments/inputs/kind с загруженным data.manifest. Development-fixture при прямом in-memory вызове может иметь пустое dataset evidence, но никогда не проходит D4. Model sidecar получает `dataKind` и `allocationsVerified` из bundle.

Не копировать большой dataset автоматически в model folder. Внешний комплект обязан содержать dataset.mat в evidence каталоге по ссылке acceptance. D2 loader проверяет небольшой training/dataset manifest и metrics; D4 дополнительно проверяет реальный dataset и исходные completion evidence.

- [ ] Перед изменением reader расширить helpers `writeModelFixture`/`writeMetrics` в `TestModelEvaluationMetrics`: fixture bundle содержит modelName и IDs `[11 12]`, `21`, `31`; training manifest v2 содержит те же списки и splitEvidence counts `[2 1 1]`. `writeMetrics` после `writetable` записывает реальный hash CSV в manifest. Существующий UI wrapper `nbiot.ui.loadModelEvaluationMetrics` оставить делегатом core.
- [ ] Добавить конкретный RED тест, использующий эти helpers:

```matlab
function changedScoreIsNotVerified(t)
    folder=tempname; mkdir(folder);
    t.addTeardown(@() removeFolder(folder));
    modelFile=writeModelFixture(folder); writeMetrics(folder);
    scores=readtable(fullfile(folder,'metrics.csv'));
    scores.mae(1)=scores.mae(1)+1;
    writetable(scores,fullfile(folder,'metrics.csv'));
    bundle=struct('modelName','linearRegression', ...
        'trainingIds',[11 12],'validationIds',21,'testIds',31);
    t.verifyEmpty(nbiot.ml.loadModelEvaluationMetrics(modelFile,bundle));
end
```

- [ ] Дополнить отдельные negative tests: CSV другой модели; дублированный train; отрицательный MAE/RMSE; NaN/Inf; дробный/нулевой sampleCount; idCount не равен длине ids; ids отличаются от bundle; ID пересекается между splits; отсутствует test; дублированный modelName/artifactFile в manifest. Для проверок содержания после порчи CSV обновлять metricsSha256 helper-ом: иначе проверится только hash branch. Старый v1 без CSV hash даёт empty table, не verified.
- [ ] Reader возвращает строго три строки в порядке train/validation/test либо текущую пустую таблицу; не фильтрует плохие строки, оставляя хорошую часть. Проверить все строки/уникальность всего CSV, затем выбрать модель; ровно одна запись model/hash/file в manifest. MAE/RMSE ≥0; integer sampleCount/idCount; sampleCount≥idCount; rmse≥mae с допуском `1e-12*max(1,rmse)`.
- [ ] Writer сначала пишет metrics.csv, закрывает файл, вычисляет hash, потом пишет training-manifest.json. Hash MAT и sidecar должны соответствовать оригинальным именам; переименование при упаковке не допускается без согласованного rewrite manifest.
- [ ] Сверить counts/ids с bundle, splitEvidence, dataset manifest assignments и `data.rowInfo`; никакого доверия только флагу allocationsVerified. В training validate требовать точное равенство множества assignments и реально использованных IDs, не только присутствие каждого использованного ID.
- [ ] Coordinator выполняет RED/GREEN только для затронутого набора:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestModelEvaluationMetrics.m','tests/TestModelInfoFormatting.m','tests/TestLoadModels.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** изменённый score никогда не отображается verified; корректная модель по прежнему загружается даже при unavailable metrics в development. **Escalate:** hash mismatch исправлять по происхождению, не пересчитывать manifest поверх неизвестных результатов. Candidate training data без исходного manifest нельзя объявлять доказанными.

## D3 — оконная diagnostics dataset, F8 (5–7 ч)

**Create:** `src/+nbiot/+dataset/windowDiagnostics.m`, `tests/TestDatasetDiagnostics.m`.

**Modify:** `src/+nbiot/NBIoTSimulator.m`, `src/+nbiot/+results/saveResult.m`, `src/+nbiot/+results/verifyCase.m`, `src/+nbiot/+dataset/assembleLoadDataset.m`, `experiments/buildLoadDataset.m`, `src/+nbiot/+dataset/summarizeLoadDataset.m`, `tests/TestLoadDataset.m`, `tests/TestExport.m`, `tests/TestRadioDiagnosticsExport.m`, `docs/metrics-contract.md`.

**Ownership:** D3 эксклюзивно меняет NBIoTSimulator.m и saveResult/verifyCase; дождаться R1 и D1, включая передачу metrics-contract/TestLoadDataset и сохранения. UI U1 начинается после D3. Не изменять физический event scheduling или вызовы receiver. Диагностику вычислять после получения исходов, никогда не подавать контроллеру.

**Контракт:** `rows=nbiot.dataset.windowDiagnostics(cfg,packets,attempts,truthEvents,observedEvents,receptionEvents,actualTick,windowKeys)` — новая чистая функция; её входы уже доступны в `NBIoTSimulator.result()`. Один проход индексации событий, groupby по ключам, затем O(N log N + W) агрегация; нельзя вызывать полную radioDiagnostics по всем историческим событиям для каждого окна. Использовать два индексных отображения occasionId→readyTick и attemptId→occasionId, уникальные пары/группы определять один раз. Никакого PHY, RNG или новых симуляций.

`data.diagnostics`: **ровно одна строка на окно каждого случая**, ключ `(caseKey,realizationId,windowId,startTick,endTick)`. До сохранения отдельного случая caseKey хранится в marker и добавляется assembler. Dataset `diagnostics.csv` включает все пять ключей. `manifest.diagnosticsSchemaVersion='window-diagnostics-v1'`. Features остаются прежними 15; диагностика не находится в observations.

| Поле | Точное определение для окна s=startTick,e=endTick |
|---|---|
| logicalCollisionGroups | Число групп `(occasionId,nInit)` с ≥2 Msg1 attempt IDs, у которых receiver readyTick принадлежит `(s,e]`; считать каждый group ровно один раз |
| logicalCollidingAttempts | Число уникальных attemptId в этих группах |
| physicalOverlapPairs | Число уникальных `(occasionId,min(attemptIdA,attemptIdB),max(...))` из `nprach_overlap` с подтверждённой полной occasion и receiver readyTick в `(s,e]` |
| physicalCollidingAttempts | Число уникальных attemptId в этих физических парах; не потерянные пакеты |
| successfulAccesses | Число attempts со status=success и endTick в `(s,e]` |
| raRetryTransmissions | Для каждого packetId попытки сортируются по `(startTick,attemptId)`; все кроме первой считаются повторами, если startTick в `[s,e)` |
| meanDelayTicks, delaySampleCount | Среднее `deliveredTick-createdTick` среди delivered packets с deliveredTick в `(s,e]`; count этих пакетов |
| unfinishedAccessCohort | Число attempts со startTick в `[s,e)`, не завершившихся к actualTick; это outcome к export horizon, а не знание контроллера на endTick |
| unfinishedPacketCohort | Число packets с createdTick в `[s,e)`, status unfinished к actualTick |
| logicalAvailable,physicalAvailable,accessAvailable,retryAvailable,delayAvailable | При доступном журнале counts=0 означает true/0; отсутствующая обязательная структура → false/NaN; delaySampleCount=0 → delayAvailable=false, meanDelayTicks=NaN |
| outcomeHorizonTick | actualTick; явно объясняет позднюю классификацию cohort |

Обязательный windowKeys — таблица `result.dataset.observations(:,result.dataset.schema.keyNames)` после создания result.dataset. Строки diagnostics создавать строго по этим ключам в том же порядке, без самостоятельного разбиения actualTick на окна. Проверить уникальность ключей, realizationId, целые startTick/endTick, `0<=startTick<endTick<=actualTick`; пустые keys дают типизированную таблицу нулевой высоты. На paused actualTick=750 observations закрыты только до500: одна diagnostics строка; на paused actualTick=250: ноль строк. Терминальное неполное окно допускается только если уже присутствует в экспортируемых observation keys и совпадающих target keys; не создавать partial observations/targets или диагностику для ещё не закрытого окна. Для полностью завершённого case actualTick=cfg.simulation.durationTicks. Receiver completion в tick=500 относится к первому окну; старт retry в tick=500 — ко второму. Нулевой receiver readyTick не принадлежит `(0,500]`: для текущей PHY такой завершённой occasion быть не должно, malformed fixture с ней отклонять. EndTick не означает, что модель получила diagnostic truth.

Фактические источники: observed `nprach_detection` содержит occasionId/readyTick/candidates и пишется в obj.currentTick; reception `nprach_component` и `nprach_overlap` пишутся в тот же tick. Truth `msg1` содержит attemptId/ueId/occasionId/nInit. attempts содержит packetId/startTick/endTick/status; packets содержит createdTick/deliveredTick/status. Не выдумывать события packet_delivered или методы WindowAccumulator: их наличие не требуется.

- [ ] Создать TestDatasetDiagnostics с синтетическими struct arrays, не waveform: cfg=defaultConfig, numUE=2,durationTicks=1000; два packets, три attempts одного packetId со startTick `[0 499 500]`, одна success с endTick=500, два msg1 одной occasion/nInit и receiver readyTick=500; overlap пара `(1,2)` в tick500. Вторая occasion readyTick=1000 имеет одну попытку без collision. Ожидается в двух строках logicalGroups `[1;0]`, physicalPairs `[1;0]`, successes `[1;0]`, retries `[1;1]`. Packet deliveredTick=500, createdTick=10 даёт delay `[490;NaN]`, delaySampleCount `[1;0]`.
- [ ] Ниже прямые assertions после построения этих аргументов; это новый API, реализовать его в этой задаче:

```matlab
windowKeys=table(repmat(cfg.simulation.realizationId,2,1),[1;2],[0;500],[500;1000], ...
    'VariableNames',{'realizationId','windowId','startTick','endTick'});
rows=nbiot.dataset.windowDiagnostics(cfg,packets,attempts,truth,observed,reception,1000,windowKeys);
t.verifyEqual(rows.windowId,[1;2]);
t.verifyEqual(rows.logicalCollisionGroups,[1;0]);
t.verifyEqual(rows.physicalOverlapPairs,[1;0]);
t.verifyEqual(rows.raRetryTransmissions,[1;1]);
t.verifyEqual(rows.successfulAccesses,[1;0]);
t.verifyEqual(rows.meanDelayTicks(1),490);
t.verifyTrue(isnan(rows.meanDelayTicks(2)));
t.verifyEqual(rows.delayAvailable,[true;false]);
```

- [ ] Добавить три явных key-driven regression tests: paused actualTick=750 с keys только `[realizationId,1,0,500]` даёт ровно одну строку; paused actualTick=250 с typed empty keys даёт ноль; terminal partial horizon использует фактически экспортированные observations keys и даёт ровно столько же строк с теми же endTick. Если partial ключ отсутствует, diagnostics его не создаёт. Во всех случаях unfinished cohort оценивается на actualTick, а interval outcomes сохраняют определения `(s,e]` / `[s,e)` из таблицы, не расширяются до actualTick автоматически.
- [ ] Negative cases: reversed duplicate physical pair → `nbiot:dataset:Diagnostics`; duplicate attemptId; duplicate occasion detection; pair references missing attempt; inconsistent readyTick/component tick; missing packetId → retry unavailable, а не ноль; missing receiver source → physical unavailable; completed empty source → physical zero. Attempts, не завершившиеся на горизонте, не включать в successes. Пара с readyTick>actualTick не переносится в последнее окно.
- [ ] Добавить вызов windowDiagnostics в `NBIoTSimulator.result()` строго после создания `result.dataset` с observations/targets/schema и после получения packets/attempts/obs/truth/radioReceptionLog. Извлечь обязательные windowKeys из `result.dataset.observations(:,result.dataset.schema.keyNames)`, проверить совпадение с target keys, передать их последним аргументом; результат сохранить `result.dataset.diagnostics`. Использовать существующий result cache, не пересчитывать при каждом refresh. Строить на уже находящихся в памяти данных один раз; не создавать копии full waveform.
- [ ] `saveResult`: добавить отдельную top-level `datasetDiagnostics` в MAT и `_diagnostics.csv` export. Добавить schema descriptor в marker, файл в exportFiles и marker.files; `verifyCase` проверяет exact колонки, числовые значения, уникальность и 1:1 ключи с observation/target, checksum и строковые counts. Старые markers без diagnostics признаются историческими, но не подтверждают §22. Для новых полных evidence diagnostics обязательны. Согласовать tableExportVersion с владельцем ранних изменений сохранения; выделить новый version=5, сохраняя старые 1..4 пути.
- [ ] `assembleLoadDataset` читает только `_diagnostics.csv` после verifyCase; сортирует по четырём оконным ключам, требует их точное совпадение с obs, затем добавляет caseKey. Нельзя outerjoin, forward-fill или повторять case summary. Старый case без diagnostics: строить строки с правильными ключами, NaN/false и manifest.diagnosticsComplete=false, не считать готовыми для scientific acceptance. Внешняя генерация использует новый export; необязательная миграция старых MAT не входит в обязательный путь.
- [ ] `buildLoadDataset` пишет diagnostics.csv и отдельный `artifacts.json` после dataset.mat/CSV/manifest.json: `{schemaVersion:1,files:[{name,sha256,bytes}]}`. Не хешировать artifacts.json внутри себя и не переписывать dataset.mat после вычисления hash. D2/D4 проверяют этот manifest при потреблении persisted dataset; scientific admission требует diagnosticsComplete=true.
- [ ] Дополнить TestLoadDataset с существующими workspace/fixture/splits helpers: два case с одним ID=7, разными numUE=3/4, по два окна. Features высоты 4/ширины 15, diagnostics высоты 4; уникальных compound keys четыре. Изменение startTick одной diagnostics строки, удаление/дублирование строки — отказ WindowAlignment/Diagnostics, а не размножение при join. В fixture writer добавить корректную diagnostics таблицу и checksum через существующий saveResult; не дописывать CSV после marker без пересохранения controlled fixture.
- [ ] Отдельная проверка экспорта: после `saveResult` и `verifyCase` открыть только datasetDiagnostics из MAT и diagnostics CSV; сравнить keys/availability/NaN. Повторный result() не меняет RNG или таблицу.
- [ ] Coordinator RED/GREEN requests:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestDatasetDiagnostics.m','tests/TestLoadDataset.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

Отдельный request проверки save/verify:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestExport.m','tests/TestRadioDiagnosticsExport.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

Не запускать всю физическую регрессию автоматически.

**Done:** §22 diagnostics определены на каждом временном окне и имеют 1:1 join, доказаны boundary/censored/duplicate случаи, признаки остаются 15. **Escalate:** missing historical logs остаются unavailable; для настоящих научных результатов использовать новую внешнюю генерацию. Не подменять оконные показатели case totals, не выдавать unavailable за ноль, не пересчитывать тяжёлые старые результаты локально.

## D4 — model/policy admission и внешний runtime, F4 (10–14 ч)

**Состояние 18.10:** reader/writer phase contract принят (20/20 + 14/14), D4-R1 stale metadata fixture исправлен и независимо принят (38/38 на выбранных файлах). D4-F заморозки реализован; GREEN-005 прошёл 5/5 на development-fixture, 11/11 D4 и 40/40 global paths unchanged; независимое SPEC/QUALITY review — PASS без замечаний. Полный D4 не закрыт: D4-E/A/I и runtime/sweep/GUI связность остаются задачами. Строгий reader не ослаблять. Программные механизмы/малые fixture checks можно подготовить сейчас; реальные scientific thresholds/review/принятие модели остаются внешними. Историческое описание исходного train-loop ниже относится к началу D4; уже принятый selection-only не переделывать заново.

**Create:** `experiments/freezeLoadModelSelection.m`, `tests/TestFrozenModelSelection.m`, `experiments/evaluateFrozenLoadModels.m`, `experiments/publishModelAcceptance.m`, `tests/TestFrozenModelEvaluation.m`, `experiments/prepareModelAcceptance.m`, `src/+nbiot/+ml/validateModelAcceptance.m`, `src/+nbiot/+ml/checkModelAcceptanceEvidence.m`, `src/+nbiot/+controller/policySha256.m`, `tests/TestModelAcceptance.m`, `docs/model-acceptance-contract.md`.

**Modify:** `src/+nbiot/+ml/trainLoadModels.m`, `src/+nbiot/+ml/loadModelEvaluationMetrics.m`, `tests/TestModelEvaluationMetrics.m`, `configs/mlTrainingDefaults.m`, `tests/TestLoadModels.m`, `src/+nbiot/+controller/prepareRuntime.m`, `experiments/runComparisonSweep.m`, `src/+nbiot/+experiments/runComparisonCase.m`, `src/+nbiot/+experiments/runtimeManifest.m`, `tests/TestComparisonSweep.m`, `tests/TestAdaptiveIntegration.m`, `tests/TestRuntimeManifest.m`.

**Файлы совместного контракта, передать владельцу упаковки:** `experiments/prepareExternalRun.m`, будущий `verification/external/validateExternalPreflight.m`. D4 не редактирует их параллельно другому исполнителю.

### Исправить текущий порядок train → validation → freeze → test

**Reader/writer phase contract, окончательный после D4:** `training-manifest.json.phase` обязателен и равен selection/evaluated. Для selection CSV содержит ровно train/validation для каждой из четырёх моделей и baseline (10 строк), для evaluated — ровно train/validation/test (15 строк). `splitEvidence` в обеих фазах содержит три ID-группы; в selection поле test sampleCount означает число зарезервированных строк, а не выполненную оценку. Writer не пишет test score и не вызывает predict(test) в selection. Reader проверяет hash/уникальность/допустимые пары по phase; корректный selection возвращает текущую пустую таблицу (UI evaluationStatus=unavailable), а не частичную verified оценку. Evaluated возвращает строго три выбранные строки; unknown/missing phase, test row в selection или missing test в evaluated → empty/unavailable. D4 владеет `loadModelEvaluationMetrics.m` и `TestModelEvaluationMetrics.m` после завершения D2; добавить тесты всех пяти случаев и повторить согласованный D2 набор, не ослабляя hash/content checks. Scientific admission требует phase=evaluated плюс freeze/evaluation/review; development evaluated fixture остаётся fixture.

Факт исходника: `nbiot.ml.trainLoadModels` сегодня считает train/validation/test для каждой из четырёх моделей в одном loop, а затем выбирает minimum validation MAE. Поэтому один текст protocol не обеспечивает blind test. Исправление обязательно до внешнего обучения.

- [ ] Добавить training option `evaluationMode='development-all-splits'` для совместимости существующих development fixture tests. Для `dataKind='candidate-training'` принимать только `evaluationMode='selection-only'`, передавать его явно через wrapper. Не разрешать candidate-training default all-splits.
- [ ] В selection-only ни один вызов `score/predict` не получает testMask, test target не включается в baseline/transforms/selection/графики. Сохранять train/validation scores и model artifacts с phase='selection'; testIds сохранять как reservation metadata. Reader D2 возвращает unavailable до полноценной evaluation фазы с тремя splits; не дописывать выдуманные нулевые test scores. TestCount для splitEvidence можно фиксировать по rows, не читая test labels для научных выводов.
- [x] Создать `freeze=freezeLoadModelSelection(options)` в `experiments/freezeLoadModelSelection.m`. Реализованы обязательные options, отказ от неизвестных полей, и запрет перезаписи/размещения результата в selection folder. В endpoint нет fit/predict/test calls.
- [x] Freeze entrypoint проверяет training manifest phase=selection, hashes четырёх MAT/sidecar и metrics, ровно train/validation scores для моделей/baseline, dataset hash/roles/artifacts, approved численный protocol, frozen-validation policy и policyTuningIds только из completed development/validation allocations. Модель выбирается по validation MAE и фиксированному tie-break; результат сверяется с bestValidationModel.
- [x] Сохраняет freeze.json со всеми перечисленными schema fields, basename references и computed evidenceKind; временный JSON проходит readback перед rename, функция возвращает decoded сохранённый struct.
- [x] Создать `TestFrozenModelSelection`: selection-only на общей small fixture; provenance `test-fixture`; hash неизменности, validation argmin, отсутствие test scores, повторы, model/sidecar/metrics/policy tamper, неверные protocol/IDs/phase/options. Проверка entrypoint подтверждает отсутствие fit/predict/training calls.
- [ ] T2 вызывает freeze entrypoint после selection/policy freeze; путь `outputFile` передаёт `evaluateFrozenLoadModels.options.freezeFile`. Не создавать freeze JSON вручную в orchestration скрипте. После D3 integration проверяется наличие diagnosticsComplete и dataset artifacts; до этого можно выполнять только isolated unit fixtures.
- [ ] Создать `report=evaluateFrozenLoadModels(options)` с обязательными `freezeFile,datasetFile,modelFolder,protocolFile,policyFile,registryFile,outputFolder`. Policy и registry передаются отдельно, потому что D4-F freeze содержит их hashes, но не сохраняет пути, а D4-E обязан проверить каждый hash. Output новый/пустой. Проверить все freeze hashes и protocol approval; извлечь уже обученные модели через validateModelBundle; **не вызывать fit/train и не изменять transforms/policy**. Применить frozen transforms и predict к test только здесь. Оценить четыре метода и baseline, но выбранный selectedModel остаётся тем же; запрещено выбирать победителя по test. Вычислить strata и evaluation.json из D4 schema.
- [ ] Evaluation output содержит byte-identical copies четырёх MAT/sidecars, новый полный metrics.csv и training-manifest.json v2 (phase='evaluated', freezeFile/hash, selectionManifestSha256); selection folder не перезаписывать. Фиксировать testOpenedAtUtc до predict, evaluation complete после сохранения; частичный failure manifest не считается complete и не даёт научного допуска. Повтор завершённой оценки возвращает verified existing result без нового test consumption; mismatch freeze отказывает. Это единственный persisted evaluated bundle для packaging D2/D4.
- [ ] В TestFrozenModelEvaluation на small development fixture проверить selection-only report не содержит split=test, hashes MAT до/после совпадают, selectedModel неизменен даже при подмене test targets, которая сделала другой метод лучше. В candidate path default all-splits отклоняется до обучения. Invalid freeze/protocol после test time → отказ до predict. Изменение test target в копии **только test-fixture** не меняет selection scores/решение, но меняет dataset hash: старый freeze обязан отказать. Эта метаморфная проверка не создаёт новый scientific test и не разрешает повторное использование scientific test IDs. В настоящем исследовании test не редактируют: после его просмотра следующий цикл требует новых заранее выделенных независимых model-test IDs и нового approved protocol/freeze; это внешнее научное решение.
- [ ] Fixture helper для этого класса извлечь из существующего `smallTrainingFixture` в `tests/helpers/smallLoadTrainingFixture.m` (создать) и явно добавить tests/helpers в test setup, не вызывать приватную локальную функцию из другого файла. Сохранить исходные TestLoadModels wrapper/helper, делегирующий общей fixture, чтобы не ломать другие тесты.
- [ ] Coordinator request:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestFrozenModelSelection.m','tests/TestFrozenModelEvaluation.m','tests/TestLoadModels.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

### Явная публикация scientific acceptance после review

Создать `metadata=publishModelAcceptance(options)` с обязательными `candidateFile,reviewFile,outputFile`. Эта функция не вызывается автоматически train/evaluate/prepare и не разрешена к локальному scientific publish на fixtures. Review JSON должен содержать decision accepted/rejected, reviewer, reviewedAtUtc, evidenceDigest, protocolSha256, текст limitations; владелец/научный руководитель передаёт его после просмотра реальных evidence. Это часть явно разрешённого внешнего этапа E4, а не действие технического reviewer.

1. Повторно проверить candidate/evaluation/freeze/protocol hashes и все D4 invariant. Проверить, что review привязан к тому же evidenceDigest и после evaluation, что numerical thresholds passed.
2. При rejected сохранить отдельный rejected JSON и причины, E5 blocked. При accepted создать новый outputFile с теми же refs/digests и status='accepted', review copied verbatim; не менять MAT, policy, test metrics, старый candidate или review.
3. Output не существует; запись через temporary file, readback, затем atomic rename. Publish выполняет `checkModelAcceptanceEvidence` до записи и на readback, проверяет review.evidenceDigest и возвращает metadata с acceptanceSha256; он не вызывает runtime admission, поскольку его options не содержат cfg/execution/comparisonIds. T2 сохраняет SHA-256 acceptance в stage ledger и в compare preflight вызывает public `validateModelAcceptance(path,modelFile,policy,execution,comparisonIds,cfg)` для всех реальных конфигураций и полного списка comparisonIds. Только успешный compare preflight разрешает stage E5.
4. Отсутствие approved review, неверный digest, fixture/evidenceKind, missing criteria или провал порогов — ошибка. Никакого флага force/skipScientificReview. Unit test проверяет эти отказы и byte identity MAT; не публикует scientific acceptance из fixture.

### Неизменяемый артефакт и структура evidence

`bundle.status='development'` остаётся таким же в исходном MAT; после обучения файл не перезаписывается ради слова accepted. `bundle.dataKind='candidate-training'` обязателен для научного допуска. Acceptance хранится отдельно, его SHA-256 входит в runtime input identity. Runtime metadata получает `admissionStatus='accepted'` только после проверок; status модели и admissionStatus — разные поля. Development runtime: `admissionStatus='development-only'`; отсутствующие оценки: evaluationStatus='unavailable'.

`prepareModelAcceptance(options)` — новая функция, только собирающая `candidate` JSON, никогда не выпускает accepted автоматически. Поля options: `modelFile,datasetFile,datasetManifestFile,datasetArtifactsFile,trainingManifestFile,metricsFile,sourceManifestFile,calibrationFile,registryFile,policyFile,protocolFile,evaluationFile,outputFile`. Все обязательны; outputFile не существует; все input refs сохранять относительно каталога acceptance, после нормализации запретить выход за корень пакета. Для подготовки вне пакета сначала скопировать evidence в выбранный каталог. Ни абсолютных путей старой машины, ни ссылок `..`.

Acceptance JSON v1:

```json
{
  "schemaVersion": "model-acceptance-v1",
  "status": "candidate",
  "evidenceKind": "scientific-candidate",
  "featureSchemaVersion": "bs-known-v2.0",
  "model": {"file": "models/linearRegression.mat", "sha256": "64 hex characters"},
  "modelSidecar": {"file": "models/linearRegression.json", "sha256": "64 hex characters"},
  "dataset": {"file": "evidence/dataset.mat", "sha256": "64 hex characters"},
  "datasetManifest": {"file": "evidence/manifest.json", "sha256": "64 hex characters"},
  "datasetArtifacts": {"file": "evidence/artifacts.json", "sha256": "64 hex characters"},
  "trainingManifest": {"file": "models/training-manifest.json", "sha256": "64 hex characters"},
  "metrics": {"file": "models/metrics.csv", "sha256": "64 hex characters"},
  "sourceManifest": {"file": "evidence/source-manifest.json", "sha256": "64 hex characters"},
  "calibration": {"file": "evidence/calibration.mat", "sha256": "64 hex characters"},
  "registry": {"file": "evidence/registry-snapshot.json", "sha256": "64 hex characters"},
  "policy": {"file": "policy.json", "sha256": "64 hex characters"},
  "protocol": {"file": "protocol.json", "sha256": "64 hex characters"},
  "evaluation": {"file": "evaluation.json", "sha256": "64 hex characters"},
  "policySha256": "canonical policy digest",
  "trainingIds": [11], "validationIds": [21], "testIds": [31],
  "policyTuningIds": [21],
  "scope": {"methods": ["Adaptive-P", "Adaptive-RA/DT"], "numUE": [100,500,1000,2500,5000], "trafficKinds": ["burst"], "burstDurationTicks": [5000], "windowTicks": 500},
  "review": {"decision": "pending", "reviewer": "", "reviewedAtUtc": "", "evidenceDigest": ""}
}
```

Это схема с иллюстративными ID/scope, не готовое свидетельство. Все hash строки должны вычисляться, приведённые тексты не являются допустимыми digest. Scope — точное проверенное множество конфигураций, не автоматически весь диапазон 100..5000. Для periodic/poisson добавить соответствующие точные `periodTicks`/`poissonRatePerSecond` в scope и проверять только применимое поле; неизвестные trafficKinds отклонять.

`protocol.json`: schemaVersion, frozenAtUtc, approver, approvedAtUtc, baseline='trainMean', selectionRule='lowest-validation-mae', `thresholds` (maxMae,maxRmse,maxMaeToBaselineRatio,maxRmseToBaselineRatio — конечные неотрицательные числа), `requiredStrata` (явные нагрузки/трафик), scope, `policyTuningAllowedRoles=['development','validation']`, `testConsumption='once-after-freeze'`. **Численные значения обязан определить научный руководитель/владелец до открытия независимого model-test и final-comparison. Агент не выбирает пороги по fixtures или по уже полученному test.** Пока порогов/утверждения нет, функция возвращает candidate и список unmetRequirements, переход внешнего pipeline E4→E5 закрыт. Даже отсутствие улучшения не разрешает изменить protocol по test; нужен явно новый исследовательский цикл с новыми test IDs.

`evaluation.json`: schemaVersion, evidenceKind, datasetSha256, modelSha256, protocolSha256, frozenModelSha256, evaluatedAtUtc, selectionSplit='validation', testOpenedAtUtc, `strata` rows (split,numUE,trafficKind,sampleCount,idCount,mae,rmse,baselineMae,baselineRmse), `passed` вычисляется проверкой порогов, а не принимается на веру. Для baseline=0 ratio критерий реализовать как `modelError <= ratioLimit * baselineError`, без деления/Inf. Все requiredStrata должны быть представлены, counts>0; одинаковый model/dataset/protocol hash. Evidence review должен подтвердить порядок freeze→test→review; одни timestamps не являются доказательством научной честности.

`review.evidenceDigest` — hash канонической структуры всех input refs+hashes, schema, split IDs, tuning IDs, scope, protocol hash, policySha256, исключая status/review. Review хранит имя ответственного и время; технический reviewer кода не назначает себя научным reviewer. Превращение candidate в accepted выполняется отдельным явным шагом внешней научной приёмки после review, никогда в автотесте. Hash гарантирует связь файлов, не достоверность науки.

### Проверка и runtime interfaces

Создать `report=nbiot.ml.checkModelAcceptanceEvidence(acceptance,rootFolder)` — чистая проверка структуры/хешей/связей/метрик, возвращает `{passed,errors,evidenceDigest}`; она не предоставляет runtime capability. Fixtures могут тестировать эту функцию с `evidenceKind='test-fixture'`, но public admission всегда отвергает test-fixture.

Создать `metadata=nbiot.ml.validateModelAcceptance(path,modelFile,policy,execution,comparisonIds,cfg)`. Первые пять аргументов соответствуют основному плану; **cfg обязателен как шестой аргумент**, поскольку execution не содержит scenario scope. При отказе бросает `nbiot:ml:ModelAcceptance` (в сообщении точная причина), ничего не запускает/не пишет. Алгоритм:

1. Проверить типы, path и profile='external-machine'; role только final-comparison (или validation для заранее разрешённой policy-validation стадии, явно записанной scope.roles). `allowDevelopmentModel` не является аргументом допуска.
2. Прочитать JSON; status='accepted', evidenceKind='scientific-candidate', review.decision='accepted', непустые reviewer/reviewedAtUtc. Весь набор refs существует внутри пакетного корня; сверить байтовые hash, затем checkModelAcceptanceEvidence.
3. `validateModelBundle(modelFile)`; dataKind=candidate-training; canonical schema; MAT hash совпадает во всех местах. allocationsVerified=true сам по себе недостаточен.
4. Проверить реальный dataset.mat, artifacts.json, manifest, IDs/roles и completed allocations registry snapshot; исключить reserved IDs, development-fixture, final-comparison в dataset. Источники inputs в dataset manifest ссылаются на completion markers: пакет несёт markers и хешированные summary/observations/targets, а полный результат может быть external artifact с обязательной доступностью в scientific acceptance. Недоступное обязательное evidence — отказ, не пропуск.
5. Проверить split sets точно совпадают у bundle, training manifest, acceptance и реальных rowInfo; assignments не содержат лишние IDs. policyTuningIds только из approved development/validation allocations; все comparisonIds целые 0..3999, уникальные, не пересекаются с train/validation/test/policyTuningIds.
6. Проверить policyFile содержит **все** поля adaptiveDefaults, без неявного merge с provisional defaults; thresholds конечные, строго возрастают; levels валидны; status='frozen-validation'. `policySha256(policy)` хеширует UTF-8 jsonencode структуры с фиксированным порядком fieldnames adaptiveDefaults и row vectors; policyFile байтовый hash хранится отдельно. Изменение любого threshold меняет digest. Actual policy должен в точности совпадать с файлом после нормализации.
7. Проверить protocol утверждён до test; evaluation удовлетворяет всем численным threshold/strata; review evidenceDigest совпадает. `bestValidationModel` должен совпадать с выбранной моделью, если protocol явно не содержит отдельное утверждённое правило выбора.
8. Проверить cfg.numUE/traffic/window/method входят в scope, current computational source manifest/calibration соответствуют evidence и actual external preflight. Execution budget валидируется существующим validateExecutionBudget. Возврат metadata содержит admissionStatus, acceptanceSha256, policySha256, evidenceDigest, review и scope.

`prepareRuntime` options whitelist расширить только `modelAcceptanceFile`; existing `model,policy,allowDevelopmentModel` сохранить. Для local-development development роли оставить explicit allowDevelopmentModel. Для external-machine требовать модель-путь, полный policy, acceptance path и D4 admission; in-memory bundle с внешним profile запретить. При прямом constructor проверить comparisonIds=cfg.simulation.realizationId, cfg scope до создания RandomSources/PHY; перед sweep дополнительно проверить весь список ID и все cfg комбинации до registerRealizationUse.

Sweep options расширить `modelAcceptanceFile=''`; в `caseOptions` передать его дальше; в `runComparisonCase` положить в controllerOptions. `controllerPolicy` остаётся названием sweep/package поля; оно переводится в `controllerOptions.policy` без переименования JSON/потери полей. В `runtimeManifest` evidence файлы добавить к `inputFiles`, policyFile к `policyFiles`; acceptance/calibration/source проверки должны выполняться до возобновления completed case. Изменение acceptance или policy должно менять runtime identity и запрещать reuse результата прошлого допуска.

**Обязательная защита обхода:** удалить external bypass `if ... || ~isempty(options.runExperimentFcn), return` в `validateExecutableModel`. Injected runner разрешён как тестовый транспорт только при local-development; внешний actual-run с injected runner всё равно проходит admission. DesignOnly не имеет права писать readyForExecution=true без accepted evidence; допускается записать blocked plan и unmetRequirements.

### Малые проверки без научного запуска

- [ ] В `TestModelAcceptance` создать helper `acceptanceFixture(folder)` только внутри тестового файла: пишет маленькие CSV/JSON, fixture model и согласованные hashes; `evidenceKind='test-fixture'`. Он не создаёт внешнего accepted scientific JSON. Для чистого checker проверить positive structural result, а для public validate — обязательный отказ даже при status/review='accepted'.
- [ ] Конкретная форма regression test после определения helper (helper возвращает поля пути/model/policy/execution/cfg и comparisonIds=41):

```matlab
f=acceptanceFixture(tempname);
report=nbiot.ml.checkModelAcceptanceEvidence(f.acceptance,f.rootFolder);
t.verifyTrue(report.passed,strjoin(report.errors,'; '));
t.verifyError(@() nbiot.ml.validateModelAcceptance( ...
    f.path,f.modelFile,f.policy,f.execution,41,f.cfg), ...
    'nbiot:ml:ModelAcceptance');
```

- [ ] Отдельные negative cases чистого checker: missing file; изменённый MAT/metrics/policy/registry; дубликат split; лишний assignment ID; overlap comparison/train, comparison/model-test и comparison/policyTuning; feature schema spoof; fixture dataKind под scientific label; отрицательная/NaN метрика; missing stratum; threshold fail; stale review digest; protocol approved после testOpened; незавершённый allocation; out-of-scope cfg; path escape.
- [ ] В `TestComparisonSweep` использовать существующий injected runner с счётчиком вызовов: external actual-run + missing acceptance ⇒ ошибка до runner, счётчик=0, registry unchanged; designOnly ⇒ no execution, ready=false. Такой тест не запускает PHY.
- [ ] В `TestAdaptiveIntegration` сохранить local fixture path и explicit allowDevelopmentModel; отсутствие флага ⇒ отказ; status остаётся development, admissionStatus development-only. Раздельный successful scientific admission test допускается только с настоящим review/evidence на внешнем этапе; локально проверяется checker и отрицательные public gates, не маскировать fixture под production.
- [ ] В `TestRuntimeManifest` изменение одного policy threshold/acceptance bytes меняет input identity; перенос всего пакета в новую папку с прежними относительными refs не меняет содержательные hashes. Сравнить поля, зависимые от paths, отдельно от научной identity; не разрешать path-dependent identity, блокирующую перенос.
- [ ] Coordinator RED/GREEN requests разбить по цене:

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestModelAcceptance.m','tests/TestRuntimeManifest.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestComparisonSweep.m','tests/TestAdaptiveIntegration.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done локально:** реализован путь, ложно принятый fixture не может запустить external Adaptive, incorrect admission отказывает до PHY/registry mutation; старый development путь проверен. **Остаётся внешне:** реальные WAVEFORM dataset, baseline/стратифицированные оценки, научные пороги и review, успешный production admission и final comparison. Нельзя написать «проект готов» после локальных fixture checks.

**Escalate:** нет утверждённых численных критериев → закрыть программную работу, оставить scientific admission blocked; не выбирать «разумные» проценты улучшения. Нельзя подтвердить provenance или порядок freeze/test → candidate/rejected и запрос научного решения, без переобучения по final IDs. Runtime/packaging contract расходится → coordinator останавливает интеграцию, выбирает один контракт и обновляет оба плана до кода.

## Передача reviewer и coordinator

- [ ] Исполнитель прикладывает изменённые файлы, точные RED/GREEN requests/results, перечень непроверенного, новые schema/error identifiers.
- [ ] Reviewer отдельно проверяет F6 spoof, F7 whole-table failure, F8 window boundaries/cohort semantics, F4 fixture/admission bypass и immutable MAT. Рецензия кода не заменяет scientific review.
- [ ] Coordinator сверяет external packaging: `modelAcceptanceFile` относится к перенесённому acceptance; `controllerPolicy` полностью читается из policy.json, не adaptiveDefaults; обязательные evidence входят в manifest; source/calibration runtime context совпадает. Только после этого объединяет D4 с внешним runner.
- [ ] Сохранить итог «сделано / проверено / осталось» в основном журнале проекта через coordinator. Этот документ сам по себе не является результатом выполненных тестов.
