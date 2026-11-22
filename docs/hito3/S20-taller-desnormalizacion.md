# S20. Taller: desnormalización para rendimiento (Parte A)

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

La **Parte B** (el Hito 3 sobre el esquema del proyecto) está en un documento aparte.

## Archivos y cómo correrlos

Los scripts están en [`postgres/scripts/hito3/taller-S20/`](../../postgres/scripts/hito3/taller-S20/) y se corren en este orden:

| Paso | Script | Qué hace |
|---|---|---|
| — | `S20-rendimiento.sql` | Script del profesor: crea el esquema `rendimiento` (5 000 libros, 15 000 ejemplares, 2 000 lectores y 303 750 préstamos, 3 750 abiertos), en 3FN y solo con los índices de las PK |
| A1 | `a1-catalogo.sql` | La consulta del catálogo, su resultado y `EXPLAIN ANALYZE` tres veces |
| A2 | `a2-indices.sql` | Los dos índices, y la misma medición |
| A3 | `a3-desnormalizar.sql` | La columna `libro.disponibles`, la vista `descuadre` y la simulación del préstamo olvidado |
| A4 | `a4-vista-materializada.sql` | El top 20 calculado frente a la vista materializada `top_prestados`, y el `REFRESH` |
| A5 | `a5-derivado-o-historico.sql` | `fecha_esperada`: ¿dato derivado o histórico? |

```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/S20-rendimiento.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a1-catalogo.sql
```

Después se corren `a2-indices.sql`, `a3-desnormalizar.sql`, `a4-vista-materializada.sql` y `a5-derivado-o-historico.sql`, con el mismo comando. Para volver a medir desde cero, se corre otra vez `S20-rendimiento.sql`.

## Tabla de mediciones

Tiempos del Docker del grupo (`Execution Time` de `EXPLAIN ANALYZE`, tres corridas; en negrita, el valor típico):

| Consulta | Sin índices | Con índices (A2) | Desnormalizada (A3 o A4) |
|---|---|---|---|
| Catálogo (`Libro 12%`, 111 títulos) | **~30 ms** (30,96 · 29,67 · 30,43) | **~4 ms** (4,49 · 3,75 · 4,01) | **~0,64 ms**, columna `disponibles` (0,63 · 0,64 · 0,65) |
| Top 20 más prestados | **~195 ms** (210,7 · 172,7 · 198,8) | no aplica | **~0,03 ms**, vista materializada (0,032 · 0,022 · 0,030) |

**Conclusión de las mediciones:**
- **Catálogo:** el índice logra casi toda la mejora (de ~30 a ~4 ms, unas 7,5 veces) **sin agregar redundancia**. Desnormalizar gana otra vez, pero sobre 4 ms, una diferencia que nadie nota al buscar un libro.
- **Top 20:** un índice no ayuda, porque hay que contar **todos** los préstamos. Ahí la vista materializada sí se justifica: pasa de ~195 ms a ~0,03 ms.

---

## A1. La consulta del catálogo

```sql
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;
```

Devuelve 111 títulos: 83 con 2 ejemplares disponibles y 28 con 3.

**(a) ¿Por qué `LEFT JOIN` y `count(p.id)`?**
- Un ejemplar **sin** préstamo abierto no tiene pareja en `prestamo`. Con `JOIN` se perdería esa fila, que es justo la de un ejemplar disponible. `LEFT JOIN` la conserva, con `p.id` en `NULL`.
- `count(p.id)` no cuenta los `NULL`, así que el ejemplar libre suma 0 préstamos. Con `count(*)` contaría 1, y todos los libros saldrían con 0 disponibles (es la trampa de contar ceros del S15).
- La condición `fecha_devolucion IS NULL` va en el `ON`. En el `WHERE` eliminaría las filas con `NULL`, y el `LEFT JOIN` volvería a comportarse como un `JOIN`.

**(b) Tiempo:** ~30 ms (ver la tabla).

**(c) El nodo costoso.** El plan se lee de adentro hacia afuera. El primer paso es `Seq Scan on prestamo p`, con `Filter: (fecha_devolucion IS NULL)` y **`Rows Removed by Filter: 300000`**: recorre los 303 750 préstamos para quedarse con los 3 750 abiertos. Termina a los ~24,8 ms de ~30 ms, o sea, **cerca del 80 % del tiempo**.

