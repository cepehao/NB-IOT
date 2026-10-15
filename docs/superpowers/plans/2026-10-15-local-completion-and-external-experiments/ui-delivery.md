# U1–U3, T1–T3: интерфейс, перенос и окончательная местная приёмка

Часть [единого плана](../2026-10-15-local-completion-and-external-experiments.md). Следовать [правилам координации](coordination.md). Перечисленные Create-файлы пока являются заданиями. Физические параметры, источники случайности и научные определения не менять ради быстродействия. Оценка этого пакета: 20–33 часа реализации + 4–6 часов ревью; ветка буквального расширения PHY/App Designer в U3 отдельно.

## TODO владельца от 15 октября: понятная сводка открытого отчёта

**Статус: отложено вместе с доработками, не реализовано.** Добавлено после пользовательской репетиции; это дополнение объёма к прежнему проверенному плану, оценить при его возобновлении. Включить в UI-работу после D3, до T1/T3; один владелец App/сохранения, без параллельных правок D3/U1/U2.

- [ ] При открытии сохранённого расчёта над таблицей/графиком показывать понятную карточку: режим; число устройств; тип появления сообщений; размер сообщения; длительность моделируемого времени; сколько сообщений запланировано, если это однозначно задано сценарием; сколько фактически создано, доставлено, завершилось неудачей и осталось незавершёнными. Для случайного потока не выдавать ожидание за точное число запланированных сообщений.
- [ ] Отдельно указать единицы: устройства, сообщения, байты, секунды модели; подписать временную таблицу «одна строка — ... мс». Расшифровать unfinished как «не завершились к концу наблюдения», а не «доставятся позже».
- [ ] Источник карточки — конфигурация и итог именно открытого сохранённого случая, с проверкой связи файлов через completion marker/identity. Не брать значения из controls следующего запуска и не угадывать по имени CSV. Если нужна компактная метаинформация, добавить проверяемый sidecar при сохранении и согласовать его с saveResult/verifyCase/export version; не грузить многогигабайтный MAT при каждом открытии отчёта.
- [ ] Явно отделить настройки следующего запуска от параметров открытого отчёта. Старый файл без части метаданных показывает «нет данных», а не текущие default значения. При нескольких открытых запусках — отдельная карточка/строка для каждого.
- [ ] Критерий приёмки: открыть сохранённые 100 UE при текущих настройках UI 10 UE; карточка отчёта показывает 100 устройств, 5 с, created=100/delivered=6/dropped=86/unfinished=8, а несвязанные параметры не подставляются. Отдельно проверить старый CSV без companion metadata, несовпадающую identity и разные условия нескольких отчётов. Научные результаты не менять.

Основание: владелец при открытии отчёта не смог определить размер/условия опыта и источник числа незавершённых сообщений. Запись в TODO не возобновляет остальной инженерный план.

- [ ] Дополнительный дефект из репетиции: на экране владельца нижний блок `radioEventLog` вкладки «Текущий запуск» не виден. В liveGrid задано 13 строк с фиксированными высотами и последней `1x`, без включённой прокрутки; места до нижнего журнала не хватает. Сделать весь журнал доступным на экране 1280×900 и при уменьшении высоты окна (прокрутка с ненулевой высотой журнала либо отдельная вкладка). Приёмка: владелец может открыть и читать радиособытия без MATLAB-команд и изменения системного масштаба. Сейчас только записано, исходник не исправлен.
- [ ] Уточнение владельца: журнал из четырёх видимых строк непригоден для объяснения процедуры. Нужны отдельная большая вкладка/открываемое окно, понятные названия событий и отметки времени. Различать время планирования передачи, её эфирный интервал и факт приёма: сейчас emitDownlink пишет rar_sent в currentTick при формировании будущей передачи, а grant указывает будущие startTick/endTick, что выглядит как мгновенный обмен. Не менять физические времена ради подписи; показать их смысл корректно. Дополнительные `nprach_detection count=0` после завершения пакета объяснять как проверку возможности доступа без обнаруженного запроса, не как новые подключения/ошибки.

