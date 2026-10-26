@echo off
REM Lanzador del kit de diagnostico de la balanza.
REM Doble clic = relevamiento de lectura completo (no escribe nada) y deja la ventana abierta.
REM Para un comando puntual: arrastrar no; abrir CMD y usar el .exe (ver LEEME.txt).
cd /d "%~dp0"
"%~dp0kit-diagnostico-balanza.exe" %*
echo.
echo ---------------------------------------------------------------------
echo  Termino. El informe quedo en esta carpeta (informe-balanza-*.txt).
echo ---------------------------------------------------------------------
pause
