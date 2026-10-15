function app=openNBIoTApp(dialogs)
%OPENNBIOTAPP Open the bounded local Static-mode user interface.
% Optional DIALOGS supplies chooseOutputDirectory() and chooseKpiFile()
% callbacks for automated UI checks; omit it for standard Windows dialogs.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); setupProject();
addpath(fullfile(root,'apps'));
if nargin<1, dialogs=[]; end
app=NBIoTApp(dialogs);
end
