# Оптимизация и проверка кандидата — 2026-10-06

> Исторический отчёт. На 13 октября 2026 актуальные измерения четырёх нагрузок находятся в [experiment-budget.md](experiment-budget.md), статус и границы доказательств — в [current-state.md](current-state.md). Старые очереди запусков ниже не выполнять на текущем ПК: долгие расчёты перенесены на другую машину по решению владельца.

## Поставка GitHub v2.0.0

Для этой поставки свежие результаты полного набора тестов, одиночного запуска, трёх случаев, resume и отдельного GPU-бенчмарка находятся в [verification/v2-validation.json](../verification/v2-validation.json). Все исходники основного симулятора совпадают с принятым кандидатом. При упаковке изменены только входной и выходной пути benchmarkNprachGpu: его MAT-вход добавлен в verification/fixtures, а выход пишется в results/gpu-fft. Совокупные хеши версии указаны в [source-manifest.json](../verification/source-manifest.json).

Выбранные прежние отчёты этапов включены в [verification/reports](../verification/reports). Ссылки на work/optimization-evidence ниже относятся к истории разработки на исходной машине; это не обязательная папка для запуска проекта у коллег.

Эта папка является отдельным кандидатом. Рабочий исходный проект и проверенный архив сохранены. Исторические отчёты в docs описывают состояние до этих патчей; текущие результаты перечислены здесь и в acceptance-coverage.md. Штатная последовательная модель использует CPU и MATLAB R2025b/LTE Toolbox; Parallel Computing Toolbox нужен только для явно вызванных process/GPU экспериментов.

## Что изменено и доказано

### Проверка инструкции для коллег — 2026-10-06

Команды нового README выполнены в отдельной чистой папке на том же Windows ПК с MATLAB R2025b и LTE Toolbox. Перенесены src, configs, examples, experiments, tests, docs, setupProject.m и принятая калибровка; старые результаты не использовались. Все 114 перенесённых MATLAB-файлов побайтово совпадают с кандидатом. Исторический корневой демонстрационный test.m в эту проверку не включался; README его не вызывает.

checkEnvironment(true) прошёл четыре PHY roundtrip. runSingleUe завершился за 17,240 с и доставил 1 пакет / 1600 полезных бит. Полный набор: 112 passed, 0 failed, 0 incomplete. Серия с одним UE и ID 0, 1, 2 завершилась за 15,428 / 15,839 / 14,732 с собственно расчёта; MAT/CSV первого случая прошли verifyCase. Повтор серии с resume вернул тот же manifest без нового расчёта. Весь проверочный сценарий занял 310,891 с. Исходники и калибровка во время запуска не изменились.

Свидетельства: readme-verification.txt, readme-fresh-suite.mat и readme-verification.mat/json в work/optimization-evidence рабочей задачи. SHA источников этой чистой копии: 8ed30829a4ae54d0888ceee323527c40e36c111035e2df20f732e6c0e495ce18; он отличается от полного кандидата из-за исключённого test.m. Это проверка переноса папки на том же ПК, а не подтверждение других ОС или версий MATLAB. Большие нагрузки и статистическая приёмка не запускались.

| Этап | Свидетельство | Граница результата |
|---|---|---|
| O1 | Реальный baseline и26/26 comparisons | source/calendar/API/RNG/payload/KPI/dataset/CSV защищены |
| O2 | Индексы DL календаря;54/54 suite;26/26 comparisons |1000UE4763.3s против5106.7s:6.72% экономии; одиночный UE не ускорился |
| O3 | UUID staging, marker-last, SHA MAT+6CSV, schema/readback, resume |13/13 targeted,71/71 suite; реальный resume не повторяет расчёт; marker.tables missing/duplicate отвергаются |
| O4 | Частные worker directories, manifest у координатора, process pool1/2/3 |18 fields exact для3 реальных PHY cases;3workers63.525s vs sequential94.238s на малом стенде; peak aggregate6.13GiB |
| O5 | Новый100UE profile2249.877s;18/18 exact vs protected profile | Кэш постоянных профилей:112/112suite,17result fields/6CSV exact; локально4.596× |
| R1 | All-tone group partial quadratic presence + SIC timing | threshold0.005; noise0/20000; все6 независимых adjacent interference условий приняты,120000окон |
| R2 | Current-state/current-grant ACK guard, alias regression | stale события отвергаются; fresh fading/noise/foreign0falseACK в3×6000; точный waveform alias остаётся |
| R3 | CP/NRS coarse timing, selective channel estimate, pilot noise residual |18 независимых DL условий по500 trials:0 ошибок; per-condition upper BLER0.007351 при20dB |
| GPU | RTX3080Ti double kernel + полный отдельный1UE prototype |54/54 substantive fields exact, GPU median21.779 vsCPU18.498s; backend не включён |
| Protocol | TestRadioProtocol12/12 | physical losses,8RA/4HARQ, RV/NDI, unique delivery, второго packet, same-tick deadlines |
| Diagnostics/export | captureFailure4/4; plotSweepSummary3/3 | selected window hard byte budget, separate truth; incomplete/NaN/counts/CI explicit |
| Scheduling | TestSchedulingFairness2/2 | EDF и requeue fairness при единственной доступной паре NPDCCH |

