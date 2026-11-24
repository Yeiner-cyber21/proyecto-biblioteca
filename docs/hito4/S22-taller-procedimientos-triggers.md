# Laboratorio S22, Parte A: procedimientos, funciones y triggers

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

SQL completo de la Parte A (A1 a A6 y el reto): [`postgres/scripts/hito4/taller-S22/S22-grupo.sql`](../../postgres/scripts/hito4/taller-S22/S22-grupo.sql). Se corre después de `S22-reservas.sql`, en orden y sin deshacer las baterías, porque A4 y A5 usan la reserva que crea la prueba 7 de A3.

## Resultado de las baterías

| Punto | Resultado en PostgreSQL 16 |
|---|---|
| A1 | Las 4 inserciones fallan, cada una por su restricción (`reserva_orden`, `reserva_duracion`, `reserva_horario`, `reserva_asistentes`). Borrar la sala D se lleva sus recursos (0). Borrar la sala A falla por `reserva_id_sala_fkey`. El último `INSERT` pasa (`INSERT 0 1`) |
| A2 | Próxima semana: 5.0, 2.0, 3.0, 2.0, 0.0, 0.0. Pasada: 0.0, 2.0, 2.0, 0.0, 0.0, 2.0. `sala_libre`: f, t, t, t |
| A3 | Las 11 pruebas dan lo esperado; cada error dice qué regla falló ("Regla 5: Elena (2610005) está sancionado/a hasta el…"). Las reservas nuevas son la 15, 16 y 17: los `INSERT` fallidos de A1 ya habían consumido los números 10 a 14 de la identidad |
| A4 | Antes del trigger, el `INSERT` de 12 personas pasa. Con el trigger: capacidad, sala ocupada, `UPDATE` de inicio y reactivar la 5 fallan; `UPDATE` de asistentes pasa |
| A5 | Felipe queda sancionado (Elena 30, Felipe 7), su `CALL reservar` falla y el `UPDATE` de la reserva 8 no sanciona a Bruno |
| A6 | `cerrar_vencidas()` pasa la reserva 9 a `cumplida` con un solo `UPDATE` |
| Reto | El `EXCLUDE` rechaza el cruce con el trigger desactivado y acepta el horario libre; el trigger queda reactivado |

## A1 (b). Acción `ON DELETE` de cada FK

| FK | Acción | Por qué |
|---|---|---|
| `sala_recurso → sala` | `CASCADE` | Los recursos son un atributo multivaluado de la sala: no existen sin ella (como los teléfonos del lector en S21). |
| `reserva → sala` | `RESTRICT` | Las reservas son historia (uso de las salas, inasistencias). Una sala que sale de servicio se marca `activa = false`, no se borra. |
| `reserva → estudiante` | `RESTRICT` | Borrar al estudiante borraría sus reservas y con ellas sus inasistencias, que justifican sus sanciones. |

## A1 (d). El `INSERT` que pasa todas las restricciones

Reserva 9 personas en la sala A, el lunes de 9:00 a 10:00. Viola dos reglas:

- **Regla 2:** la sala A tiene capacidad para 4.
- **Regla 3:** se cruza con la reserva activa de Ana (8:00 a 10:00).

Ningún `CHECK` lo puede impedir: un `CHECK` solo ve **la fila que se está escribiendo**. La capacidad está en **otra tabla** (`sala`) y el cruce depende de **otras filas** de `reserva`, y un `CHECK` no admite subconsultas (S21, sección 3.4). Por eso esas reglas van en un trigger.

## A4 (b). ¿Qué pasa si `sala_libre` no excluye la propia reserva?

En un `BEFORE UPDATE`, la versión vieja de la fila sigue en la tabla. Sin `p_excluir`, la reserva **chocaría consigo misma**: misma sala, mismo horario. Cualquier `UPDATE` de una reserva activa fallaría con "sala ocupada", aunque no cambie el horario. Por ejemplo, la prueba A4.4 (`asistentes = 5` en la reserva 6) sería rechazada. Por eso el trigger llama a `sala_libre(…, NEW.id)`.

## A4 (d). ¿Las reglas 4 y 5 van también en el trigger?

