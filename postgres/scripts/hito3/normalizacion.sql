-- =====================================================================
-- normalizacion.sql  ·  Hito 3 (S20, Parte B): migración del esquema "biblioteca"
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- (No confundir con hito3/taller-S18/normalizacion.sql, que es el taller
-- del Taller Automotriz El Pistón.)
--
-- Qué hace: lleva una base que YA tiene datos (creada con el esquema del
-- Hito 2) al esquema del Hito 3, el mismo que hoy crea postgres/init/01_esquema.sql.
--
-- El esquema ya estaba en FNBC (S19, Parte B): no hay tablas que partir.
-- Se aplican las dos reglas de integridad que el S19 propuso para el S20:
--   1. El perfil, amarrado. lector y bibliotecario reciben una columna perfil
--      (siempre 'lector' o 'bibliotecario', con CHECK) y una FK compuesta
--      (id_usuario, perfil) -> usuario (id_usuario, perfil). Antes nada
--      impedía que usuario.perfil dijera una cosa y las tablas otra.
--   2. Nombres únicos sin distinguir mayúsculas: índices únicos sobre
--      lower(categoria.nombre) y lower(trim(autor.nombre)).
--
-- Sigue la receta del S19 (sección 4): evidencia -> BEGIN -> crear ->
-- verificar (conteos y EXCEPT) -> quitar lo viejo -> COMMIT.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/normalizacion.sql
--
-- Re-ejecutable: si la base ya está migrada (o se creó con el init nuevo),
-- quita las restricciones del Hito 3 y las vuelve a crear; el resultado es
-- el mismo. No borra ni cambia ningún dato.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO biblioteca;

-- ---------------------------------------------------------------------
-- 1. Evidencia, ANTES de migrar
--    Las restricciones nuevas solo se pueden crear si los datos ya las
--    cumplen. Si alguna de estas consultas devolviera filas, primero habría
--    que decidir qué dato es el correcto y corregirlo (como en el S18 y el S19).
-- ---------------------------------------------------------------------
\echo
\echo '== 1. Evidencia: perfil frente a lector y bibliotecario (esperado: 0 en las cuatro) =='
SELECT 'perfil lector sin fila en lector' AS contradiccion, count(*) AS filas
FROM   usuario u WHERE u.perfil = 'lector' AND NOT EXISTS (SELECT 1 FROM lector l WHERE l.id_usuario = u.id_usuario)
UNION ALL
SELECT 'fila en lector con otro perfil', count(*)
FROM   lector l JOIN usuario u ON u.id_usuario = l.id_usuario WHERE u.perfil <> 'lector'
UNION ALL
SELECT 'perfil bibliotecario sin fila en bibliotecario', count(*)
FROM   usuario u WHERE u.perfil = 'bibliotecario' AND NOT EXISTS (SELECT 1 FROM bibliotecario b WHERE b.id_usuario = u.id_usuario)
UNION ALL
SELECT 'fila en bibliotecario con otro perfil', count(*)
FROM   bibliotecario b JOIN usuario u ON u.id_usuario = b.id_usuario WHERE u.perfil <> 'bibliotecario';

\echo '== 1. Evidencia: categorías que solo cambian en mayúsculas (esperado: 0 filas) =='
SELECT lower(nombre) AS nombre, count(*) FROM categoria GROUP BY lower(nombre) HAVING count(*) > 1;

\echo '== 1. Evidencia: autores que solo cambian en mayúsculas o espacios (esperado: 0 filas) =='
SELECT lower(trim(nombre)) AS nombre, count(*) FROM autor GROUP BY lower(trim(nombre)) HAVING count(*) > 1;

-- ---------------------------------------------------------------------
-- 2. La migración, dentro de una transacción
-- ---------------------------------------------------------------------
\echo
\echo '== 2. Migración =='
BEGIN;

