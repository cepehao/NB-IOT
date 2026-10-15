classdef TestSimulationCheckpoint < matlab.unittest.TestCase
    methods (Test)
        function checkpointRestoresAcrossNewMatlabProcessAtWindowBoundary(t)
            [cfg,scenario,identity,execution]=checkpointFixture();
            checkpointFolder=tempname; mkdir(checkpointFolder);
            cleanup=onCleanup(@() removeFolder(checkpointFolder)); %#ok<NASGU>

            direct=nbiot.NBIoTSimulator(cfg,scenario,execution);
            direct.run(); directResult=direct.result();
            t.verifyTrue(any([directResult.truthLog.tick]<500));
            t.verifyTrue(any([directResult.truthLog.tick]>500));
            t.verifyEqual(sum(directResult.dataset.observations.endTick==500),1);
            t.verifyGreaterThan(directResult.kpiSummary.delivered,0);

            inputPath=fullfile(checkpointFolder,'resume-input.mat');
            writerPath=fullfile(checkpointFolder,'writer-output.mat');
            outputPath=fullfile(checkpointFolder,'resume-output.mat');
            save(inputPath,'cfg','scenario','identity','execution','-v7.3');
            matlabExe=fullfile(matlabroot,'bin','matlab.exe');
            root=fileparts(fileparts(mfilename('fullpath')));
            writerBatch=sprintf(['addpath(''%s''); setupProject(); ' ...
                'inputData=load(''%s'',''cfg'',''scenario'',''identity'',''execution''); ' ...
                'split=nbiot.NBIoTSimulator(inputData.cfg,inputData.scenario,inputData.execution); ' ...
                'split.run(499); state=split.exportCheckpointState(); partial=split.result(); ' ...
                'checkpointPath=nbiot.experiments.saveCheckpoint(split,''%s'',inputData.identity); ' ...
                'writerProcessId=feature(''getpid''); writerCurrentTick=state.currentTick; ' ...
                'writerNextTick=state.nextTick; pendingCount=state.receiveQueue.count(); ' ...
                'pendingNextTick=state.receiveQueue.nextTick(); ' ...
                'decodeBefore=any(strcmp({partial.observedLog.kind},''phy_decode'')); ' ...
                'save(''%s'',''checkpointPath'',''writerProcessId'',''writerCurrentTick'',''writerNextTick'',''pendingCount'',''pendingNextTick'',''decodeBefore'');'], ...
                matlabString(root),matlabString(inputPath), ...
                matlabString(checkpointFolder),matlabString(writerPath));
            [writerExit,writerOutput]=system(sprintf('"%s" -batch "%s"',matlabExe,writerBatch));
            if writerExit~=0
                error('TestSimulationCheckpoint:WriterMatlab', ...
                    'Checkpoint writer MATLAB exited with code %d: %s',writerExit,writerOutput);
            end
            writer=load(writerPath);
            t.verifyNotEqual(writer.writerProcessId,feature('getpid'));
            t.verifyEqual(writer.writerCurrentTick,499);
            t.verifyEqual(writer.writerNextTick,500);
            t.verifyGreaterThan(writer.pendingCount,0);
            t.verifyGreaterThanOrEqual(writer.pendingNextTick,writer.writerNextTick);
            t.verifyLessThanOrEqual(writer.pendingNextTick-writer.writerNextTick,25);
            t.verifyTrue(writer.decodeBefore);

            readerBatch=sprintf(['addpath(''%s''); setupProject(); ' ...
                'inputData=load(''%s'',''identity'',''execution''); ' ...
                '[resumed,checkpointInfo]=nbiot.experiments.loadCheckpoint(''%s'',inputData.identity,inputData.execution); ' ...
                'resumed.run(); resumedResult=resumed.result(); ' ...
                'resumeProcessId=feature(''getpid''); ' ...
                'save(''%s'',''resumedResult'',''checkpointInfo'',''resumeProcessId'',''-v7.3'');'], ...
                matlabString(root),matlabString(inputPath), ...
                matlabString(checkpointFolder),matlabString(outputPath));
            [exitCode,output]=system(sprintf('"%s" -batch "%s"',matlabExe,readerBatch));
            if exitCode~=0
                error('TestSimulationCheckpoint:ReaderMatlab', ...
                    'Checkpoint reader MATLAB exited with code %d: %s',exitCode,output);
            end
            restored=load(outputPath,'resumedResult','checkpointInfo','resumeProcessId');

            t.verifyNotEqual(restored.resumeProcessId,feature('getpid'));
            t.verifyNotEqual(restored.resumeProcessId,writer.writerProcessId);
            t.verifyEqual(restored.checkpointInfo.checkpointTick,499);
            t.verifyFalse(restored.checkpointInfo.fallbackUsed);
            t.verifyTrue(restored.checkpointInfo.graphLinksValidated);
            t.verifyEqual(scientificProjection(restored.resumedResult), ...
                scientificProjection(directResult));
            t.verifyTrue(isfile(writer.checkpointPath));
        end

        function corruptNewestCheckpointFallsBackAndRecordsLostTicks(t)
            [cfg,scenario,identity,execution]=checkpointFixture(); %#ok<ASGLU>
            checkpointFolder=tempname; mkdir(checkpointFolder);
            cleanup=onCleanup(@() removeFolder(checkpointFolder)); %#ok<NASGU>
            sim=nbiot.NBIoTSimulator(cfg,scenario,execution);
            sim.run(99); first=nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            sim.run(199); nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            sim.run(299); nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            manifest=jsondecode(fileread(fullfile(checkpointFolder,'checkpoint-manifest.json')));
            t.verifyEqual(numel(manifest.checkpoints),2);
            t.verifyFalse(isfile(first));
            newest=manifest.checkpoints(end);
            newestPath=fullfile(checkpointFolder,newest.file);
            fid=fopen(newestPath,'w'); fwrite(fid,uint8('corrupt-checkpoint'),'uint8'); fclose(fid);

            [restored,info]=nbiot.experiments.loadCheckpoint( ...
                checkpointFolder,identity,execution);

            t.verifyEqual(restored.currentTick,199);
            t.verifyTrue(info.fallbackUsed);
            t.verifyEqual(info.newestCheckpointTick,299);
            t.verifyEqual(info.lostTicks,100);
            t.verifyTrue(isfile(fullfile(checkpointFolder,'checkpoint-recovery.json')));
            recovery=jsondecode(fileread(fullfile(checkpointFolder,'checkpoint-recovery.json')));
            t.verifyEqual(recovery.lostTicks,100);
            t.verifyEqual(recovery.usedTick,199);
        end

        function changedCalibrationIdentityIsRejected(t)
            [cfg,scenario,identity,execution]=checkpointFixture(); %#ok<ASGLU>
            checkpointFolder=tempname; mkdir(checkpointFolder);
            cleanup=onCleanup(@() removeFolder(checkpointFolder)); %#ok<NASGU>
            sim=nbiot.NBIoTSimulator(cfg,scenario,execution); sim.run(99);
            nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            changed=identity; changed.calibrationSha256=repmat('0',1,64);

            t.verifyError(@() nbiot.experiments.loadCheckpoint( ...
                checkpointFolder,changed,execution), ...
                'nbiot:experiments:CheckpointIdentity');
        end

        function changedSourceIdentityIsRejected(t)
            [cfg,scenario,identity,execution]=checkpointFixture(); %#ok<ASGLU>
            checkpointFolder=tempname; mkdir(checkpointFolder);
            cleanup=onCleanup(@() removeFolder(checkpointFolder)); %#ok<NASGU>
            sim=nbiot.NBIoTSimulator(cfg,scenario,execution); sim.run(99);
            nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            changed=identity; changed.sourceSha256=repmat('f',1,64);

            t.verifyError(@() nbiot.experiments.loadCheckpoint( ...
                checkpointFolder,changed,execution), ...
                'nbiot:experiments:CheckpointIdentity');
        end

        function failedManifestReplacementKeepsPreviousCheckpoint(t)
            [cfg,scenario,identity,execution]=checkpointFixture(); %#ok<ASGLU>
            checkpointFolder=tempname; mkdir(checkpointFolder);
            cleanup=onCleanup(@() removeFolder(checkpointFolder)); %#ok<NASGU>
            sim=nbiot.NBIoTSimulator(cfg,scenario,execution); sim.run(99);
            nbiot.experiments.saveCheckpoint(sim,checkpointFolder,identity);
            manifestPath=fullfile(checkpointFolder,'checkpoint-manifest.json');
            previousManifest=fileread(manifestPath);
            sim.run(199);
            lock=System.IO.FileStream(manifestPath,System.IO.FileMode.Open, ...
                System.IO.FileAccess.Read,System.IO.FileShare.Read);
            releaseLock=onCleanup(@() lock.Dispose()); %#ok<NASGU>

            t.verifyError(@() nbiot.experiments.saveCheckpoint( ...
                sim,checkpointFolder,identity), ...
                'nbiot:experiments:CheckpointWrite');
            clear releaseLock
            t.verifyEqual(fileread(manifestPath),previousManifest);
            files=dir(fullfile(checkpointFolder,'checkpoint-tick-*.mat'));
            t.verifyEqual(numel(files),1);
            [restored,info]=nbiot.experiments.loadCheckpoint( ...
                checkpointFolder,identity,execution);
            t.verifyEqual(restored.currentTick,99);
            t.verifyFalse(info.fallbackUsed);
        end
    end
end

function [cfg,scenario,identity,execution]=checkpointFixture()
root=fileparts(fileparts(mfilename('fullpath')));
cfg=nbiot.config.defaultConfig();
cfg.simulation.numUE=1; cfg.simulation.durationTicks=1500;
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

function value=scientificProjection(value)
value.profiling.elapsedSeconds=0;
runtimeOnly={'simulation_started','simulation_resumed', ...
    'checkpoint_saved','checkpoint_restored'};
value.lifecycleLog=value.lifecycleLog( ...
    ~ismember({value.lifecycleLog.kind},runtimeOnly));
end

function value=matlabString(value)
value=strrep(char(value),'''','''''');
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
