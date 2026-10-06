function metadata=runtimeManifest(cfg,options)
%RUNTIMEMANIFEST Registered computational identities, independent of docs.
if nargin<2, options=struct(); end
% Hooks other than the explicitly registered runner have no identity contract.
rejectUnknownHooks(options,{'runner','runExperimentFcn'});
rejectUnknownHooks(cfg,{});
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
options=defaults(options,struct('projectRoot',root,'calibrationFile','', ...
    'modelFiles',{{}},'policyFiles',{{}},'inputFiles',{{}},'scenario',[], ...
    'runner',[],'runnerFiles',{{}},'runnerInputs',struct(),'runnerDependenciesDeclared',false));
source=optimizationSourceManifest(options.projectRoot);
canonicalCfg=cfg;
if isfield(canonicalCfg,'logging'), canonicalCfg.logging.outputFolder='<case-output>'; end
if isfield(canonicalCfg,'calibrationReport'), canonicalCfg=rmfield(canonicalCfg,'calibrationReport'); end
if isempty(options.calibrationFile)
    if isfield(cfg,'calibrationReport'), calibration=hashValue(cfg.calibrationReport);
    else, calibration=hashValue(cfg.phy); end
else, calibration=hashFile(options.calibrationFile); end
model=hashFiles(options.modelFiles); inputs=hashValue(struct( ...
    'files',hashFiles(options.inputFiles),'scenario',options.scenario));
policy=hashValue(struct('configuration',cfg.policy,'files',hashFiles(options.policyFiles)));
if isempty(options.runner)
    runner=hashValue(struct('function','nbiot.runExperiment','source',source.sha256));
else
    info=functions(options.runner);
    if ~options.runnerDependenciesDeclared || strcmp(info.type,'anonymous') || ...
            ~isfield(info,'file') || isempty(info.file)
        error('nbiot:experiments:UnregisteredDependency','External runner and dependencies must be explicitly registered.');
    end
    registered=cellstr(string(options.runnerFiles));
    paths=cellfun(@absolutePath,registered,'UniformOutput',false);
    if ~any(strcmpi(absolutePath(info.file),paths))
        error('nbiot:experiments:UnregisteredDependency','Runner defining file is not registered.');
    end
    captured=struct();
    if isfield(info,'workspace')
        for w=1:numel(info.workspace)
            workspace=info.workspace{w}; names=fieldnames(workspace);
            for k=1:numel(names)
                name=names{k}; value=workspace.(name);
                if isa(value,'function_handle') && isequal(value,options.runner), continue; end
                if ~isfield(options.runnerInputs,name) || ~strcmp(hashValue(options.runnerInputs.(name)),hashValue(value))
                    error('nbiot:experiments:UnregisteredDependency','Captured runner input %s must be registered with its actual value.',name);
                end
                captured.(name)=value;
            end
        end
    end
    runner=hashValue(struct('function',info.function,'files',hashFiles(registered), ...
        'capturedInputs',captured,'registeredInputs',options.runnerInputs));
end
environment=struct('matlabVersion',version,'release',version('-release'), ...
    'lteVersion',ver('lte'),'computer',computer,'validatedInMatlab',false,'sourceProfile','static-v1');
metadata=struct('runtimeVersion',1,'resultSchemaVersion',2, ...
    'configSha256',nbiot.results.configSha256(cfg,true), ...
    'canonicalConfigSha256',hashValue(canonicalCfg),'sourceSha256',source.sha256, ...
    'calibrationSha256',calibration,'modelSha256',model,'policySha256',policy, ...
    'inputSha256',inputs,'runnerSha256',runner,'environment',environment);
identity=struct('method',cfg.policy.name,'configuration',metadata.canonicalConfigSha256, ...
    'traffic',cfg.traffic,'realization',cfg.simulation.realizationId, ...
    'calibration',calibration,'model',model,'policy',policy,'inputs',inputs,'runner',runner);
metadata.caseKey=['case-v2-' hashValue(identity)];
end

function value=canonical(value)
if isstruct(value)
    value=orderfields(value);
    names=fieldnames(value);
    for i=1:numel(value)
        for k=1:numel(names), value(i).(names{k})=canonical(value(i).(names{k})); end
    end
elseif iscell(value)
    for k=1:numel(value), value{k}=canonical(value{k}); end
elseif isnumeric(value) || islogical(value)
    dataClass=class(value); dataShape=size(value); sparseStorage=issparse(value); realStorage=isreal(value);
    if islogical(value)
        realBytes=uint8(full(value(:))); imaginaryBytes=uint8([]);
    else
        realBytes=typecast(full(real(value(:))),'uint8');
        imaginaryBytes=typecast(full(imag(value(:))),'uint8');
    end
    value=struct('numericClass',dataClass,'shape',dataShape,'sparseStorage',sparseStorage,'realStorage',realStorage, ...
        'realBytes',lower(reshape(dec2hex(realBytes,2).',1,[])), ...
        'imaginaryBytes',lower(reshape(dec2hex(imaginaryBytes,2).',1,[])));
elseif isa(value,'function_handle') || (isobject(value) && ~isstring(value))
    error('nbiot:experiments:UnregisteredDependency','Dynamic function/object inputs cannot be identified.');
end
end
function digest=hashValue(value)
digest=hashBytes(unicode2native(jsonencode(canonical(value)),'UTF-8'));
end
function digest=hashFiles(paths)
paths=sort(cellstr(string(paths))); entries=struct('path',{},'sha256',{});
for k=1:numel(paths)
    entries(end+1)=struct('path',absolutePath(paths{k}),'sha256',hashFile(paths{k})); %#ok<AGROW>
end
digest=hashValue(entries);
end
function path=absolutePath(path)
path=char(java.io.File(char(path)).getCanonicalPath());
end
function digest=hashFile(path)
fid=fopen(path,'rb');
if fid<0, error('nbiot:experiments:UnregisteredDependency','Cannot identify dependency %s.',path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
digest=hashBytes(fread(fid,Inf,'*uint8'));
end
function hex=hashBytes(bytes)
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)),'int8'));
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
function value=defaults(value,base)
names=fieldnames(base);
for k=1:numel(names)
    if ~isfield(value,names{k}), value.(names{k})=base.(names{k}); end
end
end

function rejectUnknownHooks(value,allowed)
if ~isstruct(value), return; end
names=fieldnames(value);
for i=1:numel(value)
    for k=1:numel(names)
        name=names{k}; item=value(i).(name);
        hook=~isempty(regexpi(name,'hook|fcn|function','once')) || isa(item,'function_handle');
        if hook && ~isempty(item) && ~ismember(name,allowed)
            error('nbiot:experiments:UnregisteredDependency','External hook %s has no registered identity contract.',name);
        end
        if ~ismember(name,allowed), rejectUnknownHooks(item,{}); end
    end
end
end
