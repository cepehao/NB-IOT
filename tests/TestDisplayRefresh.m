classdef TestDisplayRefresh < matlab.unittest.TestCase
    methods (Test)
        function redrawsAtEach100MillisecondBoundary(t)
            t.verifyFalse(nbiot.ui.shouldRefreshDisplay(99,0,false));
            t.verifyTrue(nbiot.ui.shouldRefreshDisplay(100,0,false));
            t.verifyFalse(nbiot.ui.shouldRefreshDisplay(199,100,false));
            t.verifyTrue(nbiot.ui.shouldRefreshDisplay(200,100,false));
        end

        function redrawsWhenRunFinishesBeforeBoundary(t)
            t.verifyTrue(nbiot.ui.shouldRefreshDisplay(17,0,true));
        end
    end
end
