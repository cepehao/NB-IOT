2 Examples and Demos

NB-IoT Uplink Waveform Generation and Analysis

This example shows how to generate and receive a narrowband internet of things (NB-IoT) uplink
waveform in the presence of an LTE wideband waveform. The example also analyzes the quality of the
received NB-IoT physical uplink shared channel (NPUSCH) through error vector magnitude (EVM)
measurements.

Introduction

To support maximum flexibility of the NB-IoT deployment, 3GPP defines these three NB-IoT modes of
operation (TS 36.104 Section 3.1):

• Standalone — NB-IoT carrier deployed in its own spectrum

• Guardband — NB-IoT carrier deployed in the unused resource block(s) within an LTE carrier's

guardband

• In-band — NB-IoT carrier deployed in resource block(s) of an LTE carrier

This figure shows a sketch of in-band and guardband modes for a 5 MHz LTE carrier.

For the in-band mode of NB-IoT, the NB-IoT component should not overlap with any physical resource
block (PRB) allocated for transmitting the physical uplink control channel (PUCCH).

For the guardband mode of NB-IoT, the allowed PRBs depend on the guardband size of the LTE
carrier as defined in TS 36.101 Section 5.6. Guardband mode of NB-IoT is not supported on a 1.4
MHz and 3 MHz LTE carrier because the guardband sizes are too small. This table shows the allowed
PRB indices for guardband deployment of uplink NB-IoT:

guardbandPRBTable = nbiotAllowedGuardbandPRB()

guardbandPRBTable=6×3 table
       LTE Bandwidth       Guardband PRBs (Lower Edge)    Guardband PRBs (Upper Edge)
    ___________________    ___________________________    ___________________________

2-104

 NB-IoT Uplink Waveform Generation and Analysis

    "1.4 MHz (  6 RBs)"        {1×0 double      }           {1×0 double           }
    "  3 MHz ( 15 RBs)"        {1×0 double      }           {1×0 double           }
    "  5 MHz ( 25 RBs)"        {[            -1]}           {[                 25]}
    " 10 MHz ( 50 RBs)"        {[         -2 -1]}           {[              50 51]}
    " 15 MHz ( 75 RBs)"        {[   -4 -3 -2 -1]}           {[        75 76 77 78]}
    " 20 MHz (100 RBs)"        {[-5 -4 -3 -2 -1]}           {[100 101 102 103 104]}

The example shows how to:

• Generate an NB-IoT uplink waveform based on a reference test channel.

• Receive the NB-IoT waveform in the presence of an LTE wideband waveform.

• Measure NPUSCH EVM.

Generating the waveform and the processing it at the receiver to compute the NPUSCH EVM involves
these steps:

Simulation Configuration

This example generates the NB-IoT uplink waveform based on a reference test channel, as defined in
TS 36.104 Annex A. You can select a reference test channel with the desired subcarrier spacing and
number of consecutive subcarriers in a resource unit (RU) for the NPUSCH configuration.

2-105

2 Examples and Demos

% TS 36.104, Base Station (BS) radio transmission and reception
% Annex A.14 - Fixed Reference Channels for NB-IoT reference sensitivity (pi/2 BPSK, R=1/3)
% Annex A.15 - Fixed Reference Channels for NB-IoT dynamic range (pi/4 QPSK, R=2/3)
% Annex A.16 - Fixed Reference Channels for NB-IoT PUSCH format 1

rcname =

;

Select the number of uplink resource blocks (RBs), NULRB, and the index of the PRB for NB-IoT
allocation, nbiotPRBIndex. To use the in-band operation mode for NB-IoT, specify nbiotPRBIndex
as an integer between 0 and NULRB-1. To use the guardband operation mode for NB-IoT, specify
nbiotPRBIndex with a valid value from guardbandPRBTable. Any other value of nbiotPRBIndex
indicates that the NB-IoT will be out of band.

NULRB         =

nbiotPRBIndex =

;

;

Set the waveform duration in the number of transport blocks. The specified waveform duration
applies to the LTE wideband waveform as well.

totNumTrBlks = 1;

NB-IoT Uplink Configuration and Waveform Generation

Use the local function configureNBIoTUplinkWaveform to configure the user equipment (UE)
specific configuration, the NPUSCH channel specific configuration, and other required parameters.

ngen = configureNBIoTUplinkWaveform(NULRB,nbiotPRBIndex,RCName=rcname,TotNumTrBlks=totNumTrBlks);

Simulating guardband NB-IoT carrier

Use the local function generateNBIoTUplinkWaveform to generate the NB-IoT waveform. For
details about this process, see the “NB-IoT Uplink Waveform Generation” on page 2-304 example.

[nbiotWaveform,nbiotInfo] = generateNBIoTUplinkWaveform(ngen);

Generating 32 slots corresponding to 1 transport block(s) transmitted on NPUSCH

LTE Uplink Configuration and Waveform Generation

Configure and generate the LTE wideband waveform. Use the local function
configureWidebandLTEWaveform to configure an LTE wideband waveform with the number of
uplink RBs equal to NULRB.

ltecfg = configureWidebandLTEWaveform(NULRB,ngen.TotSubframes,nbiotPRBIndex);

% Generate wideband LTE waveform
trdata = [1 0 0 1];
[lteWaveform,~,lteInfo] = lteRMCULTool(ltecfg,trdata);

Waveform Combination

The example combines the NB-IoT and the LTE waveforms in the time domain assuming perfect
synchronization between the two waveforms at the base station (BS). The
hNBUplinkCombinedWaveform function applies frequency shifting to the NB-IoT waveform to put it
in the specified PRB and upsamples the NB-IoT waveform before the combination. This function also

2-106

 NB-IoT Uplink Waveform Generation and Analysis

plots the power spectra of the upsampled and frequency shifted NB-IoT waveform and the LTE
wideband waveform.

% Create the parameter structure needed to combine the waveform
OSR = lteInfo.SamplingRate/nbiotInfo.SamplingRate;
combParams = struct();
combParams.NULRB = NULRB;
combParams.NBIoTPRBIndex = nbiotPRBIndex;
combParams.OSR = OSR;
combParams.SamplingRate = lteInfo.SamplingRate;

% Combine the waveform
[combWaveform,offset] = hNBUplinkCombinedWaveform(combParams,lteWaveform,nbiotWaveform);

NB-IoT Receive Filtering

In this section, you:

• Apply frequency correction. Shift the received waveform in frequency to bring the NB-IoT

spectrum to baseband (0 Hz).

• Filter out the LTE component and downsample. Downsample the waveform to the NB-IoT

sampling rate and filter out the frequencies outside the NB-IoT band.

Plot the spectrogram of the received waveform. The plot shows the frequency occupied by the NB-IoT
component in the received waveform.

2-107

2 Examples and Demos

rxWaveform = combWaveform;
minThreshold = -130 + 20 * double(strcmp(ngen.NBULSubcarrierSpacing,'3.75kHz')); % Threshold for spectrogram
figure;
spectrogram(rxWaveform(:,1),ones(lteInfo.Nfft,1),0,lteInfo.Nfft,'centered',lteInfo.SamplingRate,'MinThreshold',minThreshold);

Downshifting of NB-IoT Waveform

Downshift the received waveform to bring the NB-IoT component to baseband. The plot shows the
power spectrum of the received waveform after the frequency downshifting where the center of the
PRB with the NB-IoT component is shifted to 0 Hz.

rxWaveformB = lteFrequencyCorrect(ltecfg,rxWaveform,offset); % Received waveform with NB-IoT in baseband
combinedSpecPlotB = spectrumAnalyzer('SampleRate',lteInfo.SamplingRate,'Title','Received Waveform Power Spectrum with NB-IoT in Baseband');
combinedSpecPlotB(rxWaveformB);

2-108

 NB-IoT Uplink Waveform Generation and Analysis

Filtering and Downsampling of NB-IoT Waveform

Use the resample function to downsample the baseband received waveform to the nominal NB-IoT
sampling rate of 1.92 MHz. The default FIR antialiasing lowpass filter implemented in the resample
function filters out the unwanted LTE component without using an additional lowpass filter.

rxwave = resample(rxWaveformB,1,OSR);

Plot the spectrogram of the recovered NB-IoT waveform against the original NB-IoT waveform.

filteredSpecPlot = spectrumAnalyzer('SampleRate',lteInfo.SamplingRate,'Title','Original and Recovered NB-IoT Waveform Power Spectrum', ...
    'ChannelNames',{'Original NB-IoT waveform','Recovered NB-IoT waveform'},'ShowLegend',true);
filteredSpecPlot([nbiotWaveform,rxwave]);

2-109

2 Examples and Demos

Plot the spectrogram of the recovered NB-IoT waveform. The plot shows the baseband narrowband
waveform after extracting it from the received waveform.

figure;
spectrogram(rxwave(:,1),ones(nbiotInfo.Nfft,1),0,nbiotInfo.Nfft,'centered',nbiotInfo.SamplingRate,'MinThreshold',minThreshold);

2-110

 NB-IoT Uplink Waveform Generation and Analysis

EVM Measurements

Channel Estimator Configuration for EVM Measurements

Parameterize the channel estimator at the receiver end using the structure cec.

cec = struct();
cec.PilotAverage = 'UserDefined';   % Type of pilot symbol averaging
cec.FreqWindow = 23;                % Frequency window size in REs
cec.TimeWindow = 1;                 % Time window size in REs
cec.InterpType = 'Cubic';           % 2D interpolation type
cec.CELength = 1;                   % Channel estimation length in ms

Process EVM

The hNPUSCHEVM function provides per slot and overall EVM measurements.

[evmmeas,plots] = hNPUSCHEVM(ngen,cec,rxwave,nbiotInfo);

Slot  0: average EVM 0.054%, peak EVM 0.078%
Slot  1: average EVM 0.094%, peak EVM 0.152%
Slot  2: average EVM 0.076%, peak EVM 0.119%
Slot  3: average EVM 0.033%, peak EVM 0.054%
Slot  4: average EVM 0.069%, peak EVM 0.088%
Slot  5: average EVM 0.057%, peak EVM 0.076%
Slot  6: average EVM 0.075%, peak EVM 0.121%
Slot  7: average EVM 0.053%, peak EVM 0.078%
Slot  8: average EVM 0.047%, peak EVM 0.066%
Slot  9: average EVM 0.116%, peak EVM 0.174%
Slot 10: average EVM 0.050%, peak EVM 0.068%
Slot 11: average EVM 0.057%, peak EVM 0.098%
Slot 12: average EVM 0.097%, peak EVM 0.138%
Slot 13: average EVM 0.065%, peak EVM 0.077%
Slot 14: average EVM 0.034%, peak EVM 0.048%

2-111

2 Examples and Demos

Slot 15: average EVM 0.123%, peak EVM 0.182%
Slot 16: average EVM 0.055%, peak EVM 0.097%
Slot 17: average EVM 0.089%, peak EVM 0.117%
Slot 18: average EVM 0.092%, peak EVM 0.123%
Slot 19: average EVM 0.072%, peak EVM 0.125%
Slot 20: average EVM 0.082%, peak EVM 0.127%
Slot 21: average EVM 0.063%, peak EVM 0.107%
Slot 22: average EVM 0.046%, peak EVM 0.075%
Slot 23: average EVM 0.040%, peak EVM 0.054%
Slot 24: average EVM 0.067%, peak EVM 0.105%
Slot 25: average EVM 0.074%, peak EVM 0.092%
Slot 26: average EVM 0.045%, peak EVM 0.088%
Slot 27: average EVM 0.058%, peak EVM 0.089%
Slot 28: average EVM 0.052%, peak EVM 0.092%
Slot 29: average EVM 0.036%, peak EVM 0.052%
Slot 30: average EVM 0.076%, peak EVM 0.108%
Slot 31: average EVM 0.118%, peak EVM 0.178%
All 32 slots: average EVM 0.072%, peak EVM 0.182%

2-112

 NB-IoT Uplink Waveform Generation and Analysis

2-113

2 Examples and Demos

References

1

2

3

3GPP TS 36.104. "Evolved Universal Terrestrial Radio Access (E-UTRA); Base Station (BS) Radio
Transmission and Reception." 3rd Generation Partnership Project; Technical Specification Group
Radio Access Network.

3GPP TS 36.211. "Evolved Universal Terrestrial Radio Access (E-UTRA); Physical Channels and
Modulation." 3rd Generation Partnership Project; Technical Specification Group Radio Access
Network.

3GPP TS 36.213. "Evolved Universal Terrestrial Radio Access (E-UTRA); Physical Layer
Procedures." 3rd Generation Partnership Project; Technical Specification Group Radio Access
Network.

Local Functions

function t = nbiotAllowedGuardbandPRB()
    % Generate a table showing the PRB indices allowed for NB-IoT guardband
    % deployment which depend on guardband sizes

    NULRBList = [6 15 25 50 75 100]; % TS 36.101 Section 5.6
    bwMHz = [1.4 3 5 10 15 20]; % Bandwidth in MHz
    bw = (pad(string(bwMHz),'left') + repmat(" MHz (",size(bwMHz)) + pad(string(NULRBList),'left') + repmat(" RBs)",size(bwMHz)))';

    % Guardband mode
    % The allowed PRB indices for NB-IoT guardband mode are derived
    % here for all channel bandwidths.
    totalGuardHz = bwMHz*1e6 - NULRBList*12*15e3; % Total guardband in Hz
    NRBGuard = floor((totalGuardHz/2) / (12*15e3)); % Number of RBs allowed on each side of the guardband for all BWs
    PRBGuardLow = cellfun(@(x) (-x:-1),num2cell(NRBGuard(:)),'UniformOutput',false); % Allowed PRB indices for lower-edge guardband (0-based)
    PRBGuardHigh = cellfun(@(x,y) (y+(0:(x-1))),num2cell(NRBGuard(:)),num2cell(NULRBList(:)),'UniformOutput',false); % Allowed PRB indices for upper-edge guardband (0-based)

    t = table(bw,PRBGuardLow,PRBGuardHigh);
    t.Properties.VariableNames = ["LTE Bandwidth" "Guardband PRBs (Lower Edge)" "Guardband PRBs (Upper Edge)"];
end

function ngen = configureNBIoTUplinkWaveform(NULRB,nbiotPRBIndex,nvargs)
    % Configure the NB-IoT uplink waveform

    arguments
        % Number of uplink RBs, for reporting operation mode only
        NULRB
        % PRB index in which NB-IoT is deployed, for reporting operation
        % mode only
        nbiotPRBIndex
        % The RMC or FRC on which the configuration will be based, as
        % defined in TS 36.101 Annex A or TS 36.104 Annex A
        nvargs.RCName = 'A14-1';
        % Target first subcarrier index of the NPUSCH frequency allocation
        % in the PRB
        nvargs.SubcarrierOffset = 0;
        % Number of repetitions in each NPUSCH codeword
        nvargs.NRep = 1;
        % Narrowband physical layer cell identity (PCI)
        nvargs.NNCellID = 0;
        % Radio network temporary identifier of the UE
        nvargs.RNTI = 0;
        % NPUSCH DM-RS cyclic shift for multi-tone cases
        nvargs.DMRSCyclicShift = 0;

2-114

 NB-IoT Uplink Waveform Generation and Analysis

        % Total number of transport blocks to transmit in the waveform
        nvargs.TotNumTrBlks = 1;
        % RV offset signaled via DCI (TS 36.213 16.5.1.2)
        nvargs.RVDCI = 0;
        % Windowing for SC-FDMA modulation (TS 36.104 Table E.5.1-1a)
        nvargs.Windowing = 3;
        % NPUSCH power scaling in dB
        nvargs.NPUSCHPower = 0;
        % NPUSCH DM-RS power scaling in dB
        nvargs.NPUSCHDMRSPower = 0;
    end

    % Get primary independent parameters for the NPUSCH
    [ue,chs,tbs] = getBasicRMCDefinition(nvargs.RCName);

    % Set UE-wide parameters
    ue.NNCellID = nvargs.NNCellID;
    ue.DuplexMode = 'FDD';
    ue.Windowing = nvargs.Windowing;

    % Get the number of slots in a single RU according to TS 36.211 Table
    % 10.1.2.3-1
    if strcmpi(chs.NPUSCHFormat,'Data') % format 1
        if chs.NRUsc == 1
            NULSlots = 16;
        elseif any(chs.NRUsc == [3 6 12])
            NULSlots = 24 / chs.NRUsc; % giving 8/4/2 slots per RU at the associated number of subcarriers
        else
            error('Invalid number of subcarriers. NRUsc (%d) must be one of 1,3,6,12.',chs.NRUsc);
        end
    elseif strcmpi(chs.NPUSCHFormat, 'Control') % format 2
        NULSlots = 4;
    else
        error('Invalid NPUSCH format (%s). NPUSCH format must be ''Data'' or ''Control''', chs.NPUSCHFormat);
    end
    chs.NULSlots = NULSlots;

    % NPUSCH channel-specific parameters
    numSubcarriers = 12*15/str2double(ue.NBULSubcarrierSpacing(1:end-3));
    subcarrieroffset = min(nvargs.SubcarrierOffset,numSubcarriers-chs.NRUsc);
    chs.NBULSubcarrierSet = subcarrieroffset+(0:chs.NRUsc-1);
    chs.NRep = nvargs.NRep;
    chs.RNTI = nvargs.RNTI;
    chs.NSlotsPerBundle = chs.NRU*chs.NULSlots*chs.NRep;
    chs.CyclicShift = nvargs.DMRSCyclicShift;
    chs.SeqGroupHopping = 'off';
    chs.SeqGroup = 0;
    chs.SlotIdx = 0;
    chs.RVDCI = nvargs.RVDCI;
    chs.NPUSCHPower = nvargs.NPUSCHPower;
    chs.NPUSCHDMRSPower = nvargs.NPUSCHDMRSPower;

    % Set the DM-RS base sequence ID according to TS 36.211 Section
    % 10.1.4.1.2. DM-RS base sequence ID is used for the multi-tone case
    % (3, 6, 12 tones), while it has no effect for single-tone or disabled
    % sequence-group hopping cases.
    if chs.NRUsc == 3
        maxBaseSeqIdx = 12;

2-115

2 Examples and Demos

    elseif chs.NRUsc == 6
        maxBaseSeqIdx = 14;
    else
        maxBaseSeqIdx = 30;
    end
    chs.BaseSeqIdx = mod(ue.NNCellID,maxBaseSeqIdx);

    % Calculate waveform duration parameters to be used for waveform
    % generation
    if strcmpi(ue.NBULSubcarrierSpacing,'15kHz')
        NSlotsPerFrame = 20;
        NSlotsPerSubframe = 2;
    else
        NSlotsPerFrame = 5;
        NSlotsPerSubframe = 0.5;
    end
    TotNSlots = nvargs.TotNumTrBlks*chs.NSlotsPerBundle;
    TotSubframes = TotNSlots/NSlotsPerSubframe;

    % Set the configuration structure ngen
    ngen = ue;
    ngen.TBS = tbs;
    ngen.TotNumTrBlks = nvargs.TotNumTrBlks;
    ngen.TotNSlots = TotNSlots;
    ngen.TotSubframes = TotSubframes;
    ngen.NSlotsPerFrame = NSlotsPerFrame;
    ngen.NPUSCH = chs;

    % Report operation mode
    if any(nbiotPRBIndex == (0:NULRB-1))
        operationMode = 'in-band';
    else
        gbTable = nbiotAllowedGuardbandPRB();
        gbPRBs = [gbTable{contains(gbTable{:,1},string(NULRB)+" RBs"),2:3}{:}];
        if any(nbiotPRBIndex == gbPRBs)
            operationMode = 'guardband';
        else
            operationMode = 'out-of-band';
        end
    end
    fprintf('\nSimulating %s NB-IoT carrier\n',operationMode);
end

function [ue,chs,tbs] = getBasicRMCDefinition(rcname)
    % Get the primary independent parameters for the RMC from the RAN4
    % RMC/FRC specification tables

        persistent rclist nl;

        if isempty(rclist)

            % TS 36.104 A.14 Fixed Reference Channels for NB-IoT reference sensitivity (pi/2 BPSK, R=1/3)
            rclistA14 = struct( ...
                'RCName',compose('A14-%d',1:2), ...
                'TBS',32, ...
                'NBULSubcarrierSpacing',{'15kHz','3.75kHz'}, ...
                'NRUsc',1, ...
                'Modulation','BPSK', ...  % (pi/2) BPSK for single tone

2-116

 NB-IoT Uplink Waveform Generation and Analysis

                'NRU',2, ...  % Each NPUSCH instance is 2 RUs of 1x16 'subcarriers x slots x pi/2-BPSK'
                'NPUSCHFormat','Data' ...
                );

            % TS 36.104 A.15 Fixed Reference Channels for NB-IoT dynamic range (pi/4 QPSK, R=2/3)
            rclistA15 = struct( ...
                'RCName',compose('A15-%d',1:2), ...
                'TBS',104, ...
                'NBULSubcarrierSpacing',{'15kHz','3.75kHz'}, ...
                'NRUsc',1, ...
                'Modulation','QPSK', ...  % (pi/4) QPSK for a single tone
                'NRU',1, ...  % Each NPUSCH instance to 1 RU of 1x16 'subcarriers x slots x pi/4-QPSK'
                'NPUSCHFormat','Data' ...
                );

            % TS 36.104 A.16 Fixed Reference Channels for NB-IoT NPUSCH format 1
            % A.16.1 One PRB
            rclistA16_1 = struct( ...
                'RCName',compose('A16-%d',1:6), ...
                'TBS',{32,32,40,104,136,424}, ...
                'NBULSubcarrierSpacing',{'3.75kHz','15kHz','15kHz','15kHz','15kHz','15kHz'}, ...
                'NRUsc',{1,1,3,6,12,12}, ...
                'Modulation',{'BPSK','BPSK','QPSK','QPSK','QPSK','QPSK'}, ...
                'NRU',{2,2,1,1,1,5}, ...
                'NPUSCHFormat','Data' ...
                );
            % A16-7 uses 16QAM
            rclistA16_2 = struct( ...
                'RCName','A16-7', ...
                'TBS',280, ...
                'NBULSubcarrierSpacing','15kHz', ...
                'NRUsc',12, ...
                'Modulation','16QAM', ...
                'NRU',1, ...
                'NPUSCHFormat','Data' ...
                );

            % TS 36.101, Annex A.2.4 Reference Measurement Channels for UE Category NB1
            rclistA24 = struct( ...
                'RCName',compose('R-%d',1:7), ...
                'TBS',{32,40,32,40,72,72,72}, ...
                'NBULSubcarrierSpacing',{'3.75kHz','3.75kHz','15kHz','15kHz','15kHz','15kHz','15kHz'}, ...
                'NRUsc',{1,1,1,1,3,6,12}, ...
                'Modulation',{'BPSK','QPSK','BPSK','QPSK','QPSK','QPSK','QPSK'}, ...
                'NRU',{2,1,2,1,1,1,1}, ...
                'NPUSCHFormat','Data' ...
                );

            % Control (NPUSCH format 2) 'reference' channels (provided here for utility, not 3GPP defined)
            rclistControl = struct( ...
                'RCName',compose('Control-%d',1:2), ...
                'TBS',0, ...
                'NBULSubcarrierSpacing',{'3.75kHz','15kHz'}, ...
                'NRUsc',1, ...
                'Modulation','BPSK', ...
                'NRU',1, ...
                'NPUSCHFormat','Control' ...
                );

2-117

2 Examples and Demos

            % Combine all the sets of channel definitions into a single structure vector
            rclist = [rclistA14,rclistA15,rclistA16_1,rclistA16_2,rclistA24,rclistControl];
            nl = {rclist.RCName}; % Store all the RMC names contained in the above definitions

        end

        % Look-up the definition entry for the required FRC
        selection = rclist(strcmpi(rcname,nl));
        if isempty(selection)
            error('RC name must be one of %s.', join(string(nl),', '));
        end

        % Parameter field mapping function
        fv = @(y,v)setfield(y,v,selection.(v));

        % Create the UE-specific parameter structure
        ue = struct();
        ue = fv(ue,'NBULSubcarrierSpacing');

        % Create the NPUSCH channel-specific structure
        chs = struct();
        chs = fv(chs,'NPUSCHFormat');
        chs = fv(chs,'Modulation');
        chs = fv(chs,'NRUsc');
        chs = fv(chs,'NRU');

        % Return the associated TBS
        tbs = selection.TBS;
end

function [waveform,info] = generateNBIoTUplinkWaveform(ngen)
    % Generate the NB-IoT uplink waveform

    % Get parameters
    ue = ngen;
    chs = ngen.NPUSCH;
    TotNSlots = ngen.TotNSlots;
    tbs = ngen.TBS;
    NSlotsPerFrame = ngen.NSlotsPerFrame;

    % Get the slot grid
    emptySlotGrid = lteNBResourceGrid(ue);
    slotGridSize = size(emptySlotGrid);
    L = slotGridSize(2);

    % Initialization
    state = [];
    trblk = [];
    nbGrid = repmat(emptySlotGrid,1,TotNSlots);

    % Display the number of slots being generated
    fprintf('\nGenerating %d slots corresponding to %d transport block(s) transmitted on NPUSCH\n',TotNSlots,ngen.TotNumTrBlks);

    % Loop over slots
    for slotIdx = chs.SlotIdx+(0:TotNSlots-1)

        % Calculate the frame number and slot number within the frame

2-118

 NB-IoT Uplink Waveform Generation and Analysis

        ue.NFrame = fix(slotIdx/NSlotsPerFrame);
        ue.NSlot = mod(slotIdx,NSlotsPerFrame);

        if isempty(trblk)
            if strcmpi(chs.NPUSCHFormat,'Data')
                % UL-SCH encoding is done for the two RV values used for
                % transmitting the codewords. The RV sequence used is
                % determined from the rvDVI value signaled in the DCI and
                % alternates between 0 and 2 as given in TS 36.213 Section
                % 16.5.1.2

                % Determine the coded transport block size
                [~,npuschInfo] = lteNPUSCHIndices(ue,chs);
                outblklen = npuschInfo.G;

                if outblklen>0
                    % Define the transport block which will be encoded to
                    % create the codewords for different RV
                    trblk = randi([0 1],tbs,1);

                    % Create the codewords corresponding  to the two RV
                    % values used in the first and second block. This will
                    % be repeated till all blocks are transmitted
                    chs.RV = 2*mod(chs.RVDCI+0,2);                        % RV for the first block
                    cw = lteNULSCH(chs,outblklen,trblk);                  % CRC and Turbo coding
                    chs.RV = 2*mod(chs.RVDCI+1,2);                        % RV for the second block
                    cw = [cw lteNULSCH(chs,outblklen,trblk)]; %#ok<AGROW> % CRC and Turbo coding is repeated
                else
                    % If the coded transport block size is zero, there is
                    % no transmission in this slot
                    cw = zeros(0,1);
                end
            else
                trblk = randi([0 1],1); % 1 bit ACK;
                % For ACK, the same codeword is transmitted in every block
                % as defined in TS 36.212 Section 6.3.3
                cw = lteNULSCH(trblk);
            end
            blockIdx = 0; % First block to be transmitted
            thisCw = getCodewordBlock(cw,blockIdx);
        end

        % Initialize grid
        slotRange = (slotIdx-chs.SlotIdx)*L+(1:L);
        slotGrid = nbGrid(:,slotRange);

        % Encode NPUSCH and map to the slot grid
        npuschSym = lteNPUSCH(ue,chs,thisCw,state);
        npuschInd = lteNPUSCHIndices(ue,chs);
        slotGrid(npuschInd) = npuschSym*db2mag(chs.NPUSCHPower);

        % Create DM-RS sequence and map to the slot grid
        [dmrsSym,state] = lteNPUSCHDRS(ue,chs,state);
        dmrsInd = lteNPUSCHDRSIndices(ue,chs);
        slotGrid(dmrsInd) = dmrsSym*db2mag(chs.NPUSCHDMRSPower);

        % Insert this slot into the waveform grid
        nbGrid(:,slotRange) = slotGrid;

2-119

2 Examples and Demos

        % If a full block is transmitted, increment the clock counter so
        % that the correct codeword can be selected
        if state.EndOfBlk
            blockIdx = blockIdx+1;
            thisCw = getCodewordBlock(cw,blockIdx);
        end

        % Transport block count and re-initialization
        if state.EndOfTx
            trblk = [];
        end
    end % end of slot loop

    % Perform SC-FDMA modulation to create time domain baseband waveform
    ue.CyclicPrefixUL = 'Normal';
    [waveform,info] = lteSCFDMAModulate(ue,chs,nbGrid);
end

function cwOut = getCodewordBlock(cwIn,blockIdx)
    % Get the slice of the codeword related to the input block index
    cwOut = cwIn(:,mod(blockIdx,size(cwIn,2))+1);
