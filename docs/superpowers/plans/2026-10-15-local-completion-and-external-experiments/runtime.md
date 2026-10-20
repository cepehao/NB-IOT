# Runtime: диагностика, checkpoint, наблюдение и остановка — план реализации

> Исполнителю: использовать `superpowers:subagent-driven-development` в согласованной координатором схеме либо `superpowers:executing-plans`. Этот файл задаёт только R1–R4. Сам файл не разрешает запуск старой серии или больших опытов.

**Цель:** закрыть F1/F2/F3/F11 без изменения физической модели, RNG, смыслов метрик и identity старых результатов.

**Архитектура:** пакетные индексы диагностических событий; существующий потоковый SHA-256; явные фазы вокруг дорогих операций; управление принадлежащим runner Windows Job; идемпотентный учёт попыток по свидетельствам процесса. Во время MATLAB ledger пишет только MATLAB, после подтверждённого завершения — только reconciliation под эксклюзивной блокировкой.

**Технологии:** MATLAB R2025b, существующие MATLAB unittest и PowerShell, `OwnedProcessJob.cs`, JSON/MAT/CSV. Без новых сервисов, toolbox или тестовых фреймворков.

**Основание:** `AGENTS.md`, `docs/project-audit-2026-10-15.md`, основной план уровнем выше. Пути ниже относительны `C:/PROJECTS/nbiot/github-v2-publication`.

## Неизменяемые ограничения

- MATLAB запускает только координатор. Исполнитель сохраняет `verification/local/runtime-review/<R>/test-request.json` с `task`, `question`, `testFiles`, `maxCaseSeconds:300`, `maxSuiteSeconds:900`, `maxUE:10`, `expectedFailure` (для red), `sourceFiles`, `outputFolder`; затем ждёт результат. Ни исполнитель, ни ревьюер не запускают MATLAB параллельно.
- Тесты с настоящей физикой ≤10 UE; ≤300 с на файл/случай и ≤900 с на набор. Fixture `runLoadProbe(testMode=true)` содержит большие **метки** counts, но его зарегистрированный runner не создаёт физические UE. Это необходимо отличать в отчёте от настоящей нагрузки.
- Не менять `executionProfiles`, `validateExecutionBudget`, пределы, разрешённые роли или `timePolicy`. Не включать внешние политики автоматической остановки в существующий `finish-current`.
- Не возобновлять остановленную `variant2-20261014-152828-532-04934654`, не запускать 100/500/1000/2500/5000 UE. Не править source SHA/checkpoint identity для обхода проверки. Read-only чтение сохранённых событий/хеша разрешено, продолжение их симулятора запрещено.
- На каждый R: сначала конкретный воспроизводящий тест, запрос координатору на red, исправление, запрос green, независимое ревью. Если старый код уже проходит семантический тест, сохранить его как регрессионный, не изображать искусственный red. Для производительности red — установленный профиль/алгоритмический дефект, не длительное ожидание старого 220k варианта.
- Остановка с `blocked` при несовпадении научного результата, потере атомарности/identity, двойном учёте бюджета, воздействии на чужой PID, старте незапрошенного случая или превышении лимита. Максимум два узких цикла исправления без пересмотра причины; после них координатор разбирает блокер. Истечение числа циклов **не** означает приёмку.
- Ревьюер пишет отдельный `review.md`: требования / код / тесты / найденные дефекты / PASS или BLOCKED. P1 и существенный P2 запрещают приёмку. У каждого R `implementation-report.md` содержит сделано / проверено / осталось, точный diff, команды, ссылки на результаты, SHA изменённых файлов; отсутствие выполненного теста обозначать явно.

## R1. Эквивалентная радиодиагностика и знаменатель capture — F1/F11

**Зависимости:** нет. Разрешена параллельная работа с R2/R3: общих файлов нет. **Активное время:** исполнитель 5–8 ч, ревьюер 1–1,5 ч; ожидание MATLAB отдельно.

**Modify:** `src/+nbiot/+metrics/radioDiagnostics.m`, `tests/TestRadioDiagnostics.m`, `docs/metrics-contract.md`.

**Create:** `tests/TestRadioDiagnosticsScale.m`, `tests/TestRadioDiagnosticsSavedEvidence.m`, `tests/helpers/makeRadioDiagnosticsScaleFixture.m`, `verification/local/benchmarkRadioDiagnostics.m`.

**Контракт:** сохранить `diagnostics=radioDiagnostics(truthEvents,observedEvents,receptionEvents,options)` и полный выходной struct, включая порядок массивов, NaN, double и строки provenance. Ошибки некорректных событий остаются `nbiot:metrics:RadioDiagnosticsEvent`. `makeRadioDiagnosticsScaleFixture(pairCount)` возвращает `[truth,observed,receptions,options]` без PHY и без RNG. `benchmarkRadioDiagnostics(outputFolder,pairCount)` принимает один размер из [100,1000,10000,50000,220000] и пишет только результаты одного микрозамера в выбранную новую папку; это не запуск симулятора.

