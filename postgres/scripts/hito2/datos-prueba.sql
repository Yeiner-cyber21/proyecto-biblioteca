-- =====================================================================
-- datos-prueba.sql  ·  Préstamos de prueba para los 4 reportes (S16, parte B)
--
-- Requisito: haber corrido antes las cargas de libros (semilla y CSV propio)
-- y de lectores, porque los préstamos apuntan a esos ejemplares y lectores.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/datos-prueba.sql
--
-- Re-ejecutable: primero borra SUS PROPIOS datos (los préstamos registrados por
-- la bibliotecaria de prueba y la propia bibliotecaria) y los vuelve a crear.
-- Las fechas son relativas a CURRENT_DATE (CURRENT_DATE - p), como en
-- S15-reportes-demo.sql: así la mora sigue siendo mora el día de la
-- sustentación. Este script y reportes.sql se corren EL MISMO DÍA; si no,
-- hay que volver a correr este antes de los reportes.
--
-- (Hasta S15 este archivo se llamó datos-prestamos.sql.)
-- =====================================================================
--
-- RESULTADO ESPERADO, escrito ANTES de correr reportes.sql
-- ---------------------------------------------------------------------
-- Totales: 30 préstamos | 20 devueltos | 10 abiertos | 5 en mora.
--
-- Reporte 1 (top 20 con empates): 21 filas.
--   Cien años de soledad 4 · 1984 3 · Harry Potter 3 · El principito 2 ·
--   Rayuela 2 · y 16 libros con 1 préstamo, empatados del puesto 6 al 21.
--   Ningún libro con 0 préstamos (hay 21 libros con al menos uno).
-- Reporte 2 (el o los que más han leído): 2 filas.
--   Mariana Gómez y Santiago Rodríguez, con 5 préstamos devueltos cada uno.
-- Reporte 3 (lectores morosos, uno por fila): 4 filas.
--   Sebastián, Valentina, Juan David y Andrés Felipe.
-- Reporte 4 (préstamos en mora): 5 filas.
--   Sebastián 31 días · Juan David 13 · Valentina 7 · Juan David 6 · Andrés 2.
--
-- LOS 8 CASOS DE LA GUÍA S16 (sección 4) Y QUIÉN LOS CUBRE
-- ---------------------------------------------------------------------
-- 1. Libro que nadie ha prestado (R1): 16 libros sin préstamos, por ejemplo
--    "El olvido que seremos". R1 los cuenta con 0 (LEFT JOIN), pero no
--    entran al top porque hay 21 libros con al menos un préstamo.
-- 2. Empate en el último puesto (R1): 16 libros con 1 préstamo ocupan los
--    puestos 6 a 21. Salen todos: 21 filas en vez de 20.
-- 3. Empate en el primer lugar (R2): Mariana y Santiago, 5 devueltos cada uno.
-- 4. Abiertos y ninguno devuelto (R2): Juan David (2 abiertos, 0 devueltos)
--    no sale. Camila tiene MÁS préstamos que los ganadores (6) pero solo 3
--    devueltos: tampoco sale. (La regla de máximo 3 préstamos abiertos
--    impide que un lector SIN devoluciones supere a los ganadores, por eso
--    el caso se reparte entre los dos lectores.)
-- 5. Devuelto después de la fecha esperada (R3, R4): Santiago devolvió el
--    Quijote 6 días tarde. No es mora: no sale en R3 ni en R4.
-- 6. Abierto que vence hoy (R3, R4): Isabella. Es su ÚNICO préstamo abierto,
--    así que el caso se nota en los dos reportes. Regla del grupo: "<"
--    estricto, entonces NO está en mora y no sale ni en R3 ni en R4.
-- 7. Lector con dos préstamos en mora (R3, R4): Juan David. Una vez en R3
--    y dos veces en R4.
-- 8. Lector sin ningún préstamo (todos): los lectores 1000000009 a
--    1000000020 (12). No aparecen en R2, R3 ni R4.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Limpiar lo que dejó una corrida anterior de este mismo script.
--    Primero los préstamos (la FK de prestamo → bibliotecario lo exige),
--    después el usuario: ON DELETE CASCADE borra también su fila en bibliotecario.
-- ---------------------------------------------------------------------
DELETE FROM biblioteca.prestamo
WHERE id_bibliotecario IN (SELECT id_usuario FROM biblioteca.usuario WHERE documento = '2000000001');

DELETE FROM biblioteca.usuario WHERE documento = '2000000001';

-- ---------------------------------------------------------------------
-- 1. La bibliotecaria de prueba: quien "registra" los préstamos en el mostrador.
--    Como todo usuario, su contraseña se guarda con bcrypt (clave inicial: su documento).
-- ---------------------------------------------------------------------
INSERT INTO biblioteca.usuario (documento, nombres, apellidos, correo, contrasena_hash, perfil)
VALUES ('2000000001', 'Andrea', 'Castillo Ruiz', 'andrea.castillo@biblioteca-ejemplo.edu.co',
        public.crypt('2000000001', public.gen_salt('bf', 10)), 'bibliotecario');

INSERT INTO biblioteca.bibliotecario (id_usuario)
SELECT id_usuario FROM biblioteca.usuario WHERE documento = '2000000001';

-- ---------------------------------------------------------------------
-- 2. Los 30 préstamos. Cada fila: (documento del lector, isbn, copia, p, d)
--      p = hace cuántos días se prestó       → fecha_prestamo    = hoy - p
--      plazo estándar de 14 días             → fecha_vencimiento = hoy - p + 14
--      d = hace cuántos días se devolvió     → fecha_devolucion  = hoy - d
--          (NULL = todavía no lo ha devuelto: préstamo abierto)
--    Los datos respetan las reglas de negocio: nadie tiene más de 3 préstamos
--    abiertos, nadie recibió un préstamo nuevo mientras estaba en mora y
--    ninguna copia está prestada dos veces al mismo tiempo.
-- ---------------------------------------------------------------------
INSERT INTO biblioteca.prestamo (id_lector, isbn, numero_copia, id_bibliotecario,
                                 fecha_prestamo, fecha_vencimiento, fecha_devolucion)
