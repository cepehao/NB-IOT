function manifest=runStaticSweep(options)
%RUNSTATICSWEEP Run or resume cases without replacing accepted result bundles.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root); addpath(fullfile(root,'experiments')); setupProject();
if nargin<1, options=struct(); end
options=defaults(options,struct('counts',[100 500 1000 2500 5000], ...
    'burstDurations',[10 100 500],'realizationIds',0:2, ...
    'calibrationFile',fullfile(root,'results','nprach-calibration.mat'), ...
    'outputFolder',fullfile(root,'results','sweep'),'resume',true, ...
    'runExperimentFcn',[]));
if ~isfolder(options.outputFolder), mkdir(options.outputFolder); end
calibrationSha256=hashFile(options.calibrationFile);
sources=optimizationSourceManifest(root);
sourceSha256=sources.sha256;
environment=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer, ...
    'validatedInMatlab',false,'sourceProfile','static-v1');
rows={};
for count=options.counts
    for duration=options.burstDurations
        burstFolder=fullfile(options.outputFolder,sprintf('burst_%04dms',duration));
        if ~isfolder(burstFolder), mkdir(burstFolder); end
        for id=options.realizationIds
            caseKey=sprintf('static-v1_n%04d_d%04d_r%04d',count,duration,id);
            caseFolder=fullfile(burstFolder,caseKey);
            if ~isfolder(caseFolder), mkdir(caseFolder); end
            cfg=nbiot.config.defaultConfig(); cfg.simulation.numUE=count;
            cfg.simulation.realizationId=id; cfg.traffic.burstDurationTicks=duration;
            cfg.logging.outputFolder=caseFolder;
            cfg=nbiot.experiments.loadCalibration(cfg,options.calibrationFile);
            metadata=struct('caseKey',caseKey, ...
                'configSha256',nbiot.results.configSha256(cfg), ...
                'sourceSha256',sourceSha256,'calibrationSha256',calibrationSha256, ...
                'environment',environment);

            [accepted,acceptedFolder,acceptedMarker]=findAcceptedCase( ...
                caseFolder,metadata,options.resume);
            if accepted
                status=char(string(acceptedMarker.status));
                elapsedSeconds=double(acceptedMarker.elapsedSeconds);
                resultFile=fullfile(acceptedFolder,char(string(acceptedMarker.resultFile)));
            else
                [result,attemptFolder]=runCase(cfg,caseFolder,metadata,options.runExperimentFcn);
                status=char(string(result.status));
                elapsedSeconds=elapsed(result);
                marker=jsondecode(fileread(fullfile(attemptFolder,'case-complete.json')));
                resultFile=fullfile(attemptFolder,char(string(marker.resultFile)));
            end
            rows(end+1,:)={count,duration,id,status,elapsedSeconds,resultFile, ...
                caseKey,metadata.configSha256,sourceSha256,calibrationSha256}; %#ok<AGROW>
            updateManifest(options.outputFolder,rows);
            if strcmp(status,'failed')
                warning('nbiot:experiments:Failed','Stopped at %s.',resultFile);
                manifest=makeManifest(rows); return
            end
        end
    end
end
manifest=makeManifest(rows);
end

function [accepted,folder,marker]=findAcceptedCase(caseFolder,expected,resume)
accepted=false; folder=''; marker=struct();
if ~resume || ~isfolder(caseFolder), return; end
attempts=dir(fullfile(caseFolder,'run-*'));
attempts=attempts([attempts.isdir]);
for k=numel(attempts):-1:1
    candidate=fullfile(attempts(k).folder,attempts(k).name);
    report=nbiot.results.verifyCase(candidate,expected);
    if report.passed && strcmp(report.status,'completed')
        marker=jsondecode(fileread(fullfile(candidate,'case-complete.json')));
        folder=candidate; accepted=true; return
    end
end
end

function [result,finalFolder]=runCase(cfg,caseFolder,metadata,runner)
id=char(java.util.UUID.randomUUID());
stage=fullfile(caseFolder,['.staging-' id]);
finalFolder=fullfile(caseFolder,['run-' id]);
if isfolder(stage) || isfolder(finalFolder)
    error('nbiot:experiments:AttemptCollision','Generated attempt directory already exists.');
end
[ok,message]=mkdir(stage);
if ~ok, error('nbiot:experiments:Stage','Cannot create case staging directory: %s',message); end
if isempty(runner)
    result=nbiot.runExperiment(cfg);
else
    result=runner(cfg);
end
nbiot.results.saveResult(result,stage,metadata);
[ok,message]=movefile(stage,finalFolder);
if ~ok, error('nbiot:experiments:Commit','Cannot commit case directory: %s',message); end
end

function updateManifest(folder,rows)
manifest=makeManifest(rows); destination=fullfile(folder,'manifest.csv');
temporary=[tempname(folder) '.csv']; cleanup=onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
writetable(manifest,temporary);
[ok,message]=movefile(temporary,destination,'f');
if ~ok, error('nbiot:experiments:Manifest','Cannot atomically update manifest: %s',message); end
end

function manifest=makeManifest(rows)
manifest=cell2table(rows,'VariableNames',{'numUE','burstDurationTicks', ...
    'realizationId','status','elapsedSeconds','resultFile','caseKey', ...
    'configSha256','sourceSha256','calibrationSha256'});
end

function value=elapsed(result)
value=0;
if isfield(result,'profiling') && isfield(result.profiling,'elapsedSeconds')
    value=double(result.profiling.elapsedSeconds);
end
end

function hex=hashFile(path)
fid=fopen(path,'rb');
if fid<0, error('nbiot:experiments:Calibration','Cannot read calibration file %s.',path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
digest=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,4*1024*1024,'*uint8');
    if isempty(bytes), break; end
    digest.update(typecast(bytes(:),'int8'));
end
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function value=defaults(value,base)
names=fieldnames(base);
for k=1:numel(names)
    if ~isfield(value,names{k}), value.(names{k})=base.(names{k}); end
end
end

function removeTemporary(path)
if isfile(path), delete(path); end
end
