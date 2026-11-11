# S18. Taller: formas normales 1FN, 2FN, 3FN y FNBC

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Caso: la planilla de servicios del **Taller Automotriz El Pistón**. Scripts:

| Archivo | Qué es |
|---|---|
| [`postgres/scripts/S18-automotriz.sql`](../postgres/scripts/S18-automotriz.sql) | Script del profesor: crea el esquema `automotriz` con la tabla plana `servicio_plano` (11 filas, 6 órdenes). |
| [`postgres/scripts/normalizacion.sql`](../postgres/scripts/normalizacion.sql) | **Parte B**, resuelta por el grupo: limpieza, esquema 3FN, carga, reconstrucción con `EXCEPT` y las tres anomalías. |

La regla que organiza todo el taller viene de S17 (sección 6.2):

> **Una tabla está bien diseñada cuando todo determinante de una dependencia no trivial es una superclave.**

Las formas normales son versiones de esa regla, de la más permisiva a la más estricta:

| Forma normal | Qué exige | Qué prohíbe |
|---|---|---|
| 1FN | Valores atómicos | Listas en una celda y grupos de columnas que repiten lo mismo (`telefono1`, `telefono2`…) |
| 2FN | 1FN, y ningún atributo no primo depende de **una parte** de una clave candidata | Dependencias parciales |
| 3FN | 2FN, y para cada X → A no trivial: X es superclave **o** A es primo (parte de alguna clave candidata) | Dependencias transitivas (un atributo no clave que determina a otro) |
| FNBC | Para cada X → A no trivial: X es superclave, sin excepciones | Cualquier determinante que no sea superclave |

(*Atributo primo* = el que forma parte de alguna clave candidata.)

---

## Parte A1. Diagnóstico

Método para cada relación: (1) las **claves candidatas**, con el cierre X⁺ de los atributos que no aparecen al lado derecho de ninguna dependencia (S17, sección 9); (2) la **forma normal más alta**, revisando en orden 1FN → 2FN → 3FN → FNBC; (3) **lo que le impide subir** a la siguiente.

| # | Relación | Claves candidatas | Forma normal más alta | Qué le impide subir |
|---|---|---|---|---|
| 1 | `Pasajero(cedula, nombre, telefonos)` | {cedula} | **Ninguna: no está en 1FN** | El atributo `telefonos` no es atómico: guarda una lista (`'3001112233, 3154445566'`) |
| 2 | `Inscripcion(cod_est, cod_taller, fecha_inscripcion, nombre_taller)` | {cod_est, cod_taller} | **1FN** | `cod_taller → nombre_taller`: el no primo `nombre_taller` depende de una **parte** de la clave (dependencia parcial) |
| 3 | `Empleado(cedula, nombre, cod_depto, nombre_depto)` | {cedula} | **2FN** | `cod_depto → nombre_depto`: `cod_depto` no es superclave y `nombre_depto` no es primo (dependencia transitiva: cedula → cod_depto → nombre_depto) |
| 4 | `Vuelo(num_vuelo, fecha, matricula_avion, cedula_piloto)` | {num_vuelo, fecha} | **FNBC** | Nada: la única dependencia tiene como determinante la clave |
| 5 | `Municipio(cod_dane, nombre, departamento)` | {cod_dane} y {nombre, departamento} | **FNBC** | Nada: los **dos** determinantes son claves candidatas |
| 6 | `Clase(cod_est, materia, profesor)` | {cod_est, materia} y {cod_est, profesor} | **3FN** | `profesor → materia`: `profesor` no es superclave. Se acepta en 3FN solo porque `materia` es primo |

**Justificación, relación por relación:**

1. **Pasajero.** {cedula}⁺ = {cedula, nombre, telefonos}: es la clave. Pero `telefonos` guarda varios valores en una celda, y la 1FN exige valores atómicos. Sin 1FN no se evalúan las demás.
   - **¿Y con `telefono1`, `telefono2`, `telefono3`?** **Sigue sin estar en 1FN.** Cada celda tendría un solo número, pero la definición del curso también prohíbe los **grupos de columnas que repiten lo mismo** (pre-lectura, sección 2). Además, limita a tres teléfonos, deja `NULL` en quien tiene menos, obliga a buscar en tres columnas (`WHERE telefono1 = x OR telefono2 = x OR telefono3 = x`) e impide declarar con `UNIQUE` que un número no se repita. **Cómo se arregla:** `Pasajero(cedula PK, nombre)` y `Telefono_pasajero(cedula → Pasajero, telefono)`, con PK (cedula, telefono), una fila por teléfono. Las dos quedan en FNBC.