SELECT u.id_usuario,
       v.isbn,
       v.copia,
       b.id_usuario,
       CURRENT_DATE - v.p,
       CURRENT_DATE - v.p + 14,
       CURRENT_DATE - v.d                      -- si d es NULL, la resta da NULL
FROM (VALUES
    -- Mariana: 5 devueltos a tiempo                              (caso 3)
    ('1000000001', '9780000000001', 1, 200, 190),   -- Cien años de soledad
    ('1000000001', '9780000000014', 1, 180, 170),   -- 1984
    ('1000000001', '9780000000032', 1, 160, 150),   -- Harry Potter
    ('1000000001', '9780000000004', 1, 140, 130),   -- Rayuela
    ('1000000001', '9780000000039', 1, 120, 110),   -- La vorágine (CSV propio)
    -- Santiago: 5 devueltos; el Quijote, 6 días tarde            (casos 3 y 5)
    ('1000000002', '9780000000001', 2, 195, 185),   -- Cien años de soledad
    ('1000000002', '9780000000014', 2, 175, 165),   -- 1984
    ('1000000002', '9780000000017', 1, 150, 140),   -- El principito
    ('1000000002', '9780000000040', 1, 100,  90),   -- María (CSV propio)
    ('1000000002', '9780000000009', 1,  70,  50),   -- Don Quijote: vencía hace 56 días, devuelto hace 50
    -- Valentina: 2 devueltos, 1 abierto en mora y 1 abierto a tiempo
    ('1000000003', '9780000000001', 3, 110, 100),   -- Cien años de soledad
    ('1000000003', '9780000000002', 1,  60,  50),   -- El amor en los tiempos del cólera
    ('1000000003', '9780000000010', 1,  21, NULL),  -- La sombra del viento: 7 días de mora
    ('1000000003', '9780000000032', 2,  10, NULL),  -- Harry Potter: vence en 4 días
    -- Juan David: 2 abiertos, los dos en mora, y ninguno devuelto (casos 4 y 7)
    ('1000000004', '9780000000001', 4,  27, NULL),  -- Cien años de soledad: 13 días de mora
    ('1000000004', '9780000000014', 3,  20, NULL),  -- 1984: 6 días de mora
    -- Camila: 3 devueltos y 3 abiertos a tiempo (6 préstamos, la que más tiene) (caso 4)
    ('1000000005', '9780000000017', 2, 150, 142),   -- El principito
    ('1000000005', '9780000000003', 1, 120, 112),   -- Crónica de una muerte anunciada
    ('1000000005', '9780000000011', 1,  90,  85),   -- Como agua para chocolate
    ('1000000005', '9780000000032', 3,  12, NULL),  -- Harry Potter: vence en 2 días
    ('1000000005', '9780000000015', 1,   8, NULL),  -- Un mundo feliz: vence en 6 días
    ('1000000005', '9780000000016', 1,   3, NULL),  -- Fahrenheit 451: vence en 11 días
    -- Sebastián: 1 devuelto y 1 abierto en mora
    ('1000000006', '9780000000005', 1,  90,  80),   -- Pedro Páramo
    ('1000000006', '9780000000026', 1,  45, NULL),  -- Crimen y castigo: 31 días de mora
    -- Isabella: 3 devueltos y 1 abierto que vence HOY            (caso 6)
    ('1000000007', '9780000000007', 1, 100,  95),   -- Ficciones
    ('1000000007', '9780000000018', 1,  80,  70),   -- Matilda
    ('1000000007', '9780000000022', 1,  40,  30),   -- Sapiens
    ('1000000007', '9780000000004', 2,  14, NULL),  -- Rayuela: vence HOY (con "<" todavía no es mora)
    -- Andrés Felipe: 1 devuelto y 1 abierto en mora
    ('1000000008', '9780000000028', 1,  60,  50),   -- Orgullo y prejuicio
    ('1000000008', '9780000000031', 1,  16, NULL)   -- El nombre del viento: 2 días de mora
    -- Los lectores 1000000009 a 1000000020: ningún préstamo      (caso 8)
    -- 16 libros del catálogo: ningún préstamo                    (caso 1)
) AS v (documento, isbn, copia, p, d)
JOIN biblioteca.usuario u ON u.documento = v.documento
JOIN biblioteca.lector  l ON l.id_usuario = u.id_usuario       -- garantiza que sea un lector
CROSS JOIN (SELECT bi.id_usuario
            FROM biblioteca.bibliotecario bi
            JOIN biblioteca.usuario ub ON ub.id_usuario = bi.id_usuario
            WHERE ub.documento = '2000000001') AS b;

COMMIT;

-- ---------------------------------------------------------------------
-- Resumen: debe dar 30 | 20 | 10 | 5
-- ---------------------------------------------------------------------
\echo
\echo '=== Préstamos de prueba (esperado: 30 | 20 | 10 | 5)'
SELECT count(*)                                                     AS prestamos,
       count(*) FILTER (WHERE fecha_devolucion IS NOT NULL)          AS devueltos,
       count(*) FILTER (WHERE fecha_devolucion IS NULL)              AS abiertos,
       count(*) FILTER (WHERE fecha_devolucion IS NULL
                          AND fecha_vencimiento < CURRENT_DATE)      AS en_mora
FROM biblioteca.prestamo;
