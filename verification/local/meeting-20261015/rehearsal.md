# Репетиция демонстрации — 15 октября 2026

Подготовка к встрече, инженерный план отложен владельцем. Физическое ядро/параметры научных серий не менялись; старый вариант 2 не возобновлялся.

Свежие bounded проверки:

- `TestNBIoTAppPauseResumeEquivalence.m`: 1/1, failed=0/incomplete=0, process completed, 110.10 с. Один UE в благоприятных условиях доставил 200 байт; UI pause/resume совпал с CLI по проверяемым научным полям.
- `TestNBIoTAppLiveCharts.m`: 1/1, failed=0/incomplete=0, process completed, 36.47 с. График появился до завершения расчёта. Это отдельная проверка без трафика, не второй случай доставки.

Команда: `./verification/local/runBoundedChecks.ps1 -TestFiles @('tests/TestNBIoTAppPauseResumeEquivalence.m','tests/TestNBIoTAppLiveCharts.m') -MaxCaseSeconds 300 -MaxSuiteSeconds 900 -OutputFolder verification/local/meeting-20261015/checks`.

`checkLaunchers.m` открыл openDemo/openSaved100, проверил preset, idle, 10 строк сохранённых KPI и наличие графика; `MEETING_LAUNCHERS passed=2 failed=0 simulationsStarted=0 release=2025b`. Выполнен через существующий InvokeBoundedProcess с внешним пределом 120 с; логи и exit status в launcher-check/process-report.json. Скриншоты live-ready.png/saved-100-view.png сохранены; сохранённый график осмотрен.

Копии двух CSV готового 100 UE проверены по case-complete marker до/после копирования. Происхождение и hashes — saved-result-provenance.json. Большие MAT не копировали и новый 100 UE не считали. Итоги сохранённого случая: created100=delivered6+dropped86+unfinished8. Это один сценарий, не независимая серия.

Учебные launcher-скрипты открывают существующее приложение; openDemo не нажимает «Запуск». Не обещают научную готовность Adaptive. Памятка docs/meeting-guide-2026-10-16.md содержит объяснение, сценарий показа, матрицу по ТЗ и вопросы преподавателю. Владелец подтвердил показ с этого же ПК.
