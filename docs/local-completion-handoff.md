# Локальная передача NB-IoT

## Проверенная инженерная часть

T3 собрал ограниченную development-цепочку: три Static-кейса на 2 UE, D3-диагностику, явно помеченный `development-fixture`, локальное обучение и Adaptive-P с development opt-in, ZIP, проверку перемещённого reader и fail-closed preflight. Это не независимая научная выборка. Preflight проверяет структуру, но оставляет `stageReady=false` и `scientificAccepted=false`; внешний admission fixture отклонён, реестр не менялся.

После прежних T1/T2 программных приёмок исправлены четыре дефекта переноса и dispatch:

- P1-1: launcher разрешает dispatcher на чистом MATLAB path; `TestExternalStageDispatch.m` — 3/3.
- P1-2: mutable realization registry не попадает во frozen `codeFiles`, при этом registry/state digest gates сохранены; `TestExternalRunPackage.m` — 19/19, process-only integration — 1/1.
- P1-3: admit копирует полный каталог кандидата рядом с будущим acceptance; `TestExternalStageContracts.m` — 6/6, fixture ожидаемо отклонён без acceptance/report.
- P2-1: sanitation сохраняет HTTPS, `$schema` и `$id`, редактируя локальные Windows-пути; `TestExternalRunPackage.m` — 19/19.

Независимый read-only review подтвердил исправления без критических/важных дефектов реализации. В нём отмечено, что отдельные отрицательные тесты для path-escape, symlink и overwrite ветвей копирования отсутствуют; это ограничение покрытия, а не обнаруженная ошибка. В review-отчёте сохранены точные evidence и статус.

Рабочий registry SHA-256 9494aaa0b3ce4a72e6bdeabba5479a75d131f67a731cdf9a5d11d152cf3bb436. #012 — сохранённая база; #013/#014 были fail-closed; #015/#016 исправили regexp, #017 — struct-array attestation, #018 прошёл 1/1 за 32,86 с. RED #019 остановился на deferred review path; RED #020 за 33,16 с подтвердил stale package-verification ссылку, удалённую из генератора. #021 прошёл 1/1 за 31,81 с; RED #022 за 33,09 с выявил premature T3/F12 PASS и статичный review path. Исправленный генератор ставит pending и использует report path с source digest; #023 прошёл 1/1 за 31,12 с. Пакеты #024 и #025 прошли 1/1 за 31,0417108 и 31,5687795 с соответственно и получили независимые `SPEC PASS / QUALITY PASS`. В историческом snapshot #025 identity: source digest `6312a7479b5069a62d7481e1a5c8213b5bab1383429cd3b70aa9b71d88e7d1c3`, ZIP SHA `9a31757ff26706778885fa04e71a51e70ffbe061c95620c3aa815c4a215a59b7`, handoff SHA `b82a1e2d43ff20789bd19678f8b8ad3976b3ba6eba43fab77c246fec538ffa87`; отчёт `verification/local/runtime-review/T3/package-identity-review-6312a7479b50.md`. Эти review относятся к соответствующим package identities и локальному engineering scope, не к полному ТЗ и научной приёмке. Для любого нового source snapshot completion manifest снова ставит T3/F12 pending; переводить их в PASS можно только после report с точным digest и ZIP SHA. Успешные результаты T3 ограничены development fixture; все readiness-флаги и scientific acceptance остаются false. RED outputs #017/#019/#020/#022 и package #021–#025 сохранены. Команда bounded package-only приведена ниже; актуальные identity и review status сверяйте по `verification/local/implementation-20261015/local-completion.json`.

## Итоговая package-only проверка

Для текущего frozen code/doc snapshot используется одна package-only проверка. Она проверяет сборку переносимого комплекта, копию после распаковки, reader и fail-closed preflight; симуляцию и обучение не запускает. Физические проверки ограничены прежними результатами; новая нагрузочная серия остаётся остановленной.

Команда для этой проверки:

```powershell
$env:NBIOT_T3_MODE = 'package-only'
$env:NBIOT_T3_OUTPUT_FOLDER = 'T3c19'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$env:NBIOT_T3_BOUNDED_EVIDENCE_FOLDER = "verification/local/runtime-review/T3/GREEN-package-only-$runId"
pwsh -NoProfile -File verification/local/runBoundedChecks.ps1 `
  -TestFiles @('tests/TestLocalCompletionPipeline.m') `
  -MaxCaseSeconds 300 -MaxSuiteSeconds 900 `
  -OutputFolder $env:NBIOT_T3_BOUNDED_EVIDENCE_FOLDER
```

`T3c19` уже содержит результаты полного development-only этапа; повторять `full` нельзя. Указанный bounded output должен быть пустым до этой проверки. Не повторяйте package-only для того же source digest: пакетные и transfer назначения защищены от перезаписи. Локальный `local-completion.json` остаётся вне ZIP, потому что хранит hash самого ZIP; внутри portable package собственный `handoff-manifest.json` перечисляет файлы и их хеши. Итоговую идентичность ZIP сверяйте с локальным manifest.

Исходный PDF `ТЗ_NB-IoT_обновленный.pdf` имеет SHA-256 `09535695c28952890a309fa1e20af0a3bdf1a331742998abd324c514bd4166df`; PDF остаётся в корне рабочей копии и в portable package не включается. JSON-аудит `docs/original-spec-traceability-20261019.json` включается в `project/docs/` переносимого комплекта. Он подтверждает трассировку 65 разделов и всех 27 буквальных критериев §50. Условие §29 о не менее 100 независимых реализациях действует, если позволяют вычислительные ресурсы; оно не относится к списку из 27 критериев §50.

## Открытые требования и следующий шаг

Все четыре readiness-флага остаются `false`: `engineeringCoreReady`, `localReady`, `externalExperimentComplete`, `scientificFinalAcceptance`. Карточки T1–T3 и локальные тесты не закрывают полный текст ТЗ. Полная карта с реализацией, evidence и следующим шагом по каждому условию находится в [трассировке §50 и 65 разделов](section-50-readiness.md).

- **R4.12:** получить отдельное решение владельца о точном read-only scope исторического preview. До разрешения исторические данные не открывать и не возобновлять; новый load остаётся остановлен.
- **U3:** получить фактические ответы преподавателя на четыре строки `awaiting-professor` в `docs/requirements-decisions.md`; затем применить только согласованные значения и выполнить затронутые проверки.
- **GUI visual gate:** после разрешённого доступа вручную проверить сохранённый отчёт и зафиксировать, что одновременно читаются сводка, таблица и график. Текущие старые снимки сделаны до U5-R1 и не подтверждают этот gate.
- **Полная научная приёмка:** сначала согласовать протокол, пороги, независимого reviewer и ресурсный бюджет. Текущая команда владельца оставляет новую нагрузочную серию остановленной, поэтому физические серии, Stage 2, 1000/5000 UE, обучение/допуск модели и сравнения не запускаются.
- **Итоговый отчёт:** после разрешённых независимых данных выполнить парные сравнения на одинаковых реализациях, проверить все критерии ТЗ и заполнить отчёт только реальными результатами.

Публикация, отправка внешним адресатам, изменение сетевых настроек и отключение AmneziaVPN в этот handoff не входят.
