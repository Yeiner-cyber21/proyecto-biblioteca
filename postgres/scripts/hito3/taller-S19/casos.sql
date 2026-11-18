-- =====================================================================
-- casos.sql  ·  S19, Parte A: clínica de esquemas mal diseñados
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Cuatro esquemas "en producción", cada uno con una queja del negocio:
--   Caso 1  gimnasio       socio
--   Caso 2  farmacia       formula
--   Caso 3  cursos_libres  inscripcion
--   Caso 4  envios         envio
-- Para cada caso, en comentarios y SQL: (a) diagnóstico, (b) evidencia,
-- (c) esquema corregido, (d) migración en BEGIN … COMMIT, (e) verificación
-- y la pregunta propia.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S19/casos.sql
--
-- Re-ejecutable: la primera instrucción vuelve a correr S19-esquemas.sql,
-- que borra y recrea los cuatro esquemas como al principio. Así la
-- evidencia (b) siempre se toma sobre los datos originales.
--
-- Cada migración sigue el orden de la pre-lectura (sección 4): evidencia →
-- BEGIN → crear tablas nuevas → copiar → verificar (conteos esperados
-- escritos ANTES y EXCEPT) → quitar lo viejo → COMMIT. Con ON_ERROR_STOP,
-- si algo falla dentro de la transacción, el script se detiene y la
-- transacción no se confirma: la base queda como estaba.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo '== Preparación: los cuatro esquemas, como al principio =='
\ir S19-esquemas.sql


-- #####################################################################
-- CASO 1: gimnasio
-- socio (id_socio PK, nombre, plan, valor_plan, clases)
-- Queja: "Le pedí al sistema cuántos socios hay en Yoga y me dijo 2, pero
-- son 3. Y en Spinning me dijo 3, cuando son 2."
-- #####################################################################
SET search_path TO gimnasio;
\echo
\echo '######## CASO 1: gimnasio ########'

-- ---------------------------------------------------------------------
-- (a) Diagnóstico
--
-- Dependencias (reglas del negocio):
--   id_socio -> nombre, plan       cada socio tiene un nombre y un plan
--   plan -> valor_plan             cada plan tiene un valor fijo
--   (las clases de un socio son VARIAS: no dependen funcionalmente de id_socio)
--
-- Problema principal (explica la queja): la columna clases guarda una LISTA
--   separada por ';'. No es un valor atómico: NO ESTÁ EN 1FN. Para contar
--   socios por clase hay que buscar texto con LIKE, y eso falla de dos formas:
--   - 'Pilates;yoga' está en minúscula: LIKE '%Yoga%' no lo encuentra (Yoga da 2, no 3).
--   - 'Spinning avanzado' contiene 'Spinning': LIKE '%Spinning%' lo cuenta (Spinning da 3, no 2).
--   Además, los pedazos están sucios: espacios de más (' Yoga ') y separadores
--   con y sin espacio ('; ' y ';').
--
-- Problema secundario: plan -> valor_plan, y plan no es clave. Es una
--   dependencia TRANSITIVA (id_socio -> plan -> valor_plan): NO ESTÁ EN 3FN.
--   El valor del plan Mensual (90000) está escrito 3 veces; subirle el precio
--   exige actualizar a todos sus socios (anomalía de modificación de S17).
--
-- Otro problema: la clase no existe como entidad. No se puede registrar una
--   clase que todavía no tiene socios, ni guardar datos de la clase (horario).
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (b) Evidencia
-- ---------------------------------------------------------------------
\echo '-- (b.1) La queja: la consulta con LIKE (esperado: yoga 2, spinning 3, ambos MAL)'
SELECT count(*) FILTER (WHERE clases LIKE '%Yoga%')     AS socios_yoga_like,
       count(*) FILTER (WHERE clases LIKE '%Spinning%') AS socios_spinning_like
FROM   socio;

\echo '-- (b.2) Por qué: los pedazos de la lista, entre corchetes para ver los espacios (esperado: 9 filas)'
SELECT s.id_socio, s.nombre, '[' || c || ']' AS pedazo
FROM   socio s, string_to_table(s.clases, ';') AS c
ORDER BY s.id_socio;

\echo '-- (b.3) Conteo correcto, limpiando cada pedazo (esperado: yoga 3, spinning 2)'
SELECT lower(trim(c)) AS clase, count(DISTINCT s.id_socio) AS socios
FROM   socio s, string_to_table(s.clases, ';') AS c
WHERE  trim(c) <> ''
GROUP BY lower(trim(c))
ORDER BY clase;

\echo '-- (b.4) plan -> valor_plan: ¿algún plan con dos valores? (esperado: 0 filas)'
SELECT plan FROM socio GROUP BY plan HAVING count(DISTINCT valor_plan) > 1;

\echo '-- (b.5) Redundancia: cuántas veces está escrito el valor de cada plan (esperado: Mensual 3, Anual 2, Trimestral 1)'
SELECT plan, valor_plan, count(*) AS veces FROM socio GROUP BY plan, valor_plan ORDER BY veces DESC, plan;

-- ---------------------------------------------------------------------
-- (c) Esquema corregido
--   plan        (nombre_plan PK, valor)
--   socio       (id_socio PK, nombre, plan FK -> plan)          sin valor_plan ni clases
--   clase       (id_clase PK, nombre UNIQUE, también sin distinguir mayúsculas)
--   socio_clase (id_socio FK -> socio, id_clase FK -> clase)    PK (id_socio, id_clase)
-- La lista se vuelve una fila por (socio, clase): 1FN. El valor del plan
-- se escribe una sola vez: 3FN.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (d) Migración
-- Criterio de limpieza: dos pedazos son la misma clase si coinciden sin
-- espacios al inicio y al final y sin distinguir mayúsculas: lower(trim(c)).
-- El nombre que se guarda es ese texto con solo la primera letra en
-- mayúscula ('Spinning avanzado'). No se usa initcap porque convertiría
-- 'Spinning avanzado' en 'Spinning Avanzado'. 'Spinning' y 'Spinning
-- avanzado' son clases DISTINTAS (lo dice el enunciado): no se juntan.
-- Pedazos vacíos (por ejemplo, un ';' al final) se descartan.
--
-- Conteos esperados, calculados antes de migrar:
--   plan 3 (Mensual, Trimestral, Anual)
--   clase 5 (Funcional, Pilates, Spinning, Spinning avanzado, Yoga)
--   socio_clase 9 (Laura 2, Pedro 1, María Fernanda 2, Andrés 3, Sofía 0, Tomás 1)
--   socio 6 (no cambia)
-- ---------------------------------------------------------------------
\echo
\echo '-- (d) Migración del caso 1'
BEGIN;

