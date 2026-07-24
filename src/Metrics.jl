# Сборщики метрик Модуля 2 как временные ряды. Структура SimMetrics определена в
# Types.jl (см. комментарий там о причине консолидации структур).

"""
    record_occasion_result!(metrics, t, nSuccess, nCollisions, raUtil)

Фиксирует итог одного NPRACH occasion: `nSuccess`/`nCollisions` — число устройств
с успехом/коллизией В ЭТОМ occasion (не кумулятивно — накопление делает сама
функция, добавляя к последнему кумулятивному значению), `raUtil` — доля
использованных преамбул (`|used|/NumSubcarriers`).
"""
function record_occasion_result!(
    metrics::SimMetrics, t::Float64, nSuccess::Int, nCollisions::Int, raUtil::Float64,
)
    prevSuccess = isempty(metrics.nSuccessCum) ? 0 : metrics.nSuccessCum[end]
    prevCollisions = isempty(metrics.nCollisionsCum) ? 0 : metrics.nCollisionsCum[end]
    push!(metrics.tOccasion, t)
    push!(metrics.nSuccessCum, prevSuccess + nSuccess)
    push!(metrics.nCollisionsCum, prevCollisions + nCollisions)
    push!(metrics.raOccupancy, raUtil)
    return metrics
end

"""
    record_dt_snapshot!(metrics, t, dtUtil; blocked=0)

Фиксирует снимок загрузки DT-фазы `dtUtil = busy/dtParallelUnits` в момент `t`,
и (опционально) число заблокированных попыток занять DT-ресурс в этот момент
(накопление кумулятивное, аналогично `record_occasion_result!`).
"""
function record_dt_snapshot!(metrics::SimMetrics, t::Float64, dtUtil::Float64; blocked::Int=0)
    prevBlocked = isempty(metrics.nDtBlocked) ? 0 : metrics.nDtBlocked[end]
    push!(metrics.tDT, t)
    push!(metrics.dtOccupancy, dtUtil)
    push!(metrics.nDtBlocked, prevBlocked + blocked)
    return metrics
end
