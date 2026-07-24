# Модуль 1 — точка входа: TrafficConfig -> TrafficStream, плюс метрики визуализации
# (число активных устройств N_active(t), интенсивность поступления λ(t)).
#
# build_traffic_stream — чистая функция: детерминирована при фиксированном
# cfg.seed, не знает о NPRACH/коллизиях (контракт с Модулем 2, см. EventQueue.jl).
# Выход — TrafficStream с временами В МИЛЛИСЕКУНДАХ (шкала DES-симуляции);
# внутри работает в секундах (натуральные единицы TrafficModels.jl/TR 37.868) и
# конвертирует на выходе.
#
# ВАЖНО про deviceId: каждое поступление (ArrivalEvent) получает СВОЙ уникальный
# id — это не индекс физического устройства, а идентификатор конкретной сессии
# случайного доступа. Для Periodic-трафика одно физическое устройство отправляет
# много отчётов за время симуляции; в Модуле 2 каждый такой отчёт — независимая
# попытка RA (Device в Types.jl хранит состояние ровно одной попытки), поэтому
# переиспользование одного id для последовательных отчётов испортило бы состояние
# (attempts/success/state одной сессии перезаписывались бы другой). Разбиение на
# физические устройства используется только внутри генерации (для назначения фазы
# джиттера каждому устройству) и наружу не передаётся.

using Random

"""
    build_traffic_stream(cfg::TrafficConfig, simDuration::Float64; rng=Random.default_rng()) -> TrafficStream

Строит поток поступлений согласно `cfg.kind`. `simDuration` — длительность
симуляции В МИЛЛИСЕКУНДАХ. Возвращает `TrafficStream` с событиями,
отсортированными по времени (в мс), с уникальным `deviceId` на каждое поступление.
"""
function build_traffic_stream(
    cfg::TrafficConfig, simDuration::Float64; rng::Random.AbstractRNG=Random.default_rng(),
)
    cfg.numDevices >= 0 || throw(ArgumentError("numDevices должно быть неотрицательным"))
    simDuration > 0 || throw(ArgumentError("simDuration должно быть положительным"))
    localRng = cfg.seed === nothing ? rng : Random.Xoshiro(cfg.seed)
    simDurationSec = simDuration / 1000

    times_s = if cfg.kind == Periodic
        _build_periodic(localRng, cfg, simDurationSec)
    elseif cfg.kind in (Burst, Emergency)
        _build_burst_or_emergency(localRng, cfg, simDurationSec)
    elseif cfg.kind == Poisson
        _build_poisson(localRng, cfg, simDurationSec)
    elseif cfg.kind == Downlink
        _build_downlink(localRng, cfg, simDurationSec)
    else
        throw(ArgumentError("Неизвестный TrafficKind: $(cfg.kind)"))
    end

    sort!(times_s)
    events = Vector{ArrivalEvent}(undef, length(times_s))
    perDeviceKind = Dict{Int,TrafficKind}()
    for (i, t_s) in enumerate(times_s)
        events[i] = ArrivalEvent(t_s * 1000, i, cfg.kind)
        perDeviceKind[i] = cfg.kind
    end
    return TrafficStream(events, perDeviceKind)
end

function _build_periodic(rng::Random.AbstractRNG, cfg::TrafficConfig, simDurationSec::Float64)
    cfg.numDevices == 0 && return Float64[]
    times = Float64[]
    if cfg.aggregateAsPoisson
        # Асимптотика суперпозиции многих периодических источников (Пальм–Хинчин).
        λ = cfg.numDevices / cfg.reportPeriod
        append!(times, generate_poisson_arrivals(rng, λ, simDurationSec))
    else
        phases = sample_activation_model1(rng, cfg.numDevices, cfg.activationWindow)
        for devId in 1:cfg.numDevices
            stream = generate_periodic_device_stream(
                rng, cfg.reportPeriod, cfg.jitterFraction, simDurationSec; phase0=phases[devId],
            )
            append!(times, stream)
        end
    end
    return times
end

