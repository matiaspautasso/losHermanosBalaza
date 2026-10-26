# Protocolo balanza Systel Cuora — hallazgos con el equipo real

> Base para la task [29](../../tasks/pending/general/29_balanzaCapturaVendedorYSyncPreciosBilateral.md).
> Complementa la spec [ventas/11](../../specs/ventas/11_integracionBalanzaPuenteLocal.md).
> **Regla de fuente de verdad:** manda lo **VERIFICADO en el equipo**. El manual oficial (CUORA MAX
> V6.0 Rev 06) se usa como guía, pero donde el equipo lo contradice gana el equipo. Cada dato lleva
> su estado: ✅ **HW** (respuesta real en un informe/lectura), 📖 **manual** (solo documentado),
> ⚠️ **contradicho** (el equipo se comporta distinto al manual/otras docs).
>
> Historial: 2026-10-23 investigación inicial (COM6) · **2026-10-26 sesión en la PC del cliente
> (COM3, FTDI 0403:6001)** que corrigió decimales, precios y descubrió F62/F63.

Trama en ambos sentidos: `[dirección][función][datos ASCII][XOR]` (XOR de todos los bytes
previos, sin terminador). Dirección 20 (`0x14`), 115200 8N1. Respuesta de error: datos `E<dígito>`.
Escritura aceptada: `ACK`. El manual llama "CRC" a ese último byte; es el XOR.

Códigos de error: `E3` **balanza ocupada** (ver "Estado ocupado"), `E5` formato inválido, `E6`
registro inválido/PLU inexistente, `E7` sin datos / rango inválido.

## Estado ocupado (E3) — afecta a TODAS las funciones ✅ HW

Después de imprimir un ticket, o con un menú/ticket abierto, la balanza responde `E3` a **cualquier**
función, incluso a las de solo lectura (F1, F28, F62, F72). Se libera al volver a la pantalla
principal de venta (a veces hay que esperar o reiniciar la balanza). El driver debe reintentar con
espera y exponer el estado "balanza ocupada", sin tratarlo como error fatal.

## Equipo y configuración confirmados ✅ HW

- Systel **Cuora MAX**, protocolo **V6.0** (firma `F2000C030000S0060P08000A060D0`), 30 kg, 8000 PLU,
  PLU de **4 dígitos**, 60 accesos directos. Hoy hay **422 PLU** cargados.
- **Formato de precio 6:0 (sin coma)**: F2 (`D0`) y F63 coinciden. El cliente lo configuró en
  `Configuración > Moneda > Coma de precio`. Los precios son **pesos enteros**, hasta $999.999.

## Resumen de funciones

| Func | Qué hace | Datos | Respuesta | Estado |
|---|---|---|---|---|
| 1 | Peso del plato | — | peso, estable, tara | ✅ HW |
| 2 | Firma del equipo | — | firma (incluye `D`) | ✅ HW |
| 28 | Fecha/hora | — | `HH:MM:SS DD/MM/AA` | ✅ HW |
| 31 | Lista de PLU cargados | vacío | `N0001V0N0002V0…F` | ✅ HW |
| **62** | **Leer un PLU completo** | PLU(4) | 159 bytes (ver abajo) | ✅ HW |
| **63** | **Leer formato de precio/moneda** | — | `coma(1) + moneda(3)` | ✅ HW |
| 64 | Setear coma/moneda (global) | `coma(0\|2)` + moneda(3) | `OK` | 📖 manual, **no probada** |
| 3 | Leer ficha de un PLU | — | — | no se usa; **F62 la reemplaza** |
| 4 | Alta/modificación completa de PLU | registro (ver abajo) | `ACK`/`E<n>` | ✅ HW (⚠️ escala el precio) |
| **33** | **Cambio de precios (pesos enteros)** | PLU(4)+Ver(1)+P1(6)+P2(6) | `ACK`/`E7` | ✅ HW |
| **5** | **Borrar un PLU** | PLU(4) | `ACK`/`E<n>` | ✅ HW |
| 42 | Visualización de decimales (global) | `0`\|`2` | `ACK` | 📖 manual, no necesaria |
| 61 | PLU extendido (nutricional, EAN…) | registro largo | `ACK`/`E<n>` | 📖 manual, no probada |
| 72 | Ventas por ticket | `DDMMAA`+`DDMMAA` | líneas `…;F` | ✅ HW |