-- Fotos de "antes", para comparar al final (se borran solas al COMMIT)
CREATE TEMP TABLE antes_conteo ON COMMIT DROP AS
SELECT 'usuario' AS tabla, count(*) AS filas FROM usuario
UNION ALL SELECT 'lector',        count(*) FROM lector
UNION ALL SELECT 'bibliotecario', count(*) FROM bibliotecario
UNION ALL SELECT 'categoria',     count(*) FROM categoria
UNION ALL SELECT 'autor',         count(*) FROM autor;
CREATE TEMP TABLE antes_lector        ON COMMIT DROP AS SELECT id_usuario, telefono FROM lector;
CREATE TEMP TABLE antes_bibliotecario ON COMMIT DROP AS SELECT id_usuario FROM bibliotecario;

-- Si se corre otra vez (o sobre una base creada con el init nuevo), quitar
-- primero lo del Hito 3 para crearlo de nuevo igual.
ALTER TABLE lector        DROP CONSTRAINT IF EXISTS lector_usuario_perfil_fkey;
ALTER TABLE bibliotecario DROP CONSTRAINT IF EXISTS bibliotecario_usuario_perfil_fkey;
ALTER TABLE usuario       DROP CONSTRAINT IF EXISTS usuario_id_perfil_key;
DROP INDEX IF EXISTS categoria_nombre_lower_key;
DROP INDEX IF EXISTS autor_nombre_lower_key;

-- Regla 1: el perfil, amarrado con una FK compuesta.
-- usuario necesita un UNIQUE sobre (id_usuario, perfil) para que una FK
-- pueda apuntar a ese par. Es único porque id_usuario ya es la PK.
ALTER TABLE usuario ADD CONSTRAINT usuario_id_perfil_key UNIQUE (id_usuario, perfil);

-- La columna nueva nace con DEFAULT: las filas que ya existen quedan con
-- 'lector' (o 'bibliotecario'), y las cargas no tienen que cambiar.
ALTER TABLE lector ADD COLUMN IF NOT EXISTS perfil varchar(13) NOT NULL DEFAULT 'lector'
      CONSTRAINT ck_lector_perfil CHECK (perfil = 'lector');
ALTER TABLE lector ADD CONSTRAINT lector_usuario_perfil_fkey
      FOREIGN KEY (id_usuario, perfil) REFERENCES usuario (id_usuario, perfil) ON DELETE CASCADE;

ALTER TABLE bibliotecario ADD COLUMN IF NOT EXISTS perfil varchar(13) NOT NULL DEFAULT 'bibliotecario'
      CONSTRAINT ck_bibliotecario_perfil CHECK (perfil = 'bibliotecario');
ALTER TABLE bibliotecario ADD CONSTRAINT bibliotecario_usuario_perfil_fkey
      FOREIGN KEY (id_usuario, perfil) REFERENCES usuario (id_usuario, perfil) ON DELETE CASCADE;

-- Regla 2: nombres únicos sin distinguir mayúsculas
CREATE UNIQUE INDEX categoria_nombre_lower_key ON categoria (lower(nombre));
CREATE UNIQUE INDEX autor_nombre_lower_key     ON autor (lower(trim(nombre)));

-- ---------------------------------------------------------------------
-- 3. Verificación, antes de quitar lo viejo
-- ---------------------------------------------------------------------
\echo '== 3. Conteos antes y después (esperado: iguales en las 5 tablas; no se crea ni se borra ninguna fila) =='
SELECT a.tabla, a.filas AS antes, d.filas AS despues,
       CASE WHEN a.filas = d.filas THEN 'sí' ELSE 'NO' END AS coincide
FROM   antes_conteo a
JOIN  (SELECT 'usuario' AS tabla, count(*) AS filas FROM usuario
       UNION ALL SELECT 'lector',        count(*) FROM lector
       UNION ALL SELECT 'bibliotecario', count(*) FROM bibliotecario
       UNION ALL SELECT 'categoria',     count(*) FROM categoria
       UNION ALL SELECT 'autor',         count(*) FROM autor) d ON d.tabla = a.tabla;

