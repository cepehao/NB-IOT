# O4: independent cases on MATLAB process workers

## Изменения в кандидате

- Добавлен `nbiot.experiments.runStaticCase(cfg,caseFolder)`: один worker строит собственный UUID staging/attempt folder, выполняет один run, вызывает O3 readback/commit, возвращает status, elapsed, пути и SHA manifest. Ошибка до commit оставляет только диагностический staging.
- Добавлен отдельный `runStaticSweepParallel(options)` с `numWorkers` (по умолчанию 2). Он распределяет только независимые case keys через MATLAB process pool; serial `runStaticSweep` не проверяет лицензию PCT и продолжает работать отдельно.
- Coordinator один раз обновляет общий manifest атомарно после worker-фазы. Каждый worker пишет только в свой case folder. Resume применяет O3 checks по config/source/calibration/environment и всем сохранённым файлам.
- Случайные потоки, seed, realization ID и логика одного PHY run не менялись. `RandomSources` остаётся привязан к seed/realization/source/UE/tick, не к номеру worker.
- Если PCT/лицензия/pool недоступны, параллельный runner выдаёт явную ошибку с указанием serial runner; существующий неподходящий pool не удаляется.

## Проверки

- MATLAB R2025b / LTE Toolbox 25.2, Parallel Computing Toolbox 25.2 установлен, лицензия доступна (`license=1`), локальный process profile допускает до 6 workers. До серии свободно было 14,14 ГиБ RAM.
- `TestParallelCases`: **4/4**; тестирует разные attempt dirs, оставление не принятого staging после сбоя, resume без создания пула, валидацию количества workers.
- Реальный один-UE PHY smoke: sequential и process-результаты совпали **18/18 полей**, оба bundle прошли `verifyCase`; status completed, pool закрыт (`o4-process-smoke.txt`, `o4-process-smoke-comparison.json`). Время одного случая: 24,741 с sequential и 28,151 с в runner с pool startup/I/O.
- Одинаковый набор из трёх независимых PHY realization (`numUE=1`, burst 100 ms, realization 0/1/2) сравнен с последовательным режимом. На 2 workers задания поданы в обратном порядке `[2,1,0]`; результаты во всех режимах точны и проверены: 3/3 для 1, 2 и 3 workers.

| Режим | Wall time полного runner-вызова | Cases/час | К seq wall time |
|---|---:|---:|---:|
| Sequential | 94,238 с | 114,60 | 1,00× |
| Process pool, 1 worker | 124,998 с | 86,40 | 0,75× |
| Process pool, 2 workers | 92,964 с | 116,17 | 1,01× |
| Process pool, 3 workers | 63,525 с | 170,01 | 1,48× |

Измеренное в матрице wall time включает создание/закрытие pool, hash/readback, записи case-файлов и итоговый manifest. Пиковая сумма working set MATLAB client/workers — **6,13 ГиБ**, максимум **5 MATLAB-процессов**, минимум свободной системной RAM — **8,376 ГиБ** (`o4-worker-matrix-resources.json`). Это выполнило запас 8 ГиБ из плана, но ограничивает дальнейшее увеличение concurrency на этой машине.
- Полный тестовый набор после O4: **69/69**, 0 failed, 0 incomplete (`o4-final-suite.txt`).

## Вывод и границы

Для трёх маленьких 1-UE cases три workers дали лучший измеренный throughput; один process worker проиграл serial из-за накладных расходов, два дали примерно одинаковое wall time. Поэтому API оставляет выбор явным, а default — 2 workers. Эти числа нельзя переносить на 100/1000/5000 UE: большие case могут иметь существенно больший peak memory. Перед крупной серией нужно сделать отдельный 100-UE пилот; пока использовать не более двух workers по умолчанию, три — только при контроле свободной памяти.