## Precios — la regla verificada ✅ HW (⚠️ contradice docs anteriores)

Con la balanza en 6:0 **cada función interpreta el campo de precio distinto**:

| Vía | `013000` se guarda/vende como | Tope | Uso |
|---|---|---|---|
| **F4** (campo Precio1/2) | **$130** (÷100) | $9.999,99 | **no usar para el precio real** |
| **F33** | **$13.000** (pesos enteros) | $999.999 | **vía oficial para precios** |
| Teclado de la balanza | pesos enteros | $999.999 | el cliente carga así |
| **F62** (lectura) | devuelve el precio **efectivo** (`000130` tras F4, `013000` tras F33) | — | verificación |

Pruebas del 2026-10-26 sobre el PLU 8000:
- F4 `013000` → pantalla "130"; 1,025 kg vendidos dieron $133 en F72 (130 × 1,025 = 133,25).
- F4 `999999` → la pantalla mostró "10000" ($9.999,99 redondeado).
- F33 `013000` → pantalla 13000; 3,155 kg dieron **$41.015** en F72 (13.000 × 3,155).
- Teclado 10000 → 3,155 kg dieron $31.550; teclado 20000/15000 → F62 devolvió `020000`/`015000`.
- Secuencia **F4 con precio `000000` + F33 `012500`** → F62 devolvió `012500`/`012500`. ✅

**Qué NO es cierto (corregido):** que "el máximo depende de la func 42", que "la firma `D0` es
engañosa" o que "la balanza trabaja con 2 decimales". La balanza **está** en 6:0; lo que ocurre es
que **F4 escala el campo ×1/100 independientemente del formato**. F2 y F63 son confiables.

⚠️ No probado: qué hace F33 si la balanza se pasa a 4:2 (probablemente centavos). El driver debe
leer **F63 al conectar** y no sincronizar precios si la coma no es `0`.

## F63 — formato de precio y moneda ✅ HW

Solicitud `14 3F 2B`. Respuesta real: `14 3f 30 24 00 00 3f` → coma `0` (= 6:0) + moneda `"$"` (relleno
con `0x00`). `0` = formato 6:0, `2` = formato 4:2. Es de solo lectura.

## F62 — leer un PLU completo ✅ HW

Solicitud: `14 3E` + PLU(4 dígitos) + XOR. Respuesta de **159 bytes** (incluye `14 3E` y XOR). Offsets
dentro del bloque de **datos** (después de `14 3E`):

| Offset | Largo | Campo | Ejemplo real (PLU 0112) |
|---|---|---|---|
| 0 | 4 | PLU | `0112` |
| 4 | 1 | **Gestión** (`0` balanza / `1` PC) | `0` (PLU 8000 escrito por PC: `1`) |
| 5 | 18 | Nombre (relleno con espacios) | `PATITA LA PEQUE?A ` |
| 23 | 6 | Precio lista 1 (pesos enteros en 6:0) | `006500` |
| 29 | 6 | Precio lista 2 | `005000` |
| 35 | 5 | Código de PLU | `00112` |
| 40 | 2 | Sector | `02` |
| 42 | 4 | Días de vencimiento | `0000` |
| 46 | 1 | Tipo de venta (`P/U/E/C`) | `P` |
| 47 | 4 | Tara (g) | `0000` |
| 51 | 4 | % agua ×100 | `0000` |
| 55 | 1 | Tabla nutricional (`S/N`) | `N` |
| 56… | resto | tabla nutricional, origen, conservación, receta, lote, EAN, ingredientes | valores por defecto |

- Devuelve **2 listas de precio** (no 5, no hay rangos): el texto de otra versión del manual que
  habla de 5 listas y PLU de 6 dígitos **no aplica** a este firmware.
