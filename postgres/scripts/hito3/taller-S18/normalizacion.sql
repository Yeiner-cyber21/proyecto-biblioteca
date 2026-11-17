-- =====================================================================
-- normalizacion.sql  ·  S18, Parte B: la planilla de El Pistón llevada a 3FN
--
-- Requisito: haber corrido antes S18-automotriz.sql, que crea el esquema
-- "automotriz" con la tabla plana servicio_plano (11 filas, 6 órdenes).
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S18/S18-automotriz.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S18/normalizacion.sql
--
-- Re-ejecutable: borra y vuelve a crear sus propias tablas y la vista.
-- La guía pide hacer (e) después de (d), porque (e) modifica los datos.
-- Aquí cada prueba de (e) corre dentro de BEGIN … ROLLBACK: muestra el efecto
-- y lo deshace, así que el script deja las tablas completas y se puede repetir.
--
-- Esquema 3FN (el análisis paso a paso está en docs/hito3/S18-taller-normalizacion.md, A2):
--   dueno          (cedula_dueno PK, nombre_dueno, telefono_dueno)
--   modelo         (modelo PK, marca)
--   vehiculo       (placa PK, modelo → modelo, cedula_dueno → dueno)
--   orden          (num_orden PK, fecha_ingreso, kilometraje, placa → vehiculo)
--   servicio       (cod_servicio PK, nombre_servicio, precio_lista)
--   mecanico       (cod_mecanico PK, nombre_mecanico)
--   orden_servicio (num_orden → orden (ON DELETE CASCADE), cod_servicio → servicio,
--                   precio_cobrado, cod_mecanico → mecanico)
--                   PK (num_orden, cod_servicio)
--
-- Regla de S17 que guía todo: en cada tabla, el determinante de cada
-- dependencia no trivial es la clave de esa tabla.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO automotriz;

-- Limpiar lo que dejó una corrida anterior de este script (no toca servicio_plano)
DROP VIEW  IF EXISTS reconstruida;
DROP TABLE IF EXISTS orden_servicio, orden, vehiculo, modelo, dueno, servicio, mecanico CASCADE;


-- =====================================================================
-- (a) Datos que contradicen las dependencias funcionales (técnica de S17)
--
-- Para cada dependencia X → Y: se agrupa por X y se buscan los grupos con
-- más de un valor de Y. Si una dependencia que el negocio dice que existe
-- devuelve filas, el problema son los datos, y se limpian ANTES de separar
-- la tabla: si no, el SELECT DISTINCT de la parte (c) sacaría dos filas
-- con la misma clave y la PRIMARY KEY las rechazaría.
-- =====================================================================
\echo
\echo '== (a) Datos que contradicen las dependencias (0 filas = no hay contradicción) =='

\echo '-- D1: num_orden -> fecha_ingreso, kilometraje, placa'
SELECT   num_orden
FROM     servicio_plano
GROUP BY num_orden
HAVING   count(DISTINCT fecha_ingreso) > 1
      OR count(DISTINCT kilometraje)   > 1
      OR count(DISTINCT placa)         > 1;

\echo '-- D2: placa -> modelo, cedula_dueno'
SELECT   placa
FROM     servicio_plano
GROUP BY placa
HAVING   count(DISTINCT modelo)       > 1
      OR count(DISTINCT cedula_dueno) > 1;

\echo '-- D3: modelo -> marca'
SELECT   modelo
FROM     servicio_plano
GROUP BY modelo
HAVING   count(DISTINCT marca) > 1;

\echo '-- D4: cedula_dueno -> nombre_dueno, telefono_dueno'
SELECT   cedula_dueno,
         count(DISTINCT nombre_dueno)                                AS nombres,
         count(DISTINCT telefono_dueno)                              AS telefonos,
         string_agg(DISTINCT telefono_dueno, ' / ')                  AS valores_telefono
FROM     servicio_plano
GROUP BY cedula_dueno
HAVING   count(DISTINCT nombre_dueno)   > 1
      OR count(DISTINCT telefono_dueno) > 1;

\echo '-- D5: cod_servicio -> nombre_servicio, precio_lista'
SELECT   cod_servicio
FROM     servicio_plano
GROUP BY cod_servicio
HAVING   count(DISTINCT nombre_servicio) > 1
      OR count(DISTINCT precio_lista)    > 1;

\echo '-- D6: cod_mecanico -> nombre_mecanico'
SELECT   cod_mecanico
FROM     servicio_plano
GROUP BY cod_mecanico
HAVING   count(DISTINCT nombre_mecanico) > 1;

-- D7 (num_orden, cod_servicio -> precio_cobrado, cod_mecanico) no necesita
-- consulta: (num_orden, cod_servicio) es la PRIMARY KEY de servicio_plano,
-- así que no puede haber dos filas con la misma pareja.

