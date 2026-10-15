function manifest=prepareExternalRun(options)
%PREPAREEXTERNALRUN Create a verified local handoff draft without running simulations.
required={'projectRoot','outputFolder','calibrationFile','registryFile', ...
    'caseMatrix','idAssignments'};
if ~isstruct(options)||~isscalar(options)||~all(isfield(options,required))
    error('nbiot:externalRun:Options','Missing required package options.');
end
root=canonicalPath(options.projectRoot);
if ~isfolder(root), error('nbiot:externalRun:ProjectRoot','Project root does not exist.'); end
outputFolder=resolveOutput(root,options.outputFolder);
if isfile(outputFolder)||isfolder(outputFolder)
    error('nbiot:externalRun:OutputExists','The package output folder already exists.');
end

calibration=resolveFile(root,options.calibrationFile,'Calibration');
calibrationHash=nbiot.ml.fileSha256(calibration);
if isfield(options,'expectedCalibrationSha256')&&~sameHash(calibrationHash,options.expectedCalibrationSha256)
    error('nbiot:externalRun:CalibrationHash','Calibration hash does not match the declared value.');
end
registryFile=resolveFile(root,options.registryFile,'Registry');
registry=jsondecode(fileread(registryFile));
validateRegistry(registry);
validateCaseMatrix(options.caseMatrix);
ids=validateAssignments(options.idAssignments,registry);

methods=string(options.caseMatrix.method);
adaptive=any(ismember(methods,["Adaptive-P","Adaptive-RA/DT"]));
model=struct('included',false,'path','','sha256','','packagePath','');
modelFile='';
if isfield(options,'modelFile')&&~isempty(options.modelFile)
    modelFile=resolveFile(root,options.modelFile,'Model');
    modelHash=nbiot.ml.fileSha256(modelFile);
    if isfield(options,'expectedModelSha256')&&~sameHash(modelHash,options.expectedModelSha256)
        error('nbiot:externalRun:ModelHash','Model hash does not match the declared value.');
    end
    model=struct('included',true,'path',relative(root,modelFile),'sha256',modelHash, ...
        'packagePath','project/artifacts/load-model.mat');
elseif adaptive
    error('nbiot:externalRun:Model','Adaptive scenarios require an explicit model package.');
end
resumeCase='';
if isfield(options,'resumePath')&&~isempty(options.resumePath)
    resumeCase=validateResume(root,options.resumePath);
end

files=sourceFiles(root);
staging=fullfile(fileparts(outputFolder), ...
    ['.package-staging-' char(java.util.UUID.randomUUID())]);
[ok,message]=mkdir(staging);
if ~ok, error('nbiot:externalRun:Write','Could not create staging folder: %s',message); end
cleanup=onCleanup(@() removeStaging(staging));
entries=repmat(struct('path','','sha256','','packagePath','', ...
    'packageSha256','','sanitized',false),0,1);
for k=1:numel(files)
    rel=files{k}; source=fullfile(root,strrep(rel,'/',filesep));
    destination=fullfile(staging,'project',strrep(rel,'/',filesep));
    parent=fileparts(destination);
    if ~isfolder(parent), mkdir(parent); end
    [~,~,ext]=fileparts(source); sanitized=false;
    if isText(ext)
        [contents,sanitized]=sanitize(fileread(source),root);
        writeText(destination,contents);
    else
        [ok,message]=copyfile(source,destination);
        if ~ok, error('nbiot:externalRun:Copy','Could not copy %s: %s',rel,message); end
    end
    entries(end+1)=struct('path',rel,'sha256',nbiot.ml.fileSha256(source), ...
        'packagePath',['project/' rel], ...
        'packageSha256',nbiot.ml.fileSha256(destination),'sanitized',sanitized); %#ok<AGROW>
end

calibrationRel=relative(root,calibration);
copyArtifact(calibration,fullfile(staging,'project',strrep(calibrationRel,'/',filesep)));
if model.included
    copyArtifact(modelFile,fullfile(staging,'project','artifacts','load-model.mat'));
end
if isempty(ids)
    idRows=struct('externalRealizationId',{},'role',{});
else
    idRows=table2struct(ids);
end
resourceBudget=struct(); resourceStatus='not-specified';
if isfield(options,'resourceBudget')
    [resourceBudget,resourceStatus]=validateResourceBudget(options.resourceBudget);