CREATE TABLE plan (
    nombre_plan  varchar(20)  PRIMARY KEY,
    valor        integer      NOT NULL CHECK (valor > 0)
);
INSERT INTO plan (nombre_plan, valor)
SELECT DISTINCT plan, valor_plan FROM socio;

CREATE TABLE clase (
    id_clase  serial       PRIMARY KEY,
    nombre    varchar(40)  NOT NULL UNIQUE
);
-- Protege la clave natural también contra mayúsculas: 'Yoga' y 'yoga' no pueden convivir
CREATE UNIQUE INDEX ux_clase_nombre_sin_mayusculas ON clase (lower(nombre));
INSERT INTO clase (nombre)
SELECT DISTINCT upper(left(lower(trim(c)), 1)) || substr(lower(trim(c)), 2)
FROM   socio s, string_to_table(s.clases, ';') AS c
WHERE  trim(c) <> ''
ORDER BY 1;

CREATE TABLE socio_clase (
    id_socio  integer  NOT NULL REFERENCES socio (id_socio),
    id_clase  integer  NOT NULL REFERENCES clase (id_clase),
    PRIMARY KEY (id_socio, id_clase)
);
INSERT INTO socio_clase (id_socio, id_clase)
SELECT DISTINCT s.id_socio, cl.id_clase
FROM   socio s, string_to_table(s.clases, ';') AS c, clase cl
WHERE  trim(c) <> ''
  AND  lower(cl.nombre) = lower(trim(c));

-- (e) Verificación, antes de quitar las columnas viejas
\echo '-- (e) Conteos: esperado plan 3, clase 5, socio_clase 9, socio 6'
SELECT (SELECT count(*) FROM plan)        AS plan,
       (SELECT count(*) FROM clase)       AS clase,
       (SELECT count(*) FROM socio_clase) AS socio_clase,
       (SELECT count(*) FROM socio)       AS socio;

\echo '-- (e) Pares (socio, clase) del texto original que NO quedaron en socio_clase (esperado: 0 filas)'
SELECT s.id_socio, lower(trim(c)) AS clase
FROM   socio s, string_to_table(s.clases, ';') AS c
WHERE  trim(c) <> ''
EXCEPT
SELECT sc.id_socio, lower(cl.nombre)
FROM   socio_clase sc JOIN clase cl ON cl.id_clase = sc.id_clase;

\echo '-- (e) Pares en socio_clase que NO estaban en el texto original (esperado: 0 filas)'
SELECT sc.id_socio, lower(cl.nombre) AS clase
FROM   socio_clase sc JOIN clase cl ON cl.id_clase = sc.id_clase
EXCEPT
SELECT s.id_socio, lower(trim(c))
FROM   socio s, string_to_table(s.clases, ';') AS c
WHERE  trim(c) <> '';

\echo '-- (e) Cada socio conserva su plan y su valor (esperado: 0 filas)'
SELECT id_socio, plan, valor_plan FROM socio
EXCEPT
SELECT s.id_socio, p.nombre_plan, p.valor FROM socio s JOIN plan p ON p.nombre_plan = s.plan;

-- Verificado: ahora sí se quita lo viejo
ALTER TABLE socio ADD CONSTRAINT socio_plan_fkey FOREIGN KEY (plan) REFERENCES plan (nombre_plan);
ALTER TABLE socio DROP COLUMN valor_plan, DROP COLUMN clases;

COMMIT;

\echo '-- (e) La queja, resuelta en el esquema nuevo (esperado: Yoga 3 y Spinning 2; Spinning avanzado aparte, con 1)'
SELECT cl.nombre AS clase, count(sc.id_socio) AS socios
FROM   clase cl LEFT JOIN socio_clase sc ON sc.id_clase = cl.id_clase
GROUP BY cl.nombre
ORDER BY cl.nombre;

\echo '-- (e) La clave natural protegida: registrar otra vez la clase "yoga" (esperado: NOTICE de rechazo)'
DO $$
BEGIN
    INSERT INTO gimnasio.clase (nombre) VALUES ('yoga');
    RAISE NOTICE 'Se aceptó la clase repetida (no debía pasar)';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Rechazada, como debe ser: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- Pregunta propia: ¿dónde va el horario de cada clase, y por qué era
-- imposible hacerlo bien con el diseño original?
--
-- El horario es un dato de la CLASE (id_clase -> dia, hora), no del socio:
-- va en la tabla clase (columnas dia y hora) o, si una clase tiene varias
-- sesiones por semana, en una tabla clase_horario (id_clase FK, dia, hora)
-- con PK (id_clase, dia, hora).
--
-- Con el diseño original no había dónde ponerlo bien:
--   - La clase no tenía fila propia: solo existía como un pedazo de texto
--     dentro de cada socio. El horario de Yoga habría que copiarlo en cada
--     socio de Yoga (redundancia, y la anomalía de modificación al cambiarlo).
--   - Si se metía en el mismo texto ('Yoga lun 7:00; Spinning mar 18:00'),
--     la celda sería todavía menos atómica y las consultas, más frágiles.
--   - Una clase sin socios (recién abierta) no tendría dónde guardar su
--     horario: es la anomalía de inserción de S17.
-- ---------------------------------------------------------------------


