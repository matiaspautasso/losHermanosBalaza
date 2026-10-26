# Balanza Systel Cuora — carpeta de trabajo en la PC del cliente

Esta carpeta es portátil y autocontenida. Se copia a la PC del cliente (la que tiene la balanza
conectada) y se corre Claude Code **acá adentro** para: ver cómo responde la balanza real, anotar
descubrimientos y actualizar la documentación. No necesita el repo del ERP ni instalar Node: el
diagnóstico se hace con el ejecutable del kit.

## Mapa de la carpeta

- `kit/` — ejecutable de diagnóstico (ver `kit/LEEME.txt`).
  - `kit-diagnostico-balanza.exe` + `@serialport+bindings-cpp.node` (van juntos) + `diagnostico.bat`.
  - Genera `kit/informe-balanza-*.txt` con cada corrida.
- `protocolo-systel/` — manuales oficiales de Systel (PDF) + su `texto-extraido/` (los mismos en
  `.txt`, para leer/grepear sin herramientas de PDF). **El equipo real usa el V6.0** (ver firma).
- `descubrimientos/` — nuestros hallazgos, en markdown. **Es lo que hay que mantener al día.**
  - `protocoloBalanzaCuora.md` — funciones, registro F4, decimales, firma.
  - `29_balanzaCapturaVendedorYSyncPreciosBilateral.md` — la task con los bloqueantes.

## El equipo (confirmado)

- Systel **Cuora MAX**, protocolo **V6.0** (firma real `F2000C030000S0060P08000A060D0`).
- Serie: **115200 8N1**, dirección **20**, adaptador **USB FTDI** (VID 0403 / PID 6001), capacidad
  30 kg, 8000 PLU, PLU de **4 dígitos**.
- Trama: `[dirección][función][datos ASCII][XOR]`. Error = datos `E<dígito>`. Escritura OK = `ACK`.

## Cómo ver cómo funciona la balanza (correr el kit)

1. **Frenar el puente** (toma el COM): CMD como admin →
   `schtasks /end /tn "ErpLosHermanos-PuenteBalanza"` y `taskkill /IM puente-balanza.exe /F`.
2. Relevamiento de lectura (no escribe): doble clic en `kit/diagnostico.bat`, o desde CMD en `kit/`:
   `kit-diagnostico-balanza.exe` (corre F2 firma, F1 peso, F28 fecha, F31 PLU, F72 tickets).
3. Leer el `kit/informe-balanza-*.txt` resultante: trae el hex crudo + la interpretación de cada
   respuesta REAL. Eso es la fuente de verdad del hardware.
4. Al terminar, reactivar el puente: `schtasks /run /tn "ErpLosHermanos-PuenteBalanza"`.

Comandos sueltos: `... detectar | firma | peso | fecha | plus | tickets [--desde DDMMAA --hasta DDMMAA]`.

## Resumen de protocolo (detalle en `descubrimientos/`)

- **Lectura:** F2 firma (incluye decimales), F1 peso, F28 fecha, F31 lista de PLU (solo número +
  versión; sin nombre ni precio), F72 ventas por ticket.
- **F72 por línea:** ticket, fecha/hora, vendedor (2 díg), PLU (4), sector, unidades, gramos,
  drenado, importe (centavos ×100). **No trae** nombre de producto ni precio unitario de lista.
- **F4 (escritura, registro completo):** PLU(4)+Versión(1)+Nombre(18)+Precio1(6)+Precio2(6)+
  Código(5)+Sección(2)+DíasVto(4)+Tipo(1 P/U)+Tara(6)+MantenerTotales(1 N/M)+Ingredientes(1).
  `MantenerTotales=N` al crear o cambiar la condición pesable↔unitario.
- **F33** cambia solo precios; **F5** borra un PLU; **func 42** fija decimales (0 o 2, global).
- **Precios:** el campo es de 6 dígitos "sin coma"; el máximo depende de los decimales (func 42):
  0 decimales ⇒ $999.999, 2 decimales ⇒ $9.999,99. El importe de F72 va siempre ×100.

## Qué falta verificar en hardware (anotar en `descubrimientos/` con la respuesta REAL)

- **H1 decimales:** la firma dice `D0` (0 decimales) pero antes se vio `001000`=$10,00 (2 decimales).
  Resolver: `firma` + escribir el PLU 8000 a $13.000 (`f4 ... --enviar`) y ver cómo lo muestra.
- **H2 tipo kg/unidad:** reconfirmar que el registro F4 completo deja el PLU como pesable.
- **H3** F4 con un ticket abierto en la balanza; **H4** dos vendedores con tickets simultáneos;
  **H5** confirmar el vendedor 04.

## Reglas de seguridad (IMPORTANTE)

- Frenar el puente antes de usar el kit (comparten el COM). El kit **no** cierra procesos solo.
- La escritura (F4/F5) está limitada al **PLU de prueba 8000** y es **dry-run por defecto**: solo
  escribe con `--enviar` explícito; el borrado pide además `--confirmar-borrado`.
- **No cambiar los decimales globales** (func 42) ni borrar PLU sin autorización explícita del
  usuario: afecta al equipo real en producción.
- Una función se considera **PROBADA EN HARDWARE** solo cuando hay una respuesta real (ACK/datos)
  en un informe. Mantené separado lo SIMULADO (dry-run) de lo VERIFICADO al actualizar los docs.