\echo '== 3. lector: filas de antes que no están después, y al revés (esperado: 0 filas) =='
(SELECT id_usuario, telefono FROM antes_lector EXCEPT SELECT id_usuario, telefono FROM lector)
UNION ALL
(SELECT id_usuario, telefono FROM lector EXCEPT SELECT id_usuario, telefono FROM antes_lector);

\echo '== 3. bibliotecario: lo mismo (esperado: 0 filas) =='
(SELECT id_usuario FROM antes_bibliotecario EXCEPT SELECT id_usuario FROM bibliotecario)
UNION ALL
(SELECT id_usuario FROM bibliotecario EXCEPT SELECT id_usuario FROM antes_bibliotecario);

\echo '== 3. La columna nueva quedó llena (esperado: lector -> lector, bibliotecario -> bibliotecario) =='
SELECT 'lector' AS tabla, perfil, count(*) AS filas FROM lector GROUP BY perfil
UNION ALL
SELECT 'bibliotecario', perfil, count(*) FROM bibliotecario GROUP BY perfil;

-- ---------------------------------------------------------------------
-- 4. Quitar lo viejo: las FK simples (id_usuario) -> usuario. Ya sobran: la
--    FK compuesta también exige que el usuario exista.
-- ---------------------------------------------------------------------
ALTER TABLE lector        DROP CONSTRAINT IF EXISTS lector_id_usuario_fkey;
ALTER TABLE bibliotecario DROP CONSTRAINT IF EXISTS bibliotecario_id_usuario_fkey;

COMMIT;

-- ---------------------------------------------------------------------
-- 5. Las reglas nuevas funcionan: cada intento se rechaza (y no cambia nada)
-- ---------------------------------------------------------------------
\echo
\echo '== 5. Cambiar a "administrador" el perfil de un usuario que está en lector (esperado: rechazado) =='
DO $$
BEGIN
    UPDATE biblioteca.usuario SET perfil = 'administrador'
    WHERE  id_usuario = (SELECT min(id_usuario) FROM biblioteca.lector);
    RAISE NOTICE 'Se cambió (no debía pasar)';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Rechazado, como debe ser: %', SQLERRM;
END $$;

\echo '== 5. Registrar como lector a un usuario que no tiene perfil de lector (esperado: rechazado) =='
DO $$
DECLARE
    otro integer;
BEGIN
    SELECT min(id_usuario) INTO otro FROM biblioteca.usuario WHERE perfil <> 'lector';
    IF otro IS NULL THEN
        RAISE NOTICE 'No hay usuarios con otro perfil (correr antes datos-prueba.sql para tener a la bibliotecaria)';
        RETURN;
    END IF;
    INSERT INTO biblioteca.lector (id_usuario, telefono) VALUES (otro, '3000000000');
    RAISE NOTICE 'Se registró (no debía pasar)';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Rechazado, como debe ser: %', SQLERRM;
END $$;

\echo '== 5. Crear la categoría "novela" cuando ya existe "Novela" (esperado: rechazado) =='
DO $$
BEGIN
    INSERT INTO biblioteca.categoria (nombre) VALUES ('novela');
    RAISE NOTICE 'Se creó (no debía pasar)';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Rechazado, como debe ser: %', SQLERRM;
END $$;

\echo '== 5. Crear el autor " gabriel garcía márquez " (esperado: rechazado) =='
DO $$
BEGIN
    INSERT INTO biblioteca.autor (nombre) VALUES (' gabriel garcía márquez ');
    RAISE NOTICE 'Se creó (no debía pasar)';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Rechazado, como debe ser: %', SQLERRM;
END $$;

\echo '== 5. Lo que hace ahora la carga de libros con ese mismo autor: lo reconoce y no lo duplica (esperado: INSERT 0 0) =='
INSERT INTO biblioteca.autor (nombre) VALUES (' gabriel garcía márquez ')
ON CONFLICT ((lower(trim(nombre)))) DO NOTHING;

\echo
\echo '== Fin: el esquema quedó igual al de postgres/init/01_esquema.sql (Hito 3) =='
