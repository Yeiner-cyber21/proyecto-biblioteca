-- =====================================================================
-- reportes.sql  ·  Los 4 reportes del proyecto sobre el esquema "biblioteca"
-- (S15/S16, Hito 2). Adaptados del S15-reportes-demo.sql del profesor.
--
-- Requisito: haber corrido las cargas y datos-prestamos.sql.
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- Cada consulta también se puede copiar sola al Query Tool de pgAdmin
-- (sin las líneas \echo, que son de psql).
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

-- ---------------------------------------------------------------------
-- Reporte 1. Los 20 libros más prestados
--
-- Decisiones:
--   - Se cuenta por LIBRO (título), no por copia: los préstamos de las
--     copias 1, 2, 3 y 4 de un mismo ISBN suman para el mismo libro.
--   - Se cuentan todos los préstamos (abiertos y devueltos): un préstamo
--     cuenta desde que se registra.
--   - Se incluyen todos los libros, activos o no: el reporte mide la
--     historia de préstamos.
--   - WITH TIES: si hay empate en el puesto 20, salen todos los empatados.
-- ---------------------------------------------------------------------
\echo
\echo '== Reporte 1. Los 20 libros más prestados (con empates en el puesto 20) =='
SELECT isbn, titulo, prestamos
FROM (
    SELECT   l.isbn, l.titulo, count(p.id_prestamo) AS prestamos
    FROM     biblioteca.libro l
    LEFT JOIN biblioteca.prestamo p ON p.isbn = l.isbn
    GROUP BY l.isbn, l.titulo
    ORDER BY prestamos DESC
    FETCH FIRST 20 ROWS WITH TIES
) AS top
ORDER BY prestamos DESC, titulo;

-- ---------------------------------------------------------------------
-- Reporte 2. El o los lectores que más libros han leído
--
-- Decisiones:
--   - "Libro leído" = préstamo DEVUELTO (sección 3.2 del proyecto): los
--     préstamos abiertos no cuentan, para no premiar a quien retiene libros.
--   - Se cuentan préstamos devueltos, no títulos distintos: si alguien lee
--     dos veces el mismo libro, cuenta 2. (Con los datos actuales da igual.)
--   - "El o los": si hay empate en el máximo, salen todos (= max, no LIMIT 1).
-- ---------------------------------------------------------------------
\echo
\echo '== Reporte 2. El o los lectores que más libros han leído (préstamos devueltos) =='
WITH leidos AS (
    SELECT   p.id_lector, count(*) AS devueltos
    FROM     biblioteca.prestamo p
    WHERE    p.fecha_devolucion IS NOT NULL          -- solo préstamos completados
    GROUP BY p.id_lector
)
SELECT u.documento, u.nombres, u.apellidos, x.devueltos
FROM   leidos x
JOIN   biblioteca.usuario u ON u.id_usuario = x.id_lector
WHERE  x.devueltos = (SELECT max(devueltos) FROM leidos)
ORDER BY u.apellidos, u.nombres;

-- ---------------------------------------------------------------------
-- Reporte 3. Lectores morosos (con al menos un préstamo vencido y sin devolver)
--
-- Decisiones:
--   - Moroso = tiene AL MENOS UN préstamo abierto (sin devolver) cuya fecha
--     de vencimiento ya pasó. Devolver tarde NO deja moroso a nadie.
--   - Un préstamo que vence HOY todavía no está en mora: comparación
--     estricta (<). Con <= se consideraría en mora desde el día del vencimiento.
--   - Una fila por lector (EXISTS), aunque tenga varios préstamos en mora.
--   - La mora se calcula con las fechas: el esquema no guarda un "estado".
-- ---------------------------------------------------------------------
\echo
\echo '== Reporte 3. Lectores morosos =='
SELECT u.documento, u.nombres, u.apellidos
FROM   biblioteca.lector le
JOIN   biblioteca.usuario u ON u.id_usuario = le.id_usuario
WHERE  EXISTS (SELECT 1
               FROM   biblioteca.prestamo p
               WHERE  p.id_lector = le.id_usuario            -- préstamos de ESTE lector
                 AND  p.fecha_devolucion IS NULL             -- que no ha devuelto
                 AND  p.fecha_vencimiento < CURRENT_DATE)    -- y que ya vencieron
ORDER BY u.apellidos, u.nombres;

-- ---------------------------------------------------------------------
-- Reporte 4. Préstamos en mora: la lista para "Enviar notificación"
--
-- Decisiones:
--   - Una fila por PRÉSTAMO en mora (no por lector): quien tenga dos
--     préstamos vencidos aparece dos veces, una por libro.
--   - La condición de mora es la misma del reporte 3 (abierto y vencido, con <).
--   - Días de mora = hoy - fecha de vencimiento (restar dos fechas da días).
--   - Orden: primero los que llevan más días en mora; empates por nombre.
--   - Contacto: nombre y correo vienen de usuario; el teléfono, de lector.
-- ---------------------------------------------------------------------
\echo
\echo '== Reporte 4. Préstamos en mora (lista de notificación) =='
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
  AND  p.fecha_vencimiento < CURRENT_DATE         -- y ya vencido
ORDER BY dias_mora DESC, lector;
