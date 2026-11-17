-- =====================================================================
-- carga-lectores.sql  ·  Carga de lectores desde CSV al esquema "biblioteca"
-- Patrón: archivo → tabla de paso → validación → tablas finales | bitácora
-- Reglas, orden y motivos: docs/hito2/mapeo-y-criterios.md (secciones 1.2 y 2)
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/carga-lectores.sql
--   docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/hito2/carga-lectores.sql
-- Sin "-v archivo=..." carga /scripts/datos/lectores_semilla.csv.
--
-- Mismas etapas que carga-libros.sql. Lo nuevo: cada lector se reparte en
-- DOS tablas (usuario + lector) y recibe una contraseña inicial con hash.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

BEGIN;

TRUNCATE carga.stg_linea, carga.stg_lector RESTART IDENTITY;

-- ---------------------------------------------------------------------
-- 1. EXTRAER: el archivo tal cual, una fila por línea (igual que en libros).
-- ---------------------------------------------------------------------
COPY carga.stg_linea (linea) FROM :'archivo' WITH (FORMAT text);

-- ---------------------------------------------------------------------
-- 2. TRANSFORMAR: partir en campos y normalizar lo mecánico.
-- ---------------------------------------------------------------------
INSERT INTO carga.stg_lector (linea_csv, contenido, num_campos,
                              documento, nombres, apellidos, correo, telefono)
SELECT n,
       linea,
       coalesce(array_length(string_to_array(linea, ','), 1), 0),
       regexp_replace(split_part(linea, ',', 1), '[.\s]', '', 'g'),                 -- caso 19: 1.000.000.026 → 1000000026
       btrim(regexp_replace(split_part(linea, ',', 2), '\s+', ' ', 'g')),           -- caso 15
       btrim(regexp_replace(split_part(linea, ',', 3), '\s+', ' ', 'g')),
       lower(btrim(split_part(linea, ',', 4))),                                     -- caso 18: Ana@X.co → ana@x.co
       regexp_replace(split_part(linea, ',', 5), '[\s().-]', '', 'g')               -- caso 20: (300) 100-0026 → 3001000026
FROM carga.stg_linea
WHERE n > 1                  -- la línea 1 es el encabezado
  AND btrim(linea) <> '';    -- caso 21: líneas en blanco

-- ---------------------------------------------------------------------
-- 3. VALIDAR: la PRIMERA regla que se cumple da el motivo.
--    Primero el formato de cada campo; al final, las reglas que consultan
--    la base (¿ya existe?), que solo tiene sentido revisar en filas bien formadas.
-- ---------------------------------------------------------------------
UPDATE carga.stg_lector AS s SET motivo = CASE
    -- Reglas del archivo y de la línea completa
    WHEN (SELECT lower(regexp_replace(replace(replace(linea, chr(65279), ''), ';', ','), '\s', '', 'g'))
          FROM carga.stg_linea WHERE n = 1)
         IS DISTINCT FROM 'documento,nombres,apellidos,correo,telefono'
        THEN 'encabezado no coincide con el esperado (documento,nombres,apellidos,correo,telefono)'
    WHEN s.contenido LIKE '%"%'
        THEN 'contiene comillas: no se admiten comas dentro de un campo'
    WHEN s.num_campos = 1 AND s.contenido LIKE '%;%'
        THEN 'separador '';'' en lugar de '','' (¿guardado desde Excel en español?)'
    WHEN s.num_campos <> 5
        THEN 'tiene ' || s.num_campos || ' columnas, se esperaban 5'
    -- documento                                     (UNIQUE, ck_usuario_documento)
    WHEN s.documento = ''                            THEN 'documento vacío'
    WHEN s.documento !~ '^[0-9]{6,15}$'              THEN 'documento no numérico o de longitud inválida (6-15 dígitos)'
    -- nombres y apellidos                           (ck_usuario_nombres/apellidos, varchar(80))
    WHEN s.nombres = ''                              THEN 'nombres vacíos'
    WHEN char_length(s.nombres) > 80                 THEN 'nombres superan 80 caracteres'
    WHEN s.apellidos = ''                            THEN 'apellidos vacíos'
    WHEN char_length(s.apellidos) > 80               THEN 'apellidos superan 80 caracteres'
    -- correo                                        (UNIQUE, ck_usuario_correo_formato/minusculas, varchar(120))
    WHEN s.correo = ''                               THEN 'correo vacío'
    WHEN s.correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'       THEN 'correo mal formado'
    WHEN char_length(s.correo) > 120                 THEN 'correo supera 120 caracteres'
    -- telefono                                      (ck_lector_telefono)
    WHEN s.telefono = ''                             THEN 'teléfono vacío'
    WHEN s.telefono !~ '^[0-9]{7,15}$'               THEN 'teléfono no numérico o de longitud inválida (7-15 dígitos)'
    -- Duplicados CONTRA LA BASE: se busca en usuario (los 4 perfiles), no solo en lector
    WHEN EXISTS (SELECT 1 FROM biblioteca.usuario u WHERE u.documento = s.documento)
        THEN 'documento ya registrado (perfil '
             || (SELECT u.perfil FROM biblioteca.usuario u WHERE u.documento = s.documento) || ')'
    WHEN EXISTS (SELECT 1 FROM biblioteca.usuario u WHERE u.correo = s.correo)
        THEN 'correo ya registrado por otro usuario'
