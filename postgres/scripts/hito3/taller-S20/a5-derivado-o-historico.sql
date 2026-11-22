-- =====================================================================
-- a5-derivado-o-historico.sql  ·  S20, Parte A5: ¿fecha_esperada es redundante?
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: haber corrido S20-rendimiento.sql y los pasos A1 a A4.
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a5-derivado-o-historico.sql
--
-- La pregunta: con la regla por defecto (plazo de 14 días), fecha_esperada
-- se puede calcular como fecha_prestamo + 14. ¿Guardarla es redundancia?
-- Depende de la REGLA DEL NEGOCIO, no de los datos (S17, sección 5.2):
--   - Si el plazo NUNCA cambia y no hay excepciones: es un dato DERIVADO.
--   - Si el plazo PUEDE cambiar o hay plazos especiales: es un dato
--     HISTÓRICO del préstamo, y guardarlo es correcto en 3FN.
--
-- Este script no deja cambios: lo que modifica va en una tabla temporal o
-- dentro de BEGIN … ROLLBACK.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO rendimiento;

\echo
\echo '== A5. Hoy, ¿todos los préstamos cumplen fecha_esperada = fecha_prestamo + 14? (esperado: los 307751, ninguno con otro plazo) =='
SELECT count(*)                                                       AS prestamos,
       count(*) FILTER (WHERE fecha_esperada =  fecha_prestamo + 14)  AS con_plazo_14,
       count(*) FILTER (WHERE fecha_esperada <> fecha_prestamo + 14)  AS con_otro_plazo
FROM   prestamo;
-- Con los datos de hoy, PARECE derivada. Pero los datos solo pueden
-- refutar una regla, no probarla: hay que preguntarle al negocio.

-- ---------------------------------------------------------------------
-- Escenario 1: el plazo NUNCA cambia y no hay excepciones.
--   fecha_esperada = fecha_prestamo + 14 SIEMPRE: es un dato DERIVADO, y
--   guardarlo aparte es redundancia (alguien podría escribir otra fecha y
--   la base se contradiría). Lo correcto sería calcularla en la consulta, o
--   guardarla como COLUMNA GENERADA, que el DBMS calcula y nadie puede
--   escribir a mano.
-- ---------------------------------------------------------------------
\echo
\echo '== Escenario 1: si el plazo nunca cambia, una columna generada (demostración en una tabla temporal) =='
CREATE TEMP TABLE prestamo_demo (
    id              integer  PRIMARY KEY,
    fecha_prestamo  date     NOT NULL,
    fecha_esperada  date     GENERATED ALWAYS AS (fecha_prestamo + 14) STORED
);
INSERT INTO prestamo_demo (id, fecha_prestamo) VALUES (1, DATE '2026-11-01');
\echo '-- La calcula el DBMS (esperado: 2026-11-15)'
SELECT * FROM prestamo_demo;
\echo '-- Y nadie puede escribirla a mano (esperado: NOTICE con "can only be updated to DEFAULT")'
DO $$
BEGIN
    UPDATE prestamo_demo SET fecha_esperada = DATE '2026-12-31';
    RAISE NOTICE 'Se cambió (no debía pasar)';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado, como debe ser: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- Escenario 2: la biblioteca CAMBIA el plazo (pasa a 21 días).
--   Si fecha_esperada se calculara con la regla nueva, también cambiaría
--   la fecha de los préstamos VIEJOS, que se hicieron con 14 días.
-- ---------------------------------------------------------------------
\echo
\echo '== Escenario 2: el plazo pasa a 21 días. Préstamos abiertos en mora con la fecha GUARDADA frente a RECALCULADA con la regla nueva =='
\echo '   (esperado, si se corre el mismo día que S20-rendimiento.sql: 2250 contra 1250; otro día cambian los números, pero la recalculada nunca da más)'
SELECT count(*) FILTER (WHERE fecha_esperada      < CURRENT_DATE) AS en_mora_con_fecha_guardada,
       count(*) FILTER (WHERE fecha_prestamo + 21 < CURRENT_DATE) AS en_mora_si_se_recalcula_con_21,
       count(*) FILTER (WHERE fecha_esperada      < CURRENT_DATE)
     - count(*) FILTER (WHERE fecha_prestamo + 21 < CURRENT_DATE) AS salen_de_mora_sin_devolver_nada
FROM   prestamo
WHERE  fecha_devolucion IS NULL;
-- Esos préstamos se hicieron con un plazo de 14 días y ya vencieron.
-- Recalcular con 21 los "perdona" sin que nadie haya devuelto nada.

-- ---------------------------------------------------------------------
-- Escenario 2b: plazos especiales. Un lector RENUEVA un préstamo vencido:
-- la biblioteca le da 14 días más. La fecha guardada cambia; la regla
-- "fecha_prestamo + 14" ya no la describe.
-- ---------------------------------------------------------------------
\echo
\echo '== Escenario 2b: renovar un préstamo vencido (se deshace con ROLLBACK) =='
BEGIN;
UPDATE prestamo
SET    fecha_esperada = fecha_esperada + 14
WHERE  id = (SELECT min(id)
             FROM   prestamo
             WHERE  fecha_devolucion IS NULL
               AND  fecha_prestamo + 14 <  CURRENT_DATE
               AND  fecha_prestamo + 28 >= CURRENT_DATE)
RETURNING id AS renovado \gset

\echo '-- Con la fecha GUARDADA no está en mora; si se calculara con + 14, sí (esperado: no / sí)'
SELECT id,
       fecha_prestamo,
       fecha_esperada                                                   AS fecha_guardada,
       fecha_prestamo + 14                                              AS fecha_si_se_calcula,
       CASE WHEN fecha_esperada      < CURRENT_DATE THEN 'sí' ELSE 'no' END AS en_mora_con_guardada,
       CASE WHEN fecha_prestamo + 14 < CURRENT_DATE THEN 'sí' ELSE 'no' END AS en_mora_si_se_calcula
FROM   prestamo
WHERE  id = :renovado;
ROLLBACK;

-- ---------------------------------------------------------------------
-- Conclusión
--   - Plazo fijo, sin excepciones: fecha_esperada es DERIVADA. Guardarla
--     es redundancia; se calcula o se usa una columna generada.
--   - Plazo que puede cambiar, o plazos especiales (renovaciones, libros de
--     referencia): la fecha esperada de cada préstamo es un HECHO HISTÓRICO
--     del préstamo. Depende de id (la clave), no de una regla actual, así
--     que guardarla es correcto en 3FN. Calcularla con la regla nueva
--     cambiaría las fechas de los préstamos viejos y haría aparecer o
--     desaparecer moras (escenario 2).
--   Es la misma distinción del caso 4 del S19 (tarifa aplicada a un envío).
--
-- En nuestro proyecto: prestamo.fecha_vencimiento se GUARDA, porque la
-- biblioteca puede ajustar el plazo y se prevén renovaciones. Es dato
-- histórico, no redundancia (S19, Parte B, tabla prestamo).
-- ---------------------------------------------------------------------