- PLU inexistente → `E6` (si nunca estuvo cargado, ej. 8001) o `E7` (recién borrado, ej. 8000).
  El driver debe tratar `E6`/`E7` como "no existe".
- **Cierra el hueco** de "no se puede leer la ficha de un PLU": se puede respaldar un PLU antes de
  reescribirlo y verificar un cambio de precio leyendo de vuelta.
- Costo: ~0,5–1 s por PLU; leer los 422 lleva unos minutos (F31 + F62 por cada uno).
- **Codificación del nombre ✅ HW: Latin-1 / CP1252, 1 byte por carácter.** `Ñ` = `0xD1`, `Ú` =
  `0xDA` (el PLU 0112 de la balanza guarda `PEQUEÑA` con `d1`; escribir `PRUEBA ÑANDÚ KG` con esos
  bytes volvió idéntico en F62). Leer/escribir con `latin1`, **no UTF-8** (la consola mostraba `?`
  solo por la decodificación ASCII). Rellenar con espacios a 18; truncar si pasa.

## F31 — lista de PLU ✅ HW

Sin datos devuelve todos los PLU (422), `N<plu4>V<d>` por cada uno. Con cualquier dato responde
`E5`: no lee un PLU puntual. No trae nombre ni precio (para eso, F62). La letra `V` es la
**gestión**: quién modificó el PLU por última vez (✅ HW). Escrito por PC con versión `1` ⇒ `V1`;
si después se edita por teclado en la balanza ⇒ vuelve a `V0` (y F62 muestra gestión `0`). Hoy los
422 PLU están en `V0` salvo los que escribe el ERP. Es la señal barata de cambios (ver abajo).

## Detección de cambios hechos en la balanza ✅ HW (sync balanza → sistema)

No existe fecha de modificación. Pero la **gestión** cambia según quién tocó el PLU por última vez:
- El ERP escribe siempre con **versión `1`** (en F4 y en F33) ⇒ el PLU queda `V1`.
- Si el cliente lo edita por teclado ⇒ pasa a `V0`.
- **Algoritmo:** una llamada a **F31** da la letra de los 422 PLU. Un PLU que el ERP dejó en `V1`
  y ahora aparece en `V0` fue modificado en la balanza ⇒ leerlo con **F62** y traer nombre/precios
  al sistema (y volver a marcarlo `V1` con F33 si se quiere re-tomar la gestión).
- **Límite:** un PLU que nunca escribió el ERP está en `V0` siempre, así que sus ediciones no se
  distinguen por la letra. Para esos hay que comparar con F62 (lectura periódica) o hacer una
  primera "adopción" que los escriba con F33 versión `1` (sin cambiar el precio).
- Altas y bajas hechas en la balanza se ven comparando la lista de F31 (PLU nuevos/ausentes).

## F4 — alta / modificación de PLU ✅ HW

Registro (PLU de 4 dígitos; ACK verificado):

```
PLU(4) + Versión(1) + Nombre(18) + Precio1(6) + Precio2(6) + Código(5) + Sección(2) +
DíasVto(4) + TipoVenta(1 P/U) + Tara(6) + MantenerTotales(1 N/M) + Ingredientes(1 S/N)
```

- ✅ Crea o reescribe el PLU **completo** (lo no enviado queda en 0). Probado con `P` (pesable): F62
  confirma `P`, sector y nombre.
- ⚠️ **El precio de F4 se divide por 100** (ver tabla). Para el driver: **mandar `000000` en
  Precio1/2 y aplicar el precio real con F33**.
- `MantenerTotales`: `N` pone en 0 los acumulados; el manual exige `N` al crear o al cambiar
  unitario↔pesable. ✅ HW: `M` da ACK al modificar un PLU existente (nombre con `Ñ`/`Ú`), `N` da ACK
  al crear de cero y al cambiar `P`↔`U`. Los totales acumulados no se pueden leer por protocolo,
  así que la conservación con `M` no se verificó. **No reenviar F4 para cambiar solo el precio**
  (usar F33): evita perder totales y campos que no maneja el ERP.
