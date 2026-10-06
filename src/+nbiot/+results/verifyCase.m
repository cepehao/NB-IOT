function report=verifyCase(caseFolder,expected,memoryResult,requireMarker)
%VERIFYCASE Check a saved result, exported tables and run provenance.
if nargin<2 || isempty(expected), expected=struct(); end
if nargin<3, memoryResult=[]; end
if nargin<4, requireMarker=true; end
try
    report=verifyCaseImpl(caseFolder,expected,memoryResult,requireMarker);
catch exception
    report=struct('passed',false,'status','','caseKey','','checks', ...
        struct('name','damaged-package','passed',false,'detail',exception.message), ...
        'errors',{{['damaged-package: ' exception.message]}});
end
end

function report=verifyCaseImpl(caseFolder,expected,memoryResult,requireMarker)
report=struct('passed',false,'status','','caseKey','','checks', ...
    struct('name',{},'passed',{},'detail',{}),'errors',{{}});
markerPath=fullfile(caseFolder,'case-complete.json'); marker=[];
if isfile(markerPath)
    try
        marker=jsondecode(fileread(markerPath));
    catch exception
        report=addCheck(report,'completion-marker',false,exception.message);
        report=finish(report); return
    end
elseif requireMarker
    report=addCheck(report,'completion-marker',false,'Completion marker is missing.');
    report=finish(report); return
end

if ~isempty(marker)
    markerFields={'manifestVersion','caseKey','configSha256','sourceSha256', ...
        'calibrationSha256','environment','status','resultFile','exportStem', ...
        'files','tables','balances','elapsedSeconds'};
    missing=markerFields(~isfield(marker,markerFields));
    report=addCheck(report,'marker-fields',isempty(missing),strjoin(missing,', '));
    if ~isempty(missing), report=finish(report); return; end
    report.status=char(string(marker.status)); report.caseKey=char(string(marker.caseKey));
    versionOk=isequal(double(marker.manifestVersion),1) || isequal(double(marker.manifestVersion),2);
    report=addCheck(report,'marker-version',versionOk, ...
        sprintf('manifestVersion=%s',string(marker.manifestVersion)));
    if ~versionOk, report=finish(report); return; end
    if marker.manifestVersion==1 && (isfield(marker,'runtimeVersion') || isfield(marker,'resultSchemaVersion'))
        report=addCheck(report,'marker-runtime-version',false,'Legacy marker cannot contain schema-2 runtime identity.');
        report=finish(report); return;
    end
    if marker.manifestVersion==2
        report=addCheck(report,'runtime-schema',runtimeValid(marker),'Runtime identity schema 1 / result schema 2 required.');
        if ~runtimeValid(marker), report=finish(report); return; end
    end
else
    report.status='staging';
end

if ~isempty(marker)
    resultFile=char(string(marker.resultFile)); exportStem=char(string(marker.exportStem));
else
    if isempty(memoryResult)
        report=addCheck(report,'result-file-name',false,'Staging verification requires the in-memory result.');
        report=finish(report); return
    end
    exportStem=stem(memoryResult); resultFile=[exportStem '.mat'];
end
matPath=fullfile(caseFolder,resultFile);
if ~isfile(matPath)
    report=addCheck(report,'mat-file',false,'Result MAT file is missing.');
    report=finish(report); return
end
try
    variables=whos('-file',matPath); variableNames={variables.name};
catch exception
    report=addCheck(report,'mat-readable',false,exception.message);
    report=finish(report); return
end
requiredVariables={'result','caseMetadata','configSnapshot','resultStatus', ...
    'kpiSummary','environmentSnapshot'};
allPresent=all(ismember(requiredVariables,variableNames));
report=addCheck(report,'mat-variables',allPresent, ...
    strjoin(setdiff(requiredVariables,variableNames),', '));
if ~allPresent, report=finish(report); return; end
try
    loaded=load(matPath,'caseMetadata','configSnapshot','resultStatus', ...
        'kpiSummary','environmentSnapshot');
catch exception
    report=addCheck(report,'mat-snapshots',false,exception.message);
    report=finish(report); return