end

function ltecfg = configureWidebandLTEWaveform(NULRB,TotSubframe,nbiotPRBIndex)
    % Configure and generate the wideband LTE waveform with the given
    % number of uplink RBs, NULRB, the total number of subframes,
    % TotSubframe, and the PRB index of the PRB reserved for NB-IoT
    % deployment, nbiotPRBIndex, based on a reference measurement channel
    % (RMC) as defined in TS 36.104 Annex A

    % Select a reference measurement channel (RMC) as template
    ltecfg = struct();
    ltecfg.RC = 'A1-3'; % TS 36.104 Annex A
    ltecfg.NULRB = NULRB;

    % Set waveform duration
    ltecfg.TotSubframes = TotSubframe;

    % Use full band frequency allocation for PUSCH, and reserve the PRB
    % deployed with the NB-IoT component when operating in the in-band mode
    prbSet = (0:NULRB-1)';
    prbSet(prbSet==nbiotPRBIndex) = [];
    ltecfg.PUSCH.PRBSet = prbSet;
end

See Also

Related Examples
•

“NB-IoT Downlink Waveform Generation” on page 2-121

2-120

 NB-IoT Downlink Waveform Generation

NB-IoT Downlink Waveform Generation

This example shows how to generate LTE-Advanced Pro Release 13 narrowband IoT (NB-IoT)
waveforms for test and measurement applications using LTE Toolbox™ software.

Introduction

3GPP introduced a new air interface, Narrowband IoT (NB-IoT) optimized for low data rate machine
type communications in LTE-Advanced Pro Release 13. NB-IoT provides cost and power efficiency
improvements as it avoids the need for complex signaling overhead required for LTE based systems.

The LTE Toolbox can be used to generate standard compliant NB-IoT downlink complex baseband
waveforms representing the 180 kHz narrowband carrier suitable for test and measurement
applications. The waveform consists of the individual physical layer channels and signals and the
MATLAB® value class NBIoTDownlinkWaveformGenerator can be used for full resource element (RE)
grid and time-domain waveform generation. The LTE Toolbox supports all the NB-IoT modes of
operation - standalone, guardband and in-band.

• Standalone: NB-IoT carrier deployed outside the LTE spectrum, e.g. the spectrum used for GSM or

satellite communications

• Guardband: NB-IoT carrier deployed in the guardband between two LTE carriers

• In-band: NB-IoT carrier deployed in resource blocks of a LTE carrier

In-band mode can be further grouped depending on the physical cell identity (PCI) used, Inband-
SamePCI and Inband-DifferentPCI. If Inband-SamePCI, the physical layer cell identity and PCI are the
same and the UE can make assumptions about the ports and channel from LTE signals. The operation
mode is indicated in the NB-IoT MIB (MIB-NB), which provides essential information for the user
equipment (UE). The network can use radio resource control information to allocate a non-anchor
carrier to an UE operating in an anchor carrier, see TS 36.331 section 6.7.3.2 [ 5 ] and section 7.3.2.4
in [ 9 ].

This example creates the NB-IoT downlink, where the relevant physical layer channels and signals
are:

• Narrowband primary synchronization signal (NPSS)

• Narrowband secondary synchronization signal (NSSS)

• Narrowband reference signal (NRS)

• Narrowband physical broadcast channel (NPBCH)

• Narrowband physical downlink shared channel (NPDSCH)

• Narrowband physical downlink control channel (NPDCCH)

NB-IoT supports two carrier configurations:

• Anchor: The carrier used by the UE for initial NB-IoT cell selection, obtaining MIBs and system
information blocks (SIBs), and random access in the idle mode. The NPSS, NSSS, NPBCH, and
system information are transmitted on the carrier.

• Non-anchor: A carrier only used for actual exchange of data in the connected mode. NPSS, NSSS,

NPBCH, and system information are not transmitted on the carrier.

In this example, we demonstrate the NB-IoT downlink RE grid and waveform generation. The sections
below explain the physical signals and channels that form the grid along with key concepts including

2-121

2 Examples and Demos

subframe repetition, logical and transport channel mappings, and the corresponding grids for the
different configurations. Moreover, the parameters involved in the waveform generation are shown to
create waveforms as per user requirements.

The example outputs the complex baseband waveform along with the populated grid containing all
the above mentioned physical channels and signals and also information about the type of data
contained in each subframe. The waveform can be used for a range of applications from RF testing to
simulation of receiver implementations.

NB-IoT Downlink Subframe Allocation

This section explains how the physical layer channels and signals mentioned above are mapped into
the downlink subframes.

• Downlink bit map: A logical vector to configure the NB-IoT downlink subframes. NB-IoT downlink
subframes are defined as the subframes used for NPDCCH and NPDSCH not carrying SIB1-NB, it
does not include subframes carrying NPSS, NSSS, NPBCH and NB-IoT system information block
type 1 (SIB1-NB). The NB-IoT downlink subframes can be configured using parameter
Config.DownlinkBitmap in class NBIoTDownlinkWaveformGenerator.

• NPSS & NSSS: As illustrated in the figure below, the NPSS is transmitted in subframe 5 in every
frame, and the NSSS is transmitted in subframe 9 in frames with frame number nf fulfilling nf
mod 2 = 0. The NPSS and NSSS allow the UE to synchronize to the NB-IoT cell.

• NPBCH: The NPBCH is used to carry the 34 bit MIB-NB (TS 36.212 section 6.4.1 [ 2 ]). The MIB-
NB is coded to form a 1600 bits codeword (TS 36.211 section 10.2.4.1 [ 1 ]). The codeword is
evenly segmented into 8 sub-blocks, each one has 200 bits which are transmitted on subframe 0
and repeated in the 7 following consecutive frames (TS 36.211 section 10.2.4.4 [ 1 ]). The mapping
of the codeword bits is illustrated in the figure below.

2-122

 NB-IoT Downlink Waveform Generation

• NPDSCH: The key feature of NPDSCH is subframe repetition. NB-IoT defines two repetition

schemes for the case when NPDSCH is carrying broadcast control channel (BCCH) or not. BCCH
is the logical channel to carry SIB1-NB, system information messages, etc. Not carrying BCCH
implies that NPDSCH may carry Paging Control Channel (PCCH), Common Control Channel
(CCCH), Dedicated Control Channel (DCCH), Dedicated Traffic Channel (DTCH), etc (TS 36.300
sections 6.1.3.2 and 5.3.1a [ 6 ]). The two repetition schemes are illustrated in the figure below.
The NPDSCH repetition parameters includes the number of subframes in a codeword NSF and the
number of repetitions NRep. The example in the figure shows the repetition pattern with NRep = 4
for the case when NPDSCH is carrying BCCH and NRep = 8 for the case when NPDSCH is not
carrying BCCH and NSF = 3 for both cases. For the case when carrying BCCH, all the subframes
of a codeword are transmitted before repeating the codeword. For the case when not carrying
BCCH, a subframe in the codeword is repeated by min(NRep,4) before performing the same
repetition for the other subframes. After the codeword is repeated by min(NRep,4) times, the
same procedure is performed until the full repetition is complete, i.e., repeated by NRep times.
The detailed specification of the repetition scheme can be found in TS 36.211 section 10.2.3 [ 1 ].

The repeated subframes shown in the above figure are mapped to the available subframes allocated
for NPDSCH transmission. As a typical example, the following figure illustrates how to perform
mapping for the subframes of NPDSCH carrying SIB1-NB, which contains the most important system
information for an UE (TS 36.331 section 6.7.2 [ 5 ]).

A SIB1-NB is carried in 8 subframes (NSF = 8), and mapped to subframe 4 in every other frame in 16
continuous frames which are repeated NRep times (NRep = 4, 8 or 16, see TS 36.213 section 16.4.1.3
Table 16.4.1.3-3 [ 3 ]). The repetitions are equally spaced within a period of 256 frames (TS 36.331
section 5.2.1.2a [ 5 ]). The starting frame number for the first NPDSCH transmission in the period

2-123

2 Examples and Demos

depends on the narrowband physical cell identity NNCellID as well as the number of repetitions
NRep (TS 36.213 Table 16.4.1.3-4 [ 3 ]).

NB-IoT Downlink Grid

In addition to the subframe allocation described above, the generated grids below further explain the
RE allocation in a subframe. The grid is for two frames of an anchor carrier containing NPSS, NSSS,
NRS, NPBCH, SIB1-NB, and NB-IoT downlink subframes carrying NPDSCH and NPDCCH. The grids
are compared in Standalone and Inband-SamePCI operation modes. The grid can be generated
using the grid display method in the class NBIoTDownlinkWaveformGenerator, i.e., creating an object
ngen of type NBIoTDownlinkWaveformGenerator and calling ngen.displayResourceGrid.

• NRS: The RE positions can be configured by the number of NRS ports and the narrowband

physical cell identity, i.e., the parameter fields NBRefP and NNCellID in structure ngen.Config,
respectively.

• NPSS & NSSS: The first 11 subcarriers are used for NPSS, all 12 subcarriers in a physical

resource block are used for NSSS. The first 3 OFDM symbols in a subframe are not used for NPSS/
NSSS. NRS is not transmitted in any subframe containing NPSS/NSSS. The REs of NPSS/NSSS are
punctured by the LTE cell-specific reference signal (CRS) only in in-band modes. The number of
CRS ports that affects the puncturing can be configured by parameter field CellRefP in structure
ngen.Config (TS 36.211 sections 10.2.6 and 10.2.7 [ 1 ]).

• NPBCH: The REs are punctured by the NRS and the CRS using the maximum number of NRS and
CRS antenna ports (2 and 4, respectively), for both operation modes (TS 36.211 section 10.2.4
[ 1 ]). This is because the UE has no knowledge about the number of used antenna ports and the
operation mode.

• NPDSCH: For operation modes Standalone and Guardband, the REs are punctured by NRS
only; for in-band operation modes, the REs are punctured by both NRS and CRS. When the
operation mode is in-band, the first 3 OFDM symbols in the subframe are not used for NPDSCH
carrying SIB1-NB, the first ControlRegionSize OFDM symbols in the subframe are not used
when NPDSCH is carried by a NB-IoT downlink subframe. ControlRegionSize is a parameter
field in structure ngen.Config to configure the LTE control region size for NPDSCH RE
allocations (TS 36.211 section 10.2.3.4 [ 1 ], TS 36.213 section 16.4.1.4 [ 3 ] and TS 36.331 section
6.7.2 [ 5 ]). The LTE control region size configures the starting OFDM symbol position in a NB-IoT
downlink subframe carrying NPDSCH and NPDCCH in in-band operation modes.

• NPDCCH: The NRS and CRS puncturing are the same as that in NPDSCH described above. When
the operation mode is in-band, the first ControlRegionSize OFDM symbols in the subframe are
not used for NPDCCH. Same as that for NPDSCH, ControlRegionSize is used to configure the
NPDCCH RE allocations (TS 36.211 section 10.2.3.4 [ 1 ], TS 36.213 section 16.4.1.4 [ 3 ] and TS
36.331 section 6.7.2 [ 5 ]).

ngen = NBIoTDownlinkWaveformGenerator;

2-124

 NB-IoT Downlink Waveform Generation

figure;
% Display the resource grid with default 'Standalone' operation mode
ngen.displayResourceGrid;
figure;
% Change the operation mode to 'Inband-SamePCI'
ngen.Config.OperationMode = 'Inband-SamePCI';
ngen.displayResourceGrid;

2-125

2 Examples and Demos

The object ngen contains the following:

• Resource allocation and transport block size (TBS) tables for NPDSCH (see TS 36.213 sections

16.4.1.3 and 16.4.1.5 [ 3 ])

• Structure ngen.Config with the NB-IoT eNodeB configuration where parameter fields NPBCH,
SIB1NPDSCH, NPDCCH and NPDSCH configure NPBCH, NPDSCH carrying SIB1-NB, NPDSCH
carrying other SIBs (SIBn-NB), NPDCCH and NPDSCH not carrying SIB1-NB (i.e., NPDSCH
carried by NB-IoT downlink subframes), respectively.

ngen                                      % Show all available properties
nsfTable = ngen.NSFTable                  % Display number of subframes table in TS 36.213 section 16.4.1.3
enbConfig = ngen.Config                   % Display NB-IoT eNodeB configuration
npbchConfig = ngen.Config.NPBCH           % Display NPBCH configuration
sib1npdschConfig = ngen.Config.SIB1NPDSCH % Display the configuration of NPDSCH when carrying SIB1-NB
sibnnpdschConfig = ngen.Config.SIBnNPDSCH % Display the configuration of NPDSCH when carrying other NB SIBs (not SIB1-NB)

ngen =

  NBIoTDownlinkWaveformGenerator with properties:

           Config: [1×1 struct]
         NSFTable: [8×2 table]
        NRepTable: [16×2 table]
         TBSTable: [176×3 table]
    NRepTableSIB1: [12×2 table]
     TBSTableSIB1: [12×2 table]

2-126

nsfTable =

  8×2 table

    ISF    NSF
    ___    ___

     0      1
     1      2
     2      3
     3      4
     4      5
     5      6
     6      8
     7     10

enbConfig =

  struct with fields:

          TotSubframes: 20
              NNCellID: 0
                NBRefP: 1
              CellRefP: 4
     ControlRegionSize: 3
                NFrame: 0
         OperationMode: 'Inband-SamePCI'
        DownlinkBitmap: [1 1 1 1 1 1 1 1 1 1]
           CarrierType: 'Anchor'
        DLGapThreshold: 32
      DLGapPeriodicity: 64
    DLGapDurationCoeff: 0.1250
             NPSSPower: 0
             NSSSPower: 0
                 NPBCH: [1×1 struct]
            SIB1NPDSCH: [1×1 struct]
            SIBnNPDSCH: [1×1 struct]
                NPDCCH: [1×1 struct]
                NPDSCH: [1×1 struct]

npbchConfig =

  struct with fields:

             Power: 0
      EnableCoding: 'On'
       DataBlkSize: 34
        DataSource: 'PN9'
    DataRepetition: 'Off'

sib1npdschConfig =

  struct with fields:

 NB-IoT Downlink Waveform Generation

2-127

2 Examples and Demos

            Enable: 'On'
             Power: 0
              NRep: 4
        Modulation: 'QPSK'
      EnableCoding: 'On'
       DataBlkSize: 208
        DataSource: 'PN9'
    DataRepetition: 'Off'

sibnnpdschConfig =

  struct with fields:

                      Enable: 'Off'
                       Power: 0
         si_WindowLength_r13: 160
     si_RadioFrameOffset_r13: 2
          si_Periodicity_r13: 64
    si_RepetitionPattern_r13: 2
                   si_TB_r13: 56
           SchedulingInfoIdx: 0
                EnableCoding: 'On'
                  DataSource: 'PN9'
              DataRepetition: 'Off'

NPDCCH/NPDSCH Configuration

The generated RE grid below explains how to configure the subframes used for NB-IoT downlink
subframes using downlink bit map, and how to configure the parameters of NPDCCH/NPDSCH
carried by the NB-IoT downlink subframes. The NB-IoT downlink subframes can be configured by
parameter field DownlinkBitmap in the structure ngen.Config. In the example, a non-anchor
carrier is used to disable NPSS, NSSS, NPBCH and SIB1-NB in the grid.

The waveform generator supports multiple NPDCCH and NPDSCH. Each NPDSCH and NPDCCH
contains a single transport block and downlink control information (DCI) message, respectively. The
parameters of a NPDCCH/NPDSCH is specified by a structure, and multiple NPDCCH/NPDSCH are
expressed as a structure vector.

A NPDCCH is configured by the following parameters in the structure ngen.Config.NPDCCH:

• Enable: Enabling or disabling the NPDCCH ('On', 'Off').

• Power: Relative power for NPDCCH symbols in the frequency domain with assumption that the

NRS power is 1.

• NCCE: The selected narrowband control channel elements (NCCEs) to carry the NDPCCH. The
value can be either a scalar or a vector of two entries. A scalar or vector indicates NPDCCH
format 0 or 1, respectively. Entry value 0 (or 1) indicates NCCE 0 (or NCCE 1). NCCE 0 occupies
subcarriers 0 to 5 and NCCE 1 occupies subcarriers 6 to 11, respectively. (TS 36.211 section
10.2.5.1 [ 1 ]).

• NRep: Number of repetitions for a NPDCCH candidate (TS 36.213 section 16.6 [ 3 ]). Allowed

values are

, where n = 1...10.

• Rmax: Maximum number of repetitions for NPDCCH (TS 36.213 section 16.6 [ 3 ]). It affects the

NPDCCH transmission gap. Allowed values are

, where n = 1...10.

2-128

 NB-IoT Downlink Waveform Generation

• RNTI: Radio network temporary identifier used for scrambling.

• StartSubframe: 0-based starting subframe indices of each NPDCCH transmission in the

associated NPDCCH period in the generated RE grid. Any starting indices that occur when a
NPDCCH transmission is already underway are ignored.

• Period: NPDCCH allocation period in subframes. An empty value indicates no repetition.

• EnableCoding: Enabling or disabling the DCI encoding ('On', 'Off').

• DataBlkSize: Length of the DCI information bits.

• DataSource: DCI information bits. The parameter can be defined directly as a bit vector or using
a random data type e.g., 'PN9-ITU', 'PN9', 'PN11', 'PN15', 'PN23'. For the latter case, a random bit
vector is generated for the selected type.

• DataRepetition: Enabling or disabling the repetition of the data used in the first transmission

to all subsequent transmissions ('On', 'Off').

A NPDSCH is configured by the following parameters in the structure ngen.Config.NPDSCH:

• Enable: Enabling or disabling the NPDSCH ('On', 'Off').

• Power: Relative power for NPDSCH symbols in the frequency domain with assumption that the

NRS power is 1.

• NPDSCHDataType: Type of data the NPDSCH carries, the allowed values are either

'BCCHNotSIB1NB' or 'NotBCCH'. This value affects the repetition scheme as described above.

• NRep: The number of repetitions (TS 36.211 section 16.4.1.3 [ 1 ]).

• NSF: The number of subframes in a NPDSCH codeword (TS 36.211 section 16.4.1.3 [ 1 ]).

• Rmax: Maximum number of repetitions for the NPDCCH associated to the NPDSCH, its value

should be equal to the value of the same field in the corresponding NPDCCH.

• StartSubframe: 0-based starting subframe indices of each NPDSCH transmission in the

associated NPDSCH period in the generated RE grid. Any starting indices that occur when a
NPDSCH transmission is already underway are ignored.

• Period: NPDSCH allocation period in subframes. An empty value indicates no repetition.

• Modulation: Modulation used by the NPDSCH ('QPSK','16QAM').

• EnableCoding: Enabling or disabling the DL-SCH encoding ('On', 'Off').

• DataBlkSize: Transport block size.

• DataSource: Information bits of the transport block. The usage is the same as the same field in

structure ngen.Config.NPDCCH.

• DataRepetition: Enabling or disabling the repetition of the data used in the first transmission

to all subsequent transmissions ('On', 'Off').

ngen = NBIoTDownlinkWaveformGenerator;
ngen.Config.CarrierType = 'NonAnchor'; % Anchor or NonAnchor
ngen.Config.DownlinkBitmap = [1 0 1 1 1 1 1 1 0 1];
ngen.Config.TotSubframes = 30;

% Configure the parameters of the first NPDCCH
npdcch1 = ngen.Config.NPDCCH;
npdcch1.Enable = 'On';
npdcch1.Power = 0;
npdcch1.NCCE = 1;  % NPDCCH format 0 with NCCE 1
npdcch1.NRep = 2;
npdcch1.Rmax = 16;

2-129

2 Examples and Demos

npdcch1.RNTI = 0;
npdcch1.StartSubframe = 0;
npdcch1.Period = [];
npdcch1.EnableCoding = 'On';
npdcch1.DataBlkSize = 23;
npdcch1.DataSource = randi([0 1],npdcch1.DataBlkSize,1); % Users can define their own information bits
npdcch1.DataRepetition = 'Off';

% Configure the parameters of the second NPDCCH
npdcch2 = ngen.Config.NPDCCH;
npdcch2.Enable = 'On';
npdcch2.Power = 0;
npdcch2.NCCE = 0;  % NPDCCH format 0 with NCCE 0
npdcch2.NRep = 4;
npdcch2.Rmax = 16;
npdcch2.RNTI = 1;
npdcch2.StartSubframe = 3;
npdcch2.Period = [];
npdcch2.EnableCoding = 'On';
npdcch2.DataBlkSize = 23;
npdcch2.DataSource = 'PN9';
npdcch2.DataRepetition = 'Off';

% Configure the parameters of the first NPDSCH
npdsch1 = ngen.Config.NPDSCH;
npdsch1.Enable = 'On';
npdsch1.Power = 0;
npdsch1.NPDSCHDataType = 'BCCHNotSIB1NB';
npdsch1.NSF = 3;
npdsch1.NRep = 2;
npdsch1.Rmax = npdcch1.Rmax;
npdsch1.RNTI = 0;
npdsch1.StartSubframe = 10;
npdsch1.Period = [];
npdsch1.EnableCoding = 'On';
npdsch1.Modulation = 'QPSK';
npdsch1.DataBlkSize = 616;
npdsch1.DataSource = 'PN15';
npdsch1.DataRepetition = 'Off';

% Configure the parameters of the second NPDSCH
npdsch2 = ngen.Config.NPDSCH;
npdsch2.Enable = 'On';
npdsch2.Power = 0;
npdsch2.NPDSCHDataType = 'NotBCCH';
npdsch2.NSF = 2;
npdsch2.NRep = 4;
npdsch2.Rmax = npdcch2.Rmax;
npdsch2.RNTI = 1;
npdsch2.StartSubframe = 20;
npdsch2.Period = [];
npdsch2.EnableCoding = 'On';
npdsch2.Modulation = 'QPSK';
npdsch2.DataBlkSize = 616;
npdsch2.DataSource = 'PN23';
npdsch2.DataRepetition = 'Off';

% Prepare NPDSCH and NPDCCH structure vectors

2-130

 NB-IoT Downlink Waveform Generation

ngen.Config.NPDCCH = [npdcch1 npdcch2];
ngen.Config.NPDSCH = [npdsch1 npdsch2];

figure;
ngen.displayResourceGrid;

The generated RE grid below explains how to configure the transmission gap for NPDSCH/NPDCCH
according to TS 36.211 sections 10.2.3.4 and 10.2.5.5 [ 1 ]. The gap is defined by parameter field
Rmax mentioned above, as well as the following parameters in structure ngen.Config:

• DLGapThreshold: Threshold to trigger the transmission gap, i.e., there are no gaps in the

NPDSCH transmission if Rmax < |DLGapThreshold|. Allowed values are 32, 64, 128, 256 (TS
36.331 section 6.7.1 [ 5 ]).

• DLGapPeriodicity: The gap periodicity in number of subframes. It also defines the starting

subframe of the gap, i.e., the starting subframe number sf satisfying condition (sf mod
DLGapPeriodicity) = 0. Allowed values are 64, 128, 256, 512 (TS 36.331 section 6.7.1 [ 5 ]).

• DLGapDurationCoeff: Used to calculate the gap duration in number of subframes, together with

DLGapPeriodicity. The gap duration is given by DLGapPeriodicity
DLGapDurationCoeff. Allowed values are 1/8, 1/4, 3/8, 1/2 (TS 36.331 section 6.7.1 [ 5 ]).

The following example uses defaulting parameters DLGapThreshold = 32, DLGapPeriodicity =
64 and DLGapDurationCoeff = 1/8 to explain the NPDSCH transmission gap. The figure below
illustrates that the 96 (NRep
subframes, and the two gaps start at subframe 0 and subframe 64, respectively.

 NSF) NPDSCH subframes is disrupted by two gaps with a duration of 8

2-131

2 Examples and Demos

ngen = NBIoTDownlinkWaveformGenerator;
ngen.Config.CarrierType = 'NonAnchor'; % Anchor or NonAnchor
ngen.Config.TotSubframes = 150;
ngen.Config.NPDCCH.Enable = 'Off';     % Disable the NPDCCH
ngen.Config.NPDSCH.StartSubframe = 0;
ngen.Config.NPDSCH.Rmax = ngen.Config.DLGapThreshold; % Minimum value to trigger the transmission gap based on given DLGapThreshold
ngen.Config.NPDSCH.NRep = 32;
ngen.Config.NPDSCH.NSF = 3;

figure;
ngen.displayResourceGrid;

NB-IoT Downlink Waveform Generation

Generate the time-domain waveform of a reference measurement channel (RMC) for NPDSCH
performance requirements, according to TS 36.101 Appendix A.3.12 [ 7 ], or the NB Test Model (N-
TM), defined in TS 36.141 sections 6.1.3-6.1.6 [ 8 ]. The waveform can be generated using the
waveform generation method in the class NBIoTDownlinkWaveformGenerator, to call the method, an
object ngen is created and the method can be called by using ngen.generateWaveform.

rc = 'R.NB.5-1'; % Allowed values are 'R.NB.5','R.NB.5-1','R.NB.6','R.NB.6-1','R.NB.7','R.NB.8','R.NB.9','N-TM'
ngen = NBIoTDownlinkWaveformGenerator(rc);
[waveform,grid,ofdmInfo] = ngen.generateWaveform;
ofdmInfo         % Display OFDM configuration
spectrumScope = spectrumAnalyzer;
spectrumScope.SampleRate = ofdmInfo.SamplingRate;
spectrumScope.ShowLegend = true;
if ngen.Config.NBRefP == 1

2-132

 NB-IoT Downlink Waveform Generation

    spectrumScope.ChannelNames = {['Signal for RMC ' rc ' (Port 2000)']};
    spectrumScope(waveform);
else % NBRefP == 2
    spectrumScope.ChannelNames = {['Signal for RMC ' rc ' (Port 2000)'], ...
        ['Signal for RMC ' rc ' (Port 2001)']};
    spectrumScope(waveform(:,1),waveform(:,2));
end

ofdmInfo =

  struct with fields:

            SamplingRate: 1920000
                    Nfft: 128
               Windowing: 6
     CyclicPrefixLengths: [10 9 9 9 9 9 9 10 9 9 9 9 9 9]
    SubframeChannelTypes: ["NPDCCH"    "Unused"    …    ] (1×20 string)

The following figures compare the signal spectrums for the generated time-domain waveform. As
shown in the spectrum analyzer, the signal with yellow color has stronger power than the one with
blue color. This is because the RE usage percentage of yellow one is higher.

% Set up a standalone, non-anchor carrier, disable the NPDCCH and make the
% REs grid fully occupied by NPDSCH/NRS

2-133

2 Examples and Demos

ngen = NBIoTDownlinkWaveformGenerator;
ngen.Config.CarrierType = 'NonAnchor';
ngen.Config.NPDCCH.Enable = 'Off'; % Disable the NPDCCH
ngen.Config.NPDSCH.StartSubframe = 0;
ngen.Config.NPDSCH.NRep = 8;
ngen.Config.NPDSCH.NSF = 5;

% Display the grid and generate the time-domain signal
figure;
ngen.displayResourceGrid;
[waveform1,~,ofdmInfo1] = ngen.generateWaveform;

% Set up a standalone, anchor carrier, disable the NPDSCH and NPDCCH so
% that it contains NPSS/NSSS/NPBCH/SIB1-NB/NRS only
ngen = NBIoTDownlinkWaveformGenerator;
ngen.Config.NPDCCH.Enable = 'Off'; % Disable the NPDCCH
ngen.Config.NPDSCH.Enable = 'Off'; % Disable the NPDSCH

% Display the grid and generate the time-domain signal
figure;
ngen.displayResourceGrid;
waveform2 = ngen.generateWaveform;

% Plot the signal spectrums of the generated two waveforms
release(spectrumScope);
spectrumScope.ShowLegend = true;
spectrumScope.ChannelNames = {'Non-Anchor carrier fully occupied by NPDSCH/NRS (Port 2000)', ...
    'Anchor carrier with NPSS/NSSS/NPBCH/SIB1-NB/NRS only (Port 2000)'};
spectrumScope.SampleRate = ofdmInfo1.SamplingRate;
spectrumScope(waveform1,waveform2);

2-134

 NB-IoT Downlink Waveform Generation

2-135

2 Examples and Demos

2-136

 NB-IoT Downlink Waveform Generation

Selected Bibliography

1

2

3

4

5

6

7

8

3GPP TS 36.211 "Physical channels and modulation"

3GPP TS 36.212 "Multiplexing and channel coding"

3GPP TS 36.213 "Physical layer procedures"

3GPP TS 36.321 "Medium Access Control (MAC); Protocol specification"

