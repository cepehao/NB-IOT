# O5: профиль после O2–O4

6 октября 2026, MATLAB R2025b. Полный Static/WAVEFORM прогон 100 UE завершился на tick 5000 за **2249,877 с (37,498 мин)** с включённым Profiler. Результат: 100 создано, 5 доставлено, 42 dropped, 53 unfinished. Это время профилированного прогона; оценка обычной серии берётся из отдельных измерений O2/O4.

Пиковый суммарный working set MATLAB — **1,549 ГиБ**, минимум свободной системной памяти — **11,097 ГиБ**; 1003 выборки мониторинга. `o5-profile-resources.json`.

## Измеренные функции

| Функция | Calls | Self, с | Inclusive, с |
|---|---:|---:|---:|
| Scheduler.downlink | 71 547 | 345,87 | 1890,61 |
| ProfileTables.profile | 15 171 117 | 270,29 | 270,29 |
| Scheduler.reconstructDownlink | 13 277 038 | 247,78 | 1095,51 |
| Scheduler.publicGrant | 14 806 291 | 244,96 | 244,96 |
| ProfileTables.lookup | 43 471 243 | 223,91 | 223,91 |
| ResourceCalendar.check | 1 716 092 | 139,25 | 222,93 |
| ProfileTables.dlTbs | 13 277 038 | 100,73 | 100,73 |

Inclusive-времена вложены друг в друга и не складываются. В MATLAB FunctionTable отсутствует отдельное поле SelfTime; собственное время вычислено как TotalTime минус времена дочерних вызовов. [Семантика полей MATLAB Profiler](https://www.mathworks.com/help/matlab/ref/profile.html). Все функции в приведённой таблице нерекурсивны; incomplete/PartialData нет. `profile-analysis.json`, `profile-functions.csv`, `profile-top-self.csv`, `profile-top-inclusive.csv` — основные обработанные доказательства.

Первоначальный helper заполнил отсутствующий SelfTime нулями. Этот вывод сохранён отдельно как `profile-summary-original.json`; `profile-summary.json` исправлен по полной сохранённой FunctionTable.

## Решение

CPU-расход остаётся в повторном планировании DL, создании одинаковых PHY-профилей и табличных проверках. `ResourceCalendar.check` не лидирует: его self time около 6,2% времени полного профилированного прогона. Поэтому следующий небольшой CPU-кандидат — повторные неизменяемые profile/table операции в реконструкции DL. Патч incremental calendar counters пока не выбран. Дополнительная O5-оптимизация ещё не внесена; сначала закрываются R1/R2 согласно порядку основного плана.

## Версия и сохранённые файлы

`profile_n100.mat` содержит полный результат и FunctionTable. Source SHA-256 **на момент начала**: `43b7dda86e053106a69cdc7f82ae1c0fa5620b7e2c1a4a1b4b39c415f1a1cf72`. Во время выполнения добавлены два метода в `tests/TestCaseResume.m`; исполняемые production-исходники не менялись, PartialData=0. Этот SHA обозначает снимок начала прогона, а не последующие версии candidate.

Точная проверка результата против ранее сохранённого профиля эталона записывается в `o5-profile-result-comparison.json`; полный suite после исправления O3 — `o3-table-metadata-full-suite.txt`.