Факты кода: сейчас для каждой overlap-пары выполняется `arrayfun` по накопленным overlaps; component lookup также линейный, а expectedPairs строятся через все components. Оптимизировать все три участка, иначе большой синтетический тест останется квадратичным даже после первого исправления.

- [ ] R1.1. Прочитать целиком текущие `TestRadioDiagnostics` и `radioDiagnostics`, а кандидат `C:/PROJECTS/nbiot/diagnostics/matlab-live-20261014/variant2-performance-fix.patch` использовать только как справку. Не применять весь patch: progress принадлежит R3.
- [ ] R1.2. Добавить следующий метод в существующий тестовый class, используя уже имеющиеся локальные helpers:

```matlab
function reversedDuplicateOverlapIsRejected(t)
    truth=[msg1(10,1,1,1,2),msg1(10,2,2,1,3)];
    observed=radioEvent(20,1,[candidate(2,0,0),candidate(3,0,0)]);
    reception=[component(1,1,2,0,10,2),component(2,2,3,0,10,1), ...
        overlap(1,2,0,10,2,1),overlap(2,1,0,10,1,2)];
    t.verifyError(@()nbiot.metrics.radioDiagnostics(truth,observed, ...
        reception,options(100)), 'nbiot:metrics:RadioDiagnosticsEvent');
end
```

- [ ] R1.3. В отдельных методах закрепить: повтор A/B; пропущенную обязательную пару; лишнюю пару интервалов [0,10)/[10,20); неверные границы пересечения; ссылку на отсутствующий component; component из другой occasion; дублированный attempt ID; перемешанные occasions. Для последнего сравнить весь struct до/после внутренней оптимизации при одном и том же входном порядке, а не сортировать диагностический выход ради теста. Сохранить существующий known-answer `unresolvedOverlapIsCensoredRatherThanCountedAsFailure`: eligible=0, censored=1, probability=NaN. Добавить равные мощности с двумя известными исходами: eligible=0, equalPower=1 (использовать фактическое имя `equalPowerPairs` в capture), probability=NaN.
- [ ] R1.4. Построить индексы один раз: после проверки уникальности components `[sortedIds,componentOrder]=sort([components.attemptId])`; vectorized `ismember` всех overlap A/B в `sortedIds`, затем `componentOrder(location)`. Не применять плотный массив `max(attemptId)`; ID может быть редким. Outcome events собрать предварительно, сгруппировать по attemptId и отвергнуть группу с одновременно success/failure, затем заранее вычислить lookup для всех overlap ID. Для receiverEstimates построить единожды группы ключей [occasionId,nInit], их counts и единственный attempt index при count=1; не сканировать все attempts на каждого candidate. Фильтры completeOccasion/attempt membership также выполнять пакетным `ismember` или индексом, не искать в растущем массиве на каждом событии. Исходные публичные массивы не переставлять.
- [ ] R1.5. Заполнить нормализованные `loggedPairs(:,1:2)=[min(A,B),max(A,B)]`; ровно одна `unique(loggedPairs,'rows')` выявляет повтор, в том числе B/A. Сначала валидировать integer/finite/distinct ID и границы; недопустимые события не должны исчезнуть при группировке.
- [ ] R1.6. Группировать components по occasion и внутри группы сортировать по startSample с вторичным attemptId. Для каждой позиции сравнивать последующие до `b.startSample>=a.endSampleExclusive`, добавляя пару при `max(start)<min(end)`. Проверить полноту через `setxor(...,'rows')`. Это O(C log C + P) для перечисления реальных overlap; плотный полностью перекрывающийся случай всё равно требует O(P) выходных пар. Расти буфером с удвоением, затем обрезать, не создавать по одной строке матрицы в цикле. Не использовать этот внутренний порядок для публичных diagnostic массивов.
- [ ] R1.7. В `docs/metrics-contract.md` явно записать: capture denominator — пары с неравной измеренной на общем интервале мощностью и известными исходами **обеих** попыток; равная мощность и censored учитываются отдельно; нулевой denominator даёт NaN, не 0. Формулу в коде не менять.
- [ ] R1.8. Создать fixture с точным количеством пар без сотен тысяч components: пока remaining>0, выбрать максимальное n с n*(n-1)/2<=remaining, создать новую occasion из n полностью перекрывающихся [0,10) компонентов, записать все n*(n-1)/2 пар и вычесть их из remaining. Уникальные attemptId, ueId=1+mod(attemptId-1,10), nInit=0, мощности `1: n`, всем outcome success, один detection candidate nInit=0 на occasion. Все event ticks 1, horizon=2, nInitValues=0. Предвыделять struct массивы. Это 10k/50k/220k синтетических событий пар с ≤10 различными UE ID, не физическая симуляция. `TestRadioDiagnosticsScale` проверяет 10k пар и точные counts (physicalOverlapPairs=eligiblePairs=10000, capturedPairs=0, probability=0); его диагностический вывод печатает wall time. Helper directory добавить через PathFixture в тесте и cleanup после него.
- [ ] R1.9. Микрозамер: 100/1000 пар старого алгоритма только один раз, если каждый укладывается в 30 с; новый 10k/50k/220k по одному запуску, каждый отдельным ограниченным запросом. Старый 220k запрещён. В CSV `implementation,pairs,seconds,sampledPeakWorkingSetBytes,matlabRelease,sourceSha256`; пик берётся внешним sampler, неизвестное значение NaN. Если нет сохранённого малого baseline и старый снимок нельзя безопасно выделить, записать `baselineUnavailable`; это не блокирует семантическую приёмку и не разрешает обещать коэффициент ускорения.
- [ ] R1.10. Read-only эквивалентность на сохранённом завершённом 100 UE: взять точный `resultFile` из проверенного аудиторского manifest, загрузить только `result`, пересчитать только radioDiagnostics; `assert(isequaln(actual,result.radioDiagnostics))`. Не вызывать run/resume. Для команды координатор создаёт `TestRadioDiagnosticsSavedEvidence.m` в рамках этого R с одним таким тестом; если исходная диагностика отсутствует — STOP, не генерировать новую «истину». Не делать baseline нового 100 UE.

