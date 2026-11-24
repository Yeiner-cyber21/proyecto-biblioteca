-- =====================================================================
-- S22-grupo.sql  ·  Laboratorio S22, Parte A: reservas de salas de estudio
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: correr antes S22-reservas.sql (crea el esquema "reservas"
-- desde cero). Uso, en PowerShell desde la carpeta del proyecto:
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/taller-S22/S22-reservas.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/taller-S22/S22-grupo.sql
--
-- Las baterías se corren EN ORDEN y sin deshacer: A4 y A5 usan la reserva
-- que crea la prueba 7 de A3 (Diego, sala B, miércoles 8:00 a 10:00).
-- Las definiciones corren con ON_ERROR_STOP on (si algo falla, el script
-- se detiene); las baterías, con ON_ERROR_STOP off, porque tienen
-- sentencias que DEBEN fallar y su ERROR es la evidencia.
-- Cada prueba se anuncia con ">>" y el resultado esperado.
-- Respuestas a las preguntas: docs/hito4/S22-taller-procedimientos-triggers.md
-- =====================================================================

SET search_path TO reservas;
\set ON_ERROR_STOP on
\pset pager off

-- =====================================================================
-- A1. Restricciones y acciones referenciales
-- =====================================================================

-- (a) Regla 1 (máximo 3 horas, el mismo día, entre las 7:00 y las 21:00)
--     y asistentes positivos. Son reglas sobre UNA fila: caben en un CHECK.
ALTER TABLE reserva
    ADD CONSTRAINT reserva_orden      CHECK (fin > inicio),
    ADD CONSTRAINT reserva_duracion   CHECK (fin - inicio <= interval '3 hours'),
    ADD CONSTRAINT reserva_horario    CHECK (inicio::date = fin::date
                                             AND inicio::time >= time '07:00'
                                             AND fin::time    <= time '21:00'),
    ADD CONSTRAINT reserva_asistentes CHECK (asistentes > 0);

-- (b) Acciones ON DELETE de las tres FK (justificación en el documento):
--   sala_recurso -> sala      CASCADE : los recursos no existen sin su sala
--                                       (atributo multivaluado, S21 3.2).
--   reserva -> sala           RESTRICT: las reservas son historia; una sala
--                                       se desactiva (activa = false), no se borra.
--   reserva -> estudiante     RESTRICT: igual; borrar al estudiante borraría
--                                       su historia y sus inasistencias.
ALTER TABLE sala_recurso
    DROP CONSTRAINT sala_recurso_id_sala_fkey,
    ADD  CONSTRAINT sala_recurso_id_sala_fkey
         FOREIGN KEY (id_sala) REFERENCES sala ON DELETE CASCADE;

ALTER TABLE reserva
    DROP CONSTRAINT reserva_id_sala_fkey,
    ADD  CONSTRAINT reserva_id_sala_fkey
         FOREIGN KEY (id_sala) REFERENCES sala ON DELETE RESTRICT,
    DROP CONSTRAINT reserva_codigo_fkey,
    ADD  CONSTRAINT reserva_codigo_fkey
         FOREIGN KEY (codigo) REFERENCES estudiante ON DELETE RESTRICT;

-- (c) Batería de A1
\set ON_ERROR_STOP off
\echo
\echo '=================== Batería A1 ==================='
\echo '>> A1.1 debe fallar: reserva_orden'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '09:00', 2);
\echo '>> A1.2 debe fallar: reserva_duracion'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '08:00', dia(4) + time '12:00', 2);
\echo '>> A1.3 debe fallar: reserva_horario'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '20:00', dia(4) + time '22:00', 2);
\echo '>> A1.4 debe fallar: reserva_asistentes'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '11:00', 0);

