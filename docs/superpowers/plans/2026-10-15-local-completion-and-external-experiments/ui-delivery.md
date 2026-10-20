# U1–U5, T1–T3: интерфейс, перенос и окончательная местная приёмка

Часть [единого плана](../2026-10-15-local-completion-and-external-experiments.md). Следовать [правилам координации](coordination.md). Перечисленные Create-файлы пока являются заданиями. Физические параметры, источники случайности и научные определения не менять ради быстродействия. Оценка этого пакета: 28–45 часов реализации + 6–10 часов ревью; ветка буквального расширения PHY/App Designer в U3 отдельно.

## Замечания владельца из демонстрации 15–16 октября

Теперь это обязательные карточки **U4** (сводка открытого отчёта) и **U5** (журнал, пояснения, экспорт) ниже. Статус обеих: не реализованы. Встроены в общий порядок и оценку; не терять при передаче другому агенту. Минимальная правка существующего интерфейса, без нового дизайна и изменения физики.

## U1 — текущая радиодиагностика в интерфейсе, F9

**Зависимости:** R1, R3, D3 приняты; D3 освободил `NBIoTSimulator.m`. **Время:** 5–8 ч + ревью.

**Modify:** `src/+nbiot/NBIoTSimulator.m`, `src/+nbiot/+ui/SimulationSession.m`, `apps/NBIoTApp.m`, `tests/TestDisplayRefresh.m`, `docs/gui-walkthrough.md` (если такого файла нет — Create).
**Create:** `src/+nbiot/+metrics/RadioDiagnosticsAccumulator.m`, `tests/TestLiveRadioSummary.m`.
**Read:** `src/+nbiot/+metrics/radioDiagnostics.m`, `src/+nbiot/+results/EventLog.m`, текущие radioSummaryForUe и snapshot.

**Контракт:** новый `sim.liveRadioDiagnostics()` возвращает `struct('asOfTick',...,'status',...,'summary',...,'perUe',...)`. Cache только для представления, не входит в checkpoint, научные логи, runtime actions или RNG. Восстановленный объект сначала восстанавливает cache из журналов один раз; обычное обновление читает только `EventLog.since(cursor)`.

- [x] Написать `RadioDiagnosticsAccumulator.update(truthDelta,observedDelta,receptionDelta,asOfTick)` и `.snapshot()`. В cache хранить события/счётчики по occasion и последние оценки по UE. Сопоставление occasion/attempt заимствовать из R1, не придумывать иной идентификатор. Для изменившихся occasions пересчитать диагностику R1 по их полному накопленному набору событий; заменить старый вклад новым. Не пересчитывать все прошлые occasions при каждом refresh.
- [x] Обработать пустые occasions и поздние RA outcomes: отсутствие передачи не означает отсутствие false-alarm opportunity; неизвестный исход остаётся censored. Суммировать числители/знаменатели, затем вычислять доли; среднее от долей разных occasions запрещено. Последний SINR отмечать временем и available; неизвестное значение не заменять нулём.
- [x] До реализации составить таблицу соответствий полей `radioDiagnostics.summary` → накопитель. Для поля, которое невозможно складывать напрямую, сохранять необходимые первичные counts/keys. Итоговый cache на полном наборе событий должен совпасть с batch R1 для каждого показываемого поля. Не требовать побайтового совпадения внутренних cache с научным result.
- [x] В simulator добавить private cursors/cache и публичный accessor; создавать cache лениво. В `SimulationSession.snapshot` заменить терминальную зависимость radioSummary от `getResult()` на live accessor для running/paused. Терминальный научный экспорт сохраняет существующий R1 путь. Никаких `sim.result()` из работающего UI.
- [x] В UI показывать «на текущий момент», время последнего события, известные коллизии, capture, SINR/доступность и пояснение «неизвестно», если данных ещё нет. Обновлять уже созданные controls; не перестраивать всю таблицу/графики на каждом tick. Значения не должны использоваться контроллером как вход ML.
- [x] Проверки нового класса: два независимых occasions; поздний успех меняет capture; неизвестный outcome не становится неуспехом; пустой occasion учитывается; повторный snapshot без новых событий не запускает повторный batch; terminal cache совпадает с R1; после checkpoint rebuild совпадает со свежим cache.
- [x] `TestLiveRadioSummary`: fixture-журналы без PHY проверяют арифметику; отдельный ≤2 UE integration сравнивает scientific result при редком/частом UI refresh. Через счётчик у тестовой фабрики доказать 0 вызовов result до окончания. Перехват исключения с выдачей нулевых метрик тест не проходит.

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