end
caseMetadata=loaded.caseMetadata;
if isfield(caseMetadata,'runtimeVersion')
    versionSnapshot=load(matPath,'resultSchemaVersion');
    schemaOk=runtimeValid(caseMetadata) && isfield(versionSnapshot,'resultSchemaVersion') && ...
        isequal(versionSnapshot.resultSchemaVersion,2);
    report=addCheck(report,'result-schema',schemaOk,'MAT result schema must be supported and agree with runtime identity.');
end
if isempty(marker)
    marker=caseMetadata;
    marker.resultFile=resultFile; marker.exportStem=exportStem;
    marker.balances=balanceSnapshot(loaded.kpiSummary);
    marker.tables=memoryTables(memoryResult,exportStem);
    report.caseKey=char(string(marker.caseKey)); report.status=char(string(marker.status));
end

identityFields={'caseKey','configSha256','sourceSha256','calibrationSha256','environment'};
runtimeFields={'runtimeVersion','resultSchemaVersion','canonicalConfigSha256', ...
    'modelSha256','policySha256','inputSha256','runnerSha256'};
identityFields=[identityFields runtimeFields];
for k=1:numel(identityFields)
    name=identityFields{k};
    if isfield(expected,name)
        match=isfield(marker,name) && equivalent(marker.(name),expected.(name));
        report=addCheck(report,['expected-' name],match, ...
            sprintf('Expected metadata %s %s.',name,ternary(match,'matches','differs')));
    end
end

compareFields={'caseKey','configSha256','sourceSha256','calibrationSha256','environment','status'};
if isfield(marker,'runtimeVersion') || isfield(caseMetadata,'runtimeVersion')
    compareFields=[compareFields runtimeFields];
end
matched=true;
for k=1:numel(compareFields)
    name=compareFields{k};
    if ~isfield(caseMetadata,name) || ~isfield(marker,name) || ...
            ~equivalent(caseMetadata.(name),marker.(name))
        matched=false;
    end
end
report=addCheck(report,'mat-identity',matched,'MAT identity snapshot must match marker.');
try
    computed=nbiot.results.configSha256(loaded.configSnapshot,isfield(marker,'runtimeVersion'));
    configOk=strcmp(computed,char(string(marker.configSha256)));
    expectedStem=sprintf('static-v1_n%d_r%04d', ...
        loaded.configSnapshot.simulation.numUE,loaded.configSnapshot.simulation.realizationId);
    nameOk=strcmp(exportStem,expectedStem) && strcmp(resultFile,[expectedStem '.mat']);
catch
    configOk=false;
    nameOk=false;
end
report=addCheck(report,'config-hash',configOk,'MAT configuration hash must match marker.');
report=addCheck(report,'result-file-name',nameOk,'MAT and CSV names must match the saved case configuration.');
envOk=equivalent(loaded.environmentSnapshot,marker.environment);
report=addCheck(report,'receiver-version',envOk,'Receiver environment must match marker.');
try
    kpi=balanceSnapshot(loaded.kpiSummary);
    balanceOk=equivalent(kpi,marker.balances) && ...
        double(kpi.created)==double(kpi.delivered)+double(kpi.dropped)+double(kpi.unfinished) && ...
        double(kpi.raStarted)==double(kpi.raSuccess)+double(kpi.raFailed)+double(kpi.raUnfinished);
catch
    balanceOk=false;
end
report=addCheck(report,'kpi-balance',balanceOk,'Packet and random-access totals must balance.');
if ~isempty(memoryResult)
    report=addCheck(report,'memory-status', ...
        strcmp(char(string(memoryResult.status)),char(string(loaded.resultStatus))), ...
        'Saved status must match the in-memory result.');
    report=addCheck(report,'memory-kpi',equivalent( ...
        balanceSnapshot(memoryResult.kpiSummary),balanceSnapshot(loaded.kpiSummary)), ...
        'Saved KPI summary must match the in-memory result.');
end
statusOk=strcmp(char(string(loaded.resultStatus)),char(string(marker.status)));
report=addCheck(report,'result-status',statusOk,'MAT status must match marker.');

if ~isempty(markerPath) && isfile(markerPath)
    fileRecords=marker.files; if iscell(fileRecords), fileRecords=[fileRecords{:}]; end
    expectedFiles=[{resultFile},cellstr(memoryTableFiles(exportStem))];
    actualNames=cellstr(string({fileRecords.name}));
    listOk=numel(unique(actualNames))==numel(expectedFiles) && ...
        isequal(sort(actualNames),sort(expectedFiles));
    report=addCheck(report,'file-list',listOk,'Marker must list MAT and all six CSV exports exactly once.');
