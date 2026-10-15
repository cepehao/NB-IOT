# Вариант 2: местная проверка и нагрузки до 2500 UE — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Исполнять самостоятельно в указанной рабочей копии. Новый brainstorming и повторное утверждение выбранного варианта не нужны.

**Goal:** завершить оставшиеся местные требования, подготовить долгие расчёты без прерывания по таймеру, получить новый допуск физики и предварительные измерения Static на 100/500/1000/2500 устройствах на текущем ПК.

**Architecture:** сохранить существующее ядро, калибровку, интерфейс, проверки и полный пятинагрузочный пилот. Добавить явный профиль согласованного местного эксперимента, надёжные контрольные точки и отдельный запуск четырёх предварительных нагрузок. Ориентир 16 часов ограничивает начало следующих случаев; текущий случай продолжает работу. Новые результаты связывать с неизменным снимком вычислительного кода и свежими ID.

**Tech Stack:** MATLAB R2025b, LTE Toolbox, существующие MATLAB unit tests, PowerShell и Windows Job API; новые сервисы и зависимости не нужны.

**Spec:** `C:/PROJECTS/nbiot/github-v2-publication/ТЗ_NB-IoT_обновленный.pdf`, §§29, 46, 47, 50; исходный маршрут `docs/superpowers/plans/2026-10-13-completion-roadmap.md`, задачи 1–7; решения владельца в `AGENTS.md`, `docs/current-state.md`, `docs/experiment-budget.md`. Этот документ — уточнение ближайшего объёма исходного маршрута, не новый план завершения всего проекта.

## Global Constraints

- Рабочая копия: `C:/PROJECTS/nbiot/github-v2-publication`. Соседние `src/tests/docs` принадлежат старой копии.
- Сохранить все незакоммиченные изменения, калибровку, старые результаты и занятые ID. Не выполнять reset/clean/stage/commit/push и не удалять старые комплекты.
- Обычная разработка и новые проверки: `local-development`, максимум 10 UE, горизонт максимум 5000 ticks, 300 секунд на случай / 900 секунд на выбранный набор через существующий bounded runner.
- После подготовки отдельно разрешается выбранный вариант 2 на текущем ПК: последовательная Stage 2 матрица и ровно четыре нагрузки `[100 500 1000 2500]`. Новая сессия получает разрешение на этот запуск из промпта владельца; создание этого плана само по себе ничего не запускает.
- Большой случай: Static, полный горизонт 5000 ticks, burst 100 ticks, один общий новый ID для четырёх нагрузок. Геометрию, канал, мощность, приёмник и научные параметры не упрощать ради времени.
- 12–16 часов — предварительная оценка машинного времени после местной подготовки. Подготовка кода, проверки восстановления и исправления в эту оценку не входят; достоверной оценки их времени пока нет.
- Превышение ожидаемого времени, предупреждения о ресурсах и отсутствие свежего heartbeat сами по себе не разрешают принудительно завершать продолжающийся MATLAB. Сохранить доказательства, исследовать продвижение. После 16 часов не начинать следующий случай; начатый довести до результата. Возможный выход за ориентир явно сообщить.
- До 5000 UE, полное обучение, сравнительные серии, полный `runtests('tests')` и новая массовая калибровка не входят в этот вариант.
- Файл преподавателя `C:/PROJECTS/nbiot/Final_NB-IoT.m` оставить исходным примером; его 210 000 опытов и замену ядра не включать. Использовать уже сохранённый разбор `docs/professor-waveform-review-20261014.md`.
- Не повторять успешные неизменённые проверки без конкретного вопроса. Собрать один новый комплект после содержательных правок и входящих документов; дальнейшее изменение статуса не вызывает пересборку.

## Review Focus

1. Нулевые знаменатели, пустые группы и незавершённый горизонт: `NaN`/признак доступности, сохранённые счётчики; никакого вымышленного успеха.
2. Таймер истёк во время работы и закрылся управляющий процесс: долгий MATLAB продолжает работу, обычный bounded runner сохраняет прежнее поведение; соседние процессы не затрагиваются.
3. Сбой записи/повреждение контрольной точки и несовпадение версии: предыдущая проверенная точка остаётся читаемой; несовместимое состояние не загружается автоматически.
4. Перезапуск между сигналами/окнами: совпадают научные результаты, очереди, случайные потоки и последовательность событий; общее использование календаря планировщиком не теряется.
5. Четыре нагрузки готовы, пятая отсутствует: предварительный опыт завершён, полный пилот не объявляется завершённым; ID не попадает в независимое обучение или финальное сравнение.

## Отправная точка и файлы

Задачи 2–6 исходного плана уже выполнены для ранее определённых метрик. Остаток — определения/реализация outage и групп, подготовка долгого исполнения, затем новые физические доказательства. Не создавать существующие журналы/GUI/ML заново.

| Область | Существующие файлы | Добавляемые файлы |
|---|---|---|
| Остаток метрик | `src/+nbiot/NBIoTSimulator.m`, `src/+nbiot/+results/buildUeSummary.m`, `saveResult.m`, `verifyCase.m`, `src/+nbiot/+ui/formatResultSummary.m`, `apps/NBIoTApp.m` | `src/+nbiot/+metrics/serviceKpi.m`, `tests/TestServiceKpi.m` |
| Политика исполнения | `src/+nbiot/+experiments/validateExecutionBudget.m`, `NBIoTSimulator.m`, `verification/local/OwnedProcessJob.cs` | `verification/local/InvokeScheduledProcess.ps1`, `verification/local/testScheduledProcess.ps1`, `tests/TestScheduledExecutionBudget.m` |
| Восстановление | `NBIoTSimulator.m`, `src/+nbiot/+experiments/runStaticCase.m`, `runtimeManifest.m` | `src/+nbiot/+experiments/saveCheckpoint.m`, `loadCheckpoint.m`, `runCheckpointedExperiment.m`, `tests/TestSimulationCheckpoint.m` |
| Физическая проверка | `verification/completion/stage-2/stage2Physical.m`, `runStage2Physical.ps1`, `stage2Targeted.m`, `acceptStage2Evidence.m`, `experiments/validateCollisionCapture.m` | `tests/TestStage2ScheduledResume.m` |
| Четыре нагрузки | `experiments/runLoadPilot.m`, `src/+nbiot/+experiments/runStaticCase.m`, `availableRealizationIds.m`, `registerRealizationUse.m`, `updateRealizationUseStatus.m` | `experiments/runLoadProbe.m`, `verification/completion/stage-3/runVariant2.ps1`, `tests/TestLoadProbe.m` |

