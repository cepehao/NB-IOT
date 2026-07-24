# Модуль 2 — RA state machine (адаптация TS 36.321 под однотональный NPRACH,
# один уровень покрытия) и абстрактная DT-фаза. Структуры (Device, DTPool,
# SimState, ...) определены в Types.jl.
#
#   Idle --(ArrivalEvent)--> WaitingForOccasion --(occasion, no collision)--> RASuccess -> DataTransmission -> Done
#                                  ^                       |
#                                  |                 (occasion, collision)
#                                  |                       v
#                            (Backoff истёк)  <---  attempts<max: Backoff
#                                                     attempts>=max: Dropped -> Done

using Random

# ----------------------------------------------------------------------------
# Чистые функции RA-логики (не трогают SimState напрямую — тестируются изолированно)
# ----------------------------------------------------------------------------

"""
    next_occasion_time(t, cfg::NPRACHConfig) -> Float64

Ближайший момент NPRACH occasion, который `>= t` (мс), на сетке
`StartTime + k·Periodicity`, `k = 0,1,2,...`.
"""
function next_occasion_time(t::Float64, cfg::NPRACHConfig)
    T0 = Float64(cfg.StartTime)
    P = Float64(cfg.Periodicity)
    t <= T0 && return T0
    k = ceil(Int, (t - T0) / P)
    return T0 + k * P
end

"""
    select_preamble(rng, cfg::NPRACHConfig) -> Int

Равновероятный независимый выбор одной из `cfg.NumSubcarriers` преамбул
(`1:NumSubcarriers`) — постановка "шары по ячейкам" из Analytics.jl.
"""
select_preamble(rng::Random.AbstractRNG, cfg::NPRACHConfig) = rand(rng, 1:cfg.NumSubcarriers)

"""
    assign_preambles(rng, cfg::NPRACHConfig, competitors::AbstractVector{Int}) -> Dict{Int,Vector{Int}}

Каждому устройству из `competitors` независимо выбирается преамбула;
возвращает отображение "преамбула => список deviceId, её выбравших".
"""
function assign_preambles(rng::Random.AbstractRNG, cfg::NPRACHConfig, competitors::AbstractVector{Int})
    attempts = Dict{Int,Vector{Int}}()
    for did in competitors
        p = select_preamble(rng, cfg)
        push!(get!(attempts, p, Int[]), did)
    end
    return attempts
end

"""
    resolve_occasion(attempts::Dict{Int,Vector{Int}}) -> (successes::Vector{Int}, collided::Vector{Int})

Чистая функция разбиения occasion на успехи (преамбула — singleton) и
коллизии (преамбула занята >=2 устройствами). Не зависит от `rng`/времени —
удобна для unit-тестов на фиксированных `attempts`.
"""
function resolve_occasion(attempts::Dict{Int,Vector{Int}})
    successes = Int[]
    collided = Int[]
    for ids in values(attempts)
        if length(ids) == 1
            push!(successes, ids[1])
        else
            append!(collided, ids)
        end
    end
    return successes, collided
end

"""
    schedule_backoff(rng, now, cellCfg::CellConfig) -> Float64

Момент истечения backoff после коллизии: `now + Uniform(0, backoffWindowMs)`
(равномерный backoff, аналог логики TS 36.321 §5.1.4).
"""
function schedule_backoff(rng::Random.AbstractRNG, now::Float64, cellCfg::CellConfig)
    return now + rand(rng) * cellCfg.backoffWindowMs
end

# ----------------------------------------------------------------------------
# DT-фаза
# ----------------------------------------------------------------------------

dt_utilization(pool::DTPool) = pool.capacity == 0 ? 0.0 : pool.busy / pool.capacity

"""
    try_seize_dt!(pool::DTPool) -> Bool

Пытается занять один DT-"сервер". `true` — успех, `false` — пул полон
(вызывающая сторона решает, блокировать устройство или ставить в очередь).
"""
function try_seize_dt!(pool::DTPool)
    pool.busy >= pool.capacity && return false
    pool.busy += 1
    return true
