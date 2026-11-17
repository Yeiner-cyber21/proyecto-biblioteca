# S19. Taller: detectar y corregir esquemas mal diseñados

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

| Archivo | Qué es |
|---|---|
| [`postgres/scripts/S19-esquemas.sql`](../postgres/scripts/S19-esquemas.sql) | Script del profesor: los cuatro esquemas "en producción" (`gimnasio`, `farmacia`, `cursos_libres`, `envios`). |
| [`postgres/scripts/casos.sql`](../postgres/scripts/casos.sql) | **Parte A**: los cuatro casos, con (a) diagnóstico, (b) evidencia, (c) esquema, (d) migración, (e) verificación y la pregunta propia, en comentarios y SQL. |
| [`postgres/scripts/parte-b-evidencia.sql`](../postgres/scripts/parte-b-evidencia.sql) | **Parte B**: una consulta de evidencia por tabla del esquema `biblioteca`. Solo lee: no cambia nada. |

**Cómo correrlo** (desde la carpeta del proyecto):

```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/casos.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/parte-b-evidencia.sql
```

`casos.sql` empieza volviendo a correr `S19-esquemas.sql` (con `\ir`), así que siempre parte de los datos originales y se puede repetir.

---

## El método

Una base en producción no se arregla borrando columnas de una vez. Para cada caso se siguió el orden de la pre-lectura (sección 4):

1. **Señal → sospecha.** Se mira el esquema con la tabla de señales de alarma (sección 1): listas en una celda, columnas numeradas, datos de otra entidad, una clave sustituta sin la clave natural protegida, datos calculables.
2. **Sospecha → evidencia.** Cada sospecha se confirma con una consulta: la que reproduce la queja, `GROUP BY … HAVING count(DISTINCT …) > 1` para las dependencias, `HAVING count(*) > 1` para los duplicados y `valor <> cálculo` para los derivados.
3. **Esquema corregido.** Una tabla por determinante, con `PRIMARY KEY`, `FOREIGN KEY`, `NOT NULL` y `UNIQUE`, incluido el `UNIQUE` de la clave natural cuando la PK es sustituta.
4. **Migración en una transacción:** `BEGIN` → crear → copiar (`string_to_table`, `UNION ALL`, `INSERT … SELECT DISTINCT`) → **verificar** (conteos esperados escritos antes y `EXCEPT` en los dos sentidos) → quitar lo viejo (`ALTER TABLE … DROP COLUMN`) → `COMMIT`.
5. **La queja, resuelta** con una consulta sobre el esquema nuevo, y una prueba de que la restricción nueva impide que vuelva a pasar.

---

## Parte A: los cuatro casos

### Caso 1: gimnasio

> **Queja:** "Le pedí al sistema cuántos socios hay en Yoga y me dijo 2, pero son 3. Y en Spinning me dijo 3, cuando son 2."

**(a) Diagnóstico**

| Problema | Dependencias | Forma normal |
|---|---|---|
| **Principal:** `clases` guarda una lista separada por `;` (`'Spinning; Funcional; Yoga '`) | Las clases de un socio son varias: no dependen funcionalmente de `id_socio` | **No está en 1FN** (valor no atómico) |
| **Secundario:** el valor del plan se repite en cada socio | `id_socio → plan` y `plan → valor_plan` (transitiva) | **No está en 3FN** |
| La clase no existe como entidad: no se puede registrar una clase sin socios | — | Anomalía de inserción (S17) |

La consulta con `LIKE '%Yoga%'` no ve `'yoga'` en minúscula (María Fernanda), y `LIKE '%Spinning%'` cuenta también a "Spinning avanzado" (Pedro). Además, los pedazos están sucios: espacios de más (`' Yoga '`) y separadores con y sin espacio.

**(b) Evidencia**

| Consulta | Resultado |
|---|---|
| `count(*) FILTER (WHERE clases LIKE '%Yoga%')` y lo mismo con `'%Spinning%'` | **Yoga 2, Spinning 3** (la queja) |
| `string_to_table(clases, ';')`, mostrando cada pedazo entre corchetes | 9 pedazos: `[ Spinning]`, `[yoga]` y `[ Yoga ]`, entre otros |
| Conteo con `lower(trim(c))` | **Yoga 3, Spinning 2**, Spinning avanzado 1 |
| `GROUP BY plan HAVING count(DISTINCT valor_plan) > 1` | 0 filas: `plan → valor_plan` se cumple |
| Veces que se repite cada valor | Mensual 3, Anual 2, Trimestral 1 |

