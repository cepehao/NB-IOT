function metrics=loadModelEvaluationMetrics(modelFile,bundle)
%LOADMODELEVALUATIONMETRICS Read scores only when they match the model hash.
metrics=emptyMetrics();
if ~(ischar(modelFile)||(isstring(modelFile)&&isscalar(modelFile)))|| ...
        ~isstruct(bundle)||~isscalar(bundle)||~isfield(bundle,'modelName')
    return;
end
modelFile=char(string(modelFile));
[folder,base,extension]=fileparts(modelFile);
manifestFile=fullfile(folder,'training-manifest.json');
metricsFile=fullfile(folder,'metrics.csv');
if ~isfile(modelFile)||~isfile(manifestFile)||~isfile(metricsFile)
    return;
end
try
    manifest=jsondecode(fileread(manifestFile));
    required={'modelNames','artifactFiles','artifactSha256'};
    if ~isstruct(manifest)||~all(isfield(manifest,required)), return; end
    modelNames=string(manifest.modelNames(:));
    artifactFiles=string(manifest.artifactFiles(:));
    artifactHashes=string(manifest.artifactSha256(:));
    if numel(modelNames)~=numel(artifactFiles)||numel(modelNames)~=numel(artifactHashes)
        return;
    end
    artifact=[base extension];
    index=find(modelNames==string(bundle.modelName)&artifactFiles==string(artifact),1);
    if isempty(index)||~strcmpi(char(artifactHashes(index)), ...
            nbiot.ml.fileSha256(modelFile))
        return;
    end
    source=readtable(metricsFile,'TextType','string');
    required={'model','split','sampleCount','idCount','mae','rmse'};
    if ~all(ismember(required,source.Properties.VariableNames)), return; end
    modelRows=string(source.model)==string(bundle.modelName);
    splits=string(source.split);
    selected=modelRows&ismember(splits,["train","validation","test"]);
    numericRows=isfinite(source.sampleCount)&isfinite(source.idCount)& ...
        isfinite(source.mae)&isfinite(source.rmse)&source.sampleCount>0&source.idCount>0;
    selected=selected&numericRows;
    metrics=source(selected,required(2:end));
catch
    metrics=emptyMetrics();
end
end

function value=emptyMetrics()
value=table(strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'split','sampleCount','idCount','mae','rmse'});
end