**Команды координатора (по отдельным запросам):**

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestRadioDiagnostics.m','tests/TestRadioDiagnosticsScale.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestRadioDiagnosticsSavedEvidence.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

Для 50k/220k benchmark координатор использует существующий `Invoke-BoundedProcess` с TimeoutSeconds=300 на каждый MATLAB batch; суммарно ≤900 с. Команда не запускается исполнителем. **Готово:** отрицательные тесты, точный known-answer, весь сохранённый struct совпал, 220k окончен ≤300 с, опубликован CSV без заявления об ускорении всей физики. При лимите — профиль обработчика, без увеличения бюджета. **Артефакты:** test-request, suite-report, equivalence.json с SHA исходного MAT, benchmark.csv/environment.json, review.md.

## R2. Потоковый checkpoint hash и измерения — F2

**Зависимости:** нет; R3 использует новые необязательные выходы после интеграции. **Активное время:** исполнитель 4–6 ч, ревьюер 1–1,5 ч.

**Modify:** `src/+nbiot/+experiments/saveCheckpoint.m`, `src/+nbiot/+experiments/loadCheckpoint.m`, `tests/TestSimulationCheckpoint.m`, `tests/TestCheckpointedStaticCase.m`.

**Create:** `tests/TestCheckpointFileHash.m`, `tests/TestCheckpointTiming.m`, `tests/TestCheckpointProcessWriter.m`, `tests/TestCheckpointProcessReader.m`, `verification/local/measureCheckpointHash.m`.

**Read only:** `src/+nbiot/+ml/fileSha256.m`; не менять общий helper и его ML-ошибки.

**Сигнатуры:** `[path,timing]=saveCheckpoint(sim,folder,identity)` (один выход остаётся совместимым); `[sim,info]=loadCheckpoint(folder,expectedIdentity,execution)` с добавлением `info.timing`. Checkpoint MAT schema и manifest version остаются 1. `timing` save: `existingHashSeconds,exportStateSeconds,saveSeconds,readbackSeconds,hashSeconds,publishSeconds,totalSeconds,bytes`; load: `hashSeconds,loadSeconds,restoreSeconds,totalSeconds,bytes`. Время неотрицательное finite double, байты целое, тайминги не входят в identity и не пишутся в payload научного состояния.

- [ ] R2.1. Добавить SHA known answers; файл пустой и `abc` имеют независимые эталонные digest. Минимальный тест:

```matlab
function knownShaAndByteChange(t)
    p=[tempname '.bin']; t.addTeardown(@()delete(p));
    fid=fopen(p,'wb'); fwrite(fid,uint8('abc'),'uint8'); fclose(fid);
    t.verifyEqual(nbiot.ml.fileSha256(p), ...
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    fid=fopen(p,'r+b'); fwrite(fid,uint8('z'),'uint8'); fclose(fid);
    t.verifyNotEqual(nbiot.ml.fileSha256(p), ...
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
end
```