3GPP TS 36.331 "Radio Resource Control (RRC); Protocol specification"

3GPP TS 36.300 "Overall description; Stage 2"

3GPP TS 36.101 "User Equipment (UE) radio transmission and reception"

3GPP TS 36.141 "Base Station (BS) conformance testing"

9 O. Liberg, M. Sundberg, Y.-P. Wang, J. Bergman and J. Sachs, Cellular Internet of Things:

Technologies, Standards and Performance, Elsevier, 2018.

10 M. Kanj, V. Savaux and M. Le Guen, "A Tutorial on NB-IoT Physical Layer Design", IEEE

Communications Surveys & Tutorials, vol. 22, no. 4, 2020.

2-137

 NB-IoT NTN NPDSCH Throughput

NB-IoT NTN NPDSCH Throughput

This example demonstrates how to simulate a narrowband Internet of Things (NB-IoT) narrowband
physical downlink shared channel (NPDSCH) throughput in a non-terrestrial network (NTN) channel.
This example supports two narrowband NTN channels: the European Telecommunication Standards
Institute (ETSI) Rician fading channel and the International Telecommunication Union
Radiocommunication Sector (ITU-R) P.681 land mobile-satellite (LMS) channel.

Introduction

This example measures the NPDSCH throughput of an NB-IoT link, as defined by the 3GPP NB-IoT
standards [3], [4], [5], [6], and [7].

The example models these features.

• Transport channel coding

• NPDSCH, narrowband reference signal (NRS), and synchronization signals (narrowband primary

synchronization signal NPSS, narrowband secondary synchronization signal NSSS)

• ETSI Rician channel and ITU-R P.681 LMS channel

• Single-input-single-output (SISO) link

• Doppler pre-compensation at the transmitter, and Doppler compensation at the receiver

• Optional power amplifier modeling

The figure shows the implemented processing chain. For clarity, the figure does not show the NRS
and synchronization signals.

For more information about the NB-IoT NPDSCH transmitter and receiver processing units, see the
“NB-IoT NPDSCH Block Error Rate Simulation” on page 2-329 example.

To reduce the total simulation time, you can use Parallel Computing Toolbox™ to execute the range of
transmit power values of the transmit power loop in parallel.

Configure Simulation Length, Transmitter, and Receiver

Set the length of the simulation in terms of the number of transport blocks. By default, the example
uses 10 transport blocks, but you must use a large number of transport blocks to produce meaningful
throughput results. Set the range of transmit power values to simulate. The transmitter power is
defined as the power of the time-domain waveform before performing Doppler pre-compensation and
includes the gain of the power amplifier. The receiver includes its noise figure and the antenna
temperature. The noise figure models the receiver internal noise, and the antenna temperature
models the input noise. This receiver specifies the noise per antenna element. In this example, you
perform the simulation for different repetition values and compare the performance improvement
with repetitions. The iReps variable is applicable only when NPDSCH does not carry the scheduling
information block SIB1-NB.

numTrBlks = 10;             % Number of simulated transport blocks
iReps = [0 5];              % Range of repetitions simulated

2-157

2 Examples and Demos

txPower = 30:5:45;          % Transmit power (dBm)
rxNoiseFigure = 6;          % Noise figure (dB)
rxAntennaTemperature = 290; % Antenna temperature (K)

Power Amplifier Configuration

To configure a memoryless power amplifier nonlinearity, use enablePA. You can choose one of these
power amplifier models, as defined in Annex A of TR 38.803.

• 2.1 GHz Gallium Arsenide (GaAs)

• 2.1 GHz Gallium Nitride (GaN)

Alternatively, you can set paModel to Custom and use paCharacteristics to define the power
amplifier characteristics in a matrix with three columns. The first column defines the input power in
dBm. The second column defines the output power in dBm. The third column defines the output phase
in degrees. When the paCharacteristics variable is set to empty and the paModel is set to
Custom, this example uses a 2.1 GHz laterally-diffused metal-oxide semiconductor (LDMOS) Doherty-
based amplifier.

The memoryless nonlinearity applied to the waveform follows this equation for power amplifiers
(excluding a custom configuration).

yP n = ∑

ak x n x n 2k

k ∈ Kp

In this equation,

• yP n  is the output signal.
• x n  is the input signal.

• Kp is the set of polynomial degree(s).

• ak is the polynomial coefficient.

By default, the example sets enablePA to false.

enablePA =

;                 % true or false

paModel =
paCharacteristics = [];         % Lookup table as empty or a matrix with columns: Pin (dBm) | Pout (dBm) | Phase (degrees)

; % "2.1GHz GaAs", "2.1GHz GaN", or "Custom"

When you set enablePA to true, use scaleFactor variable to modify the maximum input signal
amplitude to excite the power amplifier nonlinearity. The scaleFactor controls the operating region
of the power amplifier and applies the signal amplitude scaling at each transmit antenna. You can
also use scaleFactor variable to set power backoff. For example, to provide a power backoff of 3dB
to a signal passed through the power amplifier, set scaleFactor to -3. Ensure that the input signal
is within the characterization range of the power amplifier model.

When both scaleFactor and paCharacteristics are set to empty and paModel is set to Custom,
the example uses a default value of -35 dB. In all other cases, when scaleFactor is set to empty, the
example uses a default value of 0 dB.

scaleFactor = []; % Amplitude scaling, in dB

% If enablePA is set to true, visualize the power amplifier gain and phase

2-158

 NB-IoT NTN NPDSCH Throughput

% characteristics
paModelImpl = paModel;
paInputScaleFactor = 0;                                 % in dB
if enablePA == 1
    % Set the power amplifier as applicable for the further processing
    if lower(paModel) == "custom"
        if isempty(paCharacteristics)
            tableLookup = getDefaultCustomPA;
            paInputScaleFactor = -35;
        else
            tableLookup = paCharacteristics;
        end
        % Use table look-up option of comm.MemorylessNonlinearity and provide
        % the power amplifier characteristics
        mnl = comm.MemorylessNonlinearity(Method="Lookup table", ...
            Table=tableLookup);
        plot(mnl)
        paModelImpl = mnl;
    else
        paMemorylessNonlinearity(paModel)
    end
end
% Update the power amplifier input scaling factor, based on scaleFactor
if ~isempty(scaleFactor)
    paInputScaleFactor = scaleFactor;
end

Doppler Compensation Configuration

The example supports two Doppler compensation configurations: one at the transmitter end and the
other at the receiver end. For compensation at the transmitter end, enable txDopplerCompensator.
Setting the txDopplerCompensator variable to true pre-compensates the transmitted waveform
for Doppler caused by the satellite movement. This example assumes that the Doppler effect due to
satellite movement is known when performing Doppler pre-compensation. To compensate at the
receiver end, enable rxDopplerCompensator. By setting the rxDopplerCompensator variable to
true, the receiver performs Doppler compensation using the NPSS. It is important to note that
Doppler estimates may be inaccurate at the receiver if the transmit power is low, resulting in an
operating signal-to-noise ratio below -10 dB.

txDopplerCompensator =

; % true or false

rxDopplerCompensator =

; % true or false

Set Up Higher Layer Parameters

To configure the eNodeB and NPDSCH parameters, set these higher layer parameters.

npdschDataType =
iSF = 0;                               % Resource assignment field in DCI (DCI format N1 or N2)
schedulingInfoSIB1 = 0;                % Scheduling information field in MasterInformationBlock-NB (MIB-NB)
iMCS = 4;                              % Modulation and coding scheme field in DCI (DCI format N1 or N2)

; % "SIB1NB", "BCCHNotSIB1NB", or "NotBCCH"

eNodeB and NPDSCH Configuration

Set these eNodeB parameters.

2-159

2 Examples and Demos

• NB-IoT physical layer cell identity

• Operation mode

enb = struct;
enb.NNCellID = 0;                         % NB-IoT physical layer cell identity

enb.OperationMode =

; % "Standalone", "Guardband", "Inband-SamePCI", or "Inband-DifferentPCI"

Set the radio network temporary identifier in the NPDSCH structure.

npdsch = struct;
npdsch.RNTI = 1; % Radio network temporary identifier

Propagation Channel Model Configuration

Create a channel model object for the simulation. The example supports the ETSI Rician channel and
ITU-R P.681 LMS channel. To obtain the NTN channel from these channels, apply an additional
Doppler shift. Use this equation to calculate the Doppler shift due to satellite movement, as specified
in TR 38.811.

f d, sat =

νsat
c

*

R

R + h cos αmodel * f c

In this equation,

• νsat is the satellite speed.

• c is the speed of light.

• R is the Earth radius.

• h is the satellite altitude.

• αmodel is the satellite elevation angle.

• f c is the carrier frequency.

By default, this example considers a satellite in low Earth orbit at an altitude of 600 km, with a
carrier frequency of 2 GHz. The NB-IoT user equipment (UE) is moving at a speed of 3 km/h. Also,
this example assumes that satellites move in circular orbits.

channel = struct;

channel.NTNChannelType =
channel.CarrierFrequency = 2e9;                % Carrier frequency (in Hz)
channel.ElevationAngle = 50;                   % Elevation angle (in degrees)
channel.MobileSpeed = 3*1000/3600;             % UE speed (in m/s)
channel.MobileAltitude = 0;                    % Mobile altitude (in m)
channel.SatelliteAltitude = 600e3;             % Satellite altitude (in m)
channel.Seed = 73;                             % Random seed

; % "ETSI Rician" or "ITU-R P.681"

channel.IncludeFreeSpacePathLoss =

;        % Include or exclude free space path loss

% Set these fields based on the type of channel selected
if lower(channel.NTNChannelType) == "etsi rician"
    % For ETSI Rician channel, set KFactor
    channel.KFactor = 10;           % In dB
else
    % For ITU-R P.681, set Environment and AzimuthOrientation

2-160

 NB-IoT NTN NPDSCH Throughput

    channel.Environment = "Urban";  % "Urban", "Suburban", "RuralWooded", or "Residential"
    channel.AzimuthOrientation = 0; % In degrees
end

Channel Estimator Configuration

Configure a practical channel estimator by using the cec structure. By default, this example
configures the channel with these specifications.

• Carrier frequency — 2 GHz

• Speed of NB-IoT UE — 3 km/h

This configuration results in a Doppler spread of 5.5 Hz. Therefore, perform frequency averaging
over pilot estimates with these settings.

• Time window — 1 resource element (RE)

• Frequency window — 25 REs, to ensure averaging over all subcarriers for the resource block

% Configure channel estimator
cec.PilotAverage = "UserDefined";   % Type of pilot symbol averaging
cec.TimeWindow = 1;                 % Time window size in REs
cec.FreqWindow = 25;                % Frequency window size in REs
cec.InterpType = "Cubic";           % 2-D interpolation type
cec.InterpWindow = "Centered";      % Interpolation window type
cec.InterpWinSize = 3;              % Interpolation window size
cec.Reference = "NRS";              % Channel estimator reference signal

Processing Loop

To determine the throughput at each repetition index and transmit power index, follow these steps.

1 Generate the transport block — Get the transport block size depending on the configured

higher layer parameters.

2 Generate the resource grid — Map the modulated bits, along with the NPSS, NSSS, and NRS,
signals to the resource grid. The lteNDLSCH function performs transport channel coding on the
input transport block. The lteNPDSCH function then modulates the encoded data bits.

3 Generate the waveform — Generate the NB-IoT time-domain OFDM waveform with half

subcarrier shift using the lteSCFDMAModulate function.

4

5

Apply power amplifier nonlinearities — Apply the memoryless nonlinearities to the baseband
OFDM signal.

Apply Doppler pre-compensation — Apply the Doppler shift due to satellite movement to the
generated waveform to pre-compensate the channel-induced satellite Doppler shift.

6 Model and apply a noisy channel — Pass the generated waveform through an ETSI Rician or
ITU-R P.681 LMS fading channel to get the faded waveform. Apply path loss and add thermal
noise to the faded waveform.

7

8

9

Apply Doppler compensation — Estimate the Doppler shift in the received waveform, and
compensate the Doppler shift.

Perform synchronization and OFDM demodulation — Perform timing synchronization by
correlating the received waveform with the NPSS. The lteSCFDMADemodulate function then
demodulates the synchronized signal.

Perform channel estimation — Estimate the channel using NRS.

2-161

2 Examples and Demos

10 Decode the NPDSCH — Decode the NPDSCH, with the estimated channel and noise variance,

by using the lteNPDSCHDecode function.

11 Decode the transport block — Decode the soft bits using the lteNDLSCHDecode function. The
function decodes the codeword data and returns the block cyclic redundancy check (CRC) error.

% Use the higher layer parameters, and check if the provided configuration
% is valid
numRep = numel(iReps);
npdschInfo = hNPDSCHInfo;
npdschInfo.NPDSCHDataType = npdschDataType;
npdschInfo.ISF = iSF;
npdschDataTypeLower = lower(npdschDataType);
if npdschDataTypeLower == "sib1nb"  % NPDSCH carrying SIB1-NB
    npdschInfo.SchedulingInfoSIB1 = schedulingInfoSIB1;
    % Store a copy of the information structure for all the repetitions
    npdschInfo = repmat(npdschInfo,numRep,1);
else % NPDSCH not carrying SIB1-NB
    npdschInfo.IMCS = iMCS;              % Modulation and coding scheme field in DCI (DCI format N1 or N2)
    % Store a copy of the information structure for all the repetitions
    npdschInfo = repmat(npdschInfo,numRep,1);
    for repIdx = 1:numRep
        npdschInfo(repIdx).IRep = iReps(repIdx); % Repetition number field in DCI (DCI format N1 or N2)
    end
end

% Initialize some parameters of enb
enb.NFrame = 0;
enb.NSubframe = 0;
enb.NBRefP = 1;
opMode = lower(enb.OperationMode);
inbandSamePCI = (opMode == "inband-samepci");
inbandDifferentPCI = (opMode == "inband-differentpci");
if inbandSamePCI
    enb.CellRefP = enb.NBRefP;     % Number of cell RS antenna ports (Fixed to 1 in this example)
    enb.NCellID = enb.NNCellID;
elseif inbandDifferentPCI
    enb.CellRefP = enb.NBRefP;     % Number of cell RS antenna ports (Fixed to 1 in this example)
    enb.NCellID = 1;
end
if ((npdschDataTypeLower == "bccnnotsib1nb") || (npdschDataType == "notbcch")) && ...
        (inbandSamePCI || inbandDifferentPCI)
    enb.ControlRegionSize = 3;     % The allowed values are 0...13
end

% Apply default window size according to TS 36.104 Table E.5.1-1a
if(~isfield(enb,"Windowing"))
    enb.Windowing = 6;
end

% Store enb structure with a name used for OFDM modulation and
% demodulation. The NB-IoT downlink waveform is a 1/2 subcarrier shift
% waveform. The lteSCFDMAModulate and lteSCFDMADemodulate functions use the
% NBULSubcarrierSpacing field to modulate and demodulate the NB-IoT
% downlink waveform, respectively.
enbOFDM = enb;
enbOFDM.NBULSubcarrierSpacing = "15kHz";

2-162

 NB-IoT NTN NPDSCH Throughput

% Get the waveform information and set up the NTN channel
waveformInfo = lteSCFDMAInfo(enbOFDM);
ntnChannel = setupNTNChannel(channel,waveformInfo.SamplingRate);

% Compute the noise amplitude per receive antenna
kBoltz = physconst('Boltzmann');
NF = 10^(rxNoiseFigure/10);
T0 = 290;                                               % Noise temperature at the input (K)
Teq = rxAntennaTemperature + T0*(NF-1);                 % K
N0_ampl = sqrt(kBoltz*waveformInfo.SamplingRate*Teq/2.0);

% Compute path loss based on the elevation angle and satellite altitude
c = physconst("lightspeed");
d = slantRangeCircularOrbit( ...
    channel.ElevationAngle,channel.SatelliteAltitude,channel.MobileAltitude);
lambda = c/channel.CarrierFrequency;
pathLoss = fspl(d,lambda)*double(channel.IncludeFreeSpacePathLoss); % in dB

% Initialize throughput result
numTxPow = numel(txPower);
throughputPercent = zeros(numTxPow,numRep);

% Absolute subframe number at the starting point of the simulation
NSubframe = enb.NFrame*10+enb.NSubframe;

% Loop over repetitions
repVal = zeros(numRep,1);
for repIdx = 1:numRep
    % Add these fields to the npdsch structure
    npdsch.NSF = npdschInfo(repIdx).NSF;
    npdsch.NRep = npdschInfo(repIdx).NRep;
    npdsch.NPDSCHDataType = npdschDataType;
    repVal(repIdx) = npdsch.NRep;

    % Get the bit capacity and transport block length
    [~,info] = lteNPDSCHIndices(enb,npdsch);
    rmoutlen = info.G;                 % Bit length after rate matching (codeword length)
    trblklen = npdschInfo(repIdx).TBS; % Transport block size

    % The temporary variables 'enb_init', 'enbOFDM_init', and
    % 'channel_init' create the temporary variables 'enb', 'enbOFDM', and
    % 'ntnChannel' within the transmit power loop to create independent
    % simulation loops for the 'parfor' loop
    enb_init = enb;
    enbOFDM_init = enbOFDM;
    channel_init = ntnChannel;

    for txPowIdx = 1:numTxPow
    % parfor txPowIdx = 1:numTxPow
    % To enable the use of parallel computing for increased the speed,
    % comment out the 'for' statement and uncomment the 'parfor' statement.
    % This functionality requires the Parallel Computing Toolbox. If you do
    % not have Parallel Computing Toolbox, 'parfor' defaults to the normal
    % 'for' statement.

        % Reset the random number generator so that each transmit power
        % point experiences the same noise realization
        rng(0,"threefry");

2-163

2 Examples and Demos

        enb = enb_init;                        % Initialize eNodeB configuration
        enbOFDM = enbOFDM_init;                % Initialize eNodeB configuration related to OFDM waveform
        ntnChannel = channel_init;             % Initialize fading channel configuration
        txcw = [];                             % Initialize the transmitted codeword
        numBlkErrors = 0;                      % Number of transport blocks with errors
        estate = [];                           % Initialize NPDSCH encoder state
        dstate = [];                           % Initialize NPDSCH decoder state
        lastOffset = 0;                        % Initialize overall frame timing offset
        offset = 0;                            % Initialize frame timing offset
        subframeGrid = lteNBResourceGrid(enb); % Initialize the subframe grid
        foffsetRS = 0;                         % Initialize frequency offset using reference signal

        N0 = N0_ampl;
        pl_dB = pathLoss;
        subframeIdx = NSubframe;
        numRxTrBlks = 0;
        reset(ntnChannel.BaseChannel);
        reset(ntnChannel.ChannelFilter);
        while (numRxTrBlks < numTrBlks)

            % Set current subframe and frame numbers
            enb.NSubframe = mod(subframeIdx,10);
            enb.NFrame = floor((subframeIdx)/10);

            % Generate the NPSS symbols and indices
            npssSymbols = lteNPSS(enb);
            npssIndices = lteNPSSIndices(enb);
            % Map the symbols to the subframe grid
            subframeGrid(npssIndices) = npssSymbols;

            % Generate the NSSS symbols and indices
            nsssSymbols = lteNSSS(enb);
            nsssIndices = lteNSSSIndices(enb);
            % Map the symbols to the subframe grid
            subframeGrid(nsssIndices) = nsssSymbols;

            % Establish if either NPSS or NSSS is transmitted, and if so,
            % do not transmit NPDSCH in this subframe
            isDataSubframe = isempty(npssSymbols) && isempty(nsssSymbols);

            % Create a new transport block, and encode it when the
            % transmitted codeword is empty. The receiver sets the codeword
            % to empty to signal that all subframes in a bundle have been
            % received (it is also empty before the first transmission)
            if isempty(txcw)
                txTrBlk = randi([0 1],trblklen,1);
                txcw = lteNDLSCH(rmoutlen,txTrBlk);
            end

            if (isDataSubframe)
                % Generate NPDSCH symbols and indices for a subframe
                [txNpdschSymbols,estate] = lteNPDSCH(enb,npdsch,txcw,estate);
                npdschIndices = lteNPDSCHIndices(enb,npdsch);
                % Map the symbols to the subframe grid
                subframeGrid(npdschIndices) = txNpdschSymbols;
                % Generate the NRS symbols and indices
                nrsSymbols = lteNRS(enb);

2-164

 NB-IoT NTN NPDSCH Throughput

                nrsIndices = lteNRSIndices(enb);
                % Map the symbols to the subframe grid
                subframeGrid(nrsIndices) = nrsSymbols;
            end

            % Perform OFDM modulation to generate the time domain waveform.
            % Use NB-IoT SC-FDMA to get the 1/2 subcarrier shift on the
            % OFDM modulation.
            txWaveform = lteSCFDMAModulate(enbOFDM,subframeGrid);

            % Normalize the waveform with maximum waveform amplitude
            txWaveform0 = txWaveform./max(abs(txWaveform));

            % Apply power amplifier nonlinearities
            txWaveform1 = paMemorylessNonlinearity(paModelImpl,txWaveform0,...
                db2mag(paInputScaleFactor),enablePA);

            % Scale the waveform power based on the input transmit power
            wavePower = 10*log10(sum(var(txWaveform1)));
            powerScaling = (txPower(txPowIdx)-30)-wavePower;      % In dB
            txWaveform1 = db2mag(powerScaling)*txWaveform1;

            % Pad waveform with 25 samples. This covers the range of
            % delays expected from channel modeling (a combination of
            % implementation delay and channel delay spread)
            txWaveform1 = [txWaveform1; zeros(25,enb.NBRefP)]; %#ok<AGROW>

            % Apply Doppler pre-compensation
            txWaveform2 = compensateDopplerShift(enbOFDM,txWaveform1, ...
                ntnChannel.SatelliteDopplerShift,txDopplerCompensator);

            % Pass data through channel model
            rxWaveform = generateNTNChannel(ntnChannel,txWaveform2);

            % Apply path loss to the signal
            rxWaveform = rxWaveform*db2mag(-pl_dB);

            % Add thermal noise to the received time-domain waveform. Multiply
            % the noise variance with 2 as wgn function performs the scaling
            % within.
            noise = wgn(size(rxWaveform,1),size(rxWaveform,2),2*(N0^2),1,"linear","complex");
            rxWaveform = rxWaveform + noise;

            % Perform receiver Doppler compensation using reference signals
            if (enb.NSubframe == 5)
                % Use NPSS signal for estimating Doppler
                refInd = npssIndices;
                refSym = npssSymbols;
                foffsetRS = estimateDopplerShiftUsingRS(enbOFDM,rxWaveform,refInd, ...
                    refSym,rxDopplerCompensator);
            end
            rxWaveform1 = compensateDopplerShift(enbOFDM,rxWaveform,foffsetRS, ...
                rxDopplerCompensator);

            % In this example, the subframe offset calculation relies
            % on NPSS present in subframe 5, so we need to pad the
            % subframes before it so that the frame offset returned by
            % lteNBDLFrameOffset is the offset for subframe 5

2-165

2 Examples and Demos

            sfTsamples = waveformInfo.SamplingRate*1e-3;
            if (enb.NSubframe==5)
                padding = zeros([sfTsamples*5,size(rxWaveform1,2)]);
                offset = lteNBDLFrameOffset(enb,[padding; rxWaveform1]);
                if (offset > 25) || (offset < 0)
                    offset = lastOffset;
                end
                lastOffset = offset;
            end

            % Synchronize the received waveform
            rxWaveform1 = rxWaveform1(1+offset:end,:);

            % Perform OFDM demodulation on the received data to recreate
            % the resource grid. Use NB-IoT SC-FDMA to get the 1/2
            % subcarrier shift on the OFDM demodulation.
            rxSubframe = lteSCFDMADemodulate(enbOFDM,rxWaveform1,0.55);

            % Channel estimation
            [estChannelGrid,noiseEst] = lteDLChannelEstimate( ...
                enb,cec,rxSubframe);

            % Data decoding
            if (isDataSubframe)
                % Get NPDSCH indices
                npdschIndices = lteNPDSCHIndices(enb,npdsch);

                % Get PDSCH resource elements from the received subframe.
                % Scale the received subframe by the PDSCH power factor
                % Rho. The PDSCH is scaled by this amount, while the
                % reference symbols used for channel estimation (used in
                % the PDSCH decoding stage) are not.
                [rxNpdschSymbols,npdschHest] = lteExtractResources(npdschIndices, ...
                    rxSubframe,estChannelGrid);

                % Decode NPDSCH
                [rxcw,dstate,symbols] = lteNPDSCHDecode( ...
                                     enb,npdsch,rxNpdschSymbols,npdschHest,noiseEst,dstate);

                % Decode the transport block when all the subframes in a bundle
                % have been received
                if dstate.EndOfTx
                   [trblkout,blkerr] = lteNDLSCHDecode(trblklen,rxcw);
                   numBlkErrors = numBlkErrors + blkerr;
                   numRxTrBlks = numRxTrBlks + 1;
                   % Re-initialize to enable the transmission of a new transport block
                   txcw = [];
                end
            end

            subframeIdx = subframeIdx + 1;

        end

        % Calculate the throughput percentage
        throughputPercent(txPowIdx,repIdx) = 100*(1-(numBlkErrors/numTrBlks));
        fprintf("Throughput(%%) for %d transport block(s) at transmit power %d dBm with %d repetition(s): %.4f \n", ...
            numTrBlks,txPower(txPowIdx),npdsch.NRep,throughputPercent(txPowIdx,repIdx))

2-166

 NB-IoT NTN NPDSCH Throughput

    end

end

Throughput(%) for 10 transport block(s) at transmit power 30 dBm with 1 repetition(s): 0.0000
Throughput(%) for 10 transport block(s) at transmit power 35 dBm with 1 repetition(s): 0.0000
Throughput(%) for 10 transport block(s) at transmit power 40 dBm with 1 repetition(s): 80.0000
Throughput(%) for 10 transport block(s) at transmit power 45 dBm with 1 repetition(s): 100.0000
Throughput(%) for 10 transport block(s) at transmit power 30 dBm with 32 repetition(s): 40.0000
Throughput(%) for 10 transport block(s) at transmit power 35 dBm with 32 repetition(s): 100.0000
Throughput(%) for 10 transport block(s) at transmit power 40 dBm with 32 repetition(s): 100.0000
Throughput(%) for 10 transport block(s) at transmit power 45 dBm with 32 repetition(s): 100.0000

Results

Display the measured throughput, which is the percentage of the maximum possible throughput of
the link given the available resources for data transmission.

% Set figure title
if npdschDataType == "SIB1NB"
    npdsch.NSF = 8;
end
figure; grid on; hold on;
legendstr = repmat("",numRep,1);
for repIdx = 1:numRep
    plot(txPower,throughputPercent(:,repIdx),"-o")
    legendstr(repIdx) = "NRep = " + repVal(repIdx);
end
hold off;xlabel('Input Transmit Power (dBm)'); ylabel('Throughput (%)');
title(npdsch.NPDSCHDataType + ": TBS=" + trblklen + ...
    "; NSF=" + npdsch.NSF + "; " + enb_init.NBRefP + " NRS port")
legend(legendstr,Location="southeast")

2-167

2 Examples and Demos

This example figure shows the throughput results obtained by simulating 1000 transport blocks
(numTrBlks = 1000, txPower = 30:45) for repetition indices 0 and 5. The simulation setup
includes the default higher layer, eNodeB, and NPDSCH configuration with an ETSI Rician channel.
To obtain the lines corresponding to the Tx Doppler Comp., you can set txDopplerCompensator
to true and rxDopplerCompensator to false. For the lines corresponding to the Rx Doppler
Comp., you can set txDopplerCompensator to false and rxDopplerCompensator to true.

Further Exploration

This example shows the throughput simulation for NB-IoT NPDSCH in an NTN channel. In addition to
the default behavior, you can run the example for these cases.

• Analyze the throughput at each transmit power value and repetition index for a different satellite

orbit by varying the satellite altitude and satellite speed.

• Observe the link performance without any Doppler compensation techniques by setting the

txDopplerCompensator and rxDopplerCompensator variables to false.

• Observe the link performance with only Doppler compensation at only the receiver by setting

txDopplerCompensator to false and rxDopplerCompensator to true.

2-168

 NB-IoT NTN NPDSCH Throughput

• Check the throughput performance for different repetitions by changing the iReps value.

• Compare the throughput performance in an NTN and terrestrial network by using the

lteFadingChannel channel as shown in “NB-IoT NPDSCH Block Error Rate Simulation” on page
2-329 example.

Supporting Files

This example uses this helper function.

• hNPDSCHInfo.m — NB-IoT NPDSCH information

References

1

2

3

4

5

6

7

8

9

