function meta=runStaticCase(cfg,caseFolder,provenance,runner)
%RUNSTATICCASE Execute and commit one independent case in its own folder.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(root); addpath(fullfile(root,'src')); addpath(fullfile(root,'experiments')); setupProject();
if nargin<3 || isempty(provenance), provenance=defaultProvenance(cfg,root); end
if nargin<4, runner=[]; end
cfg.logging.outputFolder=caseFolder;
if ~isfolder(caseFolder), mkdir(caseFolder); end
id=char(java.util.UUID.randomUUID());
staging=fullfile(caseFolder,['.staging-' id]);
attempt=fullfile(caseFolder,['run-' id]);
if isfolder(staging) || isfolder(attempt)
    error('nbiot:experiments:AttemptCollision','Generated case attempt already exists.');
end
[ok,message]=mkdir(staging);
if ~ok, error('nbiot:experiments:Stage','Cannot create case staging directory: %s',message); end
if isempty(runner)
    result=nbiot.runExperiment(cfg);
else
    result=runner(cfg);
end
nbiot.results.saveResult(result,staging,provenance);
[ok,message]=movefile(staging,attempt);
if ~ok, error('nbiot:experiments:Commit','Cannot commit case folder: %s',message); end
marker=jsondecode(fileread(fullfile(attempt,'case-complete.json')));
meta=struct('caseKey',char(string(marker.caseKey)), ...
    'status',char(string(marker.status)),'elapsedSeconds',double(marker.elapsedSeconds), ...
    'caseFolder',caseFolder,'attemptFolder',attempt, ...
    'resultFile',fullfile(attempt,char(string(marker.resultFile))), ...
    'configSha256',char(string(marker.configSha256)), ...
    'sourceSha256',char(string(marker.sourceSha256)), ...
    'calibrationSha256',char(string(marker.calibrationSha256)), ...
    'environment',marker.environment,'files',marker.files);
end

function metadata=defaultProvenance(cfg,root)
sources=optimizationSourceManifest(root);
if isfield(cfg,'calibrationReport')
    calibration=unicode2native(jsonencode(cfg.calibrationReport),'UTF-8');
else
    calibration=unicode2native(jsonencode(cfg.phy),'UTF-8');
end
metadata=struct('caseKey',sprintf('static-v1_n%04d_d%04d_r%04d', ...
    cfg.simulation.numUE,cfg.traffic.burstDurationTicks,cfg.simulation.realizationId), ...
    'configSha256',nbiot.results.configSha256(cfg), ...
    'sourceSha256',sources.sha256,'calibrationSha256',hashBytes(calibration), ...
    'environment',environment());
end

function value=environment()
value=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer, ...
    'validatedInMatlab',false,'sourceProfile','static-v1');
end

function hex=hashBytes(bytes)
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)),'int8'));
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