## U1 — текущая радиодиагностика в интерфейсе, F9

**Зависимости:** R1, R3, D3 приняты; D3 освободил `NBIoTSimulator.m`. **Время:** 5–8 ч + ревью.

**Modify:** `src/+nbiot/NBIoTSimulator.m`, `src/+nbiot/+ui/SimulationSession.m`, `apps/NBIoTApp.m`, `tests/TestDisplayRefresh.m`, `docs/gui-walkthrough.md` (если такого файла нет — Create).
**Create:** `src/+nbiot/+metrics/RadioDiagnosticsAccumulator.m`, `tests/TestLiveRadioSummary.m`.
**Read:** `src/+nbiot/+metrics/radioDiagnostics.m`, `src/+nbiot/+results/EventLog.m`, текущие radioSummaryForUe и snapshot.

**Контракт:** новый `sim.liveRadioDiagnostics()` возвращает `struct('asOfTick',...,'status',...,'summary',...,'perUe',...)`. Cache только для представления, не входит в checkpoint, научные логи, runtime actions или RNG. Восстановленный объект сначала восстанавливает cache из журналов один раз; обычное обновление читает только `EventLog.since(cursor)`.

- [ ] Написать `RadioDiagnosticsAccumulator.update(truthDelta,observedDelta,receptionDelta,asOfTick)` и `.snapshot()`. В cache хранить события/счётчики по occasion и последние оценки по UE. Сопоставление occasion/attempt заимствовать из R1, не придумывать иной идентификатор. Для изменившихся occasions пересчитать диагностику R1 по их полному накопленному набору событий; заменить старый вклад новым. Не пересчитывать все прошлые occasions при каждом refresh.
- [ ] Обработать пустые occasions и поздние RA outcomes: отсутствие передачи не означает отсутствие false-alarm opportunity; неизвестный исход остаётся censored. Суммировать числители/знаменатели, затем вычислять доли; среднее от долей разных occasions запрещено. Последний SINR отмечать временем и available; неизвестное значение не заменять нулём.
- [ ] До реализации составить таблицу соответствий полей `radioDiagnostics.summary` → накопитель. Для поля, которое невозможно складывать напрямую, сохранять необходимые первичные counts/keys. Итоговый cache на полном наборе событий должен совпасть с batch R1 для каждого показываемого поля. Не требовать побайтового совпадения внутренних cache с научным result.
- [ ] В simulator добавить private cursors/cache и публичный accessor; создавать cache лениво. В `SimulationSession.snapshot` заменить терминальную зависимость radioSummary от `getResult()` на live accessor для running/paused. Терминальный научный экспорт сохраняет существующий R1 путь. Никаких `sim.result()` из работающего UI.
- [ ] В UI показывать «на текущий момент», время последнего события, известные коллизии, capture, SINR/доступность и пояснение «неизвестно», если данных ещё нет. Обновлять уже созданные controls; не перестраивать всю таблицу/графики на каждом tick. Значения не должны использоваться контроллером как вход ML.
- [ ] Проверки нового класса: два независимых occasions; поздний успех меняет capture; неизвестный outcome не становится неуспехом; пустой occasion учитывается; повторный snapshot без новых событий не запускает повторный batch; terminal cache совпадает с R1; после checkpoint rebuild совпадает со свежим cache.
- [ ] `TestLiveRadioSummary`: fixture-журналы без PHY проверяют арифметику; отдельный ≤2 UE integration сравнивает scientific result при редком/частом UI refresh. Через счётчик у тестовой фабрики доказать 0 вызовов result до окончания. Перехват исключения с выдачей нулевых метрик тест не проходит.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestLiveRadioSummary.m','tests/TestDisplayRefresh.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** текущие показатели доступны во время работы, финальные значения совпадают с batch; refresh не меняет результаты/RNG; стоимость обновления зависит от новых/изменившихся событий. **Стоп:** нельзя добиться равенства — оставить unavailable для проблемного поля, задача REVIEW_CHANGES, не объявлять F9 закрытой.