- ✅ HW: **alta de un PLU nuevo** (tras F5): F4 con precio `000000` + F33 `020000/015000` ⇒ F62 lo
  devuelve completo (gestión `1`, pesable, sector `01`, precios correctos).
- ✅ HW: cambio `P`→`U`→`P` con `N`; el PLU unitario acepta F33 (precio `001500`).
- Registro de F4 con `Tara` de 6 dígitos; F62 devuelve la tara en 4 (según el manual).

## F33 — cambio de precios ✅ HW

Frame: `PLU(4) + Versión(1) + Precio1(6) + Precio2(6)` = 17 bytes de datos. Verificado con PLU 8000,
versión `1`: ACK y precio efectivo en pesos enteros. Una trama por PLU. El `E5` anterior era por
frame mal armado (sin la versión). ⚠️ El texto que habla de PLU de 6 dígitos y **19 bytes** no aplica:
con 17 bytes la balanza responde ACK.

**La letra de versión (✅ HW, PLU 8000 con gestión `0`):** F33 da ACK y aplica el precio con
**cualquier** letra (`1`, `0` o `X`). La letra enviada pasa a ser la gestión del PLU: `1` ⇒ gestión
`1` (PC), `0` ⇒ gestión `0`. **El driver debe mandar siempre `1`** (así marca los PLU del ERP, ver
"Detección de cambios"). F33 sobre un PLU que no existe responde `E7`.

## F5 — borrar un PLU ✅ HW

`PLU(4)` → `ACK`. Verificado sobre el PLU 8000: ACK ⇒ F62 y F33 responden `E7` y F31 pasa de 422 a
421 sin el 8000. El manual dice que borra también el **acceso directo** asociado (no verificable
por protocolo): avisar al operador. Es **irreversible**: respaldar antes con F62 y, si hace falta
restaurar, recrear con F4 (precio `000000`) + F33. Ese ciclo borrar → recrear quedó probado.

## F72 — ventas por ticket ✅ HW

`ticket9^DD/MM/AA^HH:MM:SS^vendedor^PLU4^sector2^unid4^gramos5^drenado5^importe12`, líneas
separadas por `;`, fin `F`.

- **Una línea por artículo.** N artículos → N líneas con el mismo `ticket` + `vendedor`.
- **Importe:** valor ×100: `000000013300` = $133,00 (crudo visto). El kit lo interpreta ÷100 y dio
  $31.550 y $41.015 en las ventas de 3,155 kg (coherente con $10.000 y $13.000/kg). Es lo cobrado,
  no el precio de lista.
- **Pesables:** `unid=0` y `gramos` con el peso (3155 g). **Unitarios:** `unid` con cantidad.
- **Vendedores:** la balanza soporta **hasta 4** (`01` a `04`), dato confirmado por el usuario/
  cliente (no se testea). En F72 se vieron `01`, `02` y `03`; el `04` es válido aunque no haya
  aparecido todavía en un ticket.
- **Anulado:** línea con `unid=0`, `gramos=0`, `importe=0`.
- **Contador de tickets:** la balanza lo reinicia; la clave `fecha-ticket-posición` lo tolera.
- **Tamaño de la respuesta:** ~7 KB con 101 líneas (≈65 bytes por línea). Hay que leer **hasta el
  final de la trama** (`…;F` + XOR) con un buffer grande: con el buffer por defecto de .NET (4.096
  bytes) la respuesta se corta y el XOR falla (se confundió con un error de la balanza).
- **Letras de vendedor:** el cliente los llama A–D en la balanza; en F72 salen como `01`–`04`:
  **A=`01`, B=`02`, C=`03`, D=`04`** (✅ confirmado por el usuario; C=`03` visto en el ticket 47).
  El ERP guarda el número tal cual lo manda la balanza.
- **Rango:** usar `DDMMAA` de ayer a hoy (ej. `251026`–`261026`). Con un solo día (`261026`–
  `261026`) respondió `E7`; con "ayer y hoy" funciona.