**(c) Esquema corregido**

```
plan        (nombre_plan PK, valor)
socio       (id_socio PK, nombre, plan FK → plan)
clase       (id_clase PK, nombre UNIQUE)        + índice UNIQUE sobre lower(nombre)
socio_clase (id_socio FK → socio, id_clase FK → clase)    PK (id_socio, id_clase)
```

**(d) Migración.** El criterio de limpieza es que dos pedazos son la misma clase si coinciden con `lower(trim(c))`. Se guarda el nombre con solo la primera letra en mayúscula. No se usa `initcap`, porque convertiría "Spinning avanzado" en "Spinning Avanzado". Spinning y Spinning avanzado son clases distintas y no se juntan.

**(e) Verificación**

| Tabla | Esperado | Obtenido |
|---|---|---|
| plan | 3 | 3 |
| clase | 5 | 5 |
| socio_clase | 9 (2 + 1 + 2 + 3 + 0 + 1) | 9 |
| socio | 6 | 6 |

El `EXCEPT` de los pares (socio, clase) da 0 filas en los dos sentidos, y otro `EXCEPT` confirma que cada socio conserva su plan y su valor (0 filas). **La queja, resuelta:** Yoga 3 y Spinning 2. Intentar registrar otra vez la clase `'yoga'` se rechaza por el índice `UNIQUE (lower(nombre))`.

**Pregunta propia: ¿dónde va el horario de cada clase, y por qué era imposible hacerlo bien antes?** El horario es un dato de la **clase** (`id_clase → dia, hora`), así que va en la tabla `clase`. Si una clase tiene varias sesiones por semana, va en una tabla `clase_horario (id_clase FK, dia, hora)` con PK (`id_clase`, `dia`, `hora`). En el diseño original la clase no tenía fila propia: era un pedazo de texto dentro de cada socio. Habría que copiar el horario de Yoga en cada socio de Yoga (redundancia y anomalía de modificación) o meterlo en el mismo texto (todavía menos atómico). Y una clase nueva sin socios no tendría dónde guardar su horario (anomalía de inserción).

---

### Caso 2: farmacia

> **Queja:** "El médico le recetó cuatro medicamentos a un paciente y el sistema solo me deja registrar tres. Y para saber cuántas fórmulas llevan acetaminofén tengo que buscar en tres columnas."

**(a) Diagnóstico**

| Problema | Dependencias | Forma normal |
|---|---|---|
| **Principal:** `medicamento1..3` y `dosis1..3` son un grupo repetido. Ponen un tope de 3 y obligan a buscar en 3 columnas | `num_formula, medicamento → dosis` | **No está en 1FN** (grupo repetido) |
| **Secundario:** el nombre del paciente se copia en cada fórmula | `num_formula → doc_paciente` y `doc_paciente → nombre_paciente` (transitiva) | **No está en 3FN** |
| No se puede declarar "un medicamento no se repite en la fórmula", y nada impide `dosis2` sin `medicamento2` | — | Regla de integridad imposible de declarar |

**(b) Evidencia**

| Consulta | Resultado |
|---|---|
| Acetaminofén buscando solo en `medicamento1` y en las 3 columnas | **1 contra 3** (la queja) |
| `count(medicamento1)`, `count(medicamento2)` y `count(medicamento3)` | 4, 3 y 1 de 4 fórmulas: casi vacías |
| `GROUP BY doc_paciente HAVING count(DISTINCT nombre_paciente) > 1` | 0 filas: `doc_paciente → nombre_paciente` se cumple |
| Pacientes repetidos | Rosa Díaz, 2 veces |
| Dosis distintas por medicamento | Acetaminofén: cada 8 h y cada 6 h. La dosis es de la **línea** de la fórmula, no del medicamento |

**(c) Esquema corregido**

```
paciente            (doc_paciente PK, nombre_paciente)
medicamento         (id_medicamento PK, nombre UNIQUE)         catálogo
formula             (num_formula PK, fecha, doc_paciente FK → paciente)
formula_medicamento (num_formula FK → formula, id_medicamento FK → medicamento, dosis)
                     PK (num_formula, id_medicamento)
```

