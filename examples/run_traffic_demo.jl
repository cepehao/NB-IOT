# Демонстрация Модуля 1 (Генератор трафика) в изоляции — без Модуля 2.
# Запуск: julia --project=examples examples/run_traffic_demo.jl

ENV["GKSwstype"] = "100"  # безголовый рендеринг GR (без дисплея)

using NBIoTSim
using Random
using Plots

simDuration_ms = 120_000.0  # 120 с

periodicCfg = TrafficConfig(kind=Periodic, numDevices=50, reportPeriod=10.0, jitterFraction=0.15, seed=1)
burstCfg = TrafficConfig(kind=Burst, numDevices=80, activationWindow=5.0, seed=2)
emergencyCfg = TrafficConfig(kind=Emergency, numDevices=150, activationWindow=10.0, seed=3)
downlinkCfg = TrafficConfig(kind=Downlink, numDevices=20, downlinkRate=1.0, pagingCycle=1.28, seed=4)

periodic = build_traffic_stream(periodicCfg, simDuration_ms)
burst = build_traffic_stream(burstCfg, simDuration_ms; rng=Xoshiro(2))
# Аварийный доступ смещён к середине окна наблюдения для наглядности всплеска.
emergencyShift = 40_000.0
emergencyRaw = build_traffic_stream(emergencyCfg, simDuration_ms - emergencyShift; rng=Xoshiro(3))
emergency = TrafficStream(
    [ArrivalEvent(e.time + emergencyShift, e.deviceId, e.kind) for e in emergencyRaw.events],
    emergencyRaw.perDeviceKind,
)
downlink = build_traffic_stream(downlinkCfg, simDuration_ms; rng=Xoshiro(4))

windowMs = 2_000.0  # окно оценки интенсивности, мс

println("Периодический трафик: ", length(periodic.events), " пакетов")
println("Всплеск (Burst): ", length(burst.events), " пакетов")
println("Аварийный доступ (Emergency): ", length(emergency.events), " пакетов")
println("Нисходящий трафик (Downlink): ", length(downlink.events), " пакетов")

# --- N_active(t) для аплинк-потоков (номинальная длительность обслуживания для
#     чисто-визуальной демонстрации Модуля 1 без Модуля 2, см. план §2.5) ---
nominalServiceMs = 300.0
function active_devices_series(stream::TrafficStream, nominalServiceMs::Float64)
    arrivals = [e.time for e in stream.events]
    departures = arrivals .+ nominalServiceMs
    return compute_active_devices(arrivals, departures)
end

tA, nA = active_devices_series(periodic, nominalServiceMs)
tB, nB = active_devices_series(burst, nominalServiceMs)
tE, nE = active_devices_series(emergency, nominalServiceMs)

pActive = plot(tA, nA; label="Periodic", xlabel="t, мс", ylabel="N_active(t)",
               title="Число активных устройств", linetype=:steppost)
plot!(pActive, tB, nB; label="Burst", linetype=:steppost)
plot!(pActive, tE, nE; label="Emergency", linetype=:steppost)

# --- λ(t) для всех потоков (включая downlink) ---
tλA, λA = estimate_intensity([e.time for e in periodic.events], simDuration_ms, windowMs)
tλB, λB = estimate_intensity([e.time for e in burst.events], simDuration_ms, windowMs)
tλE, λE = estimate_intensity([e.time for e in emergency.events], simDuration_ms, windowMs)
tλD, λD = estimate_intensity([e.time for e in downlink.events], simDuration_ms, windowMs)

pIntensity = plot(tλA, λA; label="Periodic", xlabel="t, мс", ylabel="λ̂(t), пакетов/мс",
                   title="Интенсивность поступления пакетов (окно $(windowMs) мс)")
plot!(pIntensity, tλB, λB; label="Burst")
plot!(pIntensity, tλE, λE; label="Emergency")
plot!(pIntensity, tλD, λD; label="Downlink")

outPath = joinpath(@__DIR__, "traffic_demo.png")
savefig(plot(pActive, pIntensity; layout=(2, 1), size=(900, 700)), outPath)
println("Графики сохранены в ", outPath)
