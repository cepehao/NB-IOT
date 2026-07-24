using Test
using NBIoTSim
using Random

@testset "Analytics: предельные случаи точных формул" begin
    for N in (12, 24, 36, 48)
        @test p_collision_exact(0, N) == 0.0
        @test p_collision_exact(1, N) == 0.0             # одно устройство не может столкнуться
        @test expected_success_exact(0, N) == 0.0
        @test expected_success_exact(1, N) == 1.0         # единственное устройство всегда успешно
        @test expected_collided_preambles_exact(0, N) == 0.0
        @test isapprox(expected_collided_preambles_exact(1, N), 0.0; atol=1e-9)
        @test isapprox(expected_used_preambles_exact(0, N), 0.0)
        @test isapprox(expected_used_preambles_exact(1, N), 1.0)
    end
    # N -> ∞ (много поднесущих) => вероятность коллизии -> 0 при фиксированном M
    @test p_collision_exact(10, 10_000_000) < 1e-5
end

@testset "Analytics: Пуассоновское приближение — предельные случаи" begin
    @test isapprox(throughput_slotted_aloha(1.0), 1 / ℯ; atol=1e-9)
    @test isapprox(p_empty_poisson(0.0), 1.0; atol=1e-9)
    @test isapprox(p_collision_poisson(0.0), 0.0; atol=1e-9)
    # S(ρ) достигает максимума 1/e ровно при ρ=1 (классический результат slotted ALOHA)
    ρs = 0.5:0.01:1.5
    @test argmax(throughput_slotted_aloha.(ρs)) == findfirst(==(1.0), collect(ρs))
end

@testset "Analytics: Erlang B — предельные случаи" begin
    @test erlang_b(0, 5.0) == 1.0        # без серверов — всё блокируется
    @test isapprox(erlang_b(5, 0.0), 0.0; atol=1e-12)  # без нагрузки — блокировки нет
    # B(c,A) монотонно убывает по c при фиксированном A
    Bs = [erlang_b(c, 3.0) for c in 0:8]
    @test issorted(Bs; rev=true)
end

@testset "Analytics: Монте-Карло 'шары по ячейкам' vs точные формулы" begin
    rng = Xoshiro(2024)
    K = 5000
    cfgFor(N) = NPRACHConfig(NumSubcarriers=N, Periodicity=40, StartTime=8)
    for N in (12, 24, 48), M in (1, 2, 3, 5, 10, 20, 50)
        cfg = cfgFor(N)
        successCounts = Vector{Int}(undef, K)
        taggedCollided = falses(K)
        for trial in 1:K
            attempts = assign_preambles(rng, cfg, collect(1:M))
            successes, collided = resolve_occasion(attempts)
            successCounts[trial] = length(successes)
            taggedCollided[trial] = 1 in collided
        end

        empSuccess = sum(successCounts) / K
        theorySuccess = expected_success_exact(M, N)
        @test isapprox(empSuccess, theorySuccess; atol=max(0.5, 0.08 * max(theorySuccess, 1.0)))

        empPCollision = sum(taggedCollided) / K
        theoryPCollision = p_collision_exact(M, N)
        se = sqrt(max(theoryPCollision * (1 - theoryPCollision), 1e-6) / K)
        @test isapprox(empPCollision, theoryPCollision; atol=max(0.02, 6se))
    end
end

@testset "Analytics: сходимость точной формулы к Пуассоновскому приближению" begin
    # ВАЖНО: p_collision_exact — вероятность коллизии для ПОМЕЧЕННОГО УСТРОЙСТВА
    # (device-level); её предел при N,M->∞, ρ=M/N=const — это 1-e^{-ρ}
    # (= 1 - p_empty_poisson(ρ)), а НЕ p_collision_poisson(ρ). Последняя —
    # доля ПРЕАМБУЛ с коллизией (preamble/slot-level), её точный аналог —
    # expected_collided_preambles_exact(M,N)/N. Обе сходимости проверяем отдельно.
    N = 10_000
    for ρ in (0.2, 0.5, 1.0, 2.0)
        M = round(Int, ρ * N)
        @test isapprox(p_collision_exact(M, N), 1 - p_empty_poisson(ρ); atol=1e-3)
        @test isapprox(expected_collided_preambles_exact(M, N) / N, p_collision_poisson(ρ); atol=1e-3)
        @test isapprox(expected_success_exact(M, N) / N, throughput_slotted_aloha(ρ); atol=1e-3)
    end