2. **Inscripcion.** `cod_est` y `cod_taller` no aparecen a la derecha de ninguna dependencia, y juntos determinan todo: {cod_est, cod_taller} es la única clave. Está en 1FN (valores atómicos), pero `nombre_taller` depende solo de `cod_taller`, una parte de la clave: no está en 2FN. Se arregla con `Taller(cod_taller PK, nombre_taller)` e `Inscripcion(cod_est, cod_taller → Taller, fecha_inscripcion)`.
3. **Empleado.** {cedula}⁺ = {cedula, nombre, cod_depto, nombre_depto}: clave simple, así que está en 2FN (no hay "partes" de la clave). Pero `cod_depto → nombre_depto` es transitiva: el nombre del departamento se repite en cada empleado. Se arregla con `Departamento(cod_depto PK, nombre_depto)` y `Empleado(cedula PK, nombre, cod_depto → Departamento)`.
4. **Vuelo.** {num_vuelo, fecha}⁺ = todos los atributos: es la única clave (el mismo número de vuelo se repite cada día). La única dependencia no trivial tiene como determinante la clave: cumple la regla de S17, está en **FNBC** y no hay nada que mejorar.
5. **Municipio.** {cod_dane}⁺ = todos los atributos, y también {nombre, departamento}⁺ = {nombre, departamento, cod_dane} = todos. Hay **dos claves candidatas**. La dependencia `nombre, departamento → cod_dane` *parece* un determinante que no es clave, pero sí lo es: es la otra clave candidata. Los dos determinantes son superclaves: **FNBC**. (Los tres atributos son primos.)
6. **Clase.** {cod_est, materia}⁺ = todos, por la primera dependencia. {cod_est, profesor}⁺ = {cod_est, profesor, materia} = todos, por `profesor → materia`. Hay **dos claves candidatas que se solapan** (comparten `cod_est`), y los tres atributos son primos. **3FN: sí**, porque en `profesor → materia` el lado derecho es primo. **FNBC: no**, porque `profesor` no es superclave. Es el mismo caso de `monitoria` de la pre-lectura, y el mismo de la Parte C.

## Parte A2. El Pistón hasta 3FN

### (a) Por qué la hoja original no está en 1FN, y la orden 5005 en 1FN

Así se ve la orden 5005 en la hoja de cálculo del taller:

| orden | fecha | km | placa | carro | dueño | teléfono | servicios | cobrado | mecánicos |
|---|---|---|---|---|---|---|---|---|---|
| 5005 | 2026-10-14 | 52000 | JKL012 | Renault Duster | 1144000003 Camilo Ibarra | 3157778899 | ACE Cambio de aceite, FRE Pastillas de freno, ALI Alineación | 120000, 150000, 80000 | M01 Rosa Quintero, M02 Hernán Bedoya, M02 Hernán Bedoya |

**No está en 1FN** porque varias celdas no son atómicas:

- `servicios`, `cobrado` y `mecánicos` guardan **listas**: tres servicios, tres precios y tres mecánicos en una sola celda. Además, la lista de precios y la de mecánicos solo se entienden **por posición** (el segundo precio es del segundo servicio): si alguien borra un servicio y no el precio, las listas se desalinean sin que nada lo avise.
- Cada servicio de la lista junta dos datos (`ACE Cambio de aceite` es código y nombre), igual que `dueño` (cédula y nombre) y `carro` (marca y modelo).

Con eso no se puede responder "¿cuántas alineaciones hizo Hernán?" ni sumar lo cobrado sin partir texto, ni poner una FK hacia un catálogo de servicios.

**En 1FN**, cada servicio hecho en la orden es una fila, y los datos de la orden, el vehículo y el dueño se copian en cada una. Es la forma de `servicio_plano`. Las tres filas de la orden 5005:

