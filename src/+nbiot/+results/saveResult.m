function destination=saveResult(result,folder,metadata)
%SAVERESULT Save legacy exports, or transactionally commit a manifested case.
if nargin<2 || isempty(folder), folder=result.config.logging.outputFolder; end
if nargin<3
    destination=saveLegacyResult(result,folder);
else
    destination=saveCaseResult(result,folder,metadata);
end
end

function destination=saveLegacyResult(result,folder)
if ~isfolder(folder), mkdir(folder); end
runName=exportStem(result);
destination=fullfile(folder,[runName '.mat']); temporary=[tempname(folder) '.mat'];
cleanup=onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
save(temporary,'result','-v7.3');
check=whos('-file',temporary);
assert(any(strcmp({check.name},'result')),'nbiot:results:Save','MAT result missing.');
[ok,message]=movefile(temporary,destination,'f');
if ~ok, error('nbiot:results:Save','%s',message); end
writeExports(result,folder,runName);
end

function destination=saveCaseResult(result,folder,metadata)
required={'caseKey','configSha256','sourceSha256','calibrationSha256','environment'};
for k=1:numel(required)
    if ~isfield(metadata,required{k})
        error('nbiot:results:Metadata','Missing case metadata field %s.',required{k});
    end
end
hashFields={'configSha256','sourceSha256','calibrationSha256'};
for k=1:numel(hashFields)
    value=char(string(metadata.(hashFields{k})));
    if isempty(regexp(value,'^[0-9a-fA-F]{64}$','once'))
        error('nbiot:results:Metadata','%s must be a SHA-256 hex digest.',hashFields{k});
    end
end
if ~strcmp(nbiot.results.configSha256(result.config),metadata.configSha256)
    error('nbiot:results:Metadata','Configuration hash does not match the result.');
end
if ~isfolder(folder), mkdir(folder); end
items=dir(folder); items=items(~ismember({items.name},{'.','..'}));
if ~isempty(items)
    error('nbiot:results:DuplicateCase', ...
        'Refusing to overwrite non-empty case directory for key %s.',metadata.caseKey);
end
runName=exportStem(result); destination=fullfile(folder,[runName '.mat']);
temporary=[tempname(folder) '.mat'];
cleanup=onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
caseMetadata=identity(metadata,result.status);
configSnapshot=result.config; resultStatus=result.status;
kpiSummary=result.kpiSummary; environmentSnapshot=result.environment;
save(temporary,'result','caseMetadata','configSnapshot','resultStatus', ...
    'kpiSummary','environmentSnapshot','-v7.3');
check=whos('-file',temporary);
requiredVariables={'result','caseMetadata','configSnapshot','resultStatus', ...
    'kpiSummary','environmentSnapshot'};
if ~all(ismember(requiredVariables,{check.name}))
    error('nbiot:results:Save','MAT result is missing required snapshot variables.');
end
[ok,message]=movefile(temporary,destination,'f');
if ~ok, error('nbiot:results:Save','%s',message); end
tables=writeExports(result,folder,runName);

report=nbiot.results.verifyCase(folder,metadata,result,false);
if ~report.passed
    error('nbiot:results:Verify','Staged case did not pass readback: %s',strjoin(report.errors,'; '));
end
marker=identity(metadata,result.status);
marker.manifestVersion=1; marker.resultFile=[runName '.mat'];
marker.exportStem=runName; marker.tables=tables;
marker.balances=balanceSnapshot(result.kpiSummary);
marker.elapsedSeconds=elapsedSeconds(result);
names=[{marker.resultFile} {tables.file}];
files=repmat(struct('name','','bytes',0,'sha256',''),numel(names),1);
for k=1:numel(names)
    path=fullfile(folder,names{k}); d=dir(path);
    if isempty(d), error('nbiot:results:Save','Missing staged export %s.',names{k}); end
    files(k)=struct('name',names{k},'bytes',d.bytes,'sha256',hashFile(path));
end
marker.files=files;
markerPath=fullfile(folder,'case-complete.json');
temporaryMarker=[tempname(folder) '.json'];
markerCleanup=onCleanup(@() removeTemporary(temporaryMarker)); %#ok<NASGU>
fid=fopen(temporaryMarker,'wb');
if fid<0, error('nbiot:results:Save','Cannot write completion marker.'); end
writeCleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,unicode2native(jsonencode(marker),'UTF-8'),'uint8');
clear writeCleanup
[ok,message]=movefile(temporaryMarker,markerPath,'f');
if ~ok, error('nbiot:results:Save','Cannot commit completion marker: %s',message); end

report=nbiot.results.verifyCase(folder,metadata);
if ~report.passed
    delete(markerPath);
    error('nbiot:results:Verify','Committed case failed integrity check: %s',strjoin(report.errors,'; '));
end
end

function runName=exportStem(result)
runName=sprintf('static-v1_n%d_r%04d', ...
    result.config.simulation.numUE,result.config.simulation.realizationId);
end

function tables=writeExports(result,folder,runName)
tableData={result.ueSummary,result.kpiTimeSeries,result.dataset.observations, ...
    result.dataset.targets,result.resourceUsage,result.dataset.manifest};
suffixes={'_ue.csv','_kpi.csv','_observations.csv','_targets.csv', ...
    '_resources.csv','_split.csv'};
tables=repmat(struct('file','','variableNames',{{}},'rows',0),numel(suffixes),1);
for k=1:numel(suffixes)
    file=[runName suffixes{k}]; writetable(tableData{k},fullfile(folder,file));
    tables(k)=struct('file',file,'variableNames',{tableData{k}.Properties.VariableNames}, ...
        'rows',height(tableData{k}));
end
end

function metadata=identity(input,status)
metadata=struct('caseKey',char(string(input.caseKey)), ...
    'configSha256',char(string(input.configSha256)), ...
    'sourceSha256',char(string(input.sourceSha256)), ...
    'calibrationSha256',char(string(input.calibrationSha256)), ...
    'environment',input.environment,'status',char(string(status)));
end

function balances=balanceSnapshot(kpi)
names={'created','delivered','dropped','unfinished', ...
    'raStarted','raSuccess','raFailed','raUnfinished'};
for k=1:numel(names)
    if ~isfield(kpi,names{k})
        error('nbiot:results:Balance','KPI summary lacks %s.',names{k});
    end
end
balances=struct();
for k=1:numel(names), balances.(names{k})=kpi.(names{k}); end
end

function value=elapsedSeconds(result)
value=0;
if isfield(result,'profiling') && isfield(result.profiling,'elapsedSeconds')
    value=double(result.profiling.elapsedSeconds);
end
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

function removeTemporary(path)
if isfile(path), delete(path); end
end
