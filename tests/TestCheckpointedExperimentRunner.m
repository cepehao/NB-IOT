classdef TestCheckpointedExperimentRunner < matlab.unittest.TestCase
    methods (Test)
        function freshRunStartsWithCheckpointAndCompletes(t)
            [cfg,scenario,identity,execution]=runnerFixture();
            folder=tempname; mkdir(folder);
            cleanup=onCleanup(@() removeFolder(folder)); %#ok<NASGU>
            options=struct('folder',folder,'identity',identity, ...
                'intervalSeconds',600,'resume',false);

            [result,info]=nbiot.experiments.runCheckpointedExperiment( ...
                cfg,scenario,execution,struct(),options);

            t.verifyEqual(result.status,'completed');
            t.verifyEqual(info.status,'completed');
            t.verifyEqual(info.checkpointCount,1);
            t.verifyEqual(numel(info.checkpointPaths),1);
            t.verifyTrue(isfile(fullfile(folder,'checkpoint-manifest.json')));
            t.verifyEqual(info.resumeInfo.checkpointTick,0);
        end
    end
end

function [cfg,scenario,identity,execution]=runnerFixture()
root=fileparts(fileparts(mfilename('fullpath')));
cfg=nbiot.config.defaultConfig();
cfg.simulation.numUE=1; cfg.simulation.durationTicks=2;
cfg.cell.radiusM=20; cfg.cell.indoorFraction=0;
cfg.channel.shadowOutdoorDb=0; cfg.channel.shadowIndoorDb=0;
cfg.channel.cfoSigmaHz=0; cfg.channel.syncLimitSeconds=0;
cfg.traffic.kind='burst'; cfg.traffic.packetBytes=200;
cfg.traffic.burstStartTick=0; cfg.traffic.burstDurationTicks=1;
cfg.policy.name='Static'; cfg.policy.windowTicks=500; cfg.dataset.windowTicks=500;
cfg=nbiot.experiments.loadCalibration(cfg, ...
    fullfile(root,'results','nprach-calibration.mat'));
scenario=nbiot.scenario.buildScenario(cfg);
identity=nbiot.experiments.runtimeManifest(cfg,struct('scenario',scenario));
execution=struct();
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
