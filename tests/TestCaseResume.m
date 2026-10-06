classdef TestCaseResume < matlab.unittest.TestCase
    methods (Test)
        function completeBundlePassesReadback(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyTrue(report.passed,evalc('disp(report.checks)'));
            t.verifyEmpty(report.errors);
        end

        function legacySaveSignatureStillWritesAllExports(t)
            [folder,result]=makeFixture(t);
            destination=nbiot.results.saveResult(result,folder);

            t.verifyTrue(isfile(destination));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_ue.csv')));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_kpi.csv')));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_observations.csv')));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_targets.csv')));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_resources.csv')));
            t.verifyTrue(isfile(fullfile(folder,'static-v1_n1_r0007_split.csv')));
            t.verifyFalse(isfile(fullfile(folder,'case-complete.json')));
        end

        function matWithoutCompletionMarkerIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            save(fullfile(folder,'static-v1_n1_r0007.mat'),'result');

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
            t.verifyFalse(isfile(fullfile(folder,'case-complete.json')));
        end

        function missingCsvIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            delete(fullfile(folder,'static-v1_n1_r0007_ue.csv'));

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
            t.verifyNotEmpty(report.errors);
        end

        function changedFileHashIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            markerPath=fullfile(folder,'case-complete.json');
            marker=jsondecode(fileread(markerPath));
            marker.files(1).sha256=repmat('0',1,64);
            writeJson(markerPath,marker);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
        end

        function missingTableMetadataIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            markerPath=fullfile(folder,'case-complete.json');
            marker=jsondecode(fileread(markerPath));
            marker.tables(end)=[];
            writeJson(markerPath,marker);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
        end

        function duplicateTableMetadataIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            markerPath=fullfile(folder,'case-complete.json');
            marker=jsondecode(fileread(markerPath));
            marker.tables(end)=marker.tables(1);
            writeJson(markerPath,marker);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
        end

        function differentReceiverVersionIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            expected=metadata;
            expected.environment.lteVersion='different receiver version';

            report=nbiot.results.verifyCase(folder,expected);

            t.verifyFalse(report.passed);
        end

        function differentSourceVersionIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            expected=metadata; expected.sourceSha256=repmat('c',1,64);

            report=nbiot.results.verifyCase(folder,expected);

            t.verifyFalse(report.passed);
        end

        function corruptCsvIsRejected(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            path=fullfile(folder,'static-v1_n1_r0007_kpi.csv');
            fid=fopen(path,'ab'); fwrite(fid,uint8('corruption'),'uint8'); fclose(fid);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
        end

        function corruptMatReturnsRejectedReport(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            path=fullfile(folder,'static-v1_n1_r0007.mat');
            fid=fopen(path,'wb'); fwrite(fid,uint8('not a MAT file'),'uint8'); fclose(fid);

            report=nbiot.results.verifyCase(folder,metadata);

            t.verifyFalse(report.passed);
            t.verifyNotEmpty(report.errors);
        end

        function duplicateCaseKeyCannotOverwriteAcceptedFiles(t)
            [folder,result,metadata]=makeFixture(t);
            nbiot.results.saveResult(result,folder,metadata);
            acceptedHash=fileHash(fullfile(folder,'static-v1_n1_r0007.mat'));

            t.verifyError(@() nbiot.results.saveResult(result,folder,metadata), ...
                'nbiot:results:DuplicateCase');
            t.verifyEqual(fileHash(fullfile(folder,'static-v1_n1_r0007.mat')),acceptedHash);
        end

        function sweepResumesAndKeepsDamagedAttemptForDiagnosis(t)
            folder=tempname; mkdir(folder); t.addTeardown(@() removeFixture(folder));
            calibrationFile=fullfile(folder,'calibration.mat'); writeCalibration(calibrationFile);
            counterFile=fullfile(folder,'runs.txt'); runner=countingRunner(counterFile);
            options=struct('counts',1,'burstDurations',100,'realizationIds',7, ...
                'calibrationFile',calibrationFile,'outputFolder',fullfile(folder,'sweep'), ...
                'resume',true,'runExperimentFcn',runner);

            first=runStaticSweep(options);
            firstResult=first.resultFile{1};
            second=runStaticSweep(options);

            t.verifyEqual(countRuns(counterFile),1);
            t.verifyEqual(second.resultFile{1},firstResult);
            t.verifyTrue(isfile(firstResult));

            firstCase=fullfile(fileparts(firstResult));
            csv=fullfile(firstCase,'static-v1_n1_r0007_ue.csv');
            fid=fopen(csv,'ab'); fwrite(fid,uint8('tamper'),'uint8'); fclose(fid);
            third=runStaticSweep(options);

            t.verifyEqual(countRuns(counterFile),2);
            t.verifyNotEqual(third.resultFile{1},firstResult);
            t.verifyTrue(isfile(firstResult));
            t.verifyTrue(isfile(third.resultFile{1}));
        end
    end
end

function [folder,result,metadata]=makeFixture(t)
folder=tempname; mkdir(folder); t.addTeardown(@() removeFixture(folder));
environment=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer);
cfg=struct('profileVersion','static-v1', ...
    'simulation',struct('numUE',1,'realizationId',7,'seed',42), ...
    'traffic',struct('packetBytes',200),'logging',struct('outputFolder',folder));
ueSummary=table(1,0,0,0,0,'VariableNames', ...
    {'ueId','created','delivered','dropped','unfinished'});
kpiTimeSeries=table(0,0,0,'VariableNames',{'windowId','startTick','endTick'});
observations=table(0,0,'VariableNames',{'realizationId','windowId'});
targets=table(0,0,'VariableNames',{'realizationId','windowId'});
split=table("train",1,'VariableNames',{'split','rows'});
resourceUsage=table("cpu",0,'VariableNames',{'resource','units'});
result=struct('config',cfg,'status','completed','environment',environment, ...
    'kpiSummary',struct('created',0,'delivered',0,'dropped',0,'unfinished',0, ...
    'raStarted',0,'raSuccess',0,'raFailed',0,'raUnfinished',0), ...
    'ueSummary',ueSummary,'kpiTimeSeries',kpiTimeSeries,'resourceUsage',resourceUsage, ...
    'dataset',struct('observations',observations,'targets',targets,'manifest',split), ...
    'profiling',struct('elapsedSeconds',0.125));
metadata=struct('caseKey','static-v1_n0001_d0100_r0007', ...
    'configSha256',configHash(cfg),'sourceSha256',repmat('b',1,64), ...
    'calibrationSha256',repmat('a',1,64),'environment',environment);
end

function hex=configHash(cfg)
cfg.logging.outputFolder='<case-output>';
bytes=unicode2native(jsonencode(cfg),'UTF-8');
hex=sha256(bytes);
end

function hex=fileHash(path)
fid=fopen(path,'rb'); bytes=fread(fid,Inf,'*uint8'); fclose(fid); hex=sha256(bytes);
end

function hex=sha256(bytes)
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)),'int8'));
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function writeJson(path,value)
fid=fopen(path,'w'); fwrite(fid,jsonencode(value),'char'); fclose(fid);
end