- Con tickets abiertos o recién impresos puede responder `E3` (ver arriba).
- Sin nombre de producto ni precio unitario: se resuelve por PLU (ahora también con F62).

## Estado de los bloqueantes

- ✅ **Tipo pesable (kg) por F4** — F62 confirma `P`.
- ✅ **Precios ≥ $10.000** — resuelto: **F33** en pesos enteros (probado con $12.500 y $13.000; el
  teclado con $15.000, $20.000). No hace falta tocar decimales (func 42/F64).
- ✅ **Leer la ficha de un PLU** — **F62** (no F3).
- ✅ **Significado de la versión** — letra de gestión: `0` balanza / `1` PC; F31 y F62 la reflejan.
- ✅ **Borrar un PLU (F5)** — ACK, y el ciclo borrar → recrear funciona.
- ✅ **F33 sobre PLU con versión `0`**, **`MantenerTotales=M`**, **PLU unitario con F33**, **`Ñ` y
  acentos** (Latin-1) — todos probados en el PLU 8000.
- ✅ **Vendedor 04 (H5):** cerrado; la balanza soporta hasta 4 vendedores.
- ✅ **H4 — tickets simultáneos de dos vendedores:** con el vendedor `04` ("D") con un ticket
  **abierto**, F72 entregó completo (6.973 bytes, 101 líneas, XOR OK) el ticket cerrado del `03`
  ("C", ticket 47). El ticket abierto **no aparece** hasta que se imprime. Una vez la balanza cortó
  la respuesta a los 5 bytes (XOR inválido) y se recuperó en la lectura siguiente ⇒ reintentar.
- ✅ **H3 — escritura con un ticket abierto:** F62, F33 y F4 sobre el PLU 8000 respondieron normal
  (ACK, sin `E3`) con el ticket del `04` abierto. **No verificado:** si el cambio de precio afecta a
  las líneas ya cargadas en el ticket abierto (no se confirmó si ese ticket contenía el PLU 8000).
  **Regla decidida (usuario, 2026-10-26): NO cambiar precios con un ticket abierto.** Aunque la
  balanza acepte la escritura, el driver no debe mandar F33/F4 mientras haya ventas en curso; debe
  encolar el cambio y aplicarlo cuando no haya tickets abiertos.
- ℹ️ **E3 no es solo "ticket abierto":** apareció tras imprimir un ticket y en otros estados
  (menús/impresión), pero con un ticket abierto simple la balanza respondió. El driver trata `E3`
  como "ocupada, reintentar".
- 🚫 **Descartadas a propósito:** **F61** (PLU extendido: nutricional/EAN) no hace falta, F4 ya
  cubre el CRUD; **F64/func 42** (formato de precio) son globales y la balanza ya está en 6:0.

## Herramientas (dev; frenar el puente antes — comparten el COM)

- `scripts/sondearCuora.ts <func> [datos]` — función cruda y respuesta.
- `scripts/probarEscrituraPlu.ts` — firma + registro F4 (dry-run por defecto; `--enviar` escribe).
- **Kit de diagnóstico portátil** (`npm run build:kit` → `app/bridge/release-kit/`): lectura
  (F2/F1/F28/F31/F72) y escritura F4/F5 controlada, solo PLU 8000. **No trae F33, F62 ni F63**: en
  la sesión del 2026-10-26 se probaron armando las tramas a mano por el puerto serie
  (`System.IO.Ports.SerialPort`, 115200 8N1). Conviene agregarlos al kit.

```
cd app/bridge
npx tsx scripts/sondearCuora.ts 63                       # formato de precio
npx tsx scripts/sondearCuora.ts 62 8000                  # leer PLU 8000
npx tsx scripts/probarEscrituraPlu.ts f4 --plu 8000 --precio 0 --tipo P --nombre "PRUEBA KG"
# ↑ dry-run; precio 0 en F4 y el precio real con F33 (pesos enteros)
```