| num_orden | fecha_ingreso | kilometraje | placa | modelo | marca | cedula_dueno | nombre_dueno | telefono_dueno | cod_servicio | nombre_servicio | precio_lista | precio_cobrado | cod_mecanico | nombre_mecanico |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 5005 | 2026-10-14 | 52000 | JKL012 | Duster | Renault | 1144000003 | Camilo Ibarra | 3157778899 | ACE | Cambio de aceite | 120000 | 120000 | M01 | Rosa Quintero |
| 5005 | 2026-10-14 | 52000 | JKL012 | Duster | Renault | 1144000003 | Camilo Ibarra | 3157778899 | FRE | Cambio de pastillas de freno | 150000 | 150000 | M02 | Hernán Bedoya |
| 5005 | 2026-10-14 | 52000 | JKL012 | Duster | Renault | 1144000003 | Camilo Ibarra | 3157778899 | ALI | Alineación y balanceo | 80000 | 80000 | M02 | Hernán Bedoya |

Ya está en 1FN, pero se nota la redundancia: la fecha, el kilometraje, el vehículo y el dueño están **tres veces**. Las formas siguientes la quitan.

### (b) Dependencias funcionales de `servicio_plano`

Salen de las 5 reglas del negocio que dio el dueño del taller, no de los datos (S17, sección 5.2). Los datos solo sirven para refutar: en la Parte B (a) se comprobó con SQL que ninguna dependencia queda contradicha, salvo el teléfono de Jorge Mejía, que era un error y se corrigió.

| # | Dependencia | Regla del negocio que la justifica |
|---|---|---|
| D1 | `num_orden → fecha_ingreso, kilometraje, placa` | **Regla 3:** cada orden tiene un número, la fecha de ingreso, el vehículo y el kilometraje con el que llegó |
| D2 | `placa → modelo, cedula_dueno` | **Regla 1:** cada vehículo se identifica por su placa y tiene un modelo; el taller guarda el dueño **actual**: un vehículo tiene un dueño registrado |
| D3 | `modelo → marca` | **Regla 1:** cada modelo es de una sola marca (Spark y Sail son Chevrolet; Logan y Duster, Renault) |
| D4 | `cedula_dueno → nombre_dueno, telefono_dueno` | **Regla 2:** de cada dueño se guardan cédula, nombre y **un** teléfono |
| D5 | `cod_servicio → nombre_servicio, precio_lista` | **Regla 4:** catálogo de servicios, cada uno con un código de tres letras, un nombre y un precio de lista |
| D6 | `cod_mecanico → nombre_mecanico` | **Regla 5:** de cada mecánico se guardan un código y su nombre |
| D7 | `num_orden, cod_servicio → precio_cobrado, cod_mecanico` | **Reglas 4 y 5:** cada servicio se hace a lo sumo una vez por orden, con un precio cobrado que puede ser distinto al de lista, y lo hace **un solo** mecánico |

Por transitividad se deducen otras, por ejemplo `placa → marca, nombre_dueno, telefono_dueno` (D2 y luego D3 y D4) o `num_orden → modelo, marca, cedula_dueno, …` (D1 y luego D2). No se escriben aparte, porque salen de las siete.

**Dependencias que NO se cumplen** (y explican dónde va cada columna):

| No es dependencia | Por qué | Consecuencia |
|---|---|---|
| `placa → kilometraje` | Regla 3: un vehículo vuelve muchas veces; ABC123 llegó con 45 200 km en la orden 5001 y con 46 900 en la 5004 | El kilometraje es de la **orden** |
| `cod_servicio → precio_cobrado` | El cambio de aceite se cobró a 120 000 y a 110 000 (orden 5002) | El precio cobrado es de la **línea** de la orden; el de lista, del servicio |
| `num_orden → cod_mecanico` | En la orden 5001 trabajaron M01 y M02 | El mecánico es de **cada servicio** de la orden |
| `cod_mecanico → cod_servicio` | Hernán Bedoya hizo alineaciones y frenos | Un mecánico no está atado a un servicio |

### (c) `(num_orden, cod_servicio)` es la única clave candidata

**Es superclave.** Se calcula su cierre (S17, sección 9), agregando el lado derecho de cada dependencia cuyo lado izquierdo ya esté dentro:

