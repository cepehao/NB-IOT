using Random: Random
using DataStructures: DataStructures, BinaryMinHeap

# Все структуры данных и типы событий системы собраны в одном файле.
#
# Единицы измерения времени (важно соблюдать во всех вызовах!):
#   - TrafficConfig: поля активации/периода трафика — В СЕКУНДАХ (как в 3GPP TR 37.868).
#   - NPRACHConfig/CellConfig: все временные поля — В МИЛЛИСЕКУНДАХ (как в 3GPP TS 36.211/36.321).
#   - Часы дискретно-событийной симуляции (SimState.now, все SimEvent.time,
#     TrafficStream.events[i].time) — В МИЛЛИСЕКУНДАХ. build_traffic_stream переводит
#     секунды TrafficConfig в миллисекунды на границе Модуль 1 → Модуль 2.
#
# Julia требует, чтобы тип был объявлен раньше первого использования в сигнатуре поля.
# SimState ссылается на CellConfig/Device/SimMetrics/DTPool, поэтому все структуры
# (не только "конфиги", но и DTPool/SimMetrics/SimState, которые по плану логически
# принадлежат NPRACHSimulator.jl/Metrics.jl/EventQueue.jl) размещены здесь, чтобы избежать
# циклических include. Файлы NPRACHSimulator.jl, EventQueue.jl, Metrics.jl содержат
# только функции/логику, оперирующую этими типами через multiple dispatch.

# ============================================================================
# Перечисления
# ============================================================================

"""
    TrafficKind

Тип потока трафика, порождаемого Модулем 1.

- `Periodic`  — обычный периодический восходящий трафик датчиков (в т.ч. "обычный
                восходящий IoT-трафик" из ТЗ, используется как вариант по умолчанию).
- `Poisson`   — агрегированный пуассоновский поток (асимптотика суперпозиции многих
                периодических источников либо самостоятельный поток с заданным λ).
- `Burst`     — кратковременный всплеск трафика (3GPP TR 37.868 Model 2, короткое окно T).
- `Emergency` — аварийный массовый доступ (3GPP TR 37.868 Model 2, каноническое T=10 c).
- `Downlink`  — нисходящий трафик IoT (не конкурирует за NPRACH).
"""
@enum TrafficKind Periodic Poisson Burst Emergency Downlink

"""
    DeviceState

Состояния устройства в процедуре случайного доступа (адаптация TS 36.321 под
однотональный NPRACH, один уровень покрытия).
"""
@enum DeviceState begin
    Idle
    WaitingForOccasion   # пакет пришёл (или истёк backoff), ждёт ближайший NPRACH occasion
    Transmitting         # передаёт преамбулу в текущем occasion (транзиентное состояние
                         # внутри обработки NPRACHOccasionEvent, не хранится между событиями)
    Backoff              # коллизия/неудача, ждёт случайный backoff
    RASuccess            # преамбула принята без коллизии
    Dropped              # исчерпан maxPreambleAttempts
    DataTransmission     # занимает DT-ресурс
    Done
end

# ============================================================================
# Конфигурация трафика (Модуль 1)
# ============================================================================

"""
    TrafficConfig

Параметры генератора трафика. Временные поля — в секундах (следуя 3GPP TR 37.868,
где T задаётся в секундах). См. также [`build_traffic_stream`](@ref).
"""
Base.@kwdef struct TrafficConfig
    kind::TrafficKind
    numDevices::Int
    activationWindow::Float64 = 10.0     # T, сек (TR 37.868 Model 1/2)
    reportPeriod::Float64 = 60.0         # сек, период отчёта для Periodic
    jitterFraction::Float64 = 0.1        # доля reportPeriod для равномерного джиттера
    aggregateAsPoisson::Bool = false     # Periodic: (a) per-device джиттер vs (b) агрегированный Пуассон
    downlinkRate::Float64 = 0.0          # λ_dl, пакетов/сек, для Downlink
    pagingCycle::Float64 = 1.28          # сек, квант доставки для Downlink
    seed::Union{Nothing,Int} = nothing
end

# ============================================================================
# Конфигурация соты / NPRACH (Модуль 2)
# ============================================================================