## A2. Índices

```sql
CREATE INDEX ejemplar_isbn_idx    ON ejemplar (isbn);
CREATE INDEX prestamo_abierto_idx ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;
```

- PostgreSQL crea índices para las `PRIMARY KEY` y los `UNIQUE`, pero **no** para las columnas de una `FOREIGN KEY`. Los dos joins de la consulta van por FK.
- `prestamo_abierto_idx` es **parcial**: solo indexa los 3 750 préstamos abiertos. Ocupa 104 kB, frente a los 17 MB de la tabla.

**Qué cambió:** el `Seq Scan on prestamo` desapareció. En su lugar hay un `Index Scan using prestamo_abierto_idx … loops=333`, dentro de un `Nested Loop Left Join`: por cada uno de los 333 ejemplares, busca en el índice si tiene préstamo abierto. El tiempo pasó de ~30 a ~4 ms. `ejemplar` se sigue recorriendo con `Seq Scan`, porque es pequeña.

**¿Hubo que agregar redundancia? No.** Un índice no se consulta ni se actualiza a mano: PostgreSQL lo mantiene solo en cada `INSERT`, `UPDATE` y `DELETE`, así que no puede desincronizarse. Las tablas conservan sus columnas (`libro` 4, `ejemplar` 2, `prestamo` 6) y el resultado es idéntico.

## A3. Desnormalizar `disponibles`

**(a) La columna, y la predicción hecha antes de calcularla.** El libro *i* tiene los ejemplares 3*i*−2, 3*i*−1 y 3*i*, que son tres números seguidos. Entre tres números seguidos hay **como máximo un múltiplo de 4**. Los 3 750 préstamos abiertos (uno por cada múltiplo de 4 hasta 15 000) caen entonces en **3 750 libros distintos**:
- Esos 3 750 libros quedan con **2 disponibles**.
- Los otros **1 250**, con **3**.

El resultado fue exactamente ese.

```sql
ALTER TABLE libro ADD COLUMN disponibles smallint;
UPDATE libro l
SET    disponibles = (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
                   - (SELECT count(*) FROM prestamo p JOIN ejemplar e ON e.id_ejemplar = p.id_ejemplar
                      WHERE e.isbn = l.isbn AND p.fecha_devolucion IS NULL);     -- UPDATE 5000
ALTER TABLE libro ALTER COLUMN disponibles SET NOT NULL,
                  ADD CONSTRAINT libro_disponibles_check CHECK (disponibles >= 0);
```

El orden importa. Agregar la columna con `NOT NULL` de una vez **falla** (`column "disponibles" … contains null values`), porque la tabla ya tiene 5 000 filas y la columna nueva nace vacía. Primero se agrega, después se llena y al final se le pone `NOT NULL` y el `CHECK`.

**(b) El catálogo con la columna** ya no hace joins:

```sql
SELECT isbn, titulo, disponibles FROM libro WHERE titulo LIKE 'Libro 12%';
```

El plan es un solo `Seq Scan on libro` y tarda ~0,64 ms. Da el mismo resultado que A1 (83 y 28).

**(c) La copia puede mentir.** La vista `descuadre` compara lo guardado con lo calculado y devuelve solo los libros donde no coinciden:

```sql
CREATE VIEW descuadre AS
SELECT   l.isbn, l.titulo, l.disponibles AS guardado,
         count(e.id_ejemplar) - count(p.id) AS calculado
FROM     libro l
JOIN     ejemplar e    ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar AND p.fecha_devolucion IS NULL
GROUP BY l.isbn, l.titulo, l.disponibles
HAVING   l.disponibles <> count(e.id_ejemplar) - count(p.id);
```

1. Recién calculada la columna, la vista da **0 filas**.
2. Se simula el préstamo `400001` del ejemplar 1 **sin** actualizar `libro`. Ahora la vista devuelve **Libro 1: guardado 3, calculado 2**.
3. Se recalcula la copia de los libros descuadrados (`UPDATE 1`) y la vista vuelve a 0 filas.