```
{num_orden, cod_servicio}
  + D1 → fecha_ingreso, kilometraje, placa
  + D2 → modelo, cedula_dueno
  + D3 → marca
  + D4 → nombre_dueno, telefono_dueno
  + D5 → nombre_servicio, precio_lista
  + D7 → precio_cobrado, cod_mecanico
  + D6 → nombre_mecanico
= los 15 atributos
```

**Es mínima.** Ninguna de sus partes sola alcanza:

- {num_orden}⁺ = {num_orden, fecha_ingreso, kilometraje, placa, modelo, marca, cedula_dueno, nombre_dueno, telefono_dueno}. Faltan los datos del servicio, el precio cobrado y el mecánico: una orden tiene varios servicios.
- {cod_servicio}⁺ = {cod_servicio, nombre_servicio, precio_lista}. Un servicio se hace en muchas órdenes.

**Es la única.** `num_orden` y `cod_servicio` **no aparecen al lado derecho de ninguna dependencia**: nada los determina. Por eso toda clave candidata tiene que contenerlos a los dos. Como juntos ya son clave, cualquier otro conjunto que los contenga tendría atributos de sobra y no sería mínimo. Entonces no hay otra clave candidata.

### (d) Paso a 2FN: las dependencias parciales

La clave es compuesta, así que se busca qué depende **solo de una parte** de ella:

| Dependencia parcial | Parte de la clave | Qué se repite por culpa de ella |
|---|---|---|
| D1 (y, a través de ella, D2, D3 y D4) | `num_orden` | Los datos de la orden, del vehículo y del dueño, en cada servicio de la orden |
| D5 | `cod_servicio` | El nombre y el precio de lista, cada vez que se hace el servicio (el cambio de aceite, 4 veces) |

Solo D7 depende de la clave **completa**. Se saca cada parte de la clave, con lo que determina, a su propia tabla, donde es la clave:

```
orden_2fn       (num_orden PK, fecha_ingreso, kilometraje, placa, modelo, marca,
                 cedula_dueno, nombre_dueno, telefono_dueno)
servicio        (cod_servicio PK, nombre_servicio, precio_lista)
orden_servicio  (num_orden → orden_2fn, cod_servicio → servicio,
                 precio_cobrado, cod_mecanico, nombre_mecanico)
                 PK (num_orden, cod_servicio)
```

Las tres están en 2FN. `orden_2fn` y `servicio` tienen clave simple, así que no puede haber dependencias parciales. En `orden_servicio`, `nombre_mecanico` no depende de una parte de la clave, sino de `cod_mecanico`, que no es parte de ella. Eso es un problema de 3FN, no de 2FN.

### (e) Paso a 3FN: las dependencias transitivas

Ahora se busca un atributo **no clave** que determine a otro:

| Tabla | Dependencia transitiva | Cadena |
|---|---|---|
| `orden_2fn` | `placa → modelo, cedula_dueno` | num_orden → placa → modelo, cedula_dueno |
| `orden_2fn` | `modelo → marca` | num_orden → placa → modelo → marca |
| `orden_2fn` | `cedula_dueno → nombre_dueno, telefono_dueno` | num_orden → placa → cedula_dueno → nombre, teléfono |
| `orden_servicio` | `cod_mecanico → nombre_mecanico` | (num_orden, cod_servicio) → cod_mecanico → nombre_mecanico |

Cada determinante transitivo sale a una tabla en la que es clave, y en la tabla de origen queda como FK. **Esquema final en 3FN:**

```
dueno          (cedula_dueno PK, nombre_dueno, telefono_dueno)
modelo         (modelo PK, marca)
vehiculo       (placa PK, modelo FK → modelo, cedula_dueno FK → dueno)
orden          (num_orden PK, fecha_ingreso, kilometraje, placa FK → vehiculo)
servicio       (cod_servicio PK, nombre_servicio, precio_lista)
mecanico       (cod_mecanico PK, nombre_mecanico)
orden_servicio (num_orden FK → orden, cod_servicio FK → servicio,
                precio_cobrado, cod_mecanico FK → mecanico)
                PK (num_orden, cod_servicio)
```