**(d) Migración.** Las columnas numeradas se pasan a filas con `UNION ALL`, descartando las vacías. Los nombres ya estaban escritos igual en todas las fórmulas, así que no hubo que limpiarlos.

**(e) Verificación**

| Tabla | Esperado | Obtenido |
|---|---|---|
| paciente | 3 | 3 |
| medicamento | 5 | 5 |
| formula_medicamento | 8 (2 + 1 + 3 + 2) | 8 |
| formula | 4 | 4 |

El `EXCEPT` de las líneas (fórmula, medicamento, dosis) da 0 filas en los dos sentidos, y otro `EXCEPT` confirma que cada fórmula conserva su paciente (0 filas). **La queja, resuelta:** acetaminofén está en 3 fórmulas, buscando en un solo lugar. A la fórmula 703 se le puede agregar un **cuarto** medicamento (se demuestra dentro de `BEGIN … ROLLBACK`). Repetir el ibuprofeno en la 703 se rechaza por la PK.

**Pregunta propia: ¿por qué no basta con agregar `medicamento4` y `dosis4`?**
1. **El tope solo se corre.** Con cinco medicamentos hay que volver a cambiar la tabla, y con ella los programas, formularios y consultas.
2. **Las consultas empeoran.** Cada pregunta por medicamento busca en 4 columnas, y contar "el más recetado" necesita un `UNION ALL` de 4 partes. La consulta que olvide una columna da un resultado equivocado sin avisar.
3. **Las reglas siguen sin poderse declarar.** No se puede impedir el mismo medicamento dos veces ni `dosis4` sin `medicamento4`, y la FK al catálogo tendría que escribirse cuatro veces.
4. **Hay más `NULL` de relleno**, porque la mayoría de las fórmulas tienen uno o dos medicamentos.

Sigue siendo un grupo repetido: no está en 1FN.

---

### Caso 3: cursos libres

> **Queja:** "Contabilidad dice que Fotografía digital recaudó 200 000 pesos más de lo que hay en caja."

**(a) Diagnóstico.** Las claves candidatas son {`id`}, {`doc_participante`, `cod_curso`} y {`correo`, `cod_curso`}.

| Problema | Dependencias | Forma normal |
|---|---|---|
| **Principal:** la PK es un `id serial` y **no hay `UNIQUE (doc_participante, cod_curso)`**. Juliana Rey quedó inscrita dos veces en Fotografía digital (filas 3 y 7, 200 000 cada una) | `doc_participante, cod_curso → valor_pagado` (a lo sumo una inscripción por curso) | Clave natural sin proteger |
| **Secundario:** datos del participante y del curso en cada inscripción | `doc_participante → nombre, correo`; `correo → doc_participante`; `cod_curso → nombre_curso, cod_sede`: dependen de una **parte** de la clave candidata | **No está en 2FN** |
| La dirección de la sede se repite (`'Cra 5 # 10-20'`, 5 veces) | `cod_curso → cod_sede` y `cod_sede → direccion_sede` (transitiva) | **No está en 3FN** |

**(b) Evidencia**

| Consulta | Resultado |
|---|---|
| `sum(valor_pagado)` por curso | **Fotografía digital: 580 000** (en caja hay 380 000) |
| `GROUP BY doc_participante, cod_curso HAVING count(*) > 1` | Juliana Rey en C20, **ids 3 y 7** |
| Las dependencias, con `HAVING count(DISTINCT …) > 1` | 0 filas: ninguna está contradicha |
| Veces que se repite cada dirección de sede | S1, 5 veces; S2, 3 veces |

**(c) Esquema corregido**

```
participante (doc_participante PK, nombre_participante, correo UNIQUE)
sede         (cod_sede PK, direccion_sede)
curso        (cod_curso PK, nombre_curso, cod_sede FK → sede)
inscripcion  (id PK, doc_participante FK → participante, cod_curso FK → curso, valor_pagado)
              UNIQUE (doc_participante, cod_curso)
```

El `id` se conserva, porque otros programas pueden usarlo, pero ahora la clave natural está protegida.

**(d) Migración.** El criterio de limpieza: las filas 3 y 7 son idénticas salvo el `id`, y la regla dice "a lo sumo una vez por curso", así que se conserva la primera (id 3) y se borra la 7. Son los 200 000 que no están en caja. Si los valores fueran distintos, habría que preguntar cuál se cobró de verdad antes de borrar.

