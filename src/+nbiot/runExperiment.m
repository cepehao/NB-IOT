function result=runExperiment(cfg,scenario)
%RUNEXPERIMENT Construct, run and return a waveform experiment.
if nargin<1, cfg=nbiot.config.defaultConfig(); end
if nargin<2, scenario=[]; end
sim=nbiot.NBIoTSimulator(cfg,scenario); sim.run(); result=sim.result();
end