Добавить файл `2*1024*1024+17` байт из повторяемой последовательности 0:255 и сравнить с независимым .NET `SHA256.ComputeHash(FileStream)` (закрыть stream в cleanup). Это проверяет переход границ блоков без файла в гигабайты.
- [ ] R2.2. В двух локальных `fileHash` заменить whole-file `fread(...,Inf)` вызовом `nbiot.ml.fileSha256(path)`; catch переводит ошибку в прежний checkpoint identifier (`CheckpointWrite` для save, `CheckpointCorrupt` для load). Сохранить дополнительный текст первопричины. `saveCheckpoint` по-прежнему проверяет предыдущие entries, сохраняет v7.3, readback, хеш, публикует MAT, затем manifest и только затем удаляет старые лишние точки. Никакой отмены readback.
- [ ] R2.3. Окружить перечисленные участки `tic/toc`; `totalSeconds` включает весь вызов, `publishSeconds` — обе публикации, измерения не входят в сумму дважды. В load аккумулировать hash/load время также для отвергнутого последнего checkpoint. Не измерять `memory` в tight loop, память процесса собирает coordinator sampler.
- [ ] R2.4. В тесте timing использовать имеющийся одно-UE fixture checkpoint тестов: сверить `bytes` с `dir(path).bytes`, все длительности finite ≥0, total≥каждая компонента (не требовать точной суммы из-за накладных расходов). Проверить нормальную сигнатуру с одним выходом.
- [ ] R2.5. Сохранить и расширить проверки: повреждённый последний MAT → восстановление предыдущего с recovery record/lostTicks; повреждены оба → `CheckpointCorrupt`; несовпадение source/config identity → `CheckpointIdentity` до симуляции; запись нового manifest невозможна → старый manifest побайтно неизменен и старый checkpoint загружается. В Windows тесте отказа публикации удерживать существующий manifest внутри tempdir через .NET FileStream с FileAccess.Read/FileShare.Read: чтение разрешено, замена запрещена. После ожидаемого `CheckpointWrite` закрыть stream через cleanup и сверить старый SHA/загрузку. Не менять ACL реальных данных и не удалять старую точку при отказе.
- [ ] R2.6. Короткий resume проверить в **двух** процессах: `TestCheckpointProcessWriter` сохраняет one-UE промежуточный tick, `TestCheckpointProcessReader` читает его и сравнивает с непрерывным коротким fixture по scientific logs/KPI и RNG continuation. Координатор задаёт `NB_IOT_CHECKPOINT_TEST_FOLDER` как новую абсолютную папку в tempdir; оба теста отклоняют путь вне tempdir. Writer сохраняет cfg/scenario/identity и checkpoint, Reader ничего не пересоздаёт при отсутствии файла, а падает. Оба процесса используют один свежий снимок кода. Существующие `packageSmokeWriter.m`/`packageSmokeResume.m` читать как образец, не запускать их без проверки горизонта и профиля.
- [ ] R2.7. `measureCheckpointHash(path,outputFolder)` только хеширует read-only существующий checkpoint4454, не делает `load` его payload. Координатор сравнивает helper digest, manifest и `Get-FileHash -Algorithm SHA256`; пишет размер, секунды, sampled peak, MATLAB Java heap setting. Один проход каждой реализации, лимит 300 с. Малый и большой файлы не держать в MATLAB массивах; доказательство ограниченной памяти — потоковый код + sampled memory, а не абсолютный GiB-порог, зависящий от процесса.
- [ ] R2.8. Если проектный временный `java.opts` существует, сохранить копию вне поставляемого набора и зафиксировать её SHA; исключение из поставки передать владельцу задачи упаковки. Персональные настройки MATLAB не менять. Повтор короткого теста без project heap override необходим только если override действительно использовался в первом green.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestCheckpointFileHash.m','tests/TestSimulationCheckpoint.m','tests/TestCheckpointTiming.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestCheckpointedStaticCase.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestCheckpointProcessWriter.m','tests/TestCheckpointProcessReader.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Готово:** SHA совпадают, прежние error IDs и fallback работают, two-process resume эквивалентен, тайминги/байты доступны, нет whole-file hash buffer. **Стоп:** readback/сериализация не помещается в лимит или память — сохранить профиль, не менять формат и не увеличивать heap в рамках R2. **Артефакты:** checkpoint-hash-comparison.json, checkpoint-timings.csv, process memory CSV, new-process-resume.json, suite reports, review.md.

## R3. Явные фазы и ошибки финализации — F3

**Зависимости:** может писать код параллельно R1/R2; интеграционный green после их приёмки. **Активное время:** исполнитель 5–7 ч, ревьюер 1–2 ч.

**Exclusive Modify:** `src/+nbiot/+experiments/runCheckpointedExperiment.m`, `src/+nbiot/+experiments/runStaticCase.m`, `tests/TestCheckpointedExperimentRunner.m`, `tests/TestCheckpointedStaticCase.m` (после передачи от R2; не одновременно).

**Create:** `src/+nbiot/+experiments/writeRuntimeProgress.m`, `src/+nbiot/+experiments/finalizeCheckpointResult.m`, `tests/TestRuntimeProgress.m`.

Почему `runStaticCase`: реальный `nbiot.results.saveResult` и публикация staging выполняются там, после возврата `runCheckpointedExperiment`. Называть это время simulating неверно.

**Контракты:**

```matlab
progress = nbiot.experiments.writeRuntimeProgress(path,update);
result = nbiot.experiments.finalizeCheckpointResult(resultFcn,progressFile,update);
```