-- #####################################################################
-- CASO 2: farmacia
-- formula (num_formula PK, fecha, doc_paciente, nombre_paciente,
--          medicamento1, dosis1, medicamento2, dosis2, medicamento3, dosis3)
-- Queja: "El médico le recetó cuatro medicamentos a un paciente y el sistema
-- solo me deja registrar tres. Y para saber cuántas fórmulas llevan
-- acetaminofén tengo que buscar en tres columnas."
-- #####################################################################
SET search_path TO farmacia;
\echo
\echo '######## CASO 2: farmacia ########'

-- ---------------------------------------------------------------------
-- (a) Diagnóstico
--
-- Dependencias (reglas del negocio):
--   num_formula -> fecha, doc_paciente          cada fórmula es de un paciente, en una fecha
--   doc_paciente -> nombre_paciente             el documento identifica al paciente
--   num_formula, medicamento -> dosis           cada medicamento de la fórmula tiene su dosis
--                                               (un medicamento no se repite en la fórmula)
--
-- Problema principal (explica la queja): medicamento1..3 y dosis1..3 son un
--   GRUPO REPETIDO: NO ESTÁ EN 1FN. El número de columnas pone un tope
--   artificial (3 medicamentos), y toda consulta por medicamento tiene que
--   mirar las tres columnas: si alguien busca solo en medicamento1, encuentra
--   1 fórmula con acetaminofén cuando son 3.
--
-- Problema secundario: doc_paciente -> nombre_paciente, y doc_paciente no es
--   clave. Es transitiva (num_formula -> doc_paciente -> nombre_paciente): NO
--   ESTÁ EN 3FN. El nombre de Rosa Díaz está copiado en sus dos fórmulas.
--
-- Otros problemas del grupo repetido:
--   - La regla "un medicamento no aparece dos veces en la misma fórmula" no se
--     puede declarar: un UNIQUE no compara medicamento1 con medicamento3.
--   - Casi todo medicamento3/dosis3 está en NULL, y nada impide llenar dosis2
--     sin medicamento2.
--   - La dosis NO depende solo del medicamento (acetaminofén va cada 8 h en una
--     fórmula y cada 6 h en otra): es un dato de la línea de la fórmula.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (b) Evidencia
-- ---------------------------------------------------------------------
\echo '-- (b.1) La queja: buscar acetaminofén solo en medicamento1 vs en las 3 columnas (esperado: 1 y 3)'
SELECT count(*) FILTER (WHERE medicamento1 LIKE 'Acetaminof%')                AS solo_medicamento1,
       count(*) FILTER (WHERE medicamento1 LIKE 'Acetaminof%'
                           OR medicamento2 LIKE 'Acetaminof%'
                           OR medicamento3 LIKE 'Acetaminof%')                  AS en_las_tres_columnas
FROM   formula;

\echo '-- (b.2) El grupo repetido, casi vacío: cuántas fórmulas usan cada columna (esperado: 4, 3 y 1 de 4)'
SELECT count(medicamento1) AS con_medicamento1,
       count(medicamento2) AS con_medicamento2,
       count(medicamento3) AS con_medicamento3,
       count(*)            AS formulas
FROM   formula;

\echo '-- (b.3) doc_paciente -> nombre_paciente: ¿algún documento con dos nombres? (esperado: 0 filas)'
SELECT doc_paciente FROM formula GROUP BY doc_paciente HAVING count(DISTINCT nombre_paciente) > 1;

\echo '-- (b.4) Redundancia del paciente (esperado: Rosa Díaz, 2 veces)'
SELECT doc_paciente, nombre_paciente, count(*) AS veces
FROM   formula GROUP BY doc_paciente, nombre_paciente HAVING count(*) > 1;

\echo '-- (b.5) La dosis no depende solo del medicamento (esperado: Acetaminofén con 2 dosis distintas)'
SELECT medicamento, count(DISTINCT dosis) AS dosis_distintas, string_agg(DISTINCT dosis, ' / ') AS dosis
FROM (
    SELECT medicamento1 AS medicamento, dosis1 AS dosis FROM formula
    UNION ALL SELECT medicamento2, dosis2 FROM formula WHERE medicamento2 IS NOT NULL
    UNION ALL SELECT medicamento3, dosis3 FROM formula WHERE medicamento3 IS NOT NULL
) AS lineas
GROUP BY medicamento
HAVING count(DISTINCT dosis) > 1;

-- ---------------------------------------------------------------------
-- (c) Esquema corregido
--   paciente            (doc_paciente PK, nombre_paciente)
--   medicamento         (id_medicamento PK, nombre UNIQUE)      catálogo
--   formula             (num_formula PK, fecha, doc_paciente FK -> paciente)
--   formula_medicamento (num_formula FK -> formula, id_medicamento FK -> medicamento, dosis)
--                        PK (num_formula, id_medicamento)
-- Una fila por medicamento recetado: sin tope, sin NULL de relleno, y la PK
-- impide repetir un medicamento en la misma fórmula.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (d) Migración
-- Las columnas numeradas se pasan a filas con UNION ALL (las vacías se
-- descartan). Los nombres de los medicamentos ya están escritos igual en
-- todas las fórmulas, así que no hace falta limpiarlos.
--
-- Conteos esperados, calculados antes de migrar:
--   paciente 3 (Rosa, Óscar, Elsa)
--   medicamento 5 (Acetaminofén, Amoxicilina, Ibuprofeno, Loratadina, Omeprazol)
--   formula_medicamento 8 (701: 2, 702: 1, 703: 3, 704: 2)
--   formula 4 (no cambia)
-- ---------------------------------------------------------------------
\echo
\echo '-- (d) Migración del caso 2'
BEGIN;

CREATE TABLE paciente (
    doc_paciente     varchar(15)  PRIMARY KEY,
    nombre_paciente  varchar(80)  NOT NULL
);
INSERT INTO paciente (doc_paciente, nombre_paciente)
SELECT DISTINCT doc_paciente, nombre_paciente FROM formula;

