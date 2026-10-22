function [applied,reason]=applyAction(simulator,action)
%APPLYACTION Apply one validated runtime action without changing the base config.
% Пояснение (рус.): передать решение контроллера симулятору
% (NBIoTSimulator.applyRuntimeAction); исходные настройки cfg не меняются.
if ~isobject(simulator)||~ismethod(simulator,'applyRuntimeAction')
    applied=false; reason='unsupported-simulator'; return;
end
[applied,reason]=simulator.applyRuntimeAction(action);
end