`writeRuntimeProgress` атомарно объединяет update с предыдущим JSON; допустимые update поля: `phase,caseKey,currentTick,lastCheckpoint,status,workUnitsDone,workUnitsTotal,errorIdentifier,failedPhase,phaseContext`. Пустой path означает no-op (возврат struct); битый старый JSON → новый документ с `previousProgressUnreadable=true`, не скрытый crash. Статусы: running/paused/completed/failed; фазы: initializing/checkpoint-loading/checkpointing/simulating/result-finalizing/exporting/verifying/paused/completed/failed. `workUnitsTotal=[]` означает неизвестный внутренний прогресс. `phaseStartedAtUtc` меняется только при смене фазы, `lastProgressAtUtc` — только при смене phase/tick/checkpoint/workUnitsDone; `updatedAtUtc` — каждая публикация. `phaseElapsedSeconds` — накопленные **непересекающиеся** wall durations по именам фаз; persistent map с ключом canonical path + caseKey хранит tic/последний elapsed. При первом обращении нового процесса создаётся processSegmentId=UUID и нулевые накопления; прежний JSON остаётся ссылкой `previousProcessSegmentId`, старые времена не прибавлять. Память добавляет PS sampler, не MATLAB. Helper при ошибке записи возвращает `writeSucceeded=false` и выдаёт warning `nbiot:experiments:ProgressWrite`, не меняет научное выполнение.

```json
{"schemaVersion":2,"caseKey":"fixture-case","phase":"result-finalizing","status":"running","currentTick":2,"phaseStartedAtUtc":"2026-10-15T08:00:00.000Z","lastProgressAtUtc":"2026-10-15T08:00:00.000Z","updatedAtUtc":"2026-10-15T08:00:00.000Z","lastCheckpoint":"checkpoint-tick-0000000000-token.mat","workUnitsDone":0,"workUnitsTotal":[],"phaseElapsedSeconds":{"simulating":0.4,"checkpointing":0.1}}
```

- [ ] R3.1. Добавить тест phase before throw через небольшой callable seam, не через изменение NBIoTSimulator и не через новый публичный execution profile:

```matlab
function finalizationFailureRemainsVisible(t)
    p=[tempname '.json']; t.addTeardown(@()delete(p));
    u=struct('caseKey','fixture','currentTick',2,'lastCheckpoint','saved.mat');
    f=@()error('fixture:ResultFailure','controlled');
    t.verifyError(@()nbiot.experiments.finalizeCheckpointResult(f,p,u), ...
        'fixture:ResultFailure');
    v=jsondecode(fileread(p));
    t.verifyEqual(v.phase,'failed');
    t.verifyEqual(v.failedPhase,'result-finalizing');
    t.verifyEqual(v.currentTick,2);
    t.verifyEqual(v.lastCheckpoint,'saved.mat');
end
```

- [ ] R3.2. Реализовать finalize helper: сначала write phase=result-finalizing, затем `resultFcn()`; catch публикует phase=failed, failedPhase=result-finalizing, original errorIdentifier, затем rethrow. `failedPhase` — выходное поле helper, добавить его в список допустимых update полей. Только этот helper владеет вызовом callback, чтобы тест реально проверял рабочий путь.
- [ ] R3.3. В обоих местах нынешнего `sim.result()` вызвать helper с `@()sim.result()` и `sim.currentTick`; перед ним не вызывать `exportCheckpointState` на terminal sim. После выхода цикла result формируется один раз. При pause snapshot сохранить, затем partial result собрать в result-finalizing, финальный status оставить paused, не заменять на result.status.
- [ ] R3.4. Обернуть initial/resume/periodic/pause checkpoint в phase checkpointing/checkpoint-loading. Сохранить `lastCheckpoint` только после успешной публикации; на исключении phase=failed, failedPhase=<текущая>, errorIdentifier, исходное исключение rethrow. Resume возле последнего тика не экспортирует terminal state; тест вручную создаёт checkpoint за один tick до конца на одно-UE fixture.
- [ ] R3.5. Loop использует `sim.currentTick` для прогресса; exportCheckpointState сохранять только там, где нужен nextTick существующего протокола (не извлекать весь state ради currentTick). Сохранить текущую семантику `sim.run(state.nextTick)` без изменения числа шагов. Не добавлять RNG-вызовов в instrumentation.
- [ ] R3.6. В `runStaticCase` перед `saveResult` phase=exporting; после него перед чтением/проверкой marker phase=verifying; completed только после успешного move и meta. В catch записать failedPhase и ошибку. Не объявлять completed внутри runner до внешнего commit: его возврат отмечает `status=running, phase=exporting`; сам `info.status` сохраняет completed как состояние симулятора. Существующий UI не должен принимать phase за научный статус result.
- [ ] R3.7. В info добавить `phaseElapsedSeconds` и `checkpointTimings` из R2 без изменения старых полей. `progressPhase` прежнего API сохранить как `phaseContext` в progress, а не склеивать canonical phase с `load-500-...`; PS видит canonical phase, load принадлежит caseKey/context.
- [ ] R3.8. Проверить: обычное завершение; paused; resume penultimate tick; исключение result; исключение checkpoint; ошибка записи progress; неизвестные units; repeated write не обновляет lastProgressAtUtc; phaseStartedAtUtc не сбрасывается при том же phase; UI refresh/RNG не затронуты. Compare baseline fixture scientific fields с обычным `nbiot.runExperiment`, исключив только instrumentation wall timestamps.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestRuntimeProgress.m','tests/TestCheckpointedExperimentRunner.m','tests/TestCheckpointedStaticCase.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Готово:** progress показывает finalizing до входа в result и exporting до saveResult; ошибки сохраняют фазу; paused не превращается в completed; короткий scientific result совпадает. **Стоп:** для проверки потребовалась инъекция в физическое ядро или смена checkpoint schema — вернуть координатору, не расширять scope. **Артефакты:** последовательность progress snapshots, timings.json, scientific-equivalence.json, suite report, review.md. Передать R4 точную схему helper; R4 не редактирует эти файлы.