END;

-- ---------------------------------------------------------------------
-- 4. Duplicados DENTRO DEL MISMO ARCHIVO: primero por documento (caso 26),
--    después por correo (caso 27). Como el correo ya pasó por lower(),
--    "ana@x.co" y "ANA@X.co" cuentan como el mismo.
-- ---------------------------------------------------------------------
UPDATE carga.stg_lector AS s
SET motivo = 'documento repetido en el archivo (primera aparición: línea ' || p.primera || ')'
FROM (SELECT documento, min(linea_csv) AS primera
      FROM carga.stg_lector WHERE motivo IS NULL GROUP BY documento) AS p
WHERE s.motivo IS NULL AND s.documento = p.documento AND s.linea_csv > p.primera;

UPDATE carga.stg_lector AS s
SET motivo = 'correo repetido en el archivo (primera aparición: línea ' || p.primera || ')'
FROM (SELECT correo, min(linea_csv) AS primera
      FROM carga.stg_lector WHERE motivo IS NULL GROUP BY correo) AS p
WHERE s.motivo IS NULL AND s.correo = p.correo AND s.linea_csv > p.primera;

-- ---------------------------------------------------------------------
-- 5. CARGAR en DOS tablas, en el orden que exige la FK:
--    primero usuario (la "general"), después lector (el perfil).
-- ---------------------------------------------------------------------

-- 5a. usuario. Tres columnas no vienen en el CSV:
--     - perfil: la constante 'lector'
--     - contrasena_hash: el documento cifrado con bcrypt. gen_salt('bf', 10)
--       crea una "sal" aleatoria con factor de costo 10, así que dos lectores
--       con la misma clave tienen hashes distintos. Nunca se guarda la clave.
--     - debe_cambiar_contrasena: queda en true por su DEFAULT.
INSERT INTO biblioteca.usuario (documento, nombres, apellidos, correo, contrasena_hash, perfil)
SELECT documento, nombres, apellidos, correo,
       public.crypt(documento, public.gen_salt('bf', 10)),
       'lector'
FROM carga.stg_lector
WHERE motivo IS NULL;

-- 5b. lector. Su PK es el id_usuario que PostgreSQL acaba de generar en 5a;
--     el CSV no lo trae, así que se recupera con un JOIN por el documento
--     (que es UNIQUE: identifica a la persona sin ambigüedad).
INSERT INTO biblioteca.lector (id_usuario, telefono)
SELECT u.id_usuario, s.telefono
FROM carga.stg_lector s
JOIN biblioteca.usuario u ON u.documento = s.documento
WHERE s.motivo IS NULL;

-- ---------------------------------------------------------------------
-- 6. Bitácora de rechazos
-- ---------------------------------------------------------------------
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM carga.stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- ---------------------------------------------------------------------
-- Resumen de esta carga y estado de los lectores
-- ---------------------------------------------------------------------
\echo
\echo '=== Resumen de la carga:' :archivo
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM carga.stg_lector;

\echo '=== Filas rechazadas (también quedan en carga.rechazo_carga)'
SELECT linea_csv AS linea, motivo, contenido
FROM carga.stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

\echo '=== Totales después de la carga (deben ser iguales: cada usuario lector tiene su fila en lector)'
SELECT (SELECT count(*) FROM biblioteca.usuario WHERE perfil = 'lector') AS usuarios_lector,
       (SELECT count(*) FROM biblioteca.lector)                          AS lectores;
