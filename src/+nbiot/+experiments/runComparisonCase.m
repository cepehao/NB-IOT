function record=runComparisonCase(cfg,method,caseFolder,options)
%RUNCOMPARISONCASE Run or resume one method for a paired external realization.
if nargin<4||~isstruct(options)||~isscalar(options)
    error('nbiot:experiments:ComparisonCaseOptions','A scalar case-options structure is required.');
end
method=char(string(method));
if ~ismember(method,{'Static','Adaptive-P','Adaptive-RA/DT'})
    error('nbiot:experiments:ComparisonMethod','Unsupported comparison method %s.',method);
end
if ~isfolder(caseFolder)&&isfile(caseFolder)
    error('nbiot:experiments:ComparisonCaseFolder','Case path must be a folder.');
end
cfg.policy.name=method;
if strcmp(method,'Adaptive-P')||strcmp(method,'Adaptive-RA/DT')
    cfg.policy.windowTicks=500;
    cfg.dataset.windowTicks=500;
end
cfg.logging.outputFolder=caseFolder;
runtimeOptions=runtimeIdentityOptions(options,method);
metadata=nbiot.experiments.runtimeManifest(cfg,runtimeOptions);

if isfield(options,'resume')&&options.resume&&isfolder(caseFolder)
    attempts=dir(fullfile(caseFolder,'run-*'));
    attempts=attempts([attempts.isdir]);
    for k=numel(attempts):-1:1
        candidate=fullfile(attempts(k).folder,attempts(k).name);
        report=nbiot.results.verifyCase(candidate,metadata);
        if report.passed&&strcmp(report.status,'completed')
            marker=jsondecode(fileread(fullfile(candidate,'case-complete.json')));
            resultPath=fullfile(candidate,char(string(marker.resultFile)));
            saved=load(resultPath,'kpiSummary');
            record=caseRecord(cfg,method,report.status,double(marker.elapsedSeconds), ...
                resultPath,metadata,saved.kpiSummary,'');
            return;
        end
    end
end

runner=[];
if isfield(options,'runExperimentFcn'), runner=options.runExperimentFcn; end
meta=nbiot.experiments.runStaticCase(cfg,caseFolder,metadata,runner,runtimeOptions);
saved=load(meta.resultFile,'kpiSummary');
record=caseRecord(cfg,method,meta.status,meta.elapsedSeconds,meta.resultFile, ...
    meta,saved.kpiSummary,'');
end

function runtimeOptions=runtimeIdentityOptions(options,method)
root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
runtimeOptions=struct('projectRoot',root,'execution',options.execution, ...
    'calibrationFile',options.calibrationFile,'scenario',options.scenario, ...
    'controllerPolicy',options.controllerPolicy,'runner',[]);
if ~isempty(options.modelFile)
    runtimeOptions.modelFiles={options.modelFile};
else
    runtimeOptions.modelFiles={};
end
runner=[];
if isfield(options,'runExperimentFcn'), runner=options.runExperimentFcn; end
runtimeOptions.runner=runner;
if ~isempty(runner)
    runtimeOptions.runnerFiles=options.runnerFiles;
    runtimeOptions.runnerInputs=options.runnerInputs;
    runtimeOptions.runnerDependenciesDeclared=options.runnerDependenciesDeclared;
end
if ismember(method,{'Adaptive-P','Adaptive-RA/DT'})
    controllerOptions=struct('model',options.modelFile, ...
        'allowDevelopmentModel',options.allowDevelopmentModel);
    if ~isempty(fieldnames(options.controllerPolicy))
        controllerOptions.policy=options.controllerPolicy;
    end
    runtimeOptions.controllerOptions=controllerOptions;
end
end

function record=caseRecord(cfg,method,status,elapsedSeconds,resultFile,metadata,kpi,errorMessage)
record=struct('numUE',double(cfg.simulation.numUE), ...
    'burstDurationTicks',double(cfg.traffic.burstDurationTicks), ...
    'realizationId',double(cfg.simulation.realizationId),'method',string(method), ...
    'status',string(status),'elapsedSeconds',double(elapsedSeconds), ...
    'resultFile',string(resultFile),'caseKey',string(metadata.caseKey), ...
    'inputSha256',string(fieldOr(metadata,'inputSha256','')), ...
    'configSha256',string(metadata.configSha256), ...
    'sourceSha256',string(metadata.sourceSha256), ...
    'calibrationSha256',string(metadata.calibrationSha256), ...
    'errorIdentifier',"",'errorMessage',string(errorMessage));
comparisonMetrics=nbiot.experiments.comparisonKpis(kpi,method);
names=fieldnames(comparisonMetrics);
for k=1:numel(names), record.(names{k})=comparisonMetrics.(names{k}); end
end

function value=fieldOr(input,name,fallback)
value=fallback;
if isstruct(input)&&isfield(input,name), value=input.(name); end
end