**(e) Verificación**

| Tabla | Esperado | Obtenido |
|---|---|---|
| inscripcion | 7 (8 menos el duplicado) | 7 |
| participante | 4 | 4 |
| sede | 2 | 2 |
| curso | 3 | 3 |

El `EXCEPT` entre las filas distintas de la tabla original y la reconstrucción con joins da 0 filas en los dos sentidos. **La queja, resuelta:** Fotografía digital recaudó 380 000. Inscribir otra vez a Juliana en C20 se rechaza por el `UNIQUE`.

**Pregunta propia: ¿por qué una PK de una sola columna no la pone en 2FN? ¿Qué restricción faltaba?** La 2FN se revisa contra **todas** las claves candidatas, no solo contra la PK declarada. Por la regla "a lo sumo una vez por curso", (`doc_participante`, `cod_curso`) identifica una inscripción: es clave candidata aunque nadie la haya declarado. De una **parte** de ella dependen atributos no primos (`doc_participante → nombre_participante`, `cod_curso → nombre_curso, cod_sede`), y eso es una dependencia parcial. **Agregar un `id` no normaliza nada**; solo le cambia el nombre a la PK. Faltaba **`UNIQUE (doc_participante, cod_curso)`**. Con ella, la segunda inscripción de Juliana se habría rechazado al insertarla, y el curso no habría "recaudado" 200 000 de más.

---

### Caso 4: envíos

> **Queja:** "Un cliente de Bogotá reclama que le cobramos de más."

**(a) Diagnóstico**

| Problema | Dependencias | Forma normal |
|---|---|---|
| **Principal:** `valor` es un **dato derivado** guardado (valor = peso × tarifa), y puede contradecir su cálculo. G07 (Bogotá, 4 kg × 6 000) tiene 42 000, cuando son **24 000**: se cobraron 18 000 de más | (peso_kg, tarifa_kg) → valor, por cálculo | Redundancia de un dato calculable |
| **Secundario:** datos de la ciudad y de la zona en cada envío | `num_guia → ciudad_destino`, `ciudad_destino → departamento, zona` y `zona → tarifa_kg` (transitivas) | **No está en 3FN** |

**(b) Evidencia**

| Consulta | Resultado |
|---|---|
| `WHERE valor <> peso_kg * tarifa_kg` | **G07: 42 000 frente a 24 000**, 18 000 de más (la queja) |
| Envíos a Bogotá | G03 está bien (6 000); G07, mal |
| Las dependencias, con `HAVING count(DISTINCT …) > 1` | 0 filas: ninguna está contradicha |
| Veces que se repite cada tarifa | Zona 1, 3 veces; zona 2, 4 veces; zona 3, 1 vez |

**(c) Esquema corregido**

```
zona   (zona PK, tarifa_kg)
ciudad (ciudad PK, departamento, zona FK → zona)
envio  (num_guia PK, fecha, ciudad_destino FK → ciudad, peso_kg, tarifa_kg_aplicada)
vista envio_valor: valor = peso_kg × tarifa_kg_aplicada (se calcula, no se guarda)
```

Supuesto: el nombre identifica a la ciudad, como dice el enunciado. En Colombia hay municipios con el mismo nombre en departamentos distintos; en un sistema real la clave sería el código DANE (S18, relación 5). `tarifa_kg_aplicada` sale de la pregunta propia.

**(d) Migración.** El criterio de limpieza: el peso (4,0 kg) está bien y el valor está mal. El peso se mide al recibir el paquete, y el cliente reclama que se le cobró de más; si pesara 7 kg, los 42 000 serían correctos y no habría reclamo. Por eso `valor` **no se migra**: se calcula. Los 18 000 son lo que hay que devolverle al cliente.

**(e) Verificación**

| Tabla | Esperado | Obtenido |
|---|---|---|
| zona | 3 | 3 |
| ciudad | 5 | 5 |
| envio | 8 | 8 |

El `EXCEPT` entre los datos originales (sin valor) y la vista da 0 filas en los dos sentidos. El valor solo difiere en **G07**, que es la corrección. **La queja, resuelta:** G07 vale 24 000.

