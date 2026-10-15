classdef TestLoadModels < matlab.unittest.TestCase
    methods (Test)
        function trainingRejectsHistoricalFeatureSchema(t)
            data=smallTrainingFixture();
            data.schema.version='static-v1.0';
            options=mlTrainingDefaults();
            options.forestNumTrees=2;
            options.boostNumLearningCycles=2;

            t.verifyError(@() nbiot.ml.trainLoadModels(data,options), ...
                'nbiot:ml:FeatureSchema');
        end

        function candidateTrainingRequiresExplicitExperimentRoles(t)
            data=smallTrainingFixture();
            data.manifest.kind='candidate-training';
            data.manifest.allocationsVerified=true;
            options=mlTrainingDefaults();

            t.verifyError(@() nbiot.ml.trainLoadModels(data,options), ...
                'nbiot:ml:RoleManifest');
        end

        function candidateTrainingRejectsFinalComparisonRole(t)
            data=verifiedCandidateFixture();
            data.rowInfo.experimentRole(data.rowInfo.realizationId==31)="final-comparison";
            data.manifest.assignments.experimentRole( ...
                data.manifest.assignments.externalRealizationId==31)="final-comparison";
            options=mlTrainingDefaults();

            t.verifyError(@() nbiot.ml.trainLoadModels(data,options), ...
                'nbiot:ml:FinalComparison');
        end

        function candidateTrainingRejectsRoleSplitMismatch(t)
            data=verifiedCandidateFixture();
            data.rowInfo.experimentRole(data.rowInfo.realizationId==31)="training";
            data.manifest.assignments.experimentRole( ...
                data.manifest.assignments.externalRealizationId==31)="training";
            options=mlTrainingDefaults();

            t.verifyError(@() nbiot.ml.trainLoadModels(data,options), ...
                'nbiot:ml:RoleManifest');
        end

        function fourModelsTrainUseTrainOnlyTransformsAndReload(t)
            data=smallTrainingFixture();
            functionPath=which('nbiot.ml.trainLoadModels');
            t.assertTrue(~isempty(functionPath), ...
                'Load forecasting trainer is not implemented yet.');

            outputFolder=tempname;
            t.addTeardown(@() removeFolder(outputFolder));
            options=mlTrainingDefaults();
            options.outputFolder=outputFolder;
            options.forestNumTrees=8;
            options.boostNumLearningCycles=8;
            [bundles,report]=nbiot.ml.trainLoadModels(data,options);

            expectedNames={'linearRegression','decisionTree','randomForest','gradientBoosting'};
            t.verifyEqual({bundles.name},expectedNames);
            t.verifyEqual(numel(bundles),4);
            t.verifyTrue(all(ismember({'model','split','sampleCount','idCount', ...
                'mae','rmse','bias','predictionSeconds'},report.metrics.Properties.VariableNames)));
            t.verifyEqual(sum(report.metrics.model=="trainMean"),3);
            t.verifyTrue(any(report.metrics.model==report.bestValidationModel & ...
                report.metrics.split=="validation"));

            trainRows=data.rowInfo.split=="train";
            trainFeatures=data.features{trainRows,:};
            medians=median(trainFeatures,1,'omitnan');
            imputed=trainFeatures;
            for column=1:size(imputed,2)
                missing=isnan(imputed(:,column));
                imputed(missing,column)=medians(column);
            end
            expectedMean=mean(imputed,1);
            expectedScale=std(imputed,0,1);
            expectedScale(expectedScale<=eps)=1;
            for modelIndex=1:numel(bundles)
                bundle=bundles(modelIndex).bundle;
                t.verifyEqual(bundle.status,'development');
                t.verifyEqual(bundle.dataKind,'development-fixture');
                t.verifyEqual(bundle.targetName,'meanRaUe');
                t.verifyEqual(bundle.featureNames,data.schema.inputNames);
                t.verifyEqual(bundle.trainingIds,unique(data.rowInfo.realizationId(trainRows)).');
                t.verifyEqual(bundle.transform.median,medians,'AbsTol',1e-12);
                t.verifyEqual(bundle.transform.mean,expectedMean,'AbsTol',1e-12);
                t.verifyEqual(bundle.transform.scale,expectedScale,'AbsTol',1e-12);
                t.verifyTrue(isfile(bundles(modelIndex).file));
                t.verifyEqual(numel(bundles(modelIndex).sha256),64);
            end

            validationRow=data.observations(find(data.rowInfo.split=="validation",1),:);
            limits=struct('minimum',0,'maximum',10);
            for modelIndex=1:numel(bundles)
                estimate=nbiot.ml.predictLoad(bundles(modelIndex).bundle,validationRow,limits);
                t.verifyTrue(estimate.valid,estimate.reason);
                t.verifyEqual(estimate.featureWindowEndTick,validationRow.endTick);
                loaded=nbiot.ml.validateModelBundle(bundles(modelIndex).file,data.schema);
                reloaded=nbiot.ml.predictLoad(loaded,validationRow,limits);
                t.verifyEqual(reloaded.value,estimate.value,'AbsTol',1e-12);
            end

            wrongOrder=validationRow(:,end:-1:1);
            t.verifyError(@() nbiot.ml.predictLoad(bundles(1).bundle,wrongOrder,limits), ...
                'nbiot:ml:FeatureOrder');
            invalidSchema=bundles(1).bundle;
            invalidSchema.schemaVersion='unsupported-version';
            t.verifyError(@() nbiot.ml.validateModelBundle(invalidSchema,data.schema), ...
                'nbiot:ml:SchemaMismatch');
            t.verifyError(@() nbiot.ml.validateModelBundle( ...
                fullfile(outputFolder,'missing-model.mat'),data.schema), ...
                'nbiot:ml:MissingModel');
            nanBundle=bundles(1).bundle;
            nanBundle.model=NaNRegressionPredictor();
            nonfinite=nbiot.ml.predictLoad(nanBundle,validationRow,limits);
            t.verifyFalse(nonfinite.valid);
            t.verifyEqual(nonfinite.reason,'nonfinite-prediction');
            outside=nbiot.ml.predictLoad(bundles(1).bundle,validationRow, ...
                struct('minimum',1000,'maximum',1001));
            t.verifyFalse(outside.valid);
            t.verifyEqual(outside.reason,'prediction-outside-public-limits');

            fid=fopen(bundles(1).file,'a');
            fwrite(fid,uint8(0)); fclose(fid);
            t.verifyError(@() nbiot.ml.validateModelBundle(bundles(1).file,data.schema), ...
                'nbiot:ml:PackageHash');
        end

        function mixedIdsLeakingTargetsAndUnverifiedRealDataAreRejected(t)
            data=smallTrainingFixture();
            options=mlTrainingDefaults();

            mixed=data;
            mixed.rowInfo.split(2)="validation";
            t.verifyError(@() nbiot.ml.trainLoadModels(mixed,options), ...
                'nbiot:ml:GroupLeakage');

            leaked=data;
            leaked.features.meanRaUe=leaked.targets.meanRaUe;
            t.verifyError(@() nbiot.ml.trainLoadModels(leaked,options), ...
                'nbiot:ml:FeatureSchema');

            unverified=data;
            unverified.manifest.kind='candidate-training';
            unverified.manifest.allocationsVerified=false;
            t.verifyError(@() nbiot.ml.trainLoadModels(unverified,options), ...
                'nbiot:ml:DataPurpose');

            missing=data;
            trainRows=missing.rowInfo.split=="train";
            missing.features{trainRows,1}=NaN;
            t.verifyError(@() nbiot.ml.trainLoadModels(missing,options), ...
                'nbiot:ml:TrainingFeatureMissing');
        end

        function runnerLoadsAnExplicitDatasetAndWritesModelFiles(t)
            data=smallTrainingFixture();
            functionPath=which('trainLoadModels');
            t.assertTrue(~isempty(functionPath),'Training runner is not implemented yet.');
            root=tempname; mkdir(root);
            t.addTeardown(@() removeFolder(root));
            datasetFile=fullfile(root,'dataset.mat'); save(datasetFile,'data');
            outputFolder=fullfile(root,'models');
            trainingOptions=mlTrainingDefaults();
            trainingOptions.forestNumTrees=8;
            trainingOptions.boostNumLearningCycles=8;
            options=struct('datasetFile',datasetFile,'outputFolder',outputFolder, ...
                'trainingOptions',trainingOptions);
            [bundles,report]=trainLoadModels(options);
            t.verifyEqual(numel(bundles),4);
            t.verifyEqual(report.status,'development');
            t.verifyTrue(isfile(fullfile(outputFolder,'metrics.csv')));
            t.verifyTrue(isfile(fullfile(outputFolder,'training-manifest.json')));
        end

        function runnerRequiresAnExplicitDatasetWithDataVariable(t)
            root=tempname; mkdir(root);
            t.addTeardown(@() removeFolder(root));
            outputFolder=fullfile(root,'models');
            missingOptions=struct('datasetFile',fullfile(root,'missing.mat'), ...
                'outputFolder',outputFolder);
            t.verifyError(@() trainLoadModels(missingOptions),'nbiot:ml:DatasetFile');

            unrelated=1;
            datasetFile=fullfile(root,'unrelated.mat'); save(datasetFile,'unrelated');
            options=struct('datasetFile',datasetFile,'outputFolder',outputFolder);
            t.verifyError(@() trainLoadModels(options),'nbiot:ml:DatasetFile');

            options.datasetFile=fullfile(root,'another.mat');
            save(options.datasetFile,'unrelated');
            options.unexpectedPath='auto-search';
            t.verifyError(@() trainLoadModels(options),'nbiot:ml:RunnerOptions');
        end

        function sameSeedReproducesAllFourPredictions(t)
            data=smallTrainingFixture();
            options=mlTrainingDefaults();
            options.seed=17;
            options.forestNumTrees=8;
            options.boostNumLearningCycles=8;
            first=nbiot.ml.trainLoadModels(data,options);
            second=nbiot.ml.trainLoadModels(data,options);
            row=data.observations(find(data.rowInfo.split=="validation",1),:);
            limits=struct('minimum',0,'maximum',10);
            for k=1:numel(first)
                a=nbiot.ml.predictLoad(first(k).bundle,row,limits);
                b=nbiot.ml.predictLoad(second(k).bundle,row,limits);
                t.verifyEqual(b.value,a.value,'AbsTol',1e-12);
            end
        end
    end
end

function data=smallTrainingFixture()
schema=nbiot.dataset.featureSchema();
schema.keyNames=schema.observationNames(1:4);
schema.inputNames=schema.observationNames(5:end);
schema.targetName='meanRaUe';
ids=[11 12 13 21 31];
groups=["train" "train" "train" "validation" "test"];
rowsPerId=6; rowCount=numel(ids)*rowsPerId;
keys=zeros(rowCount,4); featureValues=zeros(rowCount,numel(schema.inputNames));
targetValues=zeros(rowCount,5); rowGroups=strings(rowCount,1); caseKeys=strings(rowCount,1);
cursor=0;
for idIndex=1:numel(ids)
    for window=1:rowsPerId
        cursor=cursor+1;
        id=ids(idIndex);
        keys(cursor,:)=[id window (window-1)*500 window*500];
        rowGroups(cursor)=groups(idIndex);
        caseKeys(cursor)=sprintf('fixture-%d',id);
        for featureIndex=1:numel(schema.inputNames)
            featureValues(cursor,featureIndex)= ...
                sin(cursor*(featureIndex+1)*.17)+cos(id*(featureIndex+2)*.013)+featureIndex*.1;
        end
        if idIndex>=4
            featureValues(cursor,1)=featureValues(cursor,1)+20;
        end
        targetValues(cursor,:)=[1+0.2*window+0.01*id 0.3 0.2 1 1];
    end
end
featureValues(1,2)=NaN;
features=array2table(featureValues,'VariableNames',schema.inputNames);
observations=[array2table(keys,'VariableNames',schema.keyNames) features];
targets=array2table([keys targetValues],'VariableNames',schema.targetNames);
rowInfo=table(caseKeys,keys(:,1),keys(:,2),keys(:,3),keys(:,4),rowGroups, ...
    'VariableNames',{'caseKey','realizationId','windowId','startTick','endTick','split'});
assignments=table(ids(:),groups(:),'VariableNames',{'externalRealizationId','split'});
manifest=struct('kind','development-fixture','version',1, ...
    'independentRealizations',numel(ids),'rows',rowCount,'allocationsVerified',false, ...
    'assignments',assignments);
data=struct('observations',observations,'targets',targets,'features',features, ...
    'rowInfo',rowInfo,'schema',schema,'manifest',manifest);
end

function data=verifiedCandidateFixture()
data=smallTrainingFixture();
data.manifest.kind='candidate-training';
data.manifest.allocationsVerified=true;
data.manifest.experimentRolesExplicit=true;
roles=data.rowInfo.split;
roles(roles=="train")="training";
roles(roles=="test")="model-test";
data.rowInfo.experimentRole=roles;
data.manifest.assignments.experimentRole=data.manifest.assignments.split;
data.manifest.assignments.experimentRole( ...
    data.manifest.assignments.experimentRole=="train")="training";
data.manifest.assignments.experimentRole( ...
    data.manifest.assignments.experimentRole=="test")="model-test";
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