**(d) El mecanismo para el proyecto: un trigger sobre `prestamo`.** Al insertar un préstamo abierto resta 1 en el libro, y al registrar la devolución suma 1. Lo ejecuta el DBMS en cada `INSERT` o `UPDATE`, venga de la API, de `psql` o de una carga masiva, así que nadie se lo salta. Es trabajo del Hito 4; mientras tanto, `descuadre` queda como verificación.
- **"La aplicación lo actualiza en la misma transacción"** solo sirve si hay un único programa que escribe. Un `INSERT` a mano, como el de (c), se lo salta.
- **Una vista materializada no sirve:** se atrasa hasta el próximo `REFRESH`, y el catálogo tiene que estar al día al prestar.
- **Una columna generada tampoco:** solo puede usar columnas de la misma fila.

## A4. El top 20 con vista materializada

**(a) El reporte calculado** (préstamos → ejemplar → libro, agrupado por libro, `FETCH FIRST 20 ROWS WITH TIES`) da 20 filas: Libro 1 con 3 881, Libro 2 con 1 881, Libro 3 con 1 401… Tarda **~195 ms**.

El plan hace `Parallel Seq Scan on prestamo` con dos procesos, y aun así tiene que **leer y contar los 303 750 préstamos**. Un índice sirve para encontrar pocas filas sin leer las demás; aquí se necesitan todas, así que no lo arregla.

**(b) La vista materializada** guarda el **resultado**, no la consulta. Leerla tarda **~0,03 ms**.

```sql
CREATE MATERIALIZED VIEW top_prestados AS
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;                     -- SELECT 20
```

**(c) El precio.** Después de 4 000 préstamos nuevos del ejemplar 15 000 (Libro 5000, que tenía 21):
- `top_prestados` **sigue mostrando a Libro 1 de primero**.
- La consulta calculada ya pone a **Libro 5000 con 4 021**.
- Después de `REFRESH MATERIALIZED VIEW top_prestados`, la vista también muestra a Libro 5000 de primero.

**(d) ¿Cada cuánto refrescarla y quién?** Una vez al día, de noche, o al abrir el reporte si casi nadie lo usa. Es **aceptable que esté atrasado** hasta un día: con "los 20 más prestados" se decide qué comprar o exhibir, y nadie decide distinto por los préstamos de las últimas horas. Lo haría un trabajo programado, la API antes de servir el reporte, o el bibliotecario con un botón "Actualizar". **No** se debe refrescar después de cada préstamo: cada `REFRESH` cuesta lo mismo que la consulta original, y no se ganaría nada.

**A3 frente a A4:** el catálogo tiene que estar al día al instante, por eso usa trigger. El top 20 puede esperar, por eso usa vista materializada.

## A5. ¿`fecha_esperada` es derivada o histórica?

Hoy los 307 751 préstamos cumplen `fecha_esperada = fecha_prestamo + 14`. Mirando solo los datos, parece derivada. Pero la respuesta depende de la **regla del negocio**, no de los datos (S17, sección 5.2).

- **Si el plazo nunca cambia y no hay excepciones:** es un dato **derivado**, y guardarlo aparte es redundancia, porque alguien podría escribir otra fecha. Se calcula en la consulta o se guarda como **columna generada** (`GENERATED ALWAYS AS (fecha_prestamo + 14) STORED`), que nadie puede escribir a mano. Intentarlo da `can only be updated to DEFAULT`.
- **Si la biblioteca puede cambiar el plazo o dar plazos especiales:** la fecha esperada de cada préstamo es un **hecho histórico** del préstamo. Depende de su `id`, no de una regla actual, así que guardarla es **correcto en 3FN**. Lo comprobamos con los datos:
  - **Si el plazo pasa a 21 días** y la fecha se recalculara con la regla nueva, los préstamos abiertos en mora bajarían de **2 250 a 1 250**: **1 000 préstamos "saldrían de mora" sin que nadie devolviera nada**.
  - **Un préstamo renovado** (14 días más) **no está en mora** con su fecha guardada, pero lo estaría si se calculara con +14.

Es la misma distinción del caso 4 del S19 (la tarifa aplicada a un envío). **En nuestro proyecto**, `prestamo.fecha_vencimiento` se **guarda**, porque la biblioteca puede ajustar el plazo y se prevén renovaciones: es un dato histórico, no redundancia.