## R4. Управление принадлежащим процессом и однократный reconcile — F3

**Состояние 18.10:** R4.1–11 сверены с текущим исходным кодом и сохранёнными доказательствами, затем приняты независимым reviewer (SPEC/QUALITY PASS без замечаний). См. `verification/local/runtime-review/R4/remaining-acceptance-20261018.md`. Поэтому пункты R4.1–11 отмечены как принятые; это не означает повторный запуск всех старых групп. R4.12 остаётся `blocked-by-owner-scope`: защищённую historical запись в этой задаче не читали и не применяли. Общие указания preview/Apply ниже не отменяют эту границу. Полный R4 открыт.

**Зависимости:** R3 принят, его `writeRuntimeProgress` доступен; R2 завершён для короткого resume. **Активное время:** исполнитель 8–12 ч, ревьюер 2–3 ч. Это наиболее рискованный блок, его нельзя оценивать как одну косметическую правку JSON.

**Exclusive Modify:** `verification/local/InvokeScheduledProcess.ps1`, `verification/completion/stage-3/runVariant2.ps1`, `experiments/runLoadProbe.m`, `src/+nbiot/+experiments/loadVariant2BudgetLedger.m`, `src/+nbiot/+experiments/saveVariant2BudgetLedger.m`, `verification/local/testScheduledProcess.ps1`, `tests/TestLoadProbe.m`.

**Create:** `verification/local/ControlScheduledRun.ps1`, `verification/local/ReconcileScheduledRun.ps1`, `verification/local/testScheduledRunControl.ps1`, `verification/local/testScheduledRunReconcile.ps1`, `verification/local/fixtures/scheduledRunStub.ps1`, `tests/TestBudgetLedgerReconcileContract.m`.

**Read only:** `OwnedProcessJob.cs` — использовать существующий `.Stop()`, не заменять на kill по имени. R4 не меняет runCheckpointedExperiment/runStaticCase; нужные фазы публикует через helper R3.

**CLI (точно):**

```powershell
./verification/local/ControlScheduledRun.ps1 -Action inspect -RunFolder <absolute-folder>
./verification/local/ControlScheduledRun.ps1 -Action stop-after-case -RunFolder <absolute-folder>
./verification/local/ControlScheduledRun.ps1 -Action cancel -RunFolder <absolute-folder>
./verification/local/ControlScheduledRun.ps1 -Action resume -RunFolder <absolute-folder>
./verification/local/ReconcileScheduledRun.ps1 -RunFolder <absolute-folder> -Apply
```

`inspect` всегда read-only. `resume` проверяет identity/состояние и возвращает `resumeAllowed` и `resumeCommand`; **не запускает процесс**. Прямой вызов runner для продолжения имеет форму `runVariant2 -Resume -RunFolder <absolute-folder>`; несовместимая комбинация `-Execute -Resume` запрещена. Для остановленной владельцем исторической серии resumeAllowed=false и причина owner-stopped/source-mismatch; CLI не предлагает команду запуска. Reconcile без `-Apply` только печатает план изменений и недостающие свидетельства. Все CLI возвращают структурированный JSON и ненулевой exit при конфликте.

**Дополнение 16 октября — source-safe resume gate:** Control и прямой runner сверяют пару `sourceManifestSha256`/`runnerSha256` из progress/preflight с текущим MATLAB source manifest и единственным runner-кандидатом на эффективном MATLAB path. Owner-stop и source-mismatch отклоняются до чтения сохранённых process tuples; прямой runner дополнительно fail-closed при неизвестной launch/process-started identity до live lookup, записи и dispatch. Ограниченный синтетический GREEN принят для этого узкого сценария: [execution review](../../../../verification/local/runtime-review/R4/r4-source-safe-resume-implement-003/execution-results-review.md), [synthetic evidence](../../../../verification/local/runtime-review/R4/r4-source-safe-resume-implement-003/coordinator-output/evidence/source-safe-resume-green-scenarios.json). Этот результат закрывает только source-safe resume subgate, не R4 целиком; принятые и оставшиеся подгейты описаны в coordination ledger.

