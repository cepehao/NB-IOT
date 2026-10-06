function manifest=runStaticSweepParallel(options)
%RUNSTATICSWEEPPARALLEL Execute independent realizations on process workers.
if nargin<1, options=struct(); end
if ~isfield(options,'numWorkers'), options.numWorkers=2; end
if ~isnumeric(options.numWorkers) || ~isscalar(options.numWorkers) || ...
        ~isfinite(options.numWorkers) || options.numWorkers<1 || ...
        fix(options.numWorkers)~=options.numWorkers
    error('nbiot:experiments:ParallelWorkers','numWorkers must be a positive integer.');
end
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root); addpath(fullfile(root,'experiments')); setupProject();
options=defaults(options,struct('counts',[100 500 1000 2500 5000], ...
    'burstDurations',[10 100 500],'realizationIds',0:2, ...
    'calibrationFile',fullfile(root,'results','nprach-calibration.mat'), ...
    'outputFolder',fullfile(root,'results','sweep-parallel'),'resume',true));
validateCases(options);
if ~isfolder(options.outputFolder), mkdir(options.outputFolder); end
calibrationSha256=hashFile(options.calibrationFile);
sourceManifest=optimizationSourceManifest(root);
sourceSha256=sourceManifest.sha256;
environment=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer, ...
    'validatedInMatlab',false,'sourceProfile','static-v1');
rows={}; jobs={}; jobRows=[];
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
            [accepted,attemptFolder,marker]=findAcceptedCase(caseFolder,metadata,options.resume);
            rowIndex=size(rows,1)+1;
            if accepted
                resultFile=fullfile(attemptFolder,char(string(marker.resultFile)));
                rows(rowIndex,:)={count,duration,id,char(string(marker.status)), ...
                    double(marker.elapsedSeconds),resultFile,caseKey,metadata.configSha256, ...
                    sourceSha256,calibrationSha256};
            else
                rows(rowIndex,:)={count,duration,id,'pending',NaN,'',caseKey, ...
                    metadata.configSha256,sourceSha256,calibrationSha256};
                jobs{end+1,1}=struct('cfg',cfg,'caseFolder',caseFolder, ...
                    'metadata',metadata,'caseKey',caseKey); %#ok<AGROW>
                jobRows(end+1,1)=rowIndex; %#ok<AGROW>
            end
        end
    end
end

if ~isempty(jobs)
    pool=processPool(options.numWorkers);
    ownsPool=pool.created; pool=pool.value;
    poolCleanup=[];
    if ownsPool, poolCleanup=onCleanup(@() closePool(pool)); end %#ok<NASGU>
    workerMeta=cell(size(jobs));
    try
        parfor k=1:numel(jobs)
            job=jobs{k};
            try
                workerMeta{k}=nbiot.experiments.runStaticCase( ...
                    job.cfg,job.caseFolder,job.metadata);
            catch exception
                workerMeta{k}=struct('caseKey',job.caseKey,'status','worker-error', ...
                    'elapsedSeconds',NaN,'resultFile','', ...
                    'errorIdentifier',exception.identifier,'errorMessage',exception.message);
            end
        end
    catch exception
        error('nbiot:experiments:ParallelExecution', ...
            'Process pool stopped; accepted case folders remain available for resume. %s',exception.message);
    end
    for k=1:numel(workerMeta)
        meta=workerMeta{k}; rowIndex=jobRows(k);
        rows{rowIndex,4}=char(string(meta.status));
        rows{rowIndex,5}=double(meta.elapsedSeconds);
        rows{rowIndex,6}=char(string(meta.resultFile));
        if strcmp(meta.status,'worker-error')
            warning('nbiot:experiments:WorkerFailed','Case %s failed on worker (%s): %s', ...
                meta.caseKey,meta.errorIdentifier,meta.errorMessage);
        end
    end
end
manifest=makeManifest(rows);
updateManifest(options.outputFolder,manifest);
end

function validateCases(options)
groups={'counts','burstDurations','realizationIds'};
for k=1:numel(groups)
    name=groups{k}; values=options.(name);
    validateattributes(values,{'numeric'},{'vector','integer','nonnegative','nonempty', ...
        'finite'},mfilename,name);
    if numel(unique(values))~=numel(values)
        error('nbiot:experiments:DuplicateCase','Option %s contains duplicate values.',name);
    end
end
if any(options.counts<1) || any(options.burstDurations<1) || any(options.realizationIds>4095)
    error('nbiot:experiments:InvalidCase','Counts, burst durations or realization IDs are out of range.');
end
end

function [accepted,folder,marker]=findAcceptedCase(caseFolder,expected,resume)
accepted=false; folder=''; marker=struct();
if ~resume || ~isfolder(caseFolder), return; end
attempts=dir(fullfile(caseFolder,'run-*')); attempts=attempts([attempts.isdir]);
for k=numel(attempts):-1:1
    candidate=fullfile(attempts(k).folder,attempts(k).name);
    report=nbiot.results.verifyCase(candidate,expected);
    if report.passed && strcmp(report.status,'completed')
        folder=candidate; marker=jsondecode(fileread(fullfile(candidate,'case-complete.json')));
        accepted=true; return
    end
end
end

function value=processPool(workers)
if isempty(ver('parallel')) || ~license('test','Distrib_Computing_Toolbox')
    error('nbiot:experiments:ParallelUnavailable', ...
        'Parallel Computing Toolbox is unavailable; use runStaticSweep for sequential runs.');
end
cluster=parcluster('Processes');
if workers>cluster.NumWorkers
    error('nbiot:experiments:ParallelWorkers', ...
        'Requested %d workers; process profile allows %d. Sequential runner remains available.', ...
        workers,cluster.NumWorkers);
end
pool=gcp('nocreate'); created=false;
if isempty(pool)
    try
        pool=parpool('Processes',workers); created=true;
    catch exception
        error('nbiot:experiments:ParallelUnavailable', ...
            'Could not start a %d-worker process pool (%s). Use runStaticSweep sequentially.', ...
            workers,exception.message);
    end
elseif ~contains(class(pool),'ProcessPool')
    error('nbiot:experiments:PoolType', ...
        'An existing non-process pool is active; run the sequential sweep or close that pool explicitly.');
elseif pool.NumWorkers~=workers
    error('nbiot:experiments:PoolSize', ...
        'Existing pool has %d workers, requested %d. Close or reuse a matching process pool.', ...
        pool.NumWorkers,workers);
end
value=struct('value',pool,'created',created);
end

function closePool(pool)
try, delete(pool); catch, end
end

function manifest=makeManifest(rows)
manifest=cell2table(rows,'VariableNames',{'numUE','burstDurationTicks', ...
    'realizationId','status','elapsedSeconds','resultFile','caseKey', ...
    'configSha256','sourceSha256','calibrationSha256'});
end

function updateManifest(folder,manifest)
destination=fullfile(folder,'manifest.csv');
temporary=[tempname(folder) '.csv']; cleanup=onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
writetable(manifest,temporary);
[ok,message]=movefile(temporary,destination,'f');
if ~ok, error('nbiot:experiments:Manifest','Cannot atomically update manifest: %s',message); end
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