Пути в таблице относительны корню рабочей копии. Перечисленные новые функции ниже являются проектируемыми интерфейсами, а не уже существующими командами.

## Task 1: закрепить исходный снимок и закрыть определения

**Files:** `AGENTS.md`, `docs/current-state.md`, `docs/metrics-contract.md`, `docs/gui-requirements-audit.md`, `docs/section-47-results-audit.md`, `docs/section-50-readiness.md`, `.superpowers/sdd/2026-10-13-completion-roadmap/progress.md`.

**Interfaces:** вход — PDF и уже сохранённая `ueSummary`; выход — определение `serviceKpi(ueSummary,actualTick,isComplete)` и перечень оставшихся требований.

- [x] Прочитать правила и актуальные верхние уточнения статуса. Записать `git status --short`, исходный commit, хеш калибровки и перечень изменяемых файлов в новый каталог `verification/local/variant2-preparation-<UTC timestamp>/`. Не редактировать другие рабочие копии.
- [x] Сверить только открытые outage/группы с §§46.8/46.10/46.13 и существующей таблицей UE. Старые сообщения об ожидании выбора владельца считать отменёнными: владелец делегировал решения исполнителю.
- [x] Принять явно обозначенный **service outage за наблюдаемый горизонт H**: число UE с `created>0 && delivered==0`, делённое на число UE с `created>0`. Это отсутствие доставленного пакета до H, а не необратимый отказ или radio outage по порогу SNR. Число UE с `unfinished>0`, фактический H и доступность сохранять рядом. При незавершённом запуске итоговую вероятность для полного заданного горизонта не заявлять: `available=false`, probability=`NaN`, диагностические счётчики оставить.
- [x] Группы — существующие indoor/outdoor и отдельно `coverageClass`. Не вводить дистанционные кластеры или новые классы покрытия; при CE0 для всех так и написать. Для каждой группы сохранить UE count, demand UE count, outage UE count, created/delivered/dropped/unfinished, delivery probability и RA started/success/failure/unfinished. Отношения считать из сумм числителей/знаменателей, не средним индивидуальных процентов.
- [x] Для пустой категории сохранить нулевые счётчики и `NaN` отношений; неизвестный признак обозначить `unknown`, а не отнести к outdoor. В документах указать источник, единицы, MAT/CSV, GUI и тест. Зафиксировать выбор в ledger как Ruling с ограничением научного смысла.

**Приёмка:** определение позволяет вручную получить ответ и не требует нового ответа владельца; исходный маршрут остаётся актуальным.

## Task 2: реализовать только недостающие метрики и отображение

**Files:** новые `serviceKpi.m`, `TestServiceKpi.m`; существующие `NBIoTSimulator.m`, `saveResult.m`, `verifyCase.m`, форматтер сводки и необходимые панели `NBIoTApp.m`; `tests/TestRadioDiagnosticsExport.m`, `TestResultSummaryFormatting.m`, `TestPerUeSummary.m`.

**Interfaces:** `[service,groups]=nbiot.metrics.serviceKpi(ueSummary,actualTick,isComplete)`. `service` содержит `definition='service-outage-horizon-v1'`, `available`, `actualTick`, `demandUeCount`, `outageUeCount`, `unfinishedUeCount`, `probability`; `groups` — таблица с измерением `groupDimension`, значением `groupValue` и счётчиками Task 1. Выход сохранять в `result.kpiSummary.service` и `result.groupKpi`; не включать истинные групповые итоги в признаки BS.

- [x] Добавить сначала проверку известного результата, включая пустую группу, отсутствие спроса, censored UE и partial result. Минимальный проверяемый пример:

```matlab
u=table((1:3)',[true;false;false],["CE0";"CE0";"CE0"], ...
    [1;1;0],[0;1;0],[1;0;0],zeros(3,1),[1;1;0], ...
    [0;1;0],[1;0;0],zeros(3,1), ...
    'VariableNames',{'ueId','indoor','coverageClass','created', ...
    'delivered','dropped','unfinished','raAttempts','raSuccesses', ...
    'raFailures','raUnfinished'});
[s,g]=nbiot.metrics.serviceKpi(u,5000,true);
t.verifyEqual(s.probability,0.5);
t.verifyEqual(s.demandUeCount,2);
t.verifyEqual(s.outageUeCount,1);
t.verifyEqual(sum(g.created(g.groupDimension=="indoor")),2);
[partial,~]=nbiot.metrics.serviceKpi(u,1000,false);
t.verifyFalse(partial.available);
t.verifyTrue(isnan(partial.probability));
```