end
created=datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''');
manifest=struct('schemaVersion',1,'createdAtUtc',char(created), ...
    'status','draft-needs-external-review','readyForExecution',false, ...
    'projectRevision','working-tree-snapshot','matlabRelease',version('-release'), ...
    'codeFiles',entries,'codeManifestSha256',sha256Text(jsonencode(entries)), ...
    'calibration',struct('path',calibrationRel,'sha256',calibrationHash, ...
        'packagePath',['project/' calibrationRel]), ...
    'model',model,'caseMatrix',table2struct(options.caseMatrix), ...
    'idAssignments',idRows,'registry',struct( ...
        'path',relative(root,registryFile),'sha256',nbiot.ml.fileSha256(registryFile), ...
        'writerPolicy','External machine must be the only writer; this package does not reserve IDs.'), ...
    'resourceBudget',resourceBudget,'resourceStatus',resourceStatus, ...
    'resumeCase',resumeCase,'requiresStage2Revalidation',true, ...
    'resumePolicy','Reuse only verifyCase-passing completed cases; .staging folders are not checkpoints.', ...
    'exclusions',{{'verification/local outputs and logs; only the approved process-runner source files are included', ...
        'verification/completion evidence and previous run outputs; only Stage 2 source files and the approved Stage 2/3 wrappers are included', ...
        'results except named artifacts', ...
        '.git','.env files','credentials and private keys'}}, ...
    'expectedCommands',{{'setupProject();', ...
        'Run verification/completion/stage-2/runStage2Physical.ps1 -TargetedOnly; retain its 38/38 journal.', ...
        'Run the fresh Stage 2 physical matrix with scheduled-local, realizationSeed=43, and finish-current under the shared 57600-second budget.', ...
        'Resume the same physical run with runStage2Physical.ps1 -Resume -RunFolder <absolute path>; do not start a duplicate worker.', ...
        'Create a fresh acceptance with acceptStage2Evidence after technical review.', ...
        'Start the four-count preliminary probe with verification/completion/stage-3/runVariant2.ps1 -Execute.', ...
        'Resume the same run with runVariant2.ps1 -Resume -RunFolder <absolute path>; do not start a duplicate worker.'}});
writeText(fullfile(staging,'manifest.json'),jsonencode(manifest));
[ok,message]=movefile(staging,outputFolder);
if ~ok, error('nbiot:externalRun:Write','Could not finalize the handoff folder: %s',message); end
clear cleanup
end

function path=resolveOutput(root,value)
if ~(ischar(value)||(isstring(value)&&isscalar(value)))
    error('nbiot:externalRun:OutputPath','Output folder must be text.');
end
value=char(value);
if isAbsolute(value), path=canonicalPath(value); else, path=canonicalPath(fullfile(root,value)); end
external=canonicalPath(fullfile(root,'verification','external'));
if ~isWithin(external,path)||strcmpi(external,path)
    error('nbiot:externalRun:OutputPath','Output must be under verification/external.');
end
end

function path=resolveFile(root,value,kind)
identifier=['nbiot:externalRun:' kind];
if ~(ischar(value)||(isstring(value)&&isscalar(value)))
    error(identifier,'%s path must be project-relative text.',kind);
end
value=char(value);
if isAbsolute(value)||contains(value,'..')||contains(value,':')
    error(identifier,'%s path must be project-relative.',kind);
end
path=canonicalPath(fullfile(root,strrep(value,'/',filesep)));
if ~isWithin(root,path)||~isfile(path), error(identifier,'%s file is missing or outside the project.',kind); end
end

function validateCaseMatrix(value)
required={'method','numUE','durationTicks','trafficKind','burstDurationTicks'};
if ~istable(value)||isempty(value)||numel(value.Properties.VariableNames)~=numel(required)|| ...
        ~all(ismember(required,value.Properties.VariableNames))
    error('nbiot:externalRun:CaseMatrix', ...
        'Case matrix columns must match the supported fields exactly.');
end
if any(~ismember(string(value.method),["Static","Adaptive-P","Adaptive-RA/DT"]))|| ...
        any(~ismember(string(value.trafficKind),["burst","periodic","poisson","none"]))
    error('nbiot:externalRun:CaseMatrix','Unsupported method or traffic type.');
end
for name={'numUE','durationTicks','burstDurationTicks'}
    values=value.(name{1});
    if ~isnumeric(values)||~isreal(values)||~iscolumn(values)||any(~isfinite(values))|| ...
            any(values<0)||any(values~=fix(values))
        error('nbiot:externalRun:CaseMatrix','Case matrix values must be nonnegative integers.');
    end
end
if any(value.numUE<1)||any(value.durationTicks<1)||any(value.burstDurationTicks>value.durationTicks)
    error('nbiot:externalRun:CaseMatrix','UE count and horizon must be positive; burst must fit the horizon.');
end
end

function ids=validateAssignments(value,registry)
if ~istable(value)||~all(ismember({'externalRealizationId','role'},value.Properties.VariableNames))
    error('nbiot:externalRun:Assignments','ID assignments need externalRealizationId and role columns.');
end
numbers=value.externalRealizationId; roles=string(value.role);
if ~isnumeric(numbers)||~iscolumn(numbers)||any(~isfinite(numbers)|numbers<0|numbers>4095|numbers~=fix(numbers))|| ...
        numel(unique(numbers))~=numel(numbers)
    error('nbiot:externalRun:DuplicateId','Assigned IDs must be unique integers in 0:4095.');
end
if any(~ismember(roles,string(registry.roles)))
    error('nbiot:externalRun:Role','An assigned role is absent from the registry.');
end
if any(ismember(numbers,registryIds(registry)))
    error('nbiot:externalRun:AllocatedId','An assigned ID is reserved or already used.');
end
ids=table(double(numbers),roles,'VariableNames',{'externalRealizationId','role'});
end

function validateRegistry(registry)
if ~isstruct(registry)||~isscalar(registry)|| ...
        ~all(isfield(registry,{'schemaVersion','roles','reservations','assignments'}))
    error('nbiot:externalRun:Registry','The realization registry is invalid.');
end
end

function ids=registryIds(registry)
ids=zeros(0,1);
for k=1:numel(registry.reservations)
    range=double(registry.reservations(k).range(:).');
    if numel(range)==2&&all(isfinite(range))&&range(1)<=range(2)
        ids=[ids;(range(1):range(2)).']; %#ok<AGROW>
    end
end
for k=1:numel(registry.assignments)
    if isfield(registry.assignments(k),'ids')&&~isempty(registry.assignments(k).ids)
        ids=[ids;double(registry.assignments(k).ids(:))]; %#ok<AGROW>
    end
end
ids=unique(ids);
end

function [budget,status]=validateResourceBudget(value)
allowed={'targetMachine','availableMemoryBytes','maxUE','maxCaseSeconds', ...
    'maxSuiteSeconds','maxProcesses'};
if ~isstruct(value)||~isscalar(value)
    error('nbiot:externalRun:ResourceBudget','Resource budget must be a scalar structure.');
end
fields=fieldnames(value);
if any(~ismember(fields,allowed))
    error('nbiot:externalRun:ResourceBudget', ...
        'Resource budget contains unsupported fields.');
end
budget=struct();
for k=1:numel(fields)
    name=fields{k}; item=value.(name);
    if strcmp(name,'targetMachine')
        if isstring(item)&&isscalar(item), item=char(item); end
        if ~ischar(item)||~isrow(item)
            error('nbiot:externalRun:ResourceBudget', ...
                'targetMachine must be a short plain-text label.');
        end
        item=strtrim(item);
        if isempty(item)||numel(item)>64||contains(item,'/')||contains(item,'\')|| ...
                contains(item,':')||contains(item,'..')||any(ismember(item,[newline char(13)]))
            error('nbiot:externalRun:ResourceBudget', ...
                'targetMachine must be a label, not a path.');
        end
        budget.(name)=item;
    else
        if ~isnumeric(item)||~isscalar(item)||~isfinite(item)||item<=0|| ...
                (ismember(name,{'availableMemoryBytes','maxUE','maxProcesses'})&&item~=fix(item))
            error('nbiot:externalRun:ResourceBudget', ...
                '%s must be a positive finite numeric limit.',name);
        end
        budget.(name)=double(item);
    end
end
status='provided-but-requires-target-review';
end

function path=validateResume(root,value)
if ~(ischar(value)||(isstring(value)&&isscalar(value)))
    error('nbiot:externalRun:Resume','Resume path must be project-relative.');
end
value=char(value);
if isAbsolute(value)||contains(value,'..')||contains(value,':')||contains(lower(value),'.staging')
    error('nbiot:externalRun:Resume','An interrupted .staging folder is not a checkpoint.');
end
folder=canonicalPath(fullfile(root,strrep(value,'/',filesep)));
if ~isWithin(root,folder)||~isfolder(folder)||~isfile(fullfile(folder,'case-complete.json'))
    error('nbiot:externalRun:Resume','Only a manifested completed case may be reused.');
end
report=nbiot.results.verifyCase(folder);
if ~report.passed||~strcmp(report.status,'completed')
    error('nbiot:externalRun:Resume','The case did not pass verifyCase as completed.');
end
path=value;
end

function files=sourceFiles(root)
folders={'apps','configs','docs','examples','experiments','src','tests'};
files={'README.md','setupProject.m'};
if isfile(fullfile(root,'AGENTS.md')), files{end+1}='AGENTS.md'; end
if isfile(fullfile(root,'RELEASE.md')), files{end+1}='RELEASE.md'; end
for k=1:numel(folders)
    folder=fullfile(root,folders{k});
    if ~isfolder(folder), continue; end
    listing=dir(fullfile(folder,'**','*'));
    for j=1:numel(listing)
        if listing(j).isdir, continue; end
        full=fullfile(listing(j).folder,listing(j).name);
        [~,~,ext]=fileparts(full);
        if ~ismember(lower(ext),{'.m','.md','.json','.txt'}), continue; end
        rel=relative(root,full);
        if ~isUnsafe(rel), files{end+1}=rel; end %#ok<AGROW>
    end
end
stage2Folder=fullfile(root,'verification','completion','stage-2');
stage2Sources=dir(fullfile(stage2Folder,'*.m'));
for k=1:numel(stage2Sources)
    if ~stage2Sources(k).isdir
        files{end+1}=relative(root,fullfile(stage2Sources(k).folder, ...
            stage2Sources(k).name)); %#ok<AGROW>
    end
end
runnerSources={ ...
    'verification/completion/stage-2/runStage2Physical.ps1', ...
    'verification/completion/stage-3/runVariant2.ps1', ...
    'verification/completion/stage-3/runLoadPilot.ps1', ...
    'verification/local/InvokeScheduledProcess.ps1', ...
    'verification/local/InvokeBoundedProcess.ps1', ...
    'verification/local/OwnedProcessJob.cs'};
for k=1:numel(runnerSources)
    if isfile(fullfile(root,strrep(runnerSources{k},'/',filesep)))
        files{end+1}=runnerSources{k}; %#ok<AGROW>
    end
end
files=sort(unique(files));
end

function yes=isUnsafe(value)
value=lower(strrep(value,'\','/'));
blocked={'.env','secret','credential','password','token','private-key','.pem','.pfx','.key'};
yes=any(cellfun(@(part)contains(value,part),blocked));
end

function yes=isText(extension)
yes=ismember(lower(extension),{'.m','.md','.json','.txt','.ps1','.cs'});
end

function [value,changed]=sanitize(value,root)
original=value;
value=strrep(value,root,'<PROJECT_ROOT>');
value=strrep(value,strrep(root,'\','/'),'<PROJECT_ROOT>');
value=strrep(value,strrep(root,'/','\'),'<PROJECT_ROOT>');
value=regexprep(value,'(?i)[A-Z]:[\\/](?:[^\\/\r\n]+[\\/])*[^\\/\r\n]*','<LOCAL_PATH>');
changed=~strcmp(value,original);
end

function copyArtifact(source,destination)
parent=fileparts(destination);
if ~isfolder(parent), mkdir(parent); end
[ok,message]=copyfile(source,destination);
if ~ok, error('nbiot:externalRun:Copy','Could not copy an artifact: %s',message); end
end

function removeStaging(path)
if isfolder(path), rmdir(path,'s'); end
end

function writeText(path,value)
parent=fileparts(path);
if ~isfolder(parent), mkdir(parent); end
fid=fopen(path,'w','n','UTF-8');
if fid<0, error('nbiot:externalRun:Write','Could not write a package file.'); end
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(value,'UTF-8'),'uint8');
end

function yes=sameHash(actual,expected)
yes=(ischar(expected)||(isstring(expected)&&isscalar(expected)))&&strcmpi(actual,char(expected));
end

function value=relative(root,path)
root=canonicalPath(root); path=canonicalPath(path);
if ~isWithin(root,path)||strcmpi(root,path)
    error('nbiot:externalRun:Path','A package file is outside projectRoot.');
end
value=strrep(path(length(root)+2:end),filesep,'/');
end

function yes=isWithin(root,path)
root=[lower(stripTrailing(root)) filesep];
yes=startsWith(lower(path),root);
end

function value=stripTrailing(value)
while numel(value)>3&&any(value(end)==['\','/']), value(end)=[]; end
end

function path=canonicalPath(value)
if ~(ischar(value)||(isstring(value)&&isscalar(value)))
    error('nbiot:externalRun:Path','Paths must be scalar text.');
end
path=char(java.io.File(char(value)).getCanonicalPath());
end

function yes=isAbsolute(value)
yes=~isempty(regexp(value,'^(?:[A-Za-z]:[\\/]|\\\\|/)', 'once'));
end

function digest=sha256Text(value)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(uint8(unicode2native(value,'UTF-8')),'int8'));
digest=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
