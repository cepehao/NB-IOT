classdef TestModelEvaluationMetrics < matlab.unittest.TestCase
    methods (Test)
        function loadsTrainValidationAndTestScoresForMatchingModel(t)
            folder=tempname; mkdir(folder);
            t.addTeardown(@() removeFolder(folder));
            modelFile=writeModelFixture(folder);
            writeMetrics(folder);

            metrics=nbiot.ui.loadModelEvaluationMetrics(modelFile, ...
                struct('modelName','linearRegression'));

            t.verifyEqual(string(metrics.split),["train";"validation";"test"]);
            t.verifyEqual(metrics.mae,[.2;.3;.4]);
            t.verifyEqual(metrics.rmse,[.3;.4;.5]);
        end

        function ignoresMetricsWhenTheModelFileHashChanged(t)
            folder=tempname; mkdir(folder);
            t.addTeardown(@() removeFolder(folder));
            modelFile=writeModelFixture(folder);
            writeMetrics(folder);
            fid=fopen(modelFile,'a');
            cleanup=onCleanup(@() fclose(fid));
            fwrite(fid,'changed','char');

            metrics=nbiot.ui.loadModelEvaluationMetrics(modelFile, ...
                struct('modelName','linearRegression'));

            t.verifyEmpty(metrics);
        end
    end
end

function modelFile=writeModelFixture(folder)
modelFile=fullfile(folder,'linearRegression.mat');
fid=fopen(modelFile,'w');
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,'model package fixture','char');
hash=nbiot.ml.fileSha256(modelFile);
manifest=struct('modelNames',{{'linearRegression'}}, ...
    'artifactFiles',{{'linearRegression.mat'}},'artifactSha256',{{hash}});
writeJson(fullfile(folder,'training-manifest.json'),manifest);
end

function writeMetrics(folder)
metrics=table(repmat("linearRegression",3,1), ...
    ["train";"validation";"test"],[2;1;1],[2;1;1], ...
    [.2;.3;.4],[.3;.4;.5], ...
    'VariableNames',{'model','split','sampleCount','idCount','mae','rmse'});
writetable(metrics,fullfile(folder,'metrics.csv'));
end

function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(jsonencode(value),'UTF-8'),'uint8');
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
