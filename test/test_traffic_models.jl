using Test
using NBIoTSim
using Random
using HypothesisTests: ExactOneSampleKSTest, ApproximateOneSampleKSTest, pvalue
using Distributions: Uniform, Beta

@testset "TrafficModels: TR 37.868 Model 1 (Uniform)" begin
    rng = Xoshiro(1)
    T = 10.0
    x = sample_activation_model1(rng, 20_000, T)
    @test length(x) == 20_000
    @test all(0 .<= x .<= T)
    test = ExactOneSampleKSTest(x, Uniform(0.0, T))
    @test pvalue(test) > 0.01
end

@testset "TrafficModels: TR 37.868 Model 2 (Beta(3,4) scaled)" begin
    rng = Xoshiro(2)
    T = 10.0
    x = sample_activation_model2(rng, 20_000, T)
    @test length(x) == 20_000
    @test all(0 .<= x .<= T)
    # KS против Beta(3,4) на нормализованной x/T (масштабирование не меняет форму распределения)
    test = ExactOneSampleKSTest(x ./ T, Beta(3, 4))
    @test pvalue(test) > 0.01
    # Плотность имеет максимум при t = (a-1)/(a+b-2)*T = 0.4*T -- грубая проверка через среднее.
    @test isapprox(sum(x) / length(x), T * 3 / 7; atol=0.05 * T)  # E[Beta(3,4)] = a/(a+b) = 3/7
end

@testset "TrafficModels: периодический поток на устройство" begin
    rng = Xoshiro(3)
    P = 10.0
    simDuration = 100.0
    stream = generate_periodic_device_stream(rng, P, 0.0, simDuration)
    @test length(stream) == 11  # k=0..10 включительно: [0,simDuration] закрытый интервал
    @test issorted(stream)

    rngJ = Xoshiro(4)
    streamJ = generate_periodic_device_stream(rngJ, P, 0.2, simDuration)
    @test all(0 .<= streamJ .<= simDuration)
end

@testset "TrafficModels: пуассоновский поток" begin
    rng = Xoshiro(5)
    λ = 5.0
    simDuration = 1000.0
    times = generate_poisson_arrivals(rng, λ, simDuration)
    @test issorted(times)
    @test all(0 .<= times .<= simDuration)
    # Число событий ~ Poisson(λ*T), проверяем среднее в разумных пределах (±5σ)
    expected = λ * simDuration
    σ = sqrt(expected)
    @test abs(length(times) - expected) < 5σ
end

@testset "TrafficModels: downlink квантуется к paging cycle" begin
    rng = Xoshiro(6)
    pagingCycle = 1.28
    times = generate_downlink_arrivals(rng, 2.0, pagingCycle, 100.0)
    @test all(t -> isapprox(t / pagingCycle, round(t / pagingCycle); atol=1e-9), times)
end

@testset "TrafficGenerator: build_traffic_stream и merge_streams" begin
    cfg = TrafficConfig(kind=Periodic, numDevices=10, reportPeriod=5.0, jitterFraction=0.1, seed=42)
    stream = build_traffic_stream(cfg, 50_000.0)
    @test issorted([e.time for e in stream.events])
    @test all(e -> e.kind == Periodic, stream.events)
    ids = [e.deviceId for e in stream.events]
    @test length(ids) == length(unique(ids))  # уникальные session id (см. комментарий в TrafficGenerator.jl)

    cfg2 = TrafficConfig(kind=Emergency, numDevices=5, activationWindow=1.0, seed=43)
    stream2 = build_traffic_stream(cfg2, 2_000.0)

    merged = merge_streams([stream, stream2])
    @test length(merged.events) == length(stream.events) + length(stream2.events)
    @test issorted([e.time for e in merged.events])
    mids = [e.deviceId for e in merged.events]
    @test length(mids) == length(unique(mids))
end

@testset "TrafficGenerator: детерминизм при фиксированном seed" begin
    cfg = TrafficConfig(kind=Burst, numDevices=50, activationWindow=5.0, seed=100)
    s1 = build_traffic_stream(cfg, 5_000.0)
    s2 = build_traffic_stream(cfg, 5_000.0)
    @test [e.time for e in s1.events] == [e.time for e in s2.events]
end

@testset "TrafficGenerator: compute_active_devices / estimate_intensity" begin
    arrivals = [0.0, 1.0, 2.0, 3.0]
    departures = [1.5, 2.5, 3.5, 4.5]
    t, n = compute_active_devices(arrivals, departures)
    @test n[end] == 0
    @test maximum(n) <= length(arrivals)

    times, λ̂ = estimate_intensity([0.5, 0.5, 1.5, 2.5], 3.0, 1.0)
    @test length(times) == 3
    @test λ̂[1] == 2.0  # два поступления в бине [0,1)
end

@testset "TrafficGenerator: Periodic (a) джиттер vs (b) Пуассон-асимптотика сходятся по λ(t)" begin
    numDevices = 2000
    P = 20.0
    simDurationSec = 2000.0
    simDuration_ms = simDurationSec * 1000

    cfgA = TrafficConfig(kind=Periodic, numDevices=numDevices, reportPeriod=P, jitterFraction=0.2,
                          aggregateAsPoisson=false, seed=7)
    cfgB = TrafficConfig(kind=Periodic, numDevices=numDevices, reportPeriod=P,
                          aggregateAsPoisson=true, seed=8)

    sA = build_traffic_stream(cfgA, simDuration_ms)
    sB = build_traffic_stream(cfgB, simDuration_ms)

    rateA = length(sA.events) / simDurationSec
    rateB = length(sB.events) / simDurationSec
    expected = numDevices / P
    @test isapprox(rateA, expected; rtol=0.05)
    @test isapprox(rateB, expected; rtol=0.05)
end