```
dueno ◄── vehiculo ──► modelo
              ▲
              │
            orden ◄── orden_servicio ──► servicio
                             │
                             ▼
                          mecanico
```

Cada dependencia de (b) quedó **entera dentro de una tabla**, con su determinante como PK: D1 en `orden`, D2 en `vehiculo`, D3 en `modelo`, D4 en `dueno`, D5 en `servicio`, D6 en `mecanico` y D7 en `orden_servicio`. Por eso la base las **hace cumplir** con las PK, sin código adicional: se conservan todas las dependencias.

**Sin pérdida y sin tuplas espurias.** Cada división se hizo por un determinante que pasó a ser la **clave** de la tabla nueva. Al volver a juntar, el atributo común es clave de una de las dos partes (S17, sección 7.2): cada orden encuentra **un** vehículo, cada vehículo **un** modelo y **un** dueño, cada línea **un** servicio y **un** mecánico. No se puede combinar una fila con dos "parejas", que es lo que produce las tuplas espurias de la sección 7.3 de S17. En la Parte B (d) se comprobó con `EXCEPT` en los dos sentidos: la reconstrucción da exactamente las 11 filas de la planilla.

### (f) ¿Está también en FNBC?

**Sí.** FNBC pide que todo determinante de una dependencia no trivial sea superclave, que es la regla de S17. Tabla por tabla:

| Tabla | Clave | Dependencias no triviales | ¿Determinante superclave? |
|---|---|---|---|
| `dueno` | cedula_dueno | cedula_dueno → nombre_dueno, telefono_dueno | Sí |
| `modelo` | modelo | modelo → marca | Sí |
| `vehiculo` | placa | placa → modelo, cedula_dueno | Sí |
| `orden` | num_orden | num_orden → fecha_ingreso, kilometraje, placa | Sí |
| `servicio` | cod_servicio | cod_servicio → nombre_servicio, precio_lista | Sí |
| `mecanico` | cod_mecanico | cod_mecanico → nombre_mecanico | Sí |
| `orden_servicio` | (num_orden, cod_servicio) | (num_orden, cod_servicio) → precio_cobrado, cod_mecanico | Sí |

No queda ninguna otra dependencia. Por ejemplo, en `orden_servicio` no se cumple `cod_mecanico → cod_servicio` (Hernán hizo alineaciones y frenos), y en `orden` no se cumple `placa → kilometraje`.

Hay además un argumento general. La 3FN y la FNBC solo se diferencian cuando una tabla tiene **dos claves candidatas compuestas que se solapan** (es el caso de la Parte C). Aquí cada tabla tiene **una sola** clave candidata, así que estar en 3FN ya implica estar en FNBC.

### (g) Si el taller necesita al dueño **del día de la orden**

D2 (`placa → cedula_dueno`) dice que un vehículo tiene **un** dueño: el actual. Si el taller necesita saber quién era el dueño cuando se hizo cada orden, esa dependencia ya no sirve. Si Sandra vende el Spark en noviembre, las órdenes viejas de ABC123 deben seguir diciendo "Sandra" y las nuevas, el nombre del comprador. A lo largo del tiempo, una placa tiene **varios** dueños: `placa → cedula_dueno` deja de cumplirse.

Lo que sí se cumple es:

> **`num_orden → cedula_dueno`**: cada orden tiene un dueño, el que trajo el carro ese día.

Entonces la cédula **pasa de `vehiculo` a `orden`**:

```
vehiculo (placa PK, modelo FK → modelo)
orden    (num_orden PK, fecha_ingreso, kilometraje,
          placa FK → vehiculo, cedula_dueno FK → dueno)
```

`orden` sigue en FNBC: su única dependencia es `num_orden → fecha_ingreso, kilometraje, placa, cedula_dueno`, y ya no hay `placa → cedula_dueno` que la vuelva transitiva. Si además se quisiera saber el dueño **actual**, sería otro dato: una columna aparte en `vehiculo`, o una tabla de historial de propiedad con fechas.

---

## Parte B. La descomposición en PostgreSQL

Archivo: [`postgres/scripts/normalizacion.sql`](../postgres/scripts/normalizacion.sql), con un comentario en cada paso. Se corre después de `S18-automotriz.sql`:

```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/S18-automotriz.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql
```