## Отклонённый прототип сокращения DL timing поиска

Микропрототип сохранил выборки grid/channel/CFO и решения на128физических случаях; helper был быстрее в3.37 раза. Эти проверки оказались недостаточны для принятия изменения.

Полный100UE расчёт с pruning завершился за1488.018s. Сверка сохранённого результата показала точное совпадение конфигурации, KPI, расписаний, статуса, счётчиков пакетов и PHY summary, но различия в observedLog и dataset. Требование точного сравнения журналов и экспериментальных данных не выполнено. Эти версии файлов восстановлены; SHA-256 исходников снова равен проверенной до pruning версии d67fc6cac7ac9f27852177b4a1baee2c70f98b3bfe5de2fa3507397d93d2ff46. Полный точный diff вложенных различий и CSV пока не проверен.

Сохранённый после-pruning MAT содержит доказательство провала: dl-pruning-comparison-preassert.mat. Расчёт не запускается повторно при resume, но сравнение остановилось до CSV из-за различий верхнего уровня. Тогда внешний запуск MATLAB был отклонён из-за отсутствия кредитов; после их восстановления проверка README выше успешно выполнена вне sandbox. Вложенные различия pruning пока не исследованы. Эта оптимизация не входит в принятую версию из-за несовпадения результатов.

Timing pre-patch100UE измерялся одновременно с1000UEи короткими диагностиками; post-patch100UE последовательный. Их отношение времени будет описано как наблюдаемое при разных режимах нагрузки, не изолированный коэффициент ускорения.

Материалы проверки находятся в work/optimization-evidence исходной рабочей задачи. При подготовке переносимой папки выбранные подтверждающие файлы копируются в verification; исторические CSV и новые результаты не смешиваются.

## Воспроизводимые команды

```matlab
setupProject;
environment=checkEnvironment(true);
testResults=runtests('tests');
assertSuccess(testResults);
```

Калибровка:
```matlab
cfg=nbiot.config.defaultConfig();
report=calibrateNprach(cfg,fullfile(pwd,'results','nprach-calibration.mat'),...
    struct('fitRealizationId',4000,'validationRealizationIds',4005:4008));
interference=validateNprachInterference(struct('realizationId',4004,...
    'calibrationFile',fullfile(pwd,'results','nprach-calibration.mat'),...
    'outputFolder',fullfile(pwd,'results','interference-new')));
```

Эти ID обеспечивают детерминированное воспроизведение сохранённой проверки. Для **новой независимой** приемки после подбора алгоритма/порога выбрать ранее не использованные validation IDs/substreams и новый каталог. Повтор той же выборки не увеличивает независимое n. Failed holdout переходит в development.

В кандидате results/nprach-calibration.mat принят composite report group-partial-quadratic-v2/SIC-public-template-v1. SHA-256:1068f3daaa8c2fb8d62bc34671f63e1462b6f2b81da9f1b8cf75820c013216e4. noiseAccepted=true и interferenceValidated=true. Файл legacy сохранён как nprach-calibration-legacy-v1.mat. Noise-only report допускает диагностические проверки и сам по себе не подтверждает interferenceValidated.

Fresh interference realization4004 использует полный UL round-trip delay2d/c с sync±2us, ближайшую допустимую соседнюю полосу NPUSCH и Rayleigh3tap/CFO±200Hz. На20000окон/строку: Data20/40dB2/1false, Msg3 3/4false, Control0/0false; верхние точные95%границы0.0003612/0.0002786/0.0004383/0.0005120/0.0001844/0.0001844. Fresh noise realization4005:0/20000, upper0.0001844. Порог зафиксирован до этих данных; ранний failed holdout при0.004 остался development.13 зависимостей не менялись во время gate.

