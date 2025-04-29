clc; clear; close all;

% ------------ RUTAS RELATIVAS (desde este script) -------------
scriptDir = fileparts(mfilename('fullpath'));        % carpeta del script
dataDir   = fullfile(scriptDir, "..", "data");       % ../data

pairsIn   = fullfile(dataDir, "raw",      "independent_relay_pairs_scenario_base.json");
optJson   = fullfile(dataDir, "processed","optimized_relay_values_scenario_base.json");
pairsOut  = fullfile(dataDir, "processed","independent_relay_pairs_scenario_base_optimized.json");

% ----------------------- LECTURA -------------------------------
pairs     = jsondecode(fileread(pairsIn));
optStruct = jsondecode(fileread(optJson));

% Usamos el primer bloque de valores optimizados
relayVals = optStruct(1).relay_values;
rNames    = fieldnames(relayVals);

% ----------- MAPA relay -> [pickup  TDS] -----------------------
optMap = containers.Map;
for i = 1:numel(rNames)
    rv = relayVals.(rNames{i});
    optMap(rNames{i}) = [rv.pickup, rv.TDS];
end

% ------------- IEC INVERSA NORMAL -----------------------------
K = 0.14;  N = 0.02;
timeIEC = @(I,PU,TDS) (K*TDS) ./ ((I./PU).^N - 1);

% --------------- ACTUALIZAR LOS PARES -------------------------
for k = 1:numel(pairs)
    % main
    rn = pairs(k).main_relay.relay;
    if optMap.isKey(rn)
        v = optMap(rn);
        pairs(k).main_relay.pick_up  = v(1);
        pairs(k).main_relay.TDS      = v(2);
        pairs(k).main_relay.Time_out = timeIEC(pairs(k).main_relay.Ishc, v(1), v(2));
    end
    % backup
    rn = pairs(k).backup_relay.relay;
    if optMap.isKey(rn)
        v = optMap(rn);
        pairs(k).backup_relay.pick_up  = v(1);
        pairs(k).backup_relay.TDS      = v(2);
        pairs(k).backup_relay.Time_out = timeIEC(pairs(k).backup_relay.Ishc, v(1), v(2));
    end
end

% -------------------- GUARDAR RESULTADO ------------------------
jsonOut = jsonencode(pairs,'PrettyPrint',true);
fid = fopen(pairsOut,'w');
assert(fid>0,"No se pudo abrir %s para escribir.",pairsOut);
fwrite(fid,jsonOut,'char'); fclose(fid);

fprintf("✅ Archivo final generado: %s\n", pairsOut);