## U2 — выбор активной группы и явный внешний профиль GUI, часть F10

**Зависимости:** U1 и D4; файлы UI переходят одному исполнителю. **Время:** 3–5 ч + ревью.
**Modify:** `src/+nbiot/+config/defaultConfig.m`, `src/+nbiot/+config/validateConfig.m`, `src/+nbiot/+traffic/generateArrivals.m`, `apps/NBIoTApp.m`, `src/+nbiot/+ui/SimulationSession.m`, `examples/openNBIoTApp.m`.
**Create:** `tests/TestTrafficActivity.m`, `tests/TestExternalGuiProfile.m`.

**Контракт traffic:** `activityMode='all'|'explicit'`, `activeUeIds=[]`. По умолчанию all сохраняет прежнее поведение; explicit+[] означает никто не активен. Список — конечные уникальные целые ID в `[1,numUE]`. После проверки сортировать. Недопустимый список — ошибка конфигурации, не обрезка. Отсутствующие два поля старого сохранённого cfg нормализовать значениями по умолчанию до проверки обязательных полей.

- [ ] RED: all даёт прежние arrivals с теми же tick/payload; explicit [2 4] создаёт только их; у них те же per-UE времена и payload, что в all. packetId после удаления остальных может перенумероваться — сравнивать по ueId/sequence. explicit [] даёт пустой поток; повторы, 0, >numUE, NaN, дроби отвергаются. Проверить burst/periodic/poisson на ≤5 UE.
- [ ] В generateArrivals пропускать неактивных UE до обращения к per-UE streams. Не добавлять источник RNG и не двигать потоки активных устройств. В GUI добавить mode и список ID, например `2,4,5`; парсить split+str2double с проверками, без eval/str2num. Сохранять поля в cfg/export; отображать общее/активное число отдельно.
- [ ] Расширить `NBIoTApp(dialogs,options)` необязательным вторым аргументом, сохранив все текущие вызовы. `options.execution` по умолчанию local-development; options передаёт modelFile, modelAcceptanceFile и полную controllerPolicy по D4. Только явно переданный проверенный external-machine открывает внешний предел UI. Не заменять local-development на внешний профиль автоматически при вводе 11 UE.
- [ ] Session проверяет существующий validateExecutionBudget и соответствие cfg profile. Лимит текущего ПК 10 UE остаётся. Допустимый горизонт и число устройств внешнего профиля берутся из его проверенных полей; запрет превышения научного профиля не отменяется. Передавать model acceptance в реальный prepareRuntime, не доверять надписи accepted в GUI.
- [ ] В TestExternalGuiProfile использовать фабрику-заменитель только для проверки полей и отказов до симуляции: local 11 отвергается; explicit external с валидным бюджетом передаётся; отсутствующий/чужой acceptance не открывает Adaptive. Не выполнять реальную 11+ UE симуляцию. На ≤2 UE отдельно проверить обычный рабочий UI путь.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestTrafficActivity.m','tests/TestExternalGuiProfile.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** активная группа воспроизводима, all совместим, GUI различает локальный и внешний режимы. Это не закрывает автоматически все параметры §30 и требование App Designer §46: они в U3.

## U3 — закрыть расхождения буквального ТЗ, F10

**Зависимости:** начать обследование после P0, окончательно сверить после U2. **Время:** 1–2 ч на матрицу/решение; реализация дополнительной ветки отдельно.
**Create:** `docs/requirements-decisions.md`. **Modify после решения:** только конкретные согласованные GUI/profile файлы; это отдельная карточка U3a с обновлённой оценкой, не свободное разрешение переписать PHY.

