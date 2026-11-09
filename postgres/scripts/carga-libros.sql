-- =====================================================================
-- carga-libros.sql  ·  Carga de libros desde CSV al esquema "biblioteca"
-- Patrón: archivo → tabla de paso → validación → tablas finales | bitácora
-- Reglas, orden y motivos: docs/mapeo-y-criterios.md (secciones 1.1 y 2)
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
--   docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
-- Sin "-v archivo=..." carga /scripts/datos/libros_semilla.csv.
--
-- Se corre con psql (usa meta-comandos \set, \if y la variable :'archivo').
-- Los resultados se revisan en pgAdmin: biblioteca.* y carga.rechazo_carga.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

BEGIN;

TRUNCATE carga.stg_linea, carga.stg_libro RESTART IDENTITY;

-- ---------------------------------------------------------------------
-- 1. EXTRAER: leer el archivo tal cual, una fila por línea.
--    FORMAT text separa columnas con tabulador; como el CSV no trae
--    tabuladores, cada línea entera cae en la única columna "linea".
--    Así ninguna línea rara (columnas de más, texto en un número...)
--    puede detener la lectura.
-- ---------------------------------------------------------------------
COPY carga.stg_linea (linea) FROM :'archivo' WITH (FORMAT text);

-- ---------------------------------------------------------------------
-- 2. TRANSFORMAR (1/2): partir cada línea en campos y normalizar lo mecánico.
--    Todo sigue siendo texto. Aquí un campo vacío queda como '' (no NULL).
--    regexp_replace(x, '\s+', ' ', 'g') deja los espacios repetidos en uno.
-- ---------------------------------------------------------------------
INSERT INTO carga.stg_libro (linea_csv, contenido, num_campos, isbn, titulo,
                             autor, categoria, anio_publicacion, ejemplares_disponibles)
SELECT n,
       linea,
       coalesce(array_length(string_to_array(linea, ','), 1), 0),
       regexp_replace(split_part(linea, ',', 1), '[-\s]', '', 'g'),                    -- caso 16: sin guiones ni espacios
       btrim(regexp_replace(split_part(linea, ',', 2), '\s+', ' ', 'g')),              -- caso 15
       btrim(regexp_replace(split_part(linea, ',', 3), '\s+', ' ', 'g')),
       initcap(btrim(regexp_replace(split_part(linea, ',', 4), '\s+', ' ', 'g'))),     -- caso 17: novela → Novela
       btrim(split_part(linea, ',', 5)),
       btrim(split_part(linea, ',', 6))
FROM carga.stg_linea
WHERE n > 1                  -- la línea 1 es el encabezado (se revisa en el paso 3)
  AND btrim(linea) <> '';    -- caso 21: las líneas en blanco se descartan

-- ---------------------------------------------------------------------
-- 3. VALIDAR: la PRIMERA regla que se cumple da el motivo del rechazo.
--    El CASE se evalúa en orden, así que los ::integer solo se intentan
--    cuando la regla anterior ya comprobó que el texto son dígitos.
--    Si ninguna regla se cumple, el CASE (sin ELSE) devuelve NULL: la fila pasó.
-- ---------------------------------------------------------------------
UPDATE carga.stg_libro AS s SET motivo = CASE
    -- Reglas del archivo y de la línea completa
    -- (sin BOM ni espacios; un ';' cuenta como ',' para que un archivo de Excel
    --  en español no caiga aquí sino en la regla del separador, que es más clara)
    WHEN (SELECT lower(regexp_replace(replace(replace(linea, chr(65279), ''), ';', ','), '\s', '', 'g'))
          FROM carga.stg_linea WHERE n = 1)
         IS DISTINCT FROM 'isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles'
        THEN 'encabezado no coincide con el esperado (isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles)'
    WHEN s.contenido LIKE '%"%'
        THEN 'contiene comillas: no se admiten comas dentro de un campo'
    WHEN s.num_campos = 1 AND s.contenido LIKE '%;%'
        THEN 'separador '';'' en lugar de '','' (¿guardado desde Excel en español?)'
    WHEN s.num_campos <> 6
        THEN 'tiene ' || s.num_campos || ' columnas, se esperaban 6'
    -- isbn                                          (PK, ck_libro_isbn)
    WHEN s.isbn = ''                                 THEN 'isbn vacío'
    WHEN s.isbn !~ '^[0-9]{13}$'                     THEN 'isbn no tiene 13 dígitos'
    -- titulo                                        (NOT NULL, ck_libro_titulo, varchar(200))
    WHEN s.titulo = ''                               THEN 'título vacío'
    WHEN char_length(s.titulo) > 200                 THEN 'título supera 200 caracteres'
    -- autor                                         (ck_autor_nombre, varchar(120))
    WHEN s.autor = ''                                THEN 'autor vacío'
    WHEN char_length(s.autor) > 120                  THEN 'autor supera 120 caracteres'
    -- categoria                                     (ck_categoria_nombre, varchar(40))
    WHEN s.categoria = ''                            THEN 'categoría vacía'
    WHEN char_length(s.categoria) > 40               THEN 'categoría supera 40 caracteres'
    -- anio_publicacion                              (ck_libro_anio: 1450-2100)
    WHEN s.anio_publicacion !~ '^[0-9]{1,4}$'        THEN 'año no numérico'
    WHEN s.anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                                     THEN 'año fuera de rango (1450-2100)'
    WHEN s.anio_publicacion::integer > extract(year FROM current_date)::integer
        THEN 'año en el futuro (posterior a ' || extract(year FROM current_date)::integer || ')'
    -- ejemplares_disponibles                        (ck_ejemplar_numero, smallint)
    WHEN s.ejemplares_disponibles !~ '^-?[0-9]{1,6}$' THEN 'ejemplares no numérico'
    WHEN s.ejemplares_disponibles::integer < 0        THEN 'ejemplares negativo'
    WHEN s.ejemplares_disponibles::integer > 100      THEN 'ejemplares supera el máximo por carga (100)'
    -- Duplicado CONTRA LA TABLA FINAL (principio 1: la carga solo da de alta)
    WHEN EXISTS (SELECT 1 FROM biblioteca.libro l WHERE l.isbn = s.isbn)
                                                     THEN 'isbn ya existe en el catálogo'
