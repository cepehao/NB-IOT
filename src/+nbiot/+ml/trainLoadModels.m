function [bundles,report]=trainLoadModels(data,options)
%TRAINLOADMODELS Fit four fixed load regressors using ID-separated groups.
if nargin<2||isempty(options), options=mlTrainingDefaults(); end
options=validatedOptions(options);
requireStatisticsToolbox();
[x,y,ids,groups,schema,kind,allocationsVerified]=validateTrainingData(data);
outputFolder=prepareOutputFolder(options.outputFolder);

trainMask=groups=="train";
validationMask=groups=="validation";
testMask=groups=="test";
trainX=x(trainMask,:); trainY=y(trainMask);
medians=median(trainX,1,'omitnan');
if any(~isfinite(medians))
    error('nbiot:ml:TrainingFeatureMissing', ...
        'A feature is missing in every training row; it cannot be imputed safely.');
end
trainImputed=imputeFeatures(trainX,medians);
featureMean=mean(trainImputed,1);
featureScale=std(trainImputed,0,1);
featureScale(~isfinite(featureScale)|featureScale<=eps)=1;
transform=struct('median',medians,'mean',featureMean,'scale',featureScale, ...
    'method','training-median imputation then training-only z-score');
normalized=normalizeFeatures(x,transform);

modelNames={'linearRegression','decisionTree','randomForest','gradientBoosting'};
bundleTemplate=struct('name','','bundle',struct(),'file','','sha256','','manifestFile','');
bundles=repmat(bundleTemplate,1,numel(modelNames));
metricRows=cell(0,9); validationMae=nan(1,numel(modelNames)); trainingSeconds=zeros(1,numel(modelNames));
oldRng=rng; restoreRng=onCleanup(@() rng(oldRng));
rng(options.seed,'twister');

for modelIndex=1:numel(modelNames)
    modelName=modelNames{modelIndex}; started=tic;
    model=fitOne(modelName,normalized(trainMask,:),trainY,options);
    trainingSeconds(modelIndex)=toc(started);
    package=struct();
    package.formatVersion='load-model-bundle-v1';
    package.modelName=modelName; package.model=model;
    package.schemaVersion=schema.version;
    package.featureNames=schema.inputNames;
    package.keyNames=schema.keyNames;
    package.targetName='meanRaUe';
    package.transform=transform;
    package.trainingIds=unique(ids(trainMask)).';
    package.validationIds=unique(ids(validationMask)).';
    package.testIds=unique(ids(testMask)).';
    package.seed=options.seed;
    package.status='development';
    package.dataKind=kind;
    package.allocationsVerified=allocationsVerified;
    package.modelClass=class(model);
    package.modelOptions=modelOptions(modelName,options);
    package.matlabRelease=version('-release');
    package.toolboxVersion=toolboxVersion();

    bundles(modelIndex).name=modelName;
    bundles(modelIndex).bundle=package;
    if ~isempty(outputFolder)
        [artifact,sidecar,digest]=writePackage(package,outputFolder);
        bundles(modelIndex).file=artifact;
        bundles(modelIndex).manifestFile=sidecar;
        bundles(modelIndex).sha256=digest;
    end

    for splitIndex=1:3
        if splitIndex==1
            splitName='train'; mask=trainMask;
        elseif splitIndex==2
            splitName='validation'; mask=validationMask;
        else
            splitName='test'; mask=testMask;
        end
        [row,mae]=score(modelName,splitName,model,normalized(mask,:),y(mask), ...
            ids(mask),trainingSeconds(modelIndex));
        metricRows(end+1,:)=row; %#ok<AGROW>
        if splitIndex==2, validationMae(modelIndex)=mae; end
    end
end

baseline=mean(trainY);
for splitIndex=1:3
    if splitIndex==1, splitName='train'; mask=trainMask;
    elseif splitIndex==2, splitName='validation'; mask=validationMask;
    else, splitName='test'; mask=testMask;
    end
    [row,~]=score('trainMean',splitName,[],normalized(mask,:),y(mask),ids(mask),0,baseline);
    metricRows(end+1,:)=row; %#ok<AGROW>
end
metrics=cell2table(metricRows,'VariableNames', ...
    {'model','split','sampleCount','idCount','mae','rmse','bias','predictionSeconds','trainingSeconds'});
[~,bestIndex]=min(validationMae);
report=struct('metrics',metrics,'bestValidationModel',modelNames{bestIndex}, ...
    'baselineValue',baseline,'seed',options.seed,'dataKind',kind, ...
    'allocationsVerified',allocationsVerified,'schemaVersion',schema.version, ...
    'targetName','meanRaUe','trainingIds',unique(ids(trainMask)).', ...
    'validationIds',unique(ids(validationMask)).','testIds',unique(ids(testMask)).', ...
    'selectionRule','lowest validation MAE; test results are not used for selection', ...
    'status','development');
