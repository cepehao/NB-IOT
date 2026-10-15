classdef TestExternalRunPackage < matlab.unittest.TestCase
    methods (Test)
        function missingCalibrationIsRejected(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.calibrationFile='results/missing-calibration.mat';

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:Calibration');
        end

        function adaptivePackageRequiresAnExplicitModel(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.caseMatrix.method(:)="Adaptive-P";

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:Model');
        end

        function calibrationHashMismatchIsRejected(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.expectedCalibrationSha256=repmat('0',1,64);

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:CalibrationHash');
        end

        function modelHashMismatchIsRejected(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            writeText(fullfile(root,'results','load-model.mat'),'model fixture');
            options.caseMatrix.method(:)="Adaptive-P";
            options.modelFile='results/load-model.mat';
            options.expectedModelSha256=repmat('0',1,64);

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:ModelHash');
        end

        function resourceBudgetCannotLeakAComputerPath(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.resourceBudget=struct('targetMachine',['C:' char(92) 'private']);

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:ResourceBudget');
        end

        function malformedResourceBudgetIsRejected(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.resourceBudget=struct('maxUE',5000,'localPath','test-only');
            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:ResourceBudget');

            options.resourceBudget=struct('maxUE',0);
            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:ResourceBudget');
        end

        function caseMatrixRejectsUnexpectedFields(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.caseMatrix.localPath=repmat(string(root),height(options.caseMatrix),1);

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:CaseMatrix');
        end

        function validResourceBudgetRemainsDraftForTargetReview(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.resourceBudget=struct('targetMachine','research-pc-2', ...
                'availableMemoryBytes',32*1024^3,'maxUE',5000, ...
                'maxCaseSeconds',18000,'maxSuiteSeconds',500000,'maxProcesses',2);

            manifest=prepareExternalRun(options);

            t.verifyEqual(manifest.resourceStatus,'provided-but-requires-target-review');
            t.verifyEqual(manifest.resourceBudget.targetMachine,'research-pc-2');
            t.verifyFalse(manifest.readyForExecution);
        end

        function duplicateAndAlreadyUsedIdsAreRejected(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.idAssignments=table([1500;1500], ...
                ["stage-3-load-pilot";"training"], ...
                'VariableNames',{'externalRealizationId','role'});
            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:DuplicateId');

            options.idAssignments=table(1064,"stage-3-load-pilot", ...
                'VariableNames',{'externalRealizationId','role'});
            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:AllocatedId');
        end

        function incompleteStagingDirectoryCannotBeResumed(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.resumePath='verification/completion/stage-3/.staging-interrupted';

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:Resume');
        end

        function packageUsesCurrentSourcesWithoutLocalPathsOrRegistryMutation(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            options.idAssignments=table(1500,"stage-3-load-pilot", ...
                'VariableNames',{'externalRealizationId','role'});
            registryPath=fullfile(root,'experiments','realizationRegistry.json');
            originalRegistry=fileread(registryPath);

            manifest=prepareExternalRun(options);

            t.verifyFalse(manifest.readyForExecution);
            t.verifyEqual(manifest.status,'draft-needs-external-review');
            t.verifyTrue(any(strcmp({manifest.codeFiles.path},'apps/NBIoTApp.m')));
            t.verifyTrue(any(strcmp({manifest.codeFiles.path},'AGENTS.md')));
            t.verifyTrue(isfile(fullfile(options.outputFolder,'project', ...
                'apps','NBIoTApp.m')));
            t.verifyTrue(isfile(fullfile(options.outputFolder,'project','AGENTS.md')));
            appEntry=manifest.codeFiles(strcmp({manifest.codeFiles.path},'apps/NBIoTApp.m'));
            packagedApp=fullfile(options.outputFolder,'project','apps','NBIoTApp.m');
            t.verifyEqual(nbiot.ml.fileSha256(packagedApp),appEntry.packageSha256);
            t.verifyFalse(contains(fileread(packagedApp),root));
            t.verifyTrue(isfile(fullfile(options.outputFolder,'manifest.json')));
            t.verifyFalse(contains(fileread(fullfile(options.outputFolder,'manifest.json')),root));
            t.verifyFalse(isfile(fullfile(options.outputFolder,'project', ...
                'verification','local','private-note.txt')));
            t.verifyEqual(fileread(registryPath),originalRegistry);
            t.verifyFalse(any(contains(string({manifest.codeFiles.path}),'.env')));
            t.verifyTrue(manifest.requiresStage2Revalidation);
        end

        function packageIncludesApprovedExternalRunnerSourcesOnly(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            runnerSources={ ...
                'verification/completion/stage-2/acceptStage2Evidence.m', ...
                'verification/completion/stage-2/checkCurrentStage2Sources.m', ...
                'verification/completion/stage-2/inspectReceiverEvidence.m', ...
                'verification/completion/stage-2/recoverStage2Physical.m', ...
                'verification/completion/stage-2/runCfoDetectorRegression.m', ...
                'verification/completion/stage-2/runStage2Calibration.m', ...
                'verification/completion/stage-2/runStage2ReceiverProbe.m', ...
                'verification/completion/stage-2/runStage2Revalidation.m', ...
                'verification/completion/stage-2/stage2ArtifactHashes.m', ...
                'verification/completion/stage-2/stage2ArtifactHashesMatch.m', ...
                'verification/completion/stage-2/stage2Physical.m', ...
                'verification/completion/stage-2/stage2PhysicalProgress.m', ...
                'verification/completion/stage-2/runStage2Physical.ps1', ...
                'verification/completion/stage-2/stage2PhysicalArtifactsMatch.m', ...
                'verification/completion/stage-2/stage2Targeted.m', ...
                'verification/completion/stage-2/validateStage2RevalidationProvenance.m', ...
                'verification/completion/stage-3/runVariant2.ps1', ...
                'verification/completion/stage-3/runLoadPilot.ps1', ...
                'verification/local/InvokeScheduledProcess.ps1', ...
                'verification/local/InvokeBoundedProcess.ps1', ...
                'verification/local/OwnedProcessJob.cs'};
            for k=1:numel(runnerSources)
                source=fullfile(root,strrep(runnerSources{k},'/',filesep));
                parent=fileparts(source);
                if ~isfolder(parent), mkdir(parent); end
                writeText(source,['runner fixture ' runnerSources{k}]);
            end
            writeText(fullfile(root,'verification','completion','stage-2','acceptance.json'), ...
                '{"status":"old-evidence"}');
            writeText(fullfile(root,'verification','completion','stage-3','interruption.json'), ...
                '{"status":"old-evidence"}');

            manifest=prepareExternalRun(options);
            packagedPaths=string({manifest.codeFiles.path});

            t.verifyTrue(all(ismember(string(runnerSources),packagedPaths)));
            for k=1:numel(runnerSources)
                entry=manifest.codeFiles(strcmp({manifest.codeFiles.path},runnerSources{k}));
                packaged=fullfile(options.outputFolder,'project', ...
                    strrep(runnerSources{k},'/',filesep));
                t.verifyTrue(isfile(packaged));
                if ~isempty(entry)&&isfile(packaged)
                    t.verifyEqual(nbiot.ml.fileSha256(packaged),entry.packageSha256);
                end
            end
            t.verifyFalse(isfile(fullfile(options.outputFolder,'project', ...
                'verification','completion','stage-2','acceptance.json')));
            t.verifyFalse(isfile(fullfile(options.outputFolder,'project', ...
                'verification','completion','stage-3','interruption.json')));
            t.verifyTrue(any(contains(string(manifest.expectedCommands), ...
                'runVariant2.ps1 -Execute')));
            t.verifyTrue(any(contains(string(manifest.expectedCommands), ...
                'runVariant2.ps1 -Resume -RunFolder')));
            t.verifyFalse(any(contains(string(manifest.expectedCommands), ...
                'runLoadPilot')));
        end

        function packageDoesNotOverwriteExistingOutput(t)
            [options,root,cleanup]=fixture(); %#ok<ASGLU>
            mkdir(options.outputFolder);

            t.verifyError(@() prepareExternalRun(options), ...
                'nbiot:externalRun:OutputExists');
        end
    end
end

function [options,root,cleanup]=fixture()
root=tempname; mkdir(root); cleanup=onCleanup(@() removeFolder(root));
folders={'apps','configs','docs','examples','experiments','src','tests', ...
    'results','verification/external','verification/local'};
for k=1:numel(folders), mkdir(fullfile(root,strrep(folders{k},'/',filesep))); end
writeText(fullfile(root,'setupProject.m'),'function setupProject; end');
writeText(fullfile(root,'README.md'),'Fixture project');
writeText(fullfile(root,'AGENTS.md'),'Project instructions for external handoff.');
writeText(fullfile(root,'apps','NBIoTApp.m'), ...
    ['% project root: ' root newline 'function app=NBIoTApp; app=[]; end']);
writeText(fullfile(root,'verification','local','private-note.txt'),'do not package');
writeText(fullfile(root,'results','nprach-calibration.mat'),'calibration fixture');
registry=struct('schemaVersion',1,'roles',{{'stage-3-load-pilot','training'}}, ...
    'reservations',struct('role','legacy-holdout','range',[0 999]), ...
    'assignments',struct('role','stage-3-load-pilot','ids',1064,'status','failed'));
writeText(fullfile(root,'experiments','realizationRegistry.json'),jsonencode(registry));
options=struct('projectRoot',root, ...
    'outputFolder',fullfile(root,'verification','external','draft-package'), ...
    'calibrationFile','results/nprach-calibration.mat', ...
    'registryFile','experiments/realizationRegistry.json', ...
    'caseMatrix',table("Static",100,5000,"burst",100, ...
        'VariableNames',{'method','numUE','durationTicks','trafficKind','burstDurationTicks'}), ...
    'idAssignments',table(1500,"stage-3-load-pilot", ...
        'VariableNames',{'externalRealizationId','role'}));
end

function writeText(path,value)
fid=fopen(path,'w','n','UTF-8');
assert(fid>=0,'Could not create package fixture file.');
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(value,'UTF-8'),'uint8');
end

function removeFolder(path)
if isfolder(path), rmdir(path,'s'); end
end