- [x] Запустить `TestServiceKpi.m` существующим bounded runner и увидеть содержательный FAIL отсутствующего интерфейса/результата, затем добавить расчёт из `ueSummary` без новой симуляции.
- [x] Подключить MAT/CSV и отображение сохранённых данных. Новый CSV — `_groups.csv`; сводка содержит определение outage, H и censored count. Для старых результатов показывать «нет данных»; версия/правила чтения не должны объявлять старые файлы ошибочными. Если требуется смена schema version, явно обновить manifest/verifyCase и тесты совместимости.
- [x] После правки пройти ровно связанные formatter/export/UE tests; одним UE проверить save/readback и новое отображение. Новую короткую UI/CLI проверку запускать только если затронута последовательность исполнения/вычисления результата. Отдельный полный UI обход не повторять.
- [x] Обновить карты требований и current-state: реализовано / проверено / внешние доказательства. Закрыть соответствующий остаток задачи 1 исходного маршрута после зелёных проверок.

**Приёмка:** известные числа, `NaN`, сохранение и старый результат проверены; новый показатель не выдаётся за радиоотказ.

## Task 3: отдельная политика долгого исполнения без таймерного уничтожения

**Files:** `validateExecutionBudget.m`, `NBIoTSimulator.m`, `OwnedProcessJob.cs`; новые `InvokeScheduledProcess.ps1`, `testScheduledProcess.ps1`, `TestScheduledExecutionBudget.m`; существующие Stage 2 wrapper и suite-проверка времени в `validateCollisionCapture.m`.

**Interfaces:** добавить профиль `scheduled-local`, поле `timePolicy` с default `hard-stop`; только явный согласованный профиль принимает `finish-current`. Старые вызовы без нового поля сохраняют прежние ограничения. Параметры вариантов:

```matlab
stage2Execution=struct('profile','scheduled-local', ...
    'role','stage-2-collision-diagnostics','maxUE',10, ...
    'maxCaseSeconds',120,'maxSuiteSeconds',57600, ...
    'timePolicy','finish-current');
probeExecution=struct('profile','scheduled-local', ...
    'role','stage-3-load-pilot','maxUE',2500, ...
    'maxCaseSeconds',36000,'maxSuiteSeconds',57600, ...
    'timePolicy','finish-current');
```

Для `finish-current` maxCaseSeconds — порог предупреждения, maxSuiteSeconds — предел начала нового случая. Не требовать `numCases*maxCaseSeconds<=maxSuiteSeconds` для этой политики; для старой hard-stop это правило сохранить. `scheduled-local` принимает только две указанные роли, максимум 2500 UE и 5000 ticks, без параллельных jobs. Нельзя расширять местный development profile или подменять текущую машину ярлыком external-machine.

- [x] В новом `TestScheduledExecutionBudget` сначала проверить принятие явного профиля, отказ 5000 UE/параллельного/default большого вызова и неизменность old local limits. Пример основной проверки:

```matlab
cfg=nbiot.config.defaultConfig(); cfg.simulation.numUE=2500;
b=nbiot.experiments.validateExecutionBudget(cfg,probeExecution,4);
t.verifyEqual(b.timePolicy,'finish-current');
cfg.simulation.numUE=5000;
t.verifyError(@() nbiot.experiments.validateExecutionBudget(cfg,probeExecution,4), ...
    'nbiot:experiments:ExecutionBudget');
```

- [x] Изменить `checkExecutionDeadline`: для finish-current записать одно предупреждение исполнения, продолжить шаг; не менять status на stopped/failed. На уровне серии истечение бюджета проверять до нового случая и завершать серию с `budget-paused`, сохранив уже завершённые случаи. Для local-development прежняя остановка остаётся.
- [x] Создать отдельный scheduled wrapper поверх существующего Windows Job API. Добавить перегрузку конструктора `OwnedProcessJob` с явным `killOnClose=false` для долгого профиля; старый пятиаргументный конструктор оставляет `KILL_ON_JOB_CLOSE`. Scheduled wrapper не вызывает `Stop()` по времени или ошибке sampler. Закрытие его handle не должно убивать расчёт. PID, время создания процесса, stdout/stderr и идентификатор запуска записывать до возвращения управления.
- [x] Долгое исполнение запускать независимым worker PowerShell через `Start-Process -WindowStyle Hidden`, с сохранённым script/arguments и файловыми журналами. Worker владеет MATLAB; завершение turn/чата не заменяет результат опыта. Не считать фоновый запуск устойчивым до короткого испытания исчезновения управляющего процесса.
- [x] Heartbeat каждые 30 секунд; host memory sampler около 1 секунды со streaming CSV, без накопления 16 часов строк в RAM. Записывать PID дерева, WorkingSet, timestamp, tick/фазу/последнюю контрольную точку. Отсутствие продвижения 15 минут вызывает предупреждение, не kill; длинный текущий шаг отдельно виден. Maximum sampled working set обозначать измеренным с указанным интервалом, не непрерывным истинным максимумом.
- [x] `testScheduledProcess.ps1`: короткий дочерний процесс длится дольше warning threshold и завершается с кодом 0; исчезновение управляющего процесса не обрывает его; соседний процесс остаётся жив; ошибка записи sampler сохраняет PID и журнал, не убивает дочерний процесс. Затем проверить сохранение пяти старых bounded-process сценариев, поскольку менялся общий C# helper.
- [x] Пройти новый MATLAB test и `TestExecutionBudget.m` bounded runner. Записать новое разрешённое исключение варианта 2 в AGENTS/local-checks/budget без снятия обычных ограничений.

**Приёмка:** превышение ориентира и исчезновение контроллера проверены; существующие короткие проверки сохраняют предельное время.

## Task 4: проверенное восстановление середины случая

**Files:** новые `saveCheckpoint.m`, `loadCheckpoint.m`, `runCheckpointedExperiment.m`, `TestSimulationCheckpoint.m`; `NBIoTSimulator.m`, `runStaticCase.m`, при необходимости точечные методы связанных state classes.

**Interfaces:** `state=sim.exportCheckpointState()`; `sim=nbiot.NBIoTSimulator.fromCheckpointState(state,execution)`; `path=saveCheckpoint(sim,folder,identity)`; `[sim,info]=loadCheckpoint(folder,expectedIdentity,execution)`; `result=runCheckpointedExperiment(cfg,scenario,execution,controllerOptions,checkpointOptions)`.

