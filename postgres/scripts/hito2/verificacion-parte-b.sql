-- =====================================================================
-- verificacion-parte-b.sql  ·  Tabla de verificación de la parte B (S16)
--
-- Comprueba los 8 casos de prueba de la guía S16 (sección 4) contra lo que
-- devuelven los 4 reportes. No repite la lógica de los reportes: lee las
-- vistas que crea reportes.sql, así que prueba exactamente esas consultas.
--
-- Requisito: haber corrido datos-prueba.sql y reportes.sql (el mismo día).
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/verificacion-parte-b.sql
--
-- La columna "esperado" se escribió ANTES de correr los reportes (es la
-- misma que está en el encabezado de datos-prueba.sql). Si todo está bien,
-- las 9 filas dicen "sí" en la columna coincide.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo
\echo '== Verificación de la parte B: los 8 casos de prueba de la guía S16 =='
WITH
r1 AS (SELECT * FROM biblioteca.reporte_top_libros),
r2 AS (SELECT * FROM biblioteca.reporte_mas_lectores),
r3 AS (SELECT * FROM biblioteca.reporte_morosos),
-- el reporte 4 no muestra el documento: se recupera por el correo, que es UNIQUE
r4 AS (SELECT m.*, u.documento
       FROM   biblioteca.reporte_prestamos_mora m
       JOIN   biblioteca.usuario u ON u.correo = m.correo),
-- caso 8: lectores que no tienen ningún préstamo
sin_prestamos AS (
    SELECT u.documento
    FROM   biblioteca.lector le
    JOIN   biblioteca.usuario u ON u.id_usuario = le.id_usuario
    WHERE  NOT EXISTS (SELECT 1 FROM biblioteca.prestamo p WHERE p.id_lector = le.id_usuario)
),
casos (caso, reporte, prueba, esperado, obtenido) AS (
    SELECT '1', 'R1', 'Libro sin préstamos (El olvido que seremos)',
           'cuenta 0; fuera del top',
           'cuenta ' || (SELECT count(p.id_prestamo)
                         FROM   biblioteca.libro l
                         LEFT JOIN biblioteca.prestamo p ON p.isbn = l.isbn
                         WHERE  l.titulo = 'El olvido que seremos')
           || CASE WHEN EXISTS (SELECT 1 FROM r1 WHERE titulo = 'El olvido que seremos')
                   THEN '; dentro del top' ELSE '; fuera del top' END
    UNION ALL
    SELECT '2', 'R1', 'Empate en el último puesto del top',
           '21 filas; 16 empatados con 1',
           (SELECT count(*) FROM r1) || ' filas; '
           || (SELECT count(*) FROM r1 WHERE prestamos = (SELECT min(prestamos) FROM r1))
           || ' empatados con ' || (SELECT min(prestamos) FROM r1)
    UNION ALL
    SELECT '3', 'R2', 'Empate en el primer lugar',
           'Mariana y Santiago, 5',
           (SELECT string_agg(nombres, ' y ' ORDER BY nombres) || ', ' || max(devueltos) FROM r2)
    UNION ALL
    SELECT '4', 'R2', 'Juan David (sin devueltos) y Camila (6 préstamos)',
           'no sale ninguno',
           CASE WHEN EXISTS (SELECT 1 FROM r2 WHERE documento IN ('1000000004', '1000000005'))
                THEN 'sale alguno' ELSE 'no sale ninguno' END
    UNION ALL
    SELECT '5', 'R3, R4', 'Santiago devolvió el Quijote 6 días tarde',
           'R3: 0 · R4: 0',
           'R3: ' || (SELECT count(*) FROM r3 WHERE documento = '1000000002')
           || ' · R4: ' || (SELECT count(*) FROM r4 WHERE documento = '1000000002')
    UNION ALL
    SELECT '6', 'R3, R4', 'Isabella: su préstamo vence hoy (regla <)',
           'R3: 0 · R4: 0',
           'R3: ' || (SELECT count(*) FROM r3 WHERE documento = '1000000007')
           || ' · R4: ' || (SELECT count(*) FROM r4 WHERE documento = '1000000007')
    UNION ALL
    SELECT '7', 'R3, R4', 'Juan David: dos préstamos en mora',
           'R3: 1 · R4: 2',
           'R3: ' || (SELECT count(*) FROM r3 WHERE documento = '1000000004')
           || ' · R4: ' || (SELECT count(*) FROM r4 WHERE documento = '1000000004')
    UNION ALL
    SELECT '8', 'R2, R3, R4', 'Lectores sin ningún préstamo',
           '12 lectores; R2: 0 · R3: 0 · R4: 0',
           (SELECT count(*) FROM sin_prestamos) || ' lectores; '
           || 'R2: ' || (SELECT count(*) FROM r2 WHERE documento IN (SELECT documento FROM sin_prestamos))
           || ' · R3: ' || (SELECT count(*) FROM r3 WHERE documento IN (SELECT documento FROM sin_prestamos))
           || ' · R4: ' || (SELECT count(*) FROM r4 WHERE documento IN (SELECT documento FROM sin_prestamos))
    UNION ALL
    SELECT 'total', 'R1 a R4', 'Filas de cada reporte',
           '21 · 2 · 4 · 5',
           (SELECT count(*) FROM r1) || ' · ' || (SELECT count(*) FROM r2) || ' · '
           || (SELECT count(*) FROM r3) || ' · ' || (SELECT count(*) FROM r4)
)
SELECT caso, reporte, prueba, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'sí' ELSE 'NO' END AS coincide
FROM   casos;
