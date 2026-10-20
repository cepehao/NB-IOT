function report=runLocalCompletionPipeline(options)
%RUNLOCALCOMPLETIONPIPELINE Build a bounded, development-only handoff in two passes.
required={'outputFolder','realizationIds','boundedEvidenceFolder','mode'};
if ~isstruct(options)||~isscalar(options)||~all(isfield(options,required))|| ...
        any(~ismember(fieldnames(options),required))
    error('nbiot:T3:Options', ...
        'Supply only outputFolder, realizationIds, boundedEvidenceFolder and mode.');
end
mode=char(string(options.mode));
if ~ismember(mode,{'full','package-only'})
    error('nbiot:T3:Options','Mode must be full or package-only.');
end
root=findProjectRoot(mfilename('fullpath'));
outputFolder=resolveProjectPath(root,options.outputFolder);
ids=validateIds(options.realizationIds);
if strcmp(mode,'full')
    if isfolder(outputFolder)
        assertReusableCoreOutput(outputFolder);
    else
        mkdir(outputFolder);
    end
    report=runCore(options,root,outputFolder,ids);
else
    if ~isfolder(outputFolder)
        error('nbiot:T3:PackageOnly','Package-only mode needs a completed full-mode output folder.');
    end
    report=runPackageOnly(options,root,outputFolder,ids);
end
writeJson(fullfile(outputFolder,'pipeline-report.json'),report);
end

function report=runCore(options,root,outputFolder,ids)
registryFile=fullfile(root,'experiments','realizationRegistry.json');
registrySha256=nbiot.ml.fileSha256(registryFile);
registry=jsondecode(fileread(registryFile));
validateDevelopmentIds(registry,ids);
sourceAtStart=sourceManifest(root);
implementationDigestAtStart=implementationDigest(sourceAtStart);
artifactRoot=fullfile(outputFolder,'pipeline-artifacts');
if ~isfolder(artifactRoot), mkdir(artifactRoot); end
caseRoot=fullfile(artifactRoot,'cases');
developmentFolder=fullfile(artifactRoot,'development-dataset');
fixtureFolder=fullfile(artifactRoot,'development-fixture');
modelFolder=fullfile(artifactRoot,'model-training');
calibrationFile=fullfile(root,'results','nprach-calibration.mat');

cfg=nbiot.config.defaultConfig();
cfg.simulation.numUE=2;
cfg.simulation.durationTicks=5000;
cfg.traffic.burstDurationTicks=1000;
cfg.logging.saveWaveforms=false;
execution=struct('profile','local-development','role','development', ...
    'maxUE',2,'maxCaseSeconds',300,'maxSuiteSeconds',900, ...
    'timePolicy','hard-stop');
sweep=runStaticSweep(struct('counts',2,'burstDurations',1000, ...
    'realizationIds',ids,'config',cfg,'calibrationFile',calibrationFile, ...
    'outputFolder',caseRoot,'resume',isfolder(caseRoot),'execution',execution));