- [ ] Выписать буквально требования §11, §30, §46 из `tmp/pdfs/audit-spec-20261015.txt`; рядом перечислить реализованные controls и ограничения в validateConfig. Каждому параметру дать статус: редактируется / фиксированный поддерживаемый профиль / не реализован. Отдельно 1 ms, 1.92 MHz, 500 ms окна, физические форматы и ограничения UI.
- [ ] Проверить установленную MATLAB R2025b и её локальную документацию App Designer. Наличие `.m` файла само по себе ничего не доказывает: текущий `NBIoTApp.m` — программно созданный uifigure. Определить, открывается ли приложение для редактирования в App Designer этой версии, а не только запускается как MATLAB function.
- [ ] Записать два конкретных варианта решения владельцу/преподавателю: (A) принять документированный фиксированный физический профиль и существующую программную GUI; (B) требовать буквальное расширение настроек и редактируемый App Designer artifact. Показать расхождения и цену ветки. Владелец пока **не** принял исключение; не заполнять approval за него.
- [ ] Если выбран App Designer: сделать поддерживаемым редактором приложение, использующее существующие SimulationSession/модель, перенести требуемые controls и callbacks, не дублировать физическое ядро. Пустой launcher-shell не считается выполнением без явного согласия. Проверить открытие, запуск и сохранение в целевой R2025b. Не генерировать `.mlapp` через недокументированные ZIP/internal API. Если доступ к редактору отсутствует, сохранить задание для ручного шага и назвать блокер.
- [ ] Если нужны иные numerology/sample rates/controller windows: сначала отдельная согласованная спецификация поддерживаемых значений, калибровки и проверок; исполнитель не снимает validateConfig ограничения вслепую. Эта ветка существенно меняет объём и не имеет честной оценки до выбора диапазона.
- [ ] Решение фиксировать: точный пункт, принятое поведение, кто/когда подтвердил, ссылка на подтверждение, необходимые тесты. При отсутствии ответа сохранять `decision-pending`, продолжать независимые инженерные задачи.

**Done:** каждый пункт реализован и проверен либо есть явное согласованное изменение требований. Пока решения нет, допустимо `engineeringCoreReady=true`, но **не** `localReady=true` и не «преподавателю остались только расчёты». Для небольшого переноса GUI в App Designer ориентир дополнительно 4–12 ч + доступ к редактору; расширение PHY не включено в базовую оценку.

## T1 — переносимый комплект с полной моделью, F5

**Зависимости:** R3/R4, D4, U2 приняты; U3 решение не мешает draft, но блокирует окончательную приёмку. **Время:** 3–5 ч + ревью.
**Modify:** `experiments/prepareExternalRun.m`, `tests/TestExternalRunPackage.m`.
**Create:** `verification/external/validateExternalPreflight.m`, `tests/TestExternalPreflight.m`.

- [ ] Сначала RED test: MAT без одноимённого JSON не может стать executable Adaptive package. Полный bundle сохраняет исходные basename, MAT/JSON/training-manifest/metrics; никакого произвольного `load-model.mat` без согласованного sidecar.
- [ ] Копировать полный набор D2/D4: model, sidecar, metrics, training manifest, freeze/evaluation/acceptance, policy, protocol, dataset manifests, source/calibration/registry snapshots и обязательное evidence происхождения. Минимальный перечень берётся из acceptance refs, не из ручного списка «двух важных файлов». Недоступное обязательное evidence — конкретная ошибка preflight. Большие внешние данные можно ссылать через явно подключённый каталог с проверяемыми hash; отсутствие доступа запрещает scientific admission.
- [ ] Все ссылки пакета относительные и остаются внутри package root после нормализации. Не менять содержимое вычислительных `.m` при sanitation путей: acceptance привязан к их hash. Санитизировать только сгенерированные инструкции/конфиги; конфиденциальные данные в исходном файле — блокер, не незаметная правка принятого кода.
- [ ] Preflight возвращает `{passed,readiness,errors,sourceDigest,inputDigests}`. Проверить фактические source bytes, model sidecar, D2 metrics, D4 admission, calibration, IDs/roles, toolbox availability, бюджет и разрешённую стадию. readOnly режим ничего не резервирует и не запускает.
- [ ] Разделить `software-ready`, `stage-ready`, `scientific-accepted`. Static package допустим без модели. Adaptive draft с candidate допустим для подготовки; запуск внешнего сравнения требует accepted evidence D4. Fixture не становится scientific accepted даже после успешных тестов.
- [ ] Перенести пакет в temp путь с пробелами, убрать доступ к старому checkout в тестовом path, проверить разрешение всех относительных refs. Tamper любой sidecar/metrics/policy/source → fail до runner. Tests на заглушках проверяют передачу параметров; один маленький интеграционный путь T3 дополнительно проверяет реальные функции.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestExternalRunPackage.m','tests/TestExternalPreflight.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** полный комплект читается после переноса, исходники байтово совпадают со снимком, отказ происходит до вычислений. Не упаковывать одновременно с изменением входящих docs/code.