"""
    NPRACHConfig

Имена и семантика полей намеренно совпадают со структурой `chs`, принимаемой
функцией `lteNPRACH`/`lteNPRACHInfo` в MATLAB LTE Toolbox (см. docs/guideMatlab.md,
~L4964-4975), чтобы конфиг можно было напрямую конвертировать в MATLAB struct
(`MatlabBridge.to_mxstruct`) при подключении физического уровня в Модуле 3.

Все временные поля — в миллисекундах. `mutable`, чтобы будущий Модуль 4 мог менять
параметры между occasions без пересоздания симуляции.
"""
Base.@kwdef mutable struct NPRACHConfig
    NPRACHFormat::String   = "0"     # поддерживается только формат '0' (FDD, один CE-уровень)
    Periodicity::Int       = 80      # мс; допустимо {40,80,160,240,320,640,1280,2560} (TS 36.211 §10.1.6.1)
    SubcarrierOffset::Int  = 0       # первая поднесущая, выделенная под NPRACH
    NumSubcarriers::Int    = 12      # = число доступных преамбул на occasion; допустимо {12,24,36,48}
    NRep::Int              = 1       # число повторений преамбулы; допустимо {1,2,4,8,16,32,64,128}
    StartTime::Int         = 8       # мс; допустимо {8,16,32,64,128,256,512,1024}
    NInit::Int             = 0       # runtime: индекс преамбулы конкретной попытки (не используется как конфиг occasion)
    NPRACHPower::Float64   = 0.0     # задел под физ. уровень (Модуль 3), не используется сейчас
end

"""
    CellConfig

Параметры соты, объединяющие NPRACH-конфигурацию, процедуру повторных попыток
(аналог `preambleTransMax` из TS 36.321) и модель DT-фазы. `raShare`/`dtShare` —
статические на этом этапе; это "разъём" для будущего Модуля 4 динамической адаптации.
"""
Base.@kwdef mutable struct CellConfig
    duplexMode::String = "FDD"
    nprach::NPRACHConfig = NPRACHConfig()
    maxPreambleAttempts::Int = 10     # аналог preambleTransMax, TS 36.321
    backoffWindowMs::Float64 = 960.0  # верхняя граница равномерного backoff, мс
    raShare::Float64 = 0.1            # доля ресурса под RA (для occupancy-метрик и будущего Модуля 4)
    dtShare::Float64 = 0.9            # доля ресурса под DT
    dtParallelUnits::Int = 8          # абстрактная ёмкость DT-фазы ("серверы")
    dtServiceTimeMs::Float64 = 50.0   # среднее время занятия DT-ресурса одной передачей, мс
    dropOnDtFull::Bool = true         # true => blocking (Erlang-B), false => очередь (не реализовано в v0.1)
end

function validate_nprach_config(cfg::NPRACHConfig)
    cfg.NPRACHFormat == "0" ||
        throw(ArgumentError("В Модуле 2 (v0.1) поддерживается только NPRACHFormat \"0\" (получено \"$(cfg.NPRACHFormat)\")"))

    validPeriodicity = (40, 80, 160, 240, 320, 640, 1280, 2560)
    cfg.Periodicity in validPeriodicity ||
        throw(ArgumentError("Periodicity должен быть одним из $(validPeriodicity) мс (TS 36.211 §10.1.6.1), получено $(cfg.Periodicity)"))

    validStartTime = (8, 16, 32, 64, 128, 256, 512, 1024)
    cfg.StartTime in validStartTime ||
        throw(ArgumentError("StartTime должен быть одним из $(validStartTime) мс (FDD, TS 36.211 §10.1.6.1), получено $(cfg.StartTime)"))

    validNumSubcarriers = (12, 24, 36, 48)
    cfg.NumSubcarriers in validNumSubcarriers ||
        throw(ArgumentError("NumSubcarriers должен быть одним из $(validNumSubcarriers), получено $(cfg.NumSubcarriers)"))

    validNRep = (1, 2, 4, 8, 16, 32, 64, 128)
    cfg.NRep in validNRep ||
        throw(ArgumentError("NRep должен быть одним из $(validNRep), получено $(cfg.NRep)"))

    cfg.SubcarrierOffset >= 0 ||
        throw(ArgumentError("SubcarrierOffset должен быть неотрицательным, получено $(cfg.SubcarrierOffset)"))

    cfg.SubcarrierOffset + cfg.NumSubcarriers <= 48 ||
        throw(ArgumentError(
            "SubcarrierOffset + NumSubcarriers = $(cfg.SubcarrierOffset + cfg.NumSubcarriers) " *
            "превышает 48 поднесущих несущей NB-IoT (180 кГц / 3.75 кГц)"))

    return nothing
end