`identity` — runtime manifest плюс checkpoint schema version и идентичность MATLAB/LTE. Обязательные совпадения: code/source/config/calibration/model/policy/input/runner/ID и релиз. Не сверять глобальный registry hash как идентичность состояния: выделение другого ID не меняет этот случай. `checkpointOptions` содержит `folder`, `identity`, `intervalSeconds=600`, `resume=false`.

- [x] Сначала тест 1 UE: до контрольной точки уже были передачи/приёмы, после неё остаются события. Сравнить полный прямой прогон и save → новый MATLAB-процесс → load → продолжение. Отдельный случай с ожидающим событием возле закрытия 500-ms окна проверяет ровно один учёт события/окна. Обе проверки укладываются в местные пределы.
- [x] Экспортировать полное состояние на границе завершённого `step()`, а не UI `snapshot()`/частичный `result()`. Сохранить публичные cfg/scenario/currentTick/status/runtimeAction/devices/packets/contexts/calendar/scheduler/channel/attempts и приватные sources/receiveQueue/observed/truth/radioReceptionDiagnostics/lifecycleLog/harqJournal/queueSamples/controllerRuntime/controllerLog/controllerLatestEstimate/occasions/nextTick/arrivalCursor/monitorQueued/tokens/observationRows/targetRows/raIntegral/activeIntegral/queueIntegral/observedCrcCounters/elapsedSeconds/stopRequested. `resultCache` инвалидировать, process clock заново создавать; warning/runtime overhead хранить отдельно от науки.
- [x] Сериализовать весь связанный граф состояния одним MAT `-v7.3`; сохранить общие ссылки scheduler→calendar и channel→sources. Не пересоздавать геометрию/трафик при восстановлении. `RandomSources` именует потоки детерминированно; сохранить seed/realizationId и любые реально сохранённые RandStream состояния. Persistent PHY caches допускается построить заново из того же cfg.
- [x] Атомарная публикация: новый уникальный файл → закрытие → readback/валидация → SHA-256 → атомарное переключение manifest. Держать две последние проверенные точки. Ошибка записи новой не портит предыдущую; временный файл не является действующей точкой. Если самая новая повреждена, явно записать fallback к предыдущей и размер потерянного прогресса.
- [x] Runner вызывает `sim.run()` небольшими порциями и проверяет 600-second interval между завершёнными шагами; финальный результат вычисляет один раз. Интервал сохранения может увеличиваться на время длинного шага — это явно отражать, не обещать точные 10 минут при любой операции. Перед первой работой и по запросу pause создать точку.
- [x] Интегрировать с `runStaticCase`: новая необязательная checkpoint опция; старые вызовы неизменны. При restart проверять checkpoint identity и уже существующий completed marker. Готовый случай не пересчитывать, незавершённый не подменять новым ID. Checkpoint не становится `case-complete.json`.
- [x] Тесты: повреждённая последняя точка/прошлая цела; отказ изменённому коду или калибровке; сериализация shared handles; transient write failure; возобновление без дублей событий. Научные поля, таблицы, полученные отсчёты/CRC сравнивать `isequaln`; исключать только реально документированные поля wall-time, checkpoint/lifecycle исполнения. Нельзя исключить весь lifecycle или журналы ради зелёного теста.
- [x] Минимум один короткий тест контролируемого завершения собственного тестового MATLAB после готовой checkpoint и восстановления другим процессом. Это тест восстановления, не разрешение убивать настоящий большой опыт.

**Приёмка:** восстановление после исчезновения процесса доказано, известен размер точки и время записи; запуск до 2500 UE ещё не производится.

## Task 5: отдельный предварительный опыт четырёх нагрузок

**Files:** новые `experiments/runLoadProbe.m`, `tests/TestLoadProbe.m`, `verification/completion/stage-3/runVariant2.ps1`; существующий registry API и case runner. `runLoadPilot.m` сохраняет строгий пятинагрузочный контракт.

**Interfaces:** `report=runLoadProbe(options)`. Options: `designOnly`, `counts` строго `[100 500 1000 2500]`, `outputFolder`, `stage2AcceptanceFile`, `calibrationFile`, `registryFile`, `realizationId`, `execution`, `resume`, `budgetLedgerFile`. Report: `scope='variant2-preliminary-load-probe'`, `requestedCounts`, `completedCounts`, `missingFullPilotCounts=5000`, `fullPilotCompleted=false`, `status`, ID, per-case measurements и runtime hashes.

- [x] Design-only тест без MATLAB симуляции/создания каталогов/резервирования ID:

```matlab
p=runLoadProbe(struct('designOnly',true));
t.verifyEqual(p.requestedCounts,[100 500 1000 2500]);
t.verifyFalse(p.fullPilotCompleted);
t.verifyEqual(p.missingFullPilotCounts,5000);
t.verifyError(@() runLoadPilot(struct('designOnly',true, ...
    'counts',[100 500 1000 2500])), 'nbiot:experiments:PilotOptions');
```