END;

-- ---------------------------------------------------------------------
-- 4. Duplicados DENTRO DEL MISMO ARCHIVO (caso 25). Ninguna de las dos
--    copias está aún en biblioteca.libro, así que el EXISTS del paso 3 no
--    las ve. Se conserva la primera aparición válida y se rechazan las demás.
--    La subconsulta "p" calcula, por ISBN, la primera línea válida.
-- ---------------------------------------------------------------------
UPDATE carga.stg_libro AS s
SET motivo = 'isbn repetido en el archivo (primera aparición: línea ' || p.primera || ')'
FROM (SELECT isbn, min(linea_csv) AS primera
      FROM carga.stg_libro
      WHERE motivo IS NULL
      GROUP BY isbn) AS p
WHERE s.motivo IS NULL
  AND s.isbn = p.isbn
  AND s.linea_csv > p.primera;

-- ---------------------------------------------------------------------
-- 5. CARGAR: las filas válidas (motivo IS NULL) pasan a las tablas finales,
--    ahora sí convertidas a su tipo real. El orden importa por las FK:
--    primero las tablas "padre" (categoria, autor), luego libro y al final
--    las que dependen de libro (libro_autor, ejemplar).
-- ---------------------------------------------------------------------

-- 5a. Categorías nuevas. ON CONFLICT DO NOTHING: si ya existe, no hace nada
--     (por eso categoria.nombre tiene UNIQUE).
INSERT INTO biblioteca.categoria (nombre)
SELECT DISTINCT categoria FROM carga.stg_libro WHERE motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;

-- 5b. Autores nuevos, igual que las categorías.
INSERT INTO biblioteca.autor (nombre)
SELECT DISTINCT autor FROM carga.stg_libro WHERE motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;

-- 5c. Libros: el CSV trae el NOMBRE de la categoría, pero libro necesita su
--     id_categoria, así que se busca con un JOIN.
INSERT INTO biblioteca.libro (isbn, titulo, anio_publicacion, id_categoria)
SELECT s.isbn, s.titulo, s.anio_publicacion::smallint, c.id_categoria
FROM carga.stg_libro s
JOIN biblioteca.categoria c ON c.nombre = s.categoria
WHERE s.motivo IS NULL;

-- 5d. Relación N:M libro-autor, buscando el id_autor por nombre.
INSERT INTO biblioteca.libro_autor (isbn, id_autor)
SELECT s.isbn, a.id_autor
FROM carga.stg_libro s
JOIN biblioteca.autor a ON a.nombre = s.autor
WHERE s.motivo IS NULL;

-- 5e. Ejemplares: el número "n" del CSV se convierte en n filas (copias 1..n).
--     generate_series(1, n) produce los números 1, 2, ..., n, y el CROSS JOIN
--     LATERAL lo ejecuta una vez por cada libro, con SU propio n.
INSERT INTO biblioteca.ejemplar (isbn, numero_copia)
SELECT s.isbn, g.n
FROM carga.stg_libro s
CROSS JOIN LATERAL generate_series(1, s.ejemplares_disponibles::integer) AS g(n)
WHERE s.motivo IS NULL;

-- ---------------------------------------------------------------------
-- 6. Dejar constancia de las rechazadas en la bitácora.
-- ---------------------------------------------------------------------
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM carga.stg_libro
WHERE motivo IS NOT NULL;

COMMIT;

-- ---------------------------------------------------------------------
-- Resumen de esta carga y estado del catálogo
-- ---------------------------------------------------------------------
\echo
\echo '=== Resumen de la carga:' :archivo
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM carga.stg_libro;

\echo '=== Filas rechazadas (también quedan en carga.rechazo_carga)'
SELECT linea_csv AS linea, motivo, contenido
FROM carga.stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

\echo '=== Totales en el catálogo después de la carga'
SELECT (SELECT count(*) FROM biblioteca.libro)     AS libros,
       (SELECT count(*) FROM biblioteca.ejemplar)  AS ejemplares,
       (SELECT count(*) FROM biblioteca.autor)     AS autores,
       (SELECT count(*) FROM biblioteca.categoria) AS categorias;
