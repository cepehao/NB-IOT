# Заготовка интеграции с MATLAB LTE Toolbox через MATLAB.jl (пакет ENGEE,
# см. /julia/MATLAB/readme.html) — НЕ реализуется в v0.1 (Модуль 2 сейчас
# событийный, без синтеза IQ-сигналов). Контракт фиксируется здесь, чтобы
# будущий Модуль 3 (генерация датасета для ML на реальных NPRACH-сигналах)
# мог передавать NPRACHConfig напрямую в lteNPRACH/lteNPRACHInfo без
# дублирования логики конфигурации (имена полей NPRACHConfig совпадают с
# MATLAB-структурой chs, см. Types.jl и docs/guideMatlab.md ~L4964-4975).
#
# Пример будущего использования (не реализовано):
#
#   using MATLAB
#   chs = to_mxstruct(cfg.nprach)
#   mat"addpath('/path/to/lte/toolbox')"
#   waveform, info = mxcall(:lteNPRACH, 2, ue, chs)

"""
    to_mxstruct(cfg::NPRACHConfig) -> Dict{String,Any}

Конвертирует `NPRACHConfig` в `Dict{String,Any}`, пригодный для передачи в
MATLAB как struct через `MATLAB.mxarray(::Dict)` (пакет `MATLAB.jl`, см.
docs ENGEE `/julia/MATLAB/readme.html`, раздел "Создание MATLAB переменных").
Ключи и значения совпадают по имени и семантике с полями `chs`, ожидаемыми
`lteNPRACH`/`lteNPRACHInfo` (docs/guideMatlab.md ~L4964-4975).

НЕ РЕАЛИЗОВАНО в v0.1 — задел под Модуль 3 (физический уровень/датасет для ML).
Сигнатура и контракт зафиксированы намеренно, чтобы `NPRACHConfig` не пришлось
переделывать при подключении MATLAB-интеропа.
"""
function to_mxstruct(cfg::NPRACHConfig)
    error("to_mxstruct не реализован в v0.1 — физический уровень (MATLAB lteNPRACH) " *
          "запланирован для Модуля 3. См. комментарий в src/MatlabBridge.jl.")
end