Малый воспроизводимый запуск/resume:
```matlab
options=struct('counts',1,'burstDurations',100,'realizationIds',0,...
    'calibrationFile',fullfile(pwd,'results','nprach-calibration.mat'),...
    'outputFolder',fullfile(pwd,'results','single-new'),'resume',true);
manifest=runStaticSweep(options);
manifest=runStaticSweep(options); % использует только verified completed bundle
report=plotSweepSummary(fullfile(options.outputFolder,'manifest.csv'),...
    fullfile(pwd,'results','single-summary'));
```

Параллельный запуск вызывается отдельно через runStaticSweepParallel. Process workers не обмениваются каналами/RNG/календарями и не пишут общий case result. Manifest и принятие результата принадлежат координатору.

## Радиоограничения

NPRACH presence использует12 публичных templates и четыре symbol groups. Group partial regression отделяет разные индексы; нельзя разделить двух UE с одинаковым NInit только presence-кандидатом. Их capture должен оцениваться по реальным Msg3/Msg4.

Development near-far: strong receive SNR20dB,100 независимых физических trials paired по ratio/threshold.0..30dB:100/100 weak detections;40dB:95/100 при0.005, CI[0.8872,0.9836]. При40dB timing error>8samples в10/95 detected windows. Повышение порога снижает чувствительность; эти данные не объявляются независимой interference acceptance.

UCI не имеет CRC. RNTI100/ACK1 и RNTI2103/NACK0 могут дать идентичные7680samples. При правильном активном BS ресурсе различить их по waveform невозможно. Current-context guard устраняет логические stale completions. Свежий конечный holdout: Noise/ForeignACK/ForeignNACK0/6000falseACK каждый, upper95=0.0006146; OwnACK/OwnNACK1000/1000correct каждый, upper95failure=0.0036821. Условия: conditional receive20dB, independent Rayleigh/CFO±200Hz, post-TA residual delay±4.34samples. Статистический gate не устраняет известный alias и не подтверждает любой остаточный timing error. Подробности: uci-ambiguity.md.

DL admission: default one-way delay≤6.407samples, latest multipath примерно8.135samples, CFO±200Hz. Fresh20dB validation использует500 независимых каналов на строку; paired условия не объединяются для ложного n9000. Wrong-RNTI/noise regressions конечны, невозможность CRC-ошибок не заявляется. Дополнительно измерена SNR-кривая−20/−10/0/10/20/30dB,24rows×100trials,655CRCfail/0wrongaccepted. CFO/timing RMSE и Student-t CI среднего signed error сохранены отдельно; выбранное FFT окно не является несмещённой оценкой первой задержки.

## Диагностический capture

```matlab
cfg.logging.saveWaveforms=true; % до создания симулятора
sim=nbiot.NBIoTSimulator(cfg);
sim.run(100);
artifact=captureFailure(sim,struct('direction','UL','receiverId',0,...
    'startSample',99*1920,'endSample',100*1920,'byteBudget',512*1024,...
    'outputFolder',fullfile(pwd,'results','captures')));
```

Это явный capture выбранного недавнего окна, не автоматическая запись всех сигналов. История канала ограничена128ticks. receiver.mat содержит RX/public config/metadata; truth.mat используется отдельно только анализатором. Размер всех MAT/JSON данного capture проверяется фактически; превышение удаляет только его частные незавершённые файлы. События/RNG/KPI после capture совпали с контрольным запуском.

## Незавершённая научная приемка

Fresh R1 interference, UCI fading statistics и финальная одиночная цепочка завершены. Одиночный полный5000tick run:16.846s,1delivered/1600bits, RA1success, Data8decoded/0CRCfail, mean delay612ticks, verifiedMAT+6CSV. До дополнительного кэша профилей весь набор109/109passed. Требуются новые100/1000/5000UE измерения времени и суммарной памяти, независимый capture pilot и10 внешних realizations с CI. Полная сетка15условий×100=1500runs не запускалась. Старый8-day план не активируется автоматически. Масштаб5000 и общий выигрыш новой радио-версии пока не подтверждены.
