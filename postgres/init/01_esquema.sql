-- =====================================================================
-- 01_esquema.sql  ·  Esquema del proyecto Biblioteca (biblioteca-v2)
-- 750006C Bases de Datos · Universidad del Valle · Hito 2, revisado en el Hito 3 (S20)
-- Grupo 9 · Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Hito 3: el esquema ya estaba en FNBC (S19, Parte B). Se agregaron dos
-- reglas de integridad (marcadas con "Hito 3" abajo): el perfil de
-- lector y bibliotecario amarrado con una FK compuesta, y nombres de
-- categoría y autor únicos sin distinguir mayúsculas. Una base existente
-- se migra con postgres/scripts/hito3/normalizacion.sql.
--
-- Script de arranque: Docker lo ejecuta solo, UNA vez, cuando la carpeta
-- postgres/data/ está vacía (se monta en /docker-entrypoint-initdb.d).
--
-- También se puede correr a mano cuantas veces se quiera, porque borra y
-- recrea el esquema "biblioteca":
--   docker compose exec postgres psql -U curso -d curso \
--     -f /docker-entrypoint-initdb.d/01_esquema.sql
-- o pegándolo en el Query Tool de pgAdmin. Por eso NO usa meta-comandos
-- de psql (\set, \if, \dt...): pgAdmin no los entiende.
-- =====================================================================

-- En PostgreSQL el DDL es transaccional: si algo falla, no queda nada a medias.
BEGIN;

-- pgcrypto trae crypt() y gen_salt('bf') (bcrypt) para guardar contraseñas
-- con hash desde la carga de lectores. Se crea en "public" y ANTES del DROP,
-- para que el DROP SCHEMA ... CASCADE no se la lleve.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca, public;

-- ---------------------------------------------------------------------
-- 1. Usuarios y perfiles (opción 2 de S11: tabla general + subtipos)
--    "usuario" guarda lo común a los 4 perfiles y el login. Solo tienen
--    tabla propia los perfiles con datos propios o a los que apunta una FK:
--    lector (teléfono; lo referencia prestamo) y bibliotecario (registra
--    el préstamo). Administrador y auditor viven solo en usuario.
-- ---------------------------------------------------------------------

