-- =====================================================================
-- S21-recorrido.sql  ·  Recorrido de la clase S21 (programación en la base)
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- S21 es una clase magistral (sin entregable). Este archivo corre, en orden,
-- todos los ejemplos de la guía sobre el esquema "programable", para
-- practicarlos y tenerlos como receta del Hito 4 (S22, parte B).
--
-- Uso, en PowerShell desde la carpeta del proyecto:
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/S21/S21-biblioteca-programable.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/S21/S21-recorrido.sql
-- Si se quiere correr otra vez, primero S21-biblioteca-programable.sql
-- (borra y recrea el esquema). Las sentencias que DEBEN fallar se anuncian
-- con ">>" y su ERROR es lo que muestra la guía.
-- =====================================================================

SET search_path TO programable;
\set ON_ERROR_STOP on
\pset pager off

-- =====================================================================
-- 3. Integridad referencial y restricciones avanzadas
-- =====================================================================
\set ON_ERROR_STOP off
\echo
\echo '=================== 3.1 Borrar algo referenciado ==================='
\echo '>> debe fallar: Camila tiene préstamos (prestamo_documento_fkey)'
DELETE FROM lector WHERE documento = '1000000005';
\echo '>> debe fallar: Sebastián tiene teléfonos (telefono_lector_documento_fkey)'
DELETE FROM lector WHERE documento = '1000000006';
\set ON_ERROR_STOP on

\echo
\echo '=================== 3.2 Acciones referenciales ==================='
-- Los teléfonos no existen sin el lector: CASCADE
ALTER TABLE telefono_lector
  DROP CONSTRAINT telefono_lector_documento_fkey,
  ADD  CONSTRAINT telefono_lector_documento_fkey
       FOREIGN KEY (documento) REFERENCES lector ON DELETE CASCADE;

\echo '>> DELETE 1 y 0 teléfonos: se van con él (se deshace con ROLLBACK)'
BEGIN;
DELETE FROM lector WHERE documento = '1000000006';
SELECT count(*) AS telefonos FROM telefono_lector WHERE documento = '1000000006';
ROLLBACK;

-- Los préstamos son historia: sin cascada, y explícito
ALTER TABLE prestamo
  DROP CONSTRAINT prestamo_documento_fkey,
  ADD  CONSTRAINT prestamo_documento_fkey
       FOREIGN KEY (documento) REFERENCES lector ON DELETE RESTRICT;

\echo
\echo '=================== 3.3 CHECK de dos columnas e índice único parcial ==================='
\set ON_ERROR_STOP off
\echo '>> debe fallar: fecha esperada antes del préstamo (prestamo_check)'
INSERT INTO prestamo (id_ejemplar, documento, fecha_prestamo, fecha_esperada)
VALUES (10, '1000000002', CURRENT_DATE, CURRENT_DATE - 1);
\set ON_ERROR_STOP on

\echo '>> hoy nada impide prestar dos veces el ejemplar 2: 2 filas (se deshace)'
BEGIN;
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (2, '1000000002', CURRENT_DATE + 14);
SELECT id, id_ejemplar, documento
FROM   prestamo
WHERE  id_ejemplar = 2 AND fecha_devolucion IS NULL;
ROLLBACK;

-- Único solo entre los préstamos abiertos
CREATE UNIQUE INDEX prestamo_ejemplar_abierto
    ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;

\set ON_ERROR_STOP off
\echo '>> debe fallar: duplicate key ... "prestamo_ejemplar_abierto"'
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (2, '1000000002', CURRENT_DATE + 14);

\echo
\echo '=================== 3.4 Lo que una restricción no puede hacer ==================='
\echo '>> debe fallar: cannot use subquery in check constraint'
ALTER TABLE prestamo ADD CHECK (
  (SELECT count(*) FROM prestamo p2
   WHERE p2.documento = documento AND p2.fecha_devolucion IS NULL) <= 3);
\set ON_ERROR_STOP on

-- =====================================================================
-- 4. Funciones
-- =====================================================================
\echo
\echo '=================== 4.1 Funciones en SQL ==================='
CREATE OR REPLACE FUNCTION prestamos_abiertos(p_documento varchar) RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*)
    FROM   prestamo
    WHERE  documento = p_documento
      AND  fecha_devolucion IS NULL;
$$;