## T2 — поэтапные внешние команды, F3/F5

**Зависимости:** T1, R4, D4. **Время:** 5–8 ч + ревью.
**Create:** `verification/external/runExternalStages.ps1`, `verification/external/testExternalStages.ps1`, `verification/external/external-stages.schema.json`, `verification/external/runExternalStage.m`, `tests/TestExternalStageDispatch.m`, `docs/external-runbook.md`.
**Modify:** `experiments/prepareExternalRun.m` только после освобождения T1; генерация runbook/stages.json в пакете. Использовать существующие stage runners и process controls, не создавать второй scheduler.

**CLI:** `./verification/external/runExternalStages.ps1 -PackageFolder <absolute-path> -Stage <validate|pilot|data|assemble|train|freeze|evaluate|admit|compare|summarize> [-Inspect|-Execute]`. Без Execute — проверка/показ команды; Execute запускает ровно одну стадию. Никакого автоматического перехода к следующему большому расчёту. `admit` публикует решение только при явно переданном review-файле D4; агент не подписывает научную приёмку.

**Точные точки входа:** MATLAB dispatcher `report=runExternalStage(packageFolder,stageName)` читает только проверенный stage config, выбирает функцию по switch, не eval/str2func из JSON. PowerShell запускает dispatcher через существующий owned/bounded process supervisor. Сам dispatcher не обходит preflight и не изменяет execution profile.

| Стадия | Вызываемый API и результат |
|---|---|
| validate | Три последовательных подшага: `runStage2Physical.ps1 -TargetedOnly`, сохранить возвращённый targetedLog; затем `runStage2Physical.ps1 -ExecutionProfile external-machine -TargetedLog <этот-log> -MaxCaseSeconds <explicit> -MaxSuiteSeconds <explicit>`; после проверки physical report отдельным reviewer вызвать `acceptStage2Evidence(targetedLog,physicalReportPath,technicalReview)`. PS runner сам acceptance не выпускает. technicalReview имеет reviewer/scope/notes по действующему API; нет review — validate остаётся awaiting-review. runExternalStages вызывает PS напрямую, а dispatcher используется для приёмки с явно переданным review. Проверить новый acceptance через `verifyStage2AcceptanceForLoadProbe`; старый не переносит допуск на новый код |
| pilot | `runLoadPilot(options)`; API требует **весь** ordered counts `[100 500 1000 2500 5000]`, это исключительно внешний этап с отдельным явным бюджетом. options: designOnly=false,counts,outputFolder,stage2AcceptanceFile,calibrationFile,registryFile,realizationId,execution. Измерения расхода → resource evidence |
| data | `runStaticSweep(options)` по явным counts/burstDurations/realizationIds/config/calibrationFile/outputFolder/execution; dispatcher до вызова проверяет и регистрирует роль/IDs существующими registerRealizationUse, после verified completion вызывает updateRealizationUseStatus. Не передавать registryFile в API, который его не принимает. Итог — complete case paths и split/role manifest |
| assemble | `buildLoadDataset(struct('resultFiles',...,'splitManifest',...,'outputFolder',...,'purpose','training','registryFile',...))`; dataset.mat и artifacts.json D3 |
| train | `trainLoadModels(struct('datasetFile',...,'outputFolder',...,'trainingOptions',...))`, candidate evaluationMode='selection-only' D4 |
| freeze | Новый D4 `freezeLoadModelSelection(options)` с обязательными именованными входами из его карточки; freeze.json, без test prediction |
| evaluate | Новый D4 `evaluateFrozenLoadModels(options)`; неизменяемые модели + evaluated metrics/evidence |
| admit | Новый D4 `prepareModelAcceptance(options)`, затем только при заданном человеческом review `publishModelAcceptance(options)`; иначе candidate и blocked-for-review. Никакой фиктивной подписи |
| compare | `runComparisonSweep(options)` с modelFile/controllerPolicy/modelAcceptanceFile и реальными cfg/IDs; public validateModelAcceptance вызывается preflight до старта |
| summarize | Прочитать verified comparison cases в table, `plotComparisonSummary(cases,outputFolder)`; затем `runFinalAcceptance(struct('projectRoot',...,'evidenceManifest',...,'outputFolder',...))` выдаёт отчёт технической проверки, не автоматическое научное accepted |

