# Короткие местные проверки

Реализовано 13 октября 2026. На текущем ПК используем профиль `local-development`: до 10 устройств, горизонт до 5000 мс, не более 300 секунд на случай и 900 секунд на выбранный набор. Научная конфигурация не переписывается ради ограничения. `configs/localDevelopment.m` возвращает отдельные параметры исполнения.

Большие прямые вызовы `nbiot.runExperiment`/`NBIoTSimulator`, обычные/параллельные серии и полный load pilot блокируются до симуляции. Для новых параллельных jobs здесь используйте последовательный runner; просмотр уже завершённых результатов через parallel resume разрешён. Полная NPRACH-калибровка относится к другой машине. Большая collision-матрица проверяется по числу случаев до резервирования ID и создания каталогов.

## Запуск тестов с жёстким пределом времени

Из корня рабочей копии в PowerShell:

```powershell
& .\verification\local\runBoundedChecks.ps1 -TestFiles @('tests/TestExecutionBudget.m','tests/TestLoadDataset.m')
```

Обвязка запускает каждый явно выбранный файл тестов отдельным MATLAB-процессом. Выбирайте файлы, а не папку `tests`. Внутренний таймер MATLAB действует от начала создания симулятора и проверяется между этапами/шагами; жёсткий предел при блокирующих операциях обеспечивает эта внешняя обвязка.

В `verification/local/checks-<timestamp>` сохраняются stdout/stderr, MAT с тестовыми результатами и JSON со статусом. `timed-out`, код 124, означает остановку по времени; такой результат не считается прошедшим. Тайм-аут завершает собственную группу Windows-процессов, включая потомков после выхода родителей. Чужие процессы в группу не включаются.

`OwnedProcessJob.cs` использует встроенные Windows/.NET возможности. Установка сервисов и изменение постоянных настроек защиты не требуются. В системах, где Windows PowerShell запрещает запуск локальных `.ps1`, процессный флаг `-ExecutionPolicy Bypass` применяется только к запуску этих собственных скриптов; постоянная политика не меняется.

Проверка самой обвязки:

```powershell
& .\verification\local\testBoundedProcess.ps1
```

Пять проверок: успешный процесс, ошибка процесса, тайм-аут дерева с живым родителем и нетронутым соседним процессом, тайм-аут ребёнка после выхода родителя, запрет default load pilot до поиска MATLAB.

## Долгое исполнение варианта 2

Для разрешённых длинных запусков существует отдельный профиль `scheduled-local`; он не меняет `local-development`. Разрешены только роли Stage 2 collision diagnostics (до 10 UE) и Stage 3 load pilot (до 2500 UE), максимум 5000 ticks, без параллельных jobs. Для продолжения текущего случая укажите `timePolicy='finish-current'`: превышение `maxCaseSeconds` оставляет предупреждение и текущий процесс работает дальше. `maxSuiteSeconds` не прерывает начатый случай, но запрещает запуск следующего; Stage 2 runner сохраняет частичные доказательства со статусом `budget-paused` и списком pending cases.

Сначала после местной подготовки выполните свежий Stage 2 targeted-набор (38/38) с пределом 900 секунд. Он не запускает физическую матрицу:

```powershell
& .\verification\completion\stage-2\runStage2Physical.ps1 -TargetedOnly
```

Передайте напечатанный путь к журналу успешных targeted-проверок для свежей физической серии:

```powershell
$targetLog = 'C:\absolute\path\to\targeted-run-...\stage2-targeted.log'
& .\verification\completion\stage-2\runStage2Physical.ps1 `
    -ExecutionProfile scheduled-local -MaxCaseSeconds 57600 `
    -MaxSuiteSeconds 57600 -TargetedLog $targetLog
```

Runner сохраняет каждый готовый trial, receiver-check и replay атомарно в `physical-evidence\*.mat`, а ID, хеши и pending cases — в `physical-evidence\progress.json`. Общий `verification/completion/stage-2/budget-ledger.json` включает только свежую физическую серию и четыре Stage 3 нагрузки; targeted/preparation проверки в эти 57 600 секунд не входят. После паузы продолжайте тот же каталог, который скрипт вывел как `STAGE2_PHYSICAL_HOST_RUN`:

