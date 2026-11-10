-- =====================================================================
-- datos-prestamos.sql  ·  Préstamos de prueba para los 4 reportes (S15/S16)
--
-- Requisito: haber corrido antes las cargas de libros (semilla y CSV propio)
-- y de lectores, porque los préstamos apuntan a esos ejemplares y lectores.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prestamos.sql
--
-- Re-ejecutable: primero borra SUS PROPIOS datos (los préstamos registrados por
-- la bibliotecaria de prueba y la propia bibliotecaria) y los vuelve a crear.
-- Las fechas son relativas a CURRENT_DATE: si este script se corre el MISMO
-- DÍA que reportes.sql, los reportes de mora dan siempre lo mismo. Si se corrió
-- otro día, hay que volver a correrlo antes de los reportes.
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
    -- Mariana: 5 devueltos a tiempo
    ('1000000001', '9780000000001', 1, 200, 190),   -- Cien años de soledad
    ('1000000001', '9780000000014', 1, 180, 170),   -- 1984
    ('1000000001', '9780000000032', 1, 160, 150),   -- Harry Potter
    ('1000000001', '9780000000004', 1, 140, 130),   -- Rayuela
    ('1000000001', '9780000000039', 1, 120, 110),   -- La vorágine (CSV propio)
    -- Santiago: 5 devueltos; el Quijote, 6 días tarde (fue mora, ya no lo es)
    ('1000000002', '9780000000001', 2, 195, 185),   -- Cien años de soledad
    ('1000000002', '9780000000014', 2, 175, 165),   -- 1984
    ('1000000002', '9780000000017', 1, 150, 140),   -- El principito
    ('1000000002', '9780000000040', 1, 100,  90),   -- María (CSV propio)
    ('1000000002', '9780000000009', 1,  70,  50),   -- Don Quijote: vencía hace 56 días
    -- Valentina: 2 devueltos, 1 abierto en mora y 1 abierto a tiempo
    ('1000000003', '9780000000001', 3, 110, 100),   -- Cien años de soledad
    ('1000000003', '9780000000002', 1,  60,  50),   -- El amor en los tiempos del cólera
    ('1000000003', '9780000000010', 1,  21, NULL),  -- La sombra del viento: 7 días de mora
    ('1000000003', '9780000000032', 2,  10, NULL),  -- Harry Potter: vence en 4 días
    -- Juan David: 3 abiertos (el máximo) y ninguno devuelto
    ('1000000004', '9780000000001', 4,  27, NULL),  -- Cien años de soledad: 13 días de mora
    ('1000000004', '9780000000014', 3,  20, NULL),  -- 1984: 6 días de mora
    ('1000000004', '9780000000004', 2,  14, NULL),  -- Rayuela: vence HOY (todavía no es mora)
    -- Camila: 3 devueltos y 3 abiertos a tiempo (6 préstamos, la que más tiene)
    ('1000000005', '9780000000017', 2, 150, 142),   -- El principito
    ('1000000005', '9780000000003', 1, 120, 112),   -- Crónica de una muerte anunciada
    ('1000000005', '9780000000011', 1,  90,  85),   -- Como agua para chocolate
    ('1000000005', '9780000000032', 3,  12, NULL),  -- Harry Potter: vence en 2 días
    ('1000000005', '9780000000015', 1,   8, NULL),  -- Un mundo feliz: vence en 6 días
    ('1000000005', '9780000000016', 1,   3, NULL),  -- Fahrenheit 451: vence en 11 días
    -- Sebastián: 1 devuelto y 1 abierto en mora
    ('1000000006', '9780000000005', 1,  90,  80),   -- Pedro Páramo
    ('1000000006', '9780000000026', 1,  45, NULL),  -- Crimen y castigo: 31 días de mora
    -- Isabella: 3 devueltos
    ('1000000007', '9780000000007', 1, 100,  95),   -- Ficciones
    ('1000000007', '9780000000018', 1,  80,  70),   -- Matilda
    ('1000000007', '9780000000022', 1,  40,  30),   -- Sapiens
    -- Andrés Felipe: 1 devuelto y 1 abierto en mora
    ('1000000008', '9780000000028', 1,  60,  50),   -- Orgullo y prejuicio
    ('1000000008', '9780000000031', 1,  16, NULL)   -- El nombre del viento: 2 días de mora
    -- Los lectores 1000000009 a 1000000020: ningún préstamo
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
