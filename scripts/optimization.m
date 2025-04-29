
% ==========================================================================
% Optimiza los ajustes (TDS y pickup) de pares de relés según la norma IEC
% ==========================================================================
clc; clear; close all; % Limpiar entorno

%% ---------------- CONFIGURACIÓN GENERAL ---------------------------------
try
    scriptPath = mfilename('fullpath');
    if isempty(scriptPath)
        error('No se pudo determinar la ruta del script. Ejecute el script desde el editor de MATLAB.');
    end
    scriptDir = fileparts(scriptPath); % Directorio /scripts
    rootDir   = fileparts(scriptDir);      % Raíz del proyecto (un nivel arriba)
catch ME
    rootDir = pwd; % Fallback a directorio actual si mfilename falla (ej. ejecución por celdas)
    warning('No se pudo determinar automáticamente la ruta del script. Usando el directorio actual como raíz: %s', rootDir);
end

inDir   = fullfile(rootDir, 'data', 'raw');       % Directorio JSON entrada
outDir  = fullfile(rootDir, 'data', 'processed'); % Directorio JSON salida

inFile  = fullfile(inDir, 'independent_relay_pairs_scenario_base.json');
outFile = fullfile(outDir, 'optimized_relay_values_scenario_base.json'); % Nombre de archivo de salida actualizado

fprintf('Root del proyecto: %s\n', rootDir);
fprintf('Archivo de entrada: %s\n', inFile);

%% ------------------ CONSTANTES DEL MODELO Y OPTIMIZACIÓN ---------------
% Parámetros Curva IEC Standard Inverse
K = 0.14;
N = 0.02;

% Coordinación y Límites Operativos
CTI = 0.20;             % Coordination Time Interval (s)
MIN_TDS = 0.05;         % Mínimo Time Dial Setting (TDS)
MAX_TDS = 1.0;          % Máximo Time Dial Setting (TDS)
MIN_PICKUP = 0.05;      % Mínimo Pickup (A secundarios o p.u.)
MAX_PICKUP_FACTOR = 0.7;% Factor máximo de I_shc para el pickup (evita pickup > 0.7 * I_fault)
MAX_TIME = 20.0;        % Tiempo máximo de operación considerado (s)

% Parámetros del Optimizador
MAX_ITERATIONS = 250;   % Máximo número de iteraciones por escenario
MIN_ALLOWED_INDIVIDUAL_MT = -0.009; % Margen de tiempo individual mínimo permitido (más cercano a cero es mejor)
CONVERGENCE_THRESHOLD_TMT = 0.005; % Umbral de convergencia para el TMT (Total Miscoordination Time)
STAGNATION_LIMIT = 25;  % Límite de iteraciones sin mejora significativa del TMT

% Pasos de Ajuste Heurístico (basado en v7-final y referencia)
% -> Cuando la miscoordinación (MT) es muy negativa (agresiva)
AGGRESSIVE_MT_THRESHOLD = -CTI * 0.75; % Umbral para ajuste agresivo
AGGRESSIVE_TDS_BACKUP_FACTOR = 1.15; % Factor para incrementar TDS del relé backup
AGGRESSIVE_TDS_MAIN_FACTOR = 0.90;   % Factor para decrementar TDS del relé principal
AGGRESSIVE_PICKUP_BACKUP_FACTOR = 1.05; % Factor para incrementar Pickup del backup (solo si TDS está al máximo)

% -> Cuando la miscoordinación (MT) es negativa pero no agresiva (normal)
NORMAL_TDS_BACKUP_STEP = 0.02;  % Paso para incrementar TDS del relé backup
NORMAL_TDS_MAIN_STEP = 0.01;    % Paso para decrementar TDS del relé principal

% NOTA: Los pesos W_TIME y W_MT definidos en los scripts originales no se usan
% activamente en la lógica de ajuste heurístico implementada aquí. Se omiten
% para evitar confusión, ya que no forman parte de una función objetivo explícita.

%% ------------------------ 1. CARGAR DATOS ------------------------------
assert(isfile(inFile), 'El archivo JSON de entrada no existe: %s', inFile);
try
    fileContent = fileread(inFile);
    rawData = jsondecode(fileContent);
