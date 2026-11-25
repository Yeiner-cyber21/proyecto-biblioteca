-- =====================================================================
-- 03_programacion.sql  ·  Hito 4: funciones, procedimientos y trigger
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- La lógica de préstamos dentro de la base de datos (S21 y S22). Cada
-- objeto dice arriba qué regla del documento del proyecto implementa
-- (sección 3.1, alcance; sección 3.2, reglas de negocio).
--
-- Está en dos lugares, con el MISMO contenido:
--   postgres/init/03_programacion.sql          (una base nueva nace con esto,
--                                               después de 01_esquema y 02_carga)
--   postgres/scripts/hito4/programacion.sql    (para correrlo a mano)
-- En una base que ya existe (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito4/programacion.sql
--
-- Re-ejecutable: CREATE OR REPLACE y DROP TRIGGER IF EXISTS. Si se vuelve a
-- correr 01_esquema.sql (borra el esquema "biblioteca"), hay que correr este
-- archivo otra vez. Sin meta-comandos de psql, para que funcione en pgAdmin.
--
-- Decisiones del grupo:
--   - "En mora" y "ejemplares disponibles" se CALCULAN (Hito 3: no se
--     desnormalizó nada), así que no hay trigger de mantenimiento: la
--     disponibilidad y la mora siempre están al día.
--   - Las reglas se evalúan EN LA FECHA DEL PRÉSTAMO, no siempre "hoy": así
--     un préstamo que se registra con su fecha real (por ejemplo, los de
--     datos-prueba.sql) se valida con la situación del lector en ese momento.
--     Para un préstamo de hoy es exactamente la regla de la sección 3.2.
--   - Ningún trigger intenta "marcar la mora al vencer el plazo": un trigger
--     solo reacciona a INSERT/UPDATE/DELETE, y vencer un plazo no es un
--     evento de la base (S21, sección 6.5). La mora se calcula al consultar.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Funciones de apoyo: cada regla escrita UNA sola vez. Las usan el
--    procedimiento, el trigger y, en M7, la API.
-- ---------------------------------------------------------------------

-- Regla 3.2: "un lector tiene un máximo de 3 préstamos activos simultáneos".
-- Cuenta los préstamos que el lector tenía ABIERTOS en la fecha dada: ya se
-- habían hecho (fecha_prestamo <= p_fecha) y no se habían devuelto (sin
-- devolución, o devueltos después de p_fecha). Con p_fecha = hoy (el valor
-- por defecto) son, simplemente, sus préstamos sin devolver.
CREATE OR REPLACE FUNCTION biblioteca.prestamos_activos(p_lector integer,
                                                        p_fecha  date DEFAULT CURRENT_DATE)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*)
    FROM   biblioteca.prestamo
    WHERE  id_lector = p_lector
      AND  fecha_prestamo <= p_fecha
      AND  (fecha_devolucion IS NULL OR fecha_devolucion > p_fecha);
$$;

-- Regla 3.2: "un préstamo está en mora cuando la fecha esperada de devolución
-- ya pasó y el libro no ha sido devuelto". Cuenta los préstamos del lector
-- que estaban en mora en la fecha dada. Regla del grupo (Hito 2): "<" estricto,
-- así que un préstamo que vence HOY todavía no está en mora.
CREATE OR REPLACE FUNCTION biblioteca.prestamos_en_mora(p_lector integer,
                                                        p_fecha  date DEFAULT CURRENT_DATE)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*)
    FROM   biblioteca.prestamo
    WHERE  id_lector = p_lector
      AND  fecha_prestamo <= p_fecha
      AND  (fecha_devolucion IS NULL OR fecha_devolucion > p_fecha)
      AND  fecha_vencimiento < p_fecha;
$$;

-- Regla 3.2: "un lector con al menos un préstamo en mora no puede solicitar
-- nuevos préstamos". Verdadero si el lector tiene algún préstamo en mora.
CREATE OR REPLACE FUNCTION biblioteca.en_mora(p_lector integer,
                                              p_fecha  date DEFAULT CURRENT_DATE)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT biblioteca.prestamos_en_mora(p_lector, p_fecha) > 0;
$$;

