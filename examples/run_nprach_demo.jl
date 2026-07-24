# Демонстрация Модуля 2 (Имитационная модель NB-IoT): сверка событийной модели
# с аналитическими формулами + временные ряды коллизий/успехов/загрузки ресурса.
# Запуск: julia --project=examples examples/run_nprach_demo.jl

ENV["GKSwstype"] = "100"

using NBIoTSim
using Random
using Plots

# --- 1. P_collision(M) теория vs Монте-Карло, при фиксированном N ---
N = 12
Mrange = 1:2:60
rng = Xoshiro(10)
K = 3000

empPCollision = Float64[]
for M in Mrange
    hits = 0
    for _ in 1:K
        attempts = assign_preambles(rng, NPRACHConfig(NumSubcarriers=N), collect(1:M))
        _, collided = resolve_occasion(attempts)
        hits += (1 in collided) ? 1 : 0
    end
    push!(empPCollision, hits / K)
end
theoryPCollision = [p_collision_exact(M, N) for M in Mrange]

pCollision = plot(Mrange, theoryPCollision; label="Теория: 1-(1-1/N)^(M-1)", lw=2,
                   xlabel="M (число конкурирующих устройств)", ylabel="P_collision",
                   title="Вероятность коллизии помеченного устройства, N=$N")
scatter!(pCollision, Mrange, empPCollision; label="Монте-Карло (K=$K)", ms=3)

# --- 2. Throughput slotted ALOHA vs ρ ---
ρs = 0.01:0.02:3.0
pThroughput = plot(ρs, throughput_slotted_aloha.(ρs); label="S(ρ)=ρe^(-ρ)", lw=2,
                    xlabel="ρ = M/N", ylabel="Доля успешных преамбул",
                    title="Throughput slotted ALOHA (максимум 1/e при ρ=1)")
vline!(pThroughput, [1.0]; label="ρ=1", linestyle=:dash)

# --- 3. Полный DES-прогон: коллизии/успехи/загрузка ресурсов во времени ---
cellCfg = CellConfig(
    nprach=NPRACHConfig(NumSubcarriers=12, Periodicity=40, StartTime=8),
    maxPreambleAttempts=10, backoffWindowMs=200.0,
    dtParallelUnits=20, dtServiceTimeMs=30.0,
)
trafficCfg = TrafficConfig(kind=Emergency, numDevices=300, activationWindow=5.0, seed=20)
simDuration_ms = 10_000.0
stream = build_traffic_stream(trafficCfg, simDuration_ms)
state = run_simulation(stream, cellCfg, simDuration_ms; rng=Xoshiro(20))
m = state.metrics

pCounts = plot(m.tOccasion, m.nSuccessCum; label="Успешные доступы (накоп.)", lw=2,
               xlabel="t, мс", ylabel="Количество",
               title="Аварийный массовый доступ: 300 устройств, N=12 преамбул")
plot!(pCounts, m.tOccasion, m.nCollisionsCum; label="Коллизии (накоп.)", lw=2)

pOccupancy = plot(m.tOccasion, m.raOccupancy; label="RA occupancy", xlabel="t, мс",
                   ylabel="Загрузка", title="Загрузка ресурсов RA/DT")
plot!(pOccupancy, m.tDT, m.dtOccupancy; label="DT occupancy")

outPath = joinpath(@__DIR__, "nprach_demo.png")
savefig(plot(pCollision, pThroughput, pCounts, pOccupancy; layout=(2, 2), size=(1100, 800)), outPath)
println("Графики сохранены в ", outPath)
println("Итог: успехов=", m.nSuccessCum[end], ", коллизий(устройство-попыток)=", m.nCollisionsCum[end])