\echo '>> esperado: 0, 0, 1, 3, 1, 0'
SELECT documento, nombres, prestamos_abiertos(documento) AS abiertos
FROM   lector
ORDER BY documento;

CREATE OR REPLACE FUNCTION en_mora(p_documento varchar) RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM prestamo
                   WHERE documento = p_documento
                     AND fecha_devolucion IS NULL
                     AND fecha_esperada < CURRENT_DATE);
$$;

\echo '>> esperado: Camila'
SELECT nombres FROM lector WHERE en_mora(documento);

\echo
\echo '=================== 4.2 Función en PL/pgSQL ==================='
CREATE OR REPLACE FUNCTION estado_prestamo(p_id integer) RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_esperada    date;
    v_devolucion  date;
BEGIN
    SELECT fecha_esperada, fecha_devolucion
    INTO   v_esperada, v_devolucion
    FROM   prestamo
    WHERE  id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el préstamo %', p_id;
    END IF;

    IF v_devolucion IS NOT NULL THEN
        RETURN 'devuelto';
    ELSIF v_esperada < CURRENT_DATE THEN
        RETURN 'en mora (' || (CURRENT_DATE - v_esperada) || ' días)';
    ELSE
        RETURN 'al día';
    END IF;
END;
$$;

\echo '>> esperado: 1, 2 y 8 devueltos; 6 en mora (11 días); 3, 4, 5 y 7 al día'
SELECT id, documento, estado_prestamo(id) FROM prestamo ORDER BY id;

\set ON_ERROR_STOP off
\echo '>> debe fallar: No existe el préstamo 99'
SELECT estado_prestamo(99);
\set ON_ERROR_STOP on

-- =====================================================================
-- 5. Procedimientos almacenados
-- =====================================================================
\echo
\echo '=================== 5.1 Registrar un préstamo y una devolución ==================='
CREATE OR REPLACE PROCEDURE registrar_prestamo(p_documento varchar, p_isbn char(13))
LANGUAGE plpgsql
AS $$
DECLARE
    v_ejemplar  integer;
    v_id        integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM lector WHERE documento = p_documento) THEN
        RAISE EXCEPTION 'El lector % no existe', p_documento;
    END IF;
    IF en_mora(p_documento) THEN
        RAISE EXCEPTION 'El lector % tiene préstamos en mora', p_documento;
    END IF;
    IF prestamos_abiertos(p_documento) >= 3 THEN
        RAISE EXCEPTION 'El lector % ya tiene 3 préstamos abiertos', p_documento;
    END IF;

    -- un ejemplar del libro que no tenga un préstamo abierto
    SELECT e.id_ejemplar INTO v_ejemplar
    FROM   ejemplar e
    WHERE  e.isbn = p_isbn
      AND  NOT EXISTS (SELECT 1 FROM prestamo p
                       WHERE p.id_ejemplar = e.id_ejemplar
                         AND p.fecha_devolucion IS NULL)
    ORDER BY e.id_ejemplar
    LIMIT 1;

    IF v_ejemplar IS NULL THEN
        RAISE EXCEPTION 'No hay ejemplares disponibles del libro %', p_isbn;
    END IF;

    INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
    VALUES (v_ejemplar, p_documento, CURRENT_DATE + 14)
    RETURNING id INTO v_id;

    RAISE NOTICE 'Préstamo % registrado: ejemplar %, devolver el %',
                 v_id, v_ejemplar, CURRENT_DATE + 14;
END;
$$;

\set ON_ERROR_STOP off
\echo '>> debe fallar: Camila tiene préstamos en mora'
CALL registrar_prestamo('1000000005', '9780000000001');
\echo '>> debe fallar: Juan David ya tiene 3 préstamos abiertos'
CALL registrar_prestamo('1000000004', '9780000000001');
\echo '>> debe fallar: no hay ejemplares disponibles de Pedro Páramo'
CALL registrar_prestamo('1000000003', '9780000000005');
\echo '>> debe fallar: el lector 1000000099 no existe'
CALL registrar_prestamo('1000000099', '9780000000005');
\echo '>> pasa: NOTICE Préstamo N registrado: ejemplar 1'
CALL registrar_prestamo('1000000003', '9780000000001');
\set ON_ERROR_STOP on