CREATE TABLE medicamento (
    id_medicamento  serial       PRIMARY KEY,
    nombre          varchar(60)  NOT NULL UNIQUE
);
INSERT INTO medicamento (nombre)
SELECT medicamento1 FROM formula
UNION
SELECT medicamento2 FROM formula WHERE medicamento2 IS NOT NULL
UNION
SELECT medicamento3 FROM formula WHERE medicamento3 IS NOT NULL
ORDER BY 1;

CREATE TABLE formula_medicamento (
    num_formula     integer      NOT NULL REFERENCES formula (num_formula),
    id_medicamento  integer      NOT NULL REFERENCES medicamento (id_medicamento),
    dosis           varchar(40)  NOT NULL,
    PRIMARY KEY (num_formula, id_medicamento)
);
INSERT INTO formula_medicamento (num_formula, id_medicamento, dosis)
SELECT l.num_formula, m.id_medicamento, l.dosis
FROM (
    SELECT num_formula, medicamento1 AS medicamento, dosis1 AS dosis FROM formula
    UNION ALL
    SELECT num_formula, medicamento2, dosis2 FROM formula WHERE medicamento2 IS NOT NULL
    UNION ALL
    SELECT num_formula, medicamento3, dosis3 FROM formula WHERE medicamento3 IS NOT NULL
) AS l
JOIN medicamento m ON m.nombre = l.medicamento;

-- (e) Verificación, antes de quitar las columnas viejas
\echo '-- (e) Conteos: esperado paciente 3, medicamento 5, formula_medicamento 8, formula 4'
SELECT (SELECT count(*) FROM paciente)            AS paciente,
       (SELECT count(*) FROM medicamento)         AS medicamento,
       (SELECT count(*) FROM formula_medicamento) AS formula_medicamento,
       (SELECT count(*) FROM formula)             AS formula;

\echo '-- (e) Líneas de las columnas viejas que NO quedaron en formula_medicamento (esperado: 0 filas)'
SELECT num_formula, medicamento1 AS medicamento, dosis1 AS dosis FROM formula
UNION ALL SELECT num_formula, medicamento2, dosis2 FROM formula WHERE medicamento2 IS NOT NULL
UNION ALL SELECT num_formula, medicamento3, dosis3 FROM formula WHERE medicamento3 IS NOT NULL
EXCEPT
SELECT fm.num_formula, m.nombre, fm.dosis
FROM   formula_medicamento fm JOIN medicamento m ON m.id_medicamento = fm.id_medicamento;

\echo '-- (e) Líneas en formula_medicamento que NO estaban en las columnas viejas (esperado: 0 filas)'
SELECT fm.num_formula, m.nombre, fm.dosis
FROM   formula_medicamento fm JOIN medicamento m ON m.id_medicamento = fm.id_medicamento
EXCEPT
(SELECT num_formula, medicamento1, dosis1 FROM formula
 UNION ALL SELECT num_formula, medicamento2, dosis2 FROM formula WHERE medicamento2 IS NOT NULL
 UNION ALL SELECT num_formula, medicamento3, dosis3 FROM formula WHERE medicamento3 IS NOT NULL);

\echo '-- (e) Cada fórmula conserva su paciente (esperado: 0 filas)'
SELECT num_formula, doc_paciente, nombre_paciente FROM formula
EXCEPT
SELECT f.num_formula, p.doc_paciente, p.nombre_paciente FROM formula f JOIN paciente p ON p.doc_paciente = f.doc_paciente;

-- Verificado: ahora sí se quita lo viejo
ALTER TABLE formula ADD CONSTRAINT formula_paciente_fkey FOREIGN KEY (doc_paciente) REFERENCES paciente (doc_paciente);
ALTER TABLE formula
    DROP COLUMN nombre_paciente,
    DROP COLUMN medicamento1, DROP COLUMN dosis1,
    DROP COLUMN medicamento2, DROP COLUMN dosis2,
    DROP COLUMN medicamento3, DROP COLUMN dosis3;

COMMIT;

\echo '-- (e) La queja, resuelta: fórmulas con acetaminofén, buscando en UN solo lugar (esperado: 3)'
SELECT count(DISTINCT fm.num_formula) AS formulas_con_acetaminofen
FROM   formula_medicamento fm JOIN medicamento m ON m.id_medicamento = fm.id_medicamento
WHERE  m.nombre LIKE 'Acetaminof%';

\echo '-- (e) La queja, resuelta: un cuarto medicamento en la fórmula 703 (esperado: 4 medicamentos; se deshace con ROLLBACK)'
BEGIN;
INSERT INTO medicamento (nombre) VALUES ('Vitamina C 500 mg');
INSERT INTO formula_medicamento (num_formula, id_medicamento, dosis)
SELECT 703, id_medicamento, 'cada 24 h' FROM medicamento WHERE nombre = 'Vitamina C 500 mg';
SELECT fm.num_formula, m.nombre AS medicamento, fm.dosis
FROM   formula_medicamento fm JOIN medicamento m ON m.id_medicamento = fm.id_medicamento
WHERE  fm.num_formula = 703
ORDER BY m.nombre;
ROLLBACK;

\echo '-- (e) La regla protegida: repetir el ibuprofeno en la fórmula 703 (esperado: NOTICE de rechazo)'
DO $$
BEGIN
    INSERT INTO farmacia.formula_medicamento (num_formula, id_medicamento, dosis)
    SELECT 703, id_medicamento, 'cada 8 h' FROM farmacia.medicamento WHERE nombre = 'Ibuprofeno 400 mg';
    RAISE NOTICE 'Se aceptó el medicamento repetido (no debía pasar)';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Rechazada, como debe ser: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- Pregunta propia: ¿por qué no basta con agregar medicamento4 y dosis4?