function removeFixture(folder)
if isfolder(folder), rmdir(folder,'s'); end
end

function writeCalibration(path)
cfg=nbiot.config.defaultConfig();
profile=struct('version',cfg.profileVersion,'cellId',cfg.phy.cellId, ...
    'format',cfg.ra.format,'periodTicks',cfg.ra.periodTicks, ...
    'numSubcarriers',cfg.ra.numSubcarriers,'repetitions',cfg.ra.repetitions, ...
    'sampleRateHz',cfg.simulation.sampleRateHz, ...
    'fractionalFilterLength',cfg.channel.fractionalFilterLength,...
    'receiverRevision',nbiot.phy.nprach.receiverRevision(),'cfoLimitHz',cfg.channel.cfoLimitHz);
report=struct('accepted',true,'threshold',1,'profile',profile, ...
    'cfoGridHz',cfg.phy.nprachCfoGridHz);
save(path,'report');
end

function runner=countingRunner(path)
runner=@runOnce;
    function result=runOnce(cfg)
        fid=fopen(path,'a'); fprintf(fid,'run\n'); fclose(fid);
        result=mockResult(cfg);
    end
end

function result=mockResult(cfg)
environment=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer, ...
    'validatedInMatlab',false,'sourceProfile','static-v1');
ids=(1:cfg.simulation.numUE).'; zerosByUe=zeros(cfg.simulation.numUE,1);
ueSummary=table(ids,zerosByUe,zerosByUe,zerosByUe,zerosByUe, ...
    'VariableNames',{'ueId','created','delivered','dropped','unfinished'});
kpiTimeSeries=table(0,0,0,'VariableNames',{'windowId','startTick','endTick'});
observations=table(0,0,'VariableNames',{'realizationId','windowId'});
targets=table(0,0,'VariableNames',{'realizationId','windowId'});
split=table("train",1,'VariableNames',{'split','rows'});
resourceUsage=table("cpu",0,'VariableNames',{'resource','units'});
result=struct('config',cfg,'status','completed','environment',environment, ...
    'kpiSummary',struct('created',0,'delivered',0,'dropped',0,'unfinished',0, ...
    'raStarted',0,'raSuccess',0,'raFailed',0,'raUnfinished',0), ...
    'ueSummary',ueSummary,'kpiTimeSeries',kpiTimeSeries,'resourceUsage',resourceUsage, ...
    'dataset',struct('observations',observations,'targets',targets,'manifest',split), ...
    'profiling',struct('elapsedSeconds',0.25));
end

function count=countRuns(path)
if ~isfile(path), count=0; return; end
textValue=fileread(path); count=numel(strfind(textValue,'run')); %#ok<STREMP>
end