-- Sección 3.1 (consulta del catálogo y su disponibilidad) y sección 4 (el
-- lector consulta la disponibilidad): ejemplares que se pueden prestar hoy.
-- Son las copias en estado 'activo' de un libro activo y sin préstamo abierto.
-- Es un dato derivado: se calcula, no se guarda (Hito 3, sección 5).
CREATE OR REPLACE FUNCTION biblioteca.ejemplares_disponibles(p_isbn varchar)
RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*)
    FROM   biblioteca.ejemplar e
    JOIN   biblioteca.libro    l ON l.isbn = e.isbn
    WHERE  e.isbn = p_isbn
      AND  l.activo
      AND  e.estado = 'activo'
      AND  NOT EXISTS (SELECT 1
                       FROM   biblioteca.prestamo p
                       WHERE  p.isbn = e.isbn
                         AND  p.numero_copia = e.numero_copia
                         AND  p.fecha_devolucion IS NULL);
$$;

-- ---------------------------------------------------------------------
-- 2. Procedimiento: registrar un préstamo (caso de uso completo)
--    Sección 3.1, punto 4: "registrar el préstamo de un libro a un lector,
--    respetando las reglas de negocio de la sección 3.2". Sección 3.2: lo
--    registra el BIBLIOTECARIO, con el plazo estándar de 14 días.
--    Recibe documentos e ISBN (lo que se tiene en el mostrador) y él mismo
--    escoge una copia libre. Si algo falla, no queda nada a medias (S21, 5.3).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE biblioteca.registrar_prestamo(p_doc_lector        varchar,
                                                          p_isbn              varchar,
                                                          p_doc_bibliotecario varchar)
LANGUAGE plpgsql
AS $$
DECLARE
    v_lector         integer;
    v_lector_nombre  text;
    v_lector_activo  boolean;
    v_biblio         integer;
    v_biblio_nombre  text;
    v_biblio_activo  boolean;
    v_titulo         varchar;
    v_libro_activo   boolean;
    v_cuantos        bigint;
    v_copia          smallint;
    v_vence          date := CURRENT_DATE + 14;     -- regla 3.2: plazo estándar
    v_id             integer;
BEGIN
    -- El lector existe (es un usuario con perfil lector) y está activo
    SELECT u.id_usuario, u.nombres || ' ' || u.apellidos, u.activo
    INTO   v_lector, v_lector_nombre, v_lector_activo
    FROM   biblioteca.usuario u
    JOIN   biblioteca.lector  l ON l.id_usuario = u.id_usuario
    WHERE  u.documento = p_doc_lector;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe un lector con documento %', p_doc_lector;
    END IF;
    IF NOT v_lector_activo THEN
        RAISE EXCEPTION 'El lector % (%) está inactivo: no puede recibir préstamos',
                        v_lector_nombre, p_doc_lector;
    END IF;

    -- Quien registra es un bibliotecario activo (regla 3.2)
    SELECT u.id_usuario, u.nombres || ' ' || u.apellidos, u.activo
    INTO   v_biblio, v_biblio_nombre, v_biblio_activo
    FROM   biblioteca.usuario       u
    JOIN   biblioteca.bibliotecario b ON b.id_usuario = u.id_usuario
    WHERE  u.documento = p_doc_bibliotecario;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe un bibliotecario con documento %: solo un bibliotecario registra préstamos',
                        p_doc_bibliotecario;
    END IF;
    IF NOT v_biblio_activo THEN
        RAISE EXCEPTION 'La cuenta de bibliotecario % (%) está desactivada',
                        v_biblio_nombre, p_doc_bibliotecario;
    END IF;

    -- El libro existe y está activo
    SELECT titulo, activo INTO v_titulo, v_libro_activo
    FROM   biblioteca.libro
    WHERE  isbn = p_isbn;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe un libro con ISBN %', p_isbn;
    END IF;
    IF NOT v_libro_activo THEN
        RAISE EXCEPTION 'El libro "%" (%) está dado de baja: no se presta', v_titulo, p_isbn;
    END IF;

    -- Reglas 3.2, con las MISMAS funciones que usa el trigger. El trigger las
    -- vuelve a revisar en el INSERT; aquí se revisan antes para dar el error
    -- sin buscar ejemplar (S21, sección 6.2).
    v_cuantos := biblioteca.prestamos_en_mora(v_lector);
    IF v_cuantos > 0 THEN
        RAISE EXCEPTION 'Regla de mora (3.2): % (%) tiene % préstamo(s) en mora; no puede pedir libros hasta ponerse al día',
                        v_lector_nombre, p_doc_lector, v_cuantos;
    END IF;
    v_cuantos := biblioteca.prestamos_activos(v_lector);
    IF v_cuantos >= 3 THEN
        RAISE EXCEPTION 'Regla de máximo (3.2): % (%) ya tiene % préstamos activos; el máximo es 3',
                        v_lector_nombre, p_doc_lector, v_cuantos;
    END IF;

    -- Una copia activa del libro, sin préstamo abierto (la de número más bajo)
    SELECT e.numero_copia INTO v_copia
    FROM   biblioteca.ejemplar e
    WHERE  e.isbn = p_isbn
      AND  e.estado = 'activo'
      AND  NOT EXISTS (SELECT 1
                       FROM   biblioteca.prestamo p
                       WHERE  p.isbn = e.isbn
                         AND  p.numero_copia = e.numero_copia
                         AND  p.fecha_devolucion IS NULL)
    ORDER BY e.numero_copia
    LIMIT 1;
    IF v_copia IS NULL THEN
        RAISE EXCEPTION 'No hay ejemplares disponibles de "%" (%): todas las copias están prestadas o fuera de servicio',
                        v_titulo, p_isbn;
    END IF;

    INSERT INTO biblioteca.prestamo (id_lector, isbn, numero_copia, id_bibliotecario,
                                     fecha_prestamo, fecha_vencimiento)
    VALUES (v_lector, p_isbn, v_copia, v_biblio, CURRENT_DATE, v_vence)
    RETURNING id_prestamo INTO v_id;

    RAISE NOTICE 'Préstamo % registrado: "%" (copia %) para % (%); lo registró %; devolver a más tardar el %',
                 v_id, v_titulo, v_copia, v_lector_nombre, p_doc_lector,
                 v_biblio_nombre, to_char(v_vence, 'DD/MM/YYYY');