function _build_burst_or_emergency(rng::Random.AbstractRNG, cfg::TrafficConfig, simDurationSec::Float64)
    cfg.numDevices == 0 && return Float64[]
    raw = sample_activation_model2(rng, cfg.numDevices, cfg.activationWindow)
    return [t for t in raw if t <= simDurationSec]
end

function _build_poisson(rng::Random.AbstractRNG, cfg::TrafficConfig, simDurationSec::Float64)
    cfg.numDevices == 0 && return Float64[]
    λ = cfg.numDevices / cfg.reportPeriod
    return generate_poisson_arrivals(rng, λ, simDurationSec)
end

function _build_downlink(rng::Random.AbstractRNG, cfg::TrafficConfig, simDurationSec::Float64)
    cfg.numDevices == 0 && return Float64[]
    return generate_downlink_arrivals(rng, cfg.downlinkRate, cfg.pagingCycle, simDurationSec)
end

"""
    merge_streams(streams::AbstractVector{TrafficStream}) -> TrafficStream

Объединяет несколько потоков разных типов трафика (например, `Periodic` +
`Emergency`, идущие одновременно) в один, отсортированный по времени, с
перенумерованными глобально уникальными `deviceId`.
"""
function merge_streams(streams::AbstractVector{TrafficStream})
    allEvents = reduce(vcat, (s.events for s in streams); init=ArrivalEvent[])
    sort!(allEvents; by=e -> e.time)
    renumbered = Vector{ArrivalEvent}(undef, length(allEvents))
    perDeviceKind = Dict{Int,TrafficKind}()
    for (i, e) in enumerate(allEvents)
        renumbered[i] = ArrivalEvent(e.time, i, e.kind)
        perDeviceKind[i] = e.kind
    end
    return TrafficStream(renumbered, perDeviceKind)
end

"""
    compute_active_devices(arrivals, departures) -> (t, n)

Считает `N_active(t) = A(t) − D(t)` — разность считающих процессов поступлений и
уходов. `arrivals`/`departures` — векторы времён (одна шкала, обычно мс).
Возвращает точки излома кусочно-постоянной функции `N_active(t)`.
"""
function compute_active_devices(arrivals::AbstractVector{<:Real}, departures::AbstractVector{<:Real})
    events = Vector{Tuple{Float64,Int}}(undef, length(arrivals) + length(departures))
    idx = 1
    for a in arrivals
        events[idx] = (Float64(a), 1)
        idx += 1
    end
    for d in departures
        events[idx] = (Float64(d), -1)
        idx += 1
    end
    # При равенстве времени приход учитывается раньше ухода (устройство считается
    # активным в момент своего прихода даже если что-то другое уходит в тот же момент).
    sort!(events; alg=Base.Sort.MergeSort, lt=(a, b) -> a[1] < b[1] || (a[1] == b[1] && a[2] > b[2]))
    t = Vector{Float64}(undef, length(events))
    n = Vector{Int}(undef, length(events))
    cum = 0
    for (i, (time, delta)) in enumerate(events)
        cum += delta
        t[i] = time
        n[i] = cum
    end
    return t, n
end

"""
    estimate_intensity(arrivalTimes, simDuration, windowSize) -> (t, λ̂)

Оценка мгновенной интенсивности поступления пакетов скользящим (непересекающимся)
окном шириной `windowSize`: `λ̂(t) = N(t−Δ,t] / Δ`. `t` — правые границы бинов.
Единицы `λ̂` — [событий / (единица времени arrivalTimes)].
"""
function estimate_intensity(arrivalTimes::AbstractVector{<:Real}, simDuration::Real, windowSize::Real)
    windowSize > 0 || throw(ArgumentError("windowSize должен быть положительным"))
    nBins = max(1, ceil(Int, simDuration / windowSize))
    counts = zeros(Int, nBins)
    for a in arrivalTimes
        (a < 0 || a > simDuration) && continue
        bin = min(nBins, floor(Int, a / windowSize) + 1)
        counts[bin] += 1
    end
    t = [i * windowSize for i in 1:nBins]
    λ̂ = counts ./ windowSize
    return t, λ̂
end
