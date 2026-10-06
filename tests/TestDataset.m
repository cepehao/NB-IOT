classdef TestDataset < matlab.unittest.TestCase
    methods (Test)
        function observationDoesNotUseLabels(t)
            e=struct('tick',{},'kind',{},'fields',{});
            [a,x]=nbiot.dataset.closeWindow(e,e,0,500,1000,1500,0,0);
            [b,y]=nbiot.dataset.closeWindow(e,e,0,500,9000,8000,0,0);
            t.verifyEqual(a,b); t.verifyNotEqual(x,y); t.verifyEqual(a{5},0);
        end
        function rejectsUeDecoderLeakage(t)
            e=struct('tick',10,'kind','phy_decode','fields',struct('receiverId',1));
            empty=struct('tick',{},'kind',{},'fields',{});
            t.verifyError(@() nbiot.dataset.closeWindow(e,empty,0,500,0,0,0,0),'nbiot:dataset:Leakage');
        end
        function splitsEntireIndependentRealizations(t)
            manifest=nbiot.dataset.buildManifest(0:99);
            t.verifyEqual([sum(manifest.split=="train") sum(manifest.split=="validation") sum(manifest.split=="test")],[70 15 15]);
            t.verifyEqual(height(manifest),numel(unique(manifest.externalRealizationId)));
        end
    end
end
