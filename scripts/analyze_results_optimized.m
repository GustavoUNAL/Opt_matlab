%Cálculo de MT = (Δt - |Δt|)/2  y reporte de coordinación

% -------------------------------------------------------------------------
clear; clc; close all;

% ---------------------- CONFIGURACIÓN ------------------------------------
CTI      = 0.20;    % Coordination Time Interval (s)
maxPairs = 100;     % Máx. de pares a mostrar en gráficos y reporte
inputJsonName = 'independent_relay_pairs_scenario_base_optimized.json';
% -------------------------------------------------------------------------

% ---------------------- RUTAS RELATIVAS ----------------------------------
try
    scriptFullPath = mfilename('fullpath');
    scriptDir      = fileparts(scriptFullPath);
    if isempty(scriptDir), scriptDir = pwd; end          % si se corre sin guardar
    projRoot       = fileparts(scriptDir);               % ../ (raíz proyecto)

    jsonFile  = fullfile(projRoot,'data','processed',inputJsonName);
    resDir    = fullfile(projRoot,'results');
    repDir    = fullfile(resDir,'reports');
    figDir    = fullfile(resDir,'figures');
    cellfun(@(d) ~isfolder(d) && mkdir(d), {resDir,repDir,figDir});

    ts         = datestr(now,'yyyymmdd_HHMMSS');
    reportFile = fullfile(repDir,['results_MT_optimized_',ts,'.txt']);
    figureFile = fullfile(figDir,['MT_TDS_Pickup_optimized_',ts,'.png']);

    fprintf('Entrada : %s\n', jsonFile);
    fprintf('Reporte : %s\n', reportFile);
    fprintf('Figura  : %s\n', figureFile);
catch ME
    error('No se pudieron configurar las rutas:\n%s', ME.message);
end
% -------------------------------------------------------------------------

%% 1) Leer JSON
try
    S = jsondecode(fileread(jsonFile));
catch ME
    error('Problema leyendo/decodificando el JSON:\n%s', ME.message);
end
if ~isstruct(S) || isempty(S)
    error('JSON vacío o formato incorrecto.');
end

n        = numel(S);
vars     = {'pairID','TDSm','TDSb','PUm','PUb','MT','TimeOutM','TimeOutB'};
varTypes = repmat({'double'},1,numel(vars)); varTypes{1} = 'string';
T = table('Size',[n numel(vars)],'VariableTypes',varTypes,'VariableNames',vars);

idx = 0;
for k = 1:n
    if ~all(isfield(S(k),{'main_relay','backup_relay'})), continue; end
    m = S(k).main_relay;  b = S(k).backup_relay;
    if ~all(isfield(m,{'relay','TDS','pick_up','Time_out'})) || ...
       ~all(isfield(b,{'relay','TDS','pick_up','Time_out'})), continue; end

    idx = idx + 1;
    T.pairID(idx)   = string(m.relay) + "-" + string(b.relay);
    T.TDSm(idx)     = m.TDS;          T.TDSb(idx)  = b.TDS;
    T.PUm(idx)      = m.pick_up;      T.PUb(idx)   = b.pick_up;
    T.TimeOutM(idx) = m.Time_out;     T.TimeOutB(idx) = b.Time_out;

    dt              = b.Time_out - m.Time_out - CTI;
    T.MT(idx)       = (dt - abs(dt)) / 2;          % igual a min(dt,0)
end
T = T(1:idx,:);                     % recorta a válidos
T = sortrows(T,'MT','ascend');
if isempty(T)
    error('Sin pares válidos para analizar.');
end

%% 2) Selección para mostrar/graficar
Tplot   = T(1:min(maxPairs,height(T)),:);
catPair = categorical(Tplot.pairID);
xNums   = 1:height(Tplot);

%% 3) Gráfica
f = figure('Color','w','Position',[50 50 1400 800],'Name','Relay Coordination');
tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

% (A) MT
nexttile;
bh = bar(catPair,Tplot.MT,'FaceColor','flat'); hold on;
yline(0,'k--','CTI cumplido','LabelHorizontalAlignment','left','FontAngle','italic');
for i = 1:height(Tplot)
    if Tplot.MT(i) == 0
        bh.CData(i,:) = [0.20 0.60 0.20];   % verde coordinado
    else
        bh.CData(i,:) = [0.85 0.20 0.20];   % rojo descoordinado
    end
end
ylabel('MT (s)');
title('Margen de Coordinación');
grid on; set(gca,'XTickLabel',[]);

% (B) TDS y Pickup
nexttile;
yyaxis left
plot(xNums,Tplot.TDSm,'^-','LineWidth',1.2,'MarkerFaceColor',[0 0.45 0.74]); hold on;
plot(xNums,Tplot.TDSb,'v-','LineWidth',1.2,'MarkerFaceColor',[0.85 0.33 0.10]);
ylabel('TDS');

yyaxis right
plot(xNums,Tplot.PUm,'o--','LineWidth',1.2,'MarkerFaceColor','w');
plot(xNums,Tplot.PUb,'s--','LineWidth',1.2,'MarkerFaceColor','w');
ylabel('Pickup (A)');

set(gca,'XTick',xNums,'XTickLabel',string(catPair),'XTickLabelRotation',45);
xlabel('Par Main-Backup');
title('Ajustes TDS (sólidos) y Pickup (punteados)');
grid on; xlim([0.5 height(Tplot)+0.5]);

%% 4) Guardar figura
try
    print(f,figureFile,'-dpng','-r300');
    fprintf('Figura guardada.\n');
catch ME
    warning('No se pudo guardar la figura:\n%s', ME.message);
end

%% 5) Resumen y reporte
coord   = Tplot.pairID(Tplot.MT==0);
uncoord = Tplot.pairID(Tplot.MT<0);
TMT     = sum(Tplot.MT);

fid = fopen(reportFile,'w','n','UTF-8');
fprintf(fid,'REPORTE DE COORDINACIÓN DE RELÉS\n\n');
fprintf(fid,'Archivo: %s\nFecha  : %s\nCTI    : %.2f s\n\n', jsonFile, datestr(now), CTI);
fprintf(fid,'Pares analizados         : %d\n', height(Tplot));
fprintf(fid,'Coordinados (MT = 0)     : %d\n', numel(coord));
fprintf(fid,'Descoordinados (MT < 0)  : %d\n', numel(uncoord));
fprintf(fid,'TMT mostrado             : %.6f s\n\n', TMT);

fprintf(fid,'--- PARES DESCOORDINADOS ---\n');
if isempty(uncoord)
    fprintf(fid,'(Todos coordinados)\n');
else
    fprintf(fid,'%s\n', join(uncoord,newline));
end
fclose(fid);
fprintf('Reporte guardado.\n');

fprintf('\nAnálisis completado.\n');
