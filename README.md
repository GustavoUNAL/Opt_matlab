# Opt_matlab – Coordinación Adaptativa de Protecciones

> **Proyecto:** Automatización completa del flujo _datos → optimización → análisis_ para la coordinación de relés de sobrecorriente (IEC Standard Inverse) en la micro‑red IEEE‑33 nodos modificada.
>
> **Autor principal:** Gustavo Arteaga  
> **Última actualización:** {{DATE}}

---

## 1 · Estructura general del proyecto

```
opt_matlab/
├─ data/
│  ├─ raw/          # JSON de entrada sin procesar (pares + valores Ishc)
│  └─ processed/    # JSON con resultados optimizados
│
├─ results/
│  ├─ figures/      # PNG/FIG generados automáticamente
│  └─ reports/      # TXT con resúmenes y tablas de MT
│
├─ scripts/
│  ├─ create_data_template_optimized.m   # genera plantilla de datos de entrada
│  ├─ optimization.m                     # heurística principal de optimización
│  ├─ analyze_results_automation.m       # analítica rápida (sin figuras)
│  └─ analyze_results_optimized.m        # analítica + figuras de MT/TDS/Pick‑up
│
├─ test/                                 # (opcional) pruebas unitarias / snippets
├─ Opt_matlab.prj                        # proyecto MATLAB (abre rutas)
└─ README.md                             # este archivo
```

---

## 2 · Requisitos
* **MATLAB R2020a** o superior (se usa `jsondecode`/`jsonencode`, `tiledlayout`).
* Toolboxes: _ninguno adicional_ (todo es MATLAB base).
* El árbol de carpetas anterior debe mantenerse para que las rutas relativas funcionen.

---

## 3 · Flujo de trabajo recomendado
1. **Preparar datos de entrada**  
   *Ubicación:* `data/raw/independent_relay_pairs_scenario_base.json`  
   Si necesitás una plantilla vacía: `create_data_template_optimized.m` la genera.
2. **Optimizar ajustes**  
   ```matlab
   >> run scripts/optimization
   ```
   Genera `optimized_relay_values_scenario_base.json` en `data/processed`.
3. **Analizar resultados**  
   ```matlab
   >> run scripts/analyze_results_optimized
   ```
   Produce:
   * PNG + FIG con gráfica de MT, TDS y Pick‑up → `results/figures/`
   * Reporte TXT detallado → `results/reports/`

> Para una versión sin figuras (solo TXT): `analyze_results_automation.m`.

---

## 4 · Descripción de cada script

### 4.1 `create_data_template_optimized.m`
Crea un JSON de muestra con la siguiente estructura mínima por par de relés:
```json
{
  "scenario_id": "scenario_base",
  "main_relay":   {"relay":"R01","Ishc":800},
  "backup_relay": {"relay":"R02","Ishc":600}
}
```
> **Uso:**
> ```matlab
> >> run scripts/create_data_template_optimized
> ```
> Guarda `template_input.json` en `data/raw/`.

---

### 4.2 `optimization.m`
Ejecuta la heurística iterativa que ajusta **TDS** y **pickup** para cada relé con las siguientes características:
* Curva IEC Standard Inverse (`K=0.14`, `N=0.02`).
* Lógica adaptativa con dos niveles de corrección (agresivo / normal) según el MT.
* Convergencia cuando todos los MT ≥ −0.009 s o estancamiento de TMT.
* Parámetros configurables en la cabecera del script.

**Salida:**
* `optimized_relay_values_scenario_base.json` en `data/processed/`.

**Ejecutar:**
```matlab
>> run scripts/optimization
```

---

### 4.3 `analyze_results_automation.m`
Versión liviana para Resumen de MT sin generar figuras.  
Lee los resultados optimizados y emite **pairs_MT_automation_report.txt** con:
* Conteo de pares coordinados vs descoordinados.
* Lista ordenada de los pares con MT < 0.

**Ejecutar:**
```matlab
>> run scripts/analyze_results_automation
```

---

### 4.4 `analyze_results_optimized.m`
Herramienta de análisis completo:
* Genera tabla ordenada por severidad (MT ascendente).
* Figura doble (barra MT + líneas TDS/Pick‑up) – PNG y FIG.
* Reporte de texto consolidando métricas globales y listas de pares.

Las rutas relativas se auto‑configuran; solo asegurate de tener el JSON optimizado en `data/processed/`.

**Ejecutar:**
```matlab
>> run scripts/analyze_results_optimized
```

---

## 5 · Notas importantes
* Todos los scripts asumen que se ejecutan **desde el directorio de proyecto abierto** o que `Opt_matlab.prj` está cargado (lo cual fija `projectRoot`).
* Si ejecutás un script suelto y falla con _“ruta no encontrada”_, verificá que la variable `rootDir` apunte a la raíz correcta.
* Los valores de **CTI**, **MIN_TDS**, **MAX_TDS** y reglas de ajuste se pueden tunear en el bloque “CONFIGURACIÓN” de `optimization.m`.
* La precisión final se redondea a **5 decimales** para exportar.

---

