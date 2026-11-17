-- S16. Taller de consultas complejas · Parte A
-- Esquema: tienda (crearlo antes con S16-tienda.sql)
--
-- Uso (PowerShell, desde la carpeta del proyecto; antes, S16-tienda.sql):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/taller-S16/parte-a.sql
--
-- "Sin cancelados" quiere decir: sin los pedidos con estado = 'cancelado'.
-- El valor de una línea es cantidad * precio_unitario, no producto.precio,
-- porque el precio de hoy puede no ser el de la venta.

\pset pager off

SET search_path TO tienda;

-- ---------------------------------------------------------------
-- Ejercicio 1. Pedido 1003: cliente, productos, cantidad y subtotal.
-- Filas esperadas: 2.
-- Se recorre pedido -> cliente y pedido -> detalle -> producto.
-- ---------------------------------------------------------------
\echo '== Ejercicio 1 (esperadas: 2) =='
SELECT c.nombre                         AS cliente,
       pr.nombre                        AS producto,
       d.cantidad,
       d.cantidad * d.precio_unitario   AS subtotal
FROM   pedido p
JOIN   cliente  c  ON c.id_cliente   = p.id_cliente
JOIN   detalle  d  ON d.id_pedido    = p.id_pedido
JOIN   producto pr ON pr.id_producto = d.id_producto
WHERE  p.id_pedido = 1003
ORDER BY pr.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 2. Cada cliente con el nombre de quien lo refirió.
-- Filas esperadas: 8.
-- Self-join: cliente aparece dos veces, con dos alias. Es LEFT JOIN
-- para conservar a los que llegaron solos (referido_por NULL).
-- ---------------------------------------------------------------
\echo '== Ejercicio 2 (esperadas: 8) =='
SELECT c.nombre  AS cliente,
       r.nombre  AS referido_por
FROM   cliente c
LEFT JOIN cliente r ON r.id_cliente = c.referido_por
ORDER BY c.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 3. Productos que nunca se han vendido (ni en cancelados).
-- Filas esperadas: 1.
-- Anti-join: el LEFT JOIN deja en NULL los productos sin detalle.
-- Aquí no se filtra por estado: el enunciado cuenta también los
-- pedidos cancelados.
-- ---------------------------------------------------------------
\echo '== Ejercicio 3 (esperadas: 1) =='
SELECT pr.nombre
FROM   producto pr
LEFT JOIN detalle d ON d.id_producto = pr.id_producto
WHERE  d.id_producto IS NULL;

-- ---------------------------------------------------------------
-- Ejercicio 4. Cada cliente con su número de pedidos, incluidos los
-- cancelados, mostrando 0 para quien no tiene ninguno.
-- Filas esperadas: 8.
-- Se cuenta p.id_pedido y no *: con count(*) el cliente sin pedidos
-- contaría 1, por la fila que el LEFT JOIN conserva con NULL.
-- ---------------------------------------------------------------
\echo '== Ejercicio 4 (esperadas: 8) =='
SELECT   c.nombre, count(p.id_pedido) AS pedidos
FROM     cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre
ORDER BY pedidos DESC, c.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 5. Total vendido por categoría, sin cancelados.
-- Filas esperadas: 3.
-- Construida por capas: el FROM con los dos JOIN da 23 filas (una por
-- línea de detalle); con el WHERE quedan 19; el GROUP BY las deja en 3.
-- Pregunta del encuadre: ¿y si se olvida el filtro de cancelados? Los
-- totales suben y Accesorio pasa al primer lugar: 621000 frente a 562000
-- de Grano, porque los pedidos cancelados traían el molino (150000) y la
-- prensa (95000). Con el filtro, el orden es Grano 480000, Accesorio
-- 376000 y Molido 184000.
-- ---------------------------------------------------------------
\echo '== Ejercicio 5 (esperadas: 3) =='
SELECT   pr.categoria, sum(d.cantidad * d.precio_unitario) AS total
FROM     detalle d
JOIN     pedido   p  ON p.id_pedido    = d.id_pedido
JOIN     producto pr ON pr.id_producto = d.id_producto
WHERE    p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total DESC;

-- ---------------------------------------------------------------
-- Ejercicio 6. Meses de 2026 con ventas mayores a $200 000, sin
-- cancelados, con su total.
-- Filas esperadas: 2.
-- WHERE descarta filas (año y estado); HAVING descarta grupos (el
-- total de cada mes), porque usa un agregado.
-- ---------------------------------------------------------------
\echo '== Ejercicio 6 (esperadas: 2) =='
SELECT   extract(month FROM p.fecha)          AS mes,
         sum(d.cantidad * d.precio_unitario)  AS total
FROM     pedido p
JOIN     detalle d ON d.id_pedido = p.id_pedido
WHERE    p.estado <> 'cancelado'
  AND    extract(year FROM p.fecha) = 2026
GROUP BY extract(month FROM p.fecha)
HAVING   sum(d.cantidad * d.precio_unitario) > 200000
ORDER BY mes;