**Pregunta propia: en enero suben las tarifas. ¿Qué pasa con el valor de los envíos de octubre?** Si el valor se calcula con la tarifa **actual** de la zona, la vista recalcula también lo de octubre. Lo probamos: al subir la zona 2 a 6 600, G03 pasó de 6 000 a 6 600, aunque se cobró a 6 000. La base estaría reescribiendo lo que se cobró.

La causa es que "la tarifa" son **dos datos distintos**:
- la tarifa **vigente** de la zona (`zona → tarifa_kg`), que cambia en enero;
- la tarifa **con que se cobró** cada envío (`num_guia → tarifa_kg_aplicada`), que es un hecho del día del envío y no cambia.

Por eso se agrega `tarifa_kg_aplicada` a `envio`, copiada de la zona al registrar el envío, y el valor se calcula con ella. Con el ajuste, al subir la tarifa, G03 sigue valiendo 6 000 (también se probó).

**¿Es redundancia? No.** Un dato es redundante cuando se puede calcular **siempre** con otros que ya están guardados. La tarifa aplicada no se puede calcular después de enero, porque la de la zona ya será otra: es un **dato histórico**, que solo se parece a uno redundante mientras la tarifa no cambie. El valor sí sigue siendo derivado (peso × tarifa aplicada), y por eso se calcula en la vista. Otra opción válida es una tabla de tarifas por fecha, `zona_tarifa(zona, vigente_desde, tarifa_kg)`, que calcula cada envío con la tarifa vigente en su fecha.

---

## Parte B: el esquema del proyecto (`biblioteca`)

Examen de cada tabla con la tabla de señales de la pre-lectura. Las consultas de evidencia están en [`parte-b-evidencia.sql`](../postgres/scripts/parte-b-evidencia.sql) y se corrieron con los datos de S14 y S16 (37 libros, 20 lectores y 30 préstamos). Como las fechas de `datos-prueba.sql` son relativas, se vuelve a correr ese script el mismo día, antes de la evidencia: si no, los préstamos que vencieron después cuentan como mora. En esta sesión **no se migra** el proyecto: los cambios propuestos son para S20.