CREATE TABLE usuario (
    id_usuario       integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento        varchar(15)  NOT NULL UNIQUE                 -- clave candidata
                     CONSTRAINT ck_usuario_documento CHECK (documento ~ '^[0-9]{6,15}$'),
    nombres          varchar(80)  NOT NULL
                     CONSTRAINT ck_usuario_nombres   CHECK (nombres <> ''),
    apellidos        varchar(80)  NOT NULL
                     CONSTRAINT ck_usuario_apellidos CHECK (apellidos <> ''),
    correo           varchar(120) NOT NULL UNIQUE                 -- clave candidata y login
                     CONSTRAINT ck_usuario_correo_formato    CHECK (correo ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$')
                     CONSTRAINT ck_usuario_correo_minusculas CHECK (correo = lower(correo)),
    -- Nunca texto plano: solo se acepta algo con forma de hash bcrypt ($2a$/$2b$, 60 caracteres)
    contrasena_hash  varchar(60)  NOT NULL
                     CONSTRAINT ck_usuario_hash_bcrypt CHECK (contrasena_hash ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'),
    perfil           varchar(13)  NOT NULL
                     CONSTRAINT ck_usuario_perfil CHECK (perfil IN ('lector', 'bibliotecario', 'administrador', 'auditor')),
    debe_cambiar_contrasena  boolean     NOT NULL DEFAULT true,   -- la clave inicial se cambia en el primer login
    activo                   boolean     NOT NULL DEFAULT true,   -- baja = inactivar, no borrar (conserva historial)
    fecha_registro           timestamptz NOT NULL DEFAULT now(),
    -- Hito 3: destino de las FK compuestas de lector y bibliotecario
    CONSTRAINT usuario_id_perfil_key UNIQUE (id_usuario, perfil)
);

-- Subtipo: la PK es a la vez FK hacia usuario (relación 1:1 de especialización).
-- Hito 3: "perfil" es una copia CONTROLADA de usuario.perfil. Siempre vale
-- 'lector' (CHECK), y la FK compuesta (id_usuario, perfil) obliga a que el
-- usuario apuntado tenga ese mismo perfil. Así es imposible que alguien esté
-- en lector sin ser lector, o que se le cambie el perfil mientras siga aquí.
CREATE TABLE lector (
    id_usuario  integer      PRIMARY KEY,
    telefono    varchar(15)  NOT NULL
                CONSTRAINT ck_lector_telefono CHECK (telefono ~ '^[0-9]{7,15}$'),
    perfil      varchar(13)  NOT NULL DEFAULT 'lector'
                CONSTRAINT ck_lector_perfil CHECK (perfil = 'lector'),
    CONSTRAINT lector_usuario_perfil_fkey FOREIGN KEY (id_usuario, perfil)
        REFERENCES usuario (id_usuario, perfil) ON DELETE CASCADE
);

-- Subtipo sin atributos propios: existe para que prestamo apunte a un
-- bibliotecario y no a cualquier usuario. Hito 3: misma regla que lector.
CREATE TABLE bibliotecario (
    id_usuario  integer      PRIMARY KEY,
    perfil      varchar(13)  NOT NULL DEFAULT 'bibliotecario'
                CONSTRAINT ck_bibliotecario_perfil CHECK (perfil = 'bibliotecario'),
    CONSTRAINT bibliotecario_usuario_perfil_fkey FOREIGN KEY (id_usuario, perfil)
        REFERENCES usuario (id_usuario, perfil) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 2. Catálogo
-- ---------------------------------------------------------------------

CREATE TABLE categoria (
    id_categoria  integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        varchar(40)  NOT NULL UNIQUE
                  CONSTRAINT ck_categoria_nombre CHECK (nombre <> '')
);
-- Hito 3: "Novela" y "novela" serían la misma categoría; el UNIQUE de arriba
-- distingue mayúsculas, este índice no.
CREATE UNIQUE INDEX categoria_nombre_lower_key ON categoria (lower(nombre));

-- Simplificación documentada: dos autores distintos con el mismo nombre
-- no se pueden registrar (el nombre es la clave natural que trae el CSV).
CREATE TABLE autor (
    id_autor  integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    varchar(120)  NOT NULL UNIQUE
              CONSTRAINT ck_autor_nombre CHECK (nombre <> '')
);
-- Hito 3: el mismo autor no puede entrar dos veces con otras mayúsculas o espacios.
CREATE UNIQUE INDEX autor_nombre_lower_key ON autor (lower(trim(nombre)));

-- "ejemplares_disponibles" NO es columna: es un atributo derivado
-- (regla 4 de S11) que se calcula contando ejemplares sin préstamo abierto.
CREATE TABLE libro (
    isbn              varchar(13)   PRIMARY KEY
                      CONSTRAINT ck_libro_isbn   CHECK (isbn ~ '^[0-9]{13}$'),
    titulo            varchar(200)  NOT NULL
                      CONSTRAINT ck_libro_titulo CHECK (titulo <> ''),
    anio_publicacion  smallint      NOT NULL
                      CONSTRAINT ck_libro_anio   CHECK (anio_publicacion BETWEEN 1450 AND 2100),
    id_categoria      integer       NOT NULL REFERENCES categoria (id_categoria),  -- 1:N, participación total
    activo            boolean       NOT NULL DEFAULT true
);

-- N:M "escrito por": un libro puede tener varios autores y un autor varios libros.
-- "Todo libro tiene al menos un autor" NO se puede expresar con claves (trigger, M6).
CREATE TABLE libro_autor (
    isbn      varchar(13)  REFERENCES libro (isbn) ON DELETE CASCADE,
    id_autor  integer      REFERENCES autor (id_autor),
    PRIMARY KEY (isbn, id_autor)
);

-- Entidad débil de libro: la copia 1, 2, 3... solo tiene sentido dentro de su ISBN.
-- PK = PK de la fuerte + clave parcial (regla 5 de S11).
CREATE TABLE ejemplar (
    isbn          varchar(13)  REFERENCES libro (isbn) ON DELETE CASCADE,
    numero_copia  smallint
                  CONSTRAINT ck_ejemplar_numero CHECK (numero_copia > 0),
    estado        varchar(13)  NOT NULL DEFAULT 'activo'
                  CONSTRAINT ck_ejemplar_estado CHECK (estado IN ('activo', 'en_reparacion', 'de_baja')),
    PRIMARY KEY (isbn, numero_copia)
);

-- ---------------------------------------------------------------------
-- 3. Préstamos
--    Un mismo lector puede pedir la misma copia varias veces en el tiempo
--    (el "par que se repite" de S11), así que el préstamo lleva clave propia.
--    "En mora" NO se guarda: es derivado (fecha_devolucion IS NULL AND
--    fecha_vencimiento < current_date).
-- ---------------------------------------------------------------------

CREATE TABLE prestamo (
    id_prestamo        integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_lector          integer      NOT NULL REFERENCES lector (id_usuario),
    isbn               varchar(13)  NOT NULL,
    numero_copia       smallint     NOT NULL,
    id_bibliotecario   integer      NOT NULL REFERENCES bibliotecario (id_usuario),
    fecha_prestamo     date         NOT NULL DEFAULT current_date,
    fecha_vencimiento  date         NOT NULL,      -- por defecto, préstamo + 14 días (lo calcula el procedimiento del Hito 4)
    fecha_devolucion   date,                       -- NULL = préstamo abierto
    -- FK compuesta: la pareja (isbn, numero_copia) completa debe existir en ejemplar
    FOREIGN KEY (isbn, numero_copia) REFERENCES ejemplar (isbn, numero_copia),
    CONSTRAINT ck_prestamo_plazo      CHECK (fecha_vencimiento > fecha_prestamo),
    CONSTRAINT ck_prestamo_devolucion CHECK (fecha_devolucion >= fecha_prestamo)
);

-- Un ejemplar no puede estar prestado dos veces a la vez: índice único
-- PARCIAL, que solo mira los préstamos abiertos (los devueltos no cuentan).
CREATE UNIQUE INDEX ux_prestamo_ejemplar_abierto
    ON prestamo (isbn, numero_copia)
    WHERE fecha_devolucion IS NULL;

COMMIT;