| Paso | Qué hace el script | Resultado |
|---|---|---|
| (a) | Por cada dependencia de A2 (b), la consulta de S17 (sección 5.3): `GROUP BY x HAVING count(DISTINCT y) > 1`. D7 no necesita consulta: su determinante es la PK de `servicio_plano`. | Solo falla **D4** (`cedula_dueno → telefono_dueno`): Jorge Mejía (16700002) tiene `3104445566` en 4 filas (órdenes 5002 y 5003) y `3104445567` en 1 (orden 5006). Se deja **3104445566**: aparece en 4 de 5 filas y en dos órdenes, coincide con el de la hoja original de la guía (orden 5002), y el otro solo cambia el último dígito, lo que apunta a un error de digitación. El `UPDATE` corrige **todas** las filas de esa cédula. Sin esta corrección, la carga de `dueno` falla con `duplicate key … (cedula_dueno)=(16700002)` (comprobado). |
| (b) | Las 7 tablas de A2 (e), con `PRIMARY KEY`, `REFERENCES` y `NOT NULL` (y `CHECK` de precios y kilometraje), en el esquema `automotriz` | 7 `CREATE TABLE` |
| (c) | `INSERT INTO … SELECT DISTINCT … FROM servicio_plano`, primero las tablas a las que nadie apunta, y el conteo de filas | dueno 3, modelo 4, vehiculo 4, orden 6, servicio 5, mecanico 3, orden_servicio 11 |
| (d) | La vista `reconstruida` (join de las 7 tablas, columnas en el mismo orden) y `EXCEPT` en los dos sentidos | 11 = 11 filas; **0 filas** sobran y **0** faltan |
| (e) | Una sentencia por anomalía, después de (d), cada una en `BEGIN … ROLLBACK` | **Modificación:** `UPDATE 1` cambia el teléfono de Jorge, y sus 5 líneas lo ven. **Inserción:** el mecánico M04 se registra sin servicios. **Borrado:** `DELETE FROM orden WHERE num_orden IN (5003, 5005)` borra 2 órdenes (y sus líneas, por `ON DELETE CASCADE`), y siguen existiendo el vehículo JKL012, su dueño y el servicio BAT del catálogo, que en la planilla se habrían perdido. |

El script se puede correr varias veces seguidas: borra y vuelve a crear sus tablas, y las pruebas de (e) se deshacen solas.

### Salida de `psql` de los pasos (a), (c) y (d)

Salida de PostgreSQL 16 al correr `S18-automotriz.sql` y luego `normalizacion.sql`.

**(a) Revisión de las dependencias y corrección:**

```text
== (a) Datos que contradicen las dependencias (0 filas = no hay contradicción) ==
-- D1: num_orden -> fecha_ingreso, kilometraje, placa
 num_orden
-----------
(0 rows)

-- D2: placa -> modelo, cedula_dueno
 placa
-------
(0 rows)

-- D3: modelo -> marca
 modelo
--------
(0 rows)

-- D4: cedula_dueno -> nombre_dueno, telefono_dueno
 cedula_dueno | nombres | telefonos |    valores_telefono
--------------+---------+-----------+-------------------------
 16700002     |       1 |         2 | 3104445566 / 3104445567
(1 row)

-- D5: cod_servicio -> nombre_servicio, precio_lista
 cod_servicio
--------------
(0 rows)

-- D6: cod_mecanico -> nombre_mecanico
 cod_mecanico
--------------
(0 rows)


-- Corrección: el teléfono de Jorge Mejía (esperado: UPDATE 1; UPDATE 0 si el script ya se había corrido)
UPDATE 1
-- cedula_dueno -> telefono_dueno, después de corregir (esperado: 0 filas)
 cedula_dueno
--------------
(0 rows)
```

**(c) Carga de las tablas:**

```text
== (c) Carga de las tablas ==
INSERT 0 3
INSERT 0 4
INSERT 0 4
INSERT 0 6
INSERT 0 5
INSERT 0 3
INSERT 0 11

-- Filas por tabla (esperado: 3, 4, 4, 6, 5, 3 y 11)
     tabla      | filas
----------------+-------
 dueno          |     3
 modelo         |     4
 vehiculo       |     4
 orden          |     6
 servicio       |     5
 mecanico       |     3
 orden_servicio |    11
(7 rows)
```

