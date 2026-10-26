# losHermBalanza — kit portátil de la balanza

Carpeta para llevar a la PC del cliente (la que tiene la balanza Systel Cuora conectada) y
trabajar ahí: correr el diagnóstico, ver qué responde la balanza real y actualizar los docs.
Pensada para abrir **Claude Code dentro de esta carpeta** en esa PC (ver `CLAUDE.md`).

## Contenido

| Carpeta | Qué hay |
|---|---|
| `kit/` | El ejecutable de diagnóstico (`kit-diagnostico-balanza.exe`) + driver serie + `diagnostico.bat` + `LEEME.txt` con el paso a paso. |
| `protocolo-systel/` | Manuales oficiales de Systel (PDF) y su texto extraído (`.txt`). El equipo usa el **V6.0**. |
| `descubrimientos/` | Lo que fuimos descubriendo de la balanza (markdown). Se mantiene al día con lo real. |
| `CLAUDE.md` | Contexto completo para Claude Code corriendo en esta carpeta. |

## Uso rápido

1. Frenar el puente (libera el COM): CMD como admin →
   `schtasks /end /tn "ErpLosHermanos-PuenteBalanza"`
2. Doble clic en `kit/diagnostico.bat` (relevamiento de lectura, no escribe nada).
3. Mirar el informe que queda en `kit/informe-balanza-*.txt`.
4. Reactivar el puente: `schtasks /run /tn "ErpLosHermanos-PuenteBalanza"`

Detalle completo (incluida la escritura controlada sobre el PLU 8000): `kit/LEEME.txt` y `CLAUDE.md`.

**Durante la sesión con el cliente**, tener a mano `SECUENCIA-DE-PRUEBAS.txt` (checklist paso a paso con los comandos exactos).