catch ME
    error('Error al leer o decodificar el archivo JSON: %s\n%s', inFile, ME.message);
end
assert(isstruct(rawData) || iscell(rawData), 'El JSON de entrada debe ser un arreglo de objetos (struct array o cell array).');
if iscell(rawData) % Convertir cell array de structs a struct array si es necesario
    rawData = [rawData{:}];
end
fprintf('Se cargaron %d entradas JSON.\n', numel(rawData));

%% --------------- 2. AGRUPAR POR ESCENARIO ------------------------------
scenarioMap = groupDataByScenario(rawData);
scenarioIDs = fieldnames(scenarioMap);
assert(~isempty(scenarioIDs), 'No se encontraron escenarios válidos en los datos de entrada.');
fprintf('Escenarios encontrados: %s\n', strjoin(scenarioIDs, ', '));

%% --------------- 3. OPTIMIZAR ESCENARIOS ------------------------------
allOptimizedResults = struct();
for i = 1:numel(scenarioIDs)
    scenarioID = scenarioIDs{i};
    scenarioData = scenarioMap.(scenarioID);

    fprintf('\n>>> Iniciando optimización para escenario: %s – Pares: %d, Relés: %d\n', ...
            scenarioID, numel(scenarioData.pairs), numel(scenarioData.relays));

    if isempty(scenarioData.pairs)
        warning('Escenario "%s" no tiene pares de relés válidos para optimizar. Saltando...', scenarioID);
        continue;
    end

    % Llamada a la función de optimización con parámetros explícitos
    optimizedSettings = optimizeScenario( ...
        scenarioID, scenarioData, ...
        K, N, CTI, ...
        MIN_TDS, MAX_TDS, MIN_PICKUP, MAX_PICKUP_FACTOR, MAX_TIME, ...
        MAX_ITERATIONS, MIN_ALLOWED_INDIVIDUAL_MT, ...
        CONVERGENCE_THRESHOLD_TMT, STAGNATION_LIMIT, ...
        AGGRESSIVE_MT_THRESHOLD, ...
        AGGRESSIVE_TDS_BACKUP_FACTOR, AGGRESSIVE_TDS_MAIN_FACTOR, AGGRESSIVE_PICKUP_BACKUP_FACTOR, ...
        NORMAL_TDS_BACKUP_STEP, NORMAL_TDS_MAIN_STEP);

    if ~isempty(optimizedSettings)
        allOptimizedResults.(scenarioID) = optimizedSettings;
        fprintf('    Escenario "%s" optimizado. %d relés con ajustes finales.\n', ...
                scenarioID, numel(fieldnames(optimizedSettings)));
    else
        warning('La optimización falló o no produjo resultados válidos para el escenario "%s".', scenarioID);
    end
end

if isempty(fieldnames(allOptimizedResults))
    warning('Ningún escenario produjo resultados de optimización válidos. Verifique los datos de entrada (pares, corrientes Ishc > 0).');
    return; % Salir si no hay nada que guardar
end

%% --------------- 4. GUARDAR RESULTADOS --------------------------------
if ~isfolder(outDir)
    try
        mkdir(outDir);
        fprintf('Directorio de salida creado: %s\n', outDir);
    catch ME
        error('No se pudo crear el directorio de salida: %s\n%s', outDir, ME.message);
    end
end

