classdef NBIoTSimulator < handle
    %NBIOTSIMULATOR Sequential waveform simulation with independent UE/BS state.
    % No channel quality/true collision label decides any receiver outcome.
    properties (SetAccess=private)
        cfg
        scenario
        currentTick = 0
        status = 'ready'
        stopReason = ''
        errorInfo = struct()
        devices
        packets
        contexts
        calendar
        scheduler
        channel
        attempts = struct('attemptId',{},'ueId',{},'packetId',{},'occasionId',{}, ...
            'nInit',{},'startTick',{},'endTick',{},'status',{},'collision',{},'capture',{})
    end
    properties (Access=private)
        sources
        receiveQueue
        observed
        truth
        harqJournal
        queueSamples = zeros(0,3)
        occasions
        nextTick = 0
        arrivalCursor = 1
        monitorQueued = false
        tokens
        observationRows = {}
        targetRows = {}
        raIntegral = 0
        activeIntegral = 0
        queueIntegral = 0
        elapsedSeconds = 0
        stopRequested = false
        resultCache = []
    end
    methods
        function obj=NBIoTSimulator(cfg,scenario)
            if nargin<1, cfg=nbiot.config.defaultConfig(); end
            obj.cfg=nbiot.config.validateConfig(cfg);
            obj.sources=nbiot.randomness.RandomSources(cfg.simulation.seed,cfg.simulation.realizationId);
            if nargin<2 || isempty(scenario), scenario=nbiot.scenario.buildScenario(cfg,obj.sources); end
            obj.validateScenario(scenario); obj.scenario=scenario;
            obj.devices=nbiot.devices.DeviceStore(cfg.simulation.numUE);
            obj.packets=nbiot.traffic.PacketStore(cfg); obj.contexts=nbiot.ra.RaContextStore();
            obj.calendar=nbiot.scheduler.ResourceCalendar(cfg);
            obj.scheduler=nbiot.scheduler.Scheduler(cfg,obj.calendar);
            obj.channel=nbiot.channel.RadioChannel(cfg,scenario,obj.sources);
            obj.receiveQueue=nbiot.engine.EventQueue();
            obj.observed=nbiot.results.EventLog(); obj.truth=nbiot.results.EventLog();
            obj.harqJournal=nbiot.results.EventLog();
            obj.occasions=obj.scheduler.reserveNprach();
            obj.tokens=containers.Map('KeyType','char','ValueType','logical');
        end
        function run(obj,untilTick)
            if nargin<2, untilTick=obj.cfg.simulation.durationTicks; end
            validateattributes(untilTick,{'numeric'},{'scalar','integer','>=',obj.currentTick,'<=',obj.cfg.simulation.durationTicks});
            if any(strcmp(obj.status,{'completed','stopped','failed'})), return; end
            obj.status='running'; clockStart=tic;
            try
                nbiot.phy.requireToolbox();
                if ~isfinite(obj.cfg.phy.nprachThreshold)
                    error('nbiot:phy:Calibration','Run examples/calibrateNprach.m and load its threshold before a KPI experiment.');
                end
                while obj.nextTick<=untilTick && ~obj.stopRequested, obj.step(); end
                if obj.stopRequested, obj.status='stopped';
                elseif obj.nextTick>obj.cfg.simulation.durationTicks, obj.status='completed'; obj.stopReason='horizon';
                else, obj.status='partial'; end
            catch exception
                obj.status='failed'; obj.stopReason='exception';
                obj.errorInfo=struct('identifier',exception.identifier,'message',exception.message,'stack',exception.stack);
            end
            obj.elapsedSeconds=obj.elapsedSeconds+toc(clockStart);
            obj.resultCache=[];
        end
        function step(obj)
            if any(strcmp(obj.status,{'completed','stopped','failed'})) || obj.stopRequested, return; end
            obj.resultCache=[];
            now=obj.nextTick; obj.currentTick=now; obj.monitorQueued=false;
            % Complete physical receptions first, including the horizon boundary.
            ready=obj.receiveQueue.popReady(now);
            for k=1:numel(ready), obj.handleReceive(ready(k)); end
            if now<obj.cfg.simulation.durationTicks
                expired=obj.packets.expireLifetime(now);
                for u=1:obj.cfg.simulation.numUE
                    d=obj.devices.get(u);
                    if ismember(d.packetId,double(expired))
                        if d.attemptId>0 && strcmp(obj.attempts(d.attemptId).status,'started')
                            obj.attempts(d.attemptId).status='failure';
                            obj.attempts(d.attemptId).endTick=now;
                        end
                        obj.devices.reset(u);
                    end
                end
                obj.advanceTimers(); obj.addArrivals(); obj.activateHeads();
            end
            if now>0 && (mod(now,obj.cfg.dataset.windowTicks)==0 || now==obj.cfg.simulation.durationTicks)
                first=floor((now-1)/obj.cfg.dataset.windowTicks)*obj.cfg.dataset.windowTicks;
                obj.closeWindow(first,now);
            end
            if now<obj.cfg.simulation.durationTicks
                mandatory=nbiot.phy.buildMandatoryTransmission(obj.cfg,now);
                if ~isempty(mandatory), obj.channel.add(mandatory); end
                obj.emitNprach(); obj.schedulePending(); obj.queueMonitoring();
                [ra,~]=obj.devices.counts();
                work=0; waiting=0; totalQueued=0; maxQueued=0;
                for u=1:obj.cfg.simulation.numUE
                    queueLength=obj.packets.queueLength(u);
                    waiting=waiting+max(0,queueLength-1);
                    totalQueued=totalQueued+queueLength; maxQueued=max(maxQueued,queueLength);
                end
                obj.queueSamples(end+1,:)=[now,totalQueued,maxQueued];
                if ~isempty(obj.packets.packets)
                    pending=obj.packets.packets(strcmp({obj.packets.packets.status},'pending'));
                    work=numel(unique([pending.ueId]));
                end
                obj.raIntegral=obj.raIntegral+ra; obj.activeIntegral=obj.activeIntegral+work;
                obj.queueIntegral=obj.queueIntegral+waiting/obj.cfg.simulation.numUE;
                obj.observed.append(now,'bs_queue',struct('pendingRequests',sum([obj.contexts.entries.pending])));
                obj.channel.discardBefore(max(0,(now-128)*1920));
            end
            obj.nextTick=now+1;
            if now==obj.cfg.simulation.durationTicks, obj.status='completed'; obj.stopReason='horizon'; end
        end
        function stop(obj,reason)
            if nargin<2, reason='requested'; end
            obj.resultCache=[];
            obj.stopRequested=true; obj.stopReason=char(reason);
            if ~strcmp(obj.status,'failed'), obj.status='stopped'; end
        end
        function s=snapshot(obj)
            s=struct('tick',obj.currentTick,'status',obj.status,'devices',obj.devices.entries, ...
                'pendingEvents',obj.receiveQueue.count(),'packetCounters',obj.packets.counters);
        end
        function result=result(obj)
            if ~isempty(obj.resultCache), result=obj.resultCache; return; end
            packets=obj.packets.packets;
            % Do not mutate resumable state when exporting a partial result.
            for k=1:numel(packets)
                if strcmp(packets(k).status,'pending'), packets(k).status='unfinished'; packets(k).reason=obj.stopReason; end
            end
            attempts=obj.attempts;
            for k=1:numel(attempts)
                if strcmp(attempts(k).status,'started'), attempts(k).status='unfinished'; end
            end
            obs=obj.observed.all(); truth=obj.truth.all();
            result=nbiot.results.finalizeResult(obj.cfg,obj.scenario,packets,attempts,obs,truth, ...
                obj.calendar.usage(),obj.currentTick,obj.status,obj.stopReason,obj.errorInfo);
            result.harqLog=obj.harqJournal.all(); result.harqLogSchemaVersion=1;
            result.queueSamples=obj.queueSamples;
            result.kpiSummary=nbiot.metrics.summarizeKpi(obj.cfg,packets,attempts,obs,truth, ...
                result.resourceUsage,obj.currentTick,result.harqLog,obj.queueSamples);
            % An initialized but empty journal is known empty, not legacy data.
            result.kpiSummary.harq.available=true;
            result.kpiTimeSeries=nbiot.metrics.windowKpi(obj.cfg,packets,attempts,obs,obj.currentTick,obj.queueSamples);
            schema=nbiot.dataset.featureSchema();
            result.dataset=struct('observations',obj.rowsTable(obj.observationRows,schema.observationNames), ...
                'targets',obj.rowsTable(obj.targetRows,schema.targetNames), ...
                'schema',schema,'manifest',nbiot.dataset.buildManifest(obj.scenario.externalRealizationId));
            result.profiling=struct('elapsedSeconds',obj.elapsedSeconds,'matlabValidation','pending');
            obj.resultCache=result;
        end
    end
    methods (Access=private)
        function addArrivals(obj)
            a=obj.scenario.arrivals;
            while obj.arrivalCursor<=numel(a) && double(a(obj.arrivalCursor).createdTick)<=obj.currentTick
                arrival=a(obj.arrivalCursor); accepted=obj.packets.enqueue(arrival);
                obj.truth.append(obj.currentTick,'packet_created',struct('packetId',double(arrival.packetId),'ueId',double(arrival.ueId),'accepted',accepted));
                obj.arrivalCursor=obj.arrivalCursor+1;
            end
        end
        function activateHeads(obj)
            for u=1:obj.cfg.simulation.numUE
                d=obj.devices.get(u);
                if strcmp(d.state,'IDLE')
                    id=obj.packets.head(u);
                    if id>0, d.state='WAIT_RA'; d.packetId=double(id); d.nextAllowedTick=max(obj.currentTick,d.ulBusyUntilTick); obj.devices.set(u,d); end
                end
            end
        end
        function emitNprach(obj)
            at=find([obj.occasions.startTick]==obj.currentTick,1); if isempty(at), return; end
            occasion=obj.occasions(at); ids=[]; indices=[];
            for u=1:obj.cfg.simulation.numUE
                d=obj.devices.get(u);
                if ~any(strcmp(d.state,{'WAIT_RA','BACKOFF'})) || d.nextAllowedTick>obj.currentTick, continue; end
                stream=obj.sources.stream('access',0,u,occasion.occasionId);
                if rand(stream)>obj.cfg.policy.accessProbability, continue; end
                d.nInit=floor(rand(stream)*obj.cfg.ra.numSubcarriers);
                d.attemptNumber=d.attemptNumber+1; d.lifetimeAttempt=d.lifetimeAttempt+1;
                d.attemptId=numel(obj.attempts)+1; d.occasionId=occasion.occasionId;
                d.token=obj.newToken(u,d.lifetimeAttempt); d.raSucceeded=false;
                d.raRnti=1+floor(mod(floor(occasion.startTick/10),1024)/4);
                d.state='WAIT_RAR'; d.monitorStartTick=occasion.endTick+3;
                d.deadlineTick=obj.monitoringDeadline(d.monitorStartTick,obj.cfg.ra.rarPp);
                obj.packets.incrementAttempt(d.packetId); obj.devices.set(u,d);
                tx=nbiot.phy.nprach.buildTransmission(obj.cfg,occasion,d.nInit); tx.ueId=u; obj.channel.add(tx);
                obj.logTx(struct('startTick',occasion.startTick,'ticks',occasion.startTick:occasion.endTick-1, ...
                    'frequencyStartHz',0,'bandwidthHz',45000,'direction','UL','phase','RA','kind','NPRACH'),u);
                a=struct('attemptId',d.attemptId,'ueId',u,'packetId',d.packetId, ...
                    'occasionId',occasion.occasionId,'nInit',d.nInit,'startTick',obj.currentTick, ...
                    'endTick',NaN,'status','started','collision',false,'capture',false);
                obj.attempts(end+1)=a; ids(end+1)=d.attemptId; indices(end+1)=d.nInit; %#ok<AGROW>
                obj.truth.append(obj.currentTick,'msg1',struct('attemptId',d.attemptId,'ueId',u,'packetId',d.packetId,'nInit',d.nInit,'occasionId',occasion.occasionId));
            end
            for k=1:numel(ids), obj.attempts(ids(k)).collision=sum(indices==indices(k))>1; end
            % Every configured occasion is detected, including pure noise.
            obj.receiveQueue.push(occasion.endTick+obj.cfg.phy.processingTicks+1,'nprach',occasion);
        end
        function handleReceive(obj,event)
            switch event.kind
                case 'nprach'
                    occasion=event.payload; a=max(0,occasion.startTick*1920-128); z=occasion.endTick*1920+128;
                    rx=obj.channel.receive('UL',0,a,z);
                    [detected,metrics]=nbiot.phy.nprach.detect(obj.cfg,rx,occasion);
                    obj.observed.append(obj.currentTick,'nprach_detection',struct('count',numel(detected),'maxMetric',max(metrics),'meanMetric',mean(metrics),'energyW',mean(abs(rx.waveform).^2)));
                    deadline=obj.monitoringDeadline(occasion.endTick+3,obj.cfg.ra.rarPp);
                    for k=1:numel(detected)
                        obj.contexts.create(detected(k).nInit,occasion.occasionId,deadline,detected(k).delaySeconds);
                    end
                case 'monitor'
                    obj.receiveControl(event.payload);
                case 'dl_payload'
                    obj.receiveDlPayload(event.payload);
                case 'bs_ul'
                    obj.receiveAtBs(event.payload);
                otherwise
                    error('nbiot:engine:Event','Unknown completion %s.',event.kind);
            end
        end
        function schedulePending(obj)
            entries=obj.contexts.entries; if isempty(entries), return; end
            pending=find([entries.pending]);
            if isempty(pending), return; end
            [~,order]=sortrows([[entries(pending).deadlineTick].',[entries(pending).lastProgressTick].',pending.'],[1 2 3]);
            for id=pending(order)
                c=obj.contexts.get(id); s=[];
                if obj.currentTick>c.deadlineTick
                    if strcmp(c.state,'DATA_PENDING'), obj.harqTerminal(c,'failed'); end
                    c.pending=false; c.state='EXPIRED'; obj.contexts.set(id,c); continue;
                end
                switch c.state
                    case 'RAR_PENDING'
                        occasion=obj.occasions(c.occasionId);
                        raRnti=1+floor(mod(floor(occasion.startTick/10),1024)/4);
                        s=obj.scheduler.downlink('RAR','RA',max(obj.currentTick,occasion.endTick+3),c.deadlineTick,raRnti);
                        if isempty(s), continue; end
                        s.msg3Grant.rnti=c.rnti;
                        f=s.rarGrant; f.rapid=c.nInit; f.rnti=c.rnti;
                        f.timingAdvance=max(0,min(1282,round(c.delaySeconds/(16/(15000*2048)))));
                        bits=nbiot.ra.encodeMessage('RAR',f); obj.emitDownlink(s,bits);
                        obj.queueBsUl(id,s.msg3Grant,'Msg3'); c.state='MSG3_RX';
                        c.deadlineTick=obj.monitoringDeadline(s.msg3Grant.endTick,obj.cfg.ra.contentionPp);
                    case 'MSG4_PENDING'
                        s=obj.scheduler.downlink('Msg4','RA',obj.currentTick,c.deadlineTick,c.rnti);
                        if isempty(s), continue; end
                        obj.emitDownlink(s,nbiot.ra.encodeMessage('Msg4',struct('token',c.token)));
                        obj.queueBsUl(id,s.ackGrant,'Msg4Ack'); c.state='MSG4_ACK'; c.receiptAttempts=c.receiptAttempts+1;
                    case 'DATA_PENDING'
                        rv=obj.cfg.phy.rvSequence(c.harqTry);
                        s=obj.scheduler.uplink('Data','DT',obj.currentTick,c.deadlineTick,c.rnti,c.ndi,rv);
                        if isempty(s), continue; end
                        obj.emitControl(s.controlGrant,s.dci); obj.queueBsUl(id,s.payloadGrant,'Data'); c.state='DATA_RX';
                    case 'RECEIPT_PENDING'
                        s=obj.scheduler.downlink('receipt','DT',obj.currentTick,c.deadlineTick,c.rnti);
                        if isempty(s), continue; end
                        f=struct('sequence',c.sequence,'fragmentIndex',c.nextFragment-1,'status',1);
                        obj.emitDownlink(s,nbiot.ra.encodeMessage('receipt',f));
                        obj.queueBsUl(id,s.ackGrant,'ReceiptAck'); c.state='RECEIPT_ACK'; c.receiptAttempts=c.receiptAttempts+1;
                end
                if ~isempty(s)
                    c.schedule=s; c.pending=false; c.lastProgressTick=obj.currentTick; obj.contexts.set(id,c);
                end
            end
        end
        function emitControl(obj,g,dci)
            tx=nbiot.phy.npdcch.buildTransmission(obj.cfg,g,dci); obj.channel.add(tx);
            obj.logTx(g,0);
            obj.observed.append(obj.currentTick,'grant',struct('phase',g.phase,'rnti',g.rnti,'format',dci.format,'startTick',g.startTick,'endTick',g.endTick));
        end
        function emitDownlink(obj,s,bits)
            obj.emitControl(s.controlGrant,s.dci);
            [tx,~]=nbiot.phy.npdsch.buildTransmission(obj.cfg,s.payloadGrant,bits,[]); obj.channel.add(tx);
            obj.logTx(s.payloadGrant,0);
            if strcmpi(s.payloadGrant.kind,'RAR'), obj.observed.append(obj.currentTick,'rar_sent',struct('rnti',s.controlGrant.rnti)); end
        end
        function queueBsUl(obj,id,g,kind)
            obj.receiveQueue.push(g.endTick+obj.cfg.phy.processingTicks+1,'bs_ul',struct('contextId',id,'grant',g,'kind',kind));
            if strcmp(kind,'Data')
                c=obj.contexts.get(id); f=obj.harqIdentity(c);
                f.startTick=g.startTick; f.endTick=g.endTick;
                f.readyTick=g.endTick+obj.cfg.phy.processingTicks+1;
                obj.harqJournal.append(obj.currentTick,'scheduled',f);
            end
        end
        function queueMonitoring(obj)
            if mod(obj.currentTick,32)~=0, return; end
            ticks=obj.calendar.monitoringTicks(obj.currentTick); if numel(ticks)<2, return; end
            ticks=ticks(1:2); ready=max(ticks)+1+obj.cfg.phy.processingTicks+1;
            for u=1:obj.cfg.simulation.numUE
                d=obj.devices.get(u);
                if ~any(strcmp(d.state,{'WAIT_RAR','WAIT_MSG4','DATA','WAIT_RECEIPT'})) || ticks(1)<d.monitorStartTick, continue; end
                if ticks(1)<d.ulBusyUntilTick && max(ticks)+1>d.ulBusyStartTick, continue; end
                if strcmp(d.state,'WAIT_RAR'), rnti=d.raRnti; formats={'N1'}; else, rnti=d.rnti; formats={'N0','N1'}; end
                % Candidate is derived solely from the public monitoring calendar.
                g=struct('ticks',ticks,'startTick',ticks(1),'endTick',max(ticks)+1,'rnti',rnti, ...
                    'profile',struct('repetitions',2,'aggregationLevel',2));
                obj.receiveQueue.push(ready,'monitor',struct('ueId',u,'attemptId',d.attemptId,'grant',g,'formats',{formats}));
            end
        end
        function receiveControl(obj,p)
            d=obj.devices.get(p.ueId);
            if d.attemptId~=p.attemptId || ~any(strcmp(d.state,{'WAIT_RAR','WAIT_MSG4','DATA','WAIT_RECEIPT'})), return; end
            rx=obj.receiverWindow('DL',p.ueId,p.grant);
            for f=1:numel(p.formats)
                g=p.grant; g.format=p.formats{f}; g.profile.format=g.format;
                decoded=nbiot.phy.npdcch.receive(obj.cfg,rx,g);
                if decoded.crcError~=0, continue; end
                try
                    if strcmp(decoded.dci.format,'N0')
                        if ~any(strcmp(d.state,{'DATA','WAIT_RECEIPT'})), continue; end
                        ul=obj.scheduler.reconstructUplink(decoded.dci,g.ticks,d.rnti);
                        obj.ueTransmitData(p.ueId,ul); return;
                    else
                        dl=obj.scheduler.reconstructDownlink(decoded.dci,g.ticks,g.rnti);
                        if isempty(dl), continue; end
                        obj.receiveQueue.push(dl.endTick+obj.cfg.phy.processingTicks+1,'dl_payload', ...
                            struct('ueId',p.ueId,'attemptId',d.attemptId,'grant',dl,'dci',decoded.dci)); return;
                    end
                catch exception
                    if startsWith(exception.identifier,'nbiot:UnsupportedGrant') || startsWith(exception.identifier,'nbiot:protocol:'), continue; end
                    rethrow(exception);
                end
            end
        end
        function receiveDlPayload(obj,p)
            d=obj.devices.get(p.ueId);
            if d.attemptId~=p.attemptId || ~any(strcmp(d.state,{'WAIT_RAR','WAIT_MSG4','DATA','WAIT_RECEIPT'})), return; end
            rx=obj.receiverWindow('DL',p.ueId,p.grant);
            [decoded,~]=nbiot.phy.npdsch.receive(obj.cfg,rx,p.grant,[]);
            obj.recordDecode('NPDSCH',decoded,p.grant,p.ueId);
            if decoded.crcError~=0, return; end
            try
                if strcmp(d.state,'WAIT_RAR')
                    rar=nbiot.ra.decodeMessage('RAR',decoded.decodedBits);
                    if rar.rapid~=d.nInit || obj.currentTick>d.deadlineTick, return; end
                    ul=obj.scheduler.reconstructMsg3(rar,p.grant.ticks); ul.rnti=rar.rnti;
                    if ul.startTick<obj.currentTick, return; end
                    d.rnti=rar.rnti; d.timingAdvanceSeconds=rar.timingAdvance*16/(15000*2048);
                    d.state='WAIT_MSG4'; d.deadlineTick=obj.monitoringDeadline(ul.endTick,obj.cfg.ra.contentionPp);
                    d.monitorStartTick=ul.endTick; d.ulBusyStartTick=ul.startTick; d.ulBusyUntilTick=ul.endTick;
                    packet=obj.packets.get(d.packetId); bits=nbiot.ra.encodeMessage('Msg3',struct('token',d.token,'sequence',double(packet.sequence)));
                    [tx,d.encoderState]=nbiot.phy.npusch.buildTransmission(obj.cfg,ul,bits,[]);
                    tx.ueId=p.ueId; tx.timingAdvanceSeconds=d.timingAdvanceSeconds; obj.channel.add(tx); obj.devices.set(p.ueId,d);
                    obj.logTx(ul,p.ueId);
                elseif numel(decoded.decodedBits)>=16 && nbiot.util.fromBits(decoded.decodedBits(1:8))==60
                    msg=nbiot.ra.decodeMessage('Msg4',decoded.decodedBits);
                    if msg.token~=d.token, return; end
                    if strcmp(d.state,'WAIT_MSG4') && obj.currentTick>d.deadlineTick, return; end
                    firstSuccess=~d.raSucceeded;
                    if firstSuccess
                        d.raSucceeded=true; obj.attempts(d.attemptId).status='success'; obj.attempts(d.attemptId).endTick=obj.currentTick;
                        obj.attempts(d.attemptId).capture=obj.attempts(d.attemptId).collision;
                        obj.truth.append(obj.currentTick,'ra_success',struct('attemptId',d.attemptId,'ueId',p.ueId,'packetId',d.packetId));
                    end
                    if firstSuccess
                        d.state='DATA'; d.fragmentIndex=0; d.ndi=-1; d.monitorStartTick=obj.currentTick;
                        d.progressDeadlineTick=obj.currentTick+obj.cfg.phy.progressTimeoutTicks;
                    end
                    obj.devices.set(p.ueId,d); obj.ueAck(p.ueId,p.dci,p.grant,'RA');
                else
                    receipt=nbiot.ra.decodeMessage('receipt',decoded.decodedBits); packet=obj.packets.get(d.packetId);
                    if receipt.sequence~=double(packet.sequence) || receipt.status~=1 || receipt.fragmentIndex~=numel(packet.blocks)-1, return; end
                    obj.ueAck(p.ueId,p.dci,p.grant,'DT');
                    obj.packets.localFinish(d.packetId,obj.currentTick,true); obj.devices.reset(p.ueId);
                end
            catch exception
                if startsWith(exception.identifier,'nbiot:protocol:') || startsWith(exception.identifier,'nbiot:UnsupportedGrant'), return; end
                rethrow(exception);
            end
        end
        function ueTransmitData(obj,u,g)
            d=obj.devices.get(u); packet=obj.packets.get(d.packetId);
            if d.ndi<0, d.fragmentIndex=0;
            elseif g.ndi~=d.ndi, d.fragmentIndex=d.fragmentIndex+1; d.encoderState=[]; end
            if d.fragmentIndex>=numel(packet.blocks) || g.startTick<obj.currentTick, return; end
            d.ndi=g.ndi; d.state='DATA';
            d.progressDeadlineTick=obj.currentTick+obj.cfg.phy.progressTimeoutTicks;
            d.ulBusyStartTick=g.startTick; d.ulBusyUntilTick=g.endTick;
            [tx,d.encoderState]=nbiot.phy.npusch.buildTransmission(obj.cfg,g,packet.blocks{d.fragmentIndex+1},d.encoderState);
            tx.ueId=u; tx.timingAdvanceSeconds=d.timingAdvanceSeconds; obj.channel.add(tx); obj.devices.set(u,d);
            obj.logTx(g,u);
            % Analyzer provenance only; never influences the waveform or state.
            id=obj.contexts.findRnti(g.rnti);
            if id>0
                c=obj.contexts.get(id);
                if strcmp(c.state,'DATA_RX') && isfield(c.schedule,'payloadGrant') && ...
                        c.schedule.payloadGrant.startTick==g.startTick && c.schedule.payloadGrant.endTick==g.endTick
                    f=obj.harqIdentity(c); f.startTick=g.startTick; f.endTick=g.endTick;
                    f.transmitterSequence=double(packet.sequence); f.transmitterBlockIndex=d.fragmentIndex;
                    obj.harqJournal.append(g.startTick,'emitted',f);
                    return;
                end
            end
            obj.harqJournal.append(g.startTick,'unmatchedEmission', ...
                struct('rnti',g.rnti,'startTick',g.startTick,'endTick',g.endTick));
        end
        function ueAck(obj,u,dci,payload,phase)
            d=obj.devices.get(u); g=obj.scheduler.reconstructAck(dci,payload,d.rnti);
            g.phase=phase;
            if g.startTick<obj.currentTick, error('nbiot:engine:Timing','Decoded DL cannot meet its ACK start.'); end
            [tx,~]=nbiot.phy.npusch.buildTransmission(obj.cfg,g,int8(1),[]);
            tx.ueId=u; tx.timingAdvanceSeconds=d.timingAdvanceSeconds; obj.channel.add(tx);
            d.ulBusyStartTick=g.startTick; d.ulBusyUntilTick=g.endTick; obj.devices.set(u,d);
            obj.logTx(g,u);
        end
        function receiveAtBs(obj,p)
            c=obj.contexts.get(p.contextId); g=p.grant;
            if any(strcmp(c.state,{'FAILED','EXPIRED','DONE'})), return; end
            % Receive events belong to one public BS state and grant. A queued
            % event from an earlier schedule must not advance a newer context.
            switch p.kind
                case 'Msg3', expectedState='MSG3_RX'; grantField='msg3Grant';
                case 'Data', expectedState='DATA_RX'; grantField='payloadGrant';
                case 'Msg4Ack', expectedState='MSG4_ACK'; grantField='ackGrant';
                case 'ReceiptAck', expectedState='RECEIPT_ACK'; grantField='ackGrant';
                otherwise, return;
            end
            if ~strcmp(c.state,expectedState) || ~isstruct(c.schedule) || ...
                    ~isfield(c.schedule,grantField) || ...
                    ~isequaln(c.schedule.(grantField),g)
                return;
            end
            rx=obj.receiverWindow('UL',0,g);
            [decoded,soft]=nbiot.phy.npusch.receive(obj.cfg,rx,g,c.softBuffer);
            obj.recordDecode(p.kind,decoded,g,0);
            switch p.kind
                case 'Msg3'
                    if decoded.crcError~=0, c.state='FAILED';
                    else
                        try, msg=nbiot.ra.decodeMessage('Msg3',decoded.decodedBits);
                        catch exception
                            if startsWith(exception.identifier,'nbiot:protocol:'), c.state='FAILED'; obj.contexts.set(p.contextId,c); return; end
                            rethrow(exception);
                        end
                        c.token=msg.token; c.sequence=msg.sequence; c.state='MSG4_PENDING'; c.pending=true;
                        c.softBuffer=[]; c.receiptAttempts=0;
                    end
                case 'Data'
                    harqFields=obj.harqIdentity(c); accepted=false;
                    c.softBuffer=soft;
                    if decoded.crcError==0
                        b=decoded.decodedBits;
                        try
                            f=obj.fragmentHeader(b);
                            valid=f.sequence==c.sequence && f.index==c.nextFragment-1 && f.count==ceil(obj.cfg.traffic.packetBytes*8/208);
                        catch, valid=false; end
                        if valid
                            accepted=true;
                            % Ground-truth mapping below is an analyzer side effect only;
                            % BS scheduling uses the decoded header/token, not PacketStore.
                            obj.analyzeDelivery(c,b,f.index);
                            if c.nextFragment==f.count
                                c.dataComplete=true; c.state='RECEIPT_PENDING'; c.receiptAttempts=0;
                            else
                                c.nextFragment=c.nextFragment+1; c.ndi=1-c.ndi; c.state='DATA_PENDING';
                            end
                            c.harqTry=1; c.softBuffer=[]; c.pending=true;
                            c.deadlineTick=obj.currentTick+obj.cfg.phy.progressTimeoutTicks;
                        else, c=obj.failedTb(c); end
                    else, c=obj.failedTb(c); end
                    harqFields.crcError=decoded.crcError; harqFields.accepted=accepted;
                    obj.harqJournal.append(obj.currentTick,'decoded',harqFields);
                    if accepted
                        harqFields.outcome='accepted'; obj.harqJournal.append(obj.currentTick,'terminal',harqFields);
                    elseif strcmp(c.state,'FAILED')
                        harqFields.outcome='failed'; obj.harqJournal.append(obj.currentTick,'terminal',harqFields);
                    end
                case {'Msg4Ack','ReceiptAck'}
                    ack=~decoded.hasCrc && ~isempty(decoded.decodedBits) && decoded.decodedBits(1)==1 && ...
                        isfield(decoded.measurements,'uciDetected') && decoded.measurements.uciDetected;
                    if ack
                        if strcmp(p.kind,'Msg4Ack')
                            c.state='DATA_PENDING'; c.pending=true; c.softBuffer=[]; c.harqTry=1;
                            c.deadlineTick=obj.currentTick+obj.cfg.phy.progressTimeoutTicks;
                        else, c.state='DONE'; c.pending=false; end
                    elseif c.receiptAttempts>=obj.cfg.phy.maxReceiptTransmissions, c.state='FAILED'; c.pending=false;
                    elseif strcmp(p.kind,'Msg4Ack')
                        % Retry contention resolution within its existing window.
                        % The 512 ms receipt interval applies to data receipts.
                        c.state='MSG4_PENDING'; c.pending=true;
                    else
                        c.state=strrep(c.state,'_ACK','_RETRY'); c.pending=false;
                        c.lastProgressTick=obj.currentTick+obj.cfg.phy.receiptTimeoutTicks;
                    end
            end
            obj.contexts.set(p.contextId,c);
        end
        function c=failedTb(obj,c)
            if c.harqTry>=obj.cfg.phy.maxHarqTransmissions, c.state='FAILED'; c.pending=false;
            else, c.harqTry=c.harqTry+1; c.state='DATA_PENDING'; c.pending=true; end
        end
        function f=harqIdentity(~,c)
            f=struct('contextId',c.id,'packetSequence',c.sequence, ...
                'blockIndex',c.nextFragment-1,'attempt',c.harqTry);
        end
        function harqTerminal(obj,c,outcome)
            f=obj.harqIdentity(c); f.outcome=outcome;
            obj.harqJournal.append(obj.currentTick,'terminal',f);
        end
        function analyzeDelivery(obj,c,b,index)
            for u=1:obj.cfg.simulation.numUE
                d=obj.devices.get(u);
                if d.token==c.token && d.rnti==c.rnti && d.packetId>0
                    if obj.packets.markReceived(d.packetId,index,b,obj.currentTick)
                        obj.truth.append(obj.currentTick,'packet_delivered',struct('packetId',d.packetId,'ueId',u));
                    end
                    return;
                end
            end
        end
        function advanceTimers(obj)
            for u=1:obj.cfg.simulation.numUE
                d=obj.devices.get(u);
                if any(strcmp(d.state,{'WAIT_RAR','WAIT_MSG4'})) && obj.currentTick>=d.deadlineTick
                    obj.attempts(d.attemptId).status='failure'; obj.attempts(d.attemptId).endTick=obj.currentTick;
                    if d.attemptNumber>=obj.cfg.ra.maxAttempts
                        obj.packets.markTerminal(d.packetId,'dropped','ra_limit',obj.currentTick); obj.devices.reset(u);
                    else
                        s=obj.sources.stream('backoff',0,u,d.lifetimeAttempt);
                        d.nextAllowedTick=obj.currentTick+ceil(rand(s)*obj.cfg.ra.backoffTicks); d.state='BACKOFF'; obj.devices.set(u,d);
                    end
                elseif any(strcmp(d.state,{'DATA','WAIT_RECEIPT'})) && obj.currentTick>=d.progressDeadlineTick
                    obj.packets.markTerminal(d.packetId,'dropped','progress_timeout',obj.currentTick); obj.devices.reset(u);
                end
            end
            for id=1:numel(obj.contexts.entries)
                c=obj.contexts.get(id);
                if any(strcmp(c.state,{'MSG4_RETRY','RECEIPT_RETRY'})) && obj.currentTick>=c.lastProgressTick
                    c.state=strrep(c.state,'_RETRY','_PENDING'); c.pending=true;
                    if c.dataComplete, c.deadlineTick=obj.currentTick+obj.cfg.phy.progressTimeoutTicks; end
                    obj.contexts.set(id,c);
                end
            end
        end
        function rx=receiverWindow(obj,direction,u,g)
            rx=obj.channel.receive(direction,u,max(0,g.startTick*1920-128),g.endTick*1920+128);
        end
        function recordDecode(obj,kind,decoded,g,receiverId)
            fields=struct('channel',kind,'phase',g.phase, ...
                'rnti',g.rnti,'hasCrc',decoded.hasCrc,'crcError',decoded.crcError, ...
                'receiverId',receiverId,'startTick',g.startTick,'endTick',g.endTick);
            if receiverId==0, obj.observed.append(obj.currentTick,'phy_decode',fields);
            else, obj.truth.append(obj.currentTick,'phy_decode',fields); end
        end
        function logTx(obj,g,u)
            obj.truth.append(g.startTick,'transmission',struct('direction',g.direction,'phase',g.phase, ...
                'channel',g.kind,'ueId',u,'ticks',g.ticks,'frequencyStartHz',g.frequencyStartHz,'bandwidthHz',g.bandwidthHz));
        end
        function deadline=monitoringDeadline(obj,start,pp)
            remaining=pp*obj.cfg.phy.npdcch.rmax; deadline=Inf;
            for base=floor(start/32)*32:32:obj.cfg.simulation.durationTicks-1
                ticks=obj.calendar.monitoringTicks(base); ticks=ticks(ticks>=start);
                if numel(ticks)>=remaining
                    deadline=ticks(remaining)+1+obj.cfg.phy.processingTicks+1; return;
                end
                remaining=remaining-numel(ticks);
            end
        end
        function token=newToken(obj,u,attempt)
            s=obj.sources.stream('token',0,u,attempt);
            while true
                token=uint64(floor(rand(s)*2^48)); key=sprintf('%u',token);
                if token>0 && ~isKey(obj.tokens,key), obj.tokens(key)=true; return; end
            end
        end
        function closeWindow(obj,first,last)
            [obs,target]=nbiot.dataset.closeWindow(obj.observed.all(),obj.truth.all(),first,last, ...
                obj.raIntegral,obj.activeIntegral,obj.queueIntegral,obj.scenario.externalRealizationId,obj.cfg.dataset.windowTicks);
            obj.observationRows{end+1}=obs; obj.targetRows{end+1}=target;
            obj.raIntegral=0; obj.activeIntegral=0; obj.queueIntegral=0;
        end
        function validateScenario(obj,s)
            if ~isfield(s,'ue') || numel(s.ue)~=obj.cfg.simulation.numUE || ...
                    ~isequal(double([s.ue.ueId]),1:obj.cfg.simulation.numUE)
                error('nbiot:scenario:Incompatible','Scenario UE IDs must be 1:numUE.');
            end
            if ~isfield(s,'externalRealizationId') || s.externalRealizationId~=obj.cfg.simulation.realizationId
                error('nbiot:scenario:Randomness','Scenario/config realization IDs disagree.');
            end
            if ~isempty(s.arrivals)
                ticks=double([s.arrivals.createdTick]);
                if any(diff(ticks)<0) || any(ticks<0 | ticks>=obj.cfg.simulation.durationTicks)
                    error('nbiot:scenario:Arrivals','Arrivals must be ordered within the half-open horizon.');
                end
            end
        end
    end
    methods (Static,Access=private)
        function f=fragmentHeader(b)
            if numel(b)~=256 || any(b~=0 & b~=1), error('nbiot:protocol:Fragment','Invalid TB.'); end
            f=struct('sequence',double(nbiot.util.fromBits(b(1:16))), ...
                'index',double(nbiot.util.fromBits(b(17:24))), ...
                'count',double(nbiot.util.fromBits(b(25:32))), ...
                'validBits',double(nbiot.util.fromBits(b(33:40))));
            if any(b(41:48)) || f.count<1 || f.index>=f.count || f.validBits<1 || f.validBits>208 || any(b(49+f.validBits:end))
                error('nbiot:protocol:Fragment','Invalid fragment header/padding.');
            end
        end
        function tableValue=rowsTable(rows,names)
            if isempty(rows), tableValue=array2table(zeros(0,numel(names)),'VariableNames',names);
            else, tableValue=cell2table(vertcat(rows{:}),'VariableNames',names); end
        end
    end
end
