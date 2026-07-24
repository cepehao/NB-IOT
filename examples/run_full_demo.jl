# Сквозной прогон: Модуль 1 (смешанный трафик) -> Модуль 2 (NPRACH-симуляция).
# Демонстрирует контракт между модулями (TrafficStream -> run_simulation) и
# сопоставляет нагрузку трафика с откликом сети (коллизии/успехи/загрузка).
# Запуск: julia --project=examples examples/run_full_demo.jl

ENV["GKSwstype"] = "100"

using NBIoTSim
using Random
using Plots

simDuration_ms = 60_000.0  # 60 с

# Фоновый периодический трафик датчиков + всплеск аварийного доступа в середине окна.
periodicCfg = TrafficConfig(kind=Periodic, numDevices=60, reportPeriod=8.0, jitterFraction=0.15, seed=1)
emergencyCfg = TrafficConfig(kind=Emergency, numDevices=250, activationWindow=5.0, seed=2)

periodic = build_traffic_stream(periodicCfg, simDuration_ms)
emergencyShift = 25_000.0
emergencyRaw = build_traffic_stream(emergencyCfg, simDuration_ms - emergencyShift; rng=Xoshiro(2))
emergency = TrafficStream(
    [ArrivalEvent(e.time + emergencyShift, e.deviceId, e.kind) for e in emergencyRaw.events],
    emergencyRaw.perDeviceKind,
)

stream = merge_streams([periodic, emergency])
println("Суммарный поток: ", length(stream.events), " поступлений")

windowMs = 2_000.0
tλ, λ̂ = estimate_intensity([e.time for e in stream.events], simDuration_ms, windowMs)

cellCfg = CellConfig(
    nprach=NPRACHConfig(NumSubcarriers=12, Periodicity=80, StartTime=8),
    maxPreambleAttempts=10, backoffWindowMs=300.0,
    dtParallelUnits=30, dtServiceTimeMs=40.0,
)

state = run_simulation(stream, cellCfg, simDuration_ms; rng=Xoshiro(99))
m = state.metrics

pIntensity = plot(tλ, λ̂; label="λ̂(t)", xlabel="t, мс", ylabel="пакетов/мс",
                   title="Модуль 1: интенсивность трафика (Periodic + Emergency в t≈$(Int(emergencyShift)) мс)",
                   lw=2)

pCollisions = plot(m.tOccasion, m.nCollisionsCum; label="Коллизии (накоп.)", xlabel="t, мс",
                    ylabel="Количество", title="Модуль 2: отклик сети на всплеск нагрузки", lw=2)
plot!(pCollisions, m.tOccasion, m.nSuccessCum; label="Успехи (накоп.)", lw=2)

pOccupancy = plot(m.tOccasion, m.raOccupancy; label="RA occupancy", xlabel="t, мс",
                   ylabel="Загрузка", title="Загрузка ресурсов RA/DT")
plot!(pOccupancy, m.tDT, m.dtOccupancy; label="DT occupancy")

outPath = joinpath(@__DIR__, "full_demo.png")
savefig(plot(pIntensity, pCollisions, pOccupancy; layout=(3, 1), size=(900, 950)), outPath)
println("Графики сохранены в ", outPath)

nDropped = count(d -> d.state == Dropped, values(state.devices))
nDone = count(d -> d.state == Done, values(state.devices))
println("Устройств завершили RA успешно (Done): ", nDone)
println("Устройств отброшено (Dropped, исчерпан maxPreambleAttempts): ", nDropped)