**Control JSON:** `control-request.json` в process folder: `schemaVersion:1,requestId,runId,action,requestedAtUtc,rootProcessId,processStartTimeUtc,workerProcessId,workerProcessStartTimeUtc`. Все значения идентичности берутся из `process-started.json`/`launch.json`, проверяются по живому PID и времени старта. Ack: `requestId,status:applied|rejected,reason,acknowledgedAtUtc`. Stop-after-case дополнительно фиксируется в run-root `stop-after-case.request.json` с runId/requestId; маркер остаётся до явного нового resume, не удаляется worker автоматически.

**Ledger контракт:** оставить schemaVersion=1/budgetSeconds=57600 для этого исторического Variant2 API; добавить необязательные `accountingVersion:2`, `attempts`, `reconciliation`. Старые файлы без этих полей читаются. Каждая запись attempts: `attemptId,runId,caseKey,startedAtUtc,finishedAtUtc,status,observedSeconds,chargedSeconds,processReportSha256`. attemptId — UUID одной попытки case, не scientific realizationId. `elapsedSeconds` — старый подтверждённый расход плюс приращения chargedSeconds. activeCase дополнительно содержит attemptId и process linkage; существующие поля не удалять. Никаких новых UE/role/timePolicy полей профиля.

- [x] R4.1. Сначала process-only тесты на powershell stub: stub пишет прогресс case-1, ждёт marker, пишет finalizing, завершается; отдельный режим создаёт короткий дочерний процесс. Все temp пути содержат пробел. Ни один stub не вызывает MATLAB. Добавить встроенный Assert-Equal/Assert-True, не устанавливать Pester. Ограничить каждый сценарий 30 с и весь файл 300 с.
- [x] R4.2. `ControlScheduledRun` разрешает process folder через существующий launch metadata, не по случайному первому найденному PID. Validate runId + root/worker start times + executable/command line; несовпадение/невозможность чтения → rejected, ничего не убивать. Атомарно write temp+move request. Worker проверяет tuple ещё раз и только при cancel вызывает принадлежащий ему `$job.Stop()`; завершает report, status=cancelled, причина explicit-request. Worker heartbeat продолжает работать при смерти launcher.
- [x] R4.3. `InvokeScheduledProcess` читает canonical phases R3; elapsed heartbeat не считается прогрессом. После `NoProgressWarningSeconds` пишет needs-attention с action-командой inspect/cancel, последним phase/tick/checkpoint. Это предупреждение, не автоматический kill. Добавить в report started/finished UTC, process identity и runId; sampled peak назвать sampled, не истинным максимумом. Отчёты/heartbeat писать через temp+atomic move, иначе reconcile может читать оборванный JSON.
- [x] R4.4. Перед каждым admission в `runLoadProbe` проверить stop-after-case marker **до** создания cfg/резервирования следующего case; проверить снова сразу после завершения текущего, в том числе после exporting/verifying. Current case может закончить finalizing; следующий не начинается. Status='paused', pendingCounts сохраняется. Cancel при финализации не создаёт completion marker. Completed принимать только по проверенному marker/hashes, не по exitCode=0.
- [x] R4.5. Сохранить одного писателя ledger. `runLoadProbe` держит эксклюзивный файл lease `<ledger>.writer.lock` через Java FileChannel.tryLock, открытый весь MATLAB run; cleanup закрывает channel. Reconcile пытается взять несовместимую OS-level FileStream FileShare.None блокировку того же файла. Проверить межпроцессный конфликт на stub; простого `isfile(lock)` недостаточно. Worker пишет heartbeat/report и accounting-observation.json, но **никогда** ledger. Записи предупреждений runner происходят внутри того же MATLAB владельца.
- [x] R4.6. При начале case создать attemptId, сохранить activeCase+attempt до вызова runner; при нормальном завершении добавить только `max(0,wallSeconds-attempt.chargedSeconds)`, присвоить chargedSeconds=wallSeconds. Worker observation содержит runId, attemptId, caseKey, observedAtUtc, observedSeconds от начала active case; нет attempt → observation недоступен. На read-only inspect показать `committedSeconds + max(0,observedSeconds-chargedSeconds)`, отдельно label estimated; не подменять им persisted ledger.
- [x] R4.7. Reconcile сначала доказывает отсутствие нужного root **и** worker по tuple. Root умер, worker жив → wait-for-report, ledger не трогать. Worker умер, root жив/identity неизвестна → needs-attention, не resume и не kill по догадке. Оба отсутствуют и report есть: проверить runId/attempt привязку, finite elapsed, времена. Для новых запусков использовать report+последний activeCase start; `targetSeconds` — длительность пересечения интервала case и worker, не полное время процесса после уже учтённых нескольких cases. Не складывать process elapsed целиком с уже закрытыми phaseTimes.
- [x] R4.8. Формула `delta=max(0,targetSeconds-chargedSeconds)`, `elapsedSeconds+=delta`, `chargedSeconds=max(chargedSeconds,targetSeconds)`. Ключ идемпотентности attemptId; report SHA фиксируется. Повтор того же report → no-op; другой report для закрытого attempt → conflict, не второй расход. При отсутствии конечного report после аварии допускается только нижняя оценка по последнему проверенному heartbeat, status=interrupted-accounting-incomplete, `resumeAllowed=false`; не выдавать её за полный расход и не считать время до момента inspect вычислительным временем.
- [x] R4.9. Публикация reconcile транзакцией: под lock сохранить `.before` копии ledger/progress и SHA, записать `reconcile-intent.json` с old/new digest и уже рассчитанным новым содержимым, атомарно publish ledger, затем progress и summary, затем `reconcile-commit.json`. Повтор после падения между публикациями сверяет old/new digest и заканчивает ту же транзакцию; несовпадение чужой записи → conflict. IDs, completed records и scientific MAT не меняются. Не выдавать interrupted case за completed и не освобождать realizationId.
- [x] R4.10. Минимальный проверочный сценарий reconcile: fixture committed=100, active charged=0, target=12.5, attempt='a1'; первый Apply даёт elapsed=112.5, второй остаётся 112.5. Сценарий падения после publish ledger и до progress повторно заканчивает progress без 125.0. Оформить в `testScheduledRunReconcile.ps1`:

