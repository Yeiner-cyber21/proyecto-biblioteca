-- =====================================================================
-- pruebas-restricciones.sql  ·  INSERT que el esquema DEBE rechazar
-- (entregable de S11, parte B: cada prueba ataca una regla de negocio distinta)
--
-- Uso, en la terminal:
--   docker compose exec postgres psql -U curso -d curso -f /scripts/pruebas-restricciones.sql
-- o en pgAdmin: pegar todo en el Query Tool y ejecutar (F5); los
-- resultados salen en la pestaña "Messages".
--
-- Cada prueba es un bloque DO que intenta el INSERT malo y atrapa SOLO el
-- error esperado. Si el esquema lo aceptara, o fallara por otro motivo,
-- el bloque lo dice (o el script se detiene): la prueba no "pasa" por accidente.
-- Todo termina en ROLLBACK: no deja ningún dato en la base.
-- =====================================================================

SET search_path TO biblioteca, public;

BEGIN;

-- Datos mínimos válidos, para que cada prueba falle SOLO por su regla
INSERT INTO usuario (documento, nombres, apellidos, correo, contrasena_hash, perfil) VALUES
    ('900000001', 'Lectora', 'De Prueba', 'lectora.prueba@correo-ejemplo.edu.co',
     crypt('900000001', gen_salt('bf')), 'lector'),
    ('900000002', 'Bibliotecario', 'De Prueba', 'biblio.prueba@correo-ejemplo.edu.co',
     crypt('900000002', gen_salt('bf')), 'bibliotecario');
INSERT INTO lector (id_usuario, telefono)
    SELECT id_usuario, '3009000001' FROM usuario WHERE documento = '900000001';
INSERT INTO bibliotecario (id_usuario)
    SELECT id_usuario FROM usuario WHERE documento = '900000002';
INSERT INTO categoria (nombre) VALUES ('Prueba');
INSERT INTO libro (isbn, titulo, anio_publicacion, id_categoria)
    SELECT '9789999999991', 'Libro de prueba', 2020, id_categoria FROM categoria WHERE nombre = 'Prueba';
INSERT INTO ejemplar (isbn, numero_copia) VALUES ('9789999999991', 1);

-- Prueba 1 · Un préstamo solo se le hace a un lector registrado (FK)
DO $$
BEGIN
    INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento)
    SELECT 999999, '9789999999991', 1, b.id_usuario, DATE '2026-10-01', DATE '2026-10-15'
    FROM bibliotecario b;
    RAISE NOTICE 'Prueba 1 FALLÓ: el esquema aceptó un préstamo a un lector inexistente';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Prueba 1 OK (lector inexistente) -> %', SQLERRM;
END $$;

-- Prueba 2 · La devolución no puede ser anterior al préstamo (CHECK)
DO $$
BEGIN
    INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario,
                          fecha_prestamo, fecha_vencimiento, fecha_devolucion)
    SELECT l.id_usuario, '9789999999991', 1, b.id_usuario,
           DATE '2026-10-10', DATE '2026-10-24', DATE '2026-10-05'
    FROM lector l CROSS JOIN bibliotecario b;
    RAISE NOTICE 'Prueba 2 FALLÓ: el esquema aceptó una devolución anterior al préstamo';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Prueba 2 OK (devolución antes del préstamo) -> %', SQLERRM;
END $$;

-- Prueba 3 · Un ejemplar no puede estar prestado dos veces a la vez (índice único parcial)
DO $$
BEGIN
    INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento)
    SELECT l.id_usuario, '9789999999991', 1, b.id_usuario, DATE '2026-10-01', DATE '2026-10-15'
    FROM lector l CROSS JOIN bibliotecario b;            -- primer préstamo: válido
    INSERT INTO prestamo (id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento)
    SELECT l.id_usuario, '9789999999991', 1, b.id_usuario, DATE '2026-10-02', DATE '2026-10-16'
    FROM lector l CROSS JOIN bibliotecario b;            -- misma copia, sin devolver la anterior
    RAISE NOTICE 'Prueba 3 FALLÓ: el esquema aceptó prestar dos veces el mismo ejemplar';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Prueba 3 OK (ejemplar ya prestado) -> %', SQLERRM;
END $$;

-- Prueba extra · Las contraseñas no se guardan en texto plano (sección 6.2 del proyecto)
DO $$
BEGIN
    INSERT INTO usuario (documento, nombres, apellidos, correo, contrasena_hash, perfil)
    VALUES ('900000003', 'Auditor', 'De Prueba', 'auditor.prueba@correo-ejemplo.edu.co', 'clave123', 'auditor');
    RAISE NOTICE 'Prueba extra FALLÓ: el esquema aceptó una contraseña en texto plano';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Prueba extra OK (contraseña sin hash) -> %', SQLERRM;
END $$;

ROLLBACK;   -- deshace los datos mínimos: la base queda como estaba