- [x] Реализовать последовательный Static runner, переиспользуя calibration/runtimeManifest/runStaticCase/saveResult/verifyCase. Не скопировать весь пятинагрузочный runner вместе с его hard timeout/failure cleanup. Готовые функции извлекать в общий helper только при фактическом дублировании и с сохранением поведения старого пилота.
- [x] Один свежий ID из `availableRealizationIds(...,'stage-3-load-pilot',1000:3999)`; выбрать при запуске, не вписать занятый/предполагаемый номер в план. ID 1064 и диапазон 0–999 не использовать. Один writer реестра и исходный snapshot. Все четыре размера получают один ID, не считаются четырьмя независимыми реализациями.
- [x] При `resume` проверять assignment role/source, completed-маркеры/хеши и контрольные точки; не резервировать ещё один ID. Новое выделение в `planned`. `budget-paused`/живой опыт не закрывать как failed. В progress manifest хранить owner/process identity, completed loads и pending loads. `completed` в реестре после четырёх валидных случаев обозначает завершение именно предварительного опыта по указанному source; это не полный пилот и не право повторно назначить ID другой роли. Продолжение до 5000 потребует отдельного запуска с проверкой той же assignment/совместимости, а не новой регистрации того же ID.
- [x] Общий budget ledger: `budgetSeconds=57600`, accumulated elapsed вычислительного этапа, phase/case start timestamps, warnings, pendingCases. Бюджет общий для новой физики и четырёх нагрузок; restart не обнуляет уже затраченное время. При 16 часах runner сохраняет `budget-paused` до следующего случая. Если текущая нагрузка завершилась после 16 часов, её результат принимается; следующая не начинается.
- [x] Завершение каждого случая: `verifyCase`, полный actualTicks=5000, packet balance, наличие radio/service/group exports, хеши и немедленная запись CSV/JSON/MAT сводки. Записать wall/core/checkpoint overhead, sampled memory peak, output bytes и итоговые счётчики. После ошибки сохранять предыдущие случаи; не запускать следующий без определения причины.
- [x] Тестировать lifecycle серии на зарегистрированном тестовом runner/искусственных результатах, без больших UE: бюджет исчерпан между случаями, вариант длится за порогом внутри случая, reuse completed, corrupted checkpoint, missing Stage 2 acceptance, отсутствующая лицензия, конфликт ID, false `fullPilotCompleted`.
- [x] `runVariant2.ps1` поддерживает `-DesignOnly`, `-Execute`, `-Resume -RunFolder <absolute path>`; default без `-Execute` — только план. Execute создаёт уникальный run folder и независимый worker Task 3. `preflight.json`, `budget-ledger.json`, `progress.json`, `worker.json`, stdout/stderr, memory CSV, checkpoints и case evidence сохраняются в этом run folder. Resume проверяет PID плюс creation time/command, не запускает дубликат живого worker.

**Приёмка:** пробный runner проверен без реальных больших расчётов, пятинагрузочный контракт сохранён.

## Task 6: закончить местную подготовку и зафиксировать единственный снимок

**Files:** затронутые тесты, документы состояния/лимитов/восстановления, `experiments/prepareExternalRun.m`, `tests/TestExternalRunPackage.m`, отчёт рядом с новым комплектом.

- [x] Выполнены относящиеся к текущим изменениям MATLAB-файлы порциями до 900 секунд: [32/32](../../verification/local/checks-20261014-142636-860/), [Stage 2 acceptance 10/10](../../verification/local/checks-stage2-acceptance-pathfix-4/) и отдельные integration/resume проверки ниже. Набор 32/32 включал `TestLoadProbe`, `TestScheduledStage2Budget`, `TestLoadPilot`, `TestStage2ScheduledResume` и `TestExternalRunPackage`.

```powershell
& .\verification\local\runBoundedChecks.ps1 -TestFiles @('tests/TestServiceKpi.m','tests/TestScheduledExecutionBudget.m')
& .\verification\local\runBoundedChecks.ps1 -TestFiles @('tests/TestSimulationCheckpoint.m','tests/TestLoadProbe.m')
& .\verification\local\testScheduledProcess.ps1
& .\verification\local\testBoundedProcess.ps1
```

- [x] Worker/checkpoint восстановлен только в коротком smoke: MATLAB writer и resume работали в разных процессах; универсальные process fixtures прошли отдельно. Остановки MATLAB по имени процесса не использовались.
- [x] Проверена интеграция метрик/checkpoint на 1 UE × 1500 ticks из распакованного комплекта; `verifyCase`, service KPI, `_groups.csv` и итоговый UI formatter прошли. Прежняя Adaptive цепочка не затронута.
- [x] Завершены входящие AGENTS/current-state/budget/local-checks/handoff/metric docs и инструкция диагностики/resume; проверены предупреждение и finish-current для случая, пересекающего бюджет, и запрет допуска следующего.
- [x] Финальный комплект собран после correction seed43: 311 файлов и все hashes проверены; первый draft-пакет сохранён как исторический после того, как pretrial выявил нехватку fresh IDs при seed 42. [Финальный smoke](../../verification/local/package-smoke-variant2-20261014-seed43/smoke-report.json) — 1 UE / 1500 ticks, checkpoint/resume в разных MATLAB-процессах, `verifyCase`, service/group exports и UI formatter прошли.
- [x] Отчёт сборки хранится вне комплекта. Вычислительный код после снимка не менялся; рабочий запуск далее ведётся из текущей копии по сохранённому manifest. Документы состояния и runtime-журналы остаются снаружи пакета.

**Приёмка:** метрики/таймеры/восстановление готовы и коротко проверены; разрешение на реальные вычисления приходит из промпта новой сессии, а не из факта сборки.

## Task 7: выполнить свежую Stage 2 проверку и принять физику

**Files:** существующие `stage2Targeted.m`, `stage2Physical.m`, `validateCollisionCapture.m`, `acceptStage2Evidence.m`; новый `TestStage2ScheduledResume.m`; инструкции в `runVariant2.ps1`.