**Зависимости:** начать обследование после P0, окончательно сверить после U2/U4/U5. **Время:** 1–2 ч на матрицу/решение; реализация дополнительной ветки отдельно.
**Modify:** `docs/requirements-decisions.md`, созданный координатором в P0; передать lock на время дополнения U3. **Modify после решения:** только конкретные согласованные GUI/profile файлы; это отдельная карточка U3a с обновлённой оценкой, не свободное разрешение переписать PHY.

- [ ] Выписать буквально требования §11, §30, §46 из `tmp/pdfs/audit-spec-20261015.txt`; рядом перечислить реализованные controls и ограничения в validateConfig. Каждому параметру дать статус: редактируется / фиксированный поддерживаемый профиль / не реализован. Отдельно 1 ms, 1.92 MHz, 500 ms окна, физические форматы и ограничения UI.
- [ ] Проверить установленную MATLAB R2025b и её локальную документацию App Designer. Наличие `.m` файла само по себе ничего не доказывает: текущий `NBIoTApp.m` — программно созданный uifigure. Определить, открывается ли приложение для редактирования в App Designer этой версии, а не только запускается как MATLAB function.
- [ ] Записать два конкретных варианта решения владельцу/преподавателю: (A) принять документированный фиксированный физический профиль и существующую программную GUI; (B) требовать буквальное расширение настроек и редактируемый App Designer artifact. Показать расхождения и цену ветки. Владелец пока **не** принял исключение; не заполнять approval за него.
- [ ] Если выбран App Designer: сделать поддерживаемым редактором приложение, использующее существующие SimulationSession/модель, перенести требуемые controls и callbacks, не дублировать физическое ядро. Пустой launcher-shell не считается выполнением без явного согласия. Проверить открытие, запуск и сохранение в целевой R2025b. Не генерировать `.mlapp` через недокументированные ZIP/internal API. Если доступ к редактору отсутствует, сохранить задание для ручного шага и назвать блокер.
- [ ] Если нужны иные numerology/sample rates/controller windows: сначала отдельная согласованная спецификация поддерживаемых значений, калибровки и проверок; исполнитель не снимает validateConfig ограничения вслепую. Эта ветка существенно меняет объём и не имеет честной оценки до выбора диапазона.
- [ ] Решение фиксировать: точный пункт, принятое поведение, кто/когда подтвердил, ссылка на подтверждение, необходимые тесты. При отсутствии ответа сохранять `decision-pending`, продолжать независимые инженерные задачи.

**Done:** каждый пункт реализован и проверен либо есть явное согласованное изменение требований. Пока решения нет, допустимо `engineeringCoreReady=true`, но **не** `localReady=true` и не «преподавателю остались только расчёты». Для небольшого переноса GUI в App Designer ориентир дополнительно 4–12 ч + доступ к редактору; расширение PHY не включено в базовую оценку.

## U4 — понятная сводка сохранённого отчёта

**Совместимость и окно:** каждый новый manifested case получает sidecar и `tableExportVersion=6`; reader продолжает читать версии 2–5. Baseline screenshot и ручное открытие v3 100 UE выполнять только в отдельный согласованный видимый момент; обычные bounded GUI-тесты остаются без foreground activation.

**Зависимости:** D3 и U2 приняты, App/Session/saveResult/verifyCase освобождены. **Время:** 5–7 ч + 1–2 ч ревью. Один исполнитель владеет всеми изменениями; U5 только после U4.

**Modify:** `apps/NBIoTApp.m`, `src/+nbiot/+ui/loadKpiCsvFiles.m`, `src/+nbiot/+ui/SimulationSession.m`, `src/+nbiot/+results/saveResult.m`, `src/+nbiot/+results/verifyCase.m`, `tests/TestKpiCsvLoading.m`, `tests/TestResultMetadata.m`, `tests/TestCaseResume.m`, `tests/TestRadioDiagnosticsExport.m`, `docs/gui-guide.md`, `docs/metrics-contract.md`.
**Create:** `src/+nbiot/+results/buildReportMetadata.m`, `src/+nbiot/+ui/loadReportMetadata.m`, `tests/TestSavedReportOverview.m`.