Не вызывать исторический `runStage2Revalidation`: он рассчитан на конкретные failed allocations. Для новой validate стадии использовать fresh runner. Не запускать validate/pilot в ходе местной разработки: локальные тесты диспетчера используют stub и проверяют точный API/args. Stage2 старый жёсткий счётчик тестов не исправлять косметически в логах; если набор реально изменён, актуализировать контракт технического допуска с отдельной проверкой ожидаемых имён тестов, а не просто ослаблением total.

- [ ] Составить stages.json: schemaVersion, runId, package/source digests, stages[{name,dependencies,command,inputs,outputs,executionBudget,requiredDecision,status}]. Команда — executable+массив args, не исполняемая строка из произвольного JSON. Whitelist entrypoints; неизвестные поля/команды отвергать. Входные файлы считать данными.
- [ ] Цепь: validate (свежая техническая проверка) → pilot (ресурсный замер) → data (реальные завершённые случаи) → assemble (D3) → train (D4 selection-only) → freeze (model+policy+protocol) → evaluate (единственный независимый test) → admit (научное решение) → compare (Static/Adaptive-P/Adaptive-RA/DT на согласованных ID) → summarize. У каждой стадии свой manifest и критерий завершения; exitCode 0 без обязательных файлов не завершение.
- [ ] **Избежать кругового допуска:** validate и pilot требуют явного ограниченного бюджета, валидного профиля/машины и исходников, но не требуют уже выполненного pilot. Pilot дополнительно требует свежий Stage2 acceptance. Измеренные ресурсы pilot обязательны перед data/compare. Отсутствуют бюджет/параметры внешнего ПК — draft/blocked, никаких придуманных лимитов и переносов старых 16 часов.
- [ ] Для data проверить реестр и диапазоны ID, независимые группы и роли; reserve только при Execute после preflight. Для assemble/train/freeze учитывать D4 разделение selection и test. Изменение замороженной модели/политики после test инвалидирует downstream manifests; не использовать прежний test как независимый повторно.
- [ ] Для compare проверить final-comparison ID вне train/validation/test/tuning, один общий scenario для методов, принятый bundle и policy, completion markers. Профиль external-machine сохраняет hard-stop; местный finish-current сюда не копировать.
- [ ] Повтор Execute completed стадии при тех же input digests выводит already-complete и ничего не считает. Различные inputs → stale, требуется новый stage output folder; не стирать старые результаты. running при живом принадлежащем worker → отказ второго запуска. Interrupted проходит R4 reconcile и валидное resume, не ручной JSON.
- [ ] PowerShell stub tests ≤30 с сценарий/300 с файл: default no-execute; missing dependency; bootstrap pilot; missing resource evidence для data; нет бюджета; stale hash; running worker; failed output marker; repeat complete; fixture admission rejected; три метода передают один scenario identity. Stub никогда не вызывает MATLAB. Пример вызова: `powershell -NoProfile -File ./verification/external/testExternalStages.ps1`.
- [ ] Runbook объясняет каждую команду простыми словами, обязательные входы, где progress/report, как inspect/cancel, что считается результатом. Изготовить список файлов, которые преподаватель возвращает; никакой отправки файлов/сообщений от имени владельца.