- [x] Preflight перед 16-hour этапом пройден: свежий targeted-run подтвердил MATLAB R2025b и LTE Toolbox 25.2; AMD Ryzen 7 3700X (8C/16T), RAM 127.93 GiB всего/104.59 свободно, C: 65.25 GiB свободно; второго MATLAB worker нет. Порог 20 GiB disk/16 GiB RAM соблюдён. Для оценки выхода старые физические evidence folders занимают до 24.5 MB, короткий checkpoint из packaged smoke — 2 485 676 байт; новый прогресс пишет отдельный файл на случай, запас на диске достаточный. Новые parallel jobs не запущены.
- [x] В physical identity записаны MATLAB `25.2.0.2998904`/R2025b, LTE Toolbox `25.2`, code manifest `43aa0940…`, package manifest `5f865f38…`, calibration `a35b66d0…`, receiver revision, матрица 15×10/1500 ticks, role и seed `43`. Seed 42 оставил только 6 свежих ID для трёх одинаковых преамбул; read-only probe подтвердил seed 43, решение записано в AGENTS и документации Stage 2. Общий ledger начал учёт с первого физического случая; все 57 600 секунд общие с четырьмя Stage 3 нагрузками.
- [x] На финальном seed43-коде запущен `stage2Targeted()`: [38/38 за 79.92 с](../../verification/completion/stage-2/targeted-run-20261014-145209-604/stage2-targeted.log), журнал подтверждает MATLAB R2025b и LTE Toolbox 25.2. Состав набора не менялся; seed/scheduled/checkpoint tests проверены отдельно.
- [x] Stage 2 seed43: 232/232 физических случаев завершены в [host-run](../../verification/completion/stage-2/host-run-20261014-145455-264-a60dcedd/); MAT/progress и отчёт приняты после сверки всех хешей, registry, 150 trials, 80 receiver checks и 8 replay rows. Worker exit 0; elapsed 1774.57 с, sampled peak tree working set 1.09 GiB.
- [x] До реального запуска добавлено атомарное сохранение каждой готовой физической строки/trace, identity и назначенного ID в progress manifest. Resume переиспользует только проверенные случаи той же матрицы/версии. `TestStage2ScheduledResume` с короткими искусственными trials проверяет пропуск готового, несовместимость и сохранение planned ID при budget pause.
- [ ] Если серия упёрлась в 16-hour admission budget между случаями, сохранить неполный физический набор и не выдавать acceptance; нагрузки не начинать. Живой текущий случай при этом не обрывать.
- [x] После матрицы выполнена техническая проверка и создан новый [acceptance](../../verification/completion/stage-2/acceptance.json) для текущего targeted/report; reviewer указан `Codex technical review`, scope `targeted-tests/physical-results/limitations`, `humanReviewed=false`. Старый acceptance сохранён [в архиве](../../verification/completion/stage-2/acceptance-archive/acceptance-pre-fresh-stage2-20261014.json).
- [x] Host reconciliation после exit 0: текущий `runStage2Physical.ps1 -Resume` упал на отсутствующих в worker manifest полях `exitCode`/`elapsedSeconds`/`settledAtUtc`; manifest сохранён в `.pre-resume-reconcile.json`, поля восстановлены из process-report, повторный `-Resume` завершился `physical-completed`. Исходный код не менялся.

**Приёмка:** новый валидный допуск относится к текущему вычислительному снимку. Если найден дефект, сначала исправить и определить затронутые доказательства; нагрузочный этап не обходится.

## Task 8: реальные четыре нагрузки, отчёт и переход

**Диагностика 14 октября, 20:57 UTC:** выполняющийся 500 UE / ID1088 не прерывался. Progress tick4980 может оставаться неизменным внутри финального `sim.result()`; фактическую фазу по нему установить нельзя. Read-only подсчёт checkpoint tick4454 показал 219 594 overlap-события и около 24,11 млрд попарных проверок в текущей проверке повторов; stack scan дал только неподтверждённый кандидат `arrayfun`. Patch для пакетной проверки пар, группировки компонент по occasion и отдельной фазы `result-finalizing` подготовлен вне checkout; обычный `git apply --check` проходит. Patch не применён, тесты и замер скорости не выполнялись. Текущая функция `runLoadProbe` проверяет общий лимит между случаями; при оставшемся лимите загруженный процесс может автоматически перейти к 1000 UE на старом коде. Подробности и границы вывода: [диагностические заметки](../../../../diagnostics/matlab-live-20261014/variant2-performance-fix-notes.md).

**Review 15.10:** patch исправлен по фактическому API симулятора: `sim.currentTick` доступен read-only, а `exportCheckpointState()` запрещён для terminal состояния. Подготовлены тесты одного оставшегося тика при resume и controlled failure до завершения result, плюс synthetic cases для дубликатов, пропущенной/лишней пары и interleaved occasions. Отдельный `git apply --check` проходит; код и тесты не применялись и MATLAB не запускался из-за активного worker. `validateResumeState` и `runtimeManifest` подтверждают, что source/runner hash входят в resume identity; поддерживаемый переход того же run на новую версию не найден. Worker может сам начать 1000 UE на текущей версии. Не менять исходники/хеши и не использовать `pause.request` как границу 500 UE. После выхода worker выполнить только bounded tests, сохранённые-data `isequaln` и числовой pair benchmark; продолжать размеры лишь на совместимой версии и в пределах admission budget.

Подготовлен [черновик отчёта нагрузки](../../../verification/completion/stage-3/variant2-20261014-152828-532-04934654/variant2-report.md). В нём отделены завершённые 100 UE, активный resumed 500 UE и ещё не допущенные 1000/2500 UE; дополнить реальными статусами после освобождения worker.

**Снимок 15.10, 21:32 UTC:** PID 20816 жив (CPU 24 031.53 с, рабочий набор 16.30 GiB); worker-progress остаётся tick4980 от 14.10 15:34:50 UTC, валидный checkpoint4454, 500 UE ещё не оформлен. Ledger хранит 10 136.882 с settled, активный resume не начислен до завершения. Оценочный суммарный расход включая активный wall time около 33 895/57 600 с; следующий admission оставлен текущему runner.

**Files:** `runVariant2.ps1`, `runLoadProbe.m`, созданный run folder; `docs/current-state.md`, `docs/experiment-budget.md`, ledger.