**(d) Reconstrucción y `EXCEPT` en los dos sentidos:**

```text
== (d) Reconstrucción de la planilla ==
CREATE VIEW
-- Filas: planilla y reconstrucción (esperado: 11 y 11)
 planilla | reconstruida
----------+--------------
       11 |           11
(1 row)

-- Sobra en la reconstrucción: filas que no estaban en la planilla (esperado: 0 filas)
 num_orden | fecha_ingreso | kilometraje | placa | modelo | marca | cedula_dueno | nombre_dueno | telefono_dueno | cod_servicio | nombre_servicio | precio_lista | precio_cobrado | cod_mecanico | nombre_mecanico
-----------+---------------+-------------+-------+--------+-------+--------------+--------------+----------------+--------------+-----------------+--------------+----------------+--------------+-----------------
(0 rows)

-- Falta en la reconstrucción: filas de la planilla que se perdieron (esperado: 0 filas)
 num_orden | fecha_ingreso | kilometraje | placa | modelo | marca | cedula_dueno | nombre_dueno | telefono_dueno | cod_servicio | nombre_servicio | precio_lista | precio_cobrado | cod_mecanico | nombre_mecanico
-----------+---------------+-------------+-------+--------+-------+--------------+--------------+----------------+--------------+-----------------+--------------+----------------+--------------+-----------------
(0 rows)
```

## Parte C. 3FN frente a FNBC

Relación nueva: `responsable(num_orden, area, cod_mecanico)`, donde `area` es motor, frenos o eléctrico. Reglas:

- **R1.** En cada orden, un área tiene un solo responsable.
- **R2.** Cada mecánico trabaja en una sola área.

### (a) Dependencias y claves candidatas

| # | Dependencia | Regla |
|---|---|---|
| F1 | `num_orden, area → cod_mecanico` | R1 |
| F2 | `cod_mecanico → area` | R2 |

Claves candidatas, con cierres:

- {num_orden, area}⁺ = {num_orden, area, cod_mecanico} (por F1). Es clave: ni `num_orden` solo (una orden tiene varias áreas) ni `area` sola (un área atiende muchas órdenes) alcanzan.
- {num_orden, cod_mecanico}⁺ = {num_orden, cod_mecanico, area} (por F2). También es clave, y también es mínima.
- `num_orden` no aparece al lado derecho de ninguna dependencia, así que está en toda clave. Las únicas combinaciones mínimas con él son las dos anteriores.

**Claves candidatas: {num_orden, area} y {num_orden, cod_mecanico}.** Son dos y **se solapan** (comparten `num_orden`): esa es justo la situación en la que 3FN y FNBC dan respuestas distintas (pre-lectura, sección 5, el caso `monitoria`).

### (b) ¿3FN? ¿FNBC?

- **Sí está en 3FN.** F1: el determinante {num_orden, area} es clave. F2: `cod_mecanico` no es superclave, pero `area` es un atributo **primo** (forma parte de la clave {num_orden, area}), y la 3FN lo permite. Los tres atributos son primos, así que no puede haber dependencias parciales ni transitivas de atributos no primos.
- **No está en FNBC.** En F2, el determinante `cod_mecanico` **no es superclave**: {cod_mecanico}⁺ = {cod_mecanico, area} no incluye `num_orden`. Rompe la regla de S17, y se nota en la redundancia: el área de cada mecánico se repite en cada orden donde es responsable. Si Hernán cambia de área, hay que actualizar todas esas filas.

### (c) Descomposición en FNBC

Se parte por el determinante que causa el problema (F2), que pasa a ser clave de su propia tabla:

```
mecanico_area (cod_mecanico PK, area)
asignacion    (num_orden, cod_mecanico FK → mecanico_area)
               PK (num_orden, cod_mecanico)
```

Las dos están en FNBC. En `mecanico_area`, la única dependencia es F2, con `cod_mecanico` como clave. `asignacion` no tiene dependencias no triviales. La descomposición es **sin pérdida**, porque el atributo común, `cod_mecanico`, es clave de `mecanico_area`: al juntar, cada asignación encuentra exactamente un área y no hay tuplas espurias.

