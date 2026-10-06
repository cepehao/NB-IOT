classdef TestExport < matlab.unittest.TestCase
 methods(Test)
  function independentCountsNaNsAndIncompleteRunsAreExplicit(t)
   [manifest,folder]=fixtures(t);
   output=fullfile(folder,'plots'); report=plotSweepSummary(manifest,output);
   t.verifyEqual(report.conditions.totalRuns,3); t.verifyEqual(report.conditions.completedRuns,2);
   t.verifyEqual(report.conditions.partialRuns,1); t.verifyEqual(report.conditions.integrityFailures,0);
   row=report.metrics(strcmp(report.metrics.metric,'meanDelayTicks'),:);
   t.verifyEqual(row.finiteRuns,0); t.verifyTrue(isnan(row.mean)); t.verifyTrue(isnan(row.ci95Low));
   t.verifyTrue(isfile(fullfile(output,'summary.png')));
   exported=readtable(fullfile(output,'metrics.csv'),'TextType','string');
   t.verifyEqual(height(exported),height(report.metrics)); t.verifyEqual(exported.finiteRuns,report.metrics.finiteRuns);
  end
  function duplicateRealizationIsRejected(t)
   [manifest,folder]=fixtures(t); manifest.realizationId(2)=manifest.realizationId(1);
   t.verifyError(@() plotSweepSummary(manifest,fullfile(folder,'duplicate')),'nbiot:results:DuplicateRealization');
  end
  function mixedReceiverVersionsAreRejected(t)
   [manifest,folder]=fixtures(t); manifest.sourceSha256{2}=repmat('b',1,64);
   t.verifyError(@() plotSweepSummary(manifest,fullfile(folder,'mixed')),'nbiot:results:MixedVersions');
  end
 end
end
function [manifest,folder]=fixtures(t)
folder=tempname; mkdir(folder); t.addTeardown(@() cleanupFolder(folder)); rows={};
for id=0:2
 cfg=nbiot.config.defaultConfig(); cfg.simulation.numUE=1; cfg.simulation.durationTicks=500;
 cfg.simulation.realizationId=id; cfg.traffic.kind='none'; cfg.phy.nprachThreshold=1;
 sim=nbiot.NBIoTSimulator(cfg); if id==2, sim.run(100); else, sim.run(); end; result=sim.result();
 caseKey=sprintf('test_r%d',id); caseFolder=fullfile(folder,caseKey);
 metadata=struct('caseKey',caseKey,'configSha256',nbiot.results.configSha256(cfg),...
  'sourceSha256',repmat('a',1,64),'calibrationSha256',repmat('c',1,64),'environment',result.environment);
 nbiot.results.saveResult(result,caseFolder,metadata);
 marker=jsondecode(fileread(fullfile(caseFolder,'case-complete.json')));
 rows(end+1,:)={1,100,id,result.status,0,fullfile(caseFolder,marker.resultFile),caseKey,...
  metadata.configSha256,metadata.sourceSha256,metadata.calibrationSha256}; %#ok<AGROW>
end
manifest=cell2table(rows,'VariableNames',{'numUE','burstDurationTicks','realizationId','status',...
 'elapsedSeconds','resultFile','caseKey','configSha256','sourceSha256','calibrationSha256'});
end
function cleanupFolder(folder)
assert(startsWith(char(java.io.File(folder).getCanonicalPath()),...
 char(java.io.File(tempdir).getCanonicalPath()),'IgnoreCase',true));
if isfolder(folder), rmdir(folder,'s'); end
end
