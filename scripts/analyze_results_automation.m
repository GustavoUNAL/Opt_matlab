    
    % MT = (Δt - |Δt|)/2 = min(Δt, 0) donde Δt = t_backup - t_main - CTI
    
    clear; clc; close all; % Limpiar workspace, command window y cerrar figuras
    
    % -------- CONFIGURACIÓN --------
    % Asume la siguiente estructura de carpetas relativa a la ubicación de este script:
    % ProjectFolder/
    % |- scripts/ (Aquí está este archivo .m)
    % |- data/
    %    |- raw/
    %       |- independent_relay_pairs_scenario_base.json
    % |- results/
    %    |- reports/
    %    |- figures/
    
    % Nombre del archivo JSON de entrada (relativo a la carpeta 'data/raw')
    inputJsonName = 'independent_relay_pairs_scenario_base.json';
    
    % Carpeta base para los resultados (relativa a la carpeta del proyecto)
    resultsBaseFolder = 'results';
    reportsSubFolder  = 'reports'; % Subcarpeta para reportes de texto
    figuresSubFolder  = 'figures'; % Subcarpeta para figuras
    
    % Parámetros de coordinación y visualización
    CTI      = 0.20;   % Coordination Time Interval (s)
    maxPairs = 100;    % máximo de pares a mostrar en la gráfica y reporte detallado
    
    % -------- RUTAS RELATIVAS --------
    try
        % Obtener la ruta completa del script actual
        scriptFullPath = mfilename('fullpath');
        % Obtener el directorio donde se encuentra el script
        scriptDir = fileparts(scriptFullPath);
        % Asumir que el script está en una carpeta 'scripts' y subir un nivel para la base del proyecto
        projectBaseDir = fileparts(scriptDir); % Sube un nivel desde 'scripts'
    
        % Construir la ruta completa al archivo JSON de entrada
        jsonFile = fullfile(projectBaseDir, 'data', 'raw', inputJsonName);
    
        % Construir las rutas completas para las carpetas de resultados
        resultsDir = fullfile(projectBaseDir, resultsBaseFolder);
        reportDir  = fullfile(resultsDir, reportsSubFolder);
        figureDir  = fullfile(resultsDir, figuresSubFolder);
    
        % Verificar si el archivo de entrada existe
        if ~exist(jsonFile, 'file')
            error('El archivo JSON de entrada no se encontró en la ruta esperada:\n%s\nVerifique la estructura de carpetas y el nombre del archivo.', jsonFile);
        end
    
        % Crear las carpetas de resultados si no existen
        if ~exist(reportDir, 'dir')
            mkdir(reportDir);
            fprintf('Carpeta de reportes creada: %s\n', reportDir);
        end
        if ~exist(figureDir, 'dir')
            mkdir(figureDir);
            fprintf('Carpeta de figuras creada: %s\n', figureDir);
        end
    
    catch ME
        fprintf('Error configurando las rutas:\n%s\n', ME.message);
        fprintf('Asegúrese de que el script se ejecute desde una estructura de carpetas esperada.\n');
        return; % Detener la ejecución si hay error en las rutas
    end
    
    % -------- 1. Leer JSON y armar tabla --------
    fprintf('Leyendo archivo JSON: %s\n', jsonFile);
    try
        S = jsondecode(fileread(jsonFile));
    catch ME
        fprintf('Error leyendo o decodificando el archivo JSON:\n%s\n', ME.message);
        return;
    end
    
    n = numel(S);
    if n == 0
        fprintf('El archivo JSON está vacío o no contiene pares de relés.\n');
        return;
    end
    
    vars = {'pairID','TDSm','TDSb','PUm','PUb','Time_m', 'Time_b', 'delta_t', 'MT'};
    T    = table('Size',[n numel(vars)], 'VariableTypes', ...
                {'string','double','double','double','double','double','double','double','double'}, ...
                'VariableNames',vars);
    
    fprintf('Procesando %d pares de relés...\n', n);
    for k = 1:n
        % Validar estructura del JSON para el elemento actual
        if ~isfield(S(k), 'main_relay') || ~isfield(S(k), 'backup_relay') || ...
           ~isfield(S(k).main_relay, 'relay') || ~isfield(S(k).backup_relay, 'relay') || ...
           ~isfield(S(k).main_relay, 'TDS') || ~isfield(S(k).backup_relay, 'TDS') || ...
           ~isfield(S(k).main_relay, 'pick_up') || ~isfield(S(k).backup_relay, 'pick_up') || ...
           ~isfield(S(k).main_relay, 'Time_out') || ~isfield(S(k).backup_relay, 'Time_out')
            fprintf('Advertencia: El elemento %d del JSON tiene una estructura inesperada. Omitiendo par.\n', k);
            continue; % Saltar al siguiente par si falta algún campo
        end
        
        m = S(k).main_relay;
        b = S(k).backup_relay;
        T.pairID(k) = m.relay + "–" + b.relay;
        T.TDSm(k)   = m.TDS;
        T.TDSb(k)   = b.TDS;
        T.PUm(k)    = m.pick_up;
        T.PUb(k)    = b.pick_up;
        T.Time_m(k) = m.Time_out;
        T.Time_b(k) = b.Time_out;
        
        % Calcular delta_t = t_backup - t_main - CTI
        deltamb     = b.Time_out - m.Time_out - CTI;
        T.delta_t(k)= deltamb;
        
        % Calcular MT = min(delta_t, 0)
        % Esto es equivalente a (deltamb - abs(deltamb)) / 2
        T.MT(k)     = min(deltamb, 0);
    end
    
    % Eliminar filas que pudieron ser omitidas por datos incompletos (si pairID está vacío)
    T = T(~(T.pairID == ""), :);
    if isempty(T)
        fprintf('No se procesaron pares de relés válidos.\n');
        return;
    end
    
    % Ordenar por MT (más descoordinado primero) y recortar si excede maxPairs
    T = sortrows(T,'MT','ascend');
    numTotalPairs = height(T); % Número total de pares procesados
    if numTotalPairs > maxPairs
        T_plot = T(1:maxPairs,:);
        fprintf('Mostrando los %d pares más descoordinados (de %d totales).\n', maxPairs, numTotalPairs);
    else
        T_plot = T;
        fprintf('Mostrando todos los %d pares procesados.\n', numTotalPairs);
    end
    
    T_plot.isCoord = (T_plot.MT == 0); % coordinado si MT = 0 (delta_t >= 0)
    pairCat = categorical(T_plot.pairID); % Usar categorical para mejor manejo en gráficas
    pairCat = reordercats(pairCat, T_plot.pairID); % Mantener el orden de T_plot
    xNums   = 1:height(T_plot);
    
    % -------- 2. Ventana con dos subgráficas --------
    fprintf('Generando gráfica...\n');
    f = figure('Name','Margen de Coordinación (MT) y Ajustes de Protección', ...
               'Color','w', 'Position',[50 50 1400 800], 'Visible', 'off'); % Iniciar invisible
    
    tl = tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('Análisis de Coordinación - %d Pares Principales', height(T_plot)), 'FontSize', 14, 'FontWeight', 'bold');
    
    % --- (A) Gráfica de Barras para MT ---
    ax1 = nexttile;
    bh = bar(ax1, pairCat, T_plot.MT,'FaceColor','flat'); hold(ax1, 'on');
    
    % Línea de CTI cumplido (MT = 0)
    yline(ax1, 0,'k--','CTI cumplido ($\Delta t \geq 0$)', 'LabelHorizontalAlignment','left',...
          'FontAngle','italic','HandleVisibility','off', 'LineWidth', 1.5, 'Interpreter', 'latex');
    
    % Colorear barras según coordinación
    coordColor = [0.20 0.60 0.20]; % Verde para coordinados
    uncoordColor = [0.85 0.20 0.20]; % Rojo para descoordinados
    for k = 1:height(T_plot)
        if T_plot.isCoord(k)
            bh.CData(k,:) = coordColor;
        else
            bh.CData(k,:) = uncoordColor;
        end
    end
    
    ylabel(ax1, 'Margen de Coordinación, MT (s)');
    % Ajustar límites Y para dar espacio arriba y abajo
    yLimVals = [min(T_plot.MT)*1.1 - 0.01, max(0.05, max(T_plot.MT)*1.1)]; % Asegura espacio y al menos hasta 0.05 si todos son 0 o negativos
    ylim(ax1, yLimVals);
    title(ax1, 'Margen de Coordinación (MT) por Par de Relés (Ordenado por Severidad)');
    set(ax1, 'XTickLabel', [], 'FontSize', 10); % Ocultar etiquetas X aquí, se ponen en la de abajo
    grid(ax1, 'on');
    box(ax1, 'off');
    
    % --- (B) Gráfica de Líneas para TDS & Pickup ---
    ax2 = nexttile;
    
    % Eje izquierdo para TDS
    yyaxis(ax2, 'left');
    p1 = plot(ax2, xNums, T_plot.TDSm,'^-','LineWidth',1.2,'Color',[0 0.45 0.74],...
              'MarkerFaceColor',[0 0.45 0.74],'MarkerSize', 6,'DisplayName','TDS Main'); hold(ax2, 'on');
    p2 = plot(ax2, xNums, T_plot.TDSb,'v-','LineWidth',1.2,'Color',[0.85 0.33 0.10],...
              'MarkerFaceColor',[0.85 0.33 0.10],'MarkerSize', 6,'DisplayName','TDS Backup');
    ylabel(ax2, 'Ajuste TDS');
    ax2.YAxis(1).Color = 'k'; % Color del eje izquierdo
    
    % Eje derecho para Pickup
    yyaxis(ax2, 'right');
    p3 = plot(ax2, xNums, T_plot.PUm,'o--','LineWidth',1.2,'Color',[0 0.45 0.74],...
              'MarkerFaceColor','w','MarkerSize', 6,'DisplayName','Pickup Main (A)');
    p4 = plot(ax2, xNums, T_plot.PUb,'s--','LineWidth',1.2,'Color',[0.85 0.33 0.10],...
              'MarkerFaceColor','w','MarkerSize', 6,'DisplayName','Pickup Backup (A)');
    ylabel(ax2, 'Ajuste Pickup (A)');
    ax2.YAxis(2).Color = 'k'; % Color del eje derecho
    
    % Configuración general del eje X para la segunda gráfica
    set(ax2, 'XTick', xNums, 'XTickLabel', string(pairCat),...
             'XTickLabelRotation', 45, 'FontSize', 10);
    xlim(ax2, [0.5, height(T_plot) + 0.5]); % Ajustar límites X
    xlabel(ax2, 'Par (Principal – Respaldo)');
    title(ax2, 'Ajustes de TDS (Eje Izq., Sólido) y Pickup (Eje Der., Discontinuo)');
    legend([p1, p2, p3, p4], 'Location','northwest', 'FontSize', 9);
    grid(ax2, 'on');
    hold(ax2, 'off');
    
    % Ajustar enlace de ejes X si es necesario (aunque aquí comparten la misma categoría)
    % linkaxes([ax1, ax2], 'x'); % Puede ser útil si las categorías difieren
    
    % Guardar la figura en formatos PNG y FIG
    figureBaseName = sprintf('Coordination_Analysis_%s', inputJsonName(1:end-5)); % Nombre base sin .json
    figureFilePng = fullfile(figureDir, [figureBaseName, '.png']);
    figureFileFig = fullfile(figureDir, [figureBaseName, '.fig']);
    
    try
        fprintf('Guardando figura en: %s\n', figureFilePng);
        saveas(f, figureFilePng);
        fprintf('Guardando figura en: %s\n', figureFileFig);
        saveas(f, figureFileFig);
        set(f, 'Visible', 'on'); % Mostrar figura después de guardar
    catch ME
        fprintf('Error guardando la figura:\n%s\n', ME.message);
        if ishandle(f)
           set(f, 'Visible', 'on'); % Intentar mostrarla aunque no se guarde
        end
    end
    
    % -------- 3. Resumen y Reporte en Archivo --------
    fprintf('Generando resumen y reporte...\n');
    
    % Usar la tabla completa 'T' para el resumen global
    TMT = sum(T.MT); % Suma de todos los márgenes negativos (o cero)
    coordPairs   = T.pairID(T.MT == 0);
    uncoordPairs = T.pairID(T.MT < 0);
    numCoord   = numel(coordPairs);
    numUncoord = numel(uncoordPairs);
    
    fprintf('\n--- Resumen General (Todos los %d Pares) ---\n', numTotalPairs);
    fprintf('Pares Coordinados   (MT = 0)  : %d (%.1f%%)\n', numCoord, 100*numCoord/numTotalPairs);
    fprintf('Pares Descoordinados (MT < 0): %d (%.1f%%)\n', numUncoord, 100*numUncoord/numTotalPairs);
    fprintf('TMT Global (Suma de MT)     : %.6f s\n\n', TMT);
    
    % Generar archivo de reporte de texto
    reportBaseName = sprintf('Coordination_Report_%s', inputJsonName(1:end-5));
    reportFile = fullfile(reportDir, [reportBaseName, '.txt']);
    
    try
        fid = fopen(reportFile,'w');
        if fid == -1
            error('No se pudo abrir el archivo de reporte para escritura: %s', reportFile);
        end
    
        fprintf(fid, 'REPORTE DE COORDINACIÓN DE RELÉS\n');
        fprintf(fid, 'Archivo de entrada: %s\n', jsonFile);
        fprintf(fid, 'Fecha de generación: %s\n', datestr(now));
        fprintf(fid, 'CTI utilizado: %.2f s\n\n', CTI);
    
        fprintf(fid, '--- RESUMEN GLOBAL (%d Pares Totales) ---\n', numTotalPairs);
        fprintf(fid, 'Pares Coordinados   (MT = 0)  : %d (%.1f%%)\n', numCoord, 100*numCoord/numTotalPairs);
        fprintf(fid, 'Pares Descoordinados (MT < 0): %d (%.1f%%)\n', numUncoord, 100*numUncoord/numTotalPairs);
        fprintf(fid, 'Suma Total de Márgenes (TMT)  : %.6f s\n\n', TMT);
    
        fprintf(fid, '--- DETALLE DE PARES DESCOORDINADOS (MT < 0) [%d pares] ---\n', numUncoord);
        if numUncoord > 0
            % Mostrar detalles de los descoordinados (ordenados por MT)
            T_uncoord = T(T.MT < 0, {'pairID', 'Time_m', 'Time_b', 'delta_t', 'MT'});
            T_uncoord = sortrows(T_uncoord, 'MT', 'ascend');
            % Crear formato para tabla en texto
            header = sprintf('%-20s | %-10s | %-10s | %-10s | %-10s\n', 'Par (M–B)', 't_M (s)', 't_B (s)', 'Δt (s)', 'MT (s)');
            separator = repmat('-', 1, strlength(header)-1) + '\n'; % -1 para el newline
            fprintf(fid, header);
            fprintf(fid, separator);
            for i = 1:height(T_uncoord)
                fprintf(fid, '%-20s | %10.4f | %10.4f | %10.4f | %10.4f\n', ...
                        T_uncoord.pairID(i), T_uncoord.Time_m(i), T_uncoord.Time_b(i), ...
                        T_uncoord.delta_t(i), T_uncoord.MT(i));
            end
        else
            fprintf(fid, 'No hay pares descoordinados.\n');
        end
        
        fprintf(fid, '\n--- LISTA DE PARES COORDINADOS (MT = 0) [%d pares] ---\n', numCoord);
        if numCoord > 0
            % Opcional: Listar también los coordinados si se desea, o solo un conteo.
            % Para mantener el reporte conciso, solo listamos si son pocos, o los primeros N.
            maxListCoord = 50; 
            if numCoord <= maxListCoord
               fprintf(fid,'%s\n', join(coordPairs,newline));
            else
               fprintf(fid,'%s\n', join(coordPairs(1:maxListCoord),newline));
               fprintf(fid,'... y %d más.\n', numCoord - maxListCoord);
            end
        else
             fprintf(fid, 'No hay pares coordinados.\n');
        end
        
        fclose(fid);
        fprintf('Reporte guardado exitosamente en: %s\n', reportFile);
    
    catch ME
        fprintf('Error generando o guardando el archivo de reporte:\n%s\n', ME.message);
        if fid ~= -1 % Intentar cerrar si se abrió
            fclose(fid);
        end
    end
    
    fprintf('\nAnálisis completado.\n');