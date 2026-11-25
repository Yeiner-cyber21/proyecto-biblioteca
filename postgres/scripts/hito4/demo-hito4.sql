-- =====================================================================
-- demo-hito4.sql  ·  Hito 4: demo para la evidencia (capturas o video)
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Cuatro escenas con datos del proyecto (datos-prueba.sql del S16), cada una
-- con CONSULTA ANTES, OPERACIÓN y CONSULTA DESPUÉS:
--   1. El procedimiento registrar_prestamo registra un préstamo.
--   2. El trigger RECHAZA un INSERT directo para un lector en mora.
--   3. El trigger RECHAZA el 4.º préstamo de una lectora con 3 activos.
--   4. registrar_devolucion pone al día a un lector, y el trigger ya lo deja pasar.
-- Entre escena y escena se detiene: tomar la captura y presionar Enter.
--
-- Uso, el mismo día que datos-prueba.sql (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/demo-hito4.sql
--
-- NO deja cambios (BEGIN … ROLLBACK): se puede repetir las veces que se quiera.
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET search_path TO biblioteca, public;

BEGIN;
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on

-- La situación de un lector, con las funciones del Hito 4
CREATE TEMP VIEW situacion AS
SELECT u.documento,
       u.nombres || ' ' || u.apellidos      AS lector,
       prestamos_activos(u.id_usuario)      AS prestamos_activos,
       prestamos_en_mora(u.id_usuario)      AS prestamos_en_mora,
       CASE WHEN en_mora(u.id_usuario) THEN 'sí' ELSE 'no' END AS en_mora
FROM   usuario u
JOIN   lector  l ON l.id_usuario = u.id_usuario;

-- =====================================================================
\echo
\echo '############################################################################'
\echo '#  ESCENA 1. El PROCEDIMIENTO registrar_prestamo (sección 3.1, punto 4)    #'
\echo '############################################################################'
\echo
\echo '--- ANTES: Mariana no tiene préstamos abiertos; Cien años de soledad tiene 3 copias libres'
SELECT * FROM situacion WHERE documento = '1000000001';
SELECT isbn, titulo, ejemplares_disponibles(isbn) AS disponibles
FROM   libro WHERE isbn = '9780000000001';

\echo '--- OPERACIÓN: la bibliotecaria Andrea registra el préstamo'
\echo 'CALL registrar_prestamo(''1000000001'', ''9780000000001'', ''2000000001'');'
CALL registrar_prestamo('1000000001', '9780000000001', '2000000001');

\echo '--- DESPUÉS: Mariana tiene 1 préstamo (vence en 14 días) y quedan 2 copias libres'
SELECT * FROM situacion WHERE documento = '1000000001';
SELECT p.id_prestamo, l.titulo, p.numero_copia AS copia, p.fecha_prestamo, p.fecha_vencimiento,
       ejemplares_disponibles(p.isbn) AS disponibles
FROM   prestamo p
JOIN   libro    l ON l.isbn = p.isbn
JOIN   usuario  u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000001' AND p.fecha_devolucion IS NULL;
\prompt '>>> Tome la captura de la escena 1 y presione Enter para continuar... ' pausa

-- =====================================================================
\echo
\echo '############################################################################'
\echo '#  ESCENA 2. El TRIGGER rechaza un INSERT directo: lector en mora (3.2)    #'
\echo '############################################################################'
\echo
\echo '--- ANTES: Juan David tiene 2 préstamos, los 2 en mora'
SELECT * FROM situacion WHERE documento = '1000000004';

\echo '--- OPERACIÓN: un INSERT directo en prestamo, SIN pasar por el procedimiento'
\echo 'INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario) ...  -- Juan David, Alicia, copia 1'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario)
SELECT u.id_usuario, '9780000000019', 1, b.id_usuario
FROM   usuario u, usuario b
WHERE  u.documento = '1000000004' AND b.documento = '2000000001';
\echo '    (el CONTEXT "function validar_prestamo()" muestra que lo rechazó el TRIGGER)'

\echo '--- DESPUÉS: no se registró nada; Juan David sigue con 2 préstamos'
SELECT * FROM situacion WHERE documento = '1000000004';
\prompt '>>> Tome la captura de la escena 2 y presione Enter para continuar... ' pausa

-- =====================================================================
\echo
\echo '############################################################################'
\echo '#  ESCENA 3. El TRIGGER rechaza el 4.º préstamo: máximo 3 activos (3.2)    #'
\echo '############################################################################'
\echo
\echo '--- ANTES: Camila tiene 3 préstamos activos, todos al día'
SELECT * FROM situacion WHERE documento = '1000000005';

\echo '--- OPERACIÓN: un INSERT directo del 4.º préstamo'
\echo 'INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario) ...  -- Camila, Alicia, copia 1'
INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario)
SELECT u.id_usuario, '9780000000019', 1, b.id_usuario
FROM   usuario u, usuario b
WHERE  u.documento = '1000000005' AND b.documento = '2000000001';

\echo '--- DESPUÉS: no se registró nada; Camila sigue con 3'
SELECT * FROM situacion WHERE documento = '1000000005';
\prompt '>>> Tome la captura de la escena 3 y presione Enter para continuar... ' pausa

-- =====================================================================
\echo
\echo '############################################################################'
\echo '#  ESCENA 4. DEVOLUCIÓN completa (3.1, punto 5) y el trigger deja pasar    #'
\echo '############################################################################'
\echo
SELECT string_agg(p.id_prestamo::text, ', ' ORDER BY p.id_prestamo) AS ids_juan_david
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000004' AND p.fecha_devolucion IS NULL \gset
SELECT min(p.id_prestamo) AS jd1, max(p.id_prestamo) AS jd2
FROM   prestamo p JOIN usuario u ON u.id_usuario = p.id_lector
WHERE  u.documento = '1000000004' AND p.fecha_devolucion IS NULL \gset

\echo '--- ANTES: Juan David está en mora con 2 préstamos, ids' :ids_juan_david
SELECT * FROM situacion WHERE documento = '1000000004';

\echo '--- OPERACIÓN: devuelve los dos libros'
CALL registrar_devolucion(:jd1);
CALL registrar_devolucion(:jd2);

\echo '--- DESPUÉS: ya no está en mora...'
SELECT * FROM situacion WHERE documento = '1000000004';
\echo '--- ...y ahora el préstamo SÍ pasa (el trigger lo deja pasar)'
CALL registrar_prestamo('1000000004', '9780000000019', '2000000001');
SELECT * FROM situacion WHERE documento = '1000000004';
\prompt '>>> Tome la captura de la escena 4 y presione Enter para terminar... ' pausa

-- Se deshace todo: la demo no deja cambios
\set ON_ERROR_ROLLBACK off
ROLLBACK;
\echo
\echo 'Fin de la demo: ROLLBACK, la base quedó como la dejó datos-prueba.sql.'
