-- =====================================================================
-- pruebas-programacion.sql  ·  Hito 4: batería de pruebas de programacion.sql
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Para cada regla, al menos un caso que debe pasar y uno que debe fallar,
-- con el resultado esperado en el ">>" que lo anuncia (estilo S22, parte A).
-- Los casos usan los préstamos de datos-prueba.sql (S16):
--   Mariana (1000000001)     sin préstamos abiertos
--   Valentina (1000000003)   1 en mora (7 días) y 1 al día
--   Juan David (1000000004)  2 abiertos, los dos en mora (13 y 6 días)
--   Camila (1000000005)      3 abiertos al día: el máximo
--   Isabella (1000000007)    1 abierto que vence HOY (con "<", no es mora)
--   Laura, Daniel, Sofía (1000000009 a 1000000011): sin préstamos
--   Andrea (2000000001)      la bibliotecaria de prueba
--
-- Orden, el MISMO día (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/programacion.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/datos-prueba.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/pruebas-programacion.sql
--
-- Una corrida muestra 15 ERROR, todos en casos que deben fallar.
--
-- NO deja cambios: todo corre dentro de BEGIN … ROLLBACK. Con
-- ON_ERROR_ROLLBACK, psql deshace solo la sentencia que falla y sigue con
-- la siguiente, sin abortar la transacción. Se puede correr las veces que
-- se quiera; al final la base queda como la dejó datos-prueba.sql.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO biblioteca, public;

\echo
\echo '=================== 0. Estado inicial (lo que dejó datos-prueba.sql) ==================='
\echo '>> esperado: Mariana 0/f, Valentina 2/t, Juan David 2/t, Camila 3/f, Isabella 1/f, Laura 0/f'
SELECT u.documento, u.nombres,
       prestamos_activos(u.id_usuario)  AS activos,
       prestamos_en_mora(u.id_usuario)  AS en_mora_n,
       en_mora(u.id_usuario)            AS en_mora
FROM   usuario u
WHERE  u.documento IN ('1000000001', '1000000003', '1000000004',
                       '1000000005', '1000000007', '1000000009')
ORDER BY u.documento;

\echo '>> las funciones coinciden con los reportes del S16: 4 lectores morosos y 5 préstamos en mora'
SELECT count(*) FILTER (WHERE en_mora(id_usuario))   AS lectores_en_mora,
       sum(prestamos_en_mora(id_usuario))            AS prestamos_en_mora
FROM   lector;

\echo '>> disponibles: Cien años 3 (de 4), Pedro Páramo 2 (de 2), Rayuela 2 (de 3)'
SELECT isbn, titulo, ejemplares_disponibles(isbn) AS disponibles
FROM   libro
WHERE  isbn IN ('9780000000001', '9780000000005', '9780000000004')
ORDER BY isbn;

-- Desde aquí, todo se deshace al final
BEGIN;
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

-- =====================================================================
-- 1. Procedimiento registrar_prestamo (sección 3.1, punto 4)
-- =====================================================================
\echo
\echo '=================== 1. registrar_prestamo ==================='
\echo '>> P1 pasa: Mariana (sin préstamos abiertos) pide Cien años de soledad. NOTICE con la copia 1, la más baja libre (la 4 la tiene Juan David)'
CALL registrar_prestamo('1000000001', '9780000000001', '2000000001');
\echo '>> P1 después: Mariana con 1 activo, Cien años con 2 disponibles, vence en 14 días'
SELECT p.id_prestamo, u.nombres, p.isbn, p.numero_copia, p.fecha_prestamo, p.fecha_vencimiento,
       p.fecha_vencimiento - p.fecha_prestamo AS plazo,
       ejemplares_disponibles(p.isbn)         AS disponibles_ahora
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000001' AND p.fecha_devolucion IS NULL;

\echo '>> P2 pasa: Isabella tiene 1 préstamo que vence HOY; con "<" no está en mora'
CALL registrar_prestamo('1000000007', '9780000000019', '2000000001');

\echo '>> P3 debe fallar: el lector no existe'
CALL registrar_prestamo('1000000099', '9780000000001', '2000000001');
\echo '>> P4 debe fallar: quien registra no es bibliotecario (es la lectora Mariana)'
CALL registrar_prestamo('1000000009', '9780000000001', '1000000001');
\echo '>> P5 debe fallar: el libro no existe'
CALL registrar_prestamo('1000000009', '9789999999999', '2000000001');
\echo '>> P6 debe fallar: Regla de mora, Juan David tiene 2 préstamos en mora'
CALL registrar_prestamo('1000000004', '9780000000019', '2000000001');
\echo '>> P7 debe fallar: Regla de mora, Valentina tiene 1 en mora (aunque solo tiene 2 abiertos)'
CALL registrar_prestamo('1000000003', '9780000000019', '2000000001');
\echo '>> P8 debe fallar: Regla de máximo, Camila ya tiene 3 préstamos activos'
CALL registrar_prestamo('1000000005', '9780000000019', '2000000001');

\echo '>> P9 pasan dos y falla el tercero: Pedro Páramo tiene 2 copias. Laura se lleva la 1, Daniel la 2, Sofía ya no encuentra'
CALL registrar_prestamo('1000000009', '9780000000005', '2000000001');
CALL registrar_prestamo('1000000010', '9780000000005', '2000000001');
CALL registrar_prestamo('1000000011', '9780000000005', '2000000001');

\echo '>> P10 debe fallar: un lector inactivo no recibe préstamos (se inactiva a Nicolás para la prueba)'
UPDATE usuario SET activo = false WHERE documento = '1000000012';
CALL registrar_prestamo('1000000012', '9780000000019', '2000000001');
\echo '>> P11 debe fallar: un libro dado de baja no se presta (se da de baja Rayuela para la prueba)'
UPDATE libro SET activo = false WHERE isbn = '9780000000004';
CALL registrar_prestamo('1000000013', '9780000000004', '2000000001');

-- =====================================================================
-- 2. Trigger prestamo_validar (sección 3.2): un INSERT directo, sin pasar
--    por el procedimiento, también tiene que cumplir las reglas.
--    El CONTEXT del error dice "PL/pgSQL function validar_prestamo()": lo
--    rechazó el trigger, no el procedimiento.
-- =====================================================================
\echo
\echo '=================== 2. Trigger prestamo_validar (INSERT directo) ==================='
\echo '>> T1 debe fallar: Regla de mora, INSERT directo para Juan David'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_vencimiento)
SELECT u.id_usuario, '9780000000019', 1, b.id_usuario, CURRENT_DATE + 14
FROM   usuario u, usuario b
WHERE  u.documento = '1000000004' AND b.documento = '2000000001';