CREATE OR REPLACE PROCEDURE registrar_devolucion(p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE prestamo
    SET    fecha_devolucion = CURRENT_DATE
    WHERE  id = p_id
      AND  fecha_devolucion IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El préstamo % no existe o ya fue devuelto', p_id;
    END IF;
END;
$$;

\set ON_ERROR_STOP off
\echo '>> pasa: Valentina devuelve Rayuela'
CALL registrar_devolucion(7);
\echo '>> debe fallar: el préstamo 7 ya fue devuelto'
CALL registrar_devolucion(7);
\set ON_ERROR_STOP on

\echo
\echo '=================== 5.4 Lo que el procedimiento no cubre ==================='
\echo '>> un INSERT directo se salta la regla de 3 préstamos: Juan David queda con 4 (se deshace)'
BEGIN;
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (10, '1000000004', CURRENT_DATE + 14);
SELECT prestamos_abiertos('1000000004');
ROLLBACK;

\echo '>> y nadie actualizó libro.disponibles: Rayuela 1 contra 2, Cien años 2 contra 1'
SELECT * FROM descuadre;

-- =====================================================================
-- 6. Disparadores (triggers)
-- =====================================================================
\echo
\echo '=================== 6.2 Trigger BEFORE de validación ==================='
CREATE OR REPLACE FUNCTION validar_prestamo() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF en_mora(NEW.documento) THEN
        RAISE EXCEPTION 'El lector % tiene préstamos en mora', NEW.documento;
    END IF;
    IF prestamos_abiertos(NEW.documento) >= 3 THEN
        RAISE EXCEPTION 'El lector % ya tiene 3 préstamos abiertos', NEW.documento;
    END IF;
    -- si no se dio la fecha esperada, se pone la del plazo estándar
    IF NEW.fecha_esperada IS NULL THEN
        NEW.fecha_esperada := NEW.fecha_prestamo + 14;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prestamo_validar ON prestamo;
CREATE TRIGGER prestamo_validar
BEFORE INSERT ON prestamo
FOR EACH ROW
EXECUTE FUNCTION validar_prestamo();

\set ON_ERROR_STOP off
\echo '>> debe fallar: el mismo INSERT directo ya no pasa'
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (10, '1000000004', CURRENT_DATE + 14);
\set ON_ERROR_STOP on

\echo '>> sin fecha esperada: el trigger pone hoy + 14 (se deshace)'
BEGIN;
INSERT INTO prestamo (id_ejemplar, documento) VALUES (10, '1000000002')
RETURNING id, fecha_prestamo, fecha_esperada;
ROLLBACK;

\echo
\echo '=================== 6.3 Trigger AFTER de mantenimiento ==================='
CREATE OR REPLACE FUNCTION actualizar_disponibles() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE libro l
    SET    disponibles = (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
                       - (SELECT count(*)
                          FROM   prestamo p JOIN ejemplar e USING (id_ejemplar)
                          WHERE  e.isbn = l.isbn AND p.fecha_devolucion IS NULL)
    WHERE  l.isbn IN (SELECT isbn FROM ejemplar
                      WHERE  id_ejemplar IN (NEW.id_ejemplar, OLD.id_ejemplar));
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS prestamo_disponibles ON prestamo;
CREATE TRIGGER prestamo_disponibles
AFTER INSERT OR DELETE OR UPDATE OF id_ejemplar, fecha_devolucion ON prestamo
FOR EACH ROW
EXECUTE FUNCTION actualizar_disponibles();

\echo '>> se corrige una vez el descuadre que dejaron los procedimientos: UPDATE 2'
UPDATE libro l SET disponibles = d.calculado
FROM   descuadre d WHERE d.isbn = l.isbn;

\echo '>> 0 filas'
SELECT * FROM descuadre;
\echo '>> Quijote: disponibles pasa de 2 a 1'
SELECT titulo, disponibles FROM libro WHERE isbn = '9780000000009';
CALL registrar_prestamo('1000000002', '9780000000009');
SELECT titulo, disponibles FROM libro WHERE isbn = '9780000000009';
\echo '>> sigue en 0 filas: el trigger lo mantuvo'
SELECT * FROM descuadre;

\echo
\echo '=================== 6.4 Trigger AFTER de auditoría ==================='
CREATE TABLE IF NOT EXISTS auditoria_prestamo (
    id           bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operacion    text         NOT NULL,
    id_prestamo  integer      NOT NULL,
    usuario      text         NOT NULL DEFAULT current_user,
    momento      timestamptz  NOT NULL DEFAULT now(),
    antes        jsonb,
    despues      jsonb
);

CREATE OR REPLACE FUNCTION auditar_prestamo() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria_prestamo (operacion, id_prestamo, antes, despues)
        VALUES (TG_OP, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
    ELSE  -- DELETE
        INSERT INTO auditoria_prestamo (operacion, id_prestamo, antes)
        VALUES (TG_OP, OLD.id, to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS prestamo_auditar ON prestamo;
CREATE TRIGGER prestamo_auditar
AFTER UPDATE OR DELETE ON prestamo
FOR EACH ROW
EXECUTE FUNCTION auditar_prestamo();

\echo '>> se amplía el plazo del préstamo 3 y se borra el 4 (el borrado se deshace)'
UPDATE prestamo SET fecha_esperada = fecha_esperada + 7 WHERE id = 3;

BEGIN;
DELETE FROM prestamo WHERE id = 4;
SELECT operacion, id_prestamo, usuario,
       antes ->> 'fecha_esperada'   AS esperada_antes,
       despues ->> 'fecha_esperada' AS esperada_despues
FROM   auditoria_prestamo ORDER BY id;
ROLLBACK;

\echo '>> después del ROLLBACK solo queda el UPDATE: lo que no pasó no se audita'
SELECT operacion, id_prestamo FROM auditoria_prestamo ORDER BY id;

-- =====================================================================
-- 7. Cursores y ciclos frente a una sentencia sobre el conjunto
-- =====================================================================
\echo
\echo '=================== 7. Ciclo frente a conjunto ==================='
CREATE TABLE IF NOT EXISTS aviso_mora (
    id           integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_prestamo  integer  NOT NULL REFERENCES prestamo,
    fecha        date     NOT NULL DEFAULT CURRENT_DATE,
    mensaje      text     NOT NULL
);

CREATE OR REPLACE PROCEDURE generar_avisos_mora()
LANGUAGE plpgsql
AS $$
DECLARE
    r  record;
BEGIN
    FOR r IN
        SELECT p.id, l.nombres, l.correo, b.titulo, CURRENT_DATE - p.fecha_esperada AS dias
        FROM   prestamo p
        JOIN   lector   l USING (documento)
        JOIN   ejemplar e USING (id_ejemplar)
        JOIN   libro    b USING (isbn)
        WHERE  p.fecha_devolucion IS NULL
          AND  p.fecha_esperada < CURRENT_DATE
    LOOP
        INSERT INTO aviso_mora (id_prestamo, mensaje)
        VALUES (r.id, format('%s: "%s" lleva %s días de mora. Escribir a %s',
                             r.nombres, r.titulo, r.dias, r.correo));
        RAISE NOTICE 'Aviso para %', r.correo;
    END LOOP;
END;
$$;

\echo '>> con el ciclo: 1 aviso (Camila, El Aleph, 11 días)'
CALL generar_avisos_mora();
SELECT id_prestamo, mensaje FROM aviso_mora;

\echo '>> la misma tarea en UNA sentencia da el mismo aviso (se deshace para no duplicarlo)'
BEGIN;
DELETE FROM aviso_mora;
INSERT INTO aviso_mora (id_prestamo, mensaje)
SELECT p.id, format('%s: "%s" lleva %s días de mora. Escribir a %s',
                    l.nombres, b.titulo, CURRENT_DATE - p.fecha_esperada, l.correo)
FROM   prestamo p
JOIN   lector   l USING (documento)
JOIN   ejemplar e USING (id_ejemplar)
JOIN   libro    b USING (isbn)
WHERE  p.fecha_devolucion IS NULL
  AND  p.fecha_esperada < CURRENT_DATE;
SELECT id_prestamo, mensaje FROM aviso_mora;
ROLLBACK;

-- =====================================================================
-- Resumen: los triggers de prestamo (S21, sección 6.6: documentarlos)
-- =====================================================================
\echo
\echo '=================== Triggers de prestamo ==================='
SELECT tgname AS trigger, pg_get_triggerdef(oid) AS definicion
FROM   pg_trigger
WHERE  tgrelid = 'prestamo'::regclass AND NOT tgisinternal
ORDER BY tgname;