\echo '>> A1.5 borrar la sala D (sin reservas): sus recursos se van con ella (CASCADE), esperado 0. Se deshace con ROLLBACK'
BEGIN;
DELETE FROM sala WHERE id_sala = 4;
SELECT count(*) AS recursos_sala_4 FROM sala_recurso WHERE id_sala = 4;
ROLLBACK;
\echo '>> A1.6 debe fallar: la sala A tiene reservas (RESTRICT)'
DELETE FROM sala WHERE id_sala = 1;

\echo '>> A1.7 pasa todas las restricciones (INSERT 0 1), aunque viola las reglas 2 y 3. Se deshace con ROLLBACK'
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(1) + time '09:00', dia(1) + time '10:00', 9);
ROLLBACK;
\set ON_ERROR_STOP on

-- (d) Ese INSERT viola la regla 2 (9 personas en una sala de 4) y la
--     regla 3 (se cruza con la reserva de Ana de 8:00 a 10:00). Un CHECK
--     solo ve la fila que se escribe: no puede leer la capacidad en "sala"
--     ni las otras filas de "reserva" (S21, sección 3.4).

-- =====================================================================
-- A2. Funciones en SQL: la regla escrita una sola vez
-- =====================================================================

-- Regla 4 (apoyo): horas reservadas por el estudiante en la semana del día
-- dado (de lunes a domingo), sin contar las canceladas, con un decimal.
CREATE OR REPLACE FUNCTION horas_semana(p_codigo varchar, p_dia date) RETURNS numeric
LANGUAGE sql STABLE
AS $$
    SELECT round(coalesce(sum(extract(epoch FROM fin - inicio)) / 3600, 0), 1)
    FROM   reserva
    WHERE  codigo = p_codigo
      AND  estado <> 'cancelada'
      AND  inicio >= date_trunc('week', p_dia::timestamp)
      AND  inicio <  date_trunc('week', p_dia::timestamp) + interval '7 days';
$$;

-- Regla 3 (apoyo): la sala no tiene otra reserva ACTIVA que se cruce con
-- [p_inicio, p_fin). Dos intervalos [a, b) y [c, d) se cruzan si a < d AND c < b.
-- p_excluir deja por fuera una reserva (la que se está modificando, A4).
CREATE OR REPLACE FUNCTION sala_libre(p_sala    integer,
                                      p_inicio  timestamp,
                                      p_fin     timestamp,
                                      p_excluir integer DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM   reserva
        WHERE  id_sala = p_sala
          AND  estado  = 'activa'
          AND  inicio  < p_fin
          AND  p_inicio < fin
          AND  id IS DISTINCT FROM p_excluir   -- con p_excluir NULL no excluye nada
    );
$$;

\echo
\echo '=================== Batería A2 ==================='
\echo '>> próxima: Ana 5.0, Bruno 2.0, Carla 3.0, Diego 2.0, Elena 0.0, Felipe 0.0'
\echo '>> pasada:  Bruno 2.0, Carla 2.0, Felipe 2.0, los demás 0.0'
SELECT codigo, horas_semana(codigo, dia(1))   AS proxima,
               horas_semana(codigo, dia(-13)) AS pasada
FROM   estudiante ORDER BY codigo;

\echo '>> esperado: a = f, b = t, c = t, d = t'
SELECT sala_libre(1, dia(1) + time '09:00', dia(1) + time '11:00')    AS a,   -- f: se cruza con las de Ana y Bruno
       sala_libre(1, dia(1) + time '12:00', dia(1) + time '14:00')    AS b,   -- t: empieza cuando termina la de Bruno
       sala_libre(2, dia(3) + time '08:00', dia(3) + time '10:00')    AS c,   -- t: la que había está cancelada
       sala_libre(1, dia(1) + time '08:00', dia(1) + time '10:00', 1) AS d;   -- t: la única que choca es la 1, excluida

-- =====================================================================
-- A3. Procedimientos: los casos de uso "reservar" y "cancelar"
-- =====================================================================