else
    expectedFiles=[{resultFile},cellstr(memoryTableFiles(exportStem))];
    present=cellfun(@(name) isfile(fullfile(caseFolder,name)),expectedFiles);
    report=addCheck(report,'file-list',all(present), ...
        'Staged case must contain MAT and all six CSV exports before commit.');
    fileRecords=repmat(struct('name','','sha256','','bytes',0),0,1);
    for k=1:numel(expectedFiles)
        path=fullfile(caseFolder,expectedFiles{k});
        if isfile(path)
            d=dir(path); fileRecords(end+1)=struct('name',expectedFiles{k}, ...
                'sha256',hashFile(path),'bytes',d.bytes); %#ok<AGROW>
        end
    end
end
for k=1:numel(fileRecords)
    record=fileRecords(k); name=char(string(record.name)); path=fullfile(caseFolder,name);
    if ~isfile(path)
        report=addCheck(report,['file-' name],false,'Required file is missing.'); continue
    end
    try
        d=dir(path); hash=hashFile(path);
        fileOk=double(record.bytes)==d.bytes && strcmpi(char(string(record.sha256)),hash);
        report=addCheck(report,['file-' name],fileOk,'Byte count and SHA-256 must match marker.');
    catch exception
        report=addCheck(report,['file-' name],false,exception.message);
    end
end

try
    tables=marker.tables; if iscell(tables), tables=[tables{:}]; end
    tableListOk=isstruct(tables) && all(isfield(tables,{'file','variableNames','rows'}));
    if tableListOk
        expectedTableFiles=reshape(cellstr(memoryTableFiles(exportStem)),1,[]);
        actualTableFiles=reshape(cellstr(string({tables.file})),1,[]);
        tableListOk=numel(actualTableFiles)==numel(expectedTableFiles) && ...
            numel(unique(actualTableFiles))==numel(expectedTableFiles) && ...
            isequal(sort(actualTableFiles),sort(expectedTableFiles));
    end
catch
    tableListOk=false;
end
report=addCheck(report,'table-list',tableListOk, ...
    'Marker must describe all six CSV table schemas exactly once.');
if ~tableListOk, report=finish(report); return; end
for k=1:numel(tables)
    tableInfo=tables(k); name=char(string(tableInfo.file)); path=fullfile(caseFolder,name);
    if ~isfile(path), continue; end
    try
        actual=readtable(path,'VariableNamingRule','preserve','TextType','string');
        schema=reshape(cellstr(string(tableInfo.variableNames)),1,[]);
        schemaOk=isequal(actual.Properties.VariableNames,schema);
        rowsOk=height(actual)==double(tableInfo.rows);
        report=addCheck(report,['schema-' name],schemaOk, ...
            sprintf('CSV columns [%s], expected [%s].', ...
            strjoin(actual.Properties.VariableNames,','),strjoin(schema,',')));
        report=addCheck(report,['rows-' name],rowsOk, ...
            sprintf('Expected %d rows; read %d.',double(tableInfo.rows),height(actual)));
        if ~isempty(memoryResult)
            expectedTable=memoryTable(memoryResult,name);
            same=strcmp(tableHash(expectedTable),hashFile(path));
            report=addCheck(report,['readback-' name],same, ...
                'CSV bytes must match a fresh export of the in-memory table.');
        end
        if strcmp(name,[exportStem '_ue.csv'])
            ueOk=checkUeBalance(actual,marker.balances,loaded.configSnapshot.simulation.numUE);
            report=addCheck(report,'ue-balance',ueOk, ...
                'Per-UE totals and row count must balance the KPI summary.');
        end
    catch exception
        report=addCheck(report,['read-' name],false,exception.message);
    end
end
report=finish(report);
end

function tables=memoryTables(result,exportStem)
data={result.ueSummary,result.kpiTimeSeries,result.dataset.observations, ...
    result.dataset.targets,result.resourceUsage,result.dataset.manifest};