В профиле `scheduled-local` runner задаёт `realizationSeed=43` и сохраняет его в `stage2-host-run.json` и Stage 2 identity. Оставляйте этот seed неизменным при resume. Он нужен для новых ID, которые удовлетворяют условию трёх одинаковых преамбул; старые/default процедуры сохраняют seed 42.

```powershell
& .\verification\completion\stage-2\runStage2Physical.ps1 `
    -Resume -RunFolder 'C:\absolute\path\to\host-run-...'
```

Resume проверяет PID, время создания и команду прежнего worker, сверяет научную идентичность и целостность завершённых MAT-файлов, сохраняет прежние ID и не запускает второй расчёт поверх живого. `progress.json`, heartbeat, stdout/stderr и выборочная память находятся в папке `host-run-*`. Порог 900 секунд пишет предупреждение; он не останавливает долгий физический случай. После полного набора проверьте отчёт и только затем оформляйте Stage 2 acceptance.

Для разрешённого варианта 2 Stage 3 использует отдельный runner; не вызывайте `runLoadPilot.ps1`:

```powershell
& .\verification\completion\stage-3\runVariant2.ps1 -DesignOnly
& .\verification\completion\stage-3\runVariant2.ps1 -Execute
& .\verification\completion\stage-3\runVariant2.ps1 -Resume -RunFolder 'C:\absolute\path\to\variant2-run'
```

Первый вызов безопасно показывает размеры и бюджет. `-Execute` требует свежий файл `verification/completion/stage-2/acceptance.json` и общий `budget-ledger.json`; он создаёт новый run folder и одного worker. Для продолжения используйте тот же абсолютный путь. Перед `-Resume` проверьте `worker.json`: живой worker определяется по PID, времени создания процесса и точной командной строке; не запускайте второй. В `probe/progress.json` находятся завершённые и ожидающие размеры, а `probe/worker-progress.json` показывает фазу и tick активного кейса. `workers/worker-*/heartbeat.json` и `memory.csv` дают состояние процесса и выборочную память; `budget-ledger.json` хранит общий расход, активный кейс и предупреждения.

Если запуск вернул `budget-paused`, сохраните run folder и продолжайте только ту же серию после освобождения бюджета; новый размер не стартует автоматически за границей 57 600 секунд. При `needs-attention` изучите `probe/progress.json`, `preflight.json`, `case-evidence/`, `probe/n#####-id####/.checkpoint-*` и stdout/stderr. Не удаляйте `.checkpoint-*` или `.staging-*`, не освобождайте и не переназначайте ID вручную. Ошибки без завершённого кейса остаются `needs-attention`, а completed-кейсы проходят `nbiot.results.verifyCase` при resume.

## Короткий запуск ядра

```matlab
setupProject();
cfg=nbiot.config.defaultConfig();
cfg.simulation.numUE=1;
cfg.simulation.durationTicks=10;
cfg.traffic.kind='none';
cfg=nbiot.experiments.loadCalibration(cfg,fullfile(pwd,'results','nprach-calibration.mat'));
result=nbiot.runExperiment(cfg,[],localDevelopment());
```

Это проверочный сценарий, не научный опыт с горизонтом 5 с. На границе времени расчёт имеет `status='stopped'`, `stopReason='execution-budget'`; завершённые/незавершённые пакеты остаются различимы. При прямом `step()` выдаётся `nbiot:experiments:ExecutionTimeout`, чтобы вызывающая сессия могла явно обработать остановку.

## Другая машина

Профиль `external-machine` задаётся явно с role, maxUE, maxCaseSeconds и maxSuiteSeconds. Имя/адрес ПК не определяет профиль. Это защита от случайного запуска, а не запрет владельцу вручную задать внешний профиль.

Пример формы команды полного пилота **для другой машины**:

```powershell
& .\verification\completion\stage-3\runLoadPilot.ps1 -ExecutionProfile external-machine -MaxCaseSeconds 50000 -MaxSuiteSeconds 250000
```

Числа — пример явного бюджета, не подтверждение достаточности или разрешение запустить его здесь. Перед выполнением проверить версии и Stage 2 доказательства: старый acceptance относится к старым хешам кода и не подменяется новыми. Внешний parallel sweep ограничивает ожидание своих futures и отменяет их; блокирующий старт pool и сторонние runner-функции должны также находиться под процессной обвязкой. Большая серия и новая радиокалибровка здесь не выполнялись.
