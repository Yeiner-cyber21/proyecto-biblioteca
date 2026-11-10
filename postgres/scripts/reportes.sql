-- =====================================================================
-- reportes.sql  ·  Los 4 reportes del proyecto sobre el esquema "biblioteca"
-- (S15/S16, Hito 2). Adaptados del S15-reportes-demo.sql del profesor.
--
-- Requisito: haber corrido las cargas y datos-prueba.sql (el mismo día).
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- Cada reporte queda guardado como VISTA (sugerencia de S16 para la API de
-- M7): una consulta con nombre que se usa como una tabla. El script crea
-- las 4 vistas (CREATE OR REPLACE: se puede correr cuantas veces se quiera)
-- y luego las consulta. verificacion-parte-b.sql lee estas mismas vistas.
-- Cada SELECT de adentro también se puede copiar solo al Query Tool de
-- pgAdmin (sin las líneas \echo, que son de psql).
--
-- Qué cambia en nuestro esquema respecto a reportes_demo (S16, sección 3):
--   - El préstamo apunta a un EJEMPLAR (isbn, numero_copia), pero como la
--     clave del ejemplar incluye el ISBN, prestamo ya trae el isbn: se une
--     con libro directamente y se agrupa por libro, no por copia.
--   - Nombre y correo están en USUARIO; el teléfono, en LECTOR.
--   - No hay columna de estado: abierto = fecha_devolucion IS NULL, y la
--     mora se calcula con las fechas.
--   - La fecha esperada de devolución es prestamo.fecha_vencimiento.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

-- ---------------------------------------------------------------------
-- Reporte 1. Los 20 libros más prestados
-- Devuelve: isbn, título y número de préstamos de cada libro del top 20.
--
-- Decisiones:
--   - Se cuenta por LIBRO (título), no por copia: los préstamos de las
--     copias 1, 2, 3 y 4 de un mismo ISBN suman para el mismo libro.
--   - Se cuentan todos los préstamos (abiertos y devueltos): un préstamo
--     cuenta desde que se registra.
--   - Libros sin préstamos: entran al conteo con 0 (LEFT JOIN y
--     count(p.id_prestamo), no count(*), que les daría 1). Solo se ven en el
--     reporte si menos de 20 libros tienen préstamos.
--   - Se incluyen todos los libros, activos o no: el reporte mide la
--     historia de préstamos.
--   - Empates: WITH TIES. Si hay empate en el puesto 20, salen todos los
--     empatados. El orden alfabético entre empatados va afuera del WITH TIES.
--
-- Esperado con datos-prueba.sql: 21 filas. Cien años de soledad 4, 1984 3,
--   Harry Potter 3, El principito 2, Rayuela 2 y 16 libros con 1 préstamo
--   empatados del puesto 6 al 21 (casos 1 y 2). Ningún libro con 0.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW biblioteca.reporte_top_libros AS
SELECT isbn, titulo, prestamos
FROM (
    SELECT   l.isbn, l.titulo, count(p.id_prestamo) AS prestamos
    FROM     biblioteca.libro l
    LEFT JOIN biblioteca.prestamo p ON p.isbn = l.isbn
    GROUP BY l.isbn, l.titulo
    ORDER BY prestamos DESC
    FETCH FIRST 20 ROWS WITH TIES
) AS top;

\echo
\echo '== Reporte 1. Los 20 libros más prestados (con empates en el puesto 20) =='
SELECT * FROM biblioteca.reporte_top_libros
ORDER BY prestamos DESC, titulo;

-- ---------------------------------------------------------------------
-- Reporte 2. El o los lectores que más libros han leído
-- Devuelve: documento, nombres, apellidos y préstamos devueltos.
--
-- Decisiones:
--   - "Libro leído" = préstamo DEVUELTO (sección 3.2 del proyecto): los
--     préstamos abiertos no cuentan, para no premiar a quien retiene libros.
--   - Se cuentan préstamos devueltos, no títulos distintos: si alguien lee
--     dos veces el mismo libro, cuenta 2. (Con los datos actuales da igual.)
--   - "El o los": si hay empate en el máximo, salen todos (= max, no LIMIT 1).
--
-- Esperado con datos-prueba.sql: 2 filas. Mariana Gómez y Santiago
--   Rodríguez, con 5 cada uno (caso 3). No salen Juan David (0 devueltos) ni
--   Camila (6 préstamos, 3 devueltos) (caso 4), ni los lectores sin
--   préstamos (caso 8).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW biblioteca.reporte_mas_lectores AS
WITH leidos AS (
    SELECT   p.id_lector, count(*) AS devueltos
    FROM     biblioteca.prestamo p
    WHERE    p.fecha_devolucion IS NOT NULL          -- solo préstamos completados
    GROUP BY p.id_lector
)
SELECT u.documento, u.nombres, u.apellidos, x.devueltos
FROM   leidos x
JOIN   biblioteca.usuario u ON u.id_usuario = x.id_lector
WHERE  x.devueltos = (SELECT max(devueltos) FROM leidos);