-- Caso de uso "reservar una sala". Verifica, en este orden: que el
-- estudiante exista, regla 5 (sanción), que la sala exista, regla 2
-- (mantenimiento y capacidad), regla 3 (sala libre) y regla 4 (6 horas
-- por semana). La regla 1 la ponen los CHECK de A1 al insertar.
CREATE OR REPLACE PROCEDURE reservar(p_codigo     varchar,
                                     p_sala       integer,
                                     p_inicio     timestamp,
                                     p_fin        timestamp,
                                     p_asistentes integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_nombre     varchar;
    v_sancion    date;
    v_sala       varchar;
    v_activa     boolean;
    v_capacidad  integer;
    v_llevadas   numeric;
    v_nuevas     numeric;
    v_id         integer;
BEGIN
    -- el estudiante existe
    SELECT nombre, sancionado_hasta INTO v_nombre, v_sancion
    FROM   estudiante WHERE codigo = p_codigo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el estudiante con código %', p_codigo;
    END IF;

    -- regla 5: un estudiante sancionado no puede reservar
    IF v_sancion >= CURRENT_DATE THEN
        RAISE EXCEPTION 'Regla 5: % (%) está sancionado/a hasta el %; no puede reservar',
                        v_nombre, p_codigo, to_char(v_sancion, 'DD/MM/YYYY');
    END IF;

    -- la sala existe
    SELECT nombre, activa, capacidad INTO v_sala, v_activa, v_capacidad
    FROM   sala WHERE id_sala = p_sala;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la sala %', p_sala;
    END IF;

    -- regla 2: sala en mantenimiento y capacidad
    IF NOT v_activa THEN
        RAISE EXCEPTION 'Regla 2: la % está en mantenimiento; no se puede reservar', v_sala;
    END IF;
    IF p_asistentes > v_capacidad THEN
        RAISE EXCEPTION 'Regla 2: la % tiene capacidad para % personas, no para %',
                        v_sala, v_capacidad, p_asistentes;
    END IF;

    -- regla 3: la sala no tiene otra reserva activa en ese horario
    IF NOT sala_libre(p_sala, p_inicio, p_fin) THEN
        RAISE EXCEPTION 'Regla 3: la % ya tiene una reserva activa que se cruza con % a %',
                        v_sala, to_char(p_inicio, 'DD/MM HH24:MI'), to_char(p_fin, 'HH24:MI');
    END IF;

    -- regla 4: máximo 6 horas por semana (las canceladas no cuentan)
    v_llevadas := horas_semana(p_codigo, p_inicio::date);
    v_nuevas   := round(extract(epoch FROM p_fin - p_inicio) / 3600, 1);
    IF v_llevadas + v_nuevas > 6 THEN
        RAISE EXCEPTION 'Regla 4: % (%) lleva % horas esa semana; con % más pasaría el máximo de 6',
                        v_nombre, p_codigo, v_llevadas, v_nuevas;
    END IF;

    INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
    VALUES (p_sala, p_codigo, p_inicio, p_fin, p_asistentes)
    RETURNING id INTO v_id;

    RAISE NOTICE 'Reserva % creada: %, %, % a %, % asistentes',
                 v_id, v_sala, v_nombre, to_char(p_inicio, 'DD/MM HH24:MI'),
                 to_char(p_fin, 'HH24:MI'), p_asistentes;
END;
$$;

-- Regla 6: una reserva se cancela solo si está activa y todavía no ha empezado.
CREATE OR REPLACE PROCEDURE cancelar(p_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado  varchar;
    v_inicio  timestamp;
BEGIN
    SELECT estado, inicio INTO v_estado, v_inicio
    FROM   reserva WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la reserva %', p_id;
    END IF;
    IF v_estado <> 'activa' THEN
        RAISE EXCEPTION 'Regla 6: la reserva % no está activa (estado: %); no se puede cancelar',
                        p_id, v_estado;
    END IF;
    IF v_inicio <= now() THEN
        RAISE EXCEPTION 'Regla 6: la reserva % ya empezó (%); no se puede cancelar',
                        p_id, to_char(v_inicio, 'DD/MM HH24:MI');
    END IF;

    UPDATE reserva SET estado = 'cancelada' WHERE id = p_id;
    RAISE NOTICE 'Reserva % cancelada', p_id;
END;
$$;

\set ON_ERROR_STOP off
\echo
\echo '=================== Batería A3 ==================='
\echo '>> A3.1 error: Elena está sancionada'
CALL reservar('2610005', 1, dia(4) + time '08:00', dia(4) + time '10:00', 2);
\echo '>> A3.2 error: sala en mantenimiento'
CALL reservar('2610006', 4, dia(4) + time '08:00', dia(4) + time '10:00', 2);
\echo '>> A3.3 error: capacidad 4, no 5'
CALL reservar('2610006', 1, dia(4) + time '08:00', dia(4) + time '10:00', 5);
\echo '>> A3.4 error: sala ocupada'
CALL reservar('2610006', 1, dia(1) + time '09:00', dia(1) + time '11:00', 2);
\echo '>> A3.5 error: Ana superaría las 6 horas (lleva 5.0)'
CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '10:00', 3);
\echo '>> A3.6 reserva creada'
CALL reservar('2610006', 1, dia(1) + time '12:00', dia(1) + time '14:00', 3);
\echo '>> A3.7 reserva creada (la anterior estaba cancelada)'
CALL reservar('2610004', 2, dia(3) + time '08:00', dia(3) + time '10:00', 4);
\echo '>> A3.8 reserva creada (Ana llega justo a 6)'
CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);
\echo '>> A3.9 error: el estudiante no existe'
CALL reservar('2610099', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);
\echo '>> A3.10 error: la reserva 7 no está activa'
CALL cancelar(7);
\echo '>> A3.11 cancela la reserva de Bruno'
CALL cancelar(2);
\set ON_ERROR_STOP on