--
-- 1. El tope solo se corre: el día que el médico recete cinco, hay que volver
--    a cambiar la tabla (ALTER TABLE), y con ella todos los programas,
--    formularios y consultas que la usan.
-- 2. Las consultas empeoran: "¿cuántas fórmulas llevan acetaminofén?" pasa a
--    buscar en cuatro columnas, y "¿cuál es el medicamento más recetado?"
--    necesita un UNION ALL de cuatro partes. Cada consulta que olvide una
--    columna da un resultado equivocado sin avisar.
-- 3. Sigue sin poderse declarar la regla "un medicamento no se repite en la
--    fórmula" (un UNIQUE no compara columnas entre sí), ni una FK hacia el
--    catálogo sin escribir cuatro, ni impedir dosis4 sin medicamento4.
-- 4. Más columnas casi siempre en NULL: la mayoría de las fórmulas tienen uno
--    o dos medicamentos.
-- En resumen, sigue siendo un grupo repetido: no está en 1FN.
-- ---------------------------------------------------------------------


-- #####################################################################
-- CASO 3: cursos_libres
-- inscripcion (id PK serial, doc_participante, nombre_participante, correo,
--              cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
-- Queja: "Contabilidad dice que Fotografía digital recaudó 200 000 pesos
-- más de lo que hay en caja."
-- #####################################################################
SET search_path TO cursos_libres;
\echo
\echo '######## CASO 3: cursos_libres ########'

-- ---------------------------------------------------------------------
-- (a) Diagnóstico
--
-- Dependencias (reglas del negocio):
--   doc_participante -> nombre_participante, correo     el documento identifica al participante
--   correo -> doc_participante                          el correo también lo identifica
--   cod_curso -> nombre_curso, cod_sede                 cada curso se dicta en una sola sede
--   cod_sede -> direccion_sede                          cada sede tiene una dirección
--   doc_participante, cod_curso -> valor_pagado, id     se inscribe a lo sumo una vez por curso
--                                                       (el valor puede tener descuento)
-- Claves candidatas: {id}, {doc_participante, cod_curso} y {correo, cod_curso}.
--
-- Problema principal (explica la queja): la PK es un id serial y NO HAY
--   UNIQUE sobre la clave natural (doc_participante, cod_curso). Nada impidió
--   inscribir dos veces a Juliana Rey en Fotografía digital (filas 3 y 7, con
--   200000 cada una): el curso "recaudó" 580000 en vez de 380000.
--
-- Problema secundario: dependencias PARCIALES de la clave candidata
--   (doc_participante, cod_curso): nombre y correo dependen solo del
--   participante; nombre del curso y sede, solo del curso. NO ESTÁ EN 2FN,
--   aunque la PK tenga una sola columna.
--
-- Otro problema: cod_curso -> cod_sede -> direccion_sede es TRANSITIVA (3FN).
--   La dirección 'Cra 5 # 10-20' está escrita 5 veces.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (b) Evidencia
-- ---------------------------------------------------------------------
\echo '-- (b.1) La queja: lo recaudado por curso (esperado: Fotografía digital 580000; en caja hay 380000)'
SELECT cod_curso, nombre_curso, count(*) AS inscripciones, sum(valor_pagado) AS recaudado
FROM   inscripcion GROUP BY cod_curso, nombre_curso ORDER BY cod_curso;

\echo '-- (b.2) La causa: filas repetidas en la clave natural (esperado: Juliana en C20, ids 3 y 7)'
SELECT doc_participante, nombre_participante, cod_curso, count(*) AS veces,
       string_agg(id::text, ', ' ORDER BY id) AS ids, sum(valor_pagado) AS cobrado
FROM   inscripcion
GROUP BY doc_participante, nombre_participante, cod_curso
HAVING count(*) > 1;

\echo '-- (b.3) Las dependencias no están contradichas (esperado: 0 filas en cada una)'
SELECT 'cod_curso -> nombre_curso, cod_sede' AS dependencia, cod_curso AS valor FROM inscripcion
GROUP BY cod_curso HAVING count(DISTINCT nombre_curso) > 1 OR count(DISTINCT cod_sede) > 1
UNION ALL
SELECT 'cod_sede -> direccion_sede', cod_sede FROM inscripcion
GROUP BY cod_sede HAVING count(DISTINCT direccion_sede) > 1
UNION ALL
SELECT 'doc_participante -> nombre, correo', doc_participante FROM inscripcion
GROUP BY doc_participante HAVING count(DISTINCT nombre_participante) > 1 OR count(DISTINCT correo) > 1
UNION ALL
SELECT 'correo -> doc_participante', correo FROM inscripcion
GROUP BY correo HAVING count(DISTINCT doc_participante) > 1;

\echo '-- (b.4) Redundancia: cuántas veces está escrita cada dirección de sede (esperado: S1 5, S2 3)'
SELECT cod_sede, direccion_sede, count(*) AS veces FROM inscripcion GROUP BY cod_sede, direccion_sede ORDER BY cod_sede;

-- ---------------------------------------------------------------------
-- (c) Esquema corregido
--   participante (doc_participante PK, nombre_participante, correo UNIQUE)
--   sede         (cod_sede PK, direccion_sede)
--   curso        (cod_curso PK, nombre_curso, cod_sede FK -> sede)
--   inscripcion  (id PK, doc_participante FK -> participante, cod_curso FK -> curso,
--                 valor_pagado)   UNIQUE (doc_participante, cod_curso)
-- Se conserva el id (otros programas pueden usarlo), pero ahora la clave
-- natural está protegida con UNIQUE: el id ya no esconde duplicados.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (d) Migración
-- Criterio de limpieza: las filas 3 y 7 son idénticas salvo el id (mismo
-- participante, mismo curso, mismo valor). La regla dice que un participante
-- se inscribe a lo sumo una vez por curso, así que una de las dos es un
-- registro doble. Se conserva la primera (id 3) y se borra la 7: son los
-- 200000 que Contabilidad no encuentra en caja. (Si los valores fueran
-- distintos, habría que preguntar cuál se cobró de verdad antes de borrar.)
--
-- Conteos esperados, calculados antes de migrar:
--   inscripcion 7 (8 menos el duplicado)
--   participante 4 (Juliana, Mateo, Valeria, Esteban)
--   sede 2 (S1, S2)
--   curso 3 (C10, C20, C30)
-- ---------------------------------------------------------------------
\echo
\echo '-- (d) Migración del caso 3'
BEGIN;

-- Copia de la tabla original, solo para verificar con EXCEPT (se borra al COMMIT)
CREATE TEMP TABLE inscripcion_original ON COMMIT DROP AS SELECT * FROM inscripcion;

\echo '-- (d) Borrar la inscripción duplicada (esperado: DELETE 1, la fila 7)'
DELETE FROM inscripcion i
USING  inscripcion j
WHERE  i.doc_participante = j.doc_participante
  AND  i.cod_curso        = j.cod_curso
  AND  i.id > j.id;

CREATE TABLE participante (
    doc_participante     varchar(15)   PRIMARY KEY,
    nombre_participante  varchar(80)   NOT NULL,
    correo               varchar(120)  NOT NULL UNIQUE
);
INSERT INTO participante (doc_participante, nombre_participante, correo)
SELECT DISTINCT doc_participante, nombre_participante, correo FROM inscripcion;

CREATE TABLE sede (
    cod_sede        char(2)      PRIMARY KEY,
    direccion_sede  varchar(60)  NOT NULL
);
INSERT INTO sede (cod_sede, direccion_sede)
SELECT DISTINCT cod_sede, direccion_sede FROM inscripcion;

CREATE TABLE curso (
    cod_curso     char(3)      PRIMARY KEY,
    nombre_curso  varchar(60)  NOT NULL,
    cod_sede      char(2)      NOT NULL REFERENCES sede (cod_sede)
);
INSERT INTO curso (cod_curso, nombre_curso, cod_sede)
SELECT DISTINCT cod_curso, nombre_curso, cod_sede FROM inscripcion;

-- (e) Verificación, antes de quitar las columnas viejas
\echo '-- (e) Conteos: esperado inscripcion 7, participante 4, sede 2, curso 3'
SELECT (SELECT count(*) FROM inscripcion)  AS inscripcion,
       (SELECT count(*) FROM participante) AS participante,
       (SELECT count(*) FROM sede)         AS sede,
       (SELECT count(*) FROM curso)        AS curso;

\echo '-- (e) Filas distintas de la tabla original que NO se pueden reconstruir (esperado: 0 filas)'
SELECT doc_participante, nombre_participante, correo, cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado
FROM   inscripcion_original
EXCEPT
SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso, c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
FROM   inscripcion i
JOIN   participante p ON p.doc_participante = i.doc_participante
JOIN   curso c        ON c.cod_curso        = i.cod_curso
JOIN   sede s         ON s.cod_sede         = c.cod_sede;

\echo '-- (e) Filas reconstruidas que NO estaban en la tabla original (esperado: 0 filas)'
SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso, c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
FROM   inscripcion i
JOIN   participante p ON p.doc_participante = i.doc_participante
JOIN   curso c        ON c.cod_curso        = i.cod_curso
JOIN   sede s         ON s.cod_sede         = c.cod_sede
EXCEPT
SELECT doc_participante, nombre_participante, correo, cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado
FROM   inscripcion_original;

-- Verificado: se protege la clave natural, se agregan las FK y se quita lo viejo
ALTER TABLE inscripcion
    ADD CONSTRAINT inscripcion_participante_curso_key UNIQUE (doc_participante, cod_curso),
    ADD CONSTRAINT inscripcion_participante_fkey FOREIGN KEY (doc_participante) REFERENCES participante (doc_participante),
    ADD CONSTRAINT inscripcion_curso_fkey        FOREIGN KEY (cod_curso)        REFERENCES curso (cod_curso);
ALTER TABLE inscripcion
    DROP COLUMN nombre_participante,
    DROP COLUMN correo,
    DROP COLUMN nombre_curso,
    DROP COLUMN cod_sede,
    DROP COLUMN direccion_sede;

COMMIT;

\echo '-- (e) La queja, resuelta: lo recaudado por curso (esperado: Fotografía digital 380000)'
SELECT c.cod_curso, c.nombre_curso, count(*) AS inscripciones, sum(i.valor_pagado) AS recaudado
FROM   inscripcion i JOIN curso c ON c.cod_curso = i.cod_curso
GROUP BY c.cod_curso, c.nombre_curso
ORDER BY c.cod_curso;

\echo '-- (e) La clave natural protegida: inscribir otra vez a Juliana en C20 (esperado: NOTICE de rechazo)'
DO $$
BEGIN
    INSERT INTO cursos_libres.inscripcion (doc_participante, cod_curso, valor_pagado)
    VALUES ('1140000900', 'C20', 200000);
    RAISE NOTICE 'Se aceptó la inscripción repetida (no debía pasar)';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Rechazada, como debe ser: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- Pregunta propia: la tabla tiene una PK de una sola columna. ¿Por qué eso
-- no la pone en 2FN? ¿Qué restricción le faltaba y qué habría evitado?
--
-- La 2FN se revisa contra TODAS las claves candidatas, no solo contra la PK
-- declarada. Por la regla "un participante se inscribe a lo sumo una vez en
-- cada curso", (doc_participante, cod_curso) también identifica una fila: es
-- clave candidata aunque nadie la haya declarado. Y de una PARTE de ella
-- dependen atributos no primos: doc_participante -> nombre_participante
-- (y correo); cod_curso -> nombre_curso, cod_sede. Son dependencias
-- parciales: no está en 2FN. Agregar un id no normaliza nada; solo le
-- cambia el nombre a la PK (pre-lectura, sección 1).
--
-- Faltaba UNIQUE (doc_participante, cod_curso). Con esa restricción, la
-- segunda inscripción de Juliana en Fotografía digital (fila 7) se habría
-- rechazado al insertarla, y el curso no habría "recaudado" 200000 pesos
-- de más. Es la restricción que ahora tiene el esquema corregido.
-- ---------------------------------------------------------------------


-- #####################################################################
-- CASO 4: envios
-- envio (num_guia PK, fecha, ciudad_destino, departamento, zona, tarifa_kg,
--        peso_kg, valor)
-- Queja: "Un cliente de Bogotá reclama que le cobramos de más."
-- #####################################################################
SET search_path TO envios;
\echo
\echo '######## CASO 4: envios ########'

-- ---------------------------------------------------------------------
-- (a) Diagnóstico
--
-- Dependencias (reglas del negocio):
--   num_guia -> fecha, ciudad_destino, peso_kg
--   ciudad_destino -> departamento, zona        cada ciudad está en un departamento y una zona
--   zona -> tarifa_kg                           cada zona tiene una tarifa por kilo
--   valor = peso_kg * tarifa_kg                 el valor se CALCULA con otros datos
--
-- Problema principal (explica la queja): valor es un DATO DERIVADO guardado.
--   Se puede calcular, y como se guarda aparte, puede contradecir su cálculo:
--   la guía G07 (Bogotá, 4 kg, zona 2 a 6000/kg) tiene valor 42000, cuando
--   4 × 6000 = 24000. Se le cobraron 18000 de más. Es redundancia, no un
--   problema de forma normal en sentido estricto: el esquema no impide que el
--   valor guardado y el calculado difieran.
--
-- Problema secundario: dependencias TRANSITIVAS. num_guia -> ciudad_destino
--   -> departamento, zona, y zona -> tarifa_kg: NO ESTÁ EN 3FN. "Valle del
--   Cauca", la zona 1 y su tarifa de 4000 se repiten en cada envío a Cali o
--   Palmira; si la zona 1 sube de tarifa, hay que cambiar muchas filas.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (b) Evidencia
-- ---------------------------------------------------------------------
\echo '-- (b.1) La queja: envíos cuyo valor no coincide con peso × tarifa (esperado: G07, 42000 contra 24000)'
SELECT num_guia, fecha, ciudad_destino, peso_kg, tarifa_kg, valor,
       round(peso_kg * tarifa_kg)::integer           AS valor_calculado,
       valor - round(peso_kg * tarifa_kg)::integer   AS cobrado_de_mas
FROM   envio
WHERE  valor <> peso_kg * tarifa_kg;

\echo '-- (b.2) Los envíos a Bogotá (esperado: G03 bien, G07 mal)'
SELECT num_guia, peso_kg, tarifa_kg, valor, round(peso_kg * tarifa_kg)::integer AS valor_calculado
FROM   envio WHERE ciudad_destino = 'Bogotá' ORDER BY num_guia;

\echo '-- (b.3) Las dependencias transitivas no están contradichas (esperado: 0 filas)'
SELECT 'ciudad_destino -> departamento, zona' AS dependencia, ciudad_destino AS valor FROM envio
GROUP BY ciudad_destino HAVING count(DISTINCT departamento) > 1 OR count(DISTINCT zona) > 1
UNION ALL
SELECT 'zona -> tarifa_kg', zona::text FROM envio
GROUP BY zona HAVING count(DISTINCT tarifa_kg) > 1;

\echo '-- (b.4) Redundancia: cuántas veces está escrita la tarifa de cada zona (esperado: zona 1 3, zona 2 4, zona 3 1)'
SELECT zona, tarifa_kg, count(*) AS veces FROM envio GROUP BY zona, tarifa_kg ORDER BY zona;

-- ---------------------------------------------------------------------
-- (c) Esquema corregido
--   zona   (zona PK, tarifa_kg)
--   ciudad (ciudad PK, departamento, zona FK -> zona)
--   envio  (num_guia PK, fecha, ciudad_destino FK -> ciudad, peso_kg)
--   vista envio_valor: el valor se CALCULA (peso × tarifa), no se guarda.
-- (Supuesto: el nombre de la ciudad la identifica, como dice el enunciado.
-- En Colombia hay municipios con el mismo nombre en departamentos distintos;
-- en un sistema real la clave sería el código DANE, como en S18.)
-- La pregunta propia (más abajo) agrega un ajuste a este esquema.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- (d) Migración
-- Criterio de limpieza: el valor de G07 (42000) está mal y el peso (4.0 kg)
-- está bien. El peso se mide al recibir el paquete, y el cliente reclama
-- que se le cobró de más (si el peso real fuera 7 kg, 42000 sería correcto
-- y no habría reclamo). Por eso valor NO se migra: se calcula. Los 18000 de
-- diferencia son lo que la transportadora le debe devolver al cliente.
--
-- Conteos esperados, calculados antes de migrar:
--   zona 3 (1, 2, 3)
--   ciudad 5 (Cali, Palmira, Bogotá, Medellín, Pasto)
--   envio 8 (no cambia)
-- ---------------------------------------------------------------------
\echo
\echo '-- (d) Migración del caso 4'
BEGIN;

CREATE TEMP TABLE envio_original ON COMMIT DROP AS SELECT * FROM envio;

CREATE TABLE zona (
    zona       smallint  PRIMARY KEY,
    tarifa_kg  integer   NOT NULL CHECK (tarifa_kg > 0)
);
INSERT INTO zona (zona, tarifa_kg)
SELECT DISTINCT zona, tarifa_kg FROM envio;

CREATE TABLE ciudad (
    ciudad        varchar(40)  PRIMARY KEY,
    departamento  varchar(40)  NOT NULL,
    zona          smallint     NOT NULL REFERENCES zona (zona)
);
INSERT INTO ciudad (ciudad, departamento, zona)
SELECT DISTINCT ciudad_destino, departamento, zona FROM envio;

-- (e) Verificación, antes de quitar las columnas viejas
\echo '-- (e) Conteos: esperado zona 3, ciudad 5, envio 8'
SELECT (SELECT count(*) FROM zona)   AS zona,
       (SELECT count(*) FROM ciudad) AS ciudad,
       (SELECT count(*) FROM envio)  AS envio;

-- Quitar lo viejo y crear la vista con el valor calculado
ALTER TABLE envio ADD CONSTRAINT envio_ciudad_fkey FOREIGN KEY (ciudad_destino) REFERENCES ciudad (ciudad);
ALTER TABLE envio DROP COLUMN departamento, DROP COLUMN zona, DROP COLUMN tarifa_kg, DROP COLUMN valor;

CREATE VIEW envio_valor AS
SELECT e.num_guia, e.fecha, e.ciudad_destino, c.departamento, c.zona, z.tarifa_kg, e.peso_kg,
       round(e.peso_kg * z.tarifa_kg)::integer AS valor
FROM   envio e
JOIN   ciudad c ON c.ciudad = e.ciudad_destino
JOIN   zona   z ON z.zona   = c.zona;

\echo '-- (e) Datos originales (sin valor) que la vista NO reconstruye (esperado: 0 filas)'
SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg FROM envio_original
EXCEPT
SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg FROM envio_valor;

\echo '-- (e) Datos de la vista que NO estaban en la tabla original (esperado: 0 filas)'
SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg FROM envio_valor
EXCEPT
SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg FROM envio_original;

\echo '-- (e) El valor: la única diferencia con lo guardado es G07, la corrección (esperado: 1 fila)'
SELECT o.num_guia, o.valor AS valor_guardado, v.valor AS valor_calculado
FROM   envio_original o JOIN envio_valor v ON v.num_guia = o.num_guia
WHERE  o.valor <> v.valor;

COMMIT;

\echo '-- (e) La queja, resuelta: los envíos a Bogotá con el valor calculado (esperado: G03 6000 y G07 24000)'
SELECT num_guia, fecha, peso_kg, tarifa_kg, valor FROM envio_valor WHERE ciudad_destino = 'Bogotá' ORDER BY num_guia;

-- ---------------------------------------------------------------------
-- Pregunta propia: en enero suben las tarifas. Con el esquema corregido,
-- ¿qué pasa con el valor de los envíos de octubre? ¿Qué cambiar, y eso es
-- redundancia o no?
--
-- Con el esquema de (c), el valor se calcula con la tarifa ACTUAL de la zona.
-- Si en enero la zona 2 pasa de 6000 a 6600 por kilo, la vista recalcula
-- también los envíos de octubre: G03 dejaría de valer 6000 y pasaría a 6600,
-- aunque se cobró a 6000. La base estaría "reescribiendo" lo que se cobró.
-- Abajo se demuestra (dentro de BEGIN … ROLLBACK).
--
-- Lo que pasa es que "la tarifa de la zona" son dos datos distintos:
--   - la tarifa VIGENTE de la zona: zona -> tarifa_kg (cambia en enero);
--   - la tarifa CON QUE SE COBRÓ cada envío: num_guia -> tarifa_kg_aplicada
--     (es un hecho del día del envío y no cambia nunca).
-- Hoy coinciden, pero no son el mismo dato. Por eso se agrega a envio la
-- columna tarifa_kg_aplicada, copiada de la zona al registrar el envío, y el
-- valor se calcula con ella: peso_kg × tarifa_kg_aplicada.
--
-- ¿Es redundancia? NO. Un dato es redundante cuando se puede calcular SIEMPRE
-- con otros que ya están guardados. La tarifa aplicada no se puede calcular
-- después de enero: la tarifa de la zona ya será otra. Es un dato HISTÓRICO,
-- que solo se parece a uno redundante mientras la tarifa no cambia. El valor,
-- en cambio, sí sigue siendo derivado (peso × tarifa aplicada), así que se
-- sigue calculando en la vista y no se guarda.
-- (Otra opción válida: una tabla de tarifas por fecha, zona_tarifa(zona,
-- vigente_desde, tarifa_kg), y calcular cada envío con la tarifa vigente en
-- su fecha.)
-- ---------------------------------------------------------------------
\echo
\echo '-- Pregunta propia: subir la tarifa de la zona 2 con el esquema de (c) (esperado: G03 pasa de 6000 a 6600; se deshace)'
BEGIN;
UPDATE zona SET tarifa_kg = 6600 WHERE zona = 2;
SELECT num_guia, fecha, ciudad_destino, peso_kg, tarifa_kg, valor FROM envio_valor WHERE zona = 2 ORDER BY num_guia;
ROLLBACK;

\echo
\echo '-- Ajuste por la pregunta propia: guardar la tarifa aplicada a cada envío (dato histórico)'
BEGIN;
ALTER TABLE envio ADD COLUMN tarifa_kg_aplicada integer;
-- Los envíos de octubre se cobraron con la tarifa que tiene hoy su zona (no ha cambiado)
UPDATE envio e
SET    tarifa_kg_aplicada = z.tarifa_kg
FROM   ciudad c JOIN zona z ON z.zona = c.zona
WHERE  c.ciudad = e.ciudad_destino;
ALTER TABLE envio
    ALTER COLUMN tarifa_kg_aplicada SET NOT NULL,
    ADD CONSTRAINT envio_tarifa_aplicada_check CHECK (tarifa_kg_aplicada > 0);

CREATE OR REPLACE VIEW envio_valor AS
SELECT e.num_guia, e.fecha, e.ciudad_destino, c.departamento, c.zona,
       e.tarifa_kg_aplicada AS tarifa_kg, e.peso_kg,
       round(e.peso_kg * e.tarifa_kg_aplicada)::integer AS valor
FROM   envio e
JOIN   ciudad c ON c.ciudad = e.ciudad_destino;

\echo '-- Los 8 envíos tienen su tarifa aplicada (esperado: 8)'
SELECT count(*) AS envios_con_tarifa_aplicada FROM envio WHERE tarifa_kg_aplicada IS NOT NULL;
COMMIT;

\echo '-- Con el ajuste, subir la tarifa de la zona 2 (esperado: G03 sigue en 6000; se deshace)'
BEGIN;
UPDATE zona SET tarifa_kg = 6600 WHERE zona = 2;
SELECT num_guia, fecha, ciudad_destino, peso_kg, tarifa_kg, valor FROM envio_valor WHERE zona = 2 ORDER BY num_guia;
ROLLBACK;

\echo
\echo '== Fin de casos.sql: los cuatro esquemas quedaron migrados =='
