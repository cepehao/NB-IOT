classdef TestV4Package < matlab.unittest.TestCase
    methods (Test)
        function computationalSourcesMatchThisRelease(t)
            root=fileparts(fileparts(mfilename('fullpath')));
            frozen=jsondecode(fileread(fullfile(root,'verification','v4','source-manifest.json')));
            actual=optimizationSourceManifest(root);
            t.verifyEqual(actual.sha256,frozen.computationalSourceSha256);
            t.verifyEqual(numel(actual.files),numel(frozen.files));
        end
        function runtimeFunctionsResolveInsideThisCopy(t)
            root=fileparts(fileparts(mfilename('fullpath')));
            functions={'startNBIoT','openNBIoTApp','nbiot.NBIoTSimulator', ...
                'nbiot.metrics.RadioDiagnosticsAccumulator','nbiot.results.verifyCase'};
            for name=functions
                resolved=which(name{1});
                t.verifyTrue(startsWith(resolved,[root filesep],'IgnoreCase',true), ...
                    ['Function resolved outside the unpacked release: ' name{1}]);
            end
        end
        function everyPackagedFileMatchesItsManifest(t)
            root=fileparts(fileparts(mfilename('fullpath')));
            manifest=jsondecode(fileread(fullfile(root,'PACKAGE-MANIFEST.json')));
            t.verifyEqual(manifest.release,'v4.0.0');
            for k=1:numel(manifest.files)
                entry=manifest.files(k);
                filename=fullfile(root,strrep(entry.file,'/',filesep));
                t.assertTrue(isfile(filename),entry.file);
                info=dir(filename);
                t.verifyEqual(info.bytes,entry.bytes,entry.file);
                fid=fopen(filename,'rb');
                cleanup=onCleanup(@() fclose(fid));
                digest=java.security.MessageDigest.getInstance('SHA-256');
                while ~feof(fid)
                    data=fread(fid,1048576,'*uint8');
                    if ~isempty(data)
                        digest.update(typecast(data,'int8'));
                    end
                end
                clear cleanup
                bytes=typecast(digest.digest(),'uint8');
                hex=lower(reshape(dec2hex(bytes,2).',1,[]));
                t.verifyEqual(hex,entry.sha256,entry.file);
            end
        end
    end
end