ETSI TS 101 376-5-5 V1.3.1 (2005-02). GEO-Mobile Radio Interface Specifications (Release 1);
Part 5: Radio interface physical layer specifications; Sub-part 5: Radio Transmission and
Reception; GMR-1 05.005.

ITU-R Recommendation P.681-11 (08/2019). “Propagation data required for the design systems in
the land mobile-satellite service.” P Series; Radio-wave propagation.

3GPP TS 36.211, "Physical channels and modulation", 3rd Generation Partnership Project;
Technical Specification Group Radio Access Network; Evolved Universal Terrestrial Radio Access
(E-UTRA).

3GPP TS 36.213, "Physical layer procedures", 3rd Generation Partnership Project; Technical
Specification Group Radio Access Network; Evolved Universal Terrestrial Radio Access (E-
UTRA).

3GPP TS 36.321, "Medium Access Control (MAC) protocol specification", 3rd Generation
Partnership Project; Technical Specification Group Radio Access Network; Evolved Universal
Terrestrial Radio Access (E-UTRA).

3GPP TS 36.101, "User Equipment (UE) radio transmission and reception", 3rd Generation
Partnership Project; Technical Specification Group Radio Access Network; Evolved Universal
Terrestrial Radio Access (E-UTRA).

3GPP TS 36.104, "Base Station (BS) radio transmission and reception", 3rd Generation
Partnership Project; Technical Specification Group Radio Access Network; Evolved Universal
Terrestrial Radio Access (E-UTRA).

3GPP TR 36.763, "Study on Narrow-Band Internet of Things (NB-IoT) / enhanced Machine Type
Communication (eMTC) support for Non-Terrestrial Networks (NTN) (Release 17), 3rd
Generation Partnership Project; Technical Specification Group Radio Access Network.

3GPP TR 38.803, "Study on new radio access technology: Radio Frequency (RF) and co-existence
aspects (Release 14)", 3rd Generation Partnership Project; Technical Specification Group Radio
Access Network.

10 3GPP TR 38.811, "Study on New Radio (NR) to support non-terrestrial networks (Release 15)",
3rd Generation Partnership Project; Technical Specification Group Radio Access Network.

11 O. Hammi, S. Carichner, B. Vassilakis, and F.M. Ghannouchi. “Power Amplifiers’ Model

Assessment and Memory Effects Intensity Quantification Using Memoryless Post-Compensation
Technique.” IEEE Transactions on Microwave Theory and Techniques 56, no. 12 (December
2008): 3170–79.

Local Functions

This example uses these local functions.

2-169

2 Examples and Demos

function chanOut = setupNTNChannel(channel,sampleRate)
% Setup NTN channel

    % Assign temporary variables for carrier frequency and maximum Doppler
    % shift due to mobile movement
    fc = double(channel.CarrierFrequency);
    c = physconst("LightSpeed");
    maxDoppler = (double(channel.MobileSpeed)*fc)/c;
    elevAngle = double(channel.ElevationAngle);
    h = double(channel.SatelliteAltitude);
    % Calculate the Doppler shift due to satellite movement
    maxDopplerSat = dopplerShiftCircularOrbit(elevAngle,h,channel.MobileAltitude,fc);
    % Check the maximum Doppler shift and sample rate
    if ((maxDoppler+maxDopplerSat) >= (sampleRate/10))
        error("satcom:setupNTNChannel:MaxDoppler", ...
            "The maximum Doppler shift (%d Hz) due to mobile and satellite " + ...
            "movement, must be less than %d Hz which is one-tenth of SampleRate.", ...
            (maxDoppler + maxDopplerSat),sampleRate/10)
    end

    chanOut = struct;
    chanTypeLower = lower(channel.NTNChannelType);
    if chanTypeLower == "etsi rician"
        channelName = "ETSI Rician";
        baseChannel = etsiRicianChannel;
        baseChannel.SampleRate = sampleRate;
        baseChannel.KFactor = channel.KFactor;
        baseChannel.MaximumDopplerShift = maxDoppler;
    elseif chanTypeLower == "itu-r p.681"
        channelName = "ITU-R P.681";
        baseChannel = p681LMSChannel;
        baseChannel.SampleRate = sampleRate;
        baseChannel.Environment = channel.Environment;
        baseChannel.CarrierFrequency = channel.CarrierFrequency;
        baseChannel.MobileSpeed = channel.MobileSpeed;
        baseChannel.ElevationAngle = channel.ElevationAngle;
        baseChannel.AzimuthOrientation = channel.AzimuthOrientation;
        baseChannel.FadingTechnique = "Sum of sinusoids";
        baseChannel.SatelliteDopplerShift = maxDopplerSat;
    end
    baseChannel.RandomStream = "mt19937ar with seed";
    baseChannel.Seed = channel.Seed;

    % Set the channel filter
    chanFilt = comm.ChannelFilter( ...
                SampleRate=sampleRate,PathDelays=0, ...
                NormalizeChannelOutputs=false);

    % Set the output structure
    chanOut.ChannelName = channelName;
    chanOut.CarrierFrequency = fc;
    chanOut.SatelliteAltitude = h;
    chanOut.ElevationAngle = elevAngle;
    chanOut.BaseChannel = baseChannel;
    chanOut.SatelliteDopplerShift = maxDopplerSat;
    chanOut.ChannelFilter = chanFilt;

end

2-170

 NB-IoT NTN NPDSCH Throughput

function [out,sampleTimes] = generateNTNChannel(channel,in)
% Generate NTN channel

    if isprop(channel.BaseChannel,'SatelliteDopplerShift')
        [out,~,sampleTimes] = channel.BaseChannel(in);
    else
        % Get the channel information before channel processing
        prevInfo = info(channel.BaseChannel);
        numSamplesStart = prevInfo.NumSamplesProcessed;

        % Get the path gains of base channel
        [~,pathGainsBase] = channel.BaseChannel(in);

        % Get the channel information after channel processing
        postInfo = info(channel.BaseChannel);
        numSamplesEnd = postInfo.NumSamplesProcessed;

        % Get the channel sample times
        sampleTimes = (numSamplesStart:(numSamplesEnd-1)).'/channel.BaseChannel.SampleRate;

        % Apply satellite Doppler shift to the base channel path gains
        pathGains = pathGainsBase.*exp(1i*2*pi*channel.SatelliteDopplerShift*sampleTimes);

        % Perform channel filtering
        out = channel.ChannelFilter(in,pathGains);
    end

end

function out = compensateDopplerShift(enb,inWave,foffset,flag)
% Perform Doppler shift correction

    if flag
        % Correct frequency offset
        out = lteFrequencyCorrect(enb,inWave,foffset);
    else
        out = inWave;
    end

end

function out = estimateDopplerShiftUsingRS(enb,rxWave,refInd, ...
    refSym,flag)
% Estimate the Doppler shift using NPSS

    if flag
        % Set the Windowing field to 0, as this information is not known at
        % the receiver
        enb.Windowing = 0;
        ofdmInfo = lteSCFDMAInfo(enb);
        K = 12;                             % Number of subcarriers
        L = 14;                             % Number of OFDM symbols in slot

        % Initialize temporary variables
        rxWave1 = [rxWave; zeros((mod(size(rxWave,1),2)),1)]; % Append zero, if required
        rxLen = size(rxWave1,1);

2-171

2 Examples and Demos

        % Generate reference waveform
        refGrid = complex(zeros([K L]));
        refGrid(refInd) = refSym;
        refWave = lteSCFDMAModulate(enb,refGrid);
        refWave = [refWave; zeros((rxLen-size(refWave,1)),1)];

        % Compute the correlation of received waveform with reference
        % waveform
        x_wave = rxWave1.*conj(refWave);

        % Compute FFT of the resultant waveform
        x_fft = fftshift(fft(x_wave));

        % FFT bin values
        fftBinValues = (-rxLen/2:(rxLen/2-1))*(ofdmInfo.SamplingRate/rxLen);

        % Use the FFT bin index corresponding to the maximum FFT value.
        % The FFT bin value corresponding to this bin index is the integer
        % frequency offset.
        [~,binIndex] = max(x_fft);
        out = fftBinValues(binIndex);
    else
        out = 0;
    end

end

function varargout = paMemorylessNonlinearity(paModel,varargin)
% Apply power amplifier nonlinearity (TR 38.803)
% out = paMemorylessNonlinearity(paModel,in,enable) returns the
% impaired output.
% paMemorylessNonlinearity(paModel) returns the plot with the gain and
% phase characteristics of the power amplifier

    if nargin == 1
        in_NoScale = randn(1e6,1,'like',1i);
        scaleFactor = 1/sqrt(2);
        enable = 1;
    else
        in_NoScale = varargin{1};
        scaleFactor = varargin{2};
        enable = varargin{3};
    end

    if enable
        in = scaleFactor*in_NoScale;
        if isa(paModel,"comm.MemorylessNonlinearity")
            % paModel is a comm.MemorylessNonlinearity System object
            out = paModel(in);
            paModelName = "";
        else
            absIn = abs(in);
            paModelName = paModel;
            switch lower(paModel)
                case "2.1ghz gaas"
                    % 2.1GHz GaAs
                    out = (-0.618347-0.785905i) * in + (2.0831-1.69506i) * in .* absIn.^(2) + ...
                        (-14.7229+16.8335i) * in .* absIn.^(2*2) + (61.6423-76.9171i) * in .* absIn.^(2*3) + ...

2-172

 NB-IoT NTN NPDSCH Throughput

                        (-145.139+184.765i) * in .* absIn.^(2*4) + (190.61-239.371i)* in .* absIn.^(2*5) + ...
                        (-130.184+158.957i) * in .* absIn.^(2*6) + (36.0047-42.5192i) * in .* absIn.^(2*7);
                otherwise
                    % 2.1GHz GaN
                    out = (0.999952-0.00981788i) * in + (-0.0618171+0.118845i) * in .* absIn.^(2) + ...
                        (-1.69917-0.464933i) * in .* absIn.^(2*2) + (3.27962+0.829737i) * in .* absIn.^(2*3) + ...
                        (-1.80821-0.454331i) * in .* absIn.^(2*4);
            end
        end
    else
        out = in_NoScale;
    end

    if nargout > 0
        varargout{1} = out;
    end

    if nargin == 1 || (nargout == 0)
        % Gain Plot
        inpPower = 20*log10(absIn);
        gain = 20*log10(abs(out))-inpPower;
        figure
        subplot(211)
        plot(inpPower,gain,".")
        grid on
        ylim([-Inf 1])
        xlim([-30 0])
        xlabel("Normalized input power (dB)")
        ylabel("Gain (dB)")
        title("Gain Characteristics of PA Model " + paModelName)

        % Phase Plot
        phase = angle(out.*conj(in))*180/pi;
        subplot(212)
        plot(inpPower,phase,".")
        grid on
        xlim([-30 0])
        xlabel("Normalized input power (dB)")
        ylabel("Phase (deg)")
        title("Phase Characteristics of PA Model " + paModelName)
    end

end

function paChar = getDefaultCustomPA()
% The operating specifications for the LDMOS-based Doherty amplifier are:
% * A frequency of 2110 MHz
% * A peak power of 300 W
% * A small signal gain of 61 dB
% Each row in HAV08_Table specifies Pin (dBm), gain (dB), and phase shift
% (degrees) as derived from figure 4 of Hammi, Oualid, et al. "Power
% amplifiers' model assessment and memory effects intensity quantification
% using memoryless post-compensation technique." IEEE Transactions on
% Microwave Theory and Techniques 56.12 (2008): 3170-3179.

    HAV08_Table = ...
        [-35,60.53,0.01;
        -34,60.53,0.01;

2-173

2 Examples and Demos

        -33,60.53,0.08;
        -32,60.54,0.08;
        -31,60.55,0.1;
        -30,60.56,0.08;
        -29,60.57,0.14;
        -28,60.59,0.19;
        -27,60.6,0.23;
        -26,60.64,0.21;
        -25,60.69,0.28;
        -24,60.76,0.21;
        -23,60.85,0.12;
        -22,60.97,0.08;
        -21,61.12,-0.13;
        -20,61.31,-0.44;
        -19,61.52,-0.94;
        -18,61.76,-1.59;
        -17,62.01,-2.73;
        -16,62.25,-4.31;
        -15,62.47,-6.85;
        -14,62.56,-9.82;
        -13,62.47,-12.29;
        -12,62.31,-13.82;
        -11,62.2,-15.03;
        -10,62.15,-16.27;
        -9,62,-18.05;
        -8,61.53,-20.21;
        -7,60.93,-23.38;
        -6,60.2,-26.64;
        -5,59.38,-28.75];
    % Convert the second column of the HAV08_Table from gain to Pout for
    % use by the memoryless nonlinearity System object.
    paChar = HAV08_Table;
    paChar(:,2) = paChar(:,1) + paChar(:,2);

end

2-174

2 Examples and Demos

NB-IoT Uplink Waveform Generation

This example shows how to generate LTE-Advanced Pro Narrowband IoT (NB-IoT) uplink waveforms
consisting of the Narrowband Physical Uplink Shared Channel (NPUSCH) and the associated
demodulation reference signals for test and measurement applications using LTE Toolbox™. Select
from the NPUSCH reference measurement channels (RMC) for UE transmission testing, defined in TS
36.101 Annex A.2.4 [8 on page 2-313], and the fixed reference channels (FRC) for base station
receiver testing, defined in TS 36.104 Annexes A.14, A.15 and A.16 [9 on page 2-313].

Introduction

3GPP introduced a new air interface, Narrowband IoT (NB-IoT) optimized for low data rate machine
type communications in LTE-Advanced Pro Release 13. NB-IoT provides cost and power efficiency
improvements as it avoids the need for complex signaling overhead required for LTE based systems.

LTE Toolbox can be used to generate standard compliant NB-IoT uplink complex baseband waveforms
representing the 180kHz narrowband carrier suitable for test and measurement applications. LTE
Toolbox supports all the NB-IoT modes of operation described below - standalone, guardband and in-
band.

• Standalone: NB-IoT carrier deployed outside the LTE spectrum, e.g. the spectrum used for GSM or

satellite communications

• Guardband: NB-IoT carrier deployed in the guardband between two LTE carriers

• In-band: NB-IoT carrier deployed in resource blocks of an LTE carrier

The NB-IoT uplink consists of the following physical layer channels and signals:

• Narrowband demodulation reference signal (DM-RS)

• Narrowband physical uplink shared channel (NPUSCH)

• Narrowband physical random access channel (NPRACH)

This example demonstrates the NB-IoT uplink resource element (RE) grid and waveform generation
consisting of the NPUSCH and DM-RS signals. The sections below introduce these physical signals
and channels that form the grid along with key concepts including subframe repetition, logical and
transport channel mappings, and the corresponding grids for the different configurations.

The example outputs the complex baseband waveform along with the populated grid containing the
NPUSCH and DM-RS signals. The waveform can be used for a range of applications from RF testing
to simulation of receiver implementations.

NPUSCH Allocation

This section provides an overall description of how the NPUSCH gets mapped into the NB-IoT uplink
slots.

The NPUSCH can carry the uplink shared channel (UL-SCH) or the uplink control information
according to the two formats:

• NPUSCH format 1, used to carry the uplink shared channel (UL-SCH)

• NPUSCH format 2, used to carry uplink control information

2-304

 NB-IoT Uplink Waveform Generation

The NPUSCH is transmitted on one or more resource units and each of these resource units are
repeated up to 128 times to improve transmission reliability and coverage without compromising on
the low power and low complexity requirements to meet ultra low end IoT use cases.

The smallest mapping unit for the NPUSCH is a resource unit. It is defined as 7 * NULSlots
consecutive SC-FDMA symbols in the time domain and NscRU consecutive subcarriers in the
frequency domain, where NULSlots and NscRU are defined in TS 36.211 Table 10.1.2.3-1 [1 on page
2-313]. The NB-IoT UL-SCH may carry Common Control Channel (CCCH), Dedicated Control Channel
(DCCH) or Dedicated Traffic Channel (DTCH) and maps on to the NPUSCH physical channel (TS
36.300 section 6.1.3.1 and section 5.3.1a [6 on page 2-313]). The NPUSCH can be mapped to one or
more than one resource units, NRU as defined by TS 36.211 Section 10.1.3.6 [1 on page 2-313] and
each resource unit can be transmitted Nrep times.

The examples in the figure show the repetition pattern with NRep = 4. The total duration for
transmitting a block of data is given by NRU * NULSlots * MidenticalNPUSCH as specified in TS
36.211 Section 10.1.3.6 [1 on page 2-313]. For the first case shown below, each transport block is
transmitted over NRU = 2 and each of these NRU contains two UL slots indicated by NULSlots. After
mapping to Nslots, these slots will be repeated MidenticalNPUSCH = 2 (assuming NscRU > 1)
times. In the second case, we assume that NscRU is 1 and hence MidenticalNPUSCH = 1. This,
combined with Nslots = 1 results in the transmission pattern where each block is transmitted
without internal repetitions. In all cases, the scrambling sequence is reset at the start of the
codeword transmission or retransmission (see TS 36.211 Section 10.1.3.1 [1 on page 2-313]). The
detailed specification of the repetition scheme can be found in TS 36.211 10.1.3 [1 on page 2-313].

NB-IoT Uplink Slot Grid

In addition to the slot allocation described above, this section further explains the RE allocation in a
slot. The grid consists of one or more frames containing NPUSCH and corresponding DM-RS.

• DM-RS: The DM-RS is transmitted in every NPUSCH slot with the same bandwidth as the

associated NPUSCH. The reference signals depend on the number of subcarriers NscRU, the
narrowband cell ID NNcellID and the NPUSCH format NPUSCHFormat. The RE positions depend
on the NPUSCH format and subcarrier spacing. For NPUSCH format 1 with subcarrier spacing of
3.75kHz, the DM-RS is transmitted on symbol 4 and with subcarrier spacing of 15kHz, the DM-RS

2-305

2 Examples and Demos

is transmitted on symbol 3. For NPUSCH format 2 with subcarrier spacing of 3.75kHz, the DM-RS
is transmitted on symbols 0,1,2 and with subcarrier spacing of 15kHz, the DM-RS is transmitted
on symbols 2,3 and 4 in the slot.

• NPUSCH: The NPUSCH supports single tone bandwidth in addition to the multitone (12

subcarriers) bandwidth. Single tone transmissions can use either the 15kHz or 3.75kHz subcarrier
spacing whereas the multitone transmissions use the 15kHz subcarrier spacing. This means that
the slot duration for 15kHz mode is 0.5ms and for 3.75kHz the slot duration is 2ms. The
scrambling sequence is initialized in the first slot of the transmission of the codeword. If there are
repetitions enabled, then the scrambling sequence is reinitialized after every MidenticalNPUSCH
transmission of the codeword as described in TS 36.211 Section 10.1.3.1[1 on page 2-313]. The
codewords are BPSK/QPSK modulated on to a single layer and precoded before mapping to one or
more resource units. All the resource elements other than those used for demodulation reference
signals are used for NPUSCH transmission. If higher layer signaling (npusch-AllSymbols as
described in TS 36.211 Section 10.1.3.6 [1 on page 2-313]) indicates the presence of the SRS
symbol, these symbols are counted in the NPUSCH mapping, but not used for the transmission of
the NPUSCH (i.e. these NPUSCH positions are punctured by SRS).

NPUSCH Configuration

In this section, you configure the parameters required for NPUSCH generation. This example
parameterizes a number of 3GPP specified NB-IoT test waveforms for ease of use. These include the
reference measurement channels (RMC) for UE transmission testing, defined in TS 36.101 Annex
A.2.4, and the fixed reference channels (FRC) for base station receiver testing, defined in TS 36.104
Annexes A.14, A.15 and A.16. The NPUSCH channel configuration can be further customized after it
is created.

The UE uses the combination of MCS (modulation and coding scheme) and resource assignment
signaled via the DCI to determine the transport block size from the set defined in TS 36.213 Table
16.5.1.2-2 [3 on page 2-313] to use for NPUSCH transmission. In this example, this is specified via
the parameter tbs and the duration of the generated waveform is controlled via the totNumTrBlks
parameter.

Use the dropdown to select the desired RMC or FRC, and then define the subcarrier offset and
number of repetitions. The resulting NPUSCH channel parameters can be modified afterward to
generated a custom configuration.

% Select a reference test channel for the initial NPUSCH configuration
%
% TS 36.101, User Equipment (UE) radio transmission and reception
% Annex A.2.4 - Reference Measurement Channels for UE Category NB1
%
% TS 36.104, Base Station (BS) radio transmission and reception
% Annex A.14 - Fixed Reference Channels for NB-IoT reference sensitivity (pi/2 BPSK, R=1/3)
% Annex A.15 - Fixed Reference Channels for NB-IoT dynamic range (pi/4 QPSK, R=2/3)
% Annex A.16 - Fixed Reference Channels for NB-IoT PUSCH format 1

rcname =

;

% Additional NPUSCH and NPUSCH DM-RS related parameters
subcarrieroffset = 0;  % Target first subcarrier index of the NPUSCH frequency allocation in the PRB
nrep = 1;              % Override the number of repetitions to use in each NPUSCH transmission
nncellid = 0;          % Narrowband Cell ID
rnti = 0;              % RNTI of the UE
dmrscyclicshift = 0;   % NPUSCH DM-RS cyclic shift, for multi-tone cases

2-306

 NB-IoT Uplink Waveform Generation

duplexmode = 'FDD';    % Duplex mode ('FDD' or 'TDD')
tddconfig = 1;         % TDD configuration (1, 2, 3, 4, or 5 for 15kHz, and 1 or 4 for 3.75kHz)

Use the local function nbiotRMCConfiguation to create structures containing the configured
parameters of the selected RMC or FRC. ue contains general parameters relating to the User
Equipment (UE), and chs contains parameters relating to the NPUSCH transmissions within the
baseband waveform.

[ue,chs,tbs] = nbiotRMCConfiguration(rcname,nrep,subcarrieroffset,nncellid,rnti,dmrscyclicshift,duplexmode,tddconfig);

Set the initial RV offset signaled via DCI.

rvDCI = 0;                                       % RV offset signaled via DCI (See TS 36.213 16.5.1.2)

Set parameters that control the waveform duration.

totNumTrBlks = 1;                                % Number of transport blocks to transmit in the waveform
NSlotsPerBundle = chs.NRU*chs.NULSlots*chs.NRep; % Number of slots in a single codeword bundle
TotNSlots = totNumTrBlks*NSlotsPerBundle;        % Total number of slots required to cover the transport blocks

Specify the NPUSCH and NPUSCH DM-RS power scaling in dB for the plot visualization.

chs.NPUSCHPower = 25;
chs.NPUSCHDMRSPower = 45;

NB-IoT Uplink Waveform Generation

In this section, you create the resource grid populated with the NPUSCH and the corresponding
demodulation reference signals. This grid is then SC-FDMA modulated to generate the time domain
waveform.

% Initialize the random generator to default state
rng('default');

% Get the slot grid and number of slots per frame
emptySlotGrid = lteNBResourceGrid(ue);
slotGridSize = size(emptySlotGrid);
NSlotsPerFrame = 20/(slotGridSize(1)/12);
L = slotGridSize(2);

state = [];                                 % NPUSCH encoder and DM-RS state, auto re-initialization in the function
trblk = [];                                 % Initialize the transport block
txgrid = repmat(emptySlotGrid,1,TotNSlots); % Initialize the output grid

% Display the number of slots being generated
fprintf('\nGenerating %d slots corresponding to %d transport block(s) transmitted on NPUSCH',TotNSlots,totNumTrBlks);

Generating 32 slots corresponding to 1 transport block(s) transmitted on NPUSCH

for slotIdx = chs.SlotIdx+(0:TotNSlots-1)
    % Calculate the frame number and slot number within the frame
    ue.NFrame = fix(slotIdx/NSlotsPerFrame);
    ue.NSlot = mod(slotIdx,NSlotsPerFrame);

    if isempty(trblk)
       if strcmpi(chs.NPUSCHFormat,'Data')
           % UL-SCH encoding is done for the two RV values used for
           % transmitting the codewords. The RV sequence used is determined

2-307

2 Examples and Demos

           % from the rvDCI value signaled in the DCI and alternates
           % between 0 and 2 as given in TS 36.213 Section 16.5.1.2

           % Determine the coded transport block size
           [~, info] = lteNPUSCHIndices(ue,chs);
           outblklen = info.G;

           if outblklen>0
               % Define the transport block which will be encoded to create the
               % codewords for different RV
               trblk = randi([0 1],tbs,1);

               % Create the codewords corresponding to the two RV values used
               % in the first and second block, this will be repeated till all
               % blocks are transmitted
               chs.RV = 2*mod(rvDCI+0,2); % RV for the first block
               cw = lteNULSCH(chs,outblklen,trblk); % CRC and Turbo coding
               chs.RV = 2*mod(rvDCI+1,2); % RV for the second block
               cw = [cw lteNULSCH(chs,outblklen,trblk)]; %#ok<AGROW> % CRC and Turbo coding is repeated
           else
               % If the coded transport block size is zero, there is no
               % transmission in this slot
               cw = zeros(0, 1);
           end
       else
           trblk = randi([0 1],1); % 1 bit ACK
           % For ACK, the same codeword is transmitted in every block as
           % defined in TS 36.212 Section 6.3.3
           cw = lteNULSCH(trblk);
       end
       blockIdx = 0; % First block to be transmitted
       thisCw = getCodewordBlock(cw,blockIdx);
    end

    % Initialize grid
    symsInSlot = (slotIdx-chs.SlotIdx)*L+(1:L);
    slotGrid = txgrid(:,symsInSlot);

    % NPUSCH encoding and mapping onto the slot grid
    txsym = lteNPUSCH(ue,chs,thisCw,state);

    % Map NPUSCH symbols in the grid of a slot
    indicesNPUSCH = lteNPUSCHIndices(ue,chs);
    slotGrid(indicesNPUSCH) = txsym*db2mag(chs.NPUSCHPower);

    % Create DM-RS sequence and map to the slot grid
    [dmrs,state] = lteNPUSCHDRS(ue,chs,state);
    indicesDMRS = lteNPUSCHDRSIndices(ue,chs);
    slotGrid(indicesDMRS) = dmrs*db2mag(chs.NPUSCHDMRSPower);

    % Insert this slot into the slot grid
    txgrid(:,symsInSlot) = slotGrid;

    % If a full block is transmitted, increment the clock counter so that
    % the correct codeword can be selected
    if state.EndOfBlk
        blockIdx = blockIdx + 1;
        thisCw = getCodewordBlock(cw,blockIdx);

2-308

 NB-IoT Uplink Waveform Generation

    end

    % trblk err count and re-initialization
    if state.EndOfTx
       % Re-initialize to enable the transmission of a new transport block
       trblk = [];
    end

end

% Perform SC-FDMA modulation to create time domain baseband waveform
ue.CyclicPrefixUL = 'Normal'; % Normal cyclic prefix length for NB-IoT
[waveform,scfdmaInfo] = lteSCFDMAModulate(ue,chs,txgrid);

Plot Transmitted Grid

Plot the populated grid and observe the NPUSCH and corresponding DM-RS. The positions of the
NPUSCH and DM-RS depends on the number of subcarriers chs.NRUsc and the subcarriers used as
specified by chs.NBULSubcarrierSet. Note that the resource grid plot uses the power levels of the
PUSCH and the DM-RS to assign colors to the resource elements.

% Create an image of overall resource grid
figure
im = image(abs(txgrid));
cmap = parula(64);
colormap(im.Parent,cmap);
axis xy;
title('NB-IoT Uplink Resource Element Grid');
subtitle(sprintf('NRUsc = %d, NRU = %d (SlotsPerRU = %d), NRep = %d',chs.NRUsc,chs.NRU,chs.NULSlots,chs.NRep));
xlabel('OFDM symbols')
ylabel('Subcarriers')
% Create the legend box to indicate the channel/signal types associated with the REs
reNames = {'NPUSCH';'DM-RS'};
clevels = round(db2mag([chs.NPUSCHPower chs.NPUSCHDMRSPower]));
N = numel(reNames);
L = line(ones(N),ones(N), 'LineWidth',8); % Generate lines
% Set the colors according to cmap
set(L,{'color'},mat2cell(cmap( min(1+clevels,length(cmap) ),:),ones(1,N),3));
legend(reNames{:});

2-309

2 Examples and Demos

Local Functions