-- Resultado: solo falla cedula_dueno -> telefono_dueno.
-- Jorge Mejía (cédula 16700002) aparece con dos teléfonos:
--   3104445566 en 4 filas (órdenes 5002 y 5003)
--   3104445567 en 1 fila  (orden 5006)
-- Una persona tiene un solo teléfono registrado, así que uno de los dos sobra.
-- Decisión: el correcto es 3104445566. Aparece en 4 de las 5 filas y en dos
-- órdenes distintas, y el otro solo cambia el último dígito, lo que apunta a
-- un error de digitación en la orden 5006. (Si el taller confirmara que Jorge
-- cambió de número, se dejaría el de la orden más reciente; en cualquier caso,
-- debe quedar UN solo teléfono por cédula.)
-- La corrección se hace sobre TODAS las filas de esa cédula, no solo en una:
-- corregir una sola fila sería repetir la anomalía de modificación de S17.
\echo
\echo '-- Corrección: el teléfono de Jorge Mejía (esperado: UPDATE 1; UPDATE 0 si el script ya se había corrido)'
UPDATE servicio_plano
SET    telefono_dueno = '3104445566'
WHERE  cedula_dueno   = '16700002'
  AND  telefono_dueno <> '3104445566';

\echo '-- cedula_dueno -> telefono_dueno, después de corregir (esperado: 0 filas)'
SELECT   cedula_dueno
FROM     servicio_plano
GROUP BY cedula_dueno
HAVING   count(DISTINCT telefono_dueno) > 1;

-- Dependencias que NO se cumplen (y por eso esas columnas no se mueven con
-- el determinante que uno pensaría):
--   placa -/-> kilometraje        ABC123 tiene 45200 km en la orden 5001 y 46900 en la 5004:
--                                 el kilometraje es de la ORDEN, no del vehículo.
--   cod_servicio -/-> precio_cobrado  el cambio de aceite se cobró 120000 y 110000:
--                                 el precio cobrado es de la LÍNEA de la orden.
--   num_orden -/-> cod_mecanico   en la orden 5001 trabajaron M01 y M02:
--                                 el mecánico es de cada servicio de la orden.


-- =====================================================================
-- (b) Las tablas del esquema 3FN
-- Cada tabla nace de un determinante, que pasa a ser su PRIMARY KEY.
-- Los tipos son los mismos de servicio_plano, para que el EXCEPT de (d)
-- compare columna con columna.
-- =====================================================================
\echo
\echo '== (b) Tablas del esquema 3FN =='

-- cedula_dueno -> nombre_dueno, telefono_dueno
CREATE TABLE dueno (
    cedula_dueno    varchar(15)  PRIMARY KEY,
    nombre_dueno    varchar(80)  NOT NULL,
    telefono_dueno  varchar(15)  NOT NULL
);

-- modelo -> marca
CREATE TABLE modelo (
    modelo  varchar(30)  PRIMARY KEY,
    marca   varchar(30)  NOT NULL
);

-- placa -> modelo, cedula_dueno (el dueño ACTUAL del vehículo)
CREATE TABLE vehiculo (
    placa         char(6)      PRIMARY KEY,
    modelo        varchar(30)  NOT NULL REFERENCES modelo (modelo),
    cedula_dueno  varchar(15)  NOT NULL REFERENCES dueno (cedula_dueno)
);

-- num_orden -> fecha_ingreso, kilometraje, placa
CREATE TABLE orden (
    num_orden      integer  PRIMARY KEY,
    fecha_ingreso  date     NOT NULL,
    kilometraje    integer  NOT NULL CHECK (kilometraje >= 0),
    placa          char(6)  NOT NULL REFERENCES vehiculo (placa)
);

-- cod_servicio -> nombre_servicio, precio_lista
CREATE TABLE servicio (
    cod_servicio     char(3)      PRIMARY KEY,
    nombre_servicio  varchar(60)  NOT NULL,
    precio_lista     integer      NOT NULL CHECK (precio_lista > 0)
);

-- cod_mecanico -> nombre_mecanico
CREATE TABLE mecanico (
    cod_mecanico     char(3)      PRIMARY KEY,
    nombre_mecanico  varchar(80)  NOT NULL
);

-- num_orden, cod_servicio -> precio_cobrado, cod_mecanico
-- ON DELETE CASCADE: las líneas son parte de la orden; si se borra la orden,
-- se borran sus líneas (y nada más: vehículo, dueño, servicio y mecánico quedan).
CREATE TABLE orden_servicio (
    num_orden       integer  NOT NULL REFERENCES orden (num_orden) ON DELETE CASCADE,
    cod_servicio    char(3)  NOT NULL REFERENCES servicio (cod_servicio),
    precio_cobrado  integer  NOT NULL CHECK (precio_cobrado > 0),
    cod_mecanico    char(3)  NOT NULL REFERENCES mecanico (cod_mecanico),
    PRIMARY KEY (num_orden, cod_servicio)
);