\echo '>> Agenda después de A3: 3 reservas nuevas y la 2 cancelada'
SELECT * FROM agenda;
\echo '>> Ana quedó justo en 6.0 horas'
SELECT horas_semana('2610001', dia(1)) AS horas_ana;

-- =====================================================================
-- A4. Trigger BEFORE: las reglas 2 y 3 valen también para un INSERT o
--     UPDATE directo, sin pasar por el procedimiento
-- =====================================================================

\set ON_ERROR_STOP off
\echo
\echo '=================== Batería A4 ==================='
\echo '>> A4 (a) ANTES del trigger: pasa (INSERT 0 1) con 12 personas en una sala de 10 y cruzada con la de Ana. Se deshace'
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);
ROLLBACK;
\set ON_ERROR_STOP on

-- (b) Reglas 2 y 3 sobre toda reserva activa, venga de donde venga.
--     Si NEW.estado no es 'activa' (cancelar, cerrar, marcar inasistencia),
--     se deja pasar sin validar. sala_libre excluye la propia reserva (NEW.id):
--     al modificar una reserva, la versión vieja de esa misma fila no
--     cuenta como "otra reserva que se cruza".
CREATE OR REPLACE FUNCTION validar_reserva() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_sala       varchar;
    v_activa     boolean;
    v_capacidad  integer;
BEGIN
    IF NEW.estado <> 'activa' THEN
        RETURN NEW;
    END IF;

    SELECT nombre, activa, capacidad INTO v_sala, v_activa, v_capacidad
    FROM   sala WHERE id_sala = NEW.id_sala;
    -- si la sala no existe, la FK rechaza la fila después de este trigger

    -- regla 2
    IF NOT v_activa THEN
        RAISE EXCEPTION 'Regla 2: la % está en mantenimiento; no se puede reservar', v_sala;
    END IF;
    IF NEW.asistentes > v_capacidad THEN
        RAISE EXCEPTION 'Regla 2: la % tiene capacidad para % personas, no para %',
                        v_sala, v_capacidad, NEW.asistentes;
    END IF;

    -- regla 3
    IF NOT sala_libre(NEW.id_sala, NEW.inicio, NEW.fin, NEW.id) THEN
        RAISE EXCEPTION 'Regla 3: la % ya tiene una reserva activa que se cruza con % a %',
                        v_sala, to_char(NEW.inicio, 'DD/MM HH24:MI'), to_char(NEW.fin, 'HH24:MI');
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserva_validar ON reserva;
CREATE TRIGGER reserva_validar
BEFORE INSERT OR UPDATE ON reserva
FOR EACH ROW
EXECUTE FUNCTION validar_reserva();