| Tabla | Claves candidatas | Dependencias (con su regla) | Forma normal más alta | Problema encontrado | Evidencia (consulta) | Cambio propuesto |
|---|---|---|---|---|---|---|
| `usuario` | {id_usuario}, {documento}, {correo} | `id_usuario → documento, nombres, apellidos, correo, contrasena_hash, perfil, …`; `documento → id_usuario` (un documento es una persona); `correo → id_usuario` (el correo es el login, único) | **FNBC**: los tres determinantes son claves, y las claves naturales tienen `UNIQUE` | No es de normalización. `perfil` y las tablas `lector` y `bibliotecario` guardan **dos veces** el mismo hecho ("es lector") y nada impide que se contradigan | Documentos y correos repetidos: **0 y 0**. Contradicciones entre `perfil` y `lector`/`bibliotecario`: **0** hoy, pero ninguna restricción lo garantiza | Amarrarlos con una FK compuesta: `UNIQUE (id_usuario, perfil)` en `usuario`, y en `lector` una columna `perfil` con `CHECK (perfil = 'lector')` y `FK (id_usuario, perfil)` (igual en `bibliotecario`). Se probó: rechaza cambiar el perfil de un lector |
| `lector` | {id_usuario} | `id_usuario → telefono` (cada lector registra un teléfono) | **FNBC** | Ninguno. Un solo teléfono por lector, en una sola columna (no hay `telefono1`, `telefono2`) | Teléfonos con varios valores: **0** | Ninguno: está bien |
| `bibliotecario` | {id_usuario} | Ninguna no trivial (solo la clave) | **FNBC** | Ninguno | — (la PK es la única columna) | Ninguno: está bien. Aplica la misma FK compuesta de `usuario` |
| `categoria` | {id_categoria}, {nombre} | `id_categoria → nombre`; `nombre → id_categoria` (cada categoría tiene un nombre único) | **FNBC** | Señal: texto como clave natural. El `UNIQUE` distingue mayúsculas, así que aceptaría "Novela" y "novela" (hoy la carga lo evita con `initcap`) | Nombres que solo cambian en mayúsculas: **0 filas** | Índice `UNIQUE (lower(nombre))`, como en el caso 1. Se probó |
| `autor` | {id_autor}, {nombre} | `id_autor → nombre`; `nombre → id_autor` | **FNBC** | Igual que `categoria`. Además, el `UNIQUE (nombre)` no deja registrar dos autores distintos con el mismo nombre | Nombres que solo cambian en mayúsculas o espacios: **0 filas** | `UNIQUE (lower(trim(nombre)))`. Mantener la decisión de un nombre por autor, documentando el límite de los homónimos |
| `libro` | {isbn} | `isbn → titulo, anio_publicacion, id_categoria, activo` (un ISBN identifica una edición). `titulo → isbn` **no**, porque un título puede tener varias ediciones | **FNBC** | Ninguno. La categoría es FK, no texto repetido. `ejemplares_disponibles` **no** se guarda: se calcula | Libros por categoría, todos con FK (Novela 18, Ciencia 3…). Disponibles calculados (Harry Potter: 6 activas, 2 prestadas, 4 disponibles) | Ninguno: está bien. Mantener `ejemplares_disponibles` calculado (en una vista para la API de M7) |
| `libro_autor` | {isbn, id_autor} | Ninguna no trivial (relación N:M) | **FNBC** | Ninguno | Pares repetidos: **0 filas** (la PK lo impide) | Ninguno: está bien |
| `ejemplar` | {isbn, numero_copia} | `isbn, numero_copia → estado` (cada copia física tiene su estado). `isbn → estado` **no**: las copias de un libro pueden estar en estados distintos | **FNBC** (el estado depende de la clave completa: no hay dependencia parcial) | Ninguno. Es la entidad débil de `libro` | Libros con copias en estados distintos: **0** hoy (todas activas), pero la regla lo permite | Ninguno: está bien |
| `prestamo` | {id_prestamo}. No hay clave natural: el mismo ejemplar se puede prestar, devolver y volver a prestar el mismo día | `id_prestamo → id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento, fecha_devolucion` | **FNBC** | Señal revisada: `fecha_vencimiento` **parece** derivada (hoy siempre es préstamo + 14), pero es **histórica**: si la biblioteca cambia el plazo o renueva un préstamo, los vencimientos viejos no deben cambiar (como la tarifa del caso 4). La mora **no** se guarda como estado: se calcula | Plazo de 14 días: **30 de 30** préstamos. En mora (calculado): **5**. Mismo ejemplar dos veces el mismo día: **0**. Lectores con más de 3 abiertos: **0** | Ninguno de normalización. La regla "un ejemplar no se presta dos veces a la vez" ya la protege el índice único parcial. Quedan para el Hito 4, con trigger, "máximo 3 abiertos" y "no prestar en mora" |
| `carga.rechazo_carga` | {id} | `id → archivo, linea, contenido, motivo, fecha` | **FNBC** | Ninguno. Es una bitácora: la misma línea puede quedar registrada en varias corridas, y eso es correcto | Líneas registradas en varias corridas: en la base del grupo, las líneas de error de `libros_propios.csv` aparecen **2 veces**, porque en S14 ese CSV se cargó dos veces a propósito, para probar que no duplica. Es lo que debe hacer una bitácora | Ninguno: está bien |

Las tablas `carga.stg_*` son **tablas de paso**: se vacían en cada carga y no forman parte del modelo. Por eso no se normalizan.

**Conclusión:** las 9 tablas del esquema `biblioteca` (y la bitácora de carga) están en **FNBC**. No hay listas en celdas, ni columnas numeradas, ni texto de otra entidad copiado, ni datos derivados guardados. Toda clave sustituta tiene protegida su clave natural con `UNIQUE` (ISBN, documento, correo, nombre de categoría y de autor). Lo que se encontró son **reglas de integridad**, no problemas de normalización: la coherencia entre `perfil` y las tablas de cada perfil, y los nombres que solo cambian en mayúsculas. Los cambios propuestos se aplican en S20, junto con la decisión de desnormalizar a propósito alguna columna.

---

## Entregable

| # | La guía pide | Archivo |
|---|---|---|
| 1 | `casos.sql`: los cuatro casos, con (a)–(e) y la pregunta propia | [`postgres/scripts/casos.sql`](../postgres/scripts/casos.sql) |
| 2 | La salida de `psql` de las consultas de evidencia y de verificación | La salida de `casos.sql` y de `parte-b-evidencia.sql` |
| 3 | La tabla de la parte B, completa para todas las tablas del proyecto | Este documento, sección "Parte B" |