if ~isempty(outputFolder), writeTrainingReport(report,bundles,outputFolder); end
end

function options=validatedOptions(value)
defaults=mlTrainingDefaults();
if ~isstruct(value)||~isscalar(value), error('nbiot:ml:Options','Training options must be a scalar structure.'); end
unknown=setdiff(fieldnames(value),fieldnames(defaults));
if ~isempty(unknown), error('nbiot:ml:Options','Unsupported option: %s',unknown{1}); end
options=defaults;
names=fieldnames(value);
for k=1:numel(names), options.(names{k})=value.(names{k}); end
integerFields={'seed','treeMaxNumSplits','treeMinLeafSize','forestNumTrees', ...
    'forestMinLeafSize','boostNumLearningCycles','boostMaxNumSplits'};
for k=1:numel(integerFields)
    field=integerFields{k}; number=options.(field);
    if ~isnumeric(number)||~isscalar(number)||~isreal(number)||~isfinite(number)|| ...
            number<1||number~=fix(number)
        error('nbiot:ml:Options','%s must be a positive integer.',field);
    end
end
if options.seed>4294967295
    error('nbiot:ml:Options','Seed must be in 0:4294967295.');
end
rate=options.boostLearnRate;
if ~isnumeric(rate)||~isscalar(rate)||~isreal(rate)||~isfinite(rate)||rate<=0||rate>1
    error('nbiot:ml:Options','boostLearnRate must be greater than zero and no greater than one.');
end
folder=options.outputFolder;
if isstring(folder)&&isscalar(folder), folder=char(folder); end
if ~ischar(folder)||(~isempty(folder)&&isempty(strtrim(folder)))
    error('nbiot:ml:Options','outputFolder must be empty or a non-empty path.');
end
options.outputFolder=folder;
end

function requireStatisticsToolbox()
if isempty(ver('stats'))||~license('test','Statistics_Toolbox')
    error('nbiot:ml:ToolboxUnavailable', ...
        'Statistics and Machine Learning Toolbox and its license are required for training.');
end
required={'fitlm','fitrtree','TreeBagger','fitrensemble'};
for k=1:numel(required)
    if isempty(which(required{k}))
        error('nbiot:ml:ToolboxUnavailable','Required training function %s is unavailable.',required{k});
    end
end
end

function [x,y,ids,groups,schema,kind,allocationsVerified]=validateTrainingData(data)
required={'features','targets','rowInfo','schema','manifest'};
if ~isstruct(data)||~isscalar(data)||~all(isfield(data,required))
    error('nbiot:ml:Data','Training data is missing required tables or metadata.');
end
schema=data.schema;
if ~isstruct(schema)||~isfield(schema,'version')||~isfield(schema,'inputNames')|| ...
        ~isfield(schema,'targetName')||~strcmp(char(string(schema.targetName)),'meanRaUe')
    error('nbiot:ml:FeatureSchema','Training schema must name the meanRaUe target and ordered inputs.');
end
schema.inputNames=cellstr(string(schema.inputNames));
if ~isfield(schema,'keyNames')
    schema.keyNames={'realizationId','windowId','startTick','endTick'};
end
schema.keyNames=cellstr(string(schema.keyNames));
currentSchema=nbiot.dataset.featureSchema();
if ~strcmp(char(string(schema.version)),currentSchema.version)
    error('nbiot:ml:FeatureSchema', ...
        'Training requires the current BS-observation schema %s.',currentSchema.version);
end
if ~istable(data.features)||~isequal(data.features.Properties.VariableNames,schema.inputNames)
    error('nbiot:ml:FeatureSchema','Feature columns must exactly match the ordered schema whitelist.');
end
if ~istable(data.targets)||~ismember('meanRaUe',data.targets.Properties.VariableNames)|| ...
        ~istable(data.rowInfo)||~all(ismember({'realizationId','split'},data.rowInfo.Properties.VariableNames))
    error('nbiot:ml:Data','Targets and rowInfo need meanRaUe, realizationId and split columns.');
end
rowCount=height(data.features);
if rowCount<3||height(data.targets)~=rowCount||height(data.rowInfo)~=rowCount
    error('nbiot:ml:Data','Features, targets and rowInfo must have the same nontrivial row count.');
end
x=data.features{:,:}; y=data.targets.meanRaUe;
ids=data.rowInfo.realizationId; groups=string(data.rowInfo.split);
if ~isnumeric(x)||~isnumeric(y)||~isnumeric(ids)||~iscolumn(y)||~iscolumn(ids)|| ...
        any(isinf(x),'all')||any(~isfinite(y))||any(~isfinite(ids))
    error('nbiot:ml:Data','Features may contain NaN, but targets and realization IDs must be finite numeric values.');