function [ue,chs,tbs] = nbiotRMCConfiguration(rcname,nrep,subcarrieroffset,nncellid,rnti,dmrscyclicshift,duplexmode,tddconfig)
% Get the parameter configuration for the specified NPUSCH reference test channel
%
% TS 36.101, User Equipment (UE) radio transmission and reception
% Annex A.2.4 - Reference Measurement Channels for UE Category NB1
%
% TS 36.104, Base Station (BS) radio transmission and reception
% Annex A.14 - Fixed Reference Channels for NB-IoT reference sensitivity (pi/2 BPSK, R=1/3)
% Annex A.15 - Fixed Reference Channels for NB-IoT dynamic range (pi/4 QPSK, R=2/3)
% Annex A.16 - Fixed Reference Channels for NB-IoT PUSCH format 1

    % Prepare for reduced inputs
    if nargin < 2
        nrep = 1;
        subcarrieroffset = 0;
        nncellid = 0;
        rnti = 0;
        dmrscyclicshift = 0;
        duplexmode = 'FDD';
        tddconfig = 1;
        if nargin < 1
            rcname = 'A14-1';
        end
    end

    % Get primary independent parameters for the reference NPUSCH
    [ue,chs,tbs] = getBasicRMCDefinition(rcname);

    % Get number of time slots in a resource unit (NULSlots) according to TS 36.211 Table 10.1.2.3-1
    % The combination of the SCS and number of subcarriers uniquely defines the number of slots in the associated RU
    if strcmpi(chs.NPUSCHFormat,'Data')       % NPUSCH format 1

2-310

 NB-IoT Uplink Waveform Generation

        if chs.NRUsc == 1
            NULSlots = 16;
        elseif any(chs.NRUsc == [3 6 12])
            NULSlots = 24/chs.NRUsc;  % Giving 8,4,2 slots per RU at the associated number of subcarriers
        else
            error('Invalid number of subcarriers. NRUsc must be one of 1,3,6,12.');
        end
    elseif strcmpi(chs.NPUSCHFormat,'Control') % NPUSCH format 2
        NULSlots = 4;
    else
        error('Invalid NPUSCH Format (%s). NPUSCHFormat must be ''Data'' or ''Control''',chs.NPUSCHFormat);
    end
    chs.NULSlots = NULSlots;  % Mandatory. Number of slots in single RU (deduced from NRUsc and format, and the TS 36.211 table)

    % NPUSCH channel-specific parameters - Required parameters
    numSubcarriers = 12*15/str2double(ue.NBULSubcarrierSpacing(1:end-3));
    subcarrieroffset = min(subcarrieroffset,numSubcarriers-chs.NRUsc);
    chs.NBULSubcarrierSet = subcarrieroffset+(0:chs.NRUsc-1); % Mandatory
    chs.NRep = nrep;         % Mandatory
    chs.RNTI = rnti;         % Mandatory

    chs.NPUSCHPower = 0;     % Simulation mandatory
    chs.NPUSCHDMRSPower = 0; % Simulation mandatory

    % NPUSCH channel-specific parameters - Defaulting optional parameters
    chs.CyclicShift = dmrscyclicshift; % Optional. DM-RS multi-tone (3 or 6) cyclic shift
    chs.SeqGroupHopping = 'off';       % Optional. Enable/Disable Sequence-Group Hopping for UE
    % Set the DM-RS base sequence ID according to TS 36.211 Section 10.1.4.1.2.
    % DM-RS base sequence ID is used for the multi-tone cases (3, 6, 12
    % tones), while has no effect for single-tone or disabled sequence-group hopping cases.
    if chs.NRUsc == 3
        maxBaseSeqIdx = 12;
    elseif chs.NRUsc == 6
        maxBaseSeqIdx = 14;
    else % chs.NRUsc == 12 or single tone
        maxBaseSeqIdx = 30;
    end
    chs.BaseSeqIdx = mod(nncellid,maxBaseSeqIdx); % Optional. DM-RS base sequence ID
    chs.SeqGroup = 0;                  % Optional. Delta_SS. Higher-layer parameter groupAssignmentNPUSCH
    chs.SlotIdx = 0;                   % Optional (for lteSCFDMAModulate). Initial slot index of the waveform

    % UE-wide parameters - Required parameters
    ue.NNCellID = nncellid;     % Mandatory
    ue.DuplexMode = duplexmode; % Mandatory

    % UE-wide parameters - Defaulting optional parameters
    if strcmpi(duplexmode,'TDD')
        ue.TDDConfig = tddconfig; % Optional. TDD configuration (1, 2, 3, 4, or 5 for 15kHz, and 1 or 4 for 3.75kHz)
    end

end

function [ue,chs,tbs] = getBasicRMCDefinition(rcname)
% Get the primary independent parameters for the RMC from the RAN4 RMC/FRC specification tables

    persistent rclist nl;

    if isempty(rclist)

2-311

2 Examples and Demos

        % TS 36.104 A.14 Fixed Reference Channels for NB-IoT reference sensitivity (pi/2 BPSK, R=1/3)
        rclistA14 = struct(...
            'RCName',compose('A14-%d',1:2),...
            'TBS',32,...
            'NBULSubcarrierSpacing',{'15kHz','3.75kHz'},...
            'NRUsc',1,...
            'Modulation','BPSK',...  % (pi/2) BPSK for single tone
            'NRU',2, ...  % Each NPUSCH instance is 2 RUs of 1x16 'subcarriers x slots x pi/2-BPSK'
            'NPUSCHFormat','Data'...
            );

        % TS 36.104 A.15 Fixed Reference Channels for NB-IoT dynamic range (pi/4 QPSK, R=2/3)
        rclistA15 = struct(...
            'RCName',compose('A15-%d',1:2),...
            'TBS',104,...
            'NBULSubcarrierSpacing',{'15kHz','3.75kHz'},...
            'NRUsc',1,...
            'Modulation','QPSK',...  % (pi/4) QPSK for a single tone
            'NRU',1, ...  % Each NPUSCH instance to 1 RU of 1x16 'subcarriers x slots x pi/4-QPSK'
            'NPUSCHFormat','Data'...
            );

        % TS 36.104 A.16 Fixed Reference Channels for NB-IoT NPUSCH format 1
        % A.16.1 One PRB
        rclistA16_1 = struct(...
            'RCName',compose('A16-%d',1:6),...
            'TBS',{32,32,40,104,136,424},...
            'NBULSubcarrierSpacing',{'3.75kHz','15kHz','15kHz','15kHz','15kHz','15kHz'},...
            'NRUsc',{1,1,3,6,12,12},...
            'Modulation',{'BPSK','BPSK','QPSK','QPSK','QPSK','QPSK'},...
            'NRU',{2,2,1,1,1,5}, ...
            'NPUSCHFormat','Data'...
            );
        % A16-7 uses 16QAM
        rclistA16_2 = struct(...
            'RCName','A16-7',...
            'TBS',280,...
            'NBULSubcarrierSpacing','15kHz',...
            'NRUsc',12,...
            'Modulation','16QAM',...
            'NRU',1, ...
            'NPUSCHFormat','Data'...
            );

        % TS 36.101, Annex A.2.4 Reference Measurement Channels for UE Category NB1
        rclistA24 = struct(...
            'RCName',compose('R-%d',1:7),...
            'TBS',{32,40,32,40,72,72,72},...
            'NBULSubcarrierSpacing',{'3.75kHz','3.75kHz','15kHz','15kHz','15kHz','15kHz','15kHz'},...
            'NRUsc',{1,1,1,1,3,6,12},...
            'Modulation',{'BPSK','QPSK','BPSK','QPSK','QPSK','QPSK','QPSK'},...
            'NRU',{2,1,2,1,1,1,1}, ...
            'NPUSCHFormat','Data'...
            );

        % Control (NPUSCH format 2) 'reference' channels (provided here for utility, not 3GPP defined)
        rclistControl = struct(...

2-312

 NB-IoT Uplink Waveform Generation

            'RCName',compose('Control-%d',1:2),...
            'TBS',0,...
            'NBULSubcarrierSpacing',{'3.75kHz','15kHz'},...
            'NRUsc',1,...
            'Modulation','BPSK',...
            'NRU',1, ...
            'NPUSCHFormat','Control'...
            );

        % Combine all the sets of channel definitions into a single structure vector
        rclist = [rclistA14,rclistA15,rclistA16_1,rclistA16_2,rclistA24,rclistControl];
        nl = {rclist.RCName}; % Store all the RMC names contained in the above definitions
    end

    % Look-up the definition entry for the required FRC
    selection = rclist(strcmpi(rcname,nl));
    if isempty(selection)
        error('RC name must be one of %s.', join(string(nl),', '));
    end

    % Parameter field mapping function
    fv = @(y,v)setfield(y,v,selection.(v));

    % Create the UE-specific parameter structure
    ue = struct();
    ue = fv(ue,'NBULSubcarrierSpacing');

    % Create the NPUSCH channel-specific structure
    chs = struct();
    chs = fv(chs,'NPUSCHFormat');
    chs = fv(chs,'Modulation');
    chs = fv(chs,'NRUsc');
    chs = fv(chs,'NRU');

    % Return the associated TBS
    tbs = selection.TBS;

end

function cwOut = getCodewordBlock(cwIn,blockIdx)
    % Get the slice of the codeword related to the input block index
    cwOut = cwIn(:,mod(blockIdx,size(cwIn,2))+1);
end

Selected Bibliography

1

2

3

4

5

6

3GPP TS 36.211 "Physical channels and modulation"

3GPP TS 36.212 "Multiplexing and channel coding"

3GPP TS 36.213 "Physical layer procedures"

3GPP TS 36.321 "Medium Access Control (MAC); Protocol specification"

3GPP TS 36.331 "Radio Resource Control (RRC); Protocol specification"

3GPP TS 36.300 "Overall description; Stage 2"

7 O. Liberg, M. Sundberg, Y.-P. Wang, J. Bergman and J. Sachs, Cellular Internet of Things:

Technologies, Standards and Performance, Elsevier, 2018.

2-313

2 Examples and Demos

8

9

3GPP TS 36.101 "User Equipment (UE) radio transmission and reception"

3GPP TS 36.104 "Base Station (BS) radio transmission and reception"

See Also

Related Examples
•

“NB-IoT Downlink Waveform Generation” on page 2-121

2-314

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

NB-IoT Downlink In-Band and Guardband Waveform Generation
and Analysis

This example shows how to generate a narrowband internet of things (NB-IoT) downlink waveform
for in-band and guardband operation modes on an LTE carrier by using the LTE Toolbox™. The
example also shows an analysis of the quality of the recovered NB-IoT physical downlink shared
channel (NPDSCH) through error vector magnitude (EVM) measurements.

Introduction

To support maximum flexibility of the NB-IoT deployment, 3GPP defines these three NB-IoT modes of
operation:

• Standalone: NB-IoT carrier deployed outside the LTE spectrum, e.g., the spectrum used for GSM

or satellite communications

• Guardband: NB-IoT carrier deployed in the guardband between two LTE carriers

• In-band: NB-IoT carrier deployed in resource blocks of an LTE carrier

This example focuses on the in-band and guardband modes. For more information on generating a
standalone NB-IoT downlink waveform, see the “NB-IoT Downlink Waveform Generation” on page 2-
121 example. This figure shows a sketch of in-band and guardband modes for a 5 MHz LTE carrier.

In-band mode can be further grouped depending on the physical cell identity (PCI) used, Inband-
SamePCI and Inband-DifferentPCI. If Inband-SamePCI, the physical layer cell identity and PCI are the
same and the user equipment (UE) can make assumptions about the ports and channel from LTE
signals. The NB-IoT master information block (MIB-NB) indicates the operation mode. The network
can use radio resource control information to allocate a non-anchor carrier to a UE operating in an
anchor carrier, see Section 6.7.3.2 of TS 36.331 and sections 7.1.2.5 and 7.2.1.1 in [ 5 on page 2-
327 ].

Table 16.8-1 of TS 36.213 restricts the allowed physical resource block (PRB) indices for in-band
mode of an NB-IoT anchor carrier to these values. In-band mode of NB-IoT is not supported on a 1.4

2-315

2 Examples and Demos

MHz LTE carrier. For guardband mode of NB-IoT, the allowed PRB indices depend on the guardband
size of the LTE carrier. Guardband mode of NB-IoT is not supported on a 1.4 MHz and 3 MHz LTE
carrier. This table shows the allowed PRB indices for both in-band and guardband modes.

prbTable = nbAllowedPRB()

prbTable=6×3 table
       LTE Bandwidth             Allowed PRB indices for NB-IoT in-band mode          Allowed PRB indices for NB-IoT guardband mode
    ___________________    _______________________________________________________    _____________________________________________

    "1.4 MHz (  6 RBs)"    {1×0 double                                           }       {1×0 double                          }
    "  3 MHz ( 15 RBs)"    {[                                               2 12]}       {1×0 double                          }
    "  5 MHz ( 25 RBs)"    {[                                          2 7 17 22]}       {[                             -1 25]}
    " 10 MHz ( 50 RBs)"    {[                              4 9 14 19 30 35 40 45]}       {[                       -2 -1 50 51]}
    " 15 MHz ( 75 RBs)"    {[            2 7 12 17 22 27 32 42 47 52 57 62 67 72]}       {[           -4 -3 -2 -1 75 76 77 78]}
    " 20 MHz (100 RBs)"    {[4 9 14 19 24 29 34 39 44 55 60 65 70 75 80 85 90 95]}       {[-5 -4 -3 -2 -1 100 101 102 103 104]}

The example shows how to:

• Generate a waveform for an NB-IoT in-band operation mode

• Retrieve the original NB-IoT waveform from the received combined waveform containing both the

NB-IoT and the LTE waveforms

• Measure NPDSCH EVM to verify the quality of the recovered NB-IoT waveform

These figures show the steps to generate the waveform and the processing steps at the receiver to
compute the NPDSCH EVM. The frequency correction at the receiver introduces a phase offset to
each OFDM symbol. For this reason, the example applies symbol phase compensation to the NB-IoT
resource grid before combining it with the LTE grid.

2-316

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

Simulation Configuration

The example specifies an in-band operation mode of an NB-IoT anchor carrier on a 5 MHz LTE
carrier. You can use the nbPRB parameter to change the index of the LTE PRB for NB-IoT allocation.
To study the effect of the LTE interference on the NPDSCH EVM, run the example again without LTE
interference by setting lteDisabled to true.

operationMode =
ltecfg = struct(); % LTE configuration
ltecfg.TotSubframes = 10; % Number of subframes

; % NB-IoT operation mode

ltecfg.NDLRB =

; % Number of downlink resource blocks

nbPRB =

; % PRB in which the NB-IoT is deployed (0-based)

lteDisabled =
nbPowerBoost = 6; % NB-IoT power boost in dB

; % Set to true to disable the LTE component

% Verify that the PRB chosen for the NB-IoT operation mode in the LTE carrier is allowed.
verifyNBPRB(nbPRB,ltecfg.NDLRB,operationMode);

NB-IoT Downlink Configuration and Resource Grid Generation

Configure the NB-IoT downlink waveform generator. The example uses the
NBIoTDownlinkWaveformGenerator class to generate the NB-IoT resource grid. See the “NB-IoT
Downlink Waveform Generation” on page 2-121 example for more information about
NBIoTDownlinkWaveformGenerator.

ngen = NBIoTDownlinkWaveformGenerator;
ngen.Config.CellRefP = 1;
ngen.Config.NNCellID = 0;
ngen.Config.NFrame = 0;
ngen.Config.TotSubframes = ltecfg.TotSubframes;
ngen.Config.OperationMode = operationMode;

2-317

2 Examples and Demos

ngen.Config.NPDSCH.StartSubframe = 2;
ngen.Config.NPDSCH.NRep = 1;
ngen.Config.Windowing = 3; % Set Windowing to 3, as shown in Table E.5.1-1a of TS 36.104

Display the resource grid.

figure;
displayResourceGrid(ngen);

Generate the NB-IoT downlink waveform and resource grid.

[nbWaveform,nbGrid,nbInfo] = generateWaveform(ngen);
nbInfo

nbInfo = struct with fields:
            SamplingRate: 1920000
                    Nfft: 128
               Windowing: 3
     CyclicPrefixLengths: [10 9 9 9 9 9 9 10 9 9 9 9 9 9]
    SubframeChannelTypes: ["NPBCH"    "NPDCCH"    "NPDSCH"    "NPDSCH"    "SIB1-NB"    "NPSS"    "NPDSCH"    "NPDSCH"    "Unused"    "NSSS"]

LTE Downlink Configuration and Resource Grid Generation

Configure the LTE carrier. If you selected in-band operation mode, the example leaves the nbPRB PRB
index empty in the LTE configuration.

nbPRB = double(nbPRB);
ltecfg.PDSCH.PRBSet = (0:ltecfg.NDLRB-1)'; % Full PRB allocation for LTE
if contains(ngen.Config.OperationMode,'Inband')
    ltecfg.PDSCH.PRBSet(nbPRB+1) = []; % Leave nbPRB empty for in-band NB-IoT
end

2-318

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

Generate the LTE resource grid. The example uses lteRMCDLTool to generate the wideband
resource grid.

[~,lteGrid,lteInfo] = lteRMCDLTool(ltecfg,[1 0 0 1]);

Waveform Generation

The example combines LTE and NB-IoT resource grids before generating the waveform. The
hNBInbandGuardbandCombineGrid function applies pre-OFDM symbol phase compensation to the
NB-IoT grid to deal with the distortion that the receiver introduces when shifting the received
waveform to bring NB-IoT in baseband.

Generate the combined resource grid and get the NB-IoT frequency offset.

% Create the parameter structure needed to generate the combined grid
combGridParams = struct();
combGridParams.OperationMode = ngen.Config.OperationMode;
combGridParams.NBPRB = nbPRB;
combGridParams.OFDMInfo = nbInfo;
combGridParams.LTEDisabled = lteDisabled;
[combGrid,offset] = hNBInbandGuardbandCombinedGrid(combGridParams,lteGrid,nbGrid*db2mag(nbPowerBoost));

Generate the waveform.

OSR = lteInfo.SamplingRate/nbInfo.SamplingRate; % Oversampling ratio for NB-IoT
wavecfg.Windowing = ngen.Config.Windowing*OSR; % Use the same windowing as the NB-IoT waveform
txWaveform = lteOFDMModulate(wavecfg,combGrid);

Plot the power spectrum of the transmitted waveform.

txPlot = spectrumAnalyzer('SampleRate',lteInfo.SamplingRate,'Title','Transmitted Waveform Power Spectrum');
txPlot(txWaveform);

2-319

2 Examples and Demos

NB-IoT Synchronization and Filtering

This section follows these steps:

• Frequency correction. Shift the received waveform in frequency to bring the NB-IoT spectrum to

baseband (0 Hz).

• Filter out the LTE component and downsample. Downsample the waveform to the NB-IoT

sampling rate and filter out the frequencies outside the NB-IoT band.

• Time synchronization. Remove any potential time delay added by the filter.

Plot the spectrogram of the received waveform. This plot shows the frequency occupied by the NB-
IoT component in the received wideband waveform.

rxWaveform = txWaveform;
figure;
spectrogram(rxWaveform(:,1),ones(lteInfo.Nfft,1),0,lteInfo.Nfft,'centered',lteInfo.SamplingRate,'MinThreshold',-130);

2-320

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

Frequency Correction

Shift the received waveform to bring the NB-IoT component to baseband. The plot shows the power
spectrum of the received waveform after the frequency correction.

rxWaveformB = lteFrequencyCorrect(ltecfg,rxWaveform,offset); % Received waveform with NB-IoT in baseband
combinedSpecPlotB = spectrumAnalyzer('SampleRate',lteInfo.SamplingRate,'Title','Received Waveform Power Spectrum with NB-IoT in Baseband');
combinedSpecPlotB(rxWaveformB);

2-321

2 Examples and Demos

Filtering and Downsampling of NB-IoT Waveform

This example uses the resample function to downsample the wideband waveform to the nominal NB-
IoT sampling rate of 1.92 MHz. Furthermore, the default FIR antialiasing lowpass filter implemented
in the resample function filters out the unwanted LTE waveform, without the need of an additional
lowpass filter.

rxwave = resample(rxWaveformB,1,OSR);

Plot the power spectrum of the recovered NB-IoT waveform against the power spectrum of the
original NB-IoT waveform generated by the NB-IoT waveform generator
NBIoTDownlinkWaveformGenerator. Because the power of the generated waveform depends on
the FFT size, divide the original waveform by the oversampling rate so that both waveforms have a
comparable power.

filteredSpecPlot = spectrumAnalyzer('SampleRate',nbInfo.SamplingRate,'Title','Original and Recovered NB-IoT Waveform Power Spectrum',...
    'ChannelNames',{'Original NB-IoT waveform','Recovered NB-IoT waveform'},'ShowLegend',true);
filteredSpecPlot([nbWaveform/OSR*db2mag(nbPowerBoost),rxwave]);

2-322

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

Plot the spectrogram of the recovered NB-IoT waveform. This plot shows the baseband narrowband
waveform after extracting it from the received wideband waveform.

figure;
spectrogram(rxwave(:,1),ones(nbInfo.Nfft,1),0,nbInfo.Nfft,'centered',nbInfo.SamplingRate,'MinThreshold',-130);

2-323

2 Examples and Demos

Time Synchronization

Extract NB-IoT configuration parameters for time synchronization and EVM measurements.

enb = ngen.Config;
enb.NSubframe = lteInfo.NSubframe;

Apply time synchronization to the resulting waveform.

timeOffset = lteNBDLFrameOffset(enb,rxwave); % Time delay in samples
rxwave = rxwave(1+timeOffset:end,:);

EVM Measurements

Channel Estimator Configuration for EVM measurements

Parameterize the channel estimator at the receiver end using the structure cec.

cec = struct;                        % Channel estimation config structure
cec.PilotAverage = 'UserDefined';    % Type of pilot symbol averaging
cec.FreqWindow = 13;                 % Frequency window size
cec.TimeWindow = 9;                  % Time window size
cec.InterpType = 'Cubic';            % 2D interpolation type
cec.InterpWindow = 'Centered';       % Interpolation window type
cec.InterpWinSize = 1;               % Interpolation window size
cec.Reference = 'NRS';               % Reference signal for channel estimation

Process EVM

The hNPDSCHEVM function provides per subframe and average EVM measurements. The example also
displays plots with the EVM versus time and subcarriers.

[evmmeas,plots] = hNPDSCHEVM(enb,cec,rxwave,nbInfo);

2-324

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

EVM subframe 2: 0.210%
EVM subframe 3: 0.176%
EVM subframe 6: 0.207%
EVM subframe 7: 0.192%
Averaged EVM frame 0: 0.197%
Averaged overall EVM: 0.197%

2-325

2 Examples and Demos

2-326

 NB-IoT Downlink In-Band and Guardband Waveform Generation and Analysis

References

1

2

3

4

3GPP TS 36.101. “Evolved Universal Terrestrial Radio Access (E-UTRA); User Equipment (UE)
Radio Transmission and Reception.” 3rd Generation Partnership Project; Technical Specification
Group Radio Access Network.

3GPP TS 36.104. "Evolved Universal Terrestrial Radio Access (E-UTRA); Base Station (BS) Radio
Transmission and Reception." 3rd Generation Partnership Project; Technical Specification Group
Radio Access Network.

3GPP TS 36.213. "Evolved Universal Terrestrial Radio Access (E-UTRA); Physical Layer
Procedures." 3rd Generation Partnership Project; Technical Specification Group Radio Access
Network.

3GPP TS 36.331. "Evolved Universal Terrestrial Radio Access (E-UTRA); Radio Resource Control
(RRC); Protocol specification." 3rd Generation Partnership Project; Technical Specification Group
Radio Access Network.

5 O. Liberg, M. Sundberg, Y.-P. Wang, J. Bergman, J. Sachs and G. Wikstrom, Cellular Internet of

Things: From Massive Deployments to Critical 5G Applications, Elsevier, 2020.

Local Functions

function prbTable = nbAllowedPRB()
    % Generate a table showing the PRB indices allowed for NB-IoT in-band
    % and guardband operation mode for each LTE bandwidth.

    NDLRBList = [6 15 25 50 75 100];
    bwMHz = [1.4 3 5 10 15 20]; % Bandwidth in MHz
    bw = (pad(string(bwMHz),'left') + repmat(" MHz (",size(bwMHz)) + pad(string(NDLRBList),'left') + repmat(" RBs)",size(bwMHz)))';

    % In-band mode
    % The allowed PRB indices for in-band mode of NB-IoT anchor
    % carrier are derived from Table 16.8-1 of TS 36.213.
    prbIndexOdd = [-35:5:-5 5:5:35]; % DC (i.e., PRB 0) is excluded
    prbIndexEven = [-46:5:-6 5:5:45]; % DC (i.e., PRB 0) is excluded
    PRBInband = cell(length(NDLRBList),1);
    for ibw = 1:length(NDLRBList)
        if mod(NDLRBList(ibw),2) % Odd
            prbTemp = prbIndexOdd + floor(NDLRBList(ibw)/2);
        else % Even
            prbTemp = prbIndexEven + floor(NDLRBList(ibw)/2);
        end
        prbTemp(prbTemp<0 | prbTemp>=NDLRBList(ibw)) = [];
        PRBInband{ibw} = prbTemp;
    end
    PRBVariableNameInband = "Allowed PRB indices for NB-IoT in-band mode";

    % Guardband mode
    % The allowed PRB indices for NB-IoT guardband mode are derived
    % here for all channel bandwidths.
    totalGuardHz = bwMHz*1e6 - NDLRBList*12*15e3; % Total guardband in Hz
    NRBGuard = floor((totalGuardHz/2) / (12*15e3)); % Number of RBs allowed on each side of the guardband for all BWs
    PRBGuard = cellfun(@(x,y)([-x:-1, y+(0:(x-1))]),num2cell(NRBGuard(:)),num2cell(NDLRBList(:)),'UniformOutput',false); % Allowed PRB indices for guardband (0-based)
    PRBVariableNameGuard = "Allowed PRB indices for NB-IoT guardband mode";

    prbTable = table(bw,PRBInband,PRBGuard);

2-327

2 Examples and Demos

    prbTable.Properties.VariableNames = ["LTE Bandwidth" PRBVariableNameInband PRBVariableNameGuard];
end

function verifyNBPRB(nbPRB,NDLRB,operationMode)
    % Check whether the PRB chosen for the NB-IoT operation mode in the LTE
    % carrier is allowed.
    prbTable = nbAllowedPRB();

    r = contains(prbTable{:,1},string(NDLRB)+" RBs"); % prbTable row associated to the given bandwidth
    c = 1+contains(operationMode,'Inband')*1+contains(operationMode,'Guard')*2; % prbTable column associated to the given operation mode

    errorFlag = ismember(nbPRB,prbTable{r,c}{1}); % If true, the selected nbPRB is allowed
    tmp = extract(prbTable{r,1},digitsPattern);
    msg = "The chosen PRB index ("+string(nbPRB)+") is invalid for "+operationMode+" operation mode on a "+string(tmp(1))+...
        " MHz LTE carrier. See 'prbTable' for the allowed PRB indices for all combinations of LTE bandwidth and operation mode.";
    assert(errorFlag,msg); % Throws an error if the chosen nbPRB is invalid for the given combination of NDLRB and operation mode
end

2-328

 NB-IoT NPDSCH Block Error Rate Simulation

NB-IoT NPDSCH Block Error Rate Simulation

This example shows how LTE Toolbox™ can be used to create a NB-IoT Narrowband Physical
Downlink Shared Channel (NPDSCH) Block Error Rate (BLER) simulation under frequency-selective
fading and Additive White Gaussian Noise (AWGN) channel.

Introduction

3GPP Release 13 of LTE started to add support for Narrowband IoT applications. Release 13 defines a
single NB-IoT UE Category, namely Cat-NB1, and Release 14 adds Cat-NB2 which allows for larger
transport block sizes. This example focuses on Release 13 NB-IoT.

The example generates a NB-IoT NPDSCH BLER curve for a number of SNR points and transmission
parameters. NPSS and NSSS are transmitted in appropriate subframes and the NPSS is used for
practical timing synchronization. NPSS and NSSS subframes are not used for NPDSCH transmission.
The NRS is transmitted in NPDSCH subframes and is used for practical channel estimation. NPBCH
transmission gaps are not considered in this example.

Simulation Configuration

The simulation length is 4 DL-SCH transport blocks for a number of SNR points. A larger number of
numTrBlks should be used to produce meaningful throughput results. SNR can be an array of values
or a scalar. The simulation is performed over different repetition values to compare the performance
improvement with repetitions.

numTrBlks = 4;        % Number of simulated transport blocks
SNRdB = -32:4:0;      % SNR range in dB
ireps = [0 5 9];      % Range of reps simulated

Set Up Higher Layer Parameters

Set up the following higher layer parameters which are used to configure the NPDSCH in the next
section:

• The variable NPDSCHDataType indicates whether the NPDSCH is carrying the

