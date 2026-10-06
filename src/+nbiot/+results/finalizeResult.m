function result=finalizeResult(cfg,scenario,packets,attempts,observed,truth,usage,actualTick,status,stopReason,errorInfo)
%FINALIZERESULT Export completed, partial and failed runs without fake drops.
result=struct('config',cfg,'scenario',scenario,'status',status,'stopReason',stopReason, ...
    'actualTick',actualTick,'error',errorInfo,'randomness',scenario.randomManifest);
result.resultSchemaVersion=2;
result.environment=struct('matlabVersion',version,'release',version('-release'),'lteVersion',ver('lte'), ...
    'computer',computer,'validatedInMatlab',false,'sourceProfile','static-v1');
result.packetLog=packets; result.raLog=attempts; result.observedLog=observed; result.truthLog=truth;
result.phyLog=[observed(strcmp({observed.kind},'phy_decode'));truth(strcmp({truth.kind},'phy_decode'))];
result.kpiSummary=nbiot.metrics.summarizeKpi(cfg,packets,attempts,observed,truth,usage,actualTick);
result.kpiTimeSeries=nbiot.metrics.windowKpi(cfg,packets,attempts,observed,actualTick);
ids=(1:cfg.simulation.numUE).'; created=zeros(size(ids)); delivered=created; dropped=created; unfinished=created;
for p=packets
    u=double(p.ueId); created(u)=created(u)+1;
    switch p.status
        case 'delivered', delivered(u)=delivered(u)+1;
        case 'dropped', dropped(u)=dropped(u)+1;
        case 'unfinished', unfinished(u)=unfinished(u)+1;
    end
end
result.ueSummary=table(ids,created,delivered,dropped,unfinished,'VariableNames',{'ueId','created','delivered','dropped','unfinished'});
result.resourceUsage=usage;
end
