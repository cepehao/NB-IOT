# Аналитические формулы для верификации "математической точности" событийной
# модели Модуля 2 (сравниваются с эмпирическими результатами DES в test/).
#
# Постановка "шары по ячейкам": M активных устройств независимо и равновероятно
# выбирают одну из N доступных преамбул (одна поднесущая NPRACH = одна преамбула,
# однотональная передача). Число устройств на конкретной преамбуле ~ Binomial(M, 1/N).

"""
    p_collision_exact(M, N) -> Float64

Точная вероятность того, что случайно выбранное (помеченное) устройство из `M`
разделило свою преамбулу хотя бы с одним другим устройством, при `N` доступных
преамбулах:

    P_collision(M,N) = 1 − (1 − 1/N)^(M−1)

(классическая формула "birthday problem"/"шары по ячейкам" для помеченного шара).

Это DEVICE-LEVEL величина (вероятность для одного устройства), в отличие от
PREAMBLE-LEVEL `p_collision_poisson`/`expected_collided_preambles_exact` (доля
преамбул с коллизией). Предел при `N,M→∞`, `ρ=M/N=const`: `p_collision_exact →
1 − e^(−ρ) = 1 − p_empty_poisson(ρ)`, а НЕ `p_collision_poisson(ρ)` — не путать.
"""
function p_collision_exact(M::Integer, N::Integer)
    N >= 1 || throw(ArgumentError("N должно быть >= 1"))
    M >= 0 || throw(ArgumentError("M должно быть >= 0"))
    M < 1 && return 0.0
    return 1 - (1 - 1 / N)^(M - 1)
end

"""
    expected_success_exact(M, N) -> Float64

Ожидаемое число устройств, чья преамбула — singleton (не выбрана никем другим),
то есть ожидаемое число успешных доступов за occasion:

    E[Success](M,N) = M · (1 − 1/N)^(M−1)
"""
function expected_success_exact(M::Integer, N::Integer)
    N >= 1 || throw(ArgumentError("N должно быть >= 1"))
    M >= 0 || throw(ArgumentError("M должно быть >= 0"))
    M < 1 && return 0.0
    return M * (1 - 1 / N)^(M - 1)
end

"""
    expected_used_preambles_exact(M, N) -> Float64

Ожидаемое число преамбул, использованных хотя бы одним устройством:

    E[Used](M,N) = N · (1 − (1 − 1/N)^M)
"""
function expected_used_preambles_exact(M::Integer, N::Integer)
    N >= 1 || throw(ArgumentError("N должно быть >= 1"))
    M >= 0 || throw(ArgumentError("M должно быть >= 0"))
    return N * (1 - (1 - 1 / N)^M)
end

"""
    expected_collided_preambles_exact(M, N) -> Float64

Ожидаемое число преамбул, занятых двумя и более устройствами одновременно:

    E[CollidedPreambles](M,N) = N · (1 − (1−1/N)^M − (M/N)·(1−1/N)^(M−1))
"""
function expected_collided_preambles_exact(M::Integer, N::Integer)
    N >= 1 || throw(ArgumentError("N должно быть >= 1"))
    M >= 0 || throw(ArgumentError("M должно быть >= 0"))
    M < 1 && return 0.0
    return N * (1 - (1 - 1 / N)^M - (M / N) * (1 - 1 / N)^(M - 1))
end

# ----------------------------------------------------------------------------
# Пуассоновское приближение (N,M большие, ρ=M/N фиксировано) — throughput
# классической slotted ALOHA.
# ----------------------------------------------------------------------------

"""
    throughput_slotted_aloha(ρ) -> Float64

Доля преамбул-"синглтонов" (успешных) при пуассоновском приближении с нагрузкой
`ρ = M/N`: `S(ρ) = ρ·e^(−ρ)`. Максимум `S_max = 1/e ≈ 0.368` при `ρ=1` —
классический результат теории slotted ALOHA, здесь применённый к NPRACH.
"""
throughput_slotted_aloha(ρ::Real) = ρ * exp(-ρ)

"""
    p_empty_poisson(ρ) -> Float64

Доля пустых преамбул при пуассоновском приближении: `P(k=0) = e^(−ρ)`.
"""
p_empty_poisson(ρ::Real) = exp(-ρ)

"""
    p_collision_poisson(ρ) -> Float64

Доля преамбул с коллизией (≥2 устройств) при пуассоновском приближении:
`P(коллизия) = 1 − (1+ρ)·e^(−ρ)`.
"""
p_collision_poisson(ρ::Real) = 1 - (1 + ρ) * exp(-ρ)

# ----------------------------------------------------------------------------
# Erlang B — аналитическая сверка блокировки DT-фазы при dropOnDtFull=true.
# ----------------------------------------------------------------------------

"""
    erlang_b(c, A) -> Float64

Вероятность блокировки (потери) в системе с `c` серверами и предложенной
нагрузкой `A` Эрланг (формула Эрланга B), вычисленная численно устойчивой
рекурсией `B(0,A)=1`, `B(k,A) = A·B(k−1,A) / (k + A·B(k−1,A))`.
"""
function erlang_b(c::Integer, A::Real)
    c >= 0 || throw(ArgumentError("c должен быть >= 0"))
    A >= 0 || throw(ArgumentError("A должен быть >= 0"))
    B = 1.0
    for k in 1:c
        B = (A * B) / (k + A * B)
    end
    return B
end