end
if any(y<0)||any(ids<0)||any(ids~=fix(ids))||numel(groups)~=rowCount
    error('nbiot:ml:Data','Targets and realization IDs must be nonnegative; group labels must match rows.');
end
if any(~ismember(groups,["train","validation","test"]))
    error('nbiot:ml:Split','Use only train, validation and test groups for model training.');
end
uniqueIds=unique(ids);
for k=1:numel(uniqueIds)
    if numel(unique(groups(ids==uniqueIds(k))))~=1
        error('nbiot:ml:GroupLeakage','Each realization ID must belong to only one split.');
    end
end
for group=["train","validation","test"]
    if ~any(groups==group), error('nbiot:ml:Split','The %s group must contain at least one row.',group); end
end
if ~isstruct(data.manifest)||~isfield(data.manifest,'kind')
    error('nbiot:ml:DataPurpose','Dataset purpose is required.');
end
kind=char(string(data.manifest.kind));
allocationsVerified=isfield(data.manifest,'allocationsVerified')&& ...
    isequal(data.manifest.allocationsVerified,true);
if ismember('experimentRole',data.rowInfo.Properties.VariableNames) && ...
        any(string(data.rowInfo.experimentRole)=="final-comparison")
    error('nbiot:ml:FinalComparison', ...
        'Final comparison realizations must never enter model training or model evaluation.');
end
if strcmp(kind,'candidate-training')
    if ~allocationsVerified
        error('nbiot:ml:DataPurpose','Candidate training data must have verified allocation roles.');
    end
    validateCandidateRoles(data,groups,ids);
elseif ~strcmp(kind,'development-fixture')
    error('nbiot:ml:DataPurpose', ...
        'Only verified candidate data or explicitly marked development fixtures can train models.');
end
end

function validateCandidateRoles(data,groups,ids)
if ~isfield(data.manifest,'experimentRolesExplicit')|| ...
        ~isequal(data.manifest.experimentRolesExplicit,true)|| ...
        ~ismember('experimentRole',data.rowInfo.Properties.VariableNames)
    error('nbiot:ml:RoleManifest', ...
        'Candidate training data requires explicit experiment roles for every row.');
end
roles=string(data.rowInfo.experimentRole);
if ~iscolumn(roles)||numel(roles)~=numel(groups)|| ...
        any(~ismember(roles,["training","validation","model-test"]))
    error('nbiot:ml:RoleManifest','Candidate training data contains an unsupported experiment role.');
end
expected=groups;
expected(groups=="train")="training";
expected(groups=="test")="model-test";
if any(roles~=expected)
    error('nbiot:ml:RoleManifest','Experiment roles do not match the train/validation/test groups.');
end

if ~isfield(data.manifest,'assignments')||~istable(data.manifest.assignments)|| ...
        ~all(ismember({'externalRealizationId','split','experimentRole'}, ...
            data.manifest.assignments.Properties.VariableNames))
    error('nbiot:ml:RoleManifest','Candidate dataset manifest must preserve explicit ID roles.');
end
assignments=data.manifest.assignments;
assignmentIds=assignments.externalRealizationId;
assignmentSplits=string(assignments.split);
assignmentRoles=string(assignments.experimentRole);
if ~isnumeric(assignmentIds)||~iscolumn(assignmentIds)|| ...
        numel(unique(assignmentIds))~=numel(assignmentIds)|| ...
        numel(assignmentSplits)~=numel(assignmentIds)|| ...
        numel(assignmentRoles)~=numel(assignmentIds)
    error('nbiot:ml:RoleManifest','Candidate dataset ID assignments are malformed.');
end
uniqueIds=unique(ids);
for idIndex=1:numel(uniqueIds)
    at=find(assignmentIds==uniqueIds(idIndex));
    rowAt=ids==uniqueIds(idIndex);
    if numel(at)~=1||numel(unique(groups(rowAt)))~=1|| ...
            assignmentSplits(at)~=unique(groups(rowAt))|| ...
            assignmentRoles(at)~=unique(roles(rowAt))
        error('nbiot:ml:RoleManifest','A row role does not match the declared ID assignment.');
    end
end
end

function folder=prepareOutputFolder(folder)
if isempty(folder), return; end
if isfile(folder), error('nbiot:ml:OutputFolder','Output path is already a file.'); end
if isfolder(folder)
    contents=dir(folder); contents=contents(~ismember({contents.name},{'.','..'}));
    if ~isempty(contents)
        error('nbiot:ml:OutputFolder','Refusing to overwrite a non-empty model folder.');
    end
else
    [ok,message]=mkdir(folder);
    if ~ok, error('nbiot:ml:OutputFolder','Cannot create model folder: %s',message); end
end
end

function x=imputeFeatures(x,medians)
for column=1:size(x,2)
    missing=isnan(x(:,column));
    x(missing,column)=medians(column);
end
end

