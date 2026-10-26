# 29 — Balanza: captura de datos del ticket + edición de PLU desde el ERP

- **Módulo:** general (toca `app/bridge`, `app/backend`, `app/frontend`)
- **Creado:** 2026-10-23 · **Reescrita:** 2026-10-23 tras la validación con hardware
- **Spec:** sin spec propia — deriva de `docs/DocSistema/specs/ventas/11_integracionBalanzaPuenteLocal.md`.
  La regla "puente solo lectura" de ventas/11 queda **revisada por pedido del usuario** (edición de PLU).
- **Hallazgos de protocolo (leer primero):**
  [`docs/architecture/protocoloBalanzaCuora.md`](../../../docs/architecture/protocoloBalanzaCuora.md)
- **Estado:** pending. Fase 1 (viabilidad con hardware) **cerrada**.

## Objetivo (pedido del usuario, 2026-10-23)

1. **Capturar el vendedor** desde el sistema: cada vendedor tiene su propia interfaz de caja (o
   solución similar) y ve solo sus tickets.
2. **Ver cada artículo del ticket** con sus datos de PLU (PLU, cantidad, importe) y la **sumatoria
   del ticket**, tal como se probó con F72.
3. **Crear y editar PLUs desde el sistema** (F4), con la lista de precios cargada en el sistema.

## Decisiones tomadas (usuario, 2026-10-23)

- **Vendedor se persiste en `VentaItem`** (`VentaItem.vendedor`), tal como lo envía la balanza
  (`01`, `02`…), sin mapear a letras.
- **Artículo anulado:** se muestra **igual que en el ticket** — línea con cantidad 0 e importe $0
  — y así se manda al sistema. No se descarta.
- **Lista de precios:** se carga en el sistema y **se envía a la balanza desde el sistema**. La
  correspondencia lista del sistema ↔ lista 1 / lista 2 de la balanza se configura en ambas fuentes.
- El sistema es la fuente de verdad de nombre y precios del PLU. **Actualizado 2026-10-26:** como
  F62 permite leer la ficha, la sincronización es **bilateral**: se puede respaldar y verificar, y
  detectar cambios hechos en la balanza (ver Fase 3). F4 reescribe el registro completo; el precio
  se aplica con F33.
- Los PLU de prueba **7998, 7999, 8000 quedan cargados** en la balanza.

## Fase 1 — Viabilidad con hardware ✅ (2026-10-23)

- F72 entrega por artículo: ticket, vendedor, PLU, cantidad e importe. N artículos impresos en un
  solo ticket → N líneas; suma = total del ticket. Anulado → línea en 0.
- F4 crea/reescribe un PLU (nombre + lista 1 + lista 2) y responde `ACK`; verificado con ticket.
- **2026-10-23 (tarde): llegó el manual oficial Systel (CUORA MAX V6.0 Rev 06).** Confirma el
  protocolo y cierra los bloqueantes H1/H2, F5 y F33. Registro F4 completo, F5, F33, decimales
  (func 42) y decode de firma documentados en
  [`docs/architecture/protocoloBalanzaCuora.md`](../../../docs/architecture/protocoloBalanzaCuora.md).
- ~~Confirmado por manual: no existe función para leer la ficha de un PLU~~ **Corregido
  (2026-10-26):** F3 no se usa, pero **F62 sí lee la ficha completa** (probada en hw).
- **2026-10-26 (PC del cliente, COM3):** se resolvió H1 y H2, se descubrió F62/F63 y se verificó la
  receta de precios F4(`000000`) + F33. Detalle en el doc de protocolo.

## Fase 2 — Captura de datos del ticket

Hecho en el puente (commit de esta sesión): regex acepta el vendedor como venga; el mensaje `linea`
incluye `vendedor` e `importeBalanza`; tests con tramas reales (`test/protocolo.test.ts`).

- [ ] Front: `LineaBalanza` + `parsearLinea` (`app/frontend/src/shared/balanza/puenteBalanza.ts`)
      conservan `vendedor` y `ticket`.
- [ ] Interfaz por vendedor (caja propia o filtro por vendedor) — diseño UX a definir con el usuario.
- [ ] Vista del ticket: artículos (PLU, cantidad, importe) + total; anulados visibles en 0.
- [ ] `crearVenta` recibe `vendedor` por ítem y lo persiste en `VentaItem` (Prisma, migración real
      en Railway: `npx prisma migrate dev --name venta_item_vendedor`).
- [ ] Rebuild e instalación del puente (`build:installer`); subir versión + `CHANGELOG.md`.

Abierto: ¿el ERP cobra su precio o el `importeBalanza`? Si la lista se manda desde el sistema,
deberían coincidir; definir qué hacer ante diferencia.

## Fase 3 — CRUD de PLU y sincronización bilateral (F4 / F33 / F62 / F5)

**Receta de precios verificada en hardware (2026-10-26)** — detalle en el doc de protocolo:

