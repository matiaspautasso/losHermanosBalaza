# Protocolo balanza Systel Cuora — hallazgos con el equipo real

> Investigación 2026-10-23 con la balanza conectada (COM6, dirección 20, 115200 8N1, firma
> `F2000C030000S0060P08000A060D0`). Base para la task
> [29](../../tasks/pending/general/29_balanzaCapturaVendedorYSyncPreciosBilateral.md).
> Complementa la spec [ventas/11](../../specs/ventas/11_integracionBalanzaPuenteLocal.md).
> **2026-10-23 (tarde):** se obtuvo el **manual oficial Systel** ("Protocolo de comunicaciones
> CUORA MAX V6.0 Rev 06"). Confirma el protocolo deducido y **cierra los bloqueantes** que
> antes requerían sondeo a ciegas (F4 completa, F5, F33, decimales). Lo marcado "manual" abajo
> sale de ese documento; lo "hw" aún pide una verificación con el equipo.

Trama en ambos sentidos: `[dirección][función][datos ASCII][XOR]` (XOR de todos los bytes
previos, sin terminador). Respuesta de error: datos `E<dígito>`. Escritura aceptada: `ACK`.
El manual llama "CRC" a ese último byte; es el mismo XOR (`calcularXor`), ya verificado con F4.

## Firma del equipo (función 2) — decodificada

Formato: `F<tipo4>C<capacidad6>S<protocolo4>P<plus5>A<accesos3>D<decimales1>`. La real
`F2000C030000S0060P08000A060D0` ⇒ capacidad 30000 g, **protocolo `0060` = CUORA MAX V6.0**
(por eso aplica ese manual, y no la V6.2/V7), 8000 PLU, 60 accesos directos y **decimales `0`**
(ver nota de decimales — contradice la lectura previa de "centavos" y hay que confirmarlo en hw).

## Resumen de funciones

| Func | Qué hace | Datos de la solicitud | Respuesta | Estado |
|---|---|---|---|---|
| 1 | Peso del plato | — | peso, estable, tara | ya en uso |
| 2 | Firma del equipo | — | firma | ya en uso |
| 28 | Fecha/hora | — | `HH:MM:SS DD/MM/AA` | ya en uso |
| 72 | Ventas por ticket | `DDMMAA` inicio + `DDMMAA` fin | líneas `…;F` (ver abajo) | ya en uso, verificado |
| 31 | Lista de PLU cargados | vacío | `N0001V0N0002V0…F` | lectura, verificado |
| 3 | Leer ficha de un PLU | PLU | error | **no existe** en este equipo (manual) |
| 4 | **Alta / modificación de PLU** | registro completo (ver abajo) | `ACK` / `E<n>` | **escribe**, registro corregido por manual |
| 5 | **Borrar un PLU** | PLU (4 nros) | `ACK` / `E<n>` | manual, sin probar en hw |
| 33 | **Cambio solo de precios** | PLU + versión + precio1 + precio2 | `ACK` / `E<n>` | manual (frame corregido) |
| 42 | Decimales de precio | `0` o `2` | `ACK` | manual, config global |
| 61 | PLU extendido (nutricional, EAN…) | registro largo | `ACK` / `E<n>` | manual, **no necesario** para la task |

Códigos: `E3` balanza ocupada (operador con ticket abierto; reintentar), `E5` formato de
solicitud inválido (típicamente faltó un campo del registro), `E6` registro inválido (vacío o
PLU no numérico), `E7` sin datos / rango inválido.

## F72 — datos de cada artículo del ticket

`ticket9^DD/MM/AA^HH:MM:SS^vendedor^PLU4^sector2^unid4^gramos5^drenado5^importe12`, líneas
separadas por `;`, fin `F`. Ejemplo real:

```
000000003^23/10/26^14:52:18^01^0002^01^0000^02095^00000^000002576900
```

- **Una línea por artículo.** El vendedor carga N artículos, imprime **un solo ticket** con el
  total, y F72 devuelve N líneas con el mismo `ticket` + `vendedor`. Verificado: ticket de 3
  artículos → 3 líneas; la suma de importes es el total del ticket.
- **Vendedor:** viene como lo envía la balanza, 2 dígitos (`01`, `02`, `03`). No se mapea a letras.
- **Importe:** importe de la línea en centavos (`000002576900` → $25.769,00). Es lo cobrado
  (precio × cantidad), **no** el precio de lista del PLU.
- **Artículo anulado:** sigue apareciendo como línea con `unid=0`, `gramos=0`, `importe=0`.
  Ejemplo: `…^01^0001^01^0000^00000^00000^000000000000`. Hay que descartarla o marcarla.
- **Cuándo llega:** solo al imprimir/cerrar el ticket. Mientras un vendedor tiene un ticket
  abierto, F72 responde `E3`.
- **Contador de tickets:** la balanza lo reinicia (en el mismo día se vio volver a `000000001`).
  La clave `fecha-ticket-posición` del puente lo tolera.
- **Sin nombre de producto ni precio unitario:** F72 trae solo PLU + cantidades + importe.
- Tras un cierre en la balanza, F72 deja de devolver los tickets anteriores.

## F31 — lista de PLU

Sin datos devuelve todos los PLU cargados (419 en el equipo real), `N<plu4>V<d>` por cada uno.
Con cualquier dato (`8000`, `N8000`, `08000`…) responde `E5`: **no lee un PLU puntual**.
No trae nombre ni precio.

## F4 — alta / modificación de PLU (escritura) — registro OFICIAL (manual, pág. 9)

El registro corto deducido antes estaba **incompleto**: por eso el PLU quedaba "por unidad" y no
se podía fijar el tipo. Orden y anchos reales (PLU de 4 dígitos en este equipo):

```
PLU(4) + Versión(1) + Nombre(18) + Precio1(6) + Precio2(6) + Código(5) + Sección(2) +
DíasVto(4) + TipoVenta(1) + Tara(6) + MantenerTotales(1) + Ingredientes(1) [+ Ingredientes(100)]
```

- **Versión de PLU** (1 letra): era el "campo1" misterioso. Indica si el PLU se gestiona desde la
  PC o la balanza (F31 lo refleja como `0`/`1`/`2`). No son los decimales.
- **Precio Lista 1 / 2** (6 nros c/u, "no incluye coma"): la coma la pone la balanza según su
  config de decimales (func 42). Ver nota de decimales: el tope **no es** del protocolo.
- **Tipo de venta** (1 letra): `P` = pesable, `U` = unitario. **Resuelve el bloqueante del tipo kg.**
- **Tara** (6 nros, gramos): solo tiene sentido en pesables; `000000` si no aplica.
- **Mantener Totales** (1 letra): `N` nuevo (pone acumulados en 0) / `M` modifica (conserva totales).
  El manual exige **`N` cuando se cambia la condición unitario↔pesable**, se crea un PLU, o se
  cambia su número/código.
- **Ingredientes** (1 letra `S`/`N`, + 100 letras solo si `S`): no se usa en esta task → `N`.
- Si el PLU no existe lo **crea**; si existe lo **reescribe completo** (todo campo omitido queda en 0).

Verificado antes con el equipo: F4 responde `ACK` y el PLU cobra exactamente el precio escrito.
Falta reconfirmar en hw con el registro completo (tipo pesable + tara correctos).

## F33 — cambio solo de precios (manual, pág. 10) — por qué fallaba

Frame oficial: `PLU(4) + Versión(1 letra) + Precio1(6) + Precio2(6)` (+ XOR). Cambia los precios
manteniendo el resto del PLU y los totalizadores. El `E5` que daba antes era por **frame mal
armado**: se mandaba `008000001500002500` (PLU de 6 dígitos y **sin el byte de versión** entre PLU
y precios). Con el registro correcto, F33 es la vía liviana para sincronizar precios sin tocar
tipo/tara. Mismo tope de 6 dígitos que F4 (⇒ depende de los decimales, no es un límite duro).

## F61 — PLU extendido (manual, pág. 19-20) — disponible pero NO necesario

Registro largo (nutricional, origen, lote, EAN, congelados, hasta tipos `P/U/E/C`). Los `E6/E7`
previos eran por frame incorrecto (se probó con PLU de 8 dígitos y barridos de ceros), no por falta
de soporte. **Para esta task no hace falta:** F4 ya trae tipo de venta y tara. Queda documentado por
si más adelante se cargan tabla nutricional o códigos EAN por artículo.

## Decimales de precio (función 42) — la clave del "tope de $9.999,99"

El tope **no es del protocolo**: el campo de precio es de 6 dígitos "sin coma", y la balanza inserta
los decimales según su config global (**func 42: `0` o `2`**, reflejada en el byte `D` de la firma).
Con `2` decimales, 6 dígitos ⇒ máx $9.999,99 (el tope que se vio). Con `0` decimales ⇒ máx $999.999
y `013000` = $13.000. El importe de F72 va **siempre ×100** (2 decimales), aparte de esta config.

**A verificar en hw (contradicción):** la firma real dice `D0` (0 decimales), pero la investigación
previa reportó `001000` = $10,00 (2 decimales). Resolver con una prueba: leer firma en vivo y
escribir un PLU a $13.000, viendo cómo lo muestra. Según el resultado, o ya entra, o se setea 0
decimales con func 42 (decisión de negocio: es **global**, afecta todos los precios e importes).

## Estado de los bloqueantes (tras el manual)

- ✅ **Tipo pesable (kg) por F4** — resuelto: campo "Tipo de venta" `P`/`U` + "Tara" en el registro.
- ✅ **Precios ≥ $10.000** — resuelto a nivel protocolo (decimales, func 42); falta 1 confirmación hw.
- ✅ **Borrar un PLU** — F5 identificada (manual). Sin probar en hw; riesgo sobre los 419 PLU, probar
  solo sobre los de prueba.
- ✅ **Significado de `campo1` / campos de F4** — resuelto: es "Versión de PLU"; registro completo arriba.
- ❌ **Leer la ficha de un PLU** (nombre/precio/tipo) — el manual confirma que **no existe** en este
  equipo (F3 "no se utiliza"). No hay respaldo previo a una escritura: el sistema debe ser la fuente
  de verdad del PLU y reescribir el registro completo.

## Herramientas de sondeo (dev, frenar el puente antes — comparten el COM)

- `scripts/sondearCuora.ts <func> [datos]` — envía una función cruda y muestra la respuesta.
- `scripts/probarEscrituraPlu.ts` — lee/decodifica la firma y arma el registro F4 completo.
  **Por defecto DRY-RUN** (imprime la trama, no escribe); `--enviar` para escribir.
- **Kit de diagnóstico portátil** (`npm run build:kit` → `app/bridge/release-kit/`): `.exe`
  autocontenido (Node SEA, no requiere instalar nada) para correr en la PC del cliente por
  TeamViewer. Relevamiento de lectura (F2/F1/F28/F31/F72) con hex crudo + interpretado, informe
  en `.txt`, y escritura controlada (F4/F5 dry-run por defecto, solo PLU 8000). Fuente en
  `src/diagnostico/`, lógica pura de registros en `src/registroPlu.ts` (con tests).

```
cd app/bridge
npx tsx scripts/sondearCuora.ts 31                       # lista de PLU
npx tsx scripts/probarEscrituraPlu.ts firma              # firma + decimales en vivo
npx tsx scripts/probarEscrituraPlu.ts f4 --plu 8000 --precio 13000 --tipo P --nombre "PRUEBA KG"
# ↑ dry-run; agregar --enviar para escribir de verdad (SOLO sobre PLU de prueba 7998/7999/8000)
```