-- ---------------------------------------------------------------
-- Ejercicio 7. Productos con precio mayor al promedio de SU categoría.
-- Filas esperadas: 4.
-- La subconsulta es correlacionada: usa pr.categoria, de la consulta
-- de afuera, así que calcula un promedio distinto por categoría.
-- ---------------------------------------------------------------
\echo '== Ejercicio 7 (esperadas: 4) =='
SELECT pr.nombre, pr.categoria, pr.precio
FROM   producto pr
WHERE  pr.precio > (SELECT avg(x.precio)
                    FROM   producto x
                    WHERE  x.categoria = pr.categoria)
ORDER BY pr.categoria, pr.precio DESC;

-- ---------------------------------------------------------------
-- Ejercicio 8. Clientes de Cali que han comprado al menos un
-- accesorio, sin cancelados. Cada cliente una sola vez.
-- Filas esperadas: 2.
-- EXISTS solo pregunta si hay al menos una compra, así que no repite
-- al cliente aunque tenga varias. Con JOIN haría falta DISTINCT.
-- ---------------------------------------------------------------
\echo '== Ejercicio 8 (esperadas: 2) =='
SELECT c.nombre
FROM   cliente c
WHERE  c.ciudad = 'Cali'
  AND  EXISTS (SELECT 1
               FROM   pedido p
               JOIN   detalle  d  ON d.id_pedido    = p.id_pedido
               JOIN   producto pr ON pr.id_producto = d.id_producto
               WHERE  p.id_cliente = c.id_cliente
                 AND  p.estado <> 'cancelado'
                 AND  pr.categoria = 'Accesorio')
ORDER BY c.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 9. Clientes que no han referido a nadie.
-- Filas esperadas: 5.
--
-- Consulta del compañero, que devuelve 0 filas:
--   SELECT nombre FROM cliente
--   WHERE id_cliente NOT IN (SELECT referido_por FROM cliente);
--
-- Por qué falla: la columna referido_por trae NULL en los clientes que
-- llegaron solos, y esos NULL entran a la lista de la subconsulta.
-- x NOT IN (1, 3, 4, NULL) equivale a
-- x <> 1 AND x <> 3 AND x <> 4 AND x <> NULL.
-- Comparar con NULL da desconocido, no verdadero, para cualquier x.
-- Por eso el AND completo nunca llega a ser verdadero: es falso si x
-- está en la lista y desconocido si no está. El WHERE solo deja pasar
-- lo verdadero, así que descarta todas las filas sin dar ningún error.
--
-- Corrección: NOT EXISTS pregunta si hay una fila que apunte al cliente,
-- y una fila con referido_por NULL simplemente no coincide. También
-- serviría filtrar con WHERE referido_por IS NOT NULL en la subconsulta.
-- ---------------------------------------------------------------
\echo '== Ejercicio 9 (esperadas: 5) =='
SELECT c.nombre
FROM   cliente c
WHERE  NOT EXISTS (SELECT 1
                   FROM   cliente r
                   WHERE  r.referido_por = c.id_cliente)
ORDER BY c.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 10. El o los clientes que más han gastado, sin cancelados.
-- Filas esperadas: 2.
-- Se compara con el máximo en lugar de usar LIMIT 1, que dejaría por
-- fuera a uno de los empatados.
-- ---------------------------------------------------------------
\echo '== Ejercicio 10 (esperadas: 2) =='
WITH gasto AS (
    SELECT   p.id_cliente, sum(d.cantidad * d.precio_unitario) AS total
    FROM     pedido p
    JOIN     detalle d ON d.id_pedido = p.id_pedido
    WHERE    p.estado <> 'cancelado'
    GROUP BY p.id_cliente
)
SELECT c.nombre, g.total
FROM   gasto g
JOIN   cliente c ON c.id_cliente = g.id_cliente
WHERE  g.total = (SELECT max(total) FROM gasto)
ORDER BY c.nombre;

-- ---------------------------------------------------------------
-- Ejercicio 11. Clientes que han comprado TODOS los productos de la
-- categoría Grano, sin cancelados.
-- Filas esperadas: 2.
-- División con NOT EXISTS doble. "Compró todos" se reformula como "no
-- existe un producto de Grano que no haya comprado".
-- El filtro de cancelados va en la subconsulta interna: una compra
-- cancelada no cuenta como comprada. Andrés tiene Nariño y Cauca solo
-- en el pedido cancelado 1013, por eso no sale.
-- ---------------------------------------------------------------
\echo '== Ejercicio 11 (esperadas: 2) =='
SELECT c.nombre
FROM   cliente c
WHERE  NOT EXISTS (                              -- no existe...
         SELECT 1
         FROM   producto pr
         WHERE  pr.categoria = 'Grano'           -- ...un producto de Grano...
           AND  NOT EXISTS (                     -- ...que no haya comprado
                  SELECT 1
                  FROM   pedido p
                  JOIN   detalle d ON d.id_pedido = p.id_pedido
                  WHERE  p.id_cliente = c.id_cliente
                    AND  d.id_producto = pr.id_producto
                    AND  p.estado <> 'cancelado'))
ORDER BY c.nombre;
