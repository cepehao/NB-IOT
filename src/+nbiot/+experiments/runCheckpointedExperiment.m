function [result,info]=runCheckpointedExperiment(cfg,scenario,execution,controllerOptions,checkpointOptions)
%RUNCHECKPOINTEDEXPERIMENT Run in step-sized portions and save recoverable state.
if nargin<2, scenario=[]; end
if nargin<3||isempty(execution), execution=struct(); end
if nargin<4||isempty(controllerOptions), controllerOptions=struct(); end
if nargin<5||isempty(checkpointOptions), checkpointOptions=struct(); end
if ~isstruct(checkpointOptions)||~isscalar(checkpointOptions)
    error('nbiot:experiments:CheckpointOptions','Checkpoint options must be a scalar structure.');
end
defaults=struct('folder','','identity',[],'intervalSeconds',600,'resume',false, ...
    'pauseRequestFile','','progressFile','','budgetLedgerFile','', ...
    'progressPhase','');
names=fieldnames(checkpointOptions);
if ~all(ismember(names,fieldnames(defaults)))
    error('nbiot:experiments:CheckpointOptions','Checkpoint options contain unsupported fields.');
end
for k=1:numel(names), defaults.(names{k})=checkpointOptions.(names{k}); end
checkpointOptions=defaults;
if ~(ischar(checkpointOptions.folder)||(isstring(checkpointOptions.folder)&&isscalar(checkpointOptions.folder)))|| ...
        isempty(char(checkpointOptions.folder))|| ...
        ~(ischar(checkpointOptions.pauseRequestFile)|| ...
        (isstring(checkpointOptions.pauseRequestFile)&&isscalar(checkpointOptions.pauseRequestFile)))|| ...
        ~(ischar(checkpointOptions.progressFile)|| ...
        (isstring(checkpointOptions.progressFile)&&isscalar(checkpointOptions.progressFile)))|| ...
        ~(ischar(checkpointOptions.budgetLedgerFile)|| ...
        (isstring(checkpointOptions.budgetLedgerFile)&&isscalar(checkpointOptions.budgetLedgerFile)))|| ...
        ~(ischar(checkpointOptions.progressPhase)|| ...
        (isstring(checkpointOptions.progressPhase)&&isscalar(checkpointOptions.progressPhase)))|| ...
        ~isnumeric(checkpointOptions.intervalSeconds)|| ...
        ~isscalar(checkpointOptions.intervalSeconds)|| ...
        ~isfinite(checkpointOptions.intervalSeconds)||checkpointOptions.intervalSeconds<=0|| ...
        ~(islogical(checkpointOptions.resume)&&isscalar(checkpointOptions.resume))
    error('nbiot:experiments:CheckpointOptions', ...
        'A checkpoint folder, positive interval and scalar logical resume flag are required.');
end
if isempty(scenario)
    sources=nbiot.randomness.RandomSources(cfg.simulation.seed,cfg.simulation.realizationId);
    scenario=nbiot.scenario.buildScenario(cfg,sources);
end
identity=checkpointOptions.identity;
if isempty(identity)
    if ~strcmp(char(string(cfg.policy.name)),'Static')||~isempty(fieldnames(controllerOptions))
        error('nbiot:experiments:CheckpointIdentity', ...
            'Adaptive or model-backed checkpoints require an explicit runtime identity.');
    end
    identity=nbiot.experiments.runtimeManifest(cfg,struct('scenario',scenario));
end
runClock=tic;
progressPhase=char(string(checkpointOptions.progressPhase));
if checkpointOptions.resume
    checkpointClock=tic;
    [sim,resumeInfo]=nbiot.experiments.loadCheckpoint( ...
        checkpointOptions.folder,identity,execution);
    initialCheckpoint='';
    checkpointOverheadSeconds=toc(checkpointClock);
else
    sim=nbiot.NBIoTSimulator(cfg,scenario,execution,controllerOptions);
    checkpointClock=tic;
    initialCheckpoint=nbiot.experiments.saveCheckpoint( ...
        sim,checkpointOptions.folder,identity);
    checkpointOverheadSeconds=toc(checkpointClock);
    resumeInfo=struct('fallbackUsed',false,'lostTicks',0, ...
        'checkpointTick',0,'graphLinksValidated',true);
end
checkpointPaths={};
if ~isempty(initialCheckpoint), checkpointPaths={initialCheckpoint}; end
lastCheckpointElapsed=0;
lastCheckpointPath=initialCheckpoint;
if isempty(lastCheckpointPath)&&checkpointOptions.resume&&isfield(resumeInfo,'checkpointPath')
    lastCheckpointPath=char(string(resumeInfo.checkpointPath));
end
lastProgressElapsed=-Inf;
budgetLedgerPath=char(string(checkpointOptions.budgetLedgerFile));
budgetBaseElapsed=0; budgetSeconds=Inf; budgetWarningWritten=false;
if ~isempty(budgetLedgerPath)
    budgetLedger=nbiot.experiments.loadVariant2BudgetLedger(budgetLedgerPath,false);
    budgetBaseElapsed=double(budgetLedger.elapsedSeconds);
    budgetSeconds=double(budgetLedger.budgetSeconds);
end
pauseRequested=false;
result=[];
initialState=sim.exportCheckpointState();
writeCheckpointProgress(checkpointOptions.progressFile,progressName(progressPhase,'running'), ...
    initialState.currentTick,lastCheckpointPath);