```powershell
& "$PSScriptRoot/ReconcileScheduledRun.ps1" -RunFolder $fixtureFolder -Apply
$first = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
& "$PSScriptRoot/ReconcileScheduledRun.ps1" -RunFolder $fixtureFolder -Apply
$second = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
if ($first.elapsedSeconds -ne 112.5 -or $second.elapsedSeconds -ne 112.5) {
    throw 'Reconcile must charge the interrupted attempt exactly once.'
}
```

`$fixtureFolder/$ledgerPath` создаёт setup данного теста внутри tempdir, JSON соответствует контракту выше; process IDs заведомо отсутствуют и report содержит завершённый fixture run. Нельзя использовать реальные ID20816/20976 в исполняемом тесте.
- [x] R4.11. Негативные process cases: reused PID с чужим startTime; wrong runId; malformed report; два одновременно Apply; смерть launcher; смерть worker при живом root; orphan без report; stop-after-case во время finalizing; исчерпанный бюджет не начинает следующий; cancel задевает только job, sentinel чужого процесса жив; путь с пробелами; повтор requestId. MATLAB TestLoadProbe использует существующий `makeFixture(t)` и зарегистрированный testMode runner, проверяет paused/pendingCounts и неизменённый registry. Реальную физику больших меток counts не запускать.
- [ ] R4.12. Исторический run reconcile сначала **только preview** по `owner-stop.json`, `before-owner-stop.json`, process-report и phaseTimes. Проверить привязку восстановленного worker и точный расход уже закрытых попыток; ожидаемый ориентир аудита 10136.88+54314.27 с, это не жёсткая константа расчёта. При неразрешимой двусмысленности оставить accounting-incomplete и приложить диапазон/основание. После green stub-тестов координатор может Apply служебных файлов с backup. Сохранить completed 100 UE, partial 500, pending 500/1000/2500 и owner-stopped. Ни запуск, ни изменение MAT, ни SHA-подмена не являются частью reconcile.

```powershell
./verification/local/testScheduledRunControl.ps1
./verification/local/testScheduledRunReconcile.ps1
./verification/local/testScheduledProcess.ps1
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestLoadProbe.m','tests/TestBudgetLedgerReconcileContract.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

Process-only команды также передаются координатору с явными тайм-аутами, чтобы они не пересекались с его MATLAB sampler. **Готово:** остановка воздействует только на принадлежащий job, новые случаи не стартуют после marker/бюджета, repeat/crash reconcile однократен, orphan не превращается в безопасный resume, старый run остаётся незавершённым. **Стоп:** сомнение в PID identity, межпроцессная блокировка не подтверждена, ledger расход не выводится из свидетельств, конфликт report SHA — BLOCKED, никакой ручной «починки» цифр.

**Артефакты:** control-scenarios.json, process stdout/stderr/heartbeat/report, accounting-fixtures.json, reconcile preview/backup hashes/intent/commit, ledger before-after diff, MATLAB suite report, review.md.

## Передача результатов этих четырёх заданий

R1 передаёт UI/отчётам неизменённый diagnostics contract и исправленное определение capture. R2 передаёт R3 необязательные timing outputs. R3 передаёт R4 `writeRuntimeProgress` и canonical phase schema; после этого R4 не просит параллельно редактировать runner. Внешняя упаковка получает готовые control/reconcile команды, но не разрешение на выполнение серии.

Оценка суммарно: **22–33 активных часа исполнителей + 5–8 часов независимого ревью = 27–41 agent-hours**. Это сумма работы, не длительность календарного ожидания; лимит каждого MATLAB запроса не увеличивается из-за этой оценки. Значимый дефект или неполное свидетельство продлевает/блокирует конкретную задачу, а не уменьшает критерий приёмки.
