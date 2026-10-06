function s=featureSchema()
%FEATURESCHEMA Only receiver/BS-known sources are allowed in observations.
s.version='static-v1.0';
s.observationNames={'realizationId','windowId','startTick','endTick','detectedCandidates', ...
    'meanPeakMetric','maxPeakMetric','meanRxEnergyW','ulTbDecodes','ulCrcFailures', ...
    'rarSent','grantsSent','pendingRequestsMean'};
s.targetNames={'realizationId','windowId','startTick','endTick','meanRaUe', ...
    'meanActiveUe','meanWaitingQueuePerUe','msg1Transmissions','uniqueMsg1Ue'};
s.allowedObservationKinds={'nprach_detection','phy_decode','rar_sent','grant','bs_queue'};
s.units={'count','count','ms','ms','count','dimensionless','dimensionless','W', ...
    'count','count','count','count','count'};
s.availability='Event tick is receiver completion or BS decision time; windows are [startTick,endTick).';
s.excludedSources={'true UE queue','true collision labels','UE DL CRC outcomes','true channel taps','packet arrivals'};
end