function normalized=normalizeFeatures(x,transform)
x=imputeFeatures(double(x),transform.median);
normalized=(x-transform.mean)./transform.scale;
end

function model=fitOne(name,x,y,options)
switch name
    case 'linearRegression'
        model=fitlm(x,y);
    case 'decisionTree'
        model=fitrtree(x,y,'MaxNumSplits',options.treeMaxNumSplits, ...
            'MinLeafSize',options.treeMinLeafSize);
    case 'randomForest'
        model=TreeBagger(options.forestNumTrees,x,y,'Method','regression', ...
            'MinLeafSize',options.forestMinLeafSize);
    case 'gradientBoosting'
        learner=templateTree('MaxNumSplits',options.boostMaxNumSplits, ...
            'MinLeafSize',options.treeMinLeafSize,'Reproducible',true);
        model=fitrensemble(x,y,'Method','LSBoost', ...
            'NumLearningCycles',options.boostNumLearningCycles, ...
            'LearnRate',options.boostLearnRate,'Learners',learner);
    otherwise
        error('nbiot:ml:ModelType','Unsupported load model: %s',name);
end
end

function parameters=modelOptions(name,options)
switch name
    case 'linearRegression'
        parameters=struct('fit','least-squares linear model');
    case 'decisionTree'
        parameters=struct('maxNumSplits',options.treeMaxNumSplits, ...
            'minLeafSize',options.treeMinLeafSize);
    case 'randomForest'
        parameters=struct('numTrees',options.forestNumTrees, ...
            'minLeafSize',options.forestMinLeafSize,'method','regression');
    otherwise
        parameters=struct('method','LSBoost', ...
            'numLearningCycles',options.boostNumLearningCycles, ...
            'learnRate',options.boostLearnRate,'maxNumSplits',options.boostMaxNumSplits, ...
            'minLeafSize',options.treeMinLeafSize);
end
end

function [row,mae]=score(modelName,splitName,model,x,y,ids,trainingSeconds,baseline)
if nargin<8
    started=tic; prediction=predict(model,x); predictionSeconds=toc(started);
else
    started=tic; prediction=repmat(baseline,numel(y),1); predictionSeconds=toc(started);
end
prediction=double(prediction(:)); errorValues=prediction-double(y(:));
mae=mean(abs(errorValues)); rmse=sqrt(mean(errorValues.^2)); bias=mean(errorValues);
row={string(modelName),string(splitName),double(numel(y)),double(numel(unique(ids))), ...
    mae,rmse,bias,predictionSeconds,trainingSeconds};
end

function [artifact,sidecar,digest]=writePackage(bundle,folder)
artifact=fullfile(folder,[bundle.modelName '.mat']);
sidecar=fullfile(folder,[bundle.modelName '.json']);
save(artifact,'bundle','-v7.3');
digest=nbiot.ml.fileSha256(artifact);
manifest=struct('formatVersion',bundle.formatVersion, ...
    'artifactFile',[bundle.modelName '.mat'],'artifactSha256',digest, ...
    'modelName',bundle.modelName,'schemaVersion',bundle.schemaVersion, ...
    'targetName',bundle.targetName,'featureNames',{bundle.featureNames}, ...
    'keyNames',{bundle.keyNames},'seed',bundle.seed,'status',bundle.status, ...
    'trainingIds',bundle.trainingIds,'validationIds',bundle.validationIds,'testIds',bundle.testIds);
writeJson(sidecar,manifest);
end

function writeTrainingReport(report,bundles,folder)
writetable(report.metrics,fullfile(folder,'metrics.csv'));
names={bundles.name}; files={bundles.file}; hashes={bundles.sha256};
manifest=struct('formatVersion','load-training-report-v1','dataKind',report.dataKind, ...
    'status',report.status,'targetName',report.targetName,'schemaVersion',report.schemaVersion, ...
    'seed',report.seed,'bestValidationModel',report.bestValidationModel, ...
    'selectionRule',report.selectionRule,'modelNames',{names}, ...
    'artifactFiles',{cellfun(@localName,files,'UniformOutput',false)}, ...
    'artifactSha256',{hashes},'trainingIds',report.trainingIds, ...
    'validationIds',report.validationIds,'testIds',report.testIds);
writeJson(fullfile(folder,'training-manifest.json'),manifest);
save(fullfile(folder,'training-report.mat'),'report','-v7.3');
end

function name=localName(path)
if isempty(path), name=''; else, [~,base,extension]=fileparts(path); name=[base extension]; end
end

function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8');
if fid<0, error('nbiot:ml:OutputFolder','Cannot write model metadata.'); end
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(jsonencode(value,'PrettyPrint',true),'UTF-8'),'uint8');
end

function value=toolboxVersion()
products=ver('stats');
if isempty(products), value='unavailable'; else, value=products(1).Version; end
end
