
clear; clc;

% -------- CONFIGURA ACÁ --------
scenarioID = "scenario_1";   % escenario a inspeccionar
mainID     = "R52";          % relé principal
backupID   = "R53";          % relé respaldo
CTI        = 0.20;           % Coordination Time Interval (s)
K = 0.14;  N = 0.02;         % IEC inversa normal
pairsFile  = "independent_relay_pairs_scenario_base_optimized.json"; % nombre base
% --------------------------------

% ----------- RUTAS RELATIVAS ------------
scriptDir = fileparts(mfilename('fullpath'));      % carpeta del script
dataDir   = fullfile(scriptDir,"..","data","processed");
jsonFile  = fullfile(dataDir, pairsFile);

resultsDir = fullfile(scriptDir,"..","test","results");
if ~exist(resultsDir,"dir"), mkdir(resultsDir); end

% ------------- CARGAR -------------------
data = jsondecode(fileread(jsonFile));
idx  = find(arrayfun(@(s) s.scenario_id==scenarioID & ...
                             s.main_relay.relay==mainID & ...
                             s.backup_relay.relay==backupID, data), 1);

if isempty(idx)
    error("No se encontró el par solicitado.");
end
p = data(idx);

% ---- Parámetros principales -------------
Im = p.main_relay.Ishc;   Ip = p.main_relay.pick_up;   TDSm = p.main_relay.TDS;
Ib = p.backup_relay.Ishc; Ipb= p.backup_relay.pick_up; TDSb = p.backup_relay.TDS;

t_m = K*TDSm/((Im/Ip)^N - 1);
t_b = K*TDSb/((Ib/Ipb)^N - 1);
delta_t   = t_b - t_m;
coordFlag = delta_t >= CTI;

% ---- Vector de corrientes ---------------
Imin = min([Ip Ipb])*1.01;
Imax = max([Im Ib])*1.2;
Ivec = logspace(log10(Imin), log10(Imax), 200);

TCC_main   = K*TDSm ./ ((Ivec/Ip).^N  - 1);
TCC_backup = K*TDSb ./ ((Ivec/Ipb).^N - 1);

% --------------- GRÁFICA -----------------
f = figure('Visible','off'); hold on;
plot(TCC_main,   Ivec, 'b', 'LineWidth',1.5);
plot(TCC_backup, Ivec, 'r', 'LineWidth',1.5);
plot(t_m, Im,'ob','MarkerFaceColor','b');
plot(t_b, Ib,'or','MarkerFaceColor','r');
xline(t_m,'b--'); xline(t_b,'r--');

set(gca,'XScale','log','YScale','log');
xlabel('Tiempo de operación (s)');
ylabel('Corriente (A)');
status = "Descoordinado"; if coordFlag, status = "Coordinado"; end
title(sprintf('%s – Main %s | Backup %s – %s (Δt=%.3fs)', ...
      scenarioID, mainID, backupID, status, delta_t));
legend({'TCC Main','TCC Backup','Pto Main','Pto Backup'},'Location','best');
grid on; axis tight;

% ---------- GUARDAR FIGURA ---------------
figName = sprintf('%s_%s_%s_TCC.png',scenarioID,mainID,backupID);
saveas(f, fullfile(resultsDir, figName));
close(f);

fprintf("✅ Figura guardada en %s\n", fullfile(resultsDir, figName));
fprintf("Δt = %.4f s  →  %s\n", delta_t, status);