-- (c) Batería de A4
\set ON_ERROR_STOP off
\echo '>> A4.1 debe fallar: capacidad'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);
\echo '>> A4.2 debe fallar: sala ocupada'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 6);
\echo '>> A4.3 debe fallar: se cruza con la de Diego de las 8:00'
UPDATE reserva SET inicio = dia(3) + time '09:00' WHERE id = 6;
\echo '>> A4.4 debe pasar (UPDATE 1): la reserva no choca consigo misma'
UPDATE reserva SET asistentes = 5 WHERE id = 6;
\echo '>> A4.5 debe fallar: reactivar la 5 la cruza con la de Diego de las 8:00'
UPDATE reserva SET estado = 'activa' WHERE id = 5;
\set ON_ERROR_STOP on

-- (d) Las reglas 4 y 5 se quedan en el procedimiento (argumento en el documento).

-- =====================================================================
-- A5. Trigger AFTER con WHEN: quien no se presenta queda sancionado 7 días
-- =====================================================================

-- Se usa GREATEST para no ACORTAR una sanción más larga que ya exista
-- (Elena tiene 30 días: una inasistencia no debe bajarla a 7).
-- GREATEST ignora el NULL de quien no tenía sanción.
CREATE OR REPLACE FUNCTION sancionar_inasistencia() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE estudiante
    SET    sancionado_hasta = GREATEST(sancionado_hasta, CURRENT_DATE + 7)
    WHERE  codigo = NEW.codigo;

    RAISE NOTICE 'Regla 5: estudiante % sancionado/a por no asistir a la reserva %',
                 NEW.codigo, NEW.id;
    RETURN NULL;   -- en un trigger AFTER el valor de retorno se ignora
END;
$$;

DROP TRIGGER IF EXISTS reserva_sancionar ON reserva;
CREATE TRIGGER reserva_sancionar
AFTER UPDATE OF estado ON reserva
FOR EACH ROW
WHEN (NEW.estado = 'no_asistio' AND OLD.estado <> 'no_asistio')
EXECUTE FUNCTION sancionar_inasistencia();

\set ON_ERROR_STOP off
\echo
\echo '=================== Batería A5 ==================='
\echo '>> A5.1 Felipe no se presentó (se corrige el estado): NOTICE de sanción'
UPDATE reserva SET estado = 'no_asistio' WHERE id = 7;
\echo '>> A5.2 esperado: Elena 30, Felipe 7'
SELECT codigo, nombre, sancionado_hasta - CURRENT_DATE AS dias
FROM   estudiante WHERE sancionado_hasta IS NOT NULL ORDER BY codigo;
\echo '>> A5.3 debe fallar: Felipe sancionado'
CALL reservar('2610006', 3, dia(5) + time '08:00', dia(5) + time '10:00', 2);
\echo '>> A5.4 Bruno ya era no_asistio: UPDATE 1 y sin NOTICE de sanción'
UPDATE reserva SET asistentes = 2 WHERE id = 8;
\echo '>> A5.5 esperado: siguen solo Elena 30 y Felipe 7 (Bruno no aparece)'
SELECT codigo, nombre, sancionado_hasta - CURRENT_DATE AS dias
FROM   estudiante WHERE sancionado_hasta IS NOT NULL ORDER BY codigo;
\set ON_ERROR_STOP on