**Интерфейсы:** `metadata=nbiot.results.buildReportMetadata(result)` собирает только факты имеющегося result, без симуляции. `view=nbiot.ui.loadReportMetadata(kpiFile)` возвращает `status` (`verified`, `partial`, `unavailable`, `invalid`), `caseKey`, `fields`, `unavailableFields`, `reason`. `fields` содержит `mode,numUE,activeUE,trafficType,payloadBytes,periodTicks,durationTicks,actualTick,tickSeconds,durationSeconds,kpiWindowTicks,planned,created,delivered,dropped,unfinished`. `durationSeconds` — сохранённая длительность модели; для старых случаев брать только из `kpi_durationSeconds` связанного summary, а `tickSeconds` оставить неизвестным, если он не сохранён. Число неизвестно → NaN/нет данных, не 0; periodTicks неприменим к burst/poisson. verified означает проверенную связь показанных малых файлов, а не новую научную приёмку всего MAT.

- [x] **U4.1. Изучить сохранение D3, loadKpiCsvFiles и примеры v3 `reports/100-ue`/`reports/single-ue`.** Старые файлы и completion markers не изменялись. Исходный вид карточки до правки не фиксировался; отдельная видимая проверка отложена до удобного времени владельца.
- [x] **U4.2. Проверки данных.** TestSavedReportOverview покрывает known-answer, баланс, burst/periodic/poisson, границы горизонта, активную группу и расхождение `policy.windowTicks`/`dataset.windowTicks`; для KPI используется фактическое окно `dataset`. Несбалансированный legacy summary сохраняет исходные числа и получает статус invalid. Проверка карточки сверяет 100/6/86/8 при контролах следующего запуска 10 UE.
- [x] **U4.3. Согласовать малые метаданные с экспортом.** Новые manifested saves пишут `<stem>_report.json` до атомарной публикации completion marker; marker проверяет имя/размер/SHA-256. Sidecar связывает schemaVersion, caseKey, canonicalConfigSha256, KPI и summary. `tableExportVersion=6`; MAT `resultSchemaVersion` не меняется. `verifyCase` отклоняет отсутствующий или повреждённый sidecar.
- [x] **U4.4. Лёгкий reader.** Проверяются пути внутри папки случая, identity и hashes/bytes sidecar, KPI и summary. Reader не загружает MAT и не вызывает `verifyCase`. Кэш не используется, поэтому повторное чтение каждый раз проверяет текущее содержимое. Без совпадающего marker статус verified не присваивается.
- [x] **U4.5. Совместимость.** tableExportVersion 2–5 читаются как partial, если доступные итоги сбалансированы; standalone KPI остаётся открываемым с unavailable; изменённые файлы, чужая identity, выходящие ссылки и небаланс (включая старые summary) помечаются invalid с причиной и исходными числами. Проверены разные cases, переключение без переноса, повторное чтение после изменения и работа без MAT.
- [x] **U4.6. Карточка интерфейса.** Показываются условия/итоги, статус проверки, выбранный случай и отдельная подпись «Настройки следующего запуска». Оконные подписи используют `startTick`/`endTick`, неполный хвост отмечается; незавершённые пакеты описаны относительно конца наблюдения. Селектор одновременно меняет карточку и таблицу выбранного отчёта.
- [x] **U4.7. Bounded-путь.** Injected-dialog UI tests показали отдельные cases без нового запуска; настоящий v3 `reports/100-ue` также открыт тестом при неизменённых controls 10 UE. Старые условия без данных показываются как отсутствующие. После исправлений регрессий повторно прошли четыре связанные test files в `implementation-009`.
- [x] **U4.7. Видимая ручная проверка, 18.10.2026.** В актуальном интерфейсе открыт настоящий v3 `reports/100-ue/static-v1_n100_r1088_kpi.csv` без пересчёта. Карточка показывает 100 устройств, 5 секунд и итог 100/6/86/8; недоступные в старом формате поля не угадываются. Контролы следующего запуска остаются отдельными. Снимки: `verification/local/runtime-review/U4/report-overview-20261017/v3-report-card-overview-20261018.jpg` и `.../v3-report-card-outcomes-20261018.jpg`.
- [x] **U4 review и видимая приёмка.** Повторная независимая проверка после исправления двух замечаний вернула SPEC PASS / QUALITY PASS; все 12 файлов совпали со снимком `final-source-snapshot-after-review-fixes.json`. Отдельная ручная проверка v3 завершена без запуска расчёта.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestSavedReportOverview.m','tests/TestKpiCsvLoading.m','tests/TestResultMetadata.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

