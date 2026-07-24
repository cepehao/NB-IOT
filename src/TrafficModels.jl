# Математические модели активации/поступления трафика.
#
# Единицы: все функции в этом файле работают в СЕКУНДАХ (натуральная единица
# TrafficConfig и 3GPP TR 37.868). Перевод в миллисекунды (шкала DES-симуляции)
# выполняется на границе в build_traffic_stream (TrafficGenerator.jl).

using Random
using Distributions: Distributions, Beta, Exponential, Uniform

"""
    sample_activation_model1(rng, N, T) -> Vector{Float64}

3GPP TR 37.868 Model 1: момент активации устройства равномерно распределён на
`[0, T]` (сек). Используется как модель времени "рестарта"/первого включения
устройства без синхронизации со стартом сети.

Плотность: `f(t) = 1/T`, `t ∈ [0,T]`.
"""
function sample_activation_model1(rng::Random.AbstractRNG, N::Int, T::Float64)
    N >= 0 || throw(ArgumentError("N должно быть неотрицательным"))
    T > 0 || throw(ArgumentError("T должно быть положительным"))
    return rand(rng, Uniform(0.0, T), N)
end

"""
    sample_activation_model2(rng, N, T) -> Vector{Float64}

3GPP TR 37.868 Model 2: момент активации устройства распределён по Beta(3,4),
масштабированному на `[0, T]` (сек, канонически T=10). Используется для
всплеска трафика (Burst) и аварийного массового доступа (Emergency) — плотность
`f(t) = (60/T)·(t/T)²·(1−t/T)³` имеет максимум при `t = 0.4·T`, что соответствует
"почти одновременной", но не мгновенной активации массы устройств.
"""
function sample_activation_model2(rng::Random.AbstractRNG, N::Int, T::Float64)
    N >= 0 || throw(ArgumentError("N должно быть неотрицательным"))
    T > 0 || throw(ArgumentError("T должно быть положительным"))
    x = rand(rng, Beta(3, 4), N)
    return T .* x
end

"""
    generate_periodic_device_stream(rng, P, jitterFraction, simDuration; phase0=0.0) -> Vector{Float64}

Последовательность моментов отчёта одного устройства с периодом `P` (сек) и
равномерным джиттером `±jitterFraction·P/2`: `tₖ = phase0 + k·P + Uₖ`,
`Uₖ ~ Uniform(−jP/2, jP/2)`. Джиттер устраняет искусственную фазовую
синхронизацию множества устройств на одном периоде. Возвращает моменты в `[0, simDuration]`.
"""
function generate_periodic_device_stream(
    rng::Random.AbstractRNG, P::Float64, jitterFraction::Float64, simDuration::Float64;
    phase0::Float64=0.0,
)
    P > 0 || throw(ArgumentError("P должно быть положительным"))
    0 <= jitterFraction < 1 || throw(ArgumentError("jitterFraction должен быть в [0,1)"))
    halfJitter = jitterFraction * P / 2
    times = Float64[]
    k = 0
    while true
        jitter = halfJitter == 0 ? 0.0 : rand(rng, Uniform(-halfJitter, halfJitter))
        t = phase0 + k * P + jitter
        t > simDuration && break
        t >= 0 && push!(times, t)
        k += 1
    end
    return times
end

"""
    generate_poisson_arrivals(rng, λ, simDuration) -> Vector{Float64}

Однородный пуассоновский процесс с интенсивностью `λ` (событий/сек) на
`[0, simDuration]` (сек), сгенерированный через экспоненциальные интервалы
между поступлениями: `Δₖ ~ Exponential(1/λ)`.

Обоснование агрегированного применения к периодическому трафику: по теореме
Пальма–Хинчина (Grigelionis) суперпозиция большого числа независимых,
стационарных, "разрежённых" точечных процессов (в частности — N периодических
источников со случайной независимой фазой, см. `generate_periodic_device_stream`)
сходится к пуассоновскому потоку с суммарной интенсивностью `λ = N/P`.
"""
function generate_poisson_arrivals(rng::Random.AbstractRNG, λ::Float64, simDuration::Float64)
    λ >= 0 || throw(ArgumentError("λ должно быть неотрицательным"))
    simDuration >= 0 || throw(ArgumentError("simDuration должно быть неотрицательным"))
    λ == 0 && return Float64[]
    times = Float64[]
    t = 0.0
    dist = Exponential(1 / λ)
    while true
        t += rand(rng, dist)
        t > simDuration && break
        push!(times, t)
    end
    return times
end

"""
    generate_downlink_arrivals(rng, λ_dl, pagingCycle, simDuration) -> Vector{Float64}

Независимый пуассоновский поток "готовности" нисходящих данных (например,
уведомление об обновлении ПО) с интенсивностью `λ_dl` (пакетов/сек), доставка
которых квантуется к ближайшему циклу пейджинга NB-IoT:
`t_deliver = ⌈t_ready / T_paging⌉ · T_paging`. Поток не конкурирует за NPRACH.
"""
function generate_downlink_arrivals(
    rng::Random.AbstractRNG, λ_dl::Float64, pagingCycle::Float64, simDuration::Float64,
)
    pagingCycle > 0 || throw(ArgumentError("pagingCycle должен быть положительным"))
    ready = generate_poisson_arrivals(rng, λ_dl, simDuration)
    deliver = [ceil(t / pagingCycle) * pagingCycle for t in ready]
    return deliver
end