end

@testset "DES vs Пуассоновское приближение (маленькая P_collision на occasion, no retry)" begin
    # При Poisson-трафике число конкурентов на occasion само распределено как
    # Poisson(M̄) (интервалы между occasion фиксированы), а разбиение по N
    # преамбулам расщепляет Poisson(M̄) на N независимых Poisson(M̄/N) —
    # ТОЧНОЕ (не приближённое) свойство прореживания пуассоновского процесса.
    # maxPreambleAttempts=1 убирает эффект повторных попыток на нагрузку occasion.
    rng = Xoshiro(99)
    N = 48
    P = 40  # мс
    λ_per_s = 20.0  # событий/сек
    ρ = (λ_per_s * P / 1000) / N

    cfg = TrafficConfig(kind=Poisson, numDevices=round(Int, λ_per_s * 2000), reportPeriod=2000.0, seed=555)
    simDuration_ms = 2000.0 * 1000  # 2000 с
    stream = build_traffic_stream(cfg, simDuration_ms)

    nprach = NPRACHConfig(NumSubcarriers=N, Periodicity=P, StartTime=8)
    cellCfg = CellConfig(nprach=nprach, maxPreambleAttempts=1, dtParallelUnits=10_000, dtServiceTimeMs=1.0)

    state = run_simulation(stream, cellCfg, simDuration_ms; rng=rng)

    m = state.metrics
    nOcc = length(m.tOccasion)
    @test nOcc > 1000  # достаточно occasions для устойчивой статистики

    perOccSuccess = diff(vcat(0, m.nSuccessCum))
    avgUsedFrac = sum(m.raOccupancy) / nOcc
    avgSuccessFrac = sum(perOccSuccess) / nOcc / N
    avgCollidedPreambleFrac = avgUsedFrac - avgSuccessFrac

    @test isapprox(avgUsedFrac, 1 - p_empty_poisson(ρ); atol=0.01)
    @test isapprox(avgSuccessFrac, throughput_slotted_aloha(ρ); atol=0.01)
    @test isapprox(avgCollidedPreambleFrac, p_collision_poisson(ρ); atol=0.01)
end

@testset "DES vs Erlang B (нечувствительность к закону обслуживания, DT-блокировка)" begin
    # N велико относительно нагрузки на occasion => P_collision пренебрежимо мала,
    # поток успехов RA практически совпадает с исходным Пуассоновским потоком трафика.
    # Erlang B справедлива для M/G/c/c при пуассоновских поступлениях независимо от
    # закона обслуживания (свойство нечувствительности) — здесь обслуживание
    # ДЕТЕРМИНИРОВАННОЕ (dtServiceTimeMs фиксировано), что и проверяем.
    rng = Xoshiro(7)
    λ_per_s = 2.0
    simDurationSec = 400.0
    cfg = TrafficConfig(kind=Poisson, numDevices=round(Int, λ_per_s * simDurationSec), reportPeriod=simDurationSec, seed=321)
    simDuration_ms = simDurationSec * 1000
    stream = build_traffic_stream(cfg, simDuration_ms)

    dtServiceTimeMs = 500.0
    c = 2
    A = λ_per_s * (dtServiceTimeMs / 1000)  # предложенная нагрузка, Эрланг

    nprach = NPRACHConfig(NumSubcarriers=48, Periodicity=40, StartTime=8)
    cellCfg = CellConfig(nprach=nprach, maxPreambleAttempts=10, dtParallelUnits=c,
                          dtServiceTimeMs=dtServiceTimeMs, dropOnDtFull=true)

    state = run_simulation(stream, cellCfg, simDuration_ms; rng=rng)

    successes = state.metrics.nSuccessCum[end]
    blocked = state.metrics.nDtBlocked[end]
    empBlockFrac = blocked / successes

    theoryB = erlang_b(c, A)
    @test isapprox(empBlockFrac, theoryB; atol=0.06)
end