\echo '>> T2 debe fallar: Regla de máximo, INSERT directo del 4.º préstamo de Camila'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_vencimiento)
SELECT u.id_usuario, '9780000000019', 1, b.id_usuario, CURRENT_DATE + 14
FROM   usuario u, usuario b
WHERE  u.documento = '1000000005' AND b.documento = '2000000001';

\echo '>> T3 debe fallar: la copia 2 de Alicia está en reparación'
UPDATE ejemplar SET estado = 'en_reparacion' WHERE isbn = '9780000000019' AND numero_copia = 2;
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_vencimiento)
SELECT u.id_usuario, '9780000000019', 2, b.id_usuario, CURRENT_DATE + 14
FROM   usuario u, usuario b
WHERE  u.documento = '1000000014' AND b.documento = '2000000001';

\echo '>> T4 debe fallar: la misma copia no se presta dos veces (índice único parcial, Hito 2)'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_vencimiento)
SELECT u.id_usuario, p.isbn, p.numero_copia, b.id_usuario, CURRENT_DATE + 14
FROM   prestamo p, usuario u, usuario b
WHERE  p.fecha_devolucion IS NULL AND p.isbn = '9780000000031'
  AND  u.documento = '1000000014' AND b.documento = '2000000001';

\echo '>> T5 pasa: INSERT directo correcto SIN fecha de vencimiento; el trigger pone hoy + 14'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario)
SELECT u.id_usuario, '9780000000019', 3, b.id_usuario
FROM   usuario u, usuario b
WHERE  u.documento = '1000000014' AND b.documento = '2000000001'
RETURNING id_prestamo, isbn, numero_copia, fecha_prestamo, fecha_vencimiento,
          fecha_vencimiento - fecha_prestamo AS plazo;

