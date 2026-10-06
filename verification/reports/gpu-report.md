# GPU FFT оценка — 2026-10-06

MATLAB R2025b/Parallel Computing Toolbox25.2 видит NVIDIA GeForce RTX3080Ti, compute capability8.6. Production candidate использует CPU; GPU-прототип хранится отдельно в work/gpu-evaluation-candidate.

## Complex-double FFT стенд

17 CFO hypotheses×12 публичных templates, batch1/8/32, template FFT cached. GPU resident kernel и стоимость CPU→GPU→CPU измерены отдельно с gputimeit/timeit.

| Windows | CPU loop,s | CPU matrix,s | GPU resident,s | GPU с transfer,s | Kernel speedup |
|---|---:|---:|---:|---:|---:|
|1|0.0774272|0.0641763|0.00837924|0.00871810|8.88|
|8|0.636563|0.521994|0.0267848|0.0277830|22.91|
|32|2.602496|2.166591|0.0969919|0.0990292|26.28|

Максимальное отклонение normalized correlation8.88e-16..1.33e-15, ниже1e-10. Совпали delay/CFO grid maxima, решения fixed legacy threshold и проверки margins±1e-10 около CPU maxima. CPU loop/matrix совпали точно. Это kernel benchmark старого full-bank поиска параметров; новая presence v2 использует group projection, а SIC ищет параметры только принятых кандидатов.

## Полный расчет

Отдельный GPU-прототип заменяет только FFT-поиск параметров NPRACH; присутствие, waveform, радио и scheduler остаются CPU. Три полных повторных1UE/5000tick runs на каждой версии:
- CPU22.067/18.498/17.892s, median18.4976s.
- GPU21.779/22.780/20.829s, median21.7791s.
- Все18 содержательных полей результата совпали в3/3 парах:54/54. Profiling timing исключён, CSV/full1000UE сравнение не выполнено.
- Warmup CPU1.2640s, GPU1.7153s.
- Во время замера выполнялась отдельная3-process interference validation. Это предварительная оценка данного профиля; нагрузка ограничивает переносимость времени.

Наблюдаемый median end-to-end speedup0.8493, то есть GPU примерно17.7% медленнее. Backend не принят и в переносимую рабочую модель не включён. На шумовой калибровке presence v2 отвергает окна до FFT, поэтому этот GPU-патч не ускоряет её основное вычисление. End-to-end выигрыш на других нагрузках, peak VRAM и single-precision качество не доказаны.

Команда стенда: setupProject; benchmarkNprachGpu. Полные A/B scripts и MAT находятся в verification evidence; это диагностический эксперимент, не обязательная зависимость последовательного запуска.

[Официальная документация R2025b](https://www.mathworks.com/help/releases/R2025b/parallel-computing/run-matlab-functions-on-a-gpu.html) подтверждает fft/gpuArray, необходимость Parallel Computing Toolbox и стоимость gather/transfer. Наличие GPU само по себе не обещает ускорения симулятора.

