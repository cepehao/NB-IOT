using Test
using NBIoTSim
using Random

@testset "next_occasion_time — сетка StartTime + k*Periodicity" begin
    cfg = NPRACHConfig(NumSubcarriers=12, Periodicity=80, StartTime=8)
    @test next_occasion_time(0.0, cfg) == 8.0
    @test next_occasion_time(8.0, cfg) == 8.0     # включительно (>= t)
    @test next_occasion_time(8.1, cfg) == 88.0
    @test next_occasion_time(88.0, cfg) == 88.0
    @test next_occasion_time(200.0, cfg) == 248.0  # 8 + 3*80
end

@testset "select_preamble — диапазон" begin
    rng = Xoshiro(1)
    cfg = NPRACHConfig(NumSubcarriers=12)
    for _ in 1:1000
        p = select_preamble(rng, cfg)
        @test 1 <= p <= 12
    end
end

@testset "resolve_occasion — чистое разбиение на успехи/коллизии" begin
    attempts = Dict(1 => [10], 2 => [20, 21], 3 => [30, 31, 32], 4 => [40])
    successes, collided = resolve_occasion(attempts)
    @test sort(successes) == [10, 40]
    @test sort(collided) == [20, 21, 30, 31, 32]

    @test resolve_occasion(Dict{Int,Vector{Int}}()) == (Int[], Int[])
end

@testset "assign_preambles + resolve_occasion — принудительная коллизия (N=1)" begin
    rng = Xoshiro(2)
    cfg = NPRACHConfig(NumSubcarriers=1)  # все выбирают единственную преамбулу
    attempts = assign_preambles(rng, cfg, [1, 2, 3])
    successes, collided = resolve_occasion(attempts)
    @test isempty(successes)
    @test sort(collided) == [1, 2, 3]
end

@testset "schedule_backoff — в пределах окна" begin
    rng = Xoshiro(3)
    cellCfg = CellConfig(backoffWindowMs=500.0)
    now = 1000.0
    for _ in 1:1000
        t = schedule_backoff(rng, now, cellCfg)
        @test now <= t <= now + 500.0
    end
end

@testset "DTPool — occupancy и переполнение" begin
    pool = DTPool(2)
    @test dt_utilization(pool) == 0.0
    @test try_seize_dt!(pool) == true
    @test try_seize_dt!(pool) == true
    @test dt_utilization(pool) == 1.0
    @test try_seize_dt!(pool) == false  # пул полон
    release_dt!(pool)
    @test dt_utilization(pool) == 0.5
    @test try_seize_dt!(pool) == true
end

@testset "validate_nprach_config — отклоняет недопустимые параметры" begin
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(Periodicity=15))
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(StartTime=100))
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(NumSubcarriers=20))
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(NRep=3))
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(NPRACHFormat="1"))
    @test_throws ArgumentError validate_nprach_config(NPRACHConfig(SubcarrierOffset=40, NumSubcarriers=12))
    @test validate_nprach_config(NPRACHConfig()) === nothing
end

@testset "process!(ArrivalEvent) — Downlink не создаёт RA-сессию" begin
    cellCfg = CellConfig()
    state = create_sim_state(cellCfg; rng=Xoshiro(4))
    process!(state, ArrivalEvent(0.0, 1, Downlink))
    @test isempty(state.devices)
    @test isempty(state.waitingDevices)

    process!(state, ArrivalEvent(0.0, 2, Periodic))
    @test haskey(state.devices, 2)
    @test state.devices[2].state == WaitingForOccasion
    @test 2 in state.waitingDevices
end

@testset "Полный цикл RA: один конкурент — гарантированный успех и переход в DT" begin
    nprach = NPRACHConfig(NumSubcarriers=12, Periodicity=40, StartTime=8)
    cellCfg = CellConfig(nprach=nprach, dtParallelUnits=1, dtServiceTimeMs=10.0)
    state = create_sim_state(cellCfg; rng=Xoshiro(5))

    stream = TrafficStream([ArrivalEvent(0.0, 1, Periodic)], Dict(1 => Periodic))
    finalState = run_simulation(stream, cellCfg, 200.0; rng=Xoshiro(5))

    device = finalState.devices[1]
    @test device.state == Done
    @test device.raSuccessTime !== nothing
    @test device.dtStart !== nothing
    @test device.dtEnd !== nothing
    @test finalState.metrics.nSuccessCum[end] == 1
    @test finalState.metrics.nCollisionsCum[end] == 0
end

@testset "Повторные попытки: коллизии подряд приводят к Dropped после maxPreambleAttempts" begin
    # NumSubcarriers=1 недопустим по 3GPP (validate_nprach_config), поэтому
    # коллизию не форсируем через конфиг, а вызываем внутреннюю логику подсчёта
    # попыток напрямую (NBIoTSim._on_ra_collision! не экспортируется, но доступна
    # по полному имени) — детерминированная проверка чистой RA state machine.
    nprach = NPRACHConfig(NumSubcarriers=12, Periodicity=40, StartTime=8)
    cellCfg = CellConfig(nprach=nprach, maxPreambleAttempts=3, backoffWindowMs=20.0)
    state = create_sim_state(cellCfg; rng=Xoshiro(6))
    device = Device(1, Periodic, 0.0)
    device.state = WaitingForOccasion
    state.devices[1] = device

    NBIoTSim._on_ra_collision!(state, 1)
    @test device.preambleAttempts == 1
    @test device.state == Backoff
    @test length(state.queue) == 1  # BackoffExpiryEvent запланирован

    NBIoTSim._on_ra_collision!(state, 1)
    @test device.preambleAttempts == 2
    @test device.state == Backoff

    NBIoTSim._on_ra_collision!(state, 1)
    @test device.preambleAttempts == 3
    @test device.state == Dropped
    @test device.dropTime == state.now
end

@testset "Полный цикл под нагрузкой: малое N и много устройств дают и успехи, и коллизии" begin
    nprach = NPRACHConfig(NumSubcarriers=12, Periodicity=40, StartTime=8)
    cellCfg = CellConfig(nprach=nprach, maxPreambleAttempts=5, backoffWindowMs=100.0,
                          dtParallelUnits=200, dtServiceTimeMs=5.0)
    cfg = TrafficConfig(kind=Emergency, numDevices=200, activationWindow=1.0, seed=11)
    stream = build_traffic_stream(cfg, 2_000.0)

    finalState = run_simulation(stream, cellCfg, 5_000.0; rng=Xoshiro(11))

    states = [d.state for d in values(finalState.devices)]
    @test length(finalState.devices) == 200
    @test all(s -> s in (Done, Dropped), states)  # к концу симуляции все сессии завершены
    @test count(==(Done), states) > 0
    @test count(==(Dropped), states) > 0  # при 200 устройствах на 12 преамбул коллизии неизбежны
    @test finalState.metrics.nCollisionsCum[end] > 0
end