### (d) La regla que se deja de garantizar

**F1 (R1) ya no se puede hacer cumplir con claves**, porque sus tres atributos quedaron en tablas distintas: `area` está en `mecanico_area` y `num_orden` está en `asignacion`. Ninguna PK ni `UNIQUE` de una sola tabla ve a la vez la orden y el área. A esto se le llama **no preservar las dependencias**.

Ejemplo, probado en PostgreSQL, con un mecánico nuevo M04 que, como Hernán (M02), es de frenos:

```
mecanico_area                asignacion
cod_mecanico | area          num_orden | cod_mecanico
-------------+--------       ----------+-------------
M02          | frenos        5005      | M02
M04          | frenos        5005      | M04      ← se acepta: la PK (5005, M04) no se repite
```

Las dos inserciones pasan, porque cada tabla cumple sus claves. Pero al juntarlas:

```
num_orden | area   | responsables | mecanicos
----------+--------+--------------+-----------
5005      | frenos | 2            | M02, M04
```

La orden 5005 quedó con **dos responsables de frenos**, y la base no lo impidió: se violó R1.

### (e) Recomendación para el taller

**Quedarse en 3FN con `responsable(num_orden, area, cod_mecanico)` y hacer cumplir R2 con una FK compuesta**, en lugar de pasar a FNBC:

Sobre el esquema de la Parte B, eso es agregarle el área a `mecanico` y crear `responsable`:

```sql
ALTER TABLE mecanico
    ADD COLUMN area varchar(10) NOT NULL DEFAULT 'motor'
        CHECK (area IN ('motor', 'frenos', 'eléctrico')),
    ADD UNIQUE (cod_mecanico, area);          -- destino de la FK compuesta

CREATE TABLE responsable (
    num_orden     integer      REFERENCES orden (num_orden),
    area          varchar(10),
    cod_mecanico  char(3)      NOT NULL,
    PRIMARY KEY (num_orden, area),                                   -- R1
    FOREIGN KEY (cod_mecanico, area)
        REFERENCES mecanico (cod_mecanico, area) ON UPDATE CASCADE   -- R2
);
```

(El `DEFAULT 'motor'` solo sirve para poder agregar la columna a los mecánicos que ya existen; después se le asigna a cada uno su área real.)

- **R1** queda garantizada por la PK `(num_orden, area)`: un segundo responsable de frenos en la 5005 da `duplicate key`.
- **R2** queda garantizada por la FK compuesta: poner a M02 como responsable de eléctrico da `violates foreign key constraint`, porque el par (M02, eléctrico) no existe en `mecanico`.
- La redundancia que queda (el área repetida en `responsable`) **no puede contradecirse**: la FK obliga a que coincida con la de `mecanico`, y `ON UPDATE CASCADE` la mantiene al día si el mecánico cambia de área.

Las dos restricciones se probaron en PostgreSQL. Así las dos reglas del negocio quedan declaradas en el esquema, sin código adicional.

**Por qué no FNBC:** cuesta una regla del negocio (R1), que tendría que vigilarse con un trigger (M6) o en la aplicación, y eso es justo lo que S17 (sección 4.4) desaconseja: depender de que todos los programas lo hagan bien siempre. La FNBC es el ideal cuando se puede alcanzar sin perder dependencias. Cuando no se puede, la 3FN conserva todas las dependencias y es la elección práctica habitual.

---

## Resumen

| Parte | Resultado |
|---|---|
| A1 | Las 6 relaciones: 1 no está en 1FN (y con `telefono1..3` tampoco), 2 en 1FN, 3 en 2FN, 4 y 5 en FNBC, 6 en 3FN |
| A2 | 1FN → 2FN (dos dependencias parciales) → 3FN (cuatro transitivas): 7 tablas, todas en FNBC, sin pérdida y conservando las 7 dependencias |
| B | `normalizacion.sql`: 1 contradicción corregida (D4), 7 tablas cargadas, la vista `reconstruida` exacta (`EXCEPT` = 0 en los dos sentidos) y las 3 anomalías eliminadas |
| C | `responsable` está en 3FN pero no en FNBC; FNBC pierde R1; se recomienda 3FN con FK compuesta |