SystemInformationBlockType1-NB (SIB1-NB) or not, and whether the NPDSCH is carrying the
broadcast control channel (BCCH) or not. The allowed values of NPDSCHDataType are 'SIB1NB',
'BCCHNotSIB1NB' and 'NotBCCH'. Note that SIB1-NB belongs to the BCCH.

• The variable NPDSCHModulation indicates the modulation scheme used by the NPDSCH. The

allowed values of NPDSCHModulation are 'QPSK' and '16QAM'.

• The number of NPDSCH repetitions and the transport block size (TBS) are affected by whether

NPDSCH is carrying SIB1-NB or not and the modulation scheme used by NPDSCH (see 3GPP TS
36.213 16.4.1.3 and 16.4.1.5 [ 2 ]). NPDSCHDataType set to 'SIB1NB' indicates that the
NPDSCH is carrying SIB1-NB; NPDSCHDataType set to either 'BCCHNotSIB1NB' or 'NotBCCH'
indicates that the NPDSCH is not carrying SIB1-NB.

• The NPDSCH repetition pattern and the scrambling sequence generation is affected by whether
NPDSCH is carrying BCCH or not (see 3GPP TS 36.211 10.2.3 [ 1 ]). NPDSCHDataType set to
either 'SIB1NB' or 'BCCHNotSIB1NB' indicates that the NPDSCH is carrying BCCH;
NPDSCHDataType set to 'NotBCCH' indicates that the NPDSCH is not carrying BCCH.

NPDSCHDataType = 'NotBCCH';  % The allowed values are 'SIB1NB', 'BCCHNotSIB1NB' and 'NotBCCH'
NPDSCHModulation = 'QPSK'; % The allowed values are 'QPSK' and '16QAM'

2-329

2 Examples and Demos

• The variable ISF configures the number of subframes for a NPDSCH according to 3GPP TS

36.213 Table 16.4.1.3-1 [ 2 ]. Valid values for ISF are 0...7.

When the NPDSCH carries the SIB1-NB:

• The variable SchedulingInfoSIB1 configures the number of NPDSCH repetitions according to

3GPP TS 36.213 Table 16.4.1.3-3 and the TBS according to Table 16.4.1.5.2-1 [ 2 ]. Valid values for
SchedulingInfoSIB1 are 0...11.

When the NPDSCH does not carry the SIB1-NB:

• The variable IRep configures the number of NPDSCH repetitions according to 3GPP TS 36.213

Table 16.4.1.3-2 [ 2 ]. Valid values for IRep are 0...15.

• The variable IMCS together with IRep configure the TBS according to 3GPP TS 36.213 Table

16.4.1.5.1-1 [ 2 ]. Valid values for IMCS are 0...13.

ISF = 0;                % Resource assignment field in DCI (DCI format N1 or N2)
SchedulingInfoSIB1 = 0; % Scheduling information field in MasterInformationBlock-NB (MIB-NB)
IMCS = 4;               % Modulation and coding scheme field in DCI (DCI format N1 or N2)

eNB Configuration

Configure the starting frame and subframe numbers (enb.NFrame and enb.NSubframe) in the
simulation for each SNR point, the narrowband physical cell ID enb.NNCellID, the number of NRS
antenna ports (enb.NBRefP, one antenna port indicates port 2000 is used, two antenna ports
indicates port 2000 and port 2001 are used), the NB-IoT operation mode enb.OperationMode which
can be any value as follows:

• 'Standalone': NB-IoT carrier deployed outside the LTE spectrum, e.g. the spectrum used for

GSM or satellite communications

• 'Guardband': NB-IoT carrier deployed in the guardband between two LTE carriers

• 'Inband-SamePCI': NB-IoT carrier deployed in resource blocks of a LTE carrier, with

enb.NBRefP the same as the number of CRS ports enb.CellRefP

• 'Inband-DifferentPCI': NB-IoT carrier deployed in resource blocks of a LTE carrier, with

enb.NBRefP different as enb.CellRefP

enb.CellRefP is configured when the operation mode is 'Inband-DifferentPCI'. The starting
OFDM symbol index in a subframe for NPDSCH is configured using enb.ControlRegionSize,
when the values of NPDSCHDataType and enb.OperationMode satisfy the following conditions:

• NPDSCHDataType is either 'BCCHNotSIB1NB' or 'NotBCCH'

• enb.OperationMode is either 'Inband-SamePCI' or 'Inband-DifferentPCI'

enb.NFrame = 0;     % Simulation starting frame number
enb.NSubframe = 0;  % Simulation starting subframe number
enb.NNCellID = 0;   % NB-IoT physical cell ID
enb.NBRefP = 2;     % Number of NRS antenna ports, should be either 1 or 2
enb.OperationMode = 'Inband-DifferentPCI';  % The allowed values are 'Inband-SamePCI', 'Inband-DifferentPCI', 'Guardband' or 'Standalone'
if strcmpi(enb.OperationMode,'Inband-SamePCI')
    enb.CellRefP = enb.NBRefP;     % The allowed values are NBRefP or 4
    enb.NCellID = enb.NNCellID;
elseif strcmpi(enb.OperationMode,'Inband-DifferentPCI')
    enb.CellRefP = 4; % Number of Cell RS antenna ports (Must be equal to NBRefP or 4)
    enb.NCellID = 1;

2-330

 NB-IoT NPDSCH Block Error Rate Simulation

end
if (strcmpi(NPDSCHDataType,'BCCHNotSIB1NB') || strcmpi(NPDSCHDataType,'NotBCCH')) && ...
        (strcmpi(enb.OperationMode,'Inband-SamePCI') || strcmpi(enb.OperationMode,'Inband-DifferentPCI'))
    enb.ControlRegionSize = 3;     % The allowed values are 0...13
end

Propagation Channel Model Configuration

The structure channel contains the channel model configuration parameters.

channel = struct;                    % Initialize channel config structure
channel.Seed = 6;                    % Channel seed
channel.NRxAnts = 1;                 % 1 receive antenna
channel.DelayProfile ='EPA';         % Delay profile
channel.DopplerFreq = 5;             % Doppler frequency in Hz
channel.MIMOCorrelation = 'Low';     % Multi-antenna correlation
channel.NTerms = 16;                 % Oscillators used in fading model
channel.ModelType = 'GMEDS';         % Rayleigh fading model type
channel.InitPhase = 'Random';        % Random initial phases
channel.NormalizePathGains = 'On';   % Normalize delay profile power
channel.NormalizeTxAnts = 'On';      % Normalize for transmit antennas

Channel Estimator Configuration

In this example the parameter perfectChannelEstimator controls channel estimator behavior.
Valid values are true or false. When set to true, a perfect channel estimator is used otherwise a
practical estimator is used, based on the values of the received NRS.

% Channel estimator behavior
perfectChannelEstimator = true;

The practical channel estimator is configured with a structure cec. An EPA delay profile with 5Hz
Doppler causes the channel to change slowly over time. Therefore only frequency averaging is
performed over pilot estimates by setting the time window to 1 Resource Element (RE) and frequency
window to 25 to ensure averaging over all subcarriers for the resource block.

% Configure channel estimator
cec.PilotAverage = 'UserDefined';   % Type of pilot symbol averaging
cec.TimeWindow = 1;                 % Time window size in REs
cec.FreqWindow = 25;                % Frequency window size in REs
cec.InterpType = 'Cubic';           % 2D interpolation type
cec.InterpWindow = 'Centered';      % Interpolation window type
cec.InterpWinSize = 3;              % Interpolation window size
cec.Reference = 'NRS';              % Channel estimator reference signal

NPDSCH Configuration

Obtain the following NPDSCH parameters from the higher layer configurations defined above:

• The number of repetitions (NRep)

• The number of subframes used for a NPDSCH when there is no repetition (NSF)

• The transport block size (TBS)

2-331

2 Examples and Demos

These parameters can be obtained by using the class hNPDSCHInfo. hNPDSCHInfo also provides
method displaySubframePattern to display the NPDSCH repetition pattern, which is shown in
the next section.

for repIdx = 1:numel(ireps)

    npdschInfo = hNPDSCHInfo;
    npdschInfo.NPDSCHDataType = NPDSCHDataType;
    npdschInfo.ISF = ISF;
    npdschInfo.OperationMode = enb.OperationMode;
    npdschInfo.Modulation = NPDSCHModulation;
    if strcmpi(NPDSCHDataType,'SIB1NB')  % NPDSCH carrying SIB1-NB
        npdschInfo.SchedulingInfoSIB1 = SchedulingInfoSIB1;
    else % NPDSCH not carrying SIB1-NB
        npdschInfo.IRep = ireps(repIdx); % Repetition number field in DCI (DCI format N1 or N2)
        npdschInfo.IMCS = IMCS;          % Modulation and coding scheme field in DCI (DCI format N1 or N2)
    end

Create the structure npdsch using the obtained number of repetitions (npdschInfo.NRep), the
number of subframes of a NPDSCH (npdschInfo.NSF) from the class instance npdschInfo, input
parameter NPDSCHDataType and the Radio Network Temporary Identifier RNTI. Note that NSF = 8
is used when NPDSCHDataType is 'SIB1NB'.

    npdsch.NSF = npdschInfo.NSF;
    npdsch.NRep = npdschInfo.NRep;
    npdsch.NPDSCHDataType = NPDSCHDataType;
    npdsch.Modulation = NPDSCHModulation;
    npdsch.RNTI = 1;

Compute codeword length and transport block size.

    [~,info] = lteNPDSCHIndices(enb,npdsch);
    rmoutlen = info.G;           % Bit length after rate matching, i.e. codeword length
    trblklen = npdschInfo.TBS;   % Transport block size

Display Subframe Repetition Pattern

The variable displayPattern controls the display of the NPDSCH subframe repetition pattern. An
example is shown in the following figure for the case when the NPDSCH carries the BCCH, the
NPDSCH consists of npdschInfo.NSF = 3 different subframes, each color represents a subframe
which represents 1 ms. Each subframe is repeated npdschInfo.NRep = 4 times, thus a total of 12
subframes are required to transmit the NPDSCH.

2-332

 NB-IoT NPDSCH Block Error Rate Simulation

    %  The NPDSCH repetition pattern for the current configuration is
    %  displayed below
    displayPattern = false;
    % Display NPDSCH repetition pattern
    if displayPattern == true
        npdschInfo.displaySubframePattern;
    end

Block Error Rate Simulation Loop

This part of the example shows how to perform NB-IoT NPDSCH link level simulation and plot BLER
results. The transmit and receive chain is depicted in the following figure.

2-333

2 Examples and Demos

A random stream of bits with the size of the desired transport block undergoes CRC encoding,
convolutional encoding and rate matching to obtain the NPDSCH bits, which are repeated according
to a specific subframe repetition pattern. Scrambling, modulation, layer mapping and precoding are
then applied to form the complex NPDSCH symbols. These symbols along with the NRS signals are
mapped to the grid and OFDM modulated to create the time domain waveform. This is then passed
through a fading channel and AWGN is added. The noisy waveform is then synchronized and
demodulated. Channel estimation and equalization is performed on the recovered NPDSCH symbols
after which channel decoding and demodulation are performed to recover the transport block. After
de-scrambling, the repetitive subframes are soft-combined before rate recover. The transport block
error rate is calculated for each SNR point. The evaluation of the block error rate is based on the
assumption that all the subframes in a bundle is used to decode the transport block at the UE. A
bundle is defined in the MAC layer (see 3GPP TS 36.321 5.3.2.1 [ 3 ]) as the npdsch.NSF
npdsch.NRep subframes used to carry a transport block.

    % Absolute subframe number at the starting point of the simulation
    NSubframe = enb.NFrame*10+enb.NSubframe;

    % Initialize BLER and throughput result
    maxThroughput = zeros(length(SNRdB),1);
    simThroughput = zeros(length(SNRdB),1);
    bler = zeros(1,numel(SNRdB));

    % The temporary variables 'enb_init' and 'channel_init' are used to create
    % the temporary variable 'enb' and 'channel' within the SNR loop to create
    % independent simulation loops for the 'parfor' loop
    enb_init = enb;
    channel_init = channel;

    for snrIdx = 1:numel(SNRdB)
    % parfor snrIdx = 1:numel(SNRdB)
    % To enable the use of parallel computing for increased speed comment out
    % the 'for' statement above and uncomment the 'parfor' statement below.
    % This needs the Parallel Computing Toolbox. If this is not installed
    % 'parfor' will default to the normal 'for' statement.

        % Set the random number generator seed depending to the loop variable
        % to ensure independent random streams
        rng(snrIdx,'combRecursive');

2-334

 NB-IoT NPDSCH Block Error Rate Simulation

        fprintf('\nSimulating %d transport blocks at %gdB SNR\n',numTrBlks,SNRdB(snrIdx));

        enb = enb_init;         % Initialize eNodeB configuration
        channel = channel_init; % Initialize fading channel configuration
        txcw = [];              % Initialize the transmitted codeword
        numBlkErrors = 0;       % Number of transport blocks with errors
        estate = [];            % Initialize NPDSCH encoder state
        dstate = [];            % Initialize NPDSCH decoder state
        lastOffset = 0;         % Initialize overall frame timing offset
        offset = 0;             % Initialize frame timing offset
        subframeGrid = lteNBResourceGrid(enb); % Initialize the subframe grid

        subframeIdx = NSubframe;
        numRxTrBlks = 0;
        while (numRxTrBlks < numTrBlks)

            % Set current subframe and frame numbers
            enb.NSubframe = mod(subframeIdx,10);
            enb.NFrame = floor((subframeIdx)/10);

            % Generate the NPSS symbols and indices
            npssSymbols = lteNPSS(enb);
            npssIndices = lteNPSSIndices(enb);
            % Map the symbols to the subframe grid
            subframeGrid(npssIndices) = npssSymbols;

            % Generate the NSSS symbols and indices
            nsssSymbols = lteNSSS(enb);
            nsssIndices = lteNSSSIndices(enb);
            % Map the symbols to the subframe grid
            subframeGrid(nsssIndices) = nsssSymbols;

            % Establish if either NPSS or NSSS is transmitted and if so,
            % do not transmit NPDSCH in this subframe
            isDataSubframe = isempty(npssSymbols) && isempty(nsssSymbols);

            % Create a new transport block and encode it when the
            % transmitted codeword is empty. The receiver sets the codeword
            % to empty to signal that all subframes in a bundle have been
            % received (it is also empty before the first transmission)
            if isempty(txcw)
                txTrBlk = randi([0 1],trblklen,1);
                txcw = lteNDLSCH(rmoutlen,txTrBlk);
            end

            if (isDataSubframe)
                % Generate NPDSCH symbols and indices for a subframe
                [txNpdschSymbols,estate] = lteNPDSCH(enb,npdsch,txcw,estate);
                npdschIndices = lteNPDSCHIndices(enb,npdsch);
                % Map the symbols to the subframe grid
                subframeGrid(npdschIndices) = txNpdschSymbols;
                % Generate the NRS symbols and indices
                nrsSymbols = lteNRS(enb);
                nrsIndices = lteNRSIndices(enb);
                % Map the symbols to the subframe grid
                subframeGrid(nrsIndices) = nrsSymbols;
            end

2-335

2 Examples and Demos

            % Perform OFDM modulation to generate the time domain waveform
            [txWaveform,ofdmInfo] = nbOFDMModulate(enb,subframeGrid);

            % Add 25 sample padding. This is to cover the range of delays
            % expected from channel modeling (a combination of
            % implementation delay and channel delay spread)
            txWaveform =  [txWaveform; zeros(25, enb.NBRefP)]; %#ok<AGROW>

            % Initialize channel time for each subframe
            channel.InitTime = subframeIdx/1000;

            % Pass data through channel model
            channel.SamplingRate = ofdmInfo.SamplingRate;
            [rxWaveform,fadingInfo] = lteFadingChannel(channel, txWaveform);

            % Calculate noise gain including compensation for downlink power
            % allocation
            SNR = 10^(SNRdB(snrIdx)/10);

            % Normalize noise power to take account of sampling rate, which
            % is a function of the IFFT size used in OFDM modulation, and
            % the number of antennas
            N0 = 1/sqrt(2.0*enb.NBRefP*double(ofdmInfo.Nfft)*SNR);

            % Create additive white Gaussian noise
            noise = N0*complex(randn(size(rxWaveform)), ...
                                randn(size(rxWaveform)));

            % Add AWGN to the received time domain waveform
            rxWaveform = rxWaveform + noise;

            %------------------------------------------------------------------
            %            Receiver
            %------------------------------------------------------------------

            % Perform timing synchronization, extract the appropriate
            % subframe of the received waveform, and perform OFDM
            % demodulation
            if(perfectChannelEstimator)
                offset = hPerfectTimingEstimate(fadingInfo);
            else
                % In this example, the subframe offset calculation relies
                % on NPSS present in subframe 5, so we need to pad the
                % subframes before it so that the frame offset returned by
                % lteNBDLFrameOffset is the offset for subframe 5
                sfTsamples = ofdmInfo.SamplingRate*1e-3;
                if (enb.NSubframe==5)
                    padding = zeros([sfTsamples*5,size(rxWaveform,2)]);
                    offset = lteNBDLFrameOffset(enb, [padding; rxWaveform]);
                    if (offset > 25) || (offset < 0)
                        offset = lastOffset;
                    end
                    lastOffset = offset;
                end
            end

            % Synchronize the received waveform
            rxWaveform = rxWaveform(1+offset:end, :);

2-336

 NB-IoT NPDSCH Block Error Rate Simulation

            % Perform OFDM demodulation on the received data to recreate the
            % resource grid
            rxSubframe = nbOFDMDemodulate(enb,rxWaveform);

            % Channel estimation
            if(perfectChannelEstimator)
                % Perfect channel estimation
                estChannelGrid = nbDLPerfectChannelEstimate(enb, channel, offset);
                noiseGrid = nbOFDMDemodulate(enb, noise(1+offset:end ,:));
                noiseEst = var(noiseGrid(:));
            else

                [estChannelGrid, noiseEst] = lteDLChannelEstimate( ...
                enb, cec, rxSubframe);
            end

            if (isDataSubframe)
                % Get NPDSCH indices
                npdschIndices = lteNPDSCHIndices(enb, npdsch);

                % Get PDSCH resource elements from the received subframe. Scale the
                % received subframe by the PDSCH power factor Rho. The PDSCH is
                % scaled by this amount, while the cell reference symbols used for
                % channel estimation (used in the PDSCH decoding stage) are not.
                [rxNpdschSymbols, npdschHest] = lteExtractResources(npdschIndices, ...
                    rxSubframe, estChannelGrid);

                % Decode NPDSCH
                [rxcw,dstate,symbols] = lteNPDSCHDecode(...
                                     enb, npdsch, rxNpdschSymbols, npdschHest, noiseEst,dstate);

                % Decode the transport block when all the subframes in a bundle
                % have been received
                if dstate.EndOfTx
                   [trblkout,blkerr] = lteNDLSCHDecode(trblklen,rxcw);
                   numBlkErrors = numBlkErrors + blkerr;
                   numRxTrBlks = numRxTrBlks + 1;
                   % Re-initialize to enable the transmission of a new transport block
                   txcw = [];
                end
            end

            subframeIdx = subframeIdx + 1;

        end

        % Calculate the block error rate
        bler(snrIdx) = numBlkErrors/numTrBlks;
        fprintf('NPDSCH BLER = %.4f \n',bler(snrIdx));
        % Calculate the maximum and simulated throughput
        maxThroughput(snrIdx) = trblklen*numTrBlks; % Max possible throughput
        simThroughput(snrIdx) = trblklen*(numTrBlks-numBlkErrors);  % Simulated throughput
        fprintf('NPDSCH Throughput(%%) = %.4f %%\n',simThroughput(snrIdx)*100/maxThroughput(snrIdx));

    end

2-337

2 Examples and Demos

Simulating 4 transport blocks at -32dB SNR

Simulating 4 transport blocks at -32dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -28dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -24dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -20dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -16dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -12dB SNR
NPDSCH BLER = 0.2500
NPDSCH Throughput(%) = 75.0000 %

Simulating 4 transport blocks at -8dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -4dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at 0dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -32dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -28dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -24dB SNR
NPDSCH BLER = 0.2500
NPDSCH Throughput(%) = 75.0000 %

Simulating 4 transport blocks at -20dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -16dB SNR

2-338

 NB-IoT NPDSCH Block Error Rate Simulation

NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -12dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -8dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at -4dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Simulating 4 transport blocks at 0dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

Plot Block Error Rate vs SNR Results

    if repIdx == 1
        fh = figure;
        grid on;
        hold on;
        xlabel('SNR (dB)');
        ylabel('BLER');
        legendstr = {['NRep = ' num2str(npdsch.NRep)]};
    else
        legendstr = [legendstr ['NRep = ' num2str(npdsch.NRep)]]; %#ok<AGROW>
    end
    figure(fh);
    plot(SNRdB, bler, '-o');

2-339

2 Examples and Demos

2-340

 NB-IoT NPDSCH Block Error Rate Simulation

2-341

2 Examples and Demos

end
% Set figure title
if strcmpi(NPDSCHDataType,'SIB1NB')
    npdsch.NSF = 8;
end
title([' ' char(npdsch.NPDSCHDataType) ': TBS=' num2str(trblklen)...
    '; NSF=' num2str(npdsch.NSF) '; ' num2str(enb_init.NBRefP) ' NRS port(s)' ]);
legend(legendstr);

The following plot shows the simulation run with numTrBlks set to 1000 while using the perfect
channel estimator.

2-342

 NB-IoT NPDSCH Block Error Rate Simulation

Appendix

This example uses the helper functions:

• hPerfectTimingEstimate.m

• hNPDSCHInfo.m

Selected Bibliography

1

2

3

4

3GPP TS 36.211 "Physical channels and modulation"

3GPP TS 36.213 "Physical layer procedures"

3GPP TS 36.321 "Medium Access Control (MAC) protocol specification"

3GPP TS 36.101 "User Equipment (UE) radio transmission and reception"

Local functions

% NB-IoT DL OFDM Modulator
function [waveform,info] = nbOFDMModulate(enb,grid)
    % Apply default window size according to TS 36.104 Table E.5.1-1a
    if(~isfield(enb,'Windowing'))
        enb.Windowing = 6;
    end
    % Use NB-IoT SC-FDMA to get the 1/2 subcarrier shift on the OFDM modulation
    enb.NBULSubcarrierSpacing = '15kHz';
    [waveform,info] = lteSCFDMAModulate(enb,grid);

2-343

2 Examples and Demos

end

% NB-IoT DL OFDM Demodulator
function grid = nbOFDMDemodulate(enb,rxWaveform)
    % Use NB-IoT SC-FDMA to get the 1/2 subcarrier shift on the OFDM modulation
    enb.NBULSubcarrierSpacing = '15kHz';
    grid = lteSCFDMADemodulate(enb,rxWaveform,0.55); % CP fraction of 0.55
end

% NB-IoT DL Perfect Channel Estimator
function H = nbDLPerfectChannelEstimate(enb,channel,timefreqoffset)
    % Reconfigure NB-IoT UL perfect channel estimator to perform DL perfect
    % channel estimation
    enb.NBULSubcarrierSpacing = '15kHz';
    enb.NTxAnts = enb.NBRefP;
    enb.TotSlots = 2;
    H = lteULPerfectChannelEstimate(enb, channel,timefreqoffset);
end

NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -28dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -24dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -20dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -16dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -12dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -8dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at -4dB SNR
NPDSCH BLER = 1.0000
NPDSCH Throughput(%) = 0.0000 %

Simulating 4 transport blocks at 0dB SNR
NPDSCH BLER = 0.0000
NPDSCH Throughput(%) = 100.0000 %

2-344

 NB-IoT NPUSCH Block Error Rate Simulation

NB-IoT NPUSCH Block Error Rate Simulation

This example shows how to create an NB-IoT Narrowband Physical Uplink Shared Channel
(NPUSCH) Block Error Rate (BLER) simulation in frequency-selective fading and Additive White
Gaussian Noise (AWGN) using LTE Toolbox™.

Introduction

3GPP introduced a new air interface, Narrowband IoT (NB-IoT), optimized for low data rate machine-
type communications in LTE-Advanced Pro Release 13. NB-IoT provides cost and power efficiency
improvements as it avoids the need for complex signaling overhead required for LTE-based systems.

The example generates an NB-IoT NPUSCH BLER curve for a number of SNR points and
transmission parameters. NPUSCH and narrowband demodulation reference signal (DRS) are
transmitted in all slots. Operating on a slot-by-slot basis for each SNR point, the BLER calculation
comprises these steps:

• Generate a resource grid and populate it with NPUSCH symbols

• Create the baseband waveform by SC-FDMA modulating the grid

• Pass the waveform through a noisy fading channel

• Perform receiver operations (SC-FDMA demodulation, channel estimation, and equalization)

• Obtain the block CRC by decoding the equalized symbols

• Determine the performance of the NPUSCH by using the block CRC result at the output of the

channel decoder

Simulation Configuration

The simulation length is 5 UL-SCH transport blocks for a number of SNR points SNRdB for different
repetitions simReps. To produce meaningful throughput results, you should use a larger number of
transport blocks (numTrBlks). SNRdB and simReps can be a specified as a scalar or a numeric array.

numTrBlks = 5;              % Number of simulated transport blocks
SNRdB = [-20 -18 -15 -12.5 -10 -6.4 -3.5 0.7];  % Range of SNR values in dB
simReps = [2 16 64];        % Repetitions to simulate

NPUSCH Configuration

In this section we configure the parameters required for NPUSCH generation. There are two types of
payload defined for NPUSCH transmission, format 1 ('Data') and format 2 ('Control'). For format 1,
the UE uses the combination of modulation and coding scheme (MCS) and resource assignment
signaled via the DCI to determine the transport block size from the set defined in TS 36.213 Table
16.5.1.2-2. For format 2, the NPUSCH carries the 1 bit ACK/NACK. The chs.NPUSCHFormat
parameter specifies the format and infoLen specifies the transport block length. The parameters
used in this example are as per the A16-5 FRC defined in TS 36.104 Annex A.16.

HARQ Operation NB-IoT has one or two UL HARQ processes and HARQ operation is asynchronous
for NB-IoT UEs except for the repetitions within a bundle. Bundling operation relies on the HARQ
entity for invoking the same HARQ process for each transmission that is part of the same bundle.
Within a bundle, HARQ retransmissions are non-adaptive. They are triggered without waiting for
feedback from the reception of previous repetitions. An uplink grant corresponding to a new
transmission or a retransmission of the bundle is only received after the last repetition of the bundle.

2-345

2 Examples and Demos

A retransmission of a bundle is also a bundle. For more details, see TS 36.321 section 5.4.2. In this
example the bundle retransmissions are not modeled.

ue = struct();                        % Initialize the UE structure
ue.NBULSubcarrierSpacing = '15kHz';   % 3.75kHz, 15kHz
ue.NNCellID = 10;                     % Narrowband cell identity

chs = struct();
chs.NPUSCHFormat = 'Data';        % NPUSCH payload type ('Data' or 'Control')
% The number of subcarriers used for NPUSCH 'NscRU' depends on the NPUSCH
% format and subcarrier spacing 'NBULSubcarrierSpacing' as shown in TS 36.211
% Table 10.1.2.3-1. There are 1,3,6 or 12 continuous subcarriers for NPUSCH
chs.NBULSubcarrierSet = 0:11;     % Range is 0-11 (15kHz); 0-47 (3.75kHz)
chs.NRUsc = length(chs.NBULSubcarrierSet);
% The symbol modulation depends on the NPUSCH format and NscRU as given by
% TS 36.211 Table 10.1.3.2-1
chs.Modulation = 'QPSK';
chs.CyclicShift = 0;        % Cyclic shift required when NRUsc = 3 or 6
chs.RNTI = 20;              % RNTI value
chs.NLayers = 1;            % Number of layers
chs.NRU = 1;                % Number of resource units
chs.SlotIdx = 0;            % The slot index
chs.NTurboDecIts = 5;       % Number of turbo decoder iterations
chs.CSI = 'On';             % Use channel CSI in PUSCH decoding

% RV offset signaled via DCI (See 36.213 16.5.1.2)
rvDCI = 0;
% Calculate the RVSeq used according to the RV offset
rvSeq = [2*mod(rvDCI+0,2)  2*mod(rvDCI+1,2)];

if strcmpi(chs.NPUSCHFormat,'Data')
    infoLen = 136;   % Transport block size for NPUSCH format 1
elseif strcmpi(chs.NPUSCHFormat,'Control')
    infoLen = 1;    % ACK/NACK bit for NPUSCH format 2
end

Propagation Channel Model Configuration