-- =====================================================================
-- (c) Carga con INSERT INTO … SELECT DISTINCT … FROM servicio_plano
-- Orden: primero las tablas a las que nadie apunta con FK y después las
-- que apuntan a ellas (dueno y modelo → vehiculo → orden; servicio y
-- mecanico → orden_servicio). El DISTINCT es lo que elimina la redundancia.
-- =====================================================================
\echo
\echo '== (c) Carga de las tablas =='

INSERT INTO dueno (cedula_dueno, nombre_dueno, telefono_dueno)
SELECT DISTINCT cedula_dueno, nombre_dueno, telefono_dueno FROM servicio_plano;      -- 3

INSERT INTO modelo (modelo, marca)
SELECT DISTINCT modelo, marca FROM servicio_plano;                                   -- 4

INSERT INTO vehiculo (placa, modelo, cedula_dueno)
SELECT DISTINCT placa, modelo, cedula_dueno FROM servicio_plano;                     -- 4

INSERT INTO orden (num_orden, fecha_ingreso, kilometraje, placa)
SELECT DISTINCT num_orden, fecha_ingreso, kilometraje, placa FROM servicio_plano;    -- 6

INSERT INTO servicio (cod_servicio, nombre_servicio, precio_lista)
SELECT DISTINCT cod_servicio, nombre_servicio, precio_lista FROM servicio_plano;     -- 5

INSERT INTO mecanico (cod_mecanico, nombre_mecanico)
SELECT DISTINCT cod_mecanico, nombre_mecanico FROM servicio_plano;                   -- 3

-- Sin DISTINCT: (num_orden, cod_servicio) es la clave de la planilla, no se repite
INSERT INTO orden_servicio (num_orden, cod_servicio, precio_cobrado, cod_mecanico)
SELECT num_orden, cod_servicio, precio_cobrado, cod_mecanico FROM servicio_plano;    -- 11

\echo
\echo '-- Filas por tabla (esperado: 3, 4, 4, 6, 5, 3 y 11)'
SELECT 'dueno' AS tabla, count(*) AS filas FROM dueno
UNION ALL SELECT 'modelo',         count(*) FROM modelo
UNION ALL SELECT 'vehiculo',       count(*) FROM vehiculo
UNION ALL SELECT 'orden',          count(*) FROM orden
UNION ALL SELECT 'servicio',       count(*) FROM servicio
UNION ALL SELECT 'mecanico',       count(*) FROM mecanico
UNION ALL SELECT 'orden_servicio', count(*) FROM orden_servicio;


-- =====================================================================
-- (d) Reconstruir la planilla y comprobar que no sobra ni falta nada
-- La vista junta las 7 tablas, con las columnas en el mismo orden de
-- servicio_plano. Cada JOIN se hace por la clave de una de las dos
-- tablas (la FK apunta a una PK), así que cada fila de orden_servicio
-- encuentra exactamente una orden, un vehículo, un modelo, un dueño, un
-- servicio y un mecánico: no aparecen tuplas espurias.
-- =====================================================================
\echo
\echo '== (d) Reconstrucción de la planilla =='

CREATE VIEW reconstruida AS
SELECT o.num_orden,
       o.fecha_ingreso,
       o.kilometraje,
       v.placa,
       v.modelo,
       mo.marca,
       d.cedula_dueno,
       d.nombre_dueno,
       d.telefono_dueno,
       s.cod_servicio,
       s.nombre_servicio,
       s.precio_lista,
       os.precio_cobrado,
       me.cod_mecanico,
       me.nombre_mecanico
FROM   orden_servicio os
JOIN   orden    o  ON o.num_orden     = os.num_orden
JOIN   vehiculo v  ON v.placa         = o.placa
JOIN   modelo   mo ON mo.modelo       = v.modelo
JOIN   dueno    d  ON d.cedula_dueno  = v.cedula_dueno
JOIN   servicio s  ON s.cod_servicio  = os.cod_servicio
JOIN   mecanico me ON me.cod_mecanico = os.cod_mecanico;

\echo '-- Filas: planilla y reconstrucción (esperado: 11 y 11)'
SELECT (SELECT count(*) FROM servicio_plano)        AS planilla,
       (SELECT count(*) FROM reconstruida) AS reconstruida;

\echo '-- Sobra en la reconstrucción: filas que no estaban en la planilla (esperado: 0 filas)'
SELECT * FROM reconstruida
EXCEPT
SELECT * FROM servicio_plano;

\echo '-- Falta en la reconstrucción: filas de la planilla que se perdieron (esperado: 0 filas)'
SELECT * FROM servicio_plano
EXCEPT
SELECT * FROM reconstruida;

