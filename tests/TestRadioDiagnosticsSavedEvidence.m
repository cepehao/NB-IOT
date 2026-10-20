classdef TestRadioDiagnosticsSavedEvidence < matlab.unittest.TestCase
    methods (Test)
        function recomputesDiagnosticsFromAuditedCompletedHundredDeviceResult(t)
            projectRoot=fileparts(fileparts(mfilename('fullpath')));
            auditRelative=['verification' filesep 'local' filesep 'audit-20261015' ...
                filesep 'saved-evidence-verification.json'];
            audit=jsondecode(fileread(fullfile(projectRoot,auditRelative)));

            markerRelative=['verification' filesep 'completion' filesep 'stage-3' ...
                filesep 'variant2-20261014-152828-532-04934654' filesep 'probe' ...
                filesep 'n00100-id1088' filesep ...
                'run-13b11a71-e215-4f09-bf73-57e7dcea6f22' filesep 'case-complete.json'];
            markerRecord=find(strcmp({audit.completedCases.path},markerRelative));
            t.assertEqual(numel(markerRecord),1, ...
                'The selected result must be listed exactly once in the saved audit.');
            t.assertEqual(audit.completedCases(markerRecord).status,'completed');

            markerPath=fullfile(projectRoot,markerRelative);
            t.assertTrue(isfile(markerPath),'The audited case marker must still exist.');
            marker=jsondecode(fileread(markerPath));
            t.assertEqual(marker.status,'completed');
            t.assertEqual(marker.resultFile,'static-v1_n100_r1088.mat');
            t.assertEqual(marker.balances.created,100);

            resultFileRelative=fullfile(fileparts(markerRelative),marker.resultFile);
            resultPath=fullfile(projectRoot,resultFileRelative);
            t.assertTrue(isfile(resultPath),'The audited result MAT file must still exist.');
            markerFile=find(strcmp({marker.files.name},marker.resultFile));
            t.assertEqual(numel(markerFile),1);
            expectedSha=lower(marker.files(markerFile).sha256);
            auditCheck=find(strcmp({audit.checks.path},resultFileRelative));
            t.assertEqual(numel(auditCheck),1, ...
                'The selected MAT file must have one exact audit hash record.');
            t.assertTrue(audit.checks(auditCheck).passed, ...
                'The saved audit must have verified the selected MAT file.');
            t.assertEqual(lower(audit.checks(auditCheck).expectedSha256),expectedSha);
            t.assertEqual(lower(audit.checks(auditCheck).actualSha256),expectedSha);
            t.assertEqual(nbiot.ml.fileSha256(resultPath),expectedSha, ...
                'The saved MAT must still match the hash in the audited case marker.');

            saved=load(resultPath,'result');
            t.assertTrue(isfield(saved,'result'));
            result=saved.result;
            t.assertEqual(result.status,'completed');
            t.assertEqual(result.config.simulation.numUE,100);
            t.assertTrue(isfield(result,'radioDiagnostics'));
            t.assertTrue(isfield(result,'radioReceptionLog'));

            options=struct('actualTick',double(result.actualTick), ...
                'nInitValues',0:(double(result.config.ra.numSubcarriers)-1));
            actual=nbiot.metrics.radioDiagnostics(result.truthLog, ...
                result.observedLog,result.radioReceptionLog,options);

            t.verifyTrue(isequaln(actual,result.radioDiagnostics), ...
                'Recomputed diagnostics must exactly match the audited saved struct.');
        end
    end
end