**Done:** по открытому отчёту понятно, чей это опыт, сколько было устройств/сообщений и что произошло; неподтверждённые условия обозначены. Никаких новых расчётов 100 UE для этого задания. **Стоп:** старые данные не содержат число — показать отсутствие, не менять исходный файл и не обещать восстановление по имени.

## U5 — читаемый журнал, понятные подписи и результат экспорта

**Коррекция 18.10 — U5-R1:** после основного GREEN/review выявлен layout-дефект сохранённых KPI: ось внутри grid `[1 1]` повторно получает Row=6; фиксированные высоты сжимают таблицу и график. Уже сделанные U5.1–U5.7 не повторять целиком. Карточка U5-R1 в remaining-work-20261018.md задаёт узкую правку, layout-регрессию и отдельную видимую проверку без расчёта. Галочки основного объёма ниже не означают, что этот новый дефект исправлен. Полное принятие correction требует нового evidence/review.

**Зависимости:** R3, U1 и U4 приняты. **Время:** 3–5 ч + 1–2 ч ревью.
**Modify:** `apps/NBIoTApp.m`, `src/+nbiot/+ui/formatObservedEvents.m`, `src/+nbiot/+ui/formatLiveStateSummary.m`, `src/+nbiot/+ui/formatResultSummary.m`, `src/+nbiot/+ui/formatUeDetail.m`, `tests/TestObservedEventFormatting.m`, `tests/TestNBIoTAppChartExport.m`, `tests/TestNBIoTAppDialogs.m`, `docs/gui-guide.md`.
**Create:** `tests/TestNBIoTAppUsability.m`, `src/+nbiot/+ui/explainMetric.m`.
**Read:** `src/+nbiot/+ui/exportStaticCharts.m`, `tests/DialogSpy.m`, `tests/RadioEventSimulatorStub.m`, выполненные R3/U1 и экспортные callbacks.

**Интерфейс:** `explanation=nbiot.ui.explainMetric(key)` возвращает короткую русскую строку для отображаемого поля/статуса, неизвестный key → «Описание недоступно». Словарь — слой представления; не переименовывает поля CSV, состояния симулятора и формулы. Большой журнал читает ту же последовательность observed events, не truth и не новый расчёт. «Открыть папку» передаёт проверенный локальный путь через winopen без строковой shell-команды.