**Done:** из одного пакета понятен и технически проверен весь внешний маршрут; ни одна стадия не требует правки исходников/ручного восстановления state. Не заявлять, что внешние данные/модель уже получены.

## T3 — один приёмочный комплект, F12 и проверка связности

**Зависимости:** все R/D/U/T приняты; U3 не pending для окончательного localReady. **Время:** 3–5 ч + ревью.
**Create:** `tests/TestLocalCompletionPipeline.m`, `verification/local/implementation-20261015/local-completion.json` (создаёт приёмка), `docs/local-completion-handoff.md`.
**Modify:** `docs/current-state.md`, `docs/section-50-readiness.md`, относящиеся команды README; только после окончательного кода. Старые результаты не редактировать.

- [ ] Координатор собирает матрицу F1–F12 → task → точный test/report → reviewer decision. Отсутствует проверка/принятое U3 решение — localReady=false с понятной причиной. Сверить все 65 пунктов исходного аудита на регрессии/новые обещания, не проводить повторное полное исследование с нуля.
- [ ] Сделать **один настоящий короткий путь** ≤1–2 UE на случай и в лимитах: три физических Static случая с разными разрешёнными development ID → экспорт/verifyCase → оконный dataset D3 → маленькое development обучение → runtime Adaptive в разрешённом local development → перенос bundle/проверка package reader. Одного ID недостаточно для train/validation/test. Сначала собрать обычный development dataset через buildLoadDataset. В явно именованном test helper сделать отдельный производный `development-fixture` для обучения: целиком назначить первому ID train, второму validation, третьему test; не смешивать окна одного ID между группами. Не менять исходные cases/registry и не объявлять этот производный fixture candidate-training. Сохранить provenance к трём реальным cases и список тестовых преобразований. На этом же fixture проверить отрицательный external admission. Это реальная инженерная сцепка функций с явно тестовой процедурой обучения; не научная приёмка, не 95% интервалы и не доказательство качества ML.
- [ ] Если одна сцепленная проверка не укладывается в 300 с, разнести её на фиксированные стадии с файловыми артефактами одной identity и отдельными bounded files; каждую потребляющую стадию проверять на hash/происхождение. Не уменьшать физические параметры обычной науки и не подменять реальный PHY заглушкой незаметно. В отчёте явно перечислить реальные и synthetic/stub части.
- [ ] Выбранные regression-файлы предыдущих карточек, прошедшие на прежнем source snapshot, проверить по влиянию последующих изменений. Повторить затронутые, не всё подряд и не все tests/ по умолчанию. Все свежие проверки привязать к итоговому source digest; ранее пройденное на ином снимке обозначить историческим, не свежим.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestLocalCompletionPipeline.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

- [ ] Сначала зафиксировать окончательные входящие docs/code, затем собрать один delivery package. Отчёт времени/хешей хранить снаружи хешируемого набора. Проверить из перемещённой/распакованной копии, source manifests до/после совпадают. Если найден реальный дефект — исправить и новый снимок, не цепочка переупаковок только ради даты.
- [ ] Итоговый независимый reviewer проверяет интеграцию, 12 findings, local/external границу, процессные ограничения и полноту handoff. Он не обязан повторять все тесты при наличии проверяемых логов; новый риск обосновывает точечный повтор.
- [ ] `local-completion.json`: planVersion, sourceDigest, taskStates, reports, requirementDecisions, engineeringCoreReady, localReady, externalExperimentComplete=false, remainingExternalStages. Значение finalAcceptance.accepted не превращать в true: научная приёмка отдельно.

**Done:** `localReady=true` только после инженерных проверок и U3 решения; остаются внешние реальные данные/обучение/оценка/сравнения и исследовательский отчёт. При U3 pending сообщить: «инженерное ядро готово; остаётся решение по буквальному ТЗ», а не «остались только долгие тесты».