function validate_cell_config(cfg::CellConfig)
    validate_nprach_config(cfg.nprach)
    cfg.maxPreambleAttempts >= 1 ||
        throw(ArgumentError("maxPreambleAttempts должен быть >= 1"))
    cfg.backoffWindowMs >= 0 ||
        throw(ArgumentError("backoffWindowMs должен быть неотрицательным"))
    isapprox(cfg.raShare + cfg.dtShare, 1.0; atol=1e-9) ||
        throw(ArgumentError("raShare + dtShare должны давать в сумме 1.0, получено $(cfg.raShare + cfg.dtShare)"))
    cfg.dtParallelUnits >= 1 ||
        throw(ArgumentError("dtParallelUnits должен быть >= 1"))
    cfg.dtServiceTimeMs > 0 ||
        throw(ArgumentError("dtServiceTimeMs должен быть положительным"))
    return nothing
end

# ============================================================================
# Устройство
# ============================================================================

"""
    Device

Изменяемое состояние одного UE в ходе DES-симуляции. Времена — в миллисекундах
(шкала симуляции, см. верх файла).
"""
mutable struct Device
    id::Int
    kind::TrafficKind
    state::DeviceState
    arrivalTime::Float64
    preambleAttempts::Int
    lastPreamble::Int
    raSuccessTime::Union{Nothing,Float64}
    dropTime::Union{Nothing,Float64}
    dtStart::Union{Nothing,Float64}
    dtEnd::Union{Nothing,Float64}
end

Device(id::Int, kind::TrafficKind, arrivalTime::Float64) =
    Device(id, kind, Idle, arrivalTime, 0, 0, nothing, nothing, nothing, nothing)

# ============================================================================
# События DES
# ============================================================================

abstract type SimEvent end

struct ArrivalEvent <: SimEvent
    time::Float64
    deviceId::Int
    kind::TrafficKind
end

struct NPRACHOccasionEvent <: SimEvent
    time::Float64
end

struct BackoffExpiryEvent <: SimEvent
    time::Float64
    deviceId::Int
end

struct DTDepartureEvent <: SimEvent
    time::Float64
    deviceId::Int
end

Base.isless(a::SimEvent, b::SimEvent) = a.time < b.time

# ============================================================================
# Выход Модуля 1
# ============================================================================

"""
    TrafficStream

Результат работы Модуля 1: отсортированный по времени список поступлений и
принадлежность каждого устройства к типу трафика. `events[i].time` — в мс
(шкала симуляции), см. [`build_traffic_stream`](@ref).
"""
struct TrafficStream
    events::Vector{ArrivalEvent}
    perDeviceKind::Dict{Int,TrafficKind}
end

# ============================================================================
# DT-фаза
# ============================================================================

"""
    DTPool

Абстрактный пул ресурса фазы передачи данных (DT): `dtParallelUnits` "серверов"
без детальной физики NPUSCH (см. `try_seize_dt!`/`release_dt!` в NPRACHSimulator.jl).
"""
mutable struct DTPool
    capacity::Int
    busy::Int
end

DTPool(capacity::Int) = DTPool(capacity, 0)

# ============================================================================
# Метрики (Модуль 2, "на экране")
# ============================================================================

"""
    SimMetrics

Временные ряды метрик Модуля 2, требуемых ТЗ: количество коллизий, число успешных
доступов, загрузка ресурсов (RA/DT). Заполняется функциями `record_occasion_result!`
и `record_dt_snapshot!` (Metrics.jl).
"""
mutable struct SimMetrics
    tOccasion::Vector{Float64}
    nCollisionsCum::Vector{Int}
    nSuccessCum::Vector{Int}
    raOccupancy::Vector{Float64}
    tDT::Vector{Float64}
    dtOccupancy::Vector{Float64}
    nDtBlocked::Vector{Int}
end

SimMetrics() = SimMetrics(Float64[], Int[], Int[], Float64[], Float64[], Float64[], Int[])

# ============================================================================
# Состояние симуляции
# ============================================================================

"""
    SimState

Полное состояние дискретно-событийной симуляции Модуля 2. `queue` — очередь
событий по времени (см. EventQueue.jl); `waitingDevices` — множество id
устройств в состоянии `WaitingForOccasion`, поддерживается инкрементально
process!-обработчиками, чтобы не сканировать всех устройств на каждый occasion.
"""
mutable struct SimState
    now::Float64
    queue::BinaryMinHeap{SimEvent}    # см. EventQueue.jl: push_event!/pop_event!
    devices::Dict{Int,Device}
    waitingDevices::Set{Int}
    cellCfg::CellConfig
    metrics::SimMetrics
    dtPool::DTPool
    rng::Random.AbstractRNG
end