\echo
\echo '== Reporte 2. El o los lectores que más libros han leído (préstamos devueltos) =='
SELECT * FROM biblioteca.reporte_mas_lectores
ORDER BY apellidos, nombres;

-- ---------------------------------------------------------------------
-- Reporte 3. Lectores morosos (con al menos un préstamo vencido y sin devolver)
-- Devuelve: documento, nombres y apellidos, una fila por lector.
--
-- Decisiones:
--   - Moroso = tiene AL MENOS UN préstamo abierto (sin devolver) cuya fecha
--     de vencimiento ya pasó. Devolver tarde NO deja moroso a nadie.
--   - Un préstamo que vence HOY todavía no está en mora: comparación
--     estricta (<). Con <= se consideraría en mora desde el día del vencimiento.
--   - Una fila por lector (EXISTS), aunque tenga varios préstamos en mora.
--   - La mora se calcula con las fechas: el esquema no guarda un "estado".
--
-- Esperado con datos-prueba.sql: 4 filas. Sebastián, Valentina, Juan David
--   (una sola vez, aunque tiene dos en mora: caso 7) y Andrés Felipe.
--   No salen Santiago (devolvió tarde: caso 5) ni Isabella (su préstamo
--   vence hoy: caso 6).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW biblioteca.reporte_morosos AS
SELECT u.documento, u.nombres, u.apellidos
FROM   biblioteca.lector le
JOIN   biblioteca.usuario u ON u.id_usuario = le.id_usuario
WHERE  EXISTS (SELECT 1
               FROM   biblioteca.prestamo p
               WHERE  p.id_lector = le.id_usuario            -- préstamos de ESTE lector
                 AND  p.fecha_devolucion IS NULL             -- que no ha devuelto
                 AND  p.fecha_vencimiento < CURRENT_DATE);   -- y que ya vencieron

\echo
\echo '== Reporte 3. Lectores morosos =='
SELECT * FROM biblioteca.reporte_morosos
ORDER BY apellidos, nombres;

-- ---------------------------------------------------------------------
-- Reporte 4. Préstamos en mora: la lista para "Enviar notificación"
-- Devuelve: una fila por préstamo en mora, con nombre, correo y teléfono
-- del lector, título, copia, fecha de vencimiento y días de mora.
--
-- Decisiones:
--   - Una fila por PRÉSTAMO en mora (no por lector): quien tenga dos
--     préstamos vencidos aparece dos veces, una por libro.
--   - La condición de mora es la misma del reporte 3 (abierto y vencido, con <).
--   - Días de mora = hoy - fecha de vencimiento (restar dos fechas da días).
--   - Orden: primero los que llevan más días en mora; empates por nombre.
--   - Contacto: nombre y correo vienen de usuario; el teléfono, de lector.
--
-- Esperado con datos-prueba.sql: 5 filas. Sebastián 31 días, Juan David 13,
--   Valentina 7, Juan David 6 (dos veces: caso 7) y Andrés Felipe 2. No
--   salen el Quijote de Santiago (caso 5) ni la Rayuela de Isabella (caso 6).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW biblioteca.reporte_prestamos_mora AS
SELECT u.nombres || ' ' || u.apellidos      AS lector,
       u.correo,
       le.telefono,
       l.titulo,
       p.numero_copia                       AS copia,
       p.fecha_vencimiento,
       CURRENT_DATE - p.fecha_vencimiento   AS dias_mora
FROM   biblioteca.prestamo p
JOIN   biblioteca.lector   le ON le.id_usuario = p.id_lector
JOIN   biblioteca.usuario  u  ON u.id_usuario  = le.id_usuario
JOIN   biblioteca.libro    l  ON l.isbn        = p.isbn
WHERE  p.fecha_devolucion IS NULL                 -- no devuelto
  AND  p.fecha_vencimiento < CURRENT_DATE;        -- y ya vencido

\echo
\echo '== Reporte 4. Préstamos en mora (lista de notificación) =='
SELECT * FROM biblioteca.reporte_prestamos_mora
ORDER BY dias_mora DESC, lector;