end

"""
    release_dt!(pool::DTPool)

Освобождает один DT-"сервер".
"""
function release_dt!(pool::DTPool)
    pool.busy = max(0, pool.busy - 1)
    return pool
end

# ----------------------------------------------------------------------------
# process! — диспетчеризация событий DES (вызывается из EventQueue.step!)
# ----------------------------------------------------------------------------

function process!(state::SimState, ev::ArrivalEvent)
    # Downlink-трафик не конкурирует за NPRACH (см. ТЗ и план, §2.4) — в Модуле 2
    # v0.1 не моделируется его последующая доставка, только сама генерация в Модуле 1.
    ev.kind == Downlink && return nothing

    device = Device(ev.deviceId, ev.kind, ev.time)
    device.state = WaitingForOccasion
    state.devices[ev.deviceId] = device
    push!(state.waitingDevices, ev.deviceId)
    return nothing
end

function process!(state::SimState, ev::NPRACHOccasionEvent)
    cfg = state.cellCfg
    competitors = collect(state.waitingDevices)
    empty!(state.waitingDevices)

    if !isempty(competitors)
        attempts = assign_preambles(state.rng, cfg.nprach, competitors)
        successes, collided = resolve_occasion(attempts)
        raUtil = length(attempts) / cfg.nprach.NumSubcarriers
        record_occasion_result!(state.metrics, state.now, length(successes), length(collided), raUtil)

        for did in successes
            _on_ra_success!(state, did)
        end
        for did in collided
            _on_ra_collision!(state, did)
        end
    else
        record_occasion_result!(state.metrics, state.now, 0, 0, 0.0)
    end

    push_event!(state, NPRACHOccasionEvent(state.now + cfg.nprach.Periodicity))
    return nothing
end

function _on_ra_success!(state::SimState, deviceId::Int)
    device = state.devices[deviceId]
    device.state = RASuccess
    device.raSuccessTime = state.now

    if try_seize_dt!(state.dtPool)
        device.state = DataTransmission
        device.dtStart = state.now
        dtEnd = state.now + state.cellCfg.dtServiceTimeMs
        device.dtEnd = dtEnd
        push_event!(state, DTDepartureEvent(dtEnd, deviceId))
        record_dt_snapshot!(state.metrics, state.now, dt_utilization(state.dtPool))
    elseif state.cellCfg.dropOnDtFull
        device.state = Dropped
        device.dropTime = state.now
        record_dt_snapshot!(state.metrics, state.now, dt_utilization(state.dtPool); blocked=1)
    else
        # Очередь на DT-ресурс не реализована в v0.1 (см. план, §3.4) — устройство
        # остаётся в состоянии RASuccess до следующей реализации.
    end
    return nothing
end

function _on_ra_collision!(state::SimState, deviceId::Int)
    device = state.devices[deviceId]
    device.preambleAttempts += 1

    if device.preambleAttempts >= state.cellCfg.maxPreambleAttempts
        device.state = Dropped
        device.dropTime = state.now
    else
        device.state = Backoff
        expiry = schedule_backoff(state.rng, state.now, state.cellCfg)
        push_event!(state, BackoffExpiryEvent(expiry, deviceId))
    end
    return nothing
end

function process!(state::SimState, ev::BackoffExpiryEvent)
    device = state.devices[ev.deviceId]
    device.state == Backoff || return nothing  # устройство уже могло быть удалено/сброшено
    device.state = WaitingForOccasion
    push!(state.waitingDevices, ev.deviceId)
    return nothing
end

function process!(state::SimState, ev::DTDepartureEvent)
    device = state.devices[ev.deviceId]
    device.state = Done
    release_dt!(state.dtPool)
    record_dt_snapshot!(state.metrics, state.now, dt_utilization(state.dtPool))
    return nothing
end