The structure channel contains the channel model configuration parameters.

channel = struct;                    % Initialize channel config structure
channel.Seed = 6;                    % Channel seed
channel.NRxAnts = 2;                 % 2 receive antennas
channel.DelayProfile ='ETU';         % Delay profile
channel.DopplerFreq = 1;             % Doppler frequency in Hz
channel.MIMOCorrelation = 'Low';     % Multi-antenna correlation
channel.NTerms = 16;                 % Oscillators used in fading model
channel.ModelType = 'GMEDS';         % Rayleigh fading model type
channel.InitPhase = 'Random';        % Random initial phases
channel.NormalizePathGains = 'On';   % Normalize delay profile power
channel.NormalizeTxAnts = 'On';      % Normalize for transmit antennas

Channel Estimator Configuration

In this example, the parameter perfectChannelEstimator controls channel estimator behavior.
Valid values are true or false. When set to true, a perfect channel estimator is used. Otherwise a
practical estimator is used, based on the values of the received NPUSCH DRS.

2-346

 NB-IoT NPUSCH Block Error Rate Simulation

% Channel estimator behavior
perfectChannelEstimator = true;

The structure cec configures the practical channel estimator. An ETU delay profile with 1Hz Doppler
causes the channel to change slowly over time. To ensure averaging over all subcarriers for the
resource block, set the frequency window to 23 Resource Elements (REs). The variable
channelEstimationLength configures the number of slots over which channel estimates are
averaged, see TS 36.104 Table A.16.1-1 for suggested values for different NPUSCH configurations.

% Configure channel estimator
cec.PilotAverage = 'UserDefined';   % Type of pilot symbol averaging
cec.TimeWindow = 1;                 % Time window size in REs
cec.FreqWindow = 23;                % Frequency window size in REs
cec.InterpType = 'Cubic';           % 2D interpolation type
channelEstimationLength = 1;        % Channel estimation length in ms

For DRS signals in NPUSCH format 1, sequence-group hopping can be enabled or disabled by the
higher layer cell-specific parameter groupHoppingEnabled. Sequence-group hopping for a
particular UE can be disabled through the higher layer parameter groupHoppingDisabled as
described in TS 36.211 Section 10.1.4.1.3. In this example, we use the SeqGroupHopping parameter
to enable or disable sequence-group hopping

chs.SeqGroupHopping = 'on'; % Enable/Disable Sequence-Group Hopping for UE
chs.SeqGroup = 0;           % Higher-layer parameter groupAssignmentNPUSCH

% Get number of time slots in a resource unit NULSlots according to
% TS 36.211 Table 10.1.2.3-1
if strcmpi(chs.NPUSCHFormat,'Data')
    if chs.NRUsc == 1
        NULSlots = 16;
    elseif any(chs.NRUsc == [3 6 12])
        NULSlots = 24/chs.NRUsc;
    else
        error('Invalid number of subcarriers. NRUsc must be one of 1,3,6,12');
    end
elseif strcmpi(chs.NPUSCHFormat,'Control')
    NULSlots = 4;
else
    error('Invalid NPUSCH Format (%s). NPUSCHFormat must be ''Data'' or ''Control''',chs.NPUSCHFormat);
end
chs.NULSlots = NULSlots;

Block Error Rate Simulation Loop

To perform NB-IoT NPUSCH link level simulation and plot BLER results for a number of repetition
levels, this example performs the following steps:

For NPUSCH format 1 transmission for UL data transfer:

• Generate a random stream of bits with the size of the desired transport block

• Perform CRC encoding, turbo encoding and rate matching to create the NPUSCH bits

• Interleave the bits per resource unit to apply a time-first mapping and create the NPUSCH

codeword

For NPUSCH format 2 used for signaling HARQ feedback for NPDSCH:

2-347

2 Examples and Demos

• Perform bit repetition of the HARQ indicator to create the NPUSCH codeword

Then for either NPUSCH format:

• Perform scrambling, modulation, layer mapping and precoding on the codeword to form the

complex NPUSCH symbols

• Map the NPUSCH symbols and the corresponding DRS to the resource grid

• Generate the time domain waveform by performing SC-FDMA modulation of the resource grid

• Pass the waveform through a fading channel with AWGN

• Recover the transmitted grid by performing synchronization, channel estimation and MMSE

equalization

• Extract the NPUSCH symbols

• Recover the transport block by demodulating the symbols and channel decoding the resulting bit

estimates

Note that if practical channel estimation is configured (perfectChannelEstimator = false),
practical timing estimation based on NPUSCH DRS correlation will also be performed. The timing
offset is initialized to zero, intended to represent the initial synchronization after NPRACH reception.
The timing estimate is then updated whenever the peak of the NPUSCH DRS correlation is
sufficiently strong.

After de-scrambling, the repetitive slots are soft-combined before rate recovery. The transport block
error rate is calculated for each SNR point. The evaluation of the block error rate is based on the
assumption that all the slots in a bundle are used to decode the transport block at the UE. A bundle is
defined in the MAC layer (see 3GPP TS 36.321 5.4.2.1) as the NPUSCH.NRU
NPUSCH.NRep slots used to carry a transport block.

 NPUSCH.NULSlots

% Get the slot grid and number of slots per frame
emptySlotGrid = lteNBResourceGrid(ue); % Initialize empty slot grid
slotGridSize = size(emptySlotGrid);
NSlotsPerFrame = 20/(slotGridSize(1)/12);

tSlot = 10e-3/NSlotsPerFrame; % Slot duration
symbolsPerSlot = slotGridSize(2); % Number of symbols per slot

% Get a copy of the configuration variables ue, chs and channel to create
% independent simulation parfor loops
ueInit = ue;
chsInit = chs;
channelInit = channel;

for repIdx = 1:numel(simReps)

    chsInit.NRep = simReps(repIdx); % Number of repetitions of the NPUSCH
    NSlotsPerBundle = chsInit.NRU*chsInit.NULSlots*chsInit.NRep; % Number of slots in a codeword bundle
    TotNSlots = numTrBlks*NSlotsPerBundle;   % Total number of simulated slots

    % Initialize BLER and throughput result
    maxThroughput = zeros(length(SNRdB),1);
    simThroughput = zeros(length(SNRdB),1);
    bler = zeros(1,numel(SNRdB)); % Initialize BLER result

    for snrIdx = 1:numel(SNRdB)

2-348

 NB-IoT NPUSCH Block Error Rate Simulation

    % parfor snrIdx = 1:numel(SNRdB)
    % To enable the use of parallel computing for increased speed comment out
    % the 'for' statement above and uncomment the 'parfor' statement below.
    % This needs the Parallel Computing Toolbox (TM). If this is not installed
    % 'parfor' will default to the normal 'for' statement.

        % Set the random number generator seed depending on the loop variable
        % to ensure independent random streams
        rng(snrIdx,'combRecursive');

        ue = ueInit;    % Initialize ue configuration
        chs = chsInit;  % Initialize chs configuration
        channel = channelInit; % Initialize fading channel configuration
        numBlkErrors = 0;  % Number of transport blocks with errors
        estate = struct('SlotIdx',chs.SlotIdx);  % Initialize NPUSCH encoder state
        dstate = estate;   % Initialize NPUSCH decoder state
        offset = 0;        % Initialize overall frame timing offset
        trblk = [];        % Initialize the transport block
        npuschHest = [];   % Initialize channel estimate
        noiseEst = [];     % Initialize noise estimate

        % Display the number of slots being generated
        fprintf('\nGenerating %d slots corresponding to %d transport block(s) at %gdB SNR\n',TotNSlots,numTrBlks,SNRdB(snrIdx));

        for slotIdx = 0+(0:TotNSlots-1)
            % Calculate the frame number and slot number within the frame
            ue.NFrame = fix(slotIdx/NSlotsPerFrame);
            ue.NSlot = mod(slotIdx,NSlotsPerFrame);
            % Create the slot grid
            slotGrid = emptySlotGrid;

            if isempty(trblk)

               % Initialize transport channel decoder state
               dstateULSCH = [];

               if strcmpi(chs.NPUSCHFormat,'Data')
                   % UL-SCH encoding is performed for the two RV values used for
                   % transmitting the codewords. The RV sequence used is determined
                   % from the rvDCI value signaled in the DCI and alternates
                   % between 0 and 2 as given in TS 36.213 Section 16.5.1.2

                   % Define the transport block which will be encoded to create the
                   % codewords for different RV
                   trblk = randi([0 1],infoLen,1);

                   % Determine the coded transport block size
                   [~, info] = lteNPUSCHIndices(ue,chs);
                   outblklen = info.G;
                   % Create the codewords corresponding to the two RV values used
                   % in the first and second block, this will be repeated till all
                   % blocks are transmitted
                   chs.RV = rvSeq(1); % RV for the first block
                   cw = lteNULSCH(chs,outblklen,trblk); % CRC and Turbo coding is repeated
                   chs.RV = rvSeq(2); % RV for the second block
                   cw = [cw lteNULSCH(chs,outblklen,trblk)]; %#ok<AGROW> % CRC and Turbo coding is repeated
               else
                   trblk = randi([0 1],1); % 1 bit ACK

2-349

2 Examples and Demos

                   % For ACK, the same codeword is transmitted every block as
                   % defined in TS 36.212 Section 6.3.3
                   cw = lteNULSCH(trblk);
               end
               blockIdx = 0; % First block to be transmitted
            end

            % Copy SlotIdx for the SCFDMA modulator
            chs.SlotIdx = estate.SlotIdx;

            % Set the RV used for the current transport block
            chs.RV = rvSeq(mod(blockIdx,size(rvSeq,2))+1);

            % NPUSCH encoding and mapping onto the slot grid
            txsym = lteNPUSCH(ue,chs,cw(:,mod(blockIdx,size(cw,2))+1),estate);
            slotGrid(lteNPUSCHIndices(ue,chs)) = txsym;

            % NPUSCH DRS and mapping on to the slot grid
            [dmrs,estate] = lteNPUSCHDRS(ue,chs,estate);
            slotGrid(lteNPUSCHDRSIndices(ue,chs)) = dmrs;

            % If a full block is transmitted, increment the clock counter so that
            % the correct codeword can be selected
            if estate.EndOfBlk
                blockIdx = blockIdx + 1;
            end

            % Perform SC-FDMA modulation to create the time domain waveform
            [txWaveform,scfdmaInfo] = lteSCFDMAModulate(ue,chs,slotGrid);

            % Add 25 sample padding. This is to cover the range of delays
            % expected from channel modeling (a combination of
            % implementation delay and channel delay spread)
            txWaveform =  [txWaveform; zeros(25, size(txWaveform,2))]; %#ok<AGROW>

            % Initialize channel time for each slot
            channel.InitTime = slotIdx*tSlot;

            % Pass data through channel model
            channel.SamplingRate = scfdmaInfo.SamplingRate;
            [rxWaveform,fadingInfo] = lteFadingChannel(channel, txWaveform);

            % Calculate noise gain
            SNR = 10^(SNRdB(snrIdx)/10);

            % Normalize noise power to take account of sampling rate, which is
            % a function of the IFFT size used in SC-FDMA modulation
            N0 = 1/sqrt(2.0*double(scfdmaInfo.Nfft)*SNR);

            % Create additive white Gaussian noise
            noise = N0*complex(randn(size(rxWaveform)), ...
                                randn(size(rxWaveform)));

            % Add AWGN to the received time domain waveform
            rxWaveform = rxWaveform + noise;

            %------------------------------------------------------------------
            %            Receiver

2-350

 NB-IoT NPUSCH Block Error Rate Simulation

            %------------------------------------------------------------------

            % Perform timing synchronization, extract the appropriate
            % subframe of the received waveform, and perform SC-FDMA
            % demodulation
            if (perfectChannelEstimator)
                offset = hPerfectTimingEstimate(fadingInfo);
            else
                [t,mag] = lteULFrameOffsetNPUSCH(ue, chs, rxWaveform, dstate);
                % The function hSkipWeakTimingOffset is used to update the
                % receiver timing offset. If the correlation peak in 'mag'
                % is weak, the current timing estimate 't' is ignored and
                % the previous estimate 'offset' is used
                offset = hSkipWeakTimingOffset(offset,t,mag);
            end

            % Synchronize the received waveform
            rxWaveform = rxWaveform(1+offset:end, :);

            % Perform SC-FDMA demodulation on the received data to recreate
            % the resource grid, including padding in the event that
            % practical synchronization results in an incomplete slot being
            % demodulated
            rxSlot = lteSCFDMADemodulate(ue,chs,rxWaveform);
            [K,L,R] = size(rxSlot);
            if (L < symbolsPerSlot)
                rxSlot = cat(2,rxSlot,zeros(K,symbolsPerSlot-L,R));
            end

            % Channel estimation
            if (perfectChannelEstimator)
                % Perfect channel estimation
                ue.TotSlots = 1; % Channel estimate for 1 slot
                estChannelGrid = lteULPerfectChannelEstimate(ue, chs, channel, offset);
                noiseGrid = lteSCFDMADemodulate(ue,chs,noise(1+offset:end ,:));
                noiseEstSlot = var(noiseGrid(:));
            else
                [estChannelGrid, noiseEstSlot] = lteULChannelEstimateNPUSCH(ue, chs, cec, rxSlot, dstate);
            end

            % Get NPUSCH indices
            npuschIndices = lteNPUSCHIndices(ue,chs);

            % Get NPUSCH resource elements from the received slot
            [rxNpuschSymbols, npuschHestSlot] = lteExtractResources(npuschIndices, ...
                rxSlot, estChannelGrid);

            % Perform channel estimate and noise estimate buffering in
            % the case of practical channel estimation
            if (perfectChannelEstimator)
                npuschHest = npuschHestSlot;
                noiseEst = noiseEstSlot;
            else
                npuschHest = cat(3,npuschHest,npuschHestSlot);
                noiseEst = cat(1,noiseEst,noiseEstSlot);
                if (size(npuschHest,3) > channelEstimationLength)
                    npuschHest = npuschHest(:,:,2:end);
                    noiseEst = noiseEst(2:end);

2-351

2 Examples and Demos

                end
            end

            % Decode NPUSCH
            [rxcw,dstate,symbols] = lteNPUSCHDecode(...
                                 ue, chs, rxNpuschSymbols, mean(npuschHest,3), mean(noiseEst),dstate);

            % Decode the transport block when all the slots in a block have
            % been received
            if dstate.EndOfBlk
                % Soft-combining at transport channel decoder
                [out, err, dstateULSCH] = lteNULSCHDecode(chs,infoLen,rxcw,dstateULSCH);
            end

            % If all the slots in the bundle have been received, count the
            % errors and reinitialize for the next bundle
            if dstate.EndOfTx
               if strcmpi(chs.NPUSCHFormat,'Control')
                   err = ~isequal(out,trblk);
               end
               numBlkErrors = numBlkErrors + err;
               % Re-initialize to enable the transmission of a new transport
               % block
               trblk = [];
            end
        end
        % Calculate the block error rate
        bler(snrIdx) = numBlkErrors/numTrBlks;
        fprintf('NPUSCH BLER = %.4f \n',bler(snrIdx));
        % Calculate the maximum and simulated throughput
        maxThroughput(snrIdx) = infoLen*numTrBlks; % Max possible throughput
        simThroughput(snrIdx) = infoLen*(numTrBlks-numBlkErrors);  % Simulated throughput
        fprintf('NPUSCH Throughput(%%) = %.4f %%\n',simThroughput(snrIdx)*100/maxThroughput(snrIdx));

    end

    % Plot Block Error Rate vs SNR Results
    if repIdx == 1
        figure;
        grid on;
        hold on;
        xlabel('SNR (dB)');
        ylabel('BLER');
        legendstr = {['NRep = ' num2str(chsInit.NRep)]};
    else
        legendstr = [legendstr ['NRep = ' num2str(chsInit.NRep)]]; %#ok<AGROW>
    end
    plot(SNRdB, bler, '-o');

end
% Set figure title
title(sprintf(' NPUSCH Carrying %s: NRUsc = %d, NRU = %d, TBS = %d',...
    chsInit.NPUSCHFormat,chsInit.NRUsc,chsInit.NRU,infoLen));
legend(legendstr);

Generating 20 slots corresponding to 5 transport block(s) at -20dB SNR
NPUSCH BLER = 1.0000

2-352

 NB-IoT NPUSCH Block Error Rate Simulation

NPUSCH Throughput(%) = 0.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -18dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -15dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -12.5dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -10dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -6.4dB SNR
NPUSCH BLER = 0.4000
NPUSCH Throughput(%) = 60.0000 %

Generating 20 slots corresponding to 5 transport block(s) at -3.5dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 20 slots corresponding to 5 transport block(s) at 0.7dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -20dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -18dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -15dB SNR
NPUSCH BLER = 0.6000
NPUSCH Throughput(%) = 40.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -12.5dB SNR
NPUSCH BLER = 0.2000
NPUSCH Throughput(%) = 80.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -10dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -6.4dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 160 slots corresponding to 5 transport block(s) at -3.5dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

2-353

2 Examples and Demos

Generating 160 slots corresponding to 5 transport block(s) at 0.7dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -20dB SNR
NPUSCH BLER = 1.0000
NPUSCH Throughput(%) = 0.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -18dB SNR
NPUSCH BLER = 0.6000
NPUSCH Throughput(%) = 40.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -15dB SNR
NPUSCH BLER = 0.2000
NPUSCH Throughput(%) = 80.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -12.5dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -10dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -6.4dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 640 slots corresponding to 5 transport block(s) at -3.5dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

Generating 640 slots corresponding to 5 transport block(s) at 0.7dB SNR
NPUSCH BLER = 0.0000
NPUSCH Throughput(%) = 100.0000 %

2-354

 NB-IoT NPUSCH Block Error Rate Simulation

A larger number of transport blocks, numTrBlks should be used to produce meaningful throughput
results. The following plot shows the simulation run with numTrBlks set to 5000 for different
repetitions, with perfect channel estimator.

2-355

2 Examples and Demos

Selected Bibliography

1

2

3

4

5

6

7

3GPP TS 36.211 "Physical channels and modulation"

3GPP TS 36.212 "Multiplexing and channel coding"

3GPP TS 36.213 "Physical layer procedures"

3GPP TS 36.104 "Base Station (BS) radio transmission and reception"

3GPP TS 36.321 "Medium Access Control (MAC); Protocol specification"

3GPP TS 36.331 "Radio Resource Control (RRC); Protocol specification"

3GPP TS 36.300 "Overall description; Stage 2"

8 O. Liberg, M. Sundberg, Y.-P. Wang, J. Bergman and J. Sachs, Cellular Internet of Things:

Technologies, Standards and Performance, Elsevier, 2018.

Helper Functions

The following helper functions are used in this example:

• hPerfectTimingEstimate.m

• hSkipWeakTimingOffset.m

2-356

 NB-IoT PRACH Waveform Generation

NB-IoT PRACH Waveform Generation

This example shows how to generate LTE-Advanced Pro Release 15 narrowband internet of things
(NB-IoT) waveforms consisting of the narrowband physical random access channel (NPRACH).

Introduction

3GPP introduced a new air interface, NB-IoT, optimized for low data rate machine type
communications in LTE-Advanced Pro Release 13. NB-IoT provides cost and power efficiency
improvements as it avoids the need for complex signaling overhead required for other LTE-based
systems.

You can use LTE Toolbox to generate standard compliant NB-IoT uplink complex baseband
waveforms, representing the 180 kHz narrowband carrier, suitable for test and measurement
applications. The NB-IoT uplink physical layer channels and signals are:

• Narrowband demodulation reference signal (DM-RS)

• Narrowband physical uplink shared channel (NPUSCH)

• Narrowband physical random access channel (NPRACH)

In this example, we demonstrate NPRACH allocation in the resource grid and the generation of
NPRACH waveforms, as defined in TS 36.211 Section 10.1.6 [ 1 on page 2-360 ].

NPRACH Allocation

This section provides an overall description of the NPRACH allocation in time and frequency.

From a time point of view, an NPRACH transmission is defined as NRep repetitions of NPRACH
preambles, in which an NPRACH preamble is defined as a set of P symbol groups. TS 36.211 Section
10.1.6.1 defines a symbol group as a sequence of N identical symbols preceded by a cyclic prefix. For
this reason, the symbol group, rather than the OFDM symbol, can be considered as the atomic unit of
NPRACH. The duration of an NPRACH symbol group is a function of the preamble format, as
described in TS 36.211 Table 10.1.6.1-1 for frequency-division duplexing (FDD) and Table 10.1.6.1-2
for time-division duplexing (TDD). This figure shows a schematic of the symbol groups for the three
NPRACH preamble formats for FDD.

From a frequency point of view, the NPRACH is characterized by single-tone transmission with
frequency hopping and a subcarrier spacing defined in TS 36.211 Table 10.1.6.2-1. Each symbol
group occupies a single subcarrier, following the frequency hopping pattern described in TS 36.211
Section 10.1.6.1. SubcarrierOffset defines the frequency location of the first subcarrier allocated

2-357

2 Examples and Demos

to NPRACH. NumSubcarriers defines the total number of subcarriers allocated to NPRACH. Among
those, the subcarrier location of the first symbol group of the first preamble is determined by NInit.
For all subsequent preambles, the frequency of the first symbol group of each NPRACH preamble
depends on the pseudorandom sequence defined in TS 36.211 Section 7.2 and initialized by
NNCellID. This figure shows a schematic of the frequency hopping pattern for the first two
repetitions of preamble format 0 for FDD, given the default NPRACH configuration used in this
example. You can see that the first symbol groups of the two preambles occupy different subcarriers.

NPRACH Configuration

In this section, we configure the parameters required for NPRACH generation. For a list of all the
allowed ranges for the parameters in the ue and chs structures, see lteNPRACH.

2-358

 NB-IoT PRACH Waveform Generation

% Define the user equipment (UE) parameters
ue = struct();
ue.NBULSubcarrierSpacing = '15kHz'; % Uplink subcarrier spacing ('3.75kHz', '15kHz')
ue.NNCellID = 0;                    % Narrowband cell identity
ue.Windowing = 0;                   % Number of time-domain samples over which the function applies windowing and overlapping of OFDM symbols.
                                    % Set Windowing to empty ([]) to use its default value.
ue.DuplexMode = 'FDD';              % Duplex mode ('FDD' or 'TDD')
if strcmpi(ue.DuplexMode,'TDD')
    ue.TDDConfig = 1;               % TDD configuration. For a list of all supported TDD configurations for a given NPRACH format, see TS 36.211 Table 10.1.6.1-2
end

% Define the channel parameters
chs = struct();
chs.NPRACHFormat = '0';    % Preamble format ('0','1','2' for FDD, '0','1','2','0-a','1-a' for TDD)
chs.Periodicity = 80;      % NPRACH resource periodicity in ms
chs.SubcarrierOffset = 12; % Frequency location of the first subcarrier allocated to NPRACH
chs.NumSubcarriers = 24;   % Number of subcarriers allocated to NPRACH
chs.NRep = 8;              % Number of NPRACH repetitions
if strcmpi(ue.DuplexMode,'FDD')
    chs.StartTime = 8;     % NPRACH starting time in ms (8,16,32,64,128,256,512,1024)
else % TDD
    chs.StartTime = 10;    % NPRACH starting time in ms (10,20,40,80,160,320,640,1280,2560,5120)
end
chs.NInit = 2;             % Initial subcarrier for NPRACH
chs.NPRACHPower = 30;      % NPRACH power scaling in dB for plot visualization

NB-IoT PRACH Waveform Generation

In this section, we create the NPRACH resource grid and the time-domain waveform. The example
generates a waveform that spans chs.Periodicity milliseconds and is sampled with the same
sample rate used for the uplink signals with subcarrier spacing given by
ue.NBULSubcarrierSpacing.

[waveform,info,resourceGrid] = lteNPRACH(ue,chs);

Plot Transmitted Grid

Plot the NPRACH resource grid. You can observe the frequency hopping pattern of the NPRACH
symbols. Note that the resource grid plot uses the power levels of the NPRACH to assign colors to the
resource elements. To disable the plot of the resource grid, set the value of displayGrid to 'off'.

displayGrid = 'on'; % Display the NPRACH resource grid ('on','off')
hNPRACHResourceGridPlot(chs,resourceGrid,displayGrid);

2-359

2 Examples and Demos

Summary and Further Exploration

This example shows how to generate a time-domain waveform and visualize the resource grid for a
single NB-IoT PRACH configuration. The generated NPRACH waveform spans chs.Periodicity
milliseconds and is sampled with the same sample rate used for the uplink signals with subcarrier
spacing given by ue.NBULSubcarrierSpacing. This allows you to generate an NPRACH waveform
and add it to an existing NB-IoT uplink waveform. For more information about the generation of an
NB-IoT uplink waveform, see “NB-IoT Uplink Waveform Generation” on page 2-304.

Selected Bibliography

1

3GPP TS 36.211. "Physical channels and modulation", 3rd Generation Partnership Project;
Technical Specification Group Radio Access Network.

Local Functions

This example uses this local function:

function hNPRACHResourceGridPlot(chs,resourceGrid,displayGrid)
%hNPRACHResourceGridPlot Plots the NPRACH resource grid
%   hNPRACHResourceGridPlot(CHS,RESOURCEGRID,DISPLAYGRID) plots the NPRACH
%   resource grid. Set DISPLAYGRID to 'off' to disable the plot of the
%   resource grid.

    if strcmpi(displayGrid,'on')
        figure

        % Create an image of the NPRACH resource grid
        im = image(resourceGrid);

        % Adjust plot colors, axes, and add title and labels

2-360

 NB-IoT PRACH Waveform Generation

        cmap = parula(64);
        colormap(im.Parent,cmap);
        axis xy;
        xlabel('OFDM symbols')
        ylabel('Subcarriers')
        title(sprintf('NB-IoT PRACH RE Grid (Format = ''%s'')',chs.NPRACHFormat))

    end
end

2-361

2 Examples and Demos

NB-IoT PRACH Detection and False Alarm Conformance Test

This example implements the narrowband physical random access channel (NPRACH) missed
detection and false alarm conformance tests for frame structure type 1, as defined in TS 36.141. You
can measure the probability of correct detection of the NPRACH preamble in the presence of a
preamble signal or switch the NPRACH transmission off to measure the false alarm probability.

Introduction

The NPRACH is a narrowband internet of things (NB-IoT) uplink transmission used by the user
equipment (UE) to initiate synchronization with the eNodeB. Section 8.5.3 of TS 36.141 defines that
the probability of NPRACH detection must be greater than or equal to 99% at the SNR levels listed in
Table 8.5.3.5-1 for several combinations of preamble format, number of repetitions, and channel
propagation conditions. There are several detection error cases:

• Detecting an incorrect preamble

• Not detecting a preamble

• Detecting the correct preamble but with the wrong timing estimation

TS 36.141 states that a correct detection is achieved when the estimation error of the timing offset of
the strongest path is less than 3.646 microseconds.

In this example, an NPRACH waveform is configured and passed through an appropriate channel. At
the receiver side, the example performs NPRACH detection and calculates the NPRACH detection
probability. The example considers the parameters defined in Table 8.5.3.1-1 and Table 8.5.3.5-1 of TS
36.141. These are: frequency-division duplexing (FDD), 2 receive antennas, 8 repetitions, EPA1
channel, preamble format 0, SNR 6.7 dB. If you change the simulation scenario to use one of the
other NPRACH preamble formats, propagation channel, or number of repetitions listed in Table
8.5.3.5-1, you need to update the NPRACH configuration according to Table 8.5.3.1-1 and you need to
update the values of the frequency offset and the SNR according to Table 8.5.3.5-1.

Simulation Configuration

The example considers 10 NPRACH transmissions at a number of SNRs. You should use a large
number of numNPRACHTransmissions to produce meaningful results. You can set SNRdB as an array
of values or a scalar. Table 8.5.3.5-1 of TS 36.141 specifies the frequency offset foffset that is
modeled between the transmitter and receiver. The timeErrorTolerance variable specifies the
time error tolerance, as defined in Section 8.5.3.1 of TS 36.141. You can set the detection threshold to
a value in the range [0,1] or to empty to use the default value in the lteNPRACHDetect function. To
simulate a false alarm test, disable the NPRACH transmission by setting nprachEnabled to false
instead.

numNPRACHTransmissions = 10;         % Number of NPRACH transmissions to simulate at each SNR
SNRdB = [-5.3 -2.3 0.7 3.7 6.7 9.7]; % SNR range in dB
foffset = 200.0;                     % Frequency offset in Hz
timeErrorTolerance = 3.646;          % Time error tolerance in microseconds
threshold = [];                      % Detection threshold
nprachEnabled = true;                % Enable NPRACH transmission. To simulate false alarm test, disable NPRACH transmission.

