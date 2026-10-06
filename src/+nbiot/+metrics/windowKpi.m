function series=windowKpi(cfg,packets,attempts,observed,actualTick)
%WINDOWKPI Interval events and arrival cohorts have distinct denominators.
names={'windowId','startTick','endTick','created','deliveredInWindow','droppedInWindow', ...
    'cohortDelivered','cohortDropped','cohortUnfinished','cohortDeliveryProbability', ...
    'raStarted','raSucceededInWindow','raFailedInWindow','ulTbDecoded','ulCrcFailures','throughputBitsPerSecond'};
rows={};
for first=0:cfg.dataset.windowTicks:actualTick-1
    last=min(first+cfg.dataset.windowTicks,actualTick);
    created=0; delivered=0; dropped=0; cohortDelivered=0; cohortDropped=0; cohortUnfinished=0;
    for p=reshape(packets,1,[])
        inCohort=double(p.createdTick)>=first && double(p.createdTick)<last;
        created=created+inCohort;
        delivered=delivered+(strcmp(p.status,'delivered') && p.deliveredTick>first && p.deliveredTick<=last);
        dropped=dropped+(strcmp(p.status,'dropped') && p.terminalTick>=first && p.terminalTick<last);
        if inCohort
            cohortDelivered=cohortDelivered+strcmp(p.status,'delivered');
            cohortDropped=cohortDropped+strcmp(p.status,'dropped');
            cohortUnfinished=cohortUnfinished+strcmp(p.status,'unfinished');
        end
    end
    started=0; succeeded=0; failed=0;
    for a=reshape(attempts,1,[])
        started=started+(a.startTick>=first && a.startTick<last);
        succeeded=succeeded+(strcmp(a.status,'success') && a.endTick>first && a.endTick<=last);
        failed=failed+(strcmp(a.status,'failure') && a.endTick>=first && a.endTick<last);
    end
    decoded=0; crcFailures=0;
    for e=reshape(observed,1,[])
        if e.tick>first && e.tick<=last && strcmp(e.kind,'phy_decode') && e.fields.hasCrc
            decoded=decoded+1; crcFailures=crcFailures+double(e.fields.crcError~=0);
        end
    end
    if created==0, probability=NaN; else, probability=cohortDelivered/created; end
    throughput=delivered*cfg.traffic.packetBytes*8/((last-first)*cfg.simulation.tickSeconds);
    rows(end+1,:)={floor(first/cfg.dataset.windowTicks)+1,first,last,created,delivered,dropped, ...
        cohortDelivered,cohortDropped,cohortUnfinished,probability,started,succeeded,failed,decoded,crcFailures,throughput}; %#ok<AGROW>
end
if isempty(rows), series=array2table(zeros(0,numel(names)),'VariableNames',names);
else, series=cell2table(rows,'VariableNames',names); end
series.Properties.Description='Arrivals/drops/starts use [start,end); receiver completions use (start,end]. Cohorts classified at export horizon.';
end