**Наблюдение 17:13:36 UTC:** 500 UE / ID1088 остаётся в MATLAB PID 20816 на tick 4980; worker elapsed около 8241 с, прогресс не обновлялся около 5896 с. Предупреждение выдано, `samplerError` пуст; CPU вырос до 8487 с при стабильном рабочем наборе около 15,18 GiB. Последний проверенный checkpoint — tick 4454, SHA-256 `c99f6af069251a31bd4bdf65c7b6b2a0b4b6c02147f0d1bb6377a7384a6d0e4d`. Процесс оставлен работать; следующий размер не запускать до завершения текущего и проверки admission.

- [ ] После успешной Task 7 и наличия остатка бюджета последовательно выполнить 100, 500, 1000, 2500 UE. Проверку admission делать перед каждым случаем. Не вводить отдельный пользовательский выбор ID/формул и не спрашивать повторно разрешение на выбранную последовательность. **Выполняется:** `runVariant2.ps1 -Execute` создал [run folder](../../verification/completion/stage-3/variant2-20261014-152828-532-04934654/); 100 UE / ID1088 completed and verified, сейчас активен 500 UE.
- [x] После `-Execute` PowerShell обнаружил отсутствующее поле `updatedAtUtc` уже после запуска worker. PID и полные командные строки проверены; worker оставлен работать. Сохранены резервные копии `run-manifest.pre-running-status-reconcile.json` и `worker.pre-final-reconcile.json`; статус переведён в `running`, UTC start time MATLAB нормализован, поля будущей сверки добавлены. Исходники не менялись.
- [ ] Использовать Task 4 checkpoints каждые примерно 10 минут на безопасной границе шага. Периодический файл/heartbeat подтверждает работу; время пересечения порога показывать warning. Состояние этапа сохранять после каждого готового случая и при исключении. Первая контрольная копия сохранена на tick 1540 через ~10½ минут: 60 319 900 bytes, SHA-256 `b58fe88067500df3f07167548d2cde83810ebee3c8a91f2ca010732138eac57d`; для следующих размеров мониторинг продолжается. В 500 UE сохранён первый checkpoint на tick 645: 625 732 853 bytes, SHA-256 `495b98efc76368f078b7fd5a014f54682cc9ab3c74abc9099a186e94ac0adc5d`; на этом снимке sampled peak tree 3.21 GiB. Следующая копия tick1060 — 781 357 186 bytes, SHA-256 `28d14728fb2cd8d8e27b7e05725842554e6826d5c62c1220ebe455252ac54af2`, sampled peak tree 3.57 GiB. Третья копия tick1414 — 875 213 860 bytes, SHA-256 `2cf6b76941249ba2eaa51699492b5fdd0d054bc0e3414263a8a4af79ba9ab08a`, sampled peak tree 3.85 GiB. Четвёртая копия tick1829 — 989 341 999 bytes, SHA-256 `63b56d41710e6ad23019a31dd648364aefa449c98cae02f5af238f4416dbd3a6`, sampled peak tree 4.14 GiB. Пятая копия tick2150 — 1 039 760 124 bytes, SHA-256 `c40c27c3de9c6d8bded2fd008b5a9b4c875e94555fc42b66fddbdef21aeb2bd5`, sampled peak tree 4.33 GiB. Шестая копия tick2436 — 1 118 006 020 bytes, SHA-256 `dfb62529d2647593c6b30aa551b2065cf6b9a00a2ae5128e935ed0b1d8889f0f`, sampled peak tree 5.51 GiB. Седьмая копия tick2738 — 1 194 680 389 bytes, SHA-256 `61230afdf0f2dc175924155ae5a860a94645c4fe737d7cfdcfcdf961524dfe81`, sampled peak tree 5.71 GiB. Восьмая копия tick3045 — 1 269 571 480 bytes, SHA-256 `453b34d310e323fd842bc39075cdc74ccbe1cc46fe66f8a990cb83194f9f864f`, sampled peak tree 5.9 GiB. Дополнительный checkpoint на tick 2980 — 87 266 324 bytes, SHA-256 `279ccd73e1c7dc538d772fc2bb0060a9bded976f5863a3a099278acaf66d5a5d`. Heartbeat 14:37:41 UTC: 500 UE / tick3285, worker elapsed 7752 с, 330.6 с без продвижения, warning отсутствует, sampled tree peak 6.33 GB (5.90 GiB); последний завершённый checkpoint tick3045, в каталоге виден временный `.tmp.mat` без подтверждённой фиксации. Новый checkpoint tick3300 сохранён, 1 339 419 101 bytes, SHA-256 `8958ca20540069249bb8d6e12e8b53371c65829b4b1bf5f42fbe0f3f91936e83`. Heartbeat 14:39:13 UTC: tick3357, elapsed 7843.55 s, no-progress 8.12 s, warning absent, sampled current/peak tree working set 3.92/6.53 GB. The first 500 UE attempt failed at tick3588 with nbiot:experiments:CheckpointWrite / Java heap OOM while hashing the 1.42 GB checkpoint; tick3300 remains the last published checkpoint (1,339,419,101 bytes, SHA-256 8958ca20540069249bb8d6e12e8b53371c65829b4b1bf5f42fbe0f3f91936e83). The failed attempt was charged 6449.206 s; budget ledger before resumed attempt is 10136.882/57600 s. Project-local java.opts -Xmx32g raised Java max heap to 31,496,601,600 bytes without source edits. After backing up and reconciling stale owner/worker metadata, the same ID1088 case restored tick3300 and reached tick3318 at 14:59:27 UTC; no warning/error. A larger checkpoint now published successfully under the temporary heap profile: tick3716, 1,428,706,130 bytes, SHA-256 0ba3ff1a1cdbdc29840d1960d1e8a50ddaa9719f6ff7cd245b436f5e0b7fb1e0; external Get-FileHash matched the manifest. Heartbeat 15:13:08 UTC: tick3717, resumed-worker elapsed 1013.43 s, sampled current/peak tree working set 7.46/9.53 GB, no warning/error. Heartbeat 15:23:52 UTC: tick4036, resumed-worker elapsed 1657.96 s, no warning/error, sampled current/peak tree working set 11.73/13.79 GB. Checkpoint tick3991 (1,443,806,386 bytes) independently hashed; manifest and Get-FileHash both report 05fb25f5722b61792c6105f6ca88e6a4937b1ac2ceb8baebf4f7ef421547bf56. Heartbeat 15:33:35 UTC: tick4531, resumed-worker elapsed 2240.95 s, no warning/error, sampled current/peak tree working set 16.23/18.22 GB. Checkpoint tick4454 (1,456,966,482 bytes) independently hashed; manifest and Get-FileHash both report c99f6af069251a31bd4bdf65c7b6b2a0b4b6c02147f0d1bb6377a7384a6d0e4d. Heartbeat 15:49:59 UTC: tick4980, no-progress warning issued after 908.83 s (configured threshold 900 s), samplerError empty; MATLAB PID20816 remained active with CPU 3482.73 s and 16.29 GB working set. Last checkpoint tick4454 remains valid. Heartbeat 16:55:19 UTC: tick4980 unchanged for 4828.87 s, warning=true, samplerError empty; resumed-worker elapsed 7144.54 s; MATLAB PID20816 active with CPU 7412.97 s and 16.30 GB working set. The last verified checkpoint remains tick4454 (1,456,966,482 bytes, SHA-256 c99f6af069251a31bd4bdf65c7b6b2a0b4b6c02147f0d1bb6377a7384a6d0e4d). Read-only code inspection of `runCheckpointedExperiment.m` shows progress is written after `sim.run(state.nextTick)` returns, so the current tick remains at 4980 while that call executes. The step body handles ready receptions, timer/arrival updates, pending-transmission scheduling, and per-UE queue accounting; the expensive suboperation is not yet isolated. Keep Task 8 open while 500, 1000 and 2500 remain.
- [ ] Выполнить `nbiot.results.verifyCase` для каждого completed-случая, сверить scientific horizon/схемы/хеши/балансы и свежие метрики. Не засчитывать partial, development fixtures или старый ID 1064 как новую независимую реализацию. Первый completed: 100 UE, ID1088, 5000 ticks, все 10 файлов совпали с marker по размеру/SHA-256; `verifyCase` выполнен перед фиксацией. Delivered 6, dropped 86, unfinished 8, service outage 0.94, wall time 1939.69 с; ID/хеши сохранены в run folder.
- [ ] Итоговый `variant2-report.md` рядом с run folder: реальные времена, число завершённых размеров, ресурсы, время checkpoint, работа resume, ошибки/ограничения, причины остановки между случаями. Четыре размера одного ID — один предварительный парный опыт.
- [ ] Состояния отчёта: `preliminary-completed` только при четырёх принятых размерах; `budget-paused` при исчерпании admission budget; `needs-attention` при неисправности или несовместимости. `fullPilotCompleted=false` во всех вариантах этого плана. Отметка failure отдельного вычисления не отменяет ранее проверенные результаты.
- [ ] Кратко обновить current-state: сделано / проверено / осталось. Не пересобирать комплект ради этого статуса. Закрыть только реально выполненные пункты исходного маршрута; полная задача 7 остаётся открыта без 5000 UE и измеренных образцов трёх методов/трафиков.
- [ ] Предложить следующий конкретный объём по измеренным временам: отдельно 5000 UE на текущем ПК или контрольный замер на 9950X3D. Для новых больших серий запросить именно новое машинное время/объём, а не повторное утверждение выполненного плана. Этапы 8–10 исходного маршрута не запускать автоматически.