UE Configuration

UE settings are specified in the structure ue.

2-362

 NB-IoT PRACH Detection and False Alarm Conformance Test

ue.NBULSubcarrierSpacing = '15kHz'; % Uplink subcarrier spacing ('3.75kHz', '15kHz')
ue.NNCellID = 0;                    % Narrowband cell identity
ue.Windowing = 0;                   % Windowing samples

NPRACH Configuration

Table 8.5.3.1-1 of TS 36.141 specifies the NPRACH configurations to use for the NPRACH detection
conformance test.

Set the NPRACH configuration structure nprach and compute the NPRACH resource information
nprachInfo by calling lteNPRACHInfo.

nprach = struct();
nprach.NPRACHFormat = '0';    % Preamble format ('0','1','2')
nprach.Periodicity = 80;      % Resource periodicity in ms
nprach.SubcarrierOffset = 0;  % Frequency location of the first allocated subcarrier
nprach.NumSubcarriers = 12;   % Number of allocated subcarriers
nprach.NRep = 8;              % Number of repetitions
nprach.StartTime = 8;         % Starting time in ms
nprach.NInit = 0;             % Initial subcarrier
nprach.NPRACHPower = 0;       % Power scaling in dB

nprachInfo = lteNPRACHInfo(ue,nprach); % NPRACH resource information

Propagation Channel Configuration

Configure the propagation channel model using the chcfg structure as described in Table 8.5.3.5-1
of TS 36.141.

chcfg.NRxAnts = 2;                            % Number of receive antennas
chcfg.DelayProfile = 'EPA';                   % Delay profile
chcfg.DopplerFreq = 1;                        % Doppler frequency
chcfg.MIMOCorrelation = 'Low';                % MIMO correlation
chcfg.Seed = 42;                              % Channel seed. Change this for different channel realizations
chcfg.NTerms = 16;                            % Oscillators used in fading model
chcfg.ModelType = 'GMEDS';                    % Rayleigh fading model type
chcfg.InitPhase = 'Random';                   % Random initial phases
chcfg.NormalizePathGains = 'On';              % Normalize delay profile power
chcfg.NormalizeTxAnts = 'On';                 % Normalize for transmit antennas
chcfg.SamplingRate = nprachInfo.SamplingRate; % Sampling rate

% Compute the maximum channel delay
chcfg.InitTime = 0;
[~,chInfo] = lteFadingChannel(chcfg,0); % Get channel info
maxChDelay = ceil(max(chInfo.PathSampleDelays)) + chInfo.ChannelFilterDelay;

Loop for SNR Values

Use a loop to run the simulation for the set of SNR points given by the vector SNRdB. The SNR vector
configured here is a range of SNR points including a point at 6.7 dB, the SNR at which the test
requirement for NPRACH detection rate (99%) is to be achieved for preamble format 0, as discussed
in Table 8.5.3.5-1 of TS 36.141.

lteNPRACH generates an output signal normalized to the same transmit power as for an uplink data
transmission within the LTE Toolbox™. Therefore, the same normalization must take place on the
noise added to the NPRACH. The noise added before OFDM demodulation will be amplified by the
IFFT by a factor equal to the square root of the size of the IFFT (

). To ensure that the power of

2-363

2 Examples and Demos

the noise added is normalized after demodulation, and thus to achieve the desired SNR, the desired
noise power is divided by
separately before being combined into complex additive white Gaussian noise, the noise amplitude is

. In addition, as real and imaginary parts of the noise are created

scaled by

 so the generated noise power is 1.

At each SNR test point, calculate the probability of detection for each NPRACH transmission using
these steps:

• NPRACH Transmission: Use lteNPRACH to generate an NPRACH waveform. Send the NPRACH
preambles with a fixed timing offset of 50% of the number of cyclic shifts, as defined in Section
8.5.3.4.2 of TS 36.141.

• Noisy Channel Modeling: Pass the waveform through a fading channel and add additive white

Gaussian noise. Add additional samples to the end of the waveform to cover the range of delays
expected from the channel modeling (a combination of implementation delay and channel delay
spread). This implementation delay is then removed to ensure the implementation delay is not
interpreted as an actual timing offset in the preamble detector.

• Application of Frequency Offset: Apply the frequency offset to the received waveform as defined in

Table 8.5.3.5-1 of TS 36.141.

• NPRACH Detection: Perform NPRACH detection using the lteNPRACHDetect function for all

initial subcarrier indices NInit, each one of which uniquely defines an NPRACH preamble. Use
the detected NPRACH index and offset returned by lteNPRACHDetect to determine whether a
detection was successful according to the constraints discussed in the Introduction section.

% Initialize variables storing probability of detection at each SNR
pDetection = zeros(size(SNRdB));

% The temporary variables 'chcfg_init' and 'chInfo_init' are used to create
% the temporary variables 'chcfg' and 'chInfo' within the SNR loop to
% create independent instances in case of parallel simulation
chcfg_init = chcfg;
chInfo_init = chInfo;

for snrIdx = 1:length(SNRdB) % comment out for parallel computing
% parfor snrIdx = 1:numel(SNRdB) % uncomment for parallel computing
% To reduce the total simulation time, you can execute this loop in
% parallel by using the Parallel Computing Toolbox(TM). Comment out the
% 'for' statement and uncomment the 'parfor' statement. If the Parallel
% Computing Toolbox is not installed, 'parfor' defaults to normal 'for'
% statement

    % Display progress in the command window
    timeNow = char(datetime('now','Format','HH:mm:ss'));
    fprintf([timeNow,': Simulating SNR = %+5.1f dB...'],SNRdB(snrIdx));

    % Set the random number generator seed depending on the loop variable
    % to ensure independent random streams
    rng(snrIdx,'combRecursive');

    % Initialize variables for this SNR point, required for initialization
    % of variables when using the Parallel Computing Toolbox
    chcfg = chcfg_init;
    chInfo = chInfo_init;

2-364

 NB-IoT PRACH Detection and False Alarm Conformance Test

    % Normalize noise power to account for the sampling rate, which is a
    % function of the IFFT size used in OFDM modulation. The SNR is defined
    % per carrier resource element for each receive antenna.
    ueInfo = lteSCFDMAInfo(ue);
    SNR = 10^(SNRdB(snrIdx)/10);
    N0 = 1/sqrt(2.0*double(ueInfo.Nfft)*SNR);

    % Detected preamble count
    detectedCount = 0;

    % Loop for each NPRACH transmission
    for nprachIdx = 1:numNPRACHTransmissions

        % Generate NPRACH waveform
        waveform = generateWaveform(ue,nprach,nprachInfo,nprachEnabled);

        % Set NPRACH timing offset in microseconds as per Section 8.5.3.4.2 of TS 36.141
        timingOffset = 0.5*nprachInfo.PreambleParameters.T_CP/30720*1e3; % (microseconds)
        sampleDelay = fix(timingOffset/1e6*nprachInfo.SamplingRate);

        % Generate transmit waveform
        txwave = [zeros(sampleDelay,1); waveform];

        % Pass data through channel model
        rxwave = applyChannel(txwave,chcfg,nprachInfo.Nfft,nprach.Periodicity,nprachIdx,maxChDelay);

        % Add noise
        noise = N0*complex(randn(size(rxwave)),randn(size(rxwave)));
        rxwave = rxwave + noise;

        % Apply frequency offset
        t = ((0:size(rxwave,1) - 1)/chcfg.SamplingRate).';
        rxwave = rxwave.*repmat(exp(1i*2*pi*foffset*t),1,size(rxwave,2));

        % NPRACH detection for all frequency hopping patterns
        [detected,offset,detinfo] = lteNPRACHDetect(ue,nprach,rxwave,threshold);

        % Test for frequency hopping pattern detection
        if (length(detected)==1)
            if ~nprachEnabled
                % For the false alarm test, any preamble detected is wrong
                detectedCount = detectedCount + 1;
            else
                % Test for correct frequency hopping pattern detection
                if (detected==nprach.NInit)

                    % Calculate timing estimation error
                    trueOffset = timingOffset/1e6; % (s)
                    measuredOffset = offset/nprachInfo.SamplingRate;
                    timingerror = abs(measuredOffset - trueOffset);

                    % Test for acceptable timing error
                    if (timingerror<=(timeErrorTolerance/1e6))
                        detectedCount = detectedCount + 1; % Detected preamble
                    end
                end
            end

2-365

2 Examples and Demos

        end

    end % of NPRACH transmission loop

    % Compute final detection probability for this SNR
    pDetection(snrIdx) = detectedCount/numNPRACHTransmissions;

    % Display the detection probability for this SNR
    fprintf('Detection probability: %4.2f%%\n',pDetection(snrIdx)*100);

end % of SNR loop

18:44:05: Simulating SNR =  -5.3 dB...

Analysis

At the end of the SNR loop, the example plots the calculated detection probabilities for each SNR
value against the target probability.

targetSNR = 6.7;
NPRACHDetectionResults(pDetection,SNRdB,targetSNR,numNPRACHTransmissions,nprachEnabled);

References

1

3GPP TS 36.141. "Base Station (BS) conformance testing." 3rd Generation Partnership Project;
Technical Specification Group Radio Access Network; Evolved Universal Terrestrial Radio Access
(E-UTRA).

2-366

 NB-IoT PRACH Detection and False Alarm Conformance Test

2

3GPP TS 36.211. "Physical channels and modulation." 3rd Generation Partnership Project;
Technical Specification Group Radio Access Network; Evolved Universal Terrestrial Radio Access
(E-UTRA).

Local Functions

function waveform = generateWaveform(ue,nprach,nprachInfo,nprachEnabled)
    % Generate the waveform. If the NPRACH transmission is disabled, the
    % function generates a waveform of zeros.
    if nprachEnabled
        waveform = lteNPRACH(ue,nprach);
    else
        waveform = complex(zeros(nprach.Periodicity*nprachInfo.SamplingRate/1e3,1));
    end
end

function rxwave = applyChannel(txwave,chcfg,nFFT,periodicity,nprachIdx,maxChDelay)
    % Pass data through channel model

    % Resample the transmit waveform to speed up the channel
    nFFT_mod = nFFT/8;
    txwave = resample(txwave,nFFT_mod,nFFT);
    chcfg.SamplingRate = chcfg.SamplingRate*nFFT_mod/nFFT;

    % Pass data through channel model. Append zeros at the end of the
    % transmitted waveform to flush channel content. These zeros take into
    % account any delay introduced in the channel. This is a mix of
    % multipath delay and implementation delay. This value may change
    % depending on the sampling rate and delay profile.
    chcfg.InitTime = (nprachIdx - 1)*periodicity/1000;
    [rxwave,chInfo] = lteFadingChannel(chcfg,[txwave; zeros(ceil(maxChDelay*nFFT_mod/nFFT),1)]);

    % Remove the implementation delay of the channel filter
    rxwave = rxwave((chInfo.ChannelFilterDelay + 1):end,:);

    % Resample the receive waveform back to the original sampling rate
    rxwave = resample(rxwave,nFFT,nFFT_mod);
end

function NPRACHDetectionResults(pDetection,SNRdB,targetSNR,numNPRACHTransmissions,nprachEnabled)
    % Plot detection probability
    figure('NumberTitle','off','Name','NPRACH Detection Probability');
    plot(SNRdB,pDetection,'b-o','LineWidth',2,'MarkerSize',7);
    title(['Detection Probability for ',num2str(numNPRACHTransmissions),' NPRACH Transmission(s)']);
    xlabel('SNR (dB)'); ylabel('Detection Probability');
    grid on; hold on;

    % Plot target probability
    if nprachEnabled
        % For a missed detection test, detection probability should be >= 99%
        pTarget = 99;
    else
        % For a false alarm test, detection probability should be < 0.1%
        pTarget = 0.1;
    end
    plot(targetSNR,pTarget/100,'rx','LineWidth',2,'MarkerSize',7);
    legend('Simulation Result', ['Target ',num2str(pTarget),'% Probability'],'Location','best');

2-367

2 Examples and Demos

    minP = 0;
    if(~isnan(min(pDetection)))
        minP = min([pDetection(:); pTarget]);
    end
    axis([SNRdB(1)-0.1, SNRdB(end)+0.1, minP-0.05, 1.05]);
end

Detection probability: 60.00%
18:44:08: Simulating SNR =  -2.3 dB...Detection probability: 70.00%
18:44:10: Simulating SNR =  +0.7 dB...Detection probability: 90.00%
18:44:12: Simulating SNR =  +3.7 dB...Detection probability: 100.00%
18:44:14: Simulating SNR =  +6.7 dB...Detection probability: 100.00%
18:44:16: Simulating SNR =  +9.7 dB...Detection probability: 100.00%

See Also

Functions
lteNPRACH | lteNPRACHInfo

Related Examples
•

“NB-IoT PRACH Waveform Generation” on page 2-357

•

•

“PRACH False Alarm Probability Conformance Test” on page 2-585

“PRACH Detection Conformance Test” on page 2-580

2-368

 NB-IoT Cell Search and MIB Recovery

NB-IoT Cell Search and MIB Recovery

This example shows how the LTE Toolbox™ can be used to fully synchronize, demodulate and decode
a live narrowband internet of things (NB-IoT) downlink signal. Before the user equipment (UE) can
communicate with the network, it must perform cell search and selection procedures and obtain
initial system information. This involves acquiring slot and frame synchronization, finding out the cell
identity and decoding the MIB. This example demonstrates this process and decodes the MIB. To
decode MIB a comprehensive receiver is required, capable of demodulating and decoding the
downlink channels and signals.

Introduction

As NB-IoT is an extension of LTE infrastructure, the NB-IoT waveform has some similarities to that of
LTE. Similarities between these two include:

• Sub-carrier spacing (15kHz)

• Frame structure (10 subframes with 2 slots each)

• Frame duration (10 ms)

• Physical channels

However, the number of subcarriers in NB-IoT is fixed to 12 (one resource block), unlike in LTE,
where number of subcarriers vary with the bandwidth. Also, the physical channel mapping on the
resource grid of NB-IoT is different from that of LTE. For more information see “NB-IoT Downlink
Waveform Generation” on page 2-121.

In order to communicate with the network the UE must obtain some basic system information. This is
carried by the MIB and SIBs. The MIB carries the most essential system information:

• System frame number (SFN)

• Scheduling information of SIB1-NB

• Operation mode information for LTE-NB

• Access barring

The MIB is carried on the broadcast channel (BCH) mapped into the narrowband physical broadcast
channel (NPBCH) [ 1 ]. This is transmitted with a fixed coding and modulation scheme and can be
decoded after the initial cell search procedure. The MIB corresponds to one BCH transport block. The
BCH transmission time interval (TTI), or the time needed to transmit a single transport block, is 640
msec or 64 frames [ 3 ]. The BCH is transmitted in 64 parts, each part mapped to the first subframe
(subframe 0) of a frame and it is possible that each transmission is independently decodable,
depending on signal conditions. To ensure that subframe 0 is received, the capture should be at least
11 subframes long, to account for the possibility that the capture is started during subframe 0. For
poor signal conditions, all 64 parts of the TTI may be required, in which case the capture should be at
least 641 subframes long. For more details on NPBCH symbols generation, see “NB-IoT Downlink
Waveform Generation” on page 2-121.

NB-IoT Downlink Waveform Generation and Initializing Parameters

Generate the time-domain waveform of a reference measurement channel (RMC) for narrowband
physical downlink shared channel (NPDSCH) performance requirements, in accordance to TS 36.101
Annex A.3.12 [ 2 ]. The waveform is generated using the generateWaveform method in the class

2-369

2 Examples and Demos

NBIoTDownlinkWaveformGenerator. To call the method, an object ngen is created and the method is
called by using generateWaveform(ngen).

% Initialize NBIoTDownlinkWaveformGenerator object
%
% Use the 'rc' values of 'R.NB.5' and 'R.NB.6' for MIB decoding. Note that
% RMCs 'R.NB.5-1', 'R.NB.6-1' and 'R.NB.7' correspond to Non-Anchor type
% carriers which do not contain the required NPSS, NSSS and NPBCH.
rc = 'R.NB.5';
ngen = NBIoTDownlinkWaveformGenerator(rc);
ngen.Config.NNCellID = 120;
ngen.Config.NBRefP = 1;
ngen.Config.NFrame = 640;
ngen.Config.TotSubframes = 50;
ngen.Config.NPBCH.DataSource = 'MIB';

% Generate time domain NB-IoT waveform
[eNodeBOutput,grid,ofdmInfo] = generateWaveform(ngen);
sr = ofdmInfo.SamplingRate;

% Introduce a delay to simulate the unknown timing alignment associated
% with an arbitrary signal capture. This is compensated at the receiver
% while synchronizing the received signal.
delay = 50;
waveform = circshift(eNodeBOutput, delay);

% Initialize plots
if (~exist('channelFigure','var') || ~isvalid(channelFigure))
    channelFigure = figure('Visible','off');
end
[spectrumScope,synchCorrPlot,pdcchConstDiagram] = ...
    hSIB1RecoveryExamplePlots(channelFigure,sr);

% Display received signal spectrum
fprintf('\nPlotting received signal spectrum...\n');
spectrumScope(awgn(waveform, 100.0));

Plotting received signal spectrum...

2-370

 NB-IoT Cell Search and MIB Recovery

Cell Search and Timing Synchronization

Call the function hNBCellSearch to obtain the cell identity and timing offset offset to the first frame
head. A plot of the correlation between the received signal and the narrowband primary
synchronization signal (NPSS)/narrowband secondary synchronization signal (NSSS) for the detected
cell identity is produced. The NPSS is detected using time-domain correlation and the NSSS is
detected using frequency-domain correlation. Prior to NSSS detection, frequency offset estimation/
correction using cyclic prefix correlation is performed. The time-domain NPSS detection is robust to
small frequency offsets but larger offsets may degrade the NPSS correlation.

% Cell search
fprintf('\nPerforming cell search...\n');
alg.SSSDetection = 'PostFFT';
alg.MaxCellCount = 1;
[NNCellID, offset, peak] = hNBCellSearch(waveform, alg);
nbenb = struct;
nbenb.NNCellID = NNCellID;

[~,corr] = lteNBDLFrameOffset(setfield(nbenb,'OperationMode','Standalone'),waveform); %#ok<SFLD>

% As NB-IoT has similar waveform structure as LTE waveform, use functions
% pertaining to LTE to work with NB-IoT. For this purpose, create a
% cell-wide settings structure enb.
enb = nbenb;

2-371

2 Examples and Demos

% Plot NPSS/NSSS correlation and threshold
synchCorrPlot.YLimits = [0 max(corr(:))*1.1];
synchCorrPlot(corr);

% Perform timing synchronization
fprintf('Timing offset to frame start: %d samples\n',offset);
timesynced = waveform(1+offset:end,:);

% Show cell-wide settings
fprintf('Cell-wide settings after cell search:\n');
disp(nbenb);

Performing cell search...
Timing offset to frame start: 50 samples
Cell-wide settings after cell search:
    NNCellID: 120

Frequency Offset Estimation and Correction

Prior to OFDM demodulation, any significant frequency offset must be removed. The frequency offset
in the I/Q waveform is estimated and corrected using lteFrequencyOffset and
lteFrequencyCorrect. The frequency offset is estimated by means of correlation of the cyclic
prefix and therefore can estimate offsets up to +/- half the subcarrier spacing i.e. +/- 7.5kHz. NB-IoT
downlink waveform generation is similar to LTE uplink waveform generation as both the waveforms

2-372

 NB-IoT Cell Search and MIB Recovery

have half sub-carrier shift. Hence, use LTE uplink functions to estimate the frequency offset and to
demodulate the NB-IoT OFDM downlink received waveforms.

% Frequency offset estimation
fprintf('\nPerforming frequency offset estimation...\n');
enb.NULRB = 6; % For frequency offset computation
enb.DuplexMode = 'FDD';
foffset = lteFrequencyOffset(enb,timesynced,0);
fprintf('Frequency offset: %0.3fHz\n',foffset);

% Compensating for frequency offset
freqsynced = lteFrequencyCorrect(enb,timesynced,foffset);

Performing frequency offset estimation...
Frequency offset: -0.031Hz

OFDM Demodulation and Channel Estimation

The OFDM downsampled I/Q waveform is demodulated to produce a resource grid rxgrid. This is
used to perform channel estimation. hest is the channel estimate, nest is an estimate of the noise
(for MMSE equalization), and cec is the channel estimator configuration.

For channel estimation the example assumes four cell specific reference signals, and two narrowband
reference signals. This means that channel estimates to each receiver antenna from all possible cell-
specific reference signal ports are available. The true number of cell-specific reference signal ports is
not yet known. The channel estimation is only performed on the first subframe, i.e. using the first L
OFDM symbols in rxgrid.

A conservative 13-by-9 pilot averaging window is used, both in frequency and time, to reduce the
impact of noise on pilot estimates during channel estimation.

% Channel estimator configuration
cec.PilotAverage = 'UserDefined';     % Type of pilot averaging
cec.FreqWindow = 13;                  % Frequency window size
cec.TimeWindow = 9;                   % Time window size
cec.InterpType = 'Cubic';             % 2D interpolation type
cec.InterpWindow = 'Centered';        % Interpolation window type
cec.InterpWinSize = 1;                % Interpolation window size
cec.Reference = 'NRS';                % NB-IoT downlink channel estimation

% Assume 4 cell specific and 2 narrowband reference signals for initial
% decoding attempt. This ensures channel estimates are available for all
% reference signals
enb.CellRefP = 4;
enb.NBRefP = 2;
enb.NTxAnts = 2;
nbenb.NBRefP = 2;

fprintf('Performing OFDM demodulation...\n\n');
griddims = lteResourceGridSize(enb); % Resource grid dimensions
L = griddims(2);                     % Number of OFDM symbols in a subframe

enb.NBULSubcarrierSpacing = '15kHz'; % Required for NB-IoT downlink OFDM demodulation
rxgrid = lteSCFDMADemodulate(enb,freqsynced); % For OFDM demodulation in NB-IoT

2-373

2 Examples and Demos

if (isempty(rxgrid))
    fprintf('After timing synchronization, signal is shorter than one subframe so no further demodulation will be performed.\n');
    return;
end

% Perform channel estimation
enb.NSubframe = 0; % Initialize NSubframe for channel estimation
[hest, nest] = lteDLChannelEstimate(enb, cec, rxgrid(:,1:L,:));

Performing OFDM demodulation...

NPBCH Demodulation, BCH Decoding, MIB Parsing

The MIB is now decoded along with the number of narrowband reference signal ports transmitted as
a mask on the BCH CRC. The function lteNPBCHDecode establishes frame timing modulo 64 and
returns this in the nfmod64 parameter. It also returns the MIB bits in vector mib and the true
number of narrowband reference signal ports which is assigned into nbenb.NBRefP at the output of
this function call. If the number of narrowband reference signal ports is decoded as
nbenb.NBRefP=0, this indicates a failure to decode the BCH.

% Decode the MIB
% Extract resource elements (REs) corresponding to the NPBCH from the first
% subframe across all receive antennas and channel estimates
separator = repmat('-',1,50);
fprintf('%s\n',separator);
fprintf('Performing MIB decoding...\n');
fprintf('%s\n\n',separator);
npbchIndices = lteNPBCHIndices(nbenb);
[npbchRx, npbchHest] = lteExtractResources(npbchIndices, ...
                              rxgrid(1:12,1:L,:), hest(:,1:L,:,:));

% Decode NPBCH
dstate = [];
[bchBits, dstate,npbchSymbols,nfmod64,mib,nbenb.NBRefP] = lteNPBCHDecode( ...
    nbenb, npbchRx, npbchHest, nest, dstate);

% Parse MIB bits
nbenb = hNBMIB(mib,nbenb);

if (nbenb.NBRefP == 0)
    fprintf('MIB decoding failed (nbenb.NBRefP=0).\n\n');
    return;
end

% Incorporate the nfmod64 value from the function lteNPBCHDecode, as
% the NFrame value established from the MIB is the SFN modulo 64 (it is
% stored in the MIB as floor(SFN/64)).
if nbenb.NBRefP % If NPBCH decoding is passed then set the NFrame value
    nbenb.NFrame = nbenb.NFrame+nfmod64;
end

if strcmpi(nbenb.OperationMode, 'Inband-SamePCI')
    nbenb.NCellID = NNCellID;
end

% Display cell-wide settings after MIB decoding

2-374

 NB-IoT Cell Search and MIB Recovery

fprintf('Cell-wide settings after MIB decoding:\n');
disp(nbenb);

--------------------------------------------------
Performing MIB decoding...
--------------------------------------------------

Cell-wide settings after MIB decoding:
                      NNCellID: 120
                        NBRefP: 1
                        NFrame: 640
                      HyperSFN: 0
                     ABEnabled: 0
                 OperationMode: 'Inband-DifferentPCI'
    AdditionalTransmissionSIB1: 0

Appendix

This example uses the following helper files:

• NBIoTDownlinkWaveformGenerator

• hNBCellSearch.m

• hNBMIB.m

• hSIB1RecoveryExamplePlots.m

Selected Bibliography

1

2

3GPP TS 36.211. "Physical channels and modulation." 3rd Generation Partnership Project;
Technical Specification Group Radio Access Network; Evolved Universal Terrestrial Radio Access
(E-UTRA). URL: https://www.3gpp.org.

3GPP TS 36.101. "User Equipment (UE) radio transmission and reception". 3rd Generation
Partnership Project; Technical Specification Group Radio Access Network; Evolved Universal
Terrestrial Radio Access (E-UTRA). URL: https://www.3gpp.org.

3 O. Liberg, M. Sundberg, Y.-P. Wang, J. Bergman, and J. Sachs. Cellular Internet of Things:

Technologies, Standards and Performance. Elsevier, 2018.

2-375

2 Examples and Demos

Cell Search, MIB and SIB1 Recovery

This example shows how to fully synchronize, demodulate and decode a live eNodeB signal by using
LTE Toolbox™ software. Before the user equipment (UE) can communicate with the network, it must
perform cell search and selection procedures, and then obtain initial system information. This process
involves acquiring slot and frame synchronization, determining the cell identity and decoding the MIB
and system information blocks (SIBs). This example demonstrates this process and decodes the MIB
and SIB1, the first of the system information blocks. Decoding the MIB and SIB1 requires a
comprehensive that is capable of demodulating and decoding the majority of the downlink channels
and signals.

Introduction

In order to communicate with the network the UE must obtain some basic system information. This is
carried by the MIB and SIBs. The MIB carries the most essential system information:

• System bandwidth

• System frame number (SFN)

• Physical hybrid automatic repeat request (HARQ) indicator channel (PHICH) configuration

The MIB is carried on the broadcast channel (BCH) mapped into the physical broadcast channel
(PBCH). This is transmitted with a fixed coding and modulation scheme and can be decoded after the
initial cell search procedure. With the information obtained from the MIB the UE can now decode the
control format indicator (CFI), which indicates the physical downlink control channel (PDCCH)
length. This allows the PDCCH to be decoded, and searched for downlink control information (DCI)
messages. A DCI message CRC masked with system information radio network temporary identifier
(SI-RNTI) indicates that a SIB is carried in the same subframe. The SIBs are transmitted in the
broadcast control channel (BCCH) logical channel. Generally, BCCH messages are carried on the
downlink shared channel (DL-SCH) and transmitted on the physical downlink shared channel
(PDSCH). The format and resource allocation of the PDSCH transmission is indicated by a DCI
message on the PDCCH.

This example decodes the MIB and SystemInformationBlockType1 (SIB1). The latter is transmitted to
specify the scheduling of other system information, along with aspects of the cell identity such as
Public Land Mobile Network (PLMN) identity. Although SIB1 is transmitted in a fixed time schedule,
the resource allocation of the PDSCH carrying SIB1 is dynamic and is indicated in an associated DCI
message.

Load and Process I/Q Waveform

MATLAB® can be used to acquire I/Q data from a wide range of instruments using the Instrument
Control Toolbox™. In this example a single antenna I/Q capture of an eNodeB with two transmit
antennas is used. The capture is performed at 15.36 Msamples/s which is sufficient to correctly
sample all valid eNodeB bandwidths up to 10 MHz: 1.4 MHz, 3 MHz, 5 MHz, 10 MHz. The captured
data is stored in the file eNodeBOutput.mat.

Alternatively, a suitable LTE signal can be generated using the LTE Toolbox. This can be controlled by
the variable loadFromFile.

loadFromFile = 1; % Set to 0 to generate the eNodeB output locally

The MIB corresponds to one BCH transport block. The BCH Transmission Time Interval (TTI), or the
time needed to transmit a single transport block, is 40msec or 4 frames. The BCH is transmitted in 4

2-376

