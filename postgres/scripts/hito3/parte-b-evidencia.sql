-- =====================================================================
-- parte-b-evidencia.sql  ·  S19, Parte B: examen del esquema "biblioteca"
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Una consulta de evidencia por tabla, para la tabla de la Parte B
-- (docs/hito3/S19-taller-esquemas.md). Solo LEE: no cambia nada del proyecto.
-- En esta sesión no se migra el proyecto; los cambios propuestos son para S20.
--
-- Requisito: el esquema con los datos cargados (cargas de S14 y datos-prueba.sql).
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/parte-b-evidencia.sql
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO biblioteca;

\echo
\echo '== usuario: las claves naturales (documento, correo) no se repiten (esperado: 0 y 0) =='
SELECT (SELECT count(*) FROM (SELECT documento FROM usuario GROUP BY documento HAVING count(*) > 1) d) AS documentos_repetidos,
       (SELECT count(*) FROM (SELECT correo    FROM usuario GROUP BY correo    HAVING count(*) > 1) c) AS correos_repetidos;

\echo '== usuario: perfil frente a las tablas lector y bibliotecario (dos fuentes del mismo dato; esperado: 0 contradicciones) =='
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

\echo '== lector: un teléfono por lector, en una sola columna (esperado: 0 teléfonos con separadores) =='
SELECT count(*) AS telefonos_con_varios_valores FROM lector WHERE telefono !~ '^[0-9]+$';

\echo '== categoria: ¿nombres que solo cambian en mayúsculas? (esperado: 0 filas) =='
SELECT lower(nombre) AS nombre, count(*) FROM categoria GROUP BY lower(nombre) HAVING count(*) > 1;

\echo '== autor: ¿nombres que solo cambian en mayúsculas o espacios? (esperado: 0 filas) =='
SELECT lower(trim(nombre)) AS nombre, count(*) FROM autor GROUP BY lower(trim(nombre)) HAVING count(*) > 1;

\echo '== libro: la categoría se guarda como FK, no como texto repetido (esperado: libros por categoría, sin nombres copiados) =='
SELECT c.nombre AS categoria, count(*) AS libros
FROM   libro l JOIN categoria c ON c.id_categoria = l.id_categoria
GROUP BY c.nombre ORDER BY libros DESC, c.nombre LIMIT 5;

\echo '== libro: los ejemplares disponibles NO se guardan; se calculan (esperado: los 5 libros con más copias prestadas ahora) =='
SELECT l.isbn, l.titulo,
       count(*) FILTER (WHERE e.estado = 'activo')                   AS copias_activas,
       count(p.id_prestamo)                                          AS prestadas_ahora,
       count(*) FILTER (WHERE e.estado = 'activo') - count(p.id_prestamo) AS disponibles
FROM   libro l
JOIN   ejemplar e ON e.isbn = l.isbn
LEFT JOIN prestamo p ON p.isbn = e.isbn AND p.numero_copia = e.numero_copia AND p.fecha_devolucion IS NULL
GROUP BY l.isbn, l.titulo
ORDER BY prestadas_ahora DESC, l.titulo
LIMIT 5;

\echo '== libro_autor: ¿pares repetidos? (esperado: 0 filas; la PK lo impide) =='
SELECT isbn, id_autor, count(*) FROM libro_autor GROUP BY isbn, id_autor HAVING count(*) > 1;

\echo '== ejemplar: libros con copias en estados distintos (esperado: 0, porque hoy todas las copias están activas; el estado es de cada copia) =='
SELECT count(*) AS libros_con_copias_en_estados_distintos
FROM  (SELECT isbn FROM ejemplar GROUP BY isbn HAVING count(DISTINCT estado) > 1) x;

\echo '== prestamo: ¿fecha_vencimiento es siempre fecha_prestamo + 14? (dato que PARECE derivado) =='
SELECT count(*)                                                        AS prestamos,
       count(*) FILTER (WHERE fecha_vencimiento = fecha_prestamo + 14) AS con_plazo_14,
       count(*) FILTER (WHERE fecha_vencimiento <> fecha_prestamo + 14) AS con_otro_plazo
FROM   prestamo;

\echo '== prestamo: la mora NO se guarda como estado; se calcula (esperado: 5 préstamos en mora) =='
SELECT count(*) AS prestamos_en_mora
FROM   prestamo WHERE fecha_devolucion IS NULL AND fecha_vencimiento < CURRENT_DATE;

\echo '== prestamo: ¿hay una clave natural? Mismo ejemplar prestado dos veces el mismo día (esperado: 0 filas hoy, pero la regla no lo prohíbe) =='
SELECT isbn, numero_copia, fecha_prestamo, count(*)
FROM   prestamo GROUP BY isbn, numero_copia, fecha_prestamo HAVING count(*) > 1;

\echo '== prestamo: reglas que el esquema NO garantiza todavía (esperado: 0 lectores con más de 3 abiertos) =='
SELECT count(*) AS lectores_con_mas_de_3_abiertos
FROM  (SELECT id_lector FROM prestamo WHERE fecha_devolucion IS NULL GROUP BY id_lector HAVING count(*) > 3) x;

\echo '== carga.rechazo_carga: líneas registradas en varias corridas (esperado: 0 en una carga desde cero; aparecen si se repite una carga con errores) =='
SELECT archivo, linea, count(*) AS veces
FROM   carga.rechazo_carga GROUP BY archivo, linea HAVING count(*) > 1
ORDER BY veces DESC, archivo, linea LIMIT 3;