-- EXCEPT compara conjuntos (quita repetidos). Por eso también se cuentan
-- las filas: 11 = 11 y los dos EXCEPT vacíos, y como servicio_plano no
-- tiene filas repetidas (tiene PK), las dos tablas son exactamente iguales.
-- Ojo: se compara contra la planilla YA CORREGIDA en (a).


-- =====================================================================
-- (e) Las tres anomalías de S17 ya no ocurren
-- Una sentencia por anomalía, como pide la guía: cambiar un teléfono,
-- registrar un mecánico sin servicios y borrar órdenes sin perder el
-- vehículo ni el servicio del catálogo. Cada una corre dentro de
-- BEGIN … ROLLBACK: muestra el efecto y lo deshace.
-- =====================================================================
\echo
\echo '== (e) Las tres anomalías de S17, en el esquema 3FN =='

-- ---------------------------------------------------------------------
-- Modificación. Jorge Mejía cambia de teléfono.
-- En la planilla había que actualizar sus 5 filas (y en (a) se vio lo que
-- pasa cuando una se queda atrás). Aquí el teléfono está en UNA fila de
-- dueno: un solo UPDATE lo cambia para todas sus órdenes y vehículos.
-- ---------------------------------------------------------------------
\echo
\echo '-- Modificación: un UPDATE de 1 fila (esperado: UPDATE 1)'
BEGIN;
UPDATE dueno SET telefono_dueno = '3209998877' WHERE cedula_dueno = '16700002';

\echo '-- Todas las líneas de Jorge ven el teléfono nuevo (esperado: 5 filas, todas con 3209998877)'
SELECT num_orden, cod_servicio, nombre_dueno, telefono_dueno
FROM   reconstruida
WHERE  cedula_dueno = '16700002'
ORDER BY num_orden, cod_servicio;
ROLLBACK;

-- ---------------------------------------------------------------------
-- Inserción. Se registra un mecánico recién contratado, que todavía no ha
-- hecho ningún servicio.
-- En la planilla no se podía: la clave es (num_orden, cod_servicio) y no
-- admite NULL, así que un mecánico solo existía "dentro" de un servicio.
-- ---------------------------------------------------------------------
\echo
\echo '-- Inserción: un mecánico nuevo, sin servicios (esperado: INSERT 0 1)'
BEGIN;
INSERT INTO mecanico (cod_mecanico, nombre_mecanico) VALUES ('M04', 'Luis Carvajal');

\echo '-- Quedó registrado, con 0 servicios (esperado: 1 fila)'
SELECT m.cod_mecanico, m.nombre_mecanico,
       (SELECT count(*) FROM orden_servicio os WHERE os.cod_mecanico = m.cod_mecanico) AS servicios
FROM   mecanico m
WHERE  m.cod_mecanico = 'M04';
ROLLBACK;

-- ---------------------------------------------------------------------
-- Borrado. Se borran las órdenes 5003 y 5005 con UNA sentencia (sus
-- líneas se van con ellas por el ON DELETE CASCADE).
-- En la planilla, borrar esas filas hacía desaparecer información que nadie
-- quería borrar: la 5005 es la única orden del Duster JKL012 y de su dueño,
-- Camilo Ibarra, y la 5003 es la única vez que se hizo el cambio de batería
-- (BAT), así que se perdían el vehículo, el dueño y el servicio del catálogo.
-- Aquí solo se borran las órdenes y sus líneas.
-- ---------------------------------------------------------------------
\echo
\echo '-- Borrado: las órdenes 5003 y 5005 (esperado: DELETE 2; sus 5 líneas se borran en cascada)'
BEGIN;
DELETE FROM orden WHERE num_orden IN (5003, 5005);

\echo '-- Quedan 4 órdenes y 6 líneas (esperado: 4 y 6)'
SELECT (SELECT count(*) FROM orden)          AS ordenes,
       (SELECT count(*) FROM orden_servicio) AS lineas_de_orden;

\echo '-- Siguen existiendo el vehículo, el dueño y el servicio del catálogo (esperado: 3 filas)'
SELECT 'vehiculo' AS que, placa AS codigo, modelo AS dato
FROM   vehiculo WHERE placa = 'JKL012'
UNION ALL
SELECT 'dueno', cedula_dueno, nombre_dueno || ', tel. ' || telefono_dueno
FROM   dueno WHERE cedula_dueno = '1144000003'
UNION ALL
SELECT 'servicio', cod_servicio, nombre_servicio || ', $' || precio_lista
FROM   servicio WHERE cod_servicio = 'BAT';
ROLLBACK;

\echo
\echo '-- Después de los ROLLBACK, las tablas siguen completas (esperado: 11 líneas de orden y 6 órdenes)'
SELECT (SELECT count(*) FROM orden_servicio) AS lineas_de_orden,
       (SELECT count(*) FROM orden)          AS ordenes;
