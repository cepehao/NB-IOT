function result=runExperiment(cfg,scenario,execution,controllerOptions)
%RUNEXPERIMENT Construct, run and return a waveform experiment.
% Пояснение (рус.): самый простой способ запустить опыт из кода:
%   cfg = nbiot.config.defaultConfig(); cfg.simulation.numUE = 5;
%   cfg = nbiot.experiments.loadCalibration(cfg,'results/nprach-calibration.mat');
%   result = nbiot.runExperiment(cfg);
% Создаёт симулятор, проходит все тики и возвращает структуру result.
if nargin<1, cfg=nbiot.config.defaultConfig(); end
if nargin<2, scenario=[]; end
if nargin<3, execution=struct(); end
if nargin<4, controllerOptions=struct(); end
sim=nbiot.NBIoTSimulator(cfg,scenario,execution,controllerOptions);
sim.run(); result=sim.result();
end
