classdef TestResultMetadata < matlab.unittest.TestCase
    methods (Test)
        function staticResultRecordsTheOverallNetworkBand(t)
            cfg=nbiot.config.defaultConfig();
            cfg.simulation.numUE=1;
            cfg.simulation.durationTicks=1;
            simulator=nbiot.NBIoTSimulator(cfg,[],localDevelopment());

            result=simulator.result();

            t.verifyEqual(result.network.carrierFrequencyHz,cfg.channel.carrierHz);
            t.verifyEqual(result.network.bandwidthHz,180000);
            folder=tempname; mkdir(folder);
            t.addTeardown(@() removeFolder(folder));
            path=nbiot.results.saveResult(result,folder);
            saved=load(path,'result');
            t.verifyEqual(saved.result.network,result.network);
            summaryPath=fullfile(folder,'static-v1_n1_r0000_summary.csv');
            t.verifyTrue(isfile(summaryPath));
            summary=readtable(summaryPath,'VariableNamingRule','preserve');
            t.verifyEqual(height(summary),1);
            t.verifyEqual(string(summary.method),"Static");
            t.verifyEqual(summary.numUE,1);
            t.verifyTrue(ismember('kpi_created',summary.Properties.VariableNames));
        end

        function adaptiveResultCarriesModelScoresOnlyForItsVerifiedPackage(t)
            folder=tempname; mkdir(folder);
            t.addTeardown(@() removeFolder(folder));
            modelFile=writeModelPackage(folder);
            writeTrainingMetrics(folder,modelFile);
            cfg=nbiot.config.defaultConfig();
            cfg.simulation.numUE=1;
            cfg.simulation.durationTicks=1;
            cfg.policy.name='Adaptive-P';
            options=struct('model',modelFile,'allowDevelopmentModel',true);
            simulator=nbiot.NBIoTSimulator( ...
                cfg,[],localDevelopment(),options);

            result=simulator.result();
            schema=nbiot.dataset.featureSchema();

            t.verifyEqual(result.controllerModel.modelName,'linearRegression');
            t.verifyEqual(result.controllerModel.targetName,'meanRaUe');
            t.verifyEqual(result.controllerModel.featureNames,schema.observationNames(5:end));
            t.verifyEqual(result.controllerModel.seed,17);
            t.verifyEqual(result.controllerModel.sha256,nbiot.ml.fileSha256(modelFile));
            t.verifyEqual(string(result.controllerModel.evaluationMetrics.split), ...
                ["train";"validation";"test"]);
            t.verifyEqual(result.controllerModel.evaluationMetrics.mae,[.2;.3;.4]);
            t.verifyEqual(result.controllerModel.evaluationStatus,'verified');
            outputFolder=tempname; mkdir(outputFolder);
            t.addTeardown(@() removeFolder(outputFolder));
            path=nbiot.results.saveResult(result,outputFolder);
            saved=load(path,'result');
            t.verifyEqual(saved.result.controllerModel.evaluationMetrics, ...
                result.controllerModel.evaluationMetrics);
            t.verifyEqual(saved.result.controllerModel.sha256, ...
                result.controllerModel.sha256);
        end

        function staticAndUnscoredRunsDeclareModelEvaluationUnavailable(t)
            cfg=nbiot.config.defaultConfig();
            cfg.simulation.numUE=1;
            cfg.simulation.durationTicks=1;
            simulator=nbiot.NBIoTSimulator(cfg,[],localDevelopment());

            result=simulator.result();

            t.verifyEqual(result.controllerModel.evaluationStatus,'not-applicable');
            t.verifyEmpty(result.controllerModel.evaluationMetrics);
        end
    end
end

function modelFile=writeModelPackage(folder)
schema=nbiot.dataset.featureSchema();
featureNames=schema.observationNames(5:end);
keyNames=schema.observationNames(1:4);
bundle=struct('formatVersion','load-model-bundle-v1', ...
    'modelName','linearRegression','model',FixedRegressionPredictor(2), ...
    'schemaVersion',schema.version,'featureNames',{featureNames}, ...
    'keyNames',{keyNames},'targetName','meanRaUe', ...
    'transform',struct('median',zeros(1,numel(featureNames)), ...
        'mean',zeros(1,numel(featureNames)),'scale',ones(1,numel(featureNames))), ...
    'trainingIds',[1 2],'validationIds',3,'testIds',4,'seed',17, ...
    'status','development','dataKind','development-fixture');
modelFile=fullfile(folder,'linearRegression.mat');
save(modelFile,'bundle');
hash=nbiot.ml.fileSha256(modelFile);
modelManifest=struct('formatVersion',bundle.formatVersion, ...
    'artifactFile','linearRegression.mat','artifactSha256',hash, ...
    'modelName',bundle.modelName,'schemaVersion',bundle.schemaVersion, ...
    'targetName',bundle.targetName,'featureNames',{featureNames}, ...
    'keyNames',{keyNames},'seed',bundle.seed,'status',bundle.status, ...
    'trainingIds',bundle.trainingIds,'validationIds',bundle.validationIds, ...
    'testIds',bundle.testIds);
writeJson(fullfile(folder,'linearRegression.json'),modelManifest);
end

function writeTrainingMetrics(folder,modelFile)
metrics=table(repmat("linearRegression",3,1), ...
    ["train";"validation";"test"],[4;2;2],[2;1;1], ...
    [.2;.3;.4],[.3;.4;.5], ...
    'VariableNames',{'model','split','sampleCount','idCount','mae','rmse'});
writetable(metrics,fullfile(folder,'metrics.csv'));
[~,base,extension]=fileparts(modelFile);
trainingManifest=struct('modelNames',{{'linearRegression'}}, ...
    'artifactFiles',{{[base extension]}}, ...
    'artifactSha256',{{nbiot.ml.fileSha256(modelFile)}});
writeJson(fullfile(folder,'training-manifest.json'),trainingManifest);
end

function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(jsonencode(value),'UTF-8'),'uint8');
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
