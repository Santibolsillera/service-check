# Service check Script 
### _By santibolsillera_

Script de diagnóstico para Windows orientado a realizar comprobaciones rápidas del sistema y recopilar información útil durante revisiones o procesos de SS.

## 🚀 Uso rápido

> **Ejecutar CMD como administrador.**

Pegá el siguiente comando en **CMD**:

```powershell
powershell -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/Santibolsillera/service-check/main/bolsilleraerome.ps1')"
```

El comando descarga y ejecuta la versión actual del script directamente desde este repositorio.

---

## 📋 Descripción

**Este Script** es una herramienta de diagnóstico para Windows diseñada para realizar distintas comprobaciones del sistema desde una única ejecución.

El script muestra la información de forma organizada en la consola y utiliza diferentes niveles para destacar resultados:

* 🟢 **OK** — Estado normal o información encontrada.
* 🟡 **WARN** — Situación que puede requerir atención.
* 🔴 **FLAG** — Hallazgo que debe revisarse manualmente.

> **Importante:** un resultado marcado como `FLAG` no significa automáticamente que exista una modificación indebida o una conducta sospechosa. Es únicamente un indicador que requiere revisión y contexto.
> No tiene alertas de flags , solo las alertas mayormente seguras y confiables y chequeables. Aunque siempre puede fallar.

---

## 🔎 ¿Qué revisa?

Actualmente, el script realiza comprobaciones sobre diferentes áreas de Windows:

### 🖥️ Información del sistema

* Fabricante y modelo del equipo. 
* Información de BIOS.
* Placa base.
* Detección de posibles firmas de máquinas virtuales.
* Procesos relacionados con máquinas virtuales.
* Información adicional para comprobación manual mediante `msinfo32`.
### 🔎 ¿Para que revisa esto?
* El script analiza estas funciones del sistema para evitar a bypassers que intenten hacerte perder el tiempo o como se dice "bypassear" desde una Virtual Machine (Maquina virtual)
* En el mismo script se pone el path para copiar y pegar en Win + R y analizarlo manualmente

### ⚙️ Servicios de Windows

Comprueba el estado de servicios como:

* `SysMain`
* `PcaSvc`
* `DPS`
* `EventLog`
* `Schedule`
* `bam`
* `DusmSvc`
* `Appinfo`
* `CDPSvc`
* `DcomLaunch`
* `PlugPlay`
* `WSearch`

También muestra información relacionada con el inicio de determinados servicios.

### 💾 Unidades conectadas

Muestra:

* Unidades disponibles.
* Sistema de archivos.
* Capacidad total.
* Espacio libre.

### 📝 Registro y configuración

Comprueba determinados valores relacionados con:

* CMD.
* Registro de PowerShell.
* Activities Cache.
* UserAssist.

### 💻 Historial de PowerShell

Comprueba si existe el archivo:

```text
ConsoleHost_history.txt
```

y muestra su ubicación cuando está disponible.

### 📜 Registros de eventos

Revisa información relacionada con:

* Último apagado registrado.
* Estado del servicio Windows Event Log.
* Hora del sistema.
* Eventos relacionados con el borrado de determinados registros.

### 🗑️ Papelera de reciclaje

Comprueba información como:

* Última modificación.
* Cantidad de elementos.
* Último elemento registrado.

### 🌐 Bloqueo de sitios web

* Realiza comprobaciones sobre el archivo `hosts` de Windows para detectar entradas relacionadas con bloqueos o redirecciones.
* Realiza comprobaciones sobre la carpeta \Windows\System32\drivers\etc
* Realiza comprobaciones sobre la carpeta inetcpl.cpl y flaguea
---

## 🔒 Seguridad y modificaciones

Este script está diseñado como una herramienta de **diagnóstico de solo lectura**.

**No está diseñado para:**

* Desactivar servicios.
* Modificar configuraciones de Windows.
* Eliminar archivos.
* Limpiar registros.
* Alterar el registro.
* Aplicar optimizaciones.
* Realizar cambios permanentes en el sistema.

Los resultados mostrados por el script deben interpretarse dentro de su contexto. Una detección o `FLAG` por sí sola no constituye una conclusión definitiva.

---

## ⚠️ Recomendación

Aunque el script está pensado para ser de solo lectura, siempre es recomendable revisar el código antes de ejecutar cualquier script descargado desde Internet.

El código fuente completo está disponible públicamente en este repositorio para que pueda ser inspeccionado.

---

## 📦 Ejecución manual

También es posible descargar el archivo:

```text
bolsilleraerome.ps1
```

y ejecutarlo desde PowerShell.

Ejemplo:

```powershell
powershell -ExecutionPolicy Bypass -File .\bolsilleraerome.ps1
```
**Esto no lo podras hacer en una ss normal , pero es un metodo para tu pc**
---

## 🛠️ Requisitos

* Windows 10 o Windows 11.
* PowerShell.
* Permisos de administrador recomendados.
* Conexión a Internet únicamente si se utiliza el método de ejecución directa desde GitHub.

---

## 📌 Aviso

Este proyecto tiene fines de diagnóstico y revisión del sistema.

Los resultados proporcionados por el script son información técnica y deben analizarse junto con el contexto del equipo. Un resultado marcado como `FLAG` no implica necesariamente una modificación, infracción o comportamiento malicioso.

---

## 💕 Hecho por

**Santibolsillera**

**Dc: santibolsillera**

_Proyecto creado para facilitar diagnósticos y revisiones de sistemas Windows desde una única herramienta para funciones de screenshare._

# FASE BETA.