suffixes={'_ue.csv','_kpi.csv','_observations.csv','_targets.csv','_resources.csv','_split.csv'};
tables=repmat(struct('file','','variableNames',{{}},'rows',0),numel(suffixes),1);
for k=1:numel(suffixes)
    tables(k)=struct('file',[exportStem suffixes{k}], ...
        'variableNames',{data{k}.Properties.VariableNames},'rows',height(data{k}));
end
end

function files=memoryTableFiles(exportStem)
files=string({[exportStem '_ue.csv'],[exportStem '_kpi.csv'], ...
    [exportStem '_observations.csv'],[exportStem '_targets.csv'], ...
    [exportStem '_resources.csv'],[exportStem '_split.csv']});
end

function value=memoryTable(result,file)
tables={result.ueSummary,result.kpiTimeSeries,result.dataset.observations, ...
    result.dataset.targets,result.resourceUsage,result.dataset.manifest};
suffixes={'_ue.csv','_kpi.csv','_observations.csv','_targets.csv','_resources.csv','_split.csv'};
value=[];
for k=1:numel(suffixes)
    if endsWith(file,suffixes{k}), value=tables{k}; return; end
end
error('nbiot:results:Verify','Unknown table export %s.',file);
end

function hex=tableHash(value)
path=[tempname '.csv']; cleanup=onCleanup(@() removeTemporary(path)); %#ok<NASGU>
writetable(value,path); hex=hashFile(path);
end

function hex=hashFile(path)
fid=fopen(path,'rb');
if fid<0, error('nbiot:results:Hash','Cannot read %s.',path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
digest=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,4*1024*1024,'*uint8');
    if isempty(bytes), break; end
    digest.update(typecast(bytes(:),'int8'));
end
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function balances=balanceSnapshot(kpi)
names={'created','delivered','dropped','unfinished', ...
    'raStarted','raSuccess','raFailed','raUnfinished'};
balances=struct();
for k=1:numel(names)
    if ~isfield(kpi,names{k}), error('nbiot:results:Balance','Missing %s.',names{k}); end
    balances.(names{k})=kpi.(names{k});
end
end

function ok=checkUeBalance(ue,b,numUE)
required={'created','delivered','dropped','unfinished'};
if ~all(ismember(required,ue.Properties.VariableNames)) || height(ue)~=numUE
    ok=false; return
end
if any(ue.created~=ue.delivered+ue.dropped+ue.unfinished), ok=false; return; end
ok=sum(ue.created)==double(b.created) && sum(ue.delivered)==double(b.delivered) && ...
    sum(ue.dropped)==double(b.dropped) && sum(ue.unfinished)==double(b.unfinished);
end

function ok=equivalent(a,b)
if ischar(a) || isstring(a), a=char(string(a)); end
if ischar(b) || isstring(b), b=char(string(b)); end
try, ok=isequaln(a,b); catch, ok=false; end
end

function report=addCheck(report,name,passed,detail)
passed=logical(passed);
report.checks(end+1)=struct('name',name,'passed',passed,'detail',char(string(detail)));
if ~passed, report.errors{end+1}=sprintf('%s: %s',name,char(string(detail))); end
end

function report=finish(report)
report.passed=~isempty(report.checks) && all([report.checks.passed]) && isempty(report.errors);
end

function name=stem(result)
name=sprintf('static-v1_n%d_r%04d', ...
    result.config.simulation.numUE,result.config.simulation.realizationId);
end

function value=ternary(condition,yes,no)
if condition, value=yes; else, value=no; end
end

function removeTemporary(path)
if isfile(path), delete(path); end
end

function ok=runtimeValid(value)
names={'runtimeVersion','resultSchemaVersion','canonicalConfigSha256', ...
    'modelSha256','policySha256','inputSha256','runnerSha256'};
ok=isstruct(value) && isscalar(value) && all(isfield(value,names));
if ~ok, return; end
ok=isequal(double(value.runtimeVersion),1) && isequal(double(value.resultSchemaVersion),2);
hashes=[{'configSha256','sourceSha256','calibrationSha256'} names(3:end)];
for k=1:numel(hashes)
    ok=ok && isfield(value,hashes{k}) && ...
        ~isempty(regexp(char(string(value.(hashes{k}))),'^[0-9a-fA-F]{64}$','once'));
end
end
