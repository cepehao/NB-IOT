classdef TestMetrics < matlab.unittest.TestCase
    methods (Test)
        function countsCensoredWorkAndUniqueBits(t)
            cfg=nbiot.config.defaultConfig();
            p=repmat(struct('status','unfinished','createdTick',0,'deliveredTick',NaN),1,3);
            p(1).status='delivered'; p(1).deliveredTick=500; p(2).status='dropped';
            a=struct('status',{'success','unfinished'},'collision',{false,true});
            empty=struct('tick',{},'kind',{},'fields',{});
            k=nbiot.metrics.summarizeKpi(cfg,p,a,empty,empty,table(),5000);
            t.verifyEqual([k.created k.delivered k.dropped k.unfinished],[3 1 1 1]);
            t.verifyEqual(k.raSuccessProbability,.5); t.verifyEqual(k.raSuccessCompletedProbability,1);
            t.verifyEqual(k.throughputBitsPerSecond,320); t.verifyEqual(k.meanDelayTicks,500);
            t.verifyTrue(isnan(k.dataBler));
        end
        function occupancyCountsOverlappingUeOnce(t)
            cfg=nbiot.config.defaultConfig(); f=struct('ticks',1:8,'frequencyStartHz',0,'bandwidthHz',45000,'direction','UL');
            e=repmat(struct('tick',1,'kind','transmission','fields',f),2,1);
            empty=struct('tick',{},'kind',{},'fields',{});
            k=nbiot.metrics.summarizeKpi(cfg,[],[],empty,e,table(),5000);
            t.verifyEqual(k.ulOccupiedUnits,8*2*12);
        end
    end
end