if height(sweep)~=3||any(string(sweep.status)~="completed")|| ...
        any(sweep.numUE~=2)||~isequal(sort(double(sweep.realizationId(:))).',sort(ids))
    error('nbiot:T3:StaticCases', ...
        'The three bounded Static cases did not all complete with the expected IDs.');
end
caseFiles=cellstr(string(sweep.resultFile));
caseChecks=repmat(struct('caseKey','','realizationId',0,'status','','passed',false, ...
    'caseFolder','','markerFile','','resultFile','','markerSha256','','resultSha256',''), ...
    numel(caseFiles),1);
for k=1:numel(caseFiles)
    caseFolder=fileparts(caseFiles{k});
    markerFile=fullfile(caseFolder,'case-complete.json');
    verification=nbiot.results.verifyCase(caseFolder);
    marker=jsondecode(fileread(markerFile));
    if ~verification.passed||~strcmp(verification.status,'completed')
        error('nbiot:T3:CaseVerification','A newly generated Static case failed verifyCase.');
    end
    caseChecks(k)=struct('caseKey',char(string(marker.caseKey)), ...
        'realizationId',double(sweep.realizationId(k)),'status',char(string(marker.status)), ...
        'passed',logical(verification.passed), ...
        'caseFolder',relativeToRoot(root,caseFolder), ...
        'markerFile',relativeToRoot(root,markerFile), ...
        'resultFile',relativeToRoot(root,caseFiles{k}), ...
        'markerSha256',nbiot.ml.fileSha256(markerFile), ...
        'resultSha256',nbiot.ml.fileSha256(caseFiles{k}));
end
caseVerificationFile=fullfile(outputFolder,'case-verification.json');
writeJson(caseVerificationFile,struct('schemaVersion',1,'profile','local-development', ...
    'maxUE',2,'caseCount',numel(caseChecks),'cases',caseChecks));

trainingManifestFile=fullfile(modelFolder,'training-manifest.json');
fixtureDatasetFile=fullfile(fixtureFolder,'dataset.mat');
if isfile(trainingManifestFile)
    verifyDatasetArtifacts(developmentFolder);
    verifyDatasetArtifacts(fixtureFolder);
    developmentManifest=jsondecode(fileread(fullfile(developmentFolder,'manifest.json')));
    fixtureManifest=jsondecode(fileread(fullfile(fixtureFolder,'manifest.json')));
    fixtureProvenance=jsondecode(fileread(fullfile(fixtureFolder,'fixture-provenance.json')));
    if ~isfield(developmentManifest,'diagnosticsComplete')|| ...
            ~isequal(developmentManifest.diagnosticsComplete,true)|| ...
            ~strcmp(char(string(developmentManifest.diagnosticsSchemaVersion)),'window-diagnostics-v1')
        error('nbiot:T3:Diagnostics','The saved D3 dataset lacks complete window diagnostics.');
    end
    if ~strcmp(char(string(fixtureManifest.kind)),'development-fixture')|| ...
            logical(fixtureManifest.allocationsVerified)|| ...
            ~strcmp(char(string(fixtureProvenance.evidenceKind)),'development-fixture')|| ...
            logical(fixtureProvenance.scientificEvidence)|| ...
            ~isequal(sort(double([fixtureProvenance.splitAssignments.externalRealizationId])),sort(ids))
        error('nbiot:T3:Fixture','Saved fixture provenance does not match the development IDs.');
    end
    diagnosticsComplete=true;
else
    developmentSplit=table(ids(:),repmat("development",numel(ids),1), ...
        repmat("development",numel(ids),1), ...
        'VariableNames',{'externalRealizationId','split','experimentRole'});
    developmentData=buildLoadDataset(struct('resultFiles',{caseFiles}, ...
        'splitManifest',developmentSplit,'outputFolder',developmentFolder, ...
        'purpose','development'));
    if ~isfield(developmentData.manifest,'diagnosticsComplete')|| ...
            ~isequal(developmentData.manifest.diagnosticsComplete,true)|| ...
            ~isequal(developmentData.manifest.diagnosticsSchemaVersion,'window-diagnostics-v1')
        error('nbiot:T3:Diagnostics','The assembled D3 dataset lacks complete window diagnostics.');
    end
    developmentData=makePortableInputs(developmentData,caseRoot);
    writeDatasetBundle(developmentData,developmentFolder,{});
    developmentDatasetSha256=nbiot.ml.fileSha256(fullfile(developmentFolder,'dataset.mat'));
    developmentArtifactsSha256=nbiot.ml.fileSha256(fullfile(developmentFolder,'artifacts.json'));
    splitNames=["train";"validation";"test"];
    roleNames=["training";"validation";"model-test"];
    fixtureSplit=table(ids(:),splitNames,roleNames, ...
        'VariableNames',{'externalRealizationId','split','experimentRole'});
    fixtureData=nbiot.dataset.assembleLoadDataset(caseFiles,fixtureSplit);
    fixtureData.manifest.kind='development-fixture';
    fixtureData.manifest.allocationsVerified=false;
    fixtureData.manifest.experimentRolesExplicit=true;
    fixtureData=makePortableInputs(fixtureData,caseRoot);
    sourceCases=repmat(struct('caseKey','','realizationId',0,'sourceFile','','markerSha256','', ...
        'sourceSha256','','calibrationSha256','','split',''),numel(ids),1);
    for k=1:numel(ids)
        input=find(double([fixtureData.manifest.inputs.realizationId])==ids(k),1);
        if isempty(input), error('nbiot:T3:Fixture','A development ID has no source case.'); end
        sourceCases(k)=struct('caseKey',char(string(fixtureData.manifest.inputs(input).caseKey)), ...
            'realizationId',ids(k), ...
            'sourceFile',char(string(fixtureData.manifest.inputs(input).resultFile)), ...
            'markerSha256',char(string(fixtureData.manifest.inputs(input).markerSha256)), ...
            'sourceSha256',char(string(fixtureData.manifest.inputs(input).sourceSha256)), ...
            'calibrationSha256',char(string(fixtureData.manifest.inputs(input).calibrationSha256)), ...
            'split',char(splitNames(k)));
    end
    fixtureProvenance=struct('schemaVersion',1,'evidenceKind','development-fixture', ...
        'scientificEvidence',false,'sourceDevelopmentDatasetSha256',developmentDatasetSha256, ...
        'sourceDevelopmentArtifactsSha256',developmentArtifactsSha256, ...
        'sourceCases',sourceCases,'splitAssignments',table2struct(fixtureSplit), ...
        'transformations',{{ ...
            'Assigned each complete realization ID to one group: 1037=train, 1038=validation, 1039=test.', ...
            'Changed only split/role labels and dataset kind; feature, target, observation and diagnostic values are unchanged.', ...
            'Set kind=development-fixture and allocationsVerified=false; no candidate-training or scientific claim.', ...
            'Replaced absolute case paths with relative package paths while preserving caseKey and source hashes.'}});
    writeDatasetBundle(fixtureData,fixtureFolder,fixtureProvenance);
    diagnosticsComplete=true;
end

if isfile(trainingManifestFile)
    trainingManifest=jsondecode(fileread(trainingManifestFile));
    selectedModel=char(string(trainingManifest.bestValidationModel));
    selectedAt=find(string(trainingManifest.modelNames)==selectedModel,1);
    if isempty(selectedAt)||~strcmp(char(string(trainingManifest.dataKind)),'development-fixture')|| ...
            logical(trainingManifest.allocationsVerified)|| ...
            ~strcmpi(char(string(trainingManifest.datasetSha256)), ...
                nbiot.ml.fileSha256(fixtureDatasetFile))
        error('nbiot:T3:Training','Saved training manifest does not match the development fixture.');
    end
    modelFile=fullfile(modelFolder,char(string(trainingManifest.artifactFiles(selectedAt))));
    if ~strcmpi(char(string(trainingManifest.artifactSha256(selectedAt))), ...
            nbiot.ml.fileSha256(modelFile))|| ...
            ~strcmpi(char(string(trainingManifest.metricsSha256)), ...
            nbiot.ml.fileSha256(fullfile(modelFolder,char(string(trainingManifest.metricsFile)))))
        error('nbiot:T3:Training','Saved training artifacts differ from their manifest.');
    end
    modelBundle=nbiot.ml.validateModelBundle(modelFile);
    modelMetrics=nbiot.ml.loadModelEvaluationMetrics(modelFile,modelBundle);
    if isempty(modelMetrics)||~all(ismember({'train','validation','test'},string(modelMetrics.split)))
        error('nbiot:T3:Training','Saved fixture training metrics lack an expected split.');
    end
else
    trainingOptions=mlTrainingDefaults();
    trainingOptions.evaluationMode='development-all-splits';
    [bundles,trainingReport]=trainLoadModels(struct( ...
        'datasetFile',fixtureDatasetFile,'outputFolder',modelFolder, ...
        'trainingOptions',trainingOptions));
    if ~isfield(trainingReport,'bestValidationModel')||isempty(trainingReport.bestValidationModel)
        error('nbiot:T3:Training','Development fixture training did not select a validation model.');
    end
    selectedModel=char(string(trainingReport.bestValidationModel));
    selectedAt=find(strcmp(string({bundles.name}),selectedModel),1);
    if isempty(selectedAt)
        error('nbiot:T3:Training','The validation-selected model artifact was not written.');
    end
    modelFile=char(string(bundles(selectedAt).file));
    modelBundle=bundles(selectedAt).bundle;
end
if ~isfile(modelFile)||~strcmp(char(string(modelBundle.dataKind)),'development-fixture')|| ...
        ~strcmp(char(string(modelBundle.status)),'development')
    error('nbiot:T3:Training','The trained model is not an explicitly labeled development fixture.');
end

adaptiveCfg=nbiot.config.defaultConfig();
adaptiveCfg.simulation.numUE=2;
adaptiveCfg.simulation.durationTicks=1000;
adaptiveCfg.simulation.realizationId=ids(1);
adaptiveCfg.policy.name='Adaptive-P';
adaptiveCfg.traffic.burstDurationTicks=1000;
adaptiveCfg.logging.saveWaveforms=false;
adaptiveCfg=nbiot.experiments.loadCalibration(adaptiveCfg,calibrationFile);
localOptions=struct('model',modelFile,'allowDevelopmentModel',true);
localSimulator=nbiot.NBIoTSimulator(adaptiveCfg,[],execution,localOptions);
localSimulator.run();
localResult=localSimulator.result();
if ~strcmp(localResult.status,'completed')|| ...
        ~strcmp(char(string(localResult.controllerModel.dataKind)),'development-fixture')|| ...
        ~strcmp(char(string(localResult.controllerModel.admissionStatus)),'development-only')
    error('nbiot:T3:Adaptive','Local Adaptive did not complete with explicit development admission.');
end
runtimeFile=fullfile(outputFolder,'adaptive-runtime-smoke.json');
modelSha256=nbiot.ml.fileSha256(modelFile);
if isfile(runtimeFile)
    runtime=jsondecode(fileread(runtimeFile));
    if ~strcmp(char(string(runtime.status)),'completed')|| ...
            ~strcmp(char(string(runtime.modelDataKind)),'development-fixture')|| ...
            ~strcmp(char(string(runtime.admissionStatus)),'development-only')|| ...
            ~strcmpi(char(string(runtime.modelSha256)),modelSha256)
        error('nbiot:T3:Adaptive','Saved local Adaptive evidence does not match the trained fixture.');
    end
    runtimeStatus=char(string(runtime.status));
    runtimeModelDataKind=char(string(runtime.modelDataKind));
else
    localOptions=struct('model',modelFile,'allowDevelopmentModel',true);
    localSimulator=nbiot.NBIoTSimulator(adaptiveCfg,[],execution,localOptions);
    localSimulator.run();
    localResult=localSimulator.result();
    if ~strcmp(localResult.status,'completed')|| ...
            ~strcmp(char(string(localResult.controllerModel.dataKind)),'development-fixture')|| ...
            ~strcmp(char(string(localResult.controllerModel.admissionStatus)),'development-only')
        error('nbiot:T3:Adaptive','Local Adaptive did not complete with explicit development admission.');
    end
    runtimeStatus=localResult.status;
    runtimeModelDataKind=char(string(localResult.controllerModel.dataKind));
    writeJson(runtimeFile,struct('schemaVersion',1,'status',runtimeStatus, ...
        'profile','local-development','role','development','maxUE',2, ...
        'method',localResult.config.policy.name,'modelDataKind',runtimeModelDataKind, ...
        'admissionStatus',char(string(localResult.controllerModel.admissionStatus)), ...
        'modelSha256',modelSha256, ...
        'controllerDecisionCount',numel(localResult.controllerLog), ...
        'scientificEvidence',false));
end

externalExecution=struct('profile','external-machine','role','final-comparison', ...
    'maxUE',2,'maxCaseSeconds',300,'maxSuiteSeconds',900, ...
    'timePolicy','hard-stop');
externalCfg=adaptiveCfg;
externalCfg.simulation.realizationId=unusedComparisonId(registry);
acceptanceMissing=fullfile(outputFolder,'missing-fixture-acceptance.json');
externalRejected=false;
try
    nbiot.controller.prepareRuntime(externalCfg,externalExecution,struct( ...
        'model',modelFile,'policy',adaptiveDefaults(), ...
        'modelAcceptanceFile',acceptanceMissing));
catch exception
    if strcmp(exception.identifier,'nbiot:ml:ModelAcceptance')
        externalRejected=true;
    else
        rethrow(exception);
    end
end
if ~externalRejected
    error('nbiot:T3:ExternalAdmission','The development fixture unexpectedly passed external admission.');
end

registryAfter=nbiot.ml.fileSha256(registryFile);
if ~strcmpi(registrySha256,registryAfter)
    error('nbiot:T3:Registry','The authoritative realization registry changed during T3.');
end
sourceAtEnd=sourceManifest(root);
if ~strcmpi(implementationDigestAtStart,implementationDigest(sourceAtEnd))
    error('nbiot:T3:SourceIdentity','Implementation sources changed during the bounded integration run.');
end
report=struct('status','core-complete','caseCount',3,'realizationIds',ids, ...
    'maxUE',2,'caseVerificationPassed',all([caseChecks.passed]), ...
    'diagnosticsComplete',diagnosticsComplete, ...
    'fixtureKind','development-fixture','trainingIds',ids(1), ...
    'validationIds',ids(2),'testIds',ids(3),'runtimeStatus',runtimeStatus, ...
    'runtimeModelDataKind',runtimeModelDataKind, ...
    'transferReaderPassed',false,'externalFixtureAdmissionRejected',externalRejected, ...
    'registrySha256Before',registrySha256,'registrySha256After',registryAfter, ...
    'sourceDigest',implementationDigestAtStart,'packageFile','', ...
    'packageSha256','','packageFolder','','transferFolder','', ...
    'localCompletionFile','','engineeringCoreReady',false,'localReady',false, ...
    'externalExperimentComplete',false);
context=struct('schemaVersion',1,'outputFolder',relativeToRoot(root,outputFolder), ...
    'realizationIds',ids,'modelName',selectedModel, ...
    'registrySha256',registrySha256,'implementationDigest',implementationDigestAtStart, ...
    'caseCount',3,'maxUE',2,'caseVerificationPassed',all([caseChecks.passed]), ...
    'diagnosticsComplete',diagnosticsComplete, ...
    'fixtureKind','development-fixture','trainingIds',ids(1), ...
    'validationIds',ids(2),'testIds',ids(3), ...
    'runtimeStatus',runtimeStatus, ...
    'runtimeModelDataKind',runtimeModelDataKind, ...
    'externalFixtureAdmissionRejected',externalRejected, ...
    'coreBoundedEvidenceFolder',relativeToRoot(root, ...
        resolveProjectPath(root,options.boundedEvidenceFolder)), ...
    'coreReport',report);
writeJson(fullfile(outputFolder,'pipeline-context.json'),context);
end

function report=runPackageOnly(options,root,outputFolder,ids)
contextFile=fullfile(outputFolder,'pipeline-context.json');
if ~isfile(contextFile), error('nbiot:T3:PackageOnly','Missing core pipeline context.'); end
context=jsondecode(fileread(contextFile));
if ~isfield(context,'schemaVersion')||context.schemaVersion~=1|| ...
        ~isequal(double(context.realizationIds(:).'),ids)||context.caseCount~=3|| ...
        ~strcmp(char(string(context.fixtureKind)),'development-fixture')
    error('nbiot:T3:PackageOnly','The saved core context does not match the requested development fixture.');
end
if ~strcmp(canonical(fullfile(root,strrep(char(string(context.outputFolder)),'/',filesep))),outputFolder)
    error('nbiot:T3:PackageOnly','The core context belongs to another output folder.');
end
sourceNow=sourceManifest(root);
packageOnlySourceIdentity=verifyPackageOnlySourceIdentity( ...
    root,outputFolder,context,sourceNow);
registryFile=fullfile(root,'experiments','realizationRegistry.json');
registry=jsondecode(fileread(registryFile));
validateDevelopmentIds(registry,ids);
registrySha256=nbiot.ml.fileSha256(registryFile);
if ~strcmpi(context.registrySha256,registrySha256)
    error('nbiot:T3:Registry','The authoritative registry changed between T3 passes.');
end
core=verifyCoreArtifacts(root,outputFolder,context);
if ~context.externalFixtureAdmissionRejected||~strcmp(context.runtimeStatus,'completed')
    error('nbiot:T3:CoreEvidence','Saved local runtime or external rejection evidence is incomplete.');
end

writeJson(fullfile(outputFolder,'source-manifest.json'),sourceNow);
[~,runName]=fileparts(outputFolder);
packageTag=sourceNow.sourceDigest(1:12);
externalPackageRelative=fullfile('verification','external', ...
    ['T3-fixture-blocked-' runName '-' packageTag]);
if isfolder(fullfile(root,externalPackageRelative))
    error('nbiot:T3:Package','The external preflight draft already exists; refusing to overwrite it.');
end
probeId=unusedComparisonId(registry);
caseMatrix=table("Adaptive-P",2,1000,"burst",1000, ...
    'VariableNames',{'method','numUE','durationTicks','trafficKind','burstDurationTicks'});
modelFile=fullfile(outputFolder,'pipeline-artifacts','model-training', ...
    [char(string(context.modelName)) '.mat']);
externalManifest=prepareExternalRun(struct( ...
    'projectRoot',root,'outputFolder',externalPackageRelative, ...
    'calibrationFile','results/nprach-calibration.mat', ...
    'registryFile','experiments/realizationRegistry.json', ...
    'caseMatrix',caseMatrix, ...
    'idAssignments',table(probeId,"final-comparison", ...
        'VariableNames',{'externalRealizationId','role'}), ...
    'modelFile',relativeToRoot(root,modelFile)));
if externalManifest.readyForExecution||externalManifest.modelAcceptance.included|| ...
        ~strcmp(externalManifest.modelAcceptance.status,'')
    error('nbiot:T3:Package','The fixture draft must remain non-executable and unaccepted.');
end
externalPackage=fullfile(root,externalPackageRelative);
evidenceRoot=fullfile(externalPackage,'local-development-evidence');
if ~isfolder(evidenceRoot), mkdir(evidenceRoot); end
artifactRoot=fullfile(outputFolder,'pipeline-artifacts');
copyDirectory(fullfile(artifactRoot,'cases'),fullfile(evidenceRoot,'cases'));
copyDirectory(fullfile(artifactRoot,'development-dataset'), ...
    fullfile(evidenceRoot,'development-dataset'));
copyDirectory(fullfile(artifactRoot,'development-fixture'), ...
    fullfile(evidenceRoot,'development-fixture'));
copyDirectory(fullfile(artifactRoot,'model-training'), ...
    fullfile(evidenceRoot,'model-training'));
copyfile(fullfile(outputFolder,'case-verification.json'), ...
    fullfile(evidenceRoot,'case-verification.json'));
copyfile(contextFile,fullfile(evidenceRoot,'pipeline-context.json'));
copyfile(fullfile(outputFolder,'adaptive-runtime-smoke.json'), ...
    fullfile(evidenceRoot,'adaptive-runtime-smoke.json'));
baselineSuiteReport=fullfile(root,strrep( ...
    char(string(packageOnlySourceIdentity.baselineCoreBoundedEvidenceSuitePath)),'/',filesep));
if ~isfile(baselineSuiteReport)||~strcmpi(rawFileSha256(baselineSuiteReport), ...
        packageOnlySourceIdentity.coreBoundedEvidenceSuiteSha256)
    error('nbiot:T3:SourceIdentity', ...
        'The preserved bounded core suite report is missing or has changed.');
end
bundledSuiteReport=fullfile(evidenceRoot,'bounded-core-suite-report.json');
copyfile(baselineSuiteReport,bundledSuiteReport);
if ~strcmpi(rawFileSha256(bundledSuiteReport), ...
        packageOnlySourceIdentity.coreBoundedEvidenceSuiteSha256)
    error('nbiot:T3:SourceIdentity', ...
        'The bounded core suite report changed while being added to the package.');
end
runnerFolder=fullfile(evidenceRoot,'runner');
if ~isfolder(runnerFolder), mkdir(runnerFolder); end
copyfile([mfilename('fullpath') '.m'],fullfile(runnerFolder,'runLocalCompletionPipeline.m'));
copyfile(fullfile(root,'tests','TestLocalCompletionPipeline.m'), ...
    fullfile(runnerFolder,'TestLocalCompletionPipeline.m'));
writeText(fullfile(evidenceRoot,'README.md'), ...
    ['Evidence is derived from three completed Static development cases. ' ...
    'The trained model is a development-fixture. No external stage or scientific acceptance is authorized.']);

bundleManifestFile=fullfile(externalPackage,'handoff-manifest.json');
bundleManifest=makeBundleManifest(externalPackage,sourceNow.sourceDigest);
writeJson(bundleManifestFile,bundleManifest);
portableZip=fullfile(outputFolder,['portable-local-completion-' packageTag '.zip']);
archivePackage(externalPackage,bundleManifest,portableZip);
transferFolder=fullfile(outputFolder,['transfer copy-' packageTag]);
if isfolder(transferFolder)
    error('nbiot:T3:Transfer','Transfer destination already exists; refusing to overwrite.');
end
unzip(portableZip,transferFolder);
transferIntegrity=verifyBundleManifest(transferFolder);
if ~transferIntegrity.passed
    error('nbiot:T3:Transfer','The unpacked handoff package failed its integrity check.');
end
transferredManifest=jsondecode(fileread(fullfile(transferFolder,'manifest.json')));
transferredModel=fullfile(transferFolder,strrep( ...
    char(string(transferredManifest.model.packagePath)),'/',filesep));
transferredBundle=nbiot.ml.validateModelBundle(transferredModel);
if ~strcmp(char(string(transferredBundle.dataKind)),'development-fixture')
    error('nbiot:T3:Reader','The relocated package model reader lost fixture provenance.');
end
evidenceModel=fullfile(transferFolder,'local-development-evidence', ...
    'model-training',[char(string(context.modelName)) '.mat']);
evidenceBundle=nbiot.ml.validateModelBundle(evidenceModel);
metrics=nbiot.ml.loadModelEvaluationMetrics(evidenceModel,evidenceBundle);
if isempty(metrics)||~all(ismember({'train','validation','test'},string(metrics.split)))
    error('nbiot:T3:Reader','The relocated training reader did not return all fixture metric groups.');
end
externalPreflight=validateExternalPreflight(transferFolder,struct('stage','validate'));
preflightFile=fullfile(outputFolder,['transfer-preflight-report-' packageTag '.json']);
writeJson(preflightFile,externalPreflight);
transferReaderPassed=externalPreflight.passed&& ...
    ~externalPreflight.readiness.scientificAccepted&& ...
    ~externalPreflight.readiness.stageReady&&transferIntegrity.passed;
if ~transferReaderPassed
    error('nbiot:T3:ExternalPreflight', ...
        'Relocated preflight must validate structure and block the fixture stage.');
end
externalExecution=struct('profile','external-machine','role','final-comparison', ...
    'maxUE',2,'maxCaseSeconds',300,'maxSuiteSeconds',900, ...
    'timePolicy','hard-stop');
adaptiveCfg=nbiot.config.defaultConfig();
adaptiveCfg.simulation.numUE=2;
adaptiveCfg.simulation.durationTicks=1000;
adaptiveCfg.simulation.realizationId=probeId;
adaptiveCfg.policy.name='Adaptive-P';
adaptiveCfg.traffic.burstDurationTicks=1000;
adaptiveCfg.logging.saveWaveforms=false;
adaptiveCfg=nbiot.experiments.loadCalibration(adaptiveCfg, ...
    fullfile(root,'results','nprach-calibration.mat'));
externalRejected=false;
try
    nbiot.controller.prepareRuntime(adaptiveCfg,externalExecution,struct( ...
        'model',transferredModel,'policy',adaptiveDefaults(), ...
        'modelAcceptanceFile',fullfile(transferFolder,'missing-fixture-acceptance.json')));
catch exception
    if strcmp(exception.identifier,'nbiot:ml:ModelAcceptance')
        externalRejected=true;
    else
        rethrow(exception);
    end
end
if ~externalRejected
    error('nbiot:T3:ExternalAdmission','The transferred development fixture passed external admission.');
end
registryAfter=nbiot.ml.fileSha256(registryFile);
if ~strcmpi(registrySha256,registryAfter)
    error('nbiot:T3:Registry','The authoritative registry changed during package verification.');
end
packageSha256=nbiot.ml.fileSha256(portableZip);
bundleManifestSha256=nbiot.ml.fileSha256(bundleManifestFile);
localCompletionFile=fullfile(root,'verification','local', ...
    'implementation-20261015','local-completion.json');
localCompletion=makeLocalCompletion(sourceNow.sourceDigest,packageSha256, ...
    bundleManifestSha256,registrySha256,portableZip,preflightFile,outputFolder, ...
    char(string(context.coreBoundedEvidenceFolder)), ...
    char(string(resolveProjectPath(root,options.boundedEvidenceFolder))), ...
    packageOnlySourceIdentity);
writeJson(localCompletionFile,localCompletion);
report=struct('status','complete','caseCount',context.caseCount, ...
    'realizationIds',ids,'maxUE',context.maxUE, ...
    'caseVerificationPassed',core.caseVerificationPassed, ...
    'diagnosticsComplete',core.diagnosticsComplete, ...
    'fixtureKind',context.fixtureKind,'trainingIds',context.trainingIds, ...
    'validationIds',context.validationIds,'testIds',context.testIds, ...
    'runtimeStatus',context.runtimeStatus, ...
    'runtimeModelDataKind',context.runtimeModelDataKind, ...
    'transferReaderPassed',transferReaderPassed, ...
    'externalFixtureAdmissionRejected',externalRejected, ...
    'registrySha256Before',context.registrySha256,'registrySha256After',registryAfter, ...
    'sourceDigest',sourceNow.sourceDigest,'packageFile',portableZip, ...
    'packageSha256',packageSha256,'packageFolder',externalPackage, ...
    'transferFolder',transferFolder,'localCompletionFile',localCompletionFile, ...
    'packageOnlySourceIdentity',packageOnlySourceIdentity, ...
    'engineeringCoreReady',false,'localReady',false, ...
    'externalExperimentComplete',false);
end

function attestation=verifyPackageOnlySourceIdentity(root,outputFolder,context,sourceNow)
currentImplementationDigest=implementationDigest(sourceNow);
attestation=struct('verified',false,'mode','','baselineSourceDigest','', ...
    'baselineImplementationDigest','', ...
    'currentSourceDigest',sourceNow.sourceDigest, ...
    'coreImplementationDigest',char(string(context.implementationDigest)), ...
    'currentImplementationDigest',currentImplementationDigest, ...
    'changedPaths',{{}},'priorPackageVerificationPassed',false, ...
    'coreFunctionsUnchanged',false,'coreOutputSnapshotUnchanged',false, ...
    'coreBoundedEvidenceSuiteSha256','', ...
    'baselineCoreBoundedEvidenceSuitePath','', ...
    'baselinePackagePath','', ...
    'baselinePackageSha256','','baselineHandoffManifestSha256','', ...
    'baselinePackageVerificationPath','','baselinePackageVerificationSha256','', ...
    'baselineSuiteReportPath','','baselineSuiteReportSha256','', ...
    'baselinePreflightPath','','baselinePreflightSha256','', ...
    'coreHashHelperSha256','');

baselineDigest='f09998d09dcb092e19c7ae5dc6a64dd26f8eaf17b7cfc68d2c7e84784bc126cd';
packageSha256='a3d8751749d32e9e37091fef4912efb5849bc3256f72711b2e32ff55b1cf36ba';
handoffSha256='5838b268fc4a1cbbba7a65f8b0062ecbdb15b33489fb0a0f48fa8147729afa9e';
verificationSha256='86545c104104627dcda4bf0b743ee617e882bc1ddc50a4e80d14255fb56a33c3';
suiteSha256='2b81d92576763711aa017ed78fd8722c015d92b4659501043455a6d53bce5922';
preflightSha256='87375824087ca6a35b97f07dc55f10594d20117b9f8dec8d948e408682e5f8a1';
sourceManifestSha256='7a11467cba283e7bf118e72a32f33381d62adff27b6353e6a71cdf1ed52ad2a5';
pipelineReportSha256='0f43041f3030ba2ef490f39658f4f571581db7efd605ad687ce43a33a1783de6';
completionSha256='c26c3d41405fae0f79e8143abd1d7da1062b5ed7af660345f2f8755343ebae33';
hashHelperSha256='7e68441e819e97248068626ddb5b47abb73d6c1d9e876686f4d2d17472111941';
coreSuiteSha256='a6f0154203f308074d447a457766ffcd553dff40b2f71cacc7290ec936c0f186';
preservedFolder=fullfile(root,'verification','local','runtime-review', ...
    'T3','preserved-package-only-012-20261019');
baselineManifestFile=fullfile(preservedFolder,'source-manifest.json');
baselineVerificationFile=fullfile(preservedFolder,'package-verification.json');
baselineSuiteFile=fullfile(preservedFolder,'suite-report.json');
baselinePipelineReportFile=fullfile(preservedFolder,'pipeline-report.json');
baselineCompletionFile=fullfile(preservedFolder,'local-completion.json');
baselinePackageRelative=fullfile('T3c19', ...
    'portable-local-completion-f09998d09dcb.zip');
baselinePackage=fullfile(root,baselinePackageRelative);
baselineTransfer=fullfile(outputFolder,'transfer copy-f09998d09dcb');
baselinePreflightRelative=fullfile('T3c19', ...
    'transfer-preflight-report-f09998d09dcb.json');
baselinePreflight=fullfile(root,baselinePreflightRelative);
expectedSuiteReportRelative= ...
    'verification/local/runtime-review/T3/GREEN-package-only-012-20261019/suite-report.json';
requiredFiles={baselineManifestFile,baselineVerificationFile,baselineSuiteFile, ...
    baselinePipelineReportFile,baselineCompletionFile,baselinePackage, ...
    baselinePreflight,fullfile(baselineTransfer,'handoff-manifest.json')};
if ~all(cellfun(@isfile,requiredFiles))
    error('nbiot:T3:SourceIdentity','A required preserved package-only proof is missing.');
end
assertEvidenceSha256(baselineManifestFile,sourceManifestSha256,'source manifest');
assertEvidenceSha256(baselineVerificationFile,verificationSha256,'package verification');
assertEvidenceSha256(baselineSuiteFile,suiteSha256,'suite report');
assertEvidenceSha256(baselinePipelineReportFile,pipelineReportSha256,'pipeline report');
assertEvidenceSha256(baselineCompletionFile,completionSha256,'local completion');
assertEvidenceSha256(baselinePackage,packageSha256,'portable package');
assertEvidenceSha256(fullfile(baselineTransfer,'handoff-manifest.json'), ...
    handoffSha256,'handoff manifest');
assertEvidenceSha256(baselinePreflight,preflightSha256,'transfer preflight');
assertEvidenceSha256(fullfile(baselineTransfer,'project','src','+nbiot','+ml', ...
    'fileSha256.m'),hashHelperSha256,'baseline file hash helper');
assertEvidenceSha256(fullfile(root,'src','+nbiot','+ml','fileSha256.m'), ...
    hashHelperSha256,'current file hash helper');
baseline=jsondecode(fileread(baselineManifestFile));
if ~isfield(baseline,'schemaVersion')||baseline.schemaVersion~=1|| ...
        ~isfield(baseline,'files')||~isfield(baseline,'sourceDigest')|| ...
        ~strcmpi(baseline.sourceDigest,baselineDigest)|| ...
        ~strcmpi(hashText(jsonencode(baseline.files)),baselineDigest)
    error('nbiot:T3:SourceIdentity', ...
        'The preserved source manifest is not the verified #012 package snapshot.');
end
baselineImplementationDigest=implementationDigest(baseline);
if ~strcmpi(baselineImplementationDigest,char(string(context.implementationDigest)))
    error('nbiot:T3:SourceIdentity', ...
        'The preserved baseline implementation digest does not match the saved core context.');
end

baselinePaths=sort(string({baseline.files.path}));
currentPaths=sort(string({sourceNow.files.path}));
if ~isequal(baselinePaths,currentPaths)
    error('nbiot:T3:SourceIdentity','The package source file set changed after the core pass.');
end
baselineByPath=containers.Map(cellstr(string({baseline.files.path})), ...
    num2cell(1:numel(baseline.files)));
currentByPath=containers.Map(cellstr(string({sourceNow.files.path})), ...
    num2cell(1:numel(sourceNow.files)));
changedPaths=string.empty(0,1);
for k=1:numel(currentPaths)
    path=currentPaths(k);
    old=baseline.files(baselineByPath(char(path)));
    now=sourceNow.files(currentByPath(char(path)));
    if double(old.bytes)~=double(now.bytes)||~strcmpi(old.sha256,now.sha256)
        changedPaths(end+1,1)=path; %#ok<AGROW>
    end
end
changedPaths=sort(changedPaths);
expectedChanges=sort([ ...
    "README.md"; ...
    "docs/current-state.md"; ...
    "docs/local-completion-handoff.md"; ...
    "docs/section-50-readiness.md"; ...
    "docs/superpowers/plans/2026-10-15-local-completion-and-external-experiments/remaining-work-20261018.md"; ...
    "experiments/prepareExternalRun.m"; ...
    "tests/TestLocalCompletionPipeline.m"; ...
    "verification/local/implementation-20261015/T3/runLocalCompletionPipeline.m"]);
if ~isequal(changedPaths,expectedChanges)
    error('nbiot:T3:SourceIdentity', ...
        'Package-only source changes are outside the reviewed, explicitly allowed delta.');
end

previousRunner=fullfile(outputFolder,'transfer copy-f09998d09dcb', ...
    'local-development-evidence','runner','runLocalCompletionPipeline.m');
currentRunner=fullfile(root,'verification','local','implementation-20261015', ...
    'T3','runLocalCompletionPipeline.m');
if ~isfile(previousRunner)
    error('nbiot:T3:SourceIdentity','The preserved baseline runner is missing.');
end
completion=jsondecode(fileread(baselineCompletionFile));
pipelineReport=jsondecode(fileread(baselinePipelineReportFile));
verification=jsondecode(fileread(baselineVerificationFile));
if ~strcmpi(completion.sourceDigest,baselineDigest)|| ...
        ~strcmp(char(string(completion.sourceManifestPath)), ...
            'T3c19/source-manifest.json')|| ...
        ~strcmp(char(string(completion.portablePackage.path)), ...
            strrep(baselinePackageRelative,filesep,'/'))|| ...
        ~strcmpi(completion.portablePackage.sha256,verification.packageSha256)|| ...
        ~strcmpi(completion.portablePackage.manifestSha256,verification.handoffManifestSha256)|| ...
        ~strcmp(char(string(completion.preflightPath)), ...
            strrep(baselinePreflightRelative,filesep,'/'))|| ...
        ~strcmp(char(string(pipelineReport.status)),'complete')|| ...
        ~strcmpi(pipelineReport.sourceDigest,baselineDigest)|| ...
        ~strcmpi(pipelineReport.packageSha256,verification.packageSha256)|| ...
        ~strcmpi(pipelineReport.registrySha256Before,context.registrySha256)|| ...
        ~strcmpi(pipelineReport.registrySha256After,context.registrySha256)|| ...
        ~pipelineReport.transferReaderPassed
    error('nbiot:T3:SourceIdentity','The previous completion/package identity does not match.');
end
if ~strcmp(char(string(verification.status)),'pass')|| ...
        ~strcmp(char(string(verification.suiteReport)),expectedSuiteReportRelative)|| ...
        ~strcmp(char(string(verification.boundedTestMarker)), ...
            'BOUNDED_TEST total=1 passed=1 failed=0 incomplete=0')|| ...
        ~strcmpi(verification.sourceDigest,baselineDigest)|| ...
        double(verification.sourceManifestFileCount)~=numel(baseline.files)|| ...
        ~strcmp(char(string(verification.packagePath)), ...
            strrep(baselinePackageRelative,filesep,'/'))|| ...
        double(verification.maxCaseSeconds)~=300|| ...
        double(verification.maxSuiteSeconds)~=900|| ...
        ~verification.transferReaderPassed|| ...
        ~strcmp(char(string(verification.preflightStatus)), ...
            'structural-pass-stage-blocked-by-missing-scientific-acceptance')|| ...
        ~strcmpi(verification.registrySha256,context.registrySha256)|| ...
        verification.boundedWorkerProcessesRemaining~=0|| ...
        verification.readinessFlags.engineeringCoreReady|| ...
        verification.readinessFlags.localReady|| ...
        verification.readinessFlags.externalExperimentComplete|| ...
        verification.readinessFlags.scientificFinalAcceptance|| ...
        ~verification.traceabilityJsonInZip||~verification.traceabilityJsonInTransferCopy
    error('nbiot:T3:SourceIdentity','The prior package-only verification report is not a passing local proof.');
end
if ~strcmpi(verification.packageSha256,packageSha256)|| ...
        ~strcmpi(verification.handoffManifestSha256,handoffSha256)|| ...
        ~strcmpi(rawFileSha256(baselinePackage),verification.packageSha256)|| ...
        ~strcmpi(rawFileSha256(fullfile(baselineTransfer,'handoff-manifest.json')), ...
            verification.handoffManifestSha256)
    error('nbiot:T3:SourceIdentity','The prior ZIP or handoff manifest hash does not match.');
end
if ~sameCoreRunnerFunctions(previousRunner,currentRunner)
    error('nbiot:T3:SourceIdentity', ...
        'A full-mode entry point, core runner or core verification helper changed after the completed pass.');
end
transferIntegrity=verifyBundleManifest(baselineTransfer);
handoff=jsondecode(fileread(fullfile(baselineTransfer,'handoff-manifest.json')));
if ~transferIntegrity.passed||~strcmpi(handoff.sourceDigest,baselineDigest)|| ...
        numel(handoff.files)~=verification.handoffManifestContentFileCount|| ...
        verification.zipMemberCount~=numel(handoff.files)+1|| ...
        ~isfile(fullfile(baselineTransfer,'project','docs', ...
            'original-spec-traceability-20261019.json'))
    error('nbiot:T3:SourceIdentity','The previous transferred package fails its manifest check.');
end
traceabilityFile=fullfile(baselineTransfer,'project','docs', ...
    'original-spec-traceability-20261019.json');
if ~strcmpi(rawFileSha256(traceabilityFile), ...
        verification.traceabilityJsonSha256)
    error('nbiot:T3:SourceIdentity','The bundled requirement traceability record changed.');
end
coreEvidenceFolder=fullfile(baselineTransfer,'local-development-evidence');
coreSuiteFile=fullfile(coreEvidenceFolder,'bounded-core-suite-report.json');
assertEvidenceSha256(coreSuiteFile,coreSuiteSha256,'bounded core suite report');
coreSuite=jsondecode(fileread(coreSuiteFile));
if ~strcmp(char(string(context.coreBoundedEvidenceFolder)), ...
        'verification/local/runtime-review/T3/GREEN-core-010-20261019')|| ...
        ~strcmp(char(string(coreSuite.status)),'completed')||coreSuite.exitCode~=0|| ...
        coreSuite.elapsedSeconds>300||double(context.maxUE)~=2|| ...
        ~sameCoreOutputSnapshot(outputFolder,coreEvidenceFolder)
    error('nbiot:T3:SourceIdentity', ...
        'The bounded core evidence or saved local core output differs from the preserved #012 proof.');
end
suite=jsondecode(fileread(baselineSuiteFile));
if ~strcmp(char(string(suite.status)),'completed')||suite.exitCode~=0|| ...
        suite.elapsedSeconds>verification.maxCaseSeconds|| ...
        suite.elapsedSeconds>verification.maxSuiteSeconds
    error('nbiot:T3:SourceIdentity','The prior bounded package-only test did not complete successfully.');
end
preflight=jsondecode(fileread(baselinePreflight));
if ~preflight.passed||~preflight.readOnly||preflight.readiness.stageReady|| ...
        preflight.readiness.scientificAccepted|| ...
        ~strcmp(char(string(completion.preflightStatus)), ...
            'structural-pass-stage-blocked-by-missing-scientific-acceptance')
    error('nbiot:T3:SourceIdentity','The prior fixture preflight did not remain stage-blocked.');
end
registryFile=fullfile(root,'experiments','realizationRegistry.json');
if ~strcmpi(rawFileSha256(registryFile),context.registrySha256)
    error('nbiot:T3:SourceIdentity','The authoritative registry differs from the core pass.');
end

attestation=struct('verified',true,'mode','restricted-package-only-deltas', ...
    'baselineSourceDigest',baselineDigest, ...
    'baselineImplementationDigest',baselineImplementationDigest, ...
    'currentSourceDigest',sourceNow.sourceDigest, ...
    'coreImplementationDigest',char(string(context.implementationDigest)), ...
    'currentImplementationDigest',currentImplementationDigest, ...
    'changedPaths',{cellstr(changedPaths)}, ...
    'priorPackageVerificationPassed',true, ...
    'coreFunctionsUnchanged',true, ...
    'coreOutputSnapshotUnchanged',true, ...
    'coreBoundedEvidenceSuiteSha256',coreSuiteSha256, ...
    'baselineCoreBoundedEvidenceSuitePath', ...
        relativeToRoot(root,coreSuiteFile), ...
    'baselinePackagePath',strrep(baselinePackageRelative,'/',filesep), ...
    'baselinePackageSha256',char(string(verification.packageSha256)), ...
    'baselineHandoffManifestSha256',char(string(verification.handoffManifestSha256)), ...
    'baselinePackageVerificationPath',relativeToRoot(root,baselineVerificationFile), ...
    'baselinePackageVerificationSha256',verificationSha256, ...
    'baselineSuiteReportPath',relativeToRoot(root,baselineSuiteFile), ...
    'baselineSuiteReportSha256',suiteSha256, ...
    'baselinePreflightPath',relativeToRoot(root,baselinePreflight), ...
    'baselinePreflightSha256',preflightSha256, ...
    'coreHashHelperSha256',hashHelperSha256);
end

function unchanged=sameCoreOutputSnapshot(outputFolder,baselineCoreFolder)
paths={ ...
    'pipeline-context.json','pipeline-context.json'; ...
    'case-verification.json','case-verification.json'; ...
    'adaptive-runtime-smoke.json','adaptive-runtime-smoke.json'; ...
    fullfile('pipeline-artifacts','cases'),'cases'; ...
    fullfile('pipeline-artifacts','development-dataset'),'development-dataset'; ...
    fullfile('pipeline-artifacts','development-fixture'),'development-fixture'; ...
    fullfile('pipeline-artifacts','model-training'),'model-training'};
unchanged=false;
for k=1:size(paths,1)
    currentPath=fullfile(outputFolder,paths{k,1});
    baselinePath=fullfile(baselineCoreFolder,paths{k,2});
    if isfolder(currentPath)&&isfolder(baselinePath)
        currentFiles=relativeFiles(currentPath);
        baselineFiles=relativeFiles(baselinePath);
        if ~isequal(currentFiles,baselineFiles), return; end
        for j=1:numel(currentFiles)
            currentFile=fullfile(currentPath,strrep(currentFiles{j},'/',filesep));
            baselineFile=fullfile(baselinePath,strrep(baselineFiles{j},'/',filesep));
            if ~strcmpi(rawFileSha256(currentFile),rawFileSha256(baselineFile))
                return
            end
        end
    elseif isfile(currentPath)&&isfile(baselinePath)
        if ~strcmpi(rawFileSha256(currentPath),rawFileSha256(baselinePath)), return; end
    else
        return
    end
end
unchanged=true;
end

function assertEvidenceSha256(file,expectedSha256,label)
if ~isfile(file)||~strcmpi(rawFileSha256(file),expectedSha256)
    error('nbiot:T3:SourceIdentity','The preserved %s evidence is missing or changed.',label);
end
end

function digest=rawFileSha256(file)
if ~isfile(file), error('nbiot:T3:SourceIdentity','A file to hash is missing.'); end
md=java.security.MessageDigest.getInstance('SHA-256');
fid=fopen(file,'rb');
if fid<0, error('nbiot:T3:SourceIdentity','Cannot read an evidence file.'); end
cleanup=onCleanup(@() fclose(fid));
while ~feof(fid)
    bytes=fread(fid,1024*1024,'*uint8');
    if ~isempty(bytes), md.update(typecast(bytes,'int8')); end
end
digest=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

function unchanged=sameCoreRunnerFunctions(previousRunner,currentRunner)
previous=fileread(previousRunner);
current=fileread(currentRunner);
coreFunctions={ ...
    'runLocalCompletionPipeline','runCore','findProjectRoot','canonical', ...
    'resolveProjectPath','assertReusableCoreOutput','validateIds', ...
    'validateDevelopmentIds','unusedComparisonId','makePortableInputs', ...
    'writeDatasetBundle','verifyDatasetArtifacts','verifyCoreArtifacts','relativeFiles', ...
    'implementationDigest','sourceManifest','relativeToRoot','writeJson', ...
    'hashText','verifyBundleManifest'};
unchanged=true;
for k=1:numel(coreFunctions)
    previousBlock=localFunctionBlock(previous,coreFunctions{k},'preserved #012 runner');
    currentBlock=localFunctionBlock(current,coreFunctions{k},'current runner');
    if ~strcmp(previousBlock,currentBlock)
        unchanged=false;
        return
    end
end
end

function section=localFunctionBlock(contents,functionName,sourceLabel)
lines=regexp(contents,'\r\n|\n|\r','split');
starts=[];
for k=1:numel(lines)
    if ~isempty(regexp(lines{k},'^\s*function\>','once'))
        starts(end+1)=k; %#ok<AGROW>
    end
end
matcher=['\<' regexptranslate('escape',functionName) '\s*\('];
matches=[];
for k=1:numel(starts)
    if ~isempty(regexp(lines{starts(k)},matcher,'once'))
        matches(end+1)=starts(k); %#ok<AGROW>
    end
end
if numel(matches)~=1
    if ~isempty(starts)
        firstLine=lines{starts(1)};
    elseif ~isempty(lines)
        firstLine=lines{1};
    else
        firstLine='';
    end
    if numel(firstLine)>96, firstLine=firstLine(1:96); end
    error('nbiot:T3:SourceIdentity', ...
        ['Could not isolate core function "%s" in %s (matching declarations: %d, ' ...
        'function lines: %d, first line: "%s", matcher: "%s").'], ...
        functionName,sourceLabel,numel(matches),numel(starts),firstLine,matcher);
end
nextFunction=find(starts>matches(1),1,'first');
if isempty(nextFunction)
    lastLine=numel(lines);
else
    lastLine=starts(nextFunction)-1;
end
section=strjoin(lines(matches(1):lastLine),newline);
end

function core=verifyCoreArtifacts(root,outputFolder,context)
caseVerificationFile=fullfile(outputFolder,'case-verification.json');
if ~isfile(caseVerificationFile), error('nbiot:T3:CaseVerification','Missing case verification record.'); end
caseRecord=jsondecode(fileread(caseVerificationFile));
if caseRecord.caseCount~=3||numel(caseRecord.cases)~=3
    error('nbiot:T3:CaseVerification','Expected exactly three recorded cases.');
end
for k=1:numel(caseRecord.cases)
    item=caseRecord.cases(k);
    caseFolder=fullfile(root,strrep(char(string(item.caseFolder)),'/',filesep));
    markerFile=fullfile(root,strrep(char(string(item.markerFile)),'/',filesep));
    resultFile=fullfile(root,strrep(char(string(item.resultFile)),'/',filesep));
    verification=nbiot.results.verifyCase(caseFolder);
    if ~verification.passed||~item.passed||~strcmp(verification.status,'completed')|| ...
            ~strcmpi(nbiot.ml.fileSha256(markerFile),char(string(item.markerSha256)))|| ...
            ~strcmpi(nbiot.ml.fileSha256(resultFile),char(string(item.resultSha256)))
        error('nbiot:T3:CaseVerification','A saved case differs from its verification record.');
    end
end
artifactRoot=fullfile(outputFolder,'pipeline-artifacts');
verifyDatasetArtifacts(fullfile(artifactRoot,'development-dataset'));
verifyDatasetArtifacts(fullfile(artifactRoot,'development-fixture'));
modelFile=fullfile(artifactRoot,'model-training',[char(string(context.modelName)) '.mat']);
bundle=nbiot.ml.validateModelBundle(modelFile);
if ~strcmp(char(string(bundle.dataKind)),'development-fixture')|| ...
        ~strcmp(char(string(bundle.status)),'development')
    error('nbiot:T3:Model','Saved model bundle is not a development fixture.');
end
metrics=nbiot.ml.loadModelEvaluationMetrics(modelFile,bundle);
if isempty(metrics)||~all(ismember({'train','validation','test'},string(metrics.split)))
    error('nbiot:T3:Metrics','Saved fixture metrics lack a train/validation/test group.');
end
runtime=jsondecode(fileread(fullfile(outputFolder,'adaptive-runtime-smoke.json')));
if ~strcmp(char(string(runtime.status)),'completed')|| ...
        ~strcmp(char(string(runtime.modelDataKind)),'development-fixture')|| ...
        ~strcmp(char(string(runtime.admissionStatus)),'development-only')|| ...
        ~strcmpi(runtime.modelSha256,nbiot.ml.fileSha256(modelFile))
    error('nbiot:T3:Adaptive','Saved local Adaptive evidence does not match the trained fixture.');
end
core=struct('caseVerificationPassed',true, ...
    'diagnosticsComplete',logical(context.diagnosticsComplete));
end

function verifyDatasetArtifacts(folder)
artifactFile=fullfile(folder,'artifacts.json');
if ~isfile(artifactFile), error('nbiot:T3:Dataset','Missing dataset artifact manifest.'); end
artifact=jsondecode(fileread(artifactFile));
for k=1:numel(artifact.files)
    item=artifact.files(k); file=fullfile(folder,char(string(item.name))); info=dir(file);
    if isempty(info)||info.isdir||double(info.bytes)~=double(item.bytes)|| ...
            ~strcmpi(nbiot.ml.fileSha256(file),char(string(item.sha256)))
        error('nbiot:T3:Dataset','A dataset artifact differs from its manifest.');
    end
end
end

function digest=implementationDigest(manifest)
documentation={'README.md','docs/current-state.md','docs/section-50-readiness.md', ...
    'docs/local-completion-handoff.md', ...
    'docs/superpowers/plans/2026-10-15-local-completion-and-external-experiments/remaining-work-20261018.md'};
entries=manifest.files;
keep=~ismember(string({entries.path}),string(documentation));
digest=hashText(jsonencode(entries(keep)));
end

function root=findProjectRoot(path)
root=fileparts(path);
while ~isfile(fullfile(root,'setupProject.m'))
    parent=fileparts(root);
    if strcmp(parent,root), error('nbiot:T3:Root','Could not locate setupProject.m.'); end
    root=parent;
end
root=canonical(root);
addpath(fullfile(root,'src'),fullfile(root,'configs'),fullfile(root,'experiments'), ...
    fullfile(root,'tests','helpers'),fullfile(root,'verification','external'));
end

function path=canonical(value)
if isstring(value)&&isscalar(value), value=char(value); end
if ~ischar(value)||isempty(strtrim(value)), error('nbiot:T3:Path','A non-empty path is required.'); end
path=char(java.io.File(value).getCanonicalPath());
end

function path=resolveProjectPath(root,value)
if isstring(value)&&isscalar(value), value=char(value); end
if ~ischar(value)||isempty(strtrim(value))
    error('nbiot:T3:Path','A non-empty project path is required.');
end
file=java.io.File(value);
if ~file.isAbsolute(), value=fullfile(root,value); end
path=canonical(value);
end

function assertEmptyOrMissing(folder,label)
if isfile(folder), error('nbiot:T3:Output','%s is already a file.',label); end
if isfolder(folder)
    items=dir(folder); items=items(~ismember({items.name},{'.','..'}));
    if ~isempty(items), error('nbiot:T3:Output','%s must be empty; refusing to overwrite.',label); end
end
end

function assertReusableCoreOutput(folder)
items=dir(folder); items=items(~ismember({items.name},{'.','..'}));
allowed={'pipeline-artifacts','case-verification.json','adaptive-runtime-smoke.json', ...
    'pipeline-context.json','pipeline-report.json','source-manifest.json'};
unexpected=false;
for k=1:numel(items)
    name=items(k).name;
    isTransferCopy=items(k).isdir&&startsWith(name,'transfer copy-');
    isPortableZip=~items(k).isdir&&startsWith(name,'portable-local-completion-')&&endsWith(name,'.zip');
    isPreflightReport=~items(k).isdir&&startsWith(name,'transfer-preflight-report-')&&endsWith(name,'.json');
    if ~ismember(name,allowed)&&~isTransferCopy&&~isPortableZip&&~isPreflightReport
        unexpected=true;
    end
end
if isempty(items)||unexpected
    error('nbiot:T3:Output','The prior output contains unexpected T3 artifacts.');
end
reportFile=fullfile(folder,'pipeline-report.json');
if isfile(reportFile)
    oldReport=jsondecode(fileread(reportFile));
    if isfield(oldReport,'status')&&strcmp(char(string(oldReport.status)),'complete')
        error('nbiot:T3:Output','A completed package output cannot be reopened in full mode.');
    end
end
artifactRoot=fullfile(folder,'pipeline-artifacts');
if ~isfolder(artifactRoot), error('nbiot:T3:Output','The prior artifact folder is missing.'); end
artifacts=dir(artifactRoot); artifacts=artifacts(~ismember({artifacts.name},{'.','..'}));
allowedArtifacts={'cases','development-dataset','development-fixture','model-training'};
if isempty(artifacts)||any(~ismember({artifacts.name},allowedArtifacts))|| ...
        any(~[artifacts.isdir])
    error('nbiot:T3:Output','The prior output contains unexpected pipeline artifacts.');
end
caseRoot=fullfile(artifactRoot,'cases');
if ~isfolder(caseRoot)
    error('nbiot:T3:Output','The prior Static-case directory is missing.');
end
caseItems=dir(caseRoot); caseItems=caseItems(~ismember({caseItems.name},{'.','..'}));
if isempty(caseItems)||any(~ismember({caseItems.name},{'burst_1000ms','manifest.csv'}))
    error('nbiot:T3:Output','The prior case folder contains unexpected outputs.');
end
end

function ids=validateIds(value)
if ~isnumeric(value)||~isvector(value)||numel(value)~=3|| ...
        any(~isfinite(value(:))|value(:)<0|value(:)>=4000|value(:)~=fix(value(:)))|| ...
        numel(unique(value))~=3
    error('nbiot:T3:Ids','Exactly three distinct integer development IDs in 0:3999 are required.');
end
ids=double(value(:).');
end

function validateDevelopmentIds(registry,ids)
if ~isstruct(registry)||~isfield(registry,'assignments')||~isfield(registry,'reservations')
    error('nbiot:T3:Registry','The authoritative registry is malformed.');
end
for id=ids
    matches=0;
    for k=1:numel(registry.assignments)
        item=registry.assignments(k);
        if isfield(item,'ids')&&any(double(item.ids(:))==id)
            matches=matches+1;
            if ~strcmp(char(string(item.role)),'development')|| ...
                    ~strcmp(char(string(item.status)),'completed')
                error('nbiot:T3:Ids','Every case ID must have a completed development allocation.');
            end
        end
    end
    if matches~=1, error('nbiot:T3:Ids','Every case ID must have exactly one registry allocation.'); end
    for k=1:numel(registry.reservations)
        range=double(registry.reservations(k).range(:).');
        if numel(range)==2&&id>=min(range)&&id<=max(range)
            error('nbiot:T3:Ids','A case ID overlaps a reserved range.');
        end
    end
end
end

function id=unusedComparisonId(registry)
used=[];
for k=1:numel(registry.reservations)
    range=double(registry.reservations(k).range(:).');
    if numel(range)==2&&all(isfinite(range)), used=[used range(1):range(2)]; end %#ok<AGROW>
end
for k=1:numel(registry.assignments)
    if isfield(registry.assignments(k),'ids')
        used=[used double(registry.assignments(k).ids(:).')]; %#ok<AGROW>
    end
end
if ~any(strcmp(string(registry.roles),'final-comparison'))
    error('nbiot:T3:Registry','The registry does not declare final-comparison role.');
end
candidates=3000:3999;
at=find(~ismember(candidates,used),1);
if isempty(at), error('nbiot:T3:Registry','No unused test-only comparison ID remains in 3000:3999.'); end
id=candidates(at);
end

function data=makePortableInputs(data,caseRoot)
prefix=[caseRoot filesep];
for k=1:numel(data.manifest.inputs)
    source=char(string(data.manifest.inputs(k).resultFile));
    if ~startsWith(source,prefix,'IgnoreCase',true)
        error('nbiot:T3:Provenance','A case input is outside the new T3 package.');
    end
    tail=source(numel(prefix)+1:end);
    data.manifest.inputs(k).resultFile=strrep(fullfile('..','cases',tail),filesep,'/');
end
end

function writeDatasetBundle(data,folder,fixtureProvenance)
if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'dataset.mat'),'data','-v7.3');
observations=data.observations; observations.caseKey=data.rowInfo.caseKey;
targets=data.targets; targets.caseKey=data.rowInfo.caseKey;
writetable(observations,fullfile(folder,'observations.csv'));
writetable(targets,fullfile(folder,'targets.csv'));
writetable(data.features,fullfile(folder,'features.csv'));
writetable(data.rowInfo,fullfile(folder,'rows.csv'));
manifest=data.manifest;
manifest.assignments=table2struct(manifest.assignments);
writeJson(fullfile(folder,'manifest.json'),manifest);
[summary,coverage]=nbiot.dataset.summarizeLoadDataset(data);
writeJson(fullfile(folder,'dataset-summary.json'),summary);
writetable(coverage,fullfile(folder,'scenario-coverage.csv'));
writetable(data.diagnostics,fullfile(folder,'diagnostics.csv'));
names={'dataset.mat','observations.csv','targets.csv','features.csv','rows.csv', ...
    'manifest.json','dataset-summary.json','scenario-coverage.csv','diagnostics.csv'};
if ~isempty(fixtureProvenance)
    writeJson(fullfile(folder,'fixture-provenance.json'),fixtureProvenance);
    names{end+1}='fixture-provenance.json'; %#ok<AGROW>
end
entries=repmat(struct('name','','bytes',0,'sha256',''),numel(names),1);
for k=1:numel(names)
    file=fullfile(folder,names{k}); info=dir(file);
    if isempty(info)||info.isdir, error('nbiot:T3:Dataset','A dataset artifact was not written.'); end
    entries(k)=struct('name',names{k},'bytes',double(info.bytes), ...
        'sha256',nbiot.ml.fileSha256(file));
end
writeJson(fullfile(folder,'artifacts.json'),struct('schemaVersion',1,'files',entries));
end

function copyDirectory(source,destination)
if ~isfolder(source), error('nbiot:T3:Copy','A required package folder is missing.'); end
if isfolder(destination), error('nbiot:T3:Copy','Refusing to overwrite a package folder.'); end
[ok,message]=copyfile(source,destination);
if ~ok, error('nbiot:T3:Copy','Could not copy local evidence: %s',message); end
end

function path=relativeToRoot(root,file)
prefix=[root filesep]; file=resolveProjectPath(root,file);
if ~startsWith(file,prefix,'IgnoreCase',true)
    error('nbiot:T3:Package','An external-package input is outside the project root.');
end
path=strrep(file(numel(prefix)+1:end),filesep,'/');
end

function manifest=makeBundleManifest(folder,sourceDigest)
names=relativeFiles(folder);
names=names(~strcmp(names,'handoff-manifest.json'));
entries=repmat(struct('name','','bytes',0,'sha256',''),numel(names),1);
for k=1:numel(names)
    path=fullfile(folder,strrep(names{k},'/',filesep)); info=dir(path);
    entries(k)=struct('name',names{k},'bytes',double(info.bytes), ...
        'sha256',nbiot.ml.fileSha256(path));
end
manifest=struct('schemaVersion',1,'kind','local-development-handoff', ...
    'createdAtUtc',utcNow(),'sourceDigest',sourceDigest, ...
    'selfHashExcluded',true,'files',entries);
end

function files=relativeFiles(folder)
files={}; listing=dir(folder);
for k=1:numel(listing)
    if ismember(listing(k).name,{'.','..'}), continue; end
    child=fullfile(folder,listing(k).name);
    if listing(k).isdir
        nested=relativeFiles(child);
        for j=1:numel(nested), files{end+1}=[listing(k).name '/' nested{j}]; end %#ok<AGROW>
    else
        files{end+1}=listing(k).name; %#ok<AGROW>
    end
end
files=sort(files);
end

function archivePackage(folder,manifest,zipFile)
names={manifest.files.name};
names{end+1}='handoff-manifest.json';
if isfile(zipFile), error('nbiot:T3:Archive','Refusing to overwrite the portable ZIP.'); end
zip(zipFile,names,folder);
if ~isfile(zipFile), error('nbiot:T3:Archive','MATLAB did not create the portable ZIP.'); end
end

function result=verifyBundleManifest(folder)
result=struct('passed',false,'fileCount',0,'errors',{{}});
try
    manifest=jsondecode(fileread(fullfile(folder,'handoff-manifest.json')));
    if ~isfield(manifest,'schemaVersion')||manifest.schemaVersion~=1|| ...
            ~isfield(manifest,'files')||~isfield(manifest,'selfHashExcluded')|| ...
            ~manifest.selfHashExcluded
        error('nbiot:T3:Transfer','Unsupported handoff manifest.');
    end
    names={manifest.files.name};
    if numel(unique(names))~=numel(names), error('nbiot:T3:Transfer','Duplicate bundle path.'); end
    for k=1:numel(manifest.files)
        item=manifest.files(k);
        if contains(item.name,'..')||contains(item.name,':')||startsWith(item.name,'/')
            error('nbiot:T3:Transfer','A package path escapes the transfer root.');
        end
        file=fullfile(folder,strrep(item.name,'/',filesep)); info=dir(file);
        if isempty(info)||info.isdir||double(info.bytes)~=double(item.bytes)|| ...
                ~strcmpi(nbiot.ml.fileSha256(file),char(string(item.sha256)))
            error('nbiot:T3:Transfer','A moved package file differs from its manifest.');
        end
    end
    result.passed=true; result.fileCount=numel(manifest.files);
catch exception
    result.errors={exception.message};
end
end

function completion=makeLocalCompletion(sourceDigest,packageSha256,manifestSha256, ...
        registrySha256,portableZip,preflightFile,outputFolder,coreEvidenceFolder, ...
        packageEvidenceFolder,packageOnlySourceIdentity)
taskStates=repmat(struct('task','','status','','scope','','report',''),8,1);
taskStates(1)=struct('task','D3','status','programming-and-integration-checked', ...
    'scope','development cases/dataset only','report','verification/local/implementation-20261015/T3');
taskStates(2)=struct('task','D4','status','programming-accepted; science-open', ...
    'scope','development-fixture only','report','verification/local/runtime-review/D4/runtime-integration-20261018');
taskStates(3)=struct('task','R4','status','R4.1-11 accepted; R4.12 blocked-by-owner-scope', ...
    'scope','historical run untouched','report','verification/local/runtime-review/R4/remaining-acceptance-20261018');
taskStates(4)=struct('task','T1','status','independent-review-PASS-after-package-corrections', ...
    'scope','package/preflight software workflow; no external stage executed', ...
    'report','verification/local/runtime-review/T1-T2-corrections-20261019/final-review.md');
taskStates(5)=struct('task','T2','status','independent-review-PASS-after-dispatch-corrections', ...
    'scope','process/dispatch software workflow; no external stage executed', ...
    'report','verification/local/runtime-review/T1-T2-corrections-20261019/final-review.md');
taskStates(6)=struct('task','U3-refresh','status','documents reconciled; professor answers pending', ...
    'scope','no decision inferred','report','docs/requirements-decisions.md');
reviewReportPath=sprintf( ...
    'verification/local/runtime-review/T3/package-identity-review-%s.md', ...
    sourceDigest(1:12));
taskStates(7)=struct('task','T3', ...
    'status','independent-review-pending; bounded-package-only-PASS; local-development-only', ...
    'scope','local development integration only','report', ...
    reviewReportPath);
taskStates(8)=struct('task','External/scientific','status','not-run; not-accepted', ...
    'scope','not authorized by this local fixture','report','docs/local-completion-handoff.md');

requirementDecisions=repmat(struct('id','','implementation','','testOrEvidence','', ...
    'reviewerEvidence','','status','','remainingDecision',''),12,1);
entries={ ...
    'F1','D3 window diagnostics and existing radio diagnostics','TestDatasetDiagnostics; TestRadioDiagnosticsExport; T3 diagnosticsComplete','D3 correction-006c-fix-005 review PASS','engineering-programming-accepted','Large-load performance remains unmeasured'; ...
    'F2','R4 checkpoint/write path and bounded recovery controls','accepted R1-R4 reports and current R4 matrix','R4.1-11 SPEC/QUALITY PASS','R4.1-11 accepted','R4.12 remains blocked-by-owner-scope'; ...
    'F3','T1/T2 bounded runner, state and stale-dependency gates','T2 process-only final recheck 36/36; parser 2/2; corrected dispatch review','T1/T2 corrections independent SPEC/QUALITY PASS','engineering-programming-accepted','No external stage has executed'; ...
    'F4','D4 runtime admission and local Adaptive integration','TestModelAcceptance; TestAdaptiveIntegration; T3 external negative gate','D4-I review PASS; T3 transfer preflight blocks fixture','programming-accepted','Scientific admission and approved thresholds remain open'; ...
    'F5','T1 package reader, model sidecar and T3 moved ZIP','TestExternalRunPackage 19/19; TestExternalPreflight; TestExternalStageContracts 6/6','T1/T2 corrections independent SPEC/QUALITY PASS; current T3 bounded package-only evidence','bounded-transfer-checked','External package remains not ready'; ...
    'F6','Canonical feature whitelist and development training wrapper','TestLoadModels; TestLocalCompletionPipeline','D4-R1/D4-A reviews PASS','programming-accepted','Candidate training requires external allocation evidence'; ...
    'F7','Hash-bound training metrics and model metadata','TestModelEvaluationMetrics; TestLoadModels','D4-R1 and D2 reviews PASS','programming-accepted','Fixture scores are not scientific evidence'; ...
    'F8','D3 window diagnostics, artifacts manifest and dataset assembly','TestDatasetDiagnostics; TestLoadDataset; T3 three-case assembly','D3 correction review PASS; T3 package review pending','development-integration-checked','Scientific dataset admission remains open'; ...
    'F9','U5 live report/UI and current diagnostics','TestExternalGuiProfile; TestAdaptiveIntegration; GUI reports','U5/D4-I programming reviews PASS','programming-core-accepted','Manual saved-100-UE visual review remains open'; ...
    'F10','U3 requirement/GUI/profile reconciliation','docs/requirements-decisions.md; docs/section-50-readiness.md','U3 source reconciliation; T3 handoff review pending','documented-awaiting-professor','Four professor decision rows remain awaiting-professor'; ...
    'F11','Metrics contract and censor-aware capture definitions','TestRadioDiagnosticsExport; D3/R4 accepted evidence','D3 and R4.1-11 review reports PASS','programming-definition-accepted','No full-horizon new load experiment was run'; ...
    'F12','One local completion manifest, portable package and handoff','TestLocalCompletionPipeline bounded package-only; local-completion.json','T3 independent review pending; bounded package-only run completed by this manifest','package-pending-independent-review','localReady and externalExperimentComplete remain false'};
for k=1:size(entries,1)
    requirementDecisions(k)=struct('id',entries{k,1},'implementation',entries{k,2}, ...
        'testOrEvidence',entries{k,3},'reviewerEvidence',entries{k,4}, ...
        'status',entries{k,5},'remainingDecision',entries{k,6});
end
root=findProjectRoot(mfilename('fullpath'));
reports={ ...
    'verification/local/runtime-review/T1-T2-corrections-20261019/final-review.md', ...
    'verification/local/runtime-review/D4/runtime-integration-20261018/final-stage2-review-001/review-report.md', ...
    'verification/local/runtime-review/R4/remaining-acceptance-20261018/review-report.md', ...
    reviewReportPath, ...
    relativeToRoot(root,fullfile(coreEvidenceFolder,'suite-report.json')), ...
    relativeToRoot(root,fullfile(packageEvidenceFolder,'suite-report.json')), ...
    relativeToRoot(root,preflightFile)};
completion=struct('schemaVersion',1,'planVersion','2026-10-15; remaining-work 2026-10-18; T3 execution 2026-10-19', ...
    'generatedAtUtc',utcNow(),'sourceDigest',sourceDigest, ...
    'sourceManifestPath',relativeToRoot(root, ...
        fullfile(outputFolder,'source-manifest.json')), ...
    'taskStates',taskStates,'reports',{reports}, ...
    'requirementDecisions',requirementDecisions, ...
    'auditCoverage',struct('source','docs/project-audit-2026-10-15.md', ...
        'originalTermsOfReferenceSectionsReviewed',65, ...
        'section50ReadinessConditions',27, ...
        'traceability','F1-F12 are mapped above; individual §50 statuses remain in docs/section-50-readiness.md.'), ...
    'registrySha256',registrySha256, ...
    'portablePackage',struct('path',relativeToRoot(root,portableZip), ...
        'sha256',packageSha256,'manifestSha256',manifestSha256), ...
    'packageOnlySourceIdentity',packageOnlySourceIdentity, ...
    'engineeringCoreReady',false,'engineeringCoreReason', ...
        'R4.12 remains required by the current scope and blocked by owner authorization.', ...
    'localReady',false,'localReadyReason', ...
        'Professor decisions (U3), the R4.12 owner gate and the manual GUI visual gate remain open.', ...
    'externalExperimentComplete',false,'scientificFinalAcceptance',false, ...
    'remainingExternalStages',{{ ...
        'Resolve U3 professor decisions without inferring answers.', ...
        'Resolve the owner scope for R4.12 before any protected historical preview.', ...
        'Complete the separate saved-report visual review.', ...
        'Obtain approved scientific protocol, thresholds, resource budget and independent scientific reviewer.', ...
        'On the approved external machine only: prepare real data, train/freeze/evaluate/admit the model, run comparisons and prepare the final scientific report.'}}, ...
    'preflightPath',relativeToRoot(root,preflightFile), ...
    'preflightStatus','structural-pass-stage-blocked-by-missing-scientific-acceptance');
end

function manifest=sourceManifest(root)
paths={ ...
    'README.md','docs/current-state.md','docs/section-50-readiness.md', ...
    'docs/local-completion-handoff.md', ...
    'docs/superpowers/plans/2026-10-15-local-completion-and-external-experiments/remaining-work-20261018.md', ...
    'experiments/runStaticSweep.m','experiments/buildLoadDataset.m', ...
    'experiments/trainLoadModels.m','experiments/prepareExternalRun.m', ...
    'src/+nbiot/NBIoTSimulator.m','src/+nbiot/+dataset/assembleLoadDataset.m', ...
    'src/+nbiot/+dataset/summarizeLoadDataset.m','src/+nbiot/+ml/trainLoadModels.m', ...
    'src/+nbiot/+ml/validateModelBundle.m','src/+nbiot/+ml/loadModelEvaluationMetrics.m', ...
    'src/+nbiot/+ml/validateModelAcceptance.m','src/+nbiot/+controller/prepareRuntime.m', ...
    'configs/adaptiveDefaults.m','src/+nbiot/+experiments/validateExecutionBudget.m', ...
    'src/+nbiot/+results/saveResult.m','src/+nbiot/+results/verifyCase.m', ...
    'src/+nbiot/+config/defaultConfig.m','configs/mlTrainingDefaults.m', ...
    'verification/external/validateExternalPreflight.m', ...
    'verification/local/runBoundedChecks.ps1','tests/TestLocalCompletionPipeline.m', ...
    'verification/local/implementation-20261015/T3/runLocalCompletionPipeline.m'};
paths=sort(paths);
entries=repmat(struct('path','','bytes',0,'sha256',''),numel(paths),1);
for k=1:numel(paths)
    file=fullfile(root,strrep(paths{k},'/',filesep)); info=dir(file);
    if isempty(info)||info.isdir
        error('nbiot:T3:SourceManifest','A required source-manifest file is missing: %s',paths{k});
    end
    entries(k)=struct('path',paths{k},'bytes',double(info.bytes), ...
        'sha256',nbiot.ml.fileSha256(file));
end
digest=hashText(jsonencode(entries));
manifest=struct('schemaVersion',1,'files',entries,'sourceDigest',digest);
end

function writeJson(file,value)
parent=fileparts(file);
if ~isfolder(parent), mkdir(parent); end
fid=fopen(file,'w','n','UTF-8');
if fid<0, error('nbiot:T3:Write','Cannot create JSON artifact.'); end
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(jsonencode(value,'PrettyPrint',true),'UTF-8'),'uint8');
end

function writeText(file,value)
parent=fileparts(file);
if ~isfolder(parent), mkdir(parent); end
fid=fopen(file,'w','n','UTF-8');
if fid<0, error('nbiot:T3:Write','Cannot create text artifact.'); end
cleanup=onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(value,'UTF-8'),'uint8');
end

function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function digest=hashText(value)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(uint8(unicode2native(value,'UTF-8')),'int8'));
digest=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