while ~any(strcmp(sim.status,{'completed','stopped','failed'}))
    state=sim.exportCheckpointState();
    sim.run(state.nextTick);
    elapsed=toc(runClock);
    if ~budgetWarningWritten&&budgetBaseElapsed+elapsed>=budgetSeconds&& ...
            ~isempty(budgetLedgerPath)
        budgetLedger=nbiot.experiments.loadVariant2BudgetLedger(budgetLedgerPath,false);
        message=sprintf(['Shared 57600-second budget threshold crossed during active case %s; ' ...
            'the current case continues and no later case will be admitted.'],identity.caseKey);
        exists=~isempty(budgetLedger.warnings)&& ...
            any(contains(string({budgetLedger.warnings.message}),identity.caseKey));
        if ~exists
            budgetLedger.warnings(end+1)=struct( ...
                'timestampUtc',char(datetime('now','TimeZone','UTC', ...
                'Format','yyyy-MM-dd HH:mm:ss.SSS')), ...
                'phase','stage-3-load-probe','elapsedSeconds',budgetBaseElapsed+elapsed, ...
                'message',message);
            nbiot.experiments.saveVariant2BudgetLedger(budgetLedgerPath,budgetLedger);
        end
        budgetWarningWritten=true;
    end
    terminal=any(strcmp(sim.status,{'completed','stopped','failed'}));
    if terminal
        result=sim.result(); progressTick=result.actualTick;
    else
        stateAfter=sim.exportCheckpointState(); progressTick=stateAfter.currentTick;
    end
    pausePath=char(checkpointOptions.pauseRequestFile);
    if ~any(strcmp(sim.status,{'completed','stopped','failed'}))&& ...
            ~isempty(pausePath)&&isfile(pausePath)
        checkpointClock=tic;
        lastCheckpointPath=nbiot.experiments.saveCheckpoint( ...
            sim,checkpointOptions.folder,identity);
        checkpointPaths{end+1}=lastCheckpointPath; %#ok<AGROW>
        checkpointOverheadSeconds=checkpointOverheadSeconds+toc(checkpointClock);
        lastCheckpointElapsed=elapsed;
        pauseRequested=true;
        writeCheckpointProgress(checkpointOptions.progressFile,progressName(progressPhase,'paused'), ...
            progressTick,lastCheckpointPath);
        break
    end
    if ~any(strcmp(sim.status,{'completed','stopped','failed'}))&& ...
            elapsed-lastCheckpointElapsed>=checkpointOptions.intervalSeconds
        checkpointClock=tic;
        lastCheckpointPath=nbiot.experiments.saveCheckpoint( ...
            sim,checkpointOptions.folder,identity);
        checkpointPaths{end+1}=lastCheckpointPath; %#ok<AGROW>
        checkpointOverheadSeconds=checkpointOverheadSeconds+toc(checkpointClock);
        lastCheckpointElapsed=elapsed;
        writeCheckpointProgress(checkpointOptions.progressFile,progressName(progressPhase,'running'), ...
            progressTick,lastCheckpointPath);
    elseif elapsed-lastProgressElapsed>=10
        writeCheckpointProgress(checkpointOptions.progressFile,progressName(progressPhase,'running'), ...
            progressTick,lastCheckpointPath);
        lastProgressElapsed=elapsed;
    end
end
if isempty(result), result=sim.result(); end
writeCheckpointProgress(checkpointOptions.progressFile,progressName(progressPhase,result.status), ...
    result.actualTick,lastCheckpointPath);
checkpointFiles=dir(fullfile(char(checkpointOptions.folder),'checkpoint-tick-*.mat'));
checkpointBytes=sum([checkpointFiles.bytes]);
status=result.status;
if pauseRequested, status='paused'; end
info=struct('status',status,'pauseRequested',pauseRequested, ...
    'checkpointFolder',char(checkpointOptions.folder), ...
    'checkpointPaths',{checkpointPaths},'checkpointCount',numel(checkpointFiles), ...
    'checkpointBytes',checkpointBytes, ...
    'checkpointOverheadSeconds',checkpointOverheadSeconds, ...
    'elapsedSeconds',toc(runClock),'resumeInfo',resumeInfo);
end

function value=progressName(prefix,suffix)
if isempty(prefix), value=suffix; else, value=[prefix '-' suffix]; end
end

function writeCheckpointProgress(path,phase,tick,lastCheckpoint)
path=char(string(path));
if isempty(path), return; end
try
    progress=struct('phase',char(string(phase)),'currentTick',double(tick), ...
        'lastCheckpoint',char(string(lastCheckpoint)), ...
        'updatedAtUtc',char(datetime('now','TimeZone','UTC', ...
        'Format','yyyy-MM-dd HH:mm:ss.SSS')));
    folder=fileparts(path);
    if ~isfolder(folder), mkdir(folder); end
    temporary=[path '.' char(java.util.UUID.randomUUID()) '.tmp'];
    cleanup=onCleanup(@() deleteTemporary(temporary)); %#ok<NASGU>
    fid=fopen(temporary,'w','n','UTF-8');
    if fid<0, return; end
    closeFile=onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes=unicode2native(jsonencode(progress),'UTF-8');
    if fwrite(fid,bytes,'uint8')~=numel(bytes), return; end
    clear closeFile
    movefile(temporary,path,'f');
catch
    % Observability must not interrupt the active scientific case.
end
end

function deleteTemporary(path)
if isfile(path), delete(path); end
end