-- =====================================================================
-- A6. Ciclo o conjunto: cerrar las reservas vencidas
-- =====================================================================

-- La versión del compañero (un UPDATE por cada fila), como referencia; no se crea:
--   CREATE PROCEDURE cerrar_vencidas_ciclo() LANGUAGE plpgsql AS $$
--   DECLARE r record;
--   BEGIN
--       FOR r IN SELECT id FROM reserva WHERE estado = 'activa' AND fin < now() LOOP
--           UPDATE reserva SET estado = 'cumplida' WHERE id = r.id;
--           RAISE NOTICE 'Reserva % cerrada', r.id;
--       END LOOP;
--   END; $$;

-- (a) La misma tarea en UNA sola sentencia sobre el conjunto.
CREATE OR REPLACE PROCEDURE cerrar_vencidas()
LANGUAGE sql
AS $$
    UPDATE reserva
    SET    estado = 'cumplida'
    WHERE  estado = 'activa'
      AND  fin < now();
$$;

\echo
\echo '=================== Batería A6 ==================='
\echo '>> Antes: la reserva 9 (Carla, semana pasada) sigue activa'
SELECT id, estado, fin FROM reserva WHERE estado = 'activa' AND fin < now();
CALL cerrar_vencidas();
\echo '>> Después: 0 filas vencidas activas, y la 9 quedó cumplida'
SELECT id, estado, fin FROM reserva WHERE estado = 'activa' AND fin < now();
SELECT id, estado FROM reserva WHERE id = 9;

-- =====================================================================
-- Reto (opcional): la regla 3 como restricción EXCLUDE
-- =====================================================================

-- btree_gist permite usar "=" sobre un entero dentro de un índice GiST.
-- Se instala en public para que no dependa del esquema "reservas".
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

-- Dos reservas ACTIVAS de la misma sala no pueden tener intervalos que se
-- crucen (&&). tsrange(inicio, fin) es [inicio, fin): terminar a las 10:00
-- y empezar a las 10:00 no es cruce.
ALTER TABLE reserva ADD CONSTRAINT reserva_sin_cruce
    EXCLUDE USING gist (id_sala WITH =, tsrange(inicio, fin) WITH &&)
    WHERE (estado = 'activa');

\echo
\echo '=================== Reto: EXCLUDE ==================='
\echo '>> Se desactiva el trigger para ver que la restricción sola impide el cruce'
ALTER TABLE reserva DISABLE TRIGGER reserva_validar;

\set ON_ERROR_STOP off
\echo '>> R.1 debe fallar: se cruza con la de Ana (lunes 8:00 a 10:00, sala A): reserva_sin_cruce'
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610002', dia(1) + time '09:00', dia(1) + time '10:00', 2);
\echo '>> R.2 debe pasar (INSERT 0 1): lunes 14:00 a 15:00 en la sala A no se cruza. Se deshace con ROLLBACK'
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610002', dia(1) + time '14:00', dia(1) + time '15:00', 2);
ROLLBACK;
\set ON_ERROR_STOP on

\echo '>> Se reactiva el trigger (estado final: trigger y restricción activos)'
ALTER TABLE reserva ENABLE TRIGGER reserva_validar;
SELECT tgname, CASE tgenabled WHEN 'O' THEN 'activo' ELSE 'desactivado' END AS estado
FROM   pg_trigger
WHERE  tgrelid = 'reserva'::regclass AND NOT tgisinternal
ORDER BY tgname;

-- Con esta restricción, la regla 3 ya la garantiza el DBMS de forma
-- declarativa (S21, sección 8: lo que se puede declarar, se declara). En el
-- trigger quedaría solo la regla 2 (mantenimiento y capacidad), que mira
-- OTRA tabla (sala) y no cabe en un CHECK ni en un EXCLUDE.

\echo
\echo '=================== Estado final ==================='
SELECT * FROM agenda;