END;
$$;

-- ---------------------------------------------------------------------
-- 3. Procedimiento: registrar una devolución con sus efectos
--    Sección 3.1, punto 5: "registrar la devolución de un libro, actualizando
--    disponibilidad y, si aplica, el estado de mora del préstamo". Es el
--    ejemplo de la sección 8 ("devolución completa con sus efectos").
--    La disponibilidad y la mora no se guardan (se calculan), así que basta
--    con registrar la fecha; el procedimiento informa los efectos: si llegó
--    tarde, cuántas copias quedan libres y si el lector queda al día.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE biblioteca.registrar_devolucion(p_id_prestamo integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_lector     integer;
    v_nombre     text;
    v_documento  varchar;
    v_isbn       varchar;
    v_titulo     varchar;
    v_vence      date;
    v_devuelto   date;
    v_retraso    integer;
    v_mora       bigint;
BEGIN
    SELECT p.id_lector, u.nombres || ' ' || u.apellidos, u.documento,
           p.isbn, l.titulo, p.fecha_vencimiento, p.fecha_devolucion
    INTO   v_lector, v_nombre, v_documento, v_isbn, v_titulo, v_vence, v_devuelto
    FROM   biblioteca.prestamo p
    JOIN   biblioteca.usuario  u ON u.id_usuario = p.id_lector
    JOIN   biblioteca.libro    l ON l.isbn = p.isbn
    WHERE  p.id_prestamo = p_id_prestamo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el préstamo %', p_id_prestamo;
    END IF;
    IF v_devuelto IS NOT NULL THEN
        RAISE EXCEPTION 'El préstamo % ya fue devuelto el %',
                        p_id_prestamo, to_char(v_devuelto, 'DD/MM/YYYY');
    END IF;

    UPDATE biblioteca.prestamo
    SET    fecha_devolucion = CURRENT_DATE
    WHERE  id_prestamo = p_id_prestamo;

    -- Efecto 1: el estado de mora del préstamo
    v_retraso := CURRENT_DATE - v_vence;
    IF v_retraso > 0 THEN
        RAISE NOTICE 'Préstamo % devuelto: "%" por % (%), con % día(s) de retraso',
                     p_id_prestamo, v_titulo, v_nombre, v_documento, v_retraso;
    ELSE
        RAISE NOTICE 'Préstamo % devuelto a tiempo: "%" por % (%)',
                     p_id_prestamo, v_titulo, v_nombre, v_documento;
    END IF;

    -- Efecto 2: la disponibilidad del libro (calculada)
    RAISE NOTICE '"%" queda con % ejemplar(es) disponible(s)',
                 v_titulo, biblioteca.ejemplares_disponibles(v_isbn);

    -- Efecto 3: la situación del lector
    v_mora := biblioteca.prestamos_en_mora(v_lector);
    IF v_mora > 0 THEN
        RAISE NOTICE '% sigue en mora con % préstamo(s): todavía no puede pedir libros',
                     v_nombre, v_mora;
    ELSIF v_retraso > 0 THEN
        RAISE NOTICE '% queda al día: ya puede pedir libros otra vez', v_nombre;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. Trigger BEFORE INSERT: las reglas valen para TODOS, no solo para quien
--    usa el procedimiento (un INSERT desde la API, una carga, psql o pgAdmin).
--    Regla 3.2: no prestar a un lector en mora ni a uno con 3 préstamos
--    activos. Es el segundo ejemplo de la sección 8 ("impida un nuevo
--    préstamo si el lector ya está en mora"). Además, solo se prestan
--    ejemplares en estado 'activo' de libros activos, y si no se da la fecha
--    de vencimiento, se completa con el plazo estándar de 14 días.
--    Un préstamo que se registra ya devuelto es historia, no un préstamo
--    nuevo: se deja pasar. Se valida al INSERTAR, que es registrar un
--    préstamo; corregir uno existente con UPDATE es una tarea administrativa
--    y queda fuera, y el índice único parcial sigue impidiendo prestar dos
--    veces la misma copia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION biblioteca.validar_prestamo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_nombre        text;
    v_documento     varchar;
    v_estado        varchar;
    v_libro_activo  boolean;
    v_cuantos       bigint;
BEGIN
    IF NEW.fecha_devolucion IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- plazo estándar si no lo dieron (regla 3.2: 14 días)
    IF NEW.fecha_vencimiento IS NULL THEN
        NEW.fecha_vencimiento := NEW.fecha_prestamo + 14;
    END IF;

    SELECT u.nombres || ' ' || u.apellidos, u.documento INTO v_nombre, v_documento
    FROM   biblioteca.usuario u
    WHERE  u.id_usuario = NEW.id_lector;
    -- si el lector no existe, la FK rechaza la fila después de este trigger

    -- solo copias activas de libros activos
    SELECT e.estado, l.activo INTO v_estado, v_libro_activo
    FROM   biblioteca.ejemplar e
    JOIN   biblioteca.libro    l ON l.isbn = e.isbn
    WHERE  e.isbn = NEW.isbn
      AND  e.numero_copia = NEW.numero_copia;
    IF v_estado <> 'activo' THEN
        RAISE EXCEPTION 'Ejemplar no prestable: la copia % de % está en estado "%"',
                        NEW.numero_copia, NEW.isbn, v_estado;
    END IF;
    IF NOT v_libro_activo THEN
        RAISE EXCEPTION 'Ejemplar no prestable: el libro % está dado de baja', NEW.isbn;
    END IF;

    -- regla 3.2: mora, en la fecha del préstamo
    v_cuantos := biblioteca.prestamos_en_mora(NEW.id_lector, NEW.fecha_prestamo);
    IF v_cuantos > 0 THEN
        RAISE EXCEPTION 'Regla de mora (3.2): % (%) tiene % préstamo(s) en mora; no puede recibir préstamos nuevos',
                        v_nombre, v_documento, v_cuantos;
    END IF;

    -- regla 3.2: máximo 3 préstamos activos, en la fecha del préstamo
    v_cuantos := biblioteca.prestamos_activos(NEW.id_lector, NEW.fecha_prestamo);
    IF v_cuantos >= 3 THEN
        RAISE EXCEPTION 'Regla de máximo (3.2): % (%) ya tiene % préstamos activos; el máximo es 3',
                        v_nombre, v_documento, v_cuantos;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prestamo_validar ON biblioteca.prestamo;
CREATE TRIGGER prestamo_validar
BEFORE INSERT ON biblioteca.prestamo
FOR EACH ROW
EXECUTE FUNCTION biblioteca.validar_prestamo();

COMMIT;
