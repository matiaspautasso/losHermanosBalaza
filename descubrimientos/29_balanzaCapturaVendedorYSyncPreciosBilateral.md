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
- El sistema es la fuente de verdad de nombre y precios del PLU (la F4 reescribe el registro completo).
- Los PLU de prueba **7998, 7999, 8000 quedan cargados** en la balanza.

## Fase 1 — Viabilidad con hardware ✅ (2026-10-23)

- F72 entrega por artículo: ticket, vendedor, PLU, cantidad e importe. N artículos impresos en un
  solo ticket → N líneas; suma = total del ticket. Anulado → línea en 0.
- F4 crea/reescribe un PLU (nombre + lista 1 + lista 2) y responde `ACK`; verificado con ticket.
- **2026-10-23 (tarde): llegó el manual oficial Systel (CUORA MAX V6.0 Rev 06).** Confirma el
  protocolo y cierra los bloqueantes H1/H2, F5 y F33. Registro F4 completo, F5, F33, decimales
  (func 42) y decode de firma documentados en
  [`docs/architecture/protocoloBalanzaCuora.md`](../../../docs/architecture/protocoloBalanzaCuora.md).
- Confirmado por manual: **no existe** función para leer la ficha de un PLU en este equipo.

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

## Fase 3 — Crear / editar PLU desde el sistema (F4 / F33)

Registro F4 OFICIAL (manual, pág. 9; ver doc de protocolo para anchos exactos):
`PLU(4) + Versión(1) + Nombre(18) + Precio1(6) + Precio2(6) + Código(5) + Sección(2) + DíasVto(4)
+ TipoVenta(1 P/U) + Tara(6) + MantenerTotales(1 N/M) + Ingredientes(1 S/N)`.
Prototipo del armado + prueba de hw: `app/bridge/scripts/probarEscrituraPlu.ts` (dry-run por defecto).

- [ ] Puente: F4 **acotada** (no abrir la lista blanca general): `armarRegistroPlu(...)` con el
      registro completo + endpoint `POST /plu` → `ACK`/`E<n>`, reintento ante `E3`. `GET /plus` con
      F31. Evaluar **F33** para update de solo-precios (más liviano, conserva tipo/tara y totales).
- [ ] `MantenerTotales = N` al crear o cambiar la condición unitario↔pesable (lo exige el manual).
- [ ] Backend/front: crear PLU nuevo y enviar nombre + precios de un producto con `plu`.
- [ ] Configuración del mapeo de listas (sistema ↔ lista 1/2 de la balanza).
- [ ] Decidir la política de **decimales** (func 42) según la prueba de hw de H1 — ver abajo.

Abierto: nombre de más de 18 caracteres (¿truncar o nombre corto?); envío manual o automático.

## Pruebas de hardware pendientes (hacer con la balanza, antes de la Fase 3)

| # | Prueba | Por qué importa |
|---|---|---|
| H1 | 🟡 **Resuelto por manual, falta confirmar en hw.** El tope de $9.999,99 no es del protocolo: es la config de decimales (func 42, `0`/`2`). Con 0 decimales, 6 dígitos ⇒ $999.999. Contradicción a dirimir: firma dice `D0` pero antes se vio `001000`=$10,00. **Prueba:** `probarEscrituraPlu.ts firma` + escribir $13.000 con `--enviar`. Si da 2 decimales, setear 0 con func 42 (decisión de negocio: es global) |
| H2 | ✅ **Resuelto por manual.** El registro F4 completo tiene campo "Tipo de venta" `P`/`U` y "Tara"; antes se mandaba un registro corto que no llegaba a ese campo. Requiere `MantenerTotales=N` al cambiar la condición. Reconfirmar en hw con el registro completo |
| H3 | ⏳ Sin probar. Mandar F4 con un **ticket abierto** en la balanza | Saber si da `E3`, si bloquea teclas o si escribe igual |
| H4 | ⏳ Sin probar. Vendedor A deja un ticket abierto, vendedor B imprime | Saber si F72 entrega el de B o da `E3` hasta que A cierre (clave para la caja por vendedor) |
| H5 | ⏳ Sin probar. Ticket con el **vendedor 04** | Confirmar los 4 vendedores |

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
- PLUs de prueba: **7998** (PRUEBA CLAUDE, 1/2), **7999**, **8000** (PRUEBA KG, 9000/9500, quedó por
  unidad). Escribir solo sobre ellos.

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
- Borrado de PLU: **F5 ya identificada** (manual). Sigue siendo riesgoso — no se puede leer la ficha
  de un PLU (no hay respaldo previo) y hay 419 reales. Probar F5 solo sobre PLU de prueba; decidir
  con el usuario si entra en alcance.