\echo '>> T6 pasa: un préstamo que se registra YA DEVUELTO es historia, no un préstamo nuevo (aunque Juan David esté en mora hoy)'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario,
                      fecha_prestamo, fecha_vencimiento, fecha_devolucion)
SELECT u.id_usuario, '9780000000019', 1, b.id_usuario,
       CURRENT_DATE - 300, CURRENT_DATE - 286, CURRENT_DATE - 290
FROM   usuario u, usuario b
WHERE  u.documento = '1000000004' AND b.documento = '2000000001';

-- =====================================================================
-- 3. Procedimiento registrar_devolucion (sección 3.1, punto 5)
-- =====================================================================
\echo
\echo '=================== 3. registrar_devolucion ==================='
SELECT p.id_prestamo AS jd_cien
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000004' AND p.isbn = '9780000000001' AND p.fecha_devolucion IS NULL \gset
SELECT p.id_prestamo AS jd_1984
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000004' AND p.isbn = '9780000000014' AND p.fecha_devolucion IS NULL \gset
SELECT p.id_prestamo AS camila_hp
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000005' AND p.isbn = '9780000000032' AND p.fecha_devolucion IS NULL \gset

\echo '>> D1 pasa: Juan David devuelve Cien años, 13 días tarde; sigue en mora por el otro'
CALL registrar_devolucion(:jd_cien);
\echo '>> D2 pasa: devuelve 1984, 6 días tarde; queda al día'
CALL registrar_devolucion(:jd_1984);
\echo '>> D3 pasa: ahora el procedimiento SÍ le presta La sombra del viento (y el trigger lo deja pasar)'
CALL registrar_prestamo('1000000004', '9780000000010', '2000000001');
\echo '>> D4 debe fallar: el préstamo de Cien años ya fue devuelto'
CALL registrar_devolucion(:jd_cien);
\echo '>> D5 debe fallar: el préstamo no existe'
CALL registrar_devolucion(999999);
\echo '>> D6 pasa: Camila devuelve Harry Potter a tiempo; baja de 3 a 2 activos y puede pedir otro'
CALL registrar_devolucion(:camila_hp);
CALL registrar_prestamo('1000000005', '9780000000026', '2000000001');

\echo
\echo '=================== Resumen dentro de la transacción ==================='
\echo '>> esperado: Juan David 1 activo y sin mora; Camila 3 activos; Mariana 1'
SELECT u.documento, u.nombres,
       prestamos_activos(u.id_usuario) AS activos,
       en_mora(u.id_usuario)           AS en_mora
FROM   usuario u
WHERE  u.documento IN ('1000000001', '1000000004', '1000000005')
ORDER BY u.documento;

-- Se deshace todo: la base queda como la dejó datos-prueba.sql
\set ON_ERROR_ROLLBACK off
ROLLBACK;
\set ON_ERROR_STOP on

\echo
\echo '=================== Después del ROLLBACK (esperado: 30 | 20 | 10 | 5) ==================='
SELECT count(*)                                                     AS prestamos,
       count(*) FILTER (WHERE fecha_devolucion IS NOT NULL)          AS devueltos,
       count(*) FILTER (WHERE fecha_devolucion IS NULL)              AS abiertos,
       count(*) FILTER (WHERE fecha_devolucion IS NULL
                          AND fecha_vencimiento < CURRENT_DATE)      AS en_mora
FROM   prestamo;