% Crear la estructura de salida final (lista de objetos por escenario)
outputList = {};
processedScenarioIDs = fieldnames(allOptimizedResults); % IDs de escenarios que sí se procesaron
for i = 1:numel(processedScenarioIDs)
    sid = processedScenarioIDs{i};
    outputList{end+1} = struct( ...
        'scenario_id',  sid, ...
        'timestamp',    datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z'''), ...
        'relay_values', allOptimizedResults.(sid) ...
    );
end

% Guardar como JSON
try
    jsonText = jsonencode(outputList, 'PrettyPrint', true);
    fid = fopen(outFile, 'w');
    if fid == -1
        error('No se pudo abrir el archivo de salida para escritura: %s', outFile);
    end
    fprintf(fid, '%s', jsonText);
    fclose(fid);
    fprintf('\nResultados de optimización guardados en: %s\n', outFile);
catch ME
    error('Error al guardar los resultados en JSON: %s\n%s', outFile, ME.message);
end

%% =====================================================================
%%                         FUNCIONES AUXILIARES
%% =====================================================================

function scenarioMap = groupDataByScenario(dataArray)
% Agrupa los datos de entrada por 'scenario_id'.
% Valida campos necesarios y extrae información relevante.
    scenarioMap = struct();

    for i = 1:numel(dataArray)
        entry = dataArray(i);

        % Validar campos básicos
        if ~isfield(entry, 'scenario_id') || isempty(entry.scenario_id)
            warning('Entrada %d omitida: falta "scenario_id" o está vacío.', i);
            continue;
        end
        sid = string(entry.scenario_id); % Usar string para compatibilidad

        if ~all(isfield(entry, {'main_relay', 'backup_relay'}))
            warning('Escenario "%s", entrada %d omitida: falta "main_relay" o "backup_relay".', sid, i);
            continue;
        end
        mRelayInfo = entry.main_relay;
        bRelayInfo = entry.backup_relay;

        if ~isfield(mRelayInfo, 'relay') || ~isfield(bRelayInfo, 'relay') || isempty(mRelayInfo.relay) || isempty(bRelayInfo.relay)
             warning('Escenario "%s", entrada %d omitida: falta el nombre del relé ("relay") en main o backup.', sid, i);
             continue;
        end

        % Inicializar estructura para el escenario si es la primera vez
        if ~isfield(scenarioMap, sid)
            scenarioMap.(sid) = struct('pairs', {{}}, 'initial_settings', struct(), 'relays', strings(0));
        end
        currentScenario = scenarioMap.(sid);

        % Extraer nombres de relés
        mainRelayName = string(mRelayInfo.relay);
        backupRelayName = string(bRelayInfo.relay);

        % Extraer corrientes de cortocircuito (con flexibilidad en nombres)
        ishcMain = getNumericField(mRelayInfo, ["Ishc", "I_shc", "Isc", "fault_current"]);
        ishcBackup = getNumericField(bRelayInfo, ["Ishc", "I_shc", "Isc", "fault_current"]);

        if isnan(ishcMain) || isnan(ishcBackup) || ishcMain <= 0 || ishcBackup <= 0
             warning('Escenario "%s", par (%s, %s) omitido: Corriente Ishc inválida o no encontrada (debe ser > 0).', sid, mainRelayName, backupRelayName);
             continue; % Saltar este par si las corrientes son inválidas
        end

        % Crear estructura del par (ahora se guarda en cell array)
        pairStruct = struct(...
            'main_relay',   mainRelayName, ...
            'backup_relay', backupRelayName, ...
            'Ishc_main',    ishcMain, ...
            'Ishc_backup',  ishcBackup ...
        );
        currentScenario.pairs{end+1} = pairStruct; % Añadir al cell array

        % Actualizar lista única de relés y ajustes iniciales
        currentScenario.relays = union(currentScenario.relays, [mainRelayName, backupRelayName]);
        currentScenario.initial_settings = storeInitialSetting(currentScenario.initial_settings, mRelayInfo);
        currentScenario.initial_settings = storeInitialSetting(currentScenario.initial_settings, bRelayInfo);

        % Guardar cambios en el mapa
        scenarioMap.(sid) = currentScenario;
    end
end
% -----------------------------------------------------------------------
function value = getNumericField(structData, possibleNames)
% Busca un campo numérico en una estructura usando una lista de nombres posibles.
    value = NaN;
    for i = 1:numel(possibleNames)
        name = possibleNames(i);
        if isfield(structData, name)
            rawValue = structData.(name);
            if ischar(rawValue) || isstring(rawValue)
                numValue = str2double(rawValue);
            elseif isnumeric(rawValue)
                numValue = double(rawValue);
            else
                numValue = NaN; % Ignorar tipos no convertibles
            end

            if isnumeric(numValue) && isfinite(numValue) && ~isempty(numValue)
                value = numValue;
                return; % Devolver el primer valor numérico válido encontrado
            end
        end
    end
end
% -----------------------------------------------------------------------
function initialSettings = storeInitialSetting(initialSettings, relayInfo)
% Almacena los ajustes iniciales (TDS, pickup) si no existen ya.
    relayName = string(relayInfo.relay);
    if isfield(initialSettings, relayName)
        return; % Ya existe, no sobrescribir
    end

    initialTDS = getNumericField(relayInfo, ["TDS", "tds"]);
    initialPickup = getNumericField(relayInfo, ["pick_up", "pickup"]);

    % Solo guardar si al menos uno de los valores es válido
    if ~isnan(initialTDS) || ~isnan(initialPickup)
         initialSettings.(relayName) = struct(...
            'TDS_initial', initialTDS, ... % Puede ser NaN si no se encontró
            'pickup_initial', initialPickup ... % Puede ser NaN si no se encontró
            );
    end
end

% -----------------------------------------------------------------------
function t = calculateRelayTime(Ishc, Pickup, TDS, K, N, MAX_TIME, MIN_PICKUP, MIN_TDS, MAX_TDS, MAX_PICKUP_FACTOR)
% Calcula el tiempo de operación de un relé según la curva IEC Standard Inverse.
% Incluye validaciones y manejo de casos límite.

    % Validaciones básicas de entrada
    if Ishc <= 0 || Pickup < MIN_PICKUP || TDS < MIN_TDS || TDS > MAX_TDS
        t = NaN; % Tiempo inválido si los parámetros están fuera de rango básico
        return;
    end

    % Validación: El pickup no debe ser mayor que una fracción de la corriente de falla
    % Esto evita tiempos infinitos o ajustes irrealizables.
    if Pickup > Ishc * MAX_PICKUP_FACTOR
        t = MAX_TIME; % Considerar como no operativo (tiempo máximo)
        return;
    end

    % Cálculo del múltiplo M
    M = Ishc / Pickup;
    if M <= 1
        % Si M <= 1, el relé no debería operar para esta corriente.
        t = MAX_TIME; % Considerar como no operativo (tiempo máximo)
        return;
    end

    % Cálculo del tiempo según la fórmula IEC
    denominator = M^N - 1;
    if abs(denominator) < 1e-9 % Evitar división por cero o valores muy pequeños
        t = NaN; % Indeterminado o numéricamente inestable
        return;
    end

    calculatedTime = TDS * (K / denominator);

    % Asegurar que el tiempo no exceda el máximo y sea positivo
    t = min(max(calculatedTime, 0), MAX_TIME);

    if ~isfinite(t) % Chequeo final por si algo dio Inf o NaN
        t = NaN;
    end
end

% -----------------------------------------------------------------------
function optimizedSettings = optimizeScenario(scenarioID, scenarioData, ...
    K, N, CTI, ...
    MIN_TDS, MAX_TDS, MIN_PICKUP, MAX_PICKUP_FACTOR, MAX_TIME, ...
    MAX_ITERATIONS, MIN_ALLOWED_INDIVIDUAL_MT, ...
    CONVERGENCE_THRESHOLD_TMT, STAGNATION_LIMIT, ...
    AGGRESSIVE_MT_THRESHOLD, ...
    AGGRESSIVE_TDS_BACKUP_FACTOR, AGGRESSIVE_TDS_MAIN_FACTOR, AGGRESSIVE_PICKUP_BACKUP_FACTOR, ...
    NORMAL_TDS_BACKUP_STEP, NORMAL_TDS_MAIN_STEP)
% Función principal de optimización para un único escenario.

    pairs = scenarioData.pairs; % Cell array de structs
    relayNames = scenarioData.relays; % String array
    initialSettingsData = scenarioData.initial_settings; % Struct

    nRelays = numel(relayNames);
    if nRelays == 0
        warning('Escenario "%s": No hay relés definidos.', scenarioID);
        optimizedSettings = [];
        return;
    end

    % 1. Calcular Ishc mínimo para cada relé (importante para límites de Pickup)
    minIshcPerRelay = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:numel(pairs)
        p = pairs{i};
        updateMinIshc(minIshcPerRelay, char(p.main_relay), p.Ishc_main);
        updateMinIshc(minIshcPerRelay, char(p.backup_relay), p.Ishc_backup);
    end
    function updateMinIshc(map, relayChar, ishc)
        if isKey(map, relayChar)
            map(relayChar) = min(map(relayChar), ishc);
        else
            map(relayChar) = ishc;
        end
    end

    % 2. Inicializar ajustes (TDS y Pickup)
    currentSettings = struct();
    defaultInitialPickup = MIN_PICKUP * 1.5; % Un valor inicial razonable si no hay datos

    for i = 1:nRelays
        relayChar = char(relayNames(i));
        relayMinIshc = Inf; % Default si el relé no aparece en ningún par válido
        if isKey(minIshcPerRelay, relayChar)
             relayMinIshc = minIshcPerRelay(relayChar);
        else
             warning('Escenario "%s": El relé "%s" no tiene una Ishc asociada en los pares válidos.', scenarioID, relayChar);
             % Podríamos decidir omitir este relé o continuar con precaución
        end

        % Inicializar Pickup
        pickup = defaultInitialPickup; % Empezar con el default
        if isfield(initialSettingsData, relayChar) && isfield(initialSettingsData.(relayChar), 'pickup_initial')
            initialPU = initialSettingsData.(relayChar).pickup_initial;
            if isnumeric(initialPU) && isfinite(initialPU) && initialPU > 0
                 pickup = max(MIN_PICKUP, initialPU); % Usar inicial si es válido
            end
        end

        % Ajustar pickup si es demasiado alto comparado con la mínima Ishc
        maxAllowedPickup = relayMinIshc * MAX_PICKUP_FACTOR;
        if pickup >= maxAllowedPickup && relayMinIshc > 0
            pickup = max(MIN_PICKUP, maxAllowedPickup * 0.99); % Reducir un poco para asegurar M > 1
             fprintf('    Aviso: Pickup inicial de %s ajustado a %.4f (límite %.4f basado en Ishc min %.2fA)\n', ...
                     relayChar, pickup, maxAllowedPickup, relayMinIshc);
        end
        pickup = max(MIN_PICKUP, pickup); % Asegurar mínimo global

        % Inicializar TDS
        tds = MIN_TDS; % Empezar siempre desde el TDS mínimo

        currentSettings.(relayChar) = struct('TDS', tds, 'pickup', pickup);
    end

    % 3. Bucle de optimización iterativa
    previousTotalMiscoordinationTime = inf;
    stagnationCounter = 0;
    fprintf('    Iniciando iteraciones (máx. %d)...\n', MAX_ITERATIONS);

    for iter = 1:MAX_ITERATIONS
        totalMiscoordinationTime = 0; % Suma de MT < 0
        totalMainRelayTime = 0;       % Suma de tiempos de relés principales (informativo)
        maxNegativeMiscoordination = 0; % El MT más negativo encontrado (más cercano a -inf)
        pairResults = cell(1, numel(pairs)); % Almacenar resultados por par para ajuste

        % Calcular tiempos y miscoordinación para todos los pares con los ajustes actuales
        validPairsCount = 0;
        for i = 1:numel(pairs)
            p = pairs{i};
            mainRelayChar = char(p.main_relay);
            backupRelayChar = char(p.backup_relay);

            % Obtener ajustes actuales para el par
            settingsMain = currentSettings.(mainRelayChar);
            settingsBackup = currentSettings.(backupRelayChar);

            % Calcular tiempos de operación
            timeMain = calculateRelayTime(p.Ishc_main, settingsMain.pickup, settingsMain.TDS, K, N, MAX_TIME, MIN_PICKUP, MIN_TDS, MAX_TDS, MAX_PICKUP_FACTOR);
            timeBackup = calculateRelayTime(p.Ishc_backup, settingsBackup.pickup, settingsBackup.TDS, K, N, MAX_TIME, MIN_PICKUP, MIN_TDS, MAX_TDS, MAX_PICKUP_FACTOR);

            % Calcular margen de tiempo (Miscoordination Time - MT)
            miscoordinationTime = NaN;
            if isnan(timeMain) || isnan(timeBackup)
                 % Si algún tiempo es inválido, no podemos calcular MT
                 mtStatus = "Inválido";
            elseif timeMain >= MAX_TIME && timeBackup >= MAX_TIME
                 % Ambos no operan, coordinación trivial pero no útil
                 miscoordinationTime = 0; % O algún valor que indique no-miscoordination
                 mtStatus = "Ambos MAX_TIME";
            elseif timeMain >= MAX_TIME % Main no opera, Backup sí -> miscoordinación severa
                 miscoordinationTime = -MAX_TIME; % Penalización grande
                 mtStatus = "Main MAX_TIME";
            elseif timeBackup >= MAX_TIME % Backup no opera, Main sí -> OK (aunque backup no respalda)
                 miscoordinationTime = MAX_TIME; % Penalización grande
                 mtStatus = "Backup MAX_TIME";
            else
                % Ambos operan, calcular margen normal
                miscoordinationTime = (timeBackup - timeMain) - CTI;
                mtStatus = sprintf("%.4f", miscoordinationTime);
                 validPairsCount = validPairsCount + 1;
            end

            % Almacenar resultados para la fase de ajuste
            pairResults{i} = struct(...
                'main', mainRelayChar, 'backup', backupRelayChar, ...
                'timeMain', timeMain, 'timeBackup', timeBackup, ...
                'MT', miscoordinationTime, 'Status', mtStatus ...
            );

            % Acumular métricas globales si el MT es calculable y negativo
            if ~isnan(miscoordinationTime)
                if miscoordinationTime < 0
                    totalMiscoordinationTime = totalMiscoordinationTime + miscoordinationTime; % Sumar negativos
                    maxNegativeMiscoordination = min(maxNegativeMiscoordination, miscoordinationTime);
                end
                if ~isnan(timeMain) && timeMain < MAX_TIME
                     totalMainRelayTime = totalMainRelayTime + timeMain;
                end
            end
        end % Fin bucle sobre pares (cálculo)

        % Criterio de convergencia 1: Todos los MT individuales son aceptables
        if maxNegativeMiscoordination >= MIN_ALLOWED_INDIVIDUAL_MT
            fprintf('    Convergencia alcanzada en iteración %d: Todos los MT >= %.4f.\n', iter, MIN_ALLOWED_INDIVIDUAL_MT);
            break;
        end

        % Criterio de convergencia 2: Estancamiento del TMT
        if abs(totalMiscoordinationTime - previousTotalMiscoordinationTime) < CONVERGENCE_THRESHOLD_TMT
            stagnationCounter = stagnationCounter + 1;
            if stagnationCounter > STAGNATION_LIMIT
                 fprintf('    Convergencia por estancamiento en iteración %d: TMT no mejora significativamente (TMT actual: %.4f).\n', iter, totalMiscoordinationTime);
                 break;
            end
        else
            stagnationCounter = 0; % Resetear contador si hubo mejora
        end
        previousTotalMiscoordinationTime = totalMiscoordinationTime;

        % Si se alcanzó el máximo de iteraciones
        if iter == MAX_ITERATIONS
            fprintf('    Advertencia: Se alcanzó el máximo de iteraciones (%d) sin convergencia completa.\n', MAX_ITERATIONS);
            fprintf('               MT más negativo: %.4f (Objetivo: >= %.4f)\n', maxNegativeMiscoordination, MIN_ALLOWED_INDIVIDUAL_MT);
        end

        % Fase de ajuste: Modificar TDS y Pickup basado en los MT negativos
        nextSettings = currentSettings; % Copiar ajustes para modificarlos
        settingsChanged = false;

        for i = 1:numel(pairResults)
            pr = pairResults{i};
            if isnan(pr.MT) || pr.MT >= 0
                continue; % Solo ajustar si hay miscoordinación (MT < 0)
            end

            mainRelayChar = pr.main;
            backupRelayChar = pr.backup;

            % Aplicar ajustes según si es agresivo o normal
            if pr.MT < AGGRESSIVE_MT_THRESHOLD
                % --- Ajuste Agresivo ---
                % Aumentar TDS Backup (con límite MAX_TDS)
                currentTDS_B = nextSettings.(backupRelayChar).TDS;
                nextSettings.(backupRelayChar).TDS = min(MAX_TDS, currentTDS_B * AGGRESSIVE_TDS_BACKUP_FACTOR);

                % Disminuir TDS Main (con límite MIN_TDS)
                currentTDS_M = nextSettings.(mainRelayChar).TDS;
                nextSettings.(mainRelayChar).TDS = max(MIN_TDS, currentTDS_M * AGGRESSIVE_TDS_MAIN_FACTOR);

                 % Si TDS Backup llegó al límite, intentar aumentar Pickup Backup
                 if abs(nextSettings.(backupRelayChar).TDS - MAX_TDS) < 1e-6 && isKey(minIshcPerRelay, backupRelayChar)
                     currentPU_B = nextSettings.(backupRelayChar).pickup;
                     backupMinIshc = minIshcPerRelay(backupRelayChar);
                     maxAllowedPU_B = backupMinIshc * MAX_PICKUP_FACTOR;
                     newPU_B = min(maxAllowedPU_B, max(MIN_PICKUP, currentPU_B * AGGRESSIVE_PICKUP_BACKUP_FACTOR));
                     nextSettings.(backupRelayChar).pickup = newPU_B;
                 end

            else
                % --- Ajuste Normal ---
                % Aumentar TDS Backup (con límite MAX_TDS)
                 currentTDS_B = nextSettings.(backupRelayChar).TDS;
                 nextSettings.(backupRelayChar).TDS = min(MAX_TDS, currentTDS_B + NORMAL_TDS_BACKUP_STEP);

                 % Disminuir TDS Main (con límite MIN_TDS)
                 currentTDS_M = nextSettings.(mainRelayChar).TDS;
                 nextSettings.(mainRelayChar).TDS = max(MIN_TDS, currentTDS_M - NORMAL_TDS_MAIN_STEP);
            end
            settingsChanged = true; % Marcar que hubo al menos un ajuste
        end % Fin bucle sobre pares (ajuste)

        % Si ningún ajuste fue necesario en esta iteración (raro si no convergió antes)
        if ~settingsChanged && iter > 1 % Evitar salida prematura en iter 1
            fprintf('    Advertencia: No se realizaron cambios en la iteración %d, posible problema.\n', iter);
            break;
        end

        currentSettings = nextSettings; % Actualizar los ajustes para la siguiente iteración

    end % Fin bucle de optimización

    % 4. Post-procesamiento: Redondear y asegurar límites finales
    optimizedSettings = struct();
    relayFinalNames = fieldnames(currentSettings);
    for i = 1:numel(relayFinalNames)
        relayChar = relayFinalNames{i};
        finalTDS = currentSettings.(relayChar).TDS;
        finalPickup = currentSettings.(relayChar).pickup;

        % Redondear a 5 decimales (o según precisión deseada)
        finalTDS = round(finalTDS, 5);
        finalPickup = round(finalPickup, 5);

        % Asegurar límites estrictamente una última vez
        finalTDS = min(MAX_TDS, max(MIN_TDS, finalTDS));
        if isKey(minIshcPerRelay, relayChar)
             relayMinIshc = minIshcPerRelay(relayChar);
             maxAllowedPickup = relayMinIshc * MAX_PICKUP_FACTOR;
             finalPickup = min(maxAllowedPickup, max(MIN_PICKUP, finalPickup));
        else
             finalPickup = max(MIN_PICKUP, finalPickup); % Solo asegurar mínimo si no hay Ishc
        end


        optimizedSettings.(relayChar).TDS = finalTDS;
        optimizedSettings.(relayChar).pickup = finalPickup;
    end

    fprintf('    Optimización finalizada para "%s". MT más negativo final: %.4f\n', scenarioID, maxNegativeMiscoordination);

end % Fin de optimizeScenario