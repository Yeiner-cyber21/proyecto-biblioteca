-- =====================================================================
-- 02_carga.sql  ·  Infraestructura de la carga desde CSV (laboratorio S14)
--
-- Crea el esquema "carga", separado del esquema del negocio "biblioteca":
--   - rechazo_carga: la bitácora de filas rechazadas (persiste entre cargas)
--   - stg_*: las tablas de paso (staging), que cada carga vacía y vuelve a llenar
--
-- Va en postgres/init/, así que en una base nueva corre solo, después de
-- 01_esquema.sql (orden alfabético). En una base que ya existe se corre a mano:
--   docker compose exec postgres psql -U curso -d curso -f /docker-entrypoint-initdb.d/02_carga.sql
-- Es re-ejecutable, pero OJO: volver a correrlo borra la bitácora.
-- Sin meta-comandos de psql, para que también funcione en pgAdmin.
-- =====================================================================

BEGIN;

DROP SCHEMA IF EXISTS carga CASCADE;
CREATE SCHEMA carga;

-- ---------------------------------------------------------------------
-- Bitácora de rechazos: qué archivo, qué línea, qué decía y por qué no entró.
-- Con esto se puede corregir el CSV y volver a cargarlo.
-- ---------------------------------------------------------------------
CREATE TABLE carga.rechazo_carga (
    id         integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo    text         NOT NULL,
    linea      integer      NOT NULL,
    contenido  text         NOT NULL,
    motivo     text         NOT NULL,
    fecha      timestamptz  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Tablas de paso: TODO es text y NADA tiene restricciones, para que
-- ninguna línea del archivo se pierda antes de revisarla, por rara que sea.
-- ---------------------------------------------------------------------

-- Una fila por línea del archivo, sin partir. "n" numera las líneas en el
-- orden en que llegan, así que coincide con el número de línea del CSV.
CREATE TABLE carga.stg_linea (
    n      integer  GENERATED ALWAYS AS IDENTITY,
    linea  text
);

CREATE TABLE carga.stg_libro (
    linea_csv               integer,
    contenido               text,     -- la línea original, tal cual llegó
    num_campos              integer,
    isbn                    text,
    titulo                  text,
    autor                   text,
    categoria               text,
    anio_publicacion        text,
    ejemplares_disponibles  text,
    motivo                  text      -- NULL = la fila pasó la validación
);

CREATE TABLE carga.stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text
);

COMMIT;
