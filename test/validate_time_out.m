
% Verifica Time_out según IEC 60255 (K=0.14, N=0.02)

clear; clc;

% ------------- RUTAS RELATIVAS -----------------
scriptDir = fileparts(mfilename('fullpath'));       % carpeta de este archivo
dataDir   = fullfile(scriptDir, "..", "data");      % ../data
fileJSON  = fullfile(dataDir, "processed", ...
                     "independent_relay_pairs_scenario_base_optimized.json");

% ---------------- PARÁMETROS -------------------
tol = 1e-4;                 % |t_calc - t_json| (s) permitido
K   = 0.14;  N = 0.02;      % IEC inversa normal

% ------------------ LECTURA --------------------
data = jsondecode(fileread(fileJSON));

fails = 0;
for k = 1:numel(data)
    % ------- MAIN -------
    Im  = data(k).main_relay.Ishc;
    Ip  = data(k).main_relay.pick_up;
    TDS = data(k).main_relay.TDS;
    t_calc = K*TDS / ( (Im/Ip)^N - 1 );
    if abs(t_calc - data(k).main_relay.Time_out) > tol, fails = fails+1; end
    
    % ------- BACKUP -----
    Ib  = data(k).backup_relay.Ishc;
    IpB = data(k).backup_relay.pick_up;
    TDSB= data(k).backup_relay.TDS;
    t_calc_b = K*TDSB / ( (Ib/IpB)^N - 1 );
    if abs(t_calc_b - data(k).backup_relay.Time_out) > tol, fails = fails+1; end
end

total = 2*numel(data);
fprintf("Pares verificados: %d (main+backup)\n", total);
fprintf("Registros fuera de tolerancia: %d (%.2f %%)\n", ...
        fails, 100*fails/total);

if fails==0
    disp("✔︎ Todos los Time_out están dentro de la tolerancia.");
else
    disp("✖︎ Hay discrepancias; revisá los registros señalados.");
end