- [x] **U5.1. Сделать журнал доступным.** Кнопка «Развернуть журнал» открывает одно переиспользуемое окно с прокруткой, выбором/копированием текста и не менее 12 видимых строк при 1280×900. При 1000×700 окно/вкладка прокручивается, controls и журнал достижимы. Повторный клик фокусирует существующее окно; закрытие освобождает ссылки. liveGrid не сжимает нижний журнал до 0 или четырёх строк; длинные пути/строки можно прочитать. Эти проверки выполнены тестами и снимками реального GUI.
- [x] **U5.2. Исправить смысл времени.** В formatObservedEvents t=... означает время записи/решения; grant с startTick/endTick подписывать как будущий интервал управляющей передачи, не как длительность всего разговора. По текущему emitDownlink событие rar_sent фиксирует подготовку/планирование: писать «Подготовлен ответ на запрос доступа (RAR)», а не «устройство уже получило ответ». Без наблюдаемого факта не дорисовывать получение. Пример проверки: t16 grant с интервалом32–34 не превращается в событие получения t16/34; Msg3/RA t62 — служебное сообщение, не доставка полезных 200 байт.
- [x] **U5.3. Убрать шум без потери данных.** Переключатель «Показывать проверки без запросов» по умолчанию выключен только для представления nprach_detection count=0. Рядом число скрытых строк; включение возвращает их в исходном порядке. Объяснение: станция проверила возможность доступа, запроса не обнаружила; это не новое подключение и не ошибка. Исходные event logs, result и экспорт сохраняются полностью. Фильтр не меняет counters U1.
- [x] **U5.4. Добавить короткие расшифровки там, где возникли вопросы.** UE — устройство; IDLE — сейчас не передаёт/свободно; WAIT_RAR — ждёт ответа станции на запрос доступа; DATA — передаёт данные. CRC Data=0 означает ноль обнаруженных ошибок проверки блоков данных; «без CRC» не равно ошибка. Подключение — служебная процедура, отдельно от доставки сообщения; один пакет может передаваться частями. Progress R3 показывает «5,000 из 5,000 с модели», отдельно реальное время расчёта и фазу завершения; completed horizon не обещает доставку всего. ID и целые counts показывать без .0000.
- [x] **U5.5. Пояснить таблицы и графики.** В сворачиваемой «Что означают показатели» дать русские названия/единицы для created/delivered/dropped/unfinished, успешных попыток доступа, throughput, delay, BLER и RA/DT/P. created в окне — новые сообщения, а не все ещё ожидающие; ноль не означает пустую сеть. Скорость доставки — доставленные биты за окно, не паспортная скорость модема. Отсутствие выборки — «нет данных», а не 0% ошибок/нулевая задержка; использовать доступность из действующего контракта, без пересчёта метрик. Очередь устройства и число устройств с непустой очередью — разные счётчики, подписи их не смешивают.
- [x] **U5.6. Сделать сохранение видимым.** После успешного exportStaticCharts проверяется список существующих PNG; показываются результат «Сохранено N графиков», полный копируемый путь и кнопка «Открыть папку». Отмена диалога не создаёт файлов и не показывает успех; ошибка доступна рядом с действием. Имя nbiot-charts-... отображается после фактического создания. Пустая вкладка подсказывает, где открыть KPI CSV.
- [x] **U5.7. Проверить короткую демонстрацию.** На fixtures проверены порядок/фильтр событий и подписи времени, статусы, объяснения и целые ID. Bounded callback test проверил экспорт в путь с пробелами/кириллицей, отмену, ошибку и успех: 8 фактических PNG, то же число в статусе, open-folder заменён spy. GUI-снимки показывают отчёт, большой журнал и прежний реальный PNG-экспорт без MATLAB-команд; сравнение источника событий после фильтра не выявило изменений. Визуальная фикстура явно обозначена; новая ручная симуляция не выполнялась.

**Визуальная приёмка 18 октября:** `verification/local/runtime-review/U5/usability-20261018/GUI/app-1280x900.png` — сохранённый run и частично проверенная карточка отчёта; `app-1000x700.png` — компактный экран и достижимые controls; `journal-fixture-large.png` — 120 строк, видимый порядок событий и прокрутка; `app-path-scroll-end.png` — длинный путь читается горизонтальной прокруткой; `export-existing-8-png-20261015.png` — восемь реально существовавших результатов экспорта. Idle saved-results окно не создавало новый PNG; это ограничение вместе с происхождением снимка указано в U5 implementation report.

```powershell
./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestNBIoTAppUsability.m','tests/TestObservedEventFormatting.m','tests/TestNBIoTAppChartExport.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900
```

Если менялся dialog adapter, отдельно выполнить `tests/TestNBIoTAppDialogs.m` тем же bounded runner. Это выборка, не вся регрессия. **Done:** пользователь видит события и экспорт, понимает базовые показатели; приёмка включает изображения реального интерфейса. **Стоп:** существующий лог не подтверждает причину потерь/помех — показать «причина по этому отчёту не определена», не приписывать её расстоянию/зданиям/коллизии по догадке.

## T1 — переносимый комплект с полной моделью, F5

**Зависимости:** R3/R4, D4, U4 приняты; U3 решение не мешает draft, но блокирует окончательную приёмку. **Время:** 3–5 ч + ревью.
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

**Зависимости:** R1–R4, D1–D4, U1/U2/U4/U5, T1/T2 приняты. При pending U3 выполнить инженерную цепочку и handoff с localReady=false; окончательный localReady требует решения U3. **Время:** 3–5 ч + ревью.
**Create:** `tests/TestLocalCompletionPipeline.m`, `verification/local/implementation-20261015/local-completion.json` (создаёт приёмка), `docs/local-completion-handoff.md`.
**Modify:** `docs/current-state.md`, `docs/section-50-readiness.md`, относящиеся команды README; только после окончательного кода. Старые результаты не редактировать.

- [ ] Координатор собирает матрицу F1–F12 → task → точный test/report → reviewer decision. Включить U4/U5 и пользовательские примеры в матрицу приёмки. Отсутствует проверка/принятое U3 решение — localReady=false с понятной причиной. Сверить все 65 пунктов исходного аудита на регрессии/новые обещания, не проводить повторное полное исследование с нуля.
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