| Operación | Función | Notas |
|---|---|---|
| **Alta / cambio de datos** | **F4** con Precio1/2 = `000000` | F4 escala el precio ÷100 (tope $9.999,99): no usarla para el precio real |
| **Precio** (crear o editar) | **F33**, pesos enteros | `$12.500` → `012500`; hasta $999.999; una trama por PLU |
| **Leer / verificar** | **F62** (nombre, 2 precios, sector, tipo, tara, gestión) | reemplaza la "lectura imposible" |
| **Listar** | **F31** + F62 por cada PLU | 422 PLU, unos minutos |
| **Borrar** | **F5** | sin probar; respaldar con F62 antes |
| **Ventas** | **F72** (rango ayer–hoy) | ya en uso |

- [ ] **Precondición al conectar:** leer **F63**; si la coma no es `0` (6:0), **no sincronizar
      precios** y avisar (con 4:2 F33 podría tomar centavos; no probado).
- [ ] Puente: F4 **acotada** (`armarRegistroPlu`) con `Precio1/2 = 000000` y **F33** para precios
      (`armarCambioPrecios`: `PLU4 + Versión + P1(6) + P2(6)`, pesos enteros). Endpoint `POST /plu`
      (F4 + F33 + verificación F62), `PATCH /plu/:n/precio` (solo F33), `GET /plu/:n` (F62) y
      `GET /plus` (F31 + F62). Reintentar con espera ante `E3` (la balanza queda ocupada).
- [ ] Parser de F62 (offsets en el doc de protocolo; 159 bytes).
- [ ] `MantenerTotales = N` solo al crear o cambiar unitario↔pesable. **Para cambiar solo el
      precio usar F33**, no reenviar F4 (pierde totales y campos que el ERP no maneja).
- [ ] **Sync balanza → sistema (cambios hechos por teclado):** no hay timestamp, pero la **letra
      de gestión** sirve (H7 ✅): el ERP escribe siempre con versión `1`; un F31 periódico detecta
      los PLU `V1` que pasaron a `V0` ⇒ leer con F62 y traer nombre/precios. Altas/bajas en la
      balanza: comparar la lista de F31. Para PLU que el ERP nunca escribió (siempre `V0`): primera
      "adopción" con F33 versión `1` (sin cambiar el precio) o lectura F62 periódica.
- [ ] **Códigos de respuesta:** `E7` y `E6` en F62/F33 = "el PLU no existe"; `E3` = ocupada
      (reintentar). F5 y F33 se mandan siempre con la versión `1`.
- [ ] **Regla: no cambiar precios con un ticket abierto.** Aunque F33/F4 den ACK, encolar el cambio
      y aplicarlo sin ventas en curso (no hay forma de listar tickets abiertos por protocolo:
      definir la ventana, p. ej. fuera de horario o con confirmación del operador).
- [ ] **Vendedores A–D = `01`–`04`** (confirmado); aceptar los cuatro en el ERP.
- [ ] **Lectura de F72:** leer hasta `…;F`+XOR con buffer > 4 KB (~7 KB con 101 líneas); reintentar
      ante XOR inválido.
- [ ] **Nombres en Latin-1** (1 byte por carácter; `Ñ`=`0xD1`), no UTF-8; rellenar a 18, truncar.
- [ ] Backend/front: crear PLU nuevo y enviar nombre + precios de un producto con `plu`;
      mapeo lista del sistema ↔ lista 1/2 de la balanza.
- [ ] **Quitar del driver la lógica de decimales/tope** (func 42, "máx $9.999,99"): los precios
      son pesos enteros hasta $999.999 vía F33. El importe de F72 sigue yendo ×100.
- [ ] Nombre: máximo 18 caracteres. `Ñ`/acentos **resuelto** (Latin-1, ver arriba).

Abierto: nombre de más de 18 caracteres (¿truncar o nombre corto?); envío manual o automático.

## Pruebas de hardware pendientes (hacer con la balanza, antes de la Fase 3)