**Приёмка варианта 2:** местный остаток закрыт и проверен; поведение таймеров/восстановления доказано; свежая физика принята; четыре предварительных нагрузки проверены либо честно сохранён budget-paused с точным следующим случаем. Последний статус является сохранённым промежуточным результатом, а не полным выполнением цели.

## Оценка вычислений и граница обещаний

| Состав | Старый замер / рабочая оценка |
|---|---:|
| Физическая проверка нового кода | Ориентировочно 1–2 ч; старые 230 проверок занимали около 31 мин |
| 100 UE | 34 мин |
| 500 UE | 1 ч 28 мин |
| 1000 UE | 2 ч 26 мин |
| 2500 UE | 6 ч 26 мин |
| Четыре старых случая вместе | 10.89 ч |
| Вариант 2 после подготовки | Ориентир 12–16 ч, возможное превышение текущим случаем |

Новые метрики, checkpoint I/O, состояние ПК и обнаруженные ошибки могут изменить время. Увеличение разрешённого времени не ускоряет расчёт. Этот план не даёт календарной оценки полной статистической серии, обучения и итоговой приёмки.

## Проверка плана и передача

- [x] Текущие файлы и интерфейсы сверены чтением; новые функции явно обозначены как добавляемые.
- [x] Сохранены ограничения обычных проверок, отказ от принудительного timeout долгого случая и различие предварительного опыта/полного пилота.
- [x] У каждой из пяти опасных ситуаций Review Focus есть задача и конкретная проверка.
- [x] Старые результаты, калибровка, полный пилот и файл преподавателя не назначены к повторной разработке/перезаписи.
- [x] План подготовлен без MATLAB, физических запусков, выделения ID и сборки комплекта.

**Следующая сессия:** начать Task 1, выполнять последовательно через `superpowers:executing-plans`. Ссылка в current-state ведёт на этот план; долгие запуски разрешаются конкретным промптом владельца для варианта 2. Подготовку плана не выдавать за выполнение его задач.