**No: se quedan solo en el procedimiento `reservar`.** Las reglas 2 y 3 son **invariantes físicas**: nadie puede meter 12 personas en una sala de 10 ni usar una sala dos veces a la misma hora, sea un estudiante o la coordinación. Por eso van en el trigger, que no se puede saltar.

Las reglas 4 y 5 son **políticas del caso de uso "un estudiante reserva"**: un cupo de horas y un castigo. Otros actores escriben en `reserva` con razones legítimas para no cumplirlas:

- La coordinación reserva la sala C para un evento a nombre de un monitor. Si la regla 4 estuviera en el trigger, el evento contaría contra las 6 horas del monitor y lo bloquearía. Si la regla 5 estuviera en el trigger, un monitor sancionado no podría figurar en una reserva institucional.
- Un trigger también se dispara en los `UPDATE`. Con la regla 5 adentro, ni siquiera se podría corregir el número de asistentes de una reserva ya hecha por alguien sancionado después.

Una observación: ese evento de 4 horas también choca con `reserva_duracion` (regla 1). Si la coordinación necesita esa excepción, habría que modelarla, por ejemplo con un tipo de reserva y el `CHECK` condicionado a él. No se debe quitar la restricción para todos.

## A5. ¿Por qué el último `UPDATE` no sanciona a Bruno?

- **El trigger es `AFTER UPDATE OF estado`:** solo se dispara si el `UPDATE` incluye `estado` en el `SET`, y `SET asistentes = 2` no lo incluye.
- **Aunque incluyera `estado`, la cláusula `WHEN` exige pasar a `'no_asistio'` desde otro estado**, y la reserva 8 ya era `'no_asistio'`.
- **Bruno nunca fue sancionado** porque su inasistencia la cargó el script antes de que existiera el trigger: los triggers no son retroactivos.

**Sin el `WHEN`**, la función correría en todo `UPDATE` que toque `estado`:

- `cancelar()` (activa → cancelada) y `cerrar_vencidas()` (activa → cumplida) sancionarían a estudiantes que no hicieron nada malo.
- Volver a escribir `'no_asistio'` en una reserva que ya lo era sancionaría otra vez y alargaría la sanción.

La condición se podría poner dentro de la función con un `IF`, pero el `WHEN` evita llamarla y deja la condición visible en la definición del trigger.

**Decisión del grupo:** la función usa `GREATEST(sancionado_hasta, CURRENT_DATE + 7)` para que una inasistencia no **acorte** una sanción más larga que ya exista (Elena tiene 30 días).

## A6 (b). 2 000 reservas vencidas: ciclo frente a conjunto

| | `cerrar_vencidas_ciclo()` | `cerrar_vencidas()` |
|---|---|---|
| Sentencias `UPDATE` | **2 000**, una por fila, más el `SELECT` del ciclo y 2 000 `NOTICE` | **1** |
| Veces que se dispara `reserva_validar` | **2 000** | **2 000** |
| Veces que corre `sancionar_inasistencia` | 0 | 0 |

`reserva_validar` es `FOR EACH ROW`: se dispara **una vez por cada fila modificada**, sin importar cuántas sentencias hubo. En las dos versiones se modifican 2 000 filas, así que corre 2 000 veces. En cada una sale de inmediato, porque `NEW.estado` es `'cumplida'`, no `'activa'`.

`reserva_sancionar` evalúa su `WHEN` 2 000 veces, pero nunca llama a la función: el nuevo estado no es `'no_asistio'`.

La diferencia está en las sentencias. El ciclo planea y ejecuta 2 000 `UPDATE`, cada uno buscando su fila por la PK. El conjunto lo hace en **una sola pasada**, que el optimizador planea una vez.

## Reto. La regla 3 como `EXCLUDE`

Con `reserva_sin_cruce` (`EXCLUDE USING gist (id_sala WITH =, tsrange(inicio, fin) WITH &&) WHERE (estado = 'activa')`), el DBMS garantiza la regla 3 de forma declarativa. Con el trigger desactivado, rechazó el cruce con la reserva de Ana y aceptó el horario libre.

Siguiendo la sección 8 de S21 ("lo que se puede declarar, se declara"), **en el trigger quedaría solo la regla 2** (mantenimiento y capacidad), porque mira otra tabla (`sala`) y no cabe en un `CHECK` ni en un `EXCLUDE`.
