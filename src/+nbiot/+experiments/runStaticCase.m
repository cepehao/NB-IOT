function meta=runStaticCase(cfg,caseFolder,provenance,runner,runtimeOptions)
%RUNSTATICCASE Execute and commit one independent case in its own folder.
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(root); addpath(fullfile(root,'src')); addpath(fullfile(root,'experiments')); setupProject();
if nargin<4, runner=[]; end
if nargin<5, runtimeOptions=struct(); end
runtimeOptions.projectRoot=root; runtimeOptions.runner=runner;
if nargin<3 || isempty(provenance)
    provenance=nbiot.experiments.runtimeManifest(cfg,runtimeOptions);
elseif isfield(provenance,'runtimeVersion')
    current=nbiot.experiments.runtimeManifest(cfg,runtimeOptions);
    names=fieldnames(current);
    for k=1:numel(names)
        if ~isfield(provenance,names{k}) || ~isequaln(provenance.(names{k}),current.(names{k}))
            error('nbiot:experiments:RuntimeIdentity','Supplied runtime identity differs in %s.',names{k});
        end
    end
end
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
    scenario=[];
    if isfield(runtimeOptions,'scenario'), scenario=runtimeOptions.scenario; end
    result=nbiot.runExperiment(cfg,scenario);
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
if isfield(marker,'runtimeVersion')
    names={'runtimeVersion','resultSchemaVersion','canonicalConfigSha256', ...
        'modelSha256','policySha256','inputSha256','runnerSha256'};
    for k=1:numel(names), meta.(names{k})=marker.(names{k}); end
end
end