| # | Prueba | Por qué importa |
|---|---|---|
| H1 | ✅ **Resuelto en hw (2026-10-26).** La balanza está en **6:0** (F2 y F63). **F4 escala el precio ÷100** (`013000` → $130; tope $9.999,99). **F33 usa pesos enteros** (`013000` → $13.000; verificado con venta de 3,155 kg = $41.015 y lectura F62). No hace falta func 42/F64 | Define la receta de precios del driver |
| H2 | ✅ **Resuelto en hw.** F4 completo deja el PLU como pesable: F62 devuelve tipo `P` | — |
| H3 | ✅ **Resuelto en hw (2026-10-26).** Con el ticket del vendedor `04` abierto, F62/F33/F4 sobre el PLU 8000 respondieron ACK, sin `E3` ni bloqueo. Queda sin verificar si el precio cambia en las líneas ya cargadas del ticket abierto | La balanza acepta la escritura, pero **regla decidida: no cambiar precios con un ticket abierto** (el driver encola el cambio hasta que no haya ventas en curso) |
| H4 | ✅ **Resuelto en hw.** Con el ticket del `04` abierto, F72 entregó el ticket cerrado del `03` (ticket 47) completo. El ticket abierto no aparece hasta imprimirse. Hay que leer la trama completa (~7 KB, buffer > 4 KB) y reintentar ante XOR inválido | La caja por vendedor no necesita esperar a que todos cierren |
| H5 | ✅ **Cerrado por dato del cliente (2026-10-26):** la balanza soporta **hasta 4 vendedores** (`01`–`04`); no hace falta testear. En F72 se vieron `01`, `02`, `03` | El driver y el ERP deben aceptar `01` a `04` |
| H6 | ✅ **Resuelto en hw (2026-10-26).** F33 acepta **cualquier** letra de versión sobre un PLU `V0` y aplica el precio; la letra enviada queda como gestión. **El driver manda siempre `1`** | — |
| H7 | ✅ **Resuelto en hw.** Editar por teclado devuelve el PLU a gestión `0` (F62) / `V0` (F31); escribirlo con versión `1` lo deja `V1`. Detección barata: **un F31** compara las letras; un PLU del ERP (`V1`) que ahora es `V0` fue tocado en la balanza ⇒ leer con F62. Límite: PLU que el ERP nunca escribió están en `V0` siempre | Habilita el sync balanza → sistema sin leer los 422 PLU |
| H8 | ✅ **Resuelto en hw.** F5 sobre el PLU 8000 con respaldo F62 previo: ACK; luego F62/F33 dan `E7` y F31 baja a 421. Recreado como alta nueva con F4 `000000` + F33 | Cierra el CRUD |
| H9 | ✅ **Resuelto en hw.** `MantenerTotales=M` ACK; nombre con `Ñ`/`Ú` vuelve idéntico (Latin-1: `d1`/`da`); PLU unitario `U` acepta F33; ciclo `P→U→P` con `N` OK. No verificable por protocolo: que `M` conserve los totales (no hay lectura de acumulados) | Casos de borde del alta/edición |

Estas pruebas se corren con el **kit de diagnóstico portátil** (`npm run build:kit` →
`app/bridge/release-kit/kit-diagnostico-balanza.exe` + addon + `LEEME.txt`), pensado para la PC
del cliente por TeamViewer: relevamiento de lectura (F2/F1/F28/F31/F72) con hex + interpretado e
informe `.txt`, y escritura controlada (F4/F5 dry-run por defecto, solo PLU 8000). Fuente en
`app/bridge/src/diagnostico/`; la lista blanca del puente de producción queda intacta.

## Entorno de desarrollo (balanza conectada)

- COM6, dirección 20. El puente instalado (`puente-balanza.exe`, tarea `ErpLosHermanos-PuenteBalanza`)
  toma el COM: **frenarlo** antes de correr el puente desde código o el sondeo; relanzarlo al terminar.
- Puente desde código: `BALANZA_COM=COM6 BRIDGE_PORT=3199 BRIDGE_ESTADO_PATH=<tmp>/estado.json npx tsx src/main.ts`
  (con `baselineTomada:true` y `procesadas:[]` entrega todo lo que tenga F72).
- Sondeo crudo: `npx tsx scripts/sondearCuora.ts <func> [datos]` (desde `app/bridge`).
- PLUs de prueba: **7998** (PRUEBA CLAUDE, 1/2), **7999**, **8000** (PRUEBA KG; hoy pesable,
  $20.000/$15.000). Escribir solo sobre ellos. En la PC del cliente el puerto es **COM3**.

## Tests requeridos

- **unit (bridge):** F72 con tramas reales (hecho); anulados en 0; armado del registro F4 (relleno,
  centavos, longitudes, XOR) y manejo de `ACK`/`E6`/`E3`.
- **integration (bridge):** simulador acepta F4 y refleja el precio en F72.
- **unit (front):** `parsearLinea` conserva `vendedor`/`ticket`; anulados visibles en 0.
- **integration (backend):** `crearVenta` persiste `VentaItem.vendedor`; regresión del flujo normal.

## Salvedades

- Test previo roto, ajeno a esta task: "poda al guardar…" (`test/puente.integration.test.ts`)
  depende del reloj (la clave `200926` ya tiene más de 30 días). Corregir fijando la fecha.
- Al cerrar: actualizar spec ventas/11 (el puente deja de ser solo lectura).
- Borrado de PLU: **F5 identificada** (manual), sin probar en hw. Sigue siendo riesgoso (hay 422
  PLU reales e irreversible), pero ahora se puede **respaldar la ficha con F62** antes de borrar.
  Probar F5 solo sobre el PLU de prueba 8000; decidir con el usuario si entra en alcance.
- Estado del PLU de prueba **8000** al 2026-10-26: "PRUEBA KG", pesable, $20.000 / $15.000
  (cargado por teclado). Escribir solo sobre él.
