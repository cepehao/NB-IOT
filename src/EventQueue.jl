# Универсальный DES-движок: приоритетная очередь событий по времени + главный
# цикл диспетчеризации. Сами структуры (SimState, DTPool, SimMetrics) определены
# в Types.jl; конкретные обработчики process!(state, ::ArrivalEvent) и т.д.
# определены в NPRACHSimulator.jl (Julia не требует, чтобы методы process!
# существовали в момент компиляции step! — только к моменту его вызова, а оба
# файла инклудятся в NBIoTSim.jl до первого вызова run_simulation).

using Random
using DataStructures: DataStructures, BinaryMinHeap

push_event!(state::SimState, ev::SimEvent) = push!(state.queue, ev)
pop_event!(state::SimState) = pop!(state.queue)

"""
    create_sim_state(cellCfg::CellConfig; rng=Random.default_rng()) -> SimState

Инициализирует пустое состояние симуляции (без событий трафика) для заданной
конфигурации соты. `validate_cell_config` вызывается здесь же.
"""
function create_sim_state(cellCfg::CellConfig; rng::Random.AbstractRNG=Random.default_rng())
    validate_cell_config(cellCfg)
    return SimState(
        0.0,
        BinaryMinHeap{SimEvent}(),
        Dict{Int,Device}(),
        Set{Int}(),
        cellCfg,
        SimMetrics(),
        DTPool(cellCfg.dtParallelUnits),
        rng,
    )
end

"""
    step!(state::SimState) -> Bool

Извлекает из очереди ближайшее по времени событие, продвигает `state.now` и
диспетчеризует его в `process!`. Возвращает `false`, если очередь пуста
(симуляция завершена), иначе `true`.
"""
function step!(state::SimState)
    isempty(state.queue) && return false
    ev = pop_event!(state)
    state.now = ev.time
    process!(state, ev)
    return true
end

"""
    run_simulation(stream::TrafficStream, cellCfg::CellConfig, simDuration::Float64; rng=Random.default_rng()) -> SimState

Запускает полную DES-симуляцию Модуля 2: заполняет очередь событиями поступлений
из `stream` (контракт с Модулем 1 — только `ArrivalEvent`, все служебные события
NPRACH/backoff/DT порождает сам движок), затем планирует первый NPRACH occasion и
крутит цикл `step!` до `simDuration` (мс) включительно (события с `time >
simDuration` не обрабатываются, а изымаются из очереди и отбрасываются).
Возвращает итоговый `SimState` (метрики — `state.metrics`).
"""
function run_simulation(
    stream::TrafficStream, cellCfg::CellConfig, simDuration::Float64;
    rng::Random.AbstractRNG=Random.default_rng(),
)
    state = create_sim_state(cellCfg; rng=rng)
    for ev in stream.events
        push_event!(state, ev)
    end
    firstOccasion = next_occasion_time(0.0, cellCfg.nprach)
    push_event!(state, NPRACHOccasionEvent(firstOccasion))

    while !isempty(state.queue)
        nextTime = first_event_time(state)
        nextTime > simDuration && break
        step!(state)
    end
    return state
end

first_event_time(state::SimState) = first(state.queue).time
