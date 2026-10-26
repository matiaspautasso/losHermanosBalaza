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

- **Lectura:** F2 firma, F1 peso, F28 fecha, F31 lista de PLU (solo número + versión),
  **F62 ficha completa de un PLU** (nombre, 2 precios, sector, tipo, tara, gestión; 159 bytes),
  **F63 formato de precio/moneda**, F72 ventas por ticket.
- **F72 por línea:** ticket, fecha/hora, vendedor (2 díg: se vieron 01, 02, 03), PLU (4), sector,
  unidades, gramos, drenado, importe (×100). **No trae** nombre ni precio unitario (usar F62).
  Rango siempre **ayer–hoy** (`--desde 251026 --hasta 261026`); un solo día da `E7`.
- **Balanza en 6:0 (sin coma)** ✅ HW (F2 `D0` + F63): los precios son **pesos enteros** hasta
  $999.999. Los decimales (func 42/F64) **no se tocan**.
- **Precios — receta verificada en hw (2026-10-26):** **F4 divide el campo de precio por 100**
  (`013000` ⇒ $130; tope $9.999,99); **F33 usa pesos enteros** (`013000` ⇒ $13.000). Por eso:
  alta/datos con **F4 con Precio1/2 = `000000`**, precio con **F33** (`PLU4+Versión+P1(6)+P2(6)`),
  verificación con **F62**. El teclado de la balanza también carga pesos enteros.
- **F4 (registro completo):** PLU(4)+Versión(1)+Nombre(18)+Precio1(6)+Precio2(6)+Código(5)+
  Sección(2)+DíasVto(4)+Tipo(1 P/U)+Tara(6)+MantenerTotales(1 N/M)+Ingredientes(1).
  `MantenerTotales=N` al crear o cambiar la condición pesable↔unitario. **No reenviar F4 solo para
  cambiar el precio** (usar F33): reescribe el PLU completo.
- **F5** borra un PLU ✅ HW (ACK; luego F62/F33 dan `E7`, F31 baja de 422 a 421; irreversible, borra
  también el acceso directo). **F3 no se usa**; la ficha se lee con **F62**.
- **Versión/gestión:** F4 y F33 llevan una letra de versión; **mandar siempre `1`**. Queda como
  gestión del PLU y F31 (`V<d>`) / F62 la devuelven: `1` = escrito por el ERP, `0` = editado en la
  balanza. Un PLU `V1` que pasa a `V0` fue modificado por teclado (detección de cambios con un F31).
- **Nombres en Latin-1** (1 byte/carácter, `Ñ`=`0xD1`), 18 caracteres con espacios. No UTF-8.
- PLU inexistente: `E6` (nunca cargado) o `E7` (recién borrado).
- **E3 = balanza ocupada** (ticket recién impreso/abierto o menú): responde `E3` a **todas** las
  funciones, también a las de lectura. Esperar a que vuelva a la pantalla principal y reintentar.
- Si el texto de otra versión del manual (PLU de 6 dígitos, 5 listas de precio, 19 bytes en F33)
  contradice al equipo, **manda el equipo**: PLU de 4 dígitos, 2 listas, F33 de 17 bytes.

## Qué falta verificar en hardware (anotar en `descubrimientos/` con la respuesta REAL)

- ✅ **Resueltos (2026-10-26):** H1 (decimales/precios), H2 (pesable `P`), **H6** (F33 con cualquier
  letra de versión), **H7** (detección de cambios con la letra `V`), **H8** (F5), **H9**
  (`MantenerTotales=M`, PLU unitario con F33, `Ñ`/acentos). F62 y F63 probadas. Ciclo completo
  alta → leer → cambiar precio → borrar → recrear verificado sobre el PLU 8000.
- **H5 cerrado:** la balanza soporta **hasta 4 vendedores** (`01`–`04`), dato del cliente; no se
  testea.
- **H3 y H4 resueltos (2026-10-26):** con un ticket abierto (vendedor `04`) la balanza acepta
  F62/F33/F4 (ACK) y F72 entrega los tickets cerrados de otro vendedor (`03`); el ticket abierto no
  aparece hasta imprimirse. F72 pesa ~7 KB: leer hasta `…;F`+XOR con buffer grande (>4 KB) y
  reintentar ante XOR inválido. Los vendedores A–D de la balanza salen como `01`–`04`.
- **Regla (usuario): NO cambiar precios con un ticket abierto**, aunque la balanza dé ACK. Vendedores
  **A=01, B=02, C=03, D=04** (confirmado).
- **Sin pendientes de hardware** para el CRUD y la sync bilateral. Sin verificar: si cambiar un
  precio afecta a un ticket abierto que ya lo contiene (por eso la regla de arriba).
- **PLU 8000** queda como "PRUEBA KG", pesable, $20.000 / $15.000, gestión 1 (no se borra).
- **Descartadas a propósito:** F61 (no hace falta, F4 alcanza) y F64/func 42 (globales; la balanza
  ya está en 6:0). No sin autorización explícita.
- El kit (`kit-diagnostico-balanza.exe`) **no trae F33, F62 ni F63**: se probaron armando la trama
  a mano por el puerto serie (115200 8N1). Hay que agregarlos al kit en el repo del ERP.

## Reglas de seguridad (IMPORTANTE)

- Frenar el puente antes de usar el kit (comparten el COM). El kit **no** cierra procesos solo.
- La escritura (F4/F5) está limitada al **PLU de prueba 8000** y es **dry-run por defecto**: solo
  escribe con `--enviar` explícito; el borrado pide además `--confirmar-borrado`.
- **No cambiar los decimales globales** (func 42/F64) ni borrar PLU sin autorización explícita del
  usuario: afecta al equipo real en producción.
- Toda escritura de prueba (F4, F33, F5) va **solo sobre el PLU 8000**. Si hace falta tocar otro,
  pedir autorización explícita y respaldarlo antes con F62.
- Una función se considera **PROBADA EN HARDWARE** solo cuando hay una respuesta real (ACK/datos)
  en un informe. Mantené separado lo SIMULADO (dry-run) de lo VERIFICADO al actualizar los docs.
