# Mapeo CSV → esquema y criterios de carga

**Proyecto Biblioteca · Hito 2 · Laboratorio S14**

Este documento define, **antes de escribir el SQL**, a dónde va cada columna de los CSV en el esquema `biblioteca` (`postgres/init/01_esquema.sql`) y qué se hace con cada tipo de error. Los scripts `carga-libros.sql` y `carga-lectores.sql` implementan exactamente estas reglas, en este mismo orden y con estos mismos motivos.

## 0. Principios del grupo

Todas las decisiones de las tablas siguientes salen de estos seis principios:

1. **La carga masiva solo da de alta.** Nunca modifica ni borra un registro que ya existe; las correcciones de datos existentes se hacen por la API (Hito 5). Por eso repetir una carga no duplica ni altera nada.
2. **Solo se corrige lo mecánico**, es decir, lo que no cambia el significado: espacios sobrantes, mayúsculas del correo, separadores dentro del ISBN, el documento o el teléfono, y la capitalización de la categoría. Todo lo demás se **rechaza** con un motivo legible.
3. **Una fila mala no detiene la carga:** las filas válidas del mismo archivo sí entran. Todo corre en una transacción (`BEGIN … COMMIT`); si algo inesperado falla, la base queda como estaba.
4. **La primera regla que falla da el motivo.** Las reglas se evalúan en el orden en que aparecen en las tablas de la sección 1.
5. **Cada restricción del esquema (`NOT NULL`, `CHECK`, `UNIQUE`, longitud de `varchar`) tiene su regla en la validación.** El esquema es la última línea de defensa: si una fila llega a chocar con él, la validación falló.
6. **Orden de carga: primero los archivos limpios, después los que tienen errores.** Así un duplicado de prueba no puede quedar en el catálogo antes que el registro real.

## 1. Mapeo CSV → esquema

### 1.1 Libros: `isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación → motivo | Respaldo en el esquema |
|---|---|---|---|---|
| *(línea 1)* | — | Se le quitan el BOM y los espacios, y se pasa a minúsculas | Distinta del encabezado esperado → **todas** las filas: `encabezado no coincide con el esperado (isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles)` | — |
| *(línea completa)* | `carga.rechazo_carga.contenido` (solo si se rechaza) | Se guarda tal cual llegó | Línea en blanco → se descarta<br>Trae `"` → `contiene comillas: no se admiten comas dentro de un campo`<br>1 campo y trae `;` → `separador ';' en lugar de ',' (¿guardado desde Excel en español?)`<br>≠ 6 campos → `tiene N columnas, se esperaban 6` | — |
| `isbn` | `libro.isbn`<br>`libro_autor.isbn`<br>`ejemplar.isbn` | `trim`; se quitan guiones y espacios (`978-0-00-000039-1` → `9780000000391`) | Vacío → `isbn vacío`<br>No son 13 dígitos → `isbn no tiene 13 dígitos`<br>Ya está en `libro` → `isbn ya existe en el catálogo`<br>Repetido en el archivo → `isbn repetido en el archivo (primera aparición: línea N)` | PK, `ck_libro_isbn` |
| `titulo` | `libro.titulo` | `trim`; los espacios internos repetidos quedan en uno | Vacío → `título vacío`<br>Más de 200 caracteres → `título supera 200 caracteres` | `NOT NULL`, `ck_libro_titulo`, `varchar(200)` |
| `autor` | `autor.nombre` (se da de alta si no existe)<br>`libro_autor.id_autor` (se busca por nombre) | `trim` y espacios repetidos; coincidencia exacta del nombre | Vacío → `autor vacío`<br>Más de 120 caracteres → `autor supera 120 caracteres` | `ck_autor_nombre`, `UNIQUE`, `varchar(120)` |
| `categoria` | `categoria.nombre` (se da de alta si no existe)<br>`libro.id_categoria` (se busca por nombre) | `trim`, espacios repetidos e `initcap` (`novela`/`NOVELA` → `Novela`) | Vacía → `categoría vacía`<br>Más de 40 caracteres → `categoría supera 40 caracteres` | `NOT NULL` de `id_categoria`, `ck_categoria_nombre`, `varchar(40)` |
| `anio_publicacion` | `libro.anio_publicacion` | `::smallint` (solo después de comprobar que son dígitos) | No son 1–4 dígitos → `año no numérico`<br>Fuera de 1450–2100 → `año fuera de rango (1450-2100)`<br>Mayor que el año actual → `año en el futuro (posterior a AAAA)` | `ck_libro_anio` (1450–2100) |
| `ejemplares_disponibles` | `ejemplar`: *n* filas (`numero_copia` 1…n, `estado = 'activo'`) | `generate_series(1, n)`. **No se guarda como número**: la disponibilidad es un dato derivado | No es entero → `ejemplares no numérico`<br>Menor que 0 → `ejemplares negativo`<br>Mayor que 100 → `ejemplares supera el máximo por carga (100)` | PK de `ejemplar`, `ck_ejemplar_numero`, `smallint` |
| *(no viene)* | `libro.activo` | `DEFAULT true` | — | — |

### 1.2 Lectores: `documento,nombres,apellidos,correo,telefono`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación → motivo | Respaldo en el esquema |
|---|---|---|---|---|
| *(línea 1)* | — | Igual que en libros | Distinta del encabezado esperado → **todas** las filas: `encabezado no coincide con el esperado (documento,nombres,apellidos,correo,telefono)` | — |
| *(línea completa)* | `carga.rechazo_carga.contenido` (solo si se rechaza) | Se guarda tal cual llegó | Igual que en libros, pero con 5 columnas: `tiene N columnas, se esperaban 5` | — |
| `documento` | `usuario.documento` | `trim`; se quitan puntos y espacios (`1.000.000.026` → `1000000026`) | Vacío → `documento vacío`<br>No son 6–15 dígitos → `documento no numérico o de longitud inválida (6-15 dígitos)`<br>Ya está en `usuario` → `documento ya registrado (perfil X)`<br>Repetido en el archivo → `documento repetido en el archivo (primera aparición: línea N)` | `UNIQUE`, `ck_usuario_documento` |
| `nombres` | `usuario.nombres` | `trim` y espacios repetidos | Vacío → `nombres vacíos`<br>Más de 80 caracteres → `nombres superan 80 caracteres` | `ck_usuario_nombres`, `varchar(80)` |
| `apellidos` | `usuario.apellidos` | `trim` y espacios repetidos | Vacío → `apellidos vacíos`<br>Más de 80 caracteres → `apellidos superan 80 caracteres` | `ck_usuario_apellidos`, `varchar(80)` |
| `correo` | `usuario.correo` | `trim` y `lower` (`Ana@X.co` → `ana@x.co`) | Vacío → `correo vacío`<br>Formato inválido → `correo mal formado`<br>Más de 120 caracteres → `correo supera 120 caracteres`<br>Ya lo usa otro usuario (de cualquier perfil) → `correo ya registrado por otro usuario`<br>Repetido en el archivo → `correo repetido en el archivo (primera aparición: línea N)` | `UNIQUE`, `ck_usuario_correo_formato`, `ck_usuario_correo_minusculas` |
| `telefono` | `lector.telefono` | `trim`; se quitan espacios, guiones, puntos y paréntesis (`(300) 100-0026` → `3001000026`) | Vacío → `teléfono vacío`<br>No son 7–15 dígitos → `teléfono no numérico o de longitud inválida (7-15 dígitos)` | `ck_lector_telefono` |
| *(no viene)* | `usuario.perfil` | Constante `'lector'` | — | `ck_usuario_perfil` |
| *(no viene)* | `usuario.contrasena_hash` | `crypt(documento, gen_salt('bf'))`, es decir, bcrypt del documento | — | `ck_usuario_hash_bcrypt` |
| *(no viene)* | `usuario.debe_cambiar_contrasena` | `true`: la clave inicial se cambia en el primer login | — | — |
| *(se genera)* | `lector.id_usuario` | Se recupera con `JOIN usuario ON documento` después de insertar el usuario | — | PK/FK de `lector` |

**Contraseña inicial.** Los CSV no traen contraseña, a propósito. El grupo decidió usar el **documento como clave inicial, guardada con bcrypt** (pgcrypto), y marcar `debe_cambiar_contrasena = true`. Como el documento es un dato conocido, la aplicación obligará a cambiarla en el primer inicio de sesión (Hito 5). Nunca se guarda en texto plano: el `CHECK ck_usuario_hash_bcrypt` lo impide.

## 2. Criterios por tipo de error

Las tres decisiones posibles son **rechazar** (la fila va a la bitácora `carga.rechazo_carga` con su motivo), **corregir** (se normaliza y se carga) y **actualizar** (modificar un registro existente). Por el principio 1, este grupo **no usa "actualizar"** en la carga masiva.

### 2.1 Los 14 errores de los archivos del curso

**`libros_semilla_con_errores.csv`** (después de cargar `libros_semilla.csv`)

| # | Línea | Fila | Problema | Motivo registrado | Decisión | Por qué |
|---|---|---|---|---|---|---|
| 1 | 2 | `9780000000001` | ISBN que ya existe en el catálogo | `isbn ya existe en el catálogo` | Rechazar | El archivo es de altas. La fila trae otro título ("edición duplicada") y otros ejemplares: actualizar pisaría los datos de un libro real con datos de prueba. Si de verdad fuera otra edición, tendría otro ISBN. |
| 2 | 3 | `9780000000033` | Título vacío | `título vacío` | Rechazar | El título no se puede adivinar. La pista (Cortázar, novela, 1963) apunta a *Rayuela*, que ya existe con otro ISBN (`…004`): "completarla" crearía un duplicado. |
| 3 | 4 | `9780000000034` | `"dos"` como valor numérico (ver la nota 2.3) | `año no numérico` | Rechazar | No se convierten números escritos en palabras: no es una corrección mecánica confiable. |
| 4 | 5 | `9780000000035` | Año en números romanos (`MCMXLIX`) | `año no numérico` | Rechazar | Se podría convertir (1949), pero es un caso aislado y no justifica un conversor. Se corrige a mano en el CSV y se vuelve a cargar. |
| 5 | 6 | `9780000000036` | Una columna de más | `tiene 7 columnas, se esperaban 6` | Rechazar | No se sabe qué columna sobra: si los datos están corridos, cualquier "arreglo" mezclaría campos. |
| 6 | 7 | `9780000000037` | Autor vacío | `autor vacío` | Rechazar | Todo libro debe tener al menos un autor (participación total en `libro_autor`). El esquema no puede exigirlo, así que lo exige la carga. |
| 7 | 8 | *(vacío)* | ISBN vacío | `isbn vacío` | Rechazar | El ISBN es la clave primaria: sin él no hay libro. |
| 8 | 9 | `9780000000038` | Ejemplares negativos (`-3`) | `ejemplares negativo` | Rechazar | Es numéricamente válido, pero no tiene sentido de negocio. Cambiarlo a 3 o a 0 sería adivinar; el bibliotecario debe contar las copias. |

**`lectores_semilla_con_errores.csv`** (después de cargar `lectores_semilla.csv`)

| # | Línea | Fila | Problema | Motivo registrado | Decisión | Por qué |
|---|---|---|---|---|---|---|
| 9 | 2 | `1000000001` | Documento que ya existe | `documento ya registrado (perfil lector)` | Rechazar | Altas solamente. Cambiar datos personales de alguien desde un archivo masivo, sin verificar su identidad, es riesgoso; eso se hace por la API. |
| 10 | 3 | `1000000021` | Correo vacío | `correo vacío` | Rechazar | El correo es el usuario de login y el canal para la notificación de mora: no se puede inventar. |
| 11 | 4 | `1000000022` | Correo sin `@` (`…-arroba-…`) | `correo mal formado` | Rechazar | Reemplazar `-arroba-` por `@` solo sirve para este caso puntual; no es una corrección mecánica general. |
| 12 | 5 | `1000000023` | Teléfono en palabras (`tres-cero-cero`) | `teléfono no numérico o de longitud inválida (7-15 dígitos)` | Rechazar | Además está incompleto: aunque se tradujera, no es un número válido. |
| 13 | 6 | *(vacío)* | Documento vacío | `documento vacío` | Rechazar | El documento identifica a la persona y es su clave inicial: sin él no hay lector. |
| 14 | 7 | `1000000025` | Nombres vacíos | `nombres vacíos` | Rechazar | El nombre aparece en la lista de mora y en los reportes; no se puede adivinar. |

### 2.2 Casos agregados por el grupo

| # | Caso | Ejemplo | Decisión | Resultado / motivo | Por qué |
|---|---|---|---|---|---|
| 15 | Espacios sobrantes en cualquier campo | `  Rayuela ` o `Julio   Cortázar` | Corregir | `trim` y espacios internos repetidos → uno | No cambia el significado y evita registros "distintos" que son el mismo. |
| 16 | ISBN con guiones o espacios | `978-0-00-000039-1` | Corregir | Se guarda `9780000000391` | Es la forma habitual de escribir un ISBN; los guiones no son parte del dato. |
| 17 | Categoría con otra capitalización | `novela`, `NOVELA` | Corregir | `initcap` → `Novela` | Sin esto, cada variante crearía una categoría nueva y los reportes por categoría se partirían. |
| 18 | Correo con mayúsculas | `Ana.Gomez@Correo.co` | Corregir | `lower` → `ana.gomez@correo.co` | Los correos no distinguen mayúsculas en la práctica. El esquema lo exige (`ck_usuario_correo_minusculas`). |
| 19 | Documento con puntos o espacios | `1.000.000.026` | Corregir | Se guarda `1000000026` | En Colombia es común escribir la cédula con puntos; no son parte del dato. |
| 20 | Teléfono con separadores | `(300) 100-0026` | Corregir | Se guarda `3001000026` | Los separadores son formato visual. El indicativo `+57` **no** se corrige (ver 2.4). |
| 21 | Línea en blanco | Un salto de línea de más al final del archivo | Descartar | No se carga ni se registra | No hay ningún dato que corregir; registrarla solo llenaría la bitácora de ruido. |
| 22 | Encabezado distinto al esperado | Archivo sin encabezado, columnas en otro orden, o el CSV de lectores pasado al script de libros | Rechazar todo el archivo | `encabezado no coincide con el esperado (…)` | Con las columnas en otro orden, cada dato iría a la columna equivocada. Sin encabezado, la primera fila de datos se perdería en silencio. |
| 23 | Archivo guardado con `;` | Excel con configuración regional en español | Rechazar | `separador ';' en lugar de ',' (¿guardado desde Excel en español?)` | Es mucho más útil que el genérico `tiene 1 columnas, se esperaban 6`: dice exactamente qué arreglar. |
| 24 | Campo con coma entre comillas | `"Libro, con coma"` | Rechazar | `contiene comillas: no se admiten comas dentro de un campo` | Es una limitación conocida (ver 2.4): se avisa con claridad en vez de reportar columnas de más. |
| 25 | ISBN repetido dentro del mismo archivo | Dos líneas con `9780000000040` | Cargar la primera, rechazar las demás | `isbn repetido en el archivo (primera aparición: línea N)` | Ninguna de las dos está todavía en `libro`, así que la regla "ya existe" no la ve. La primera aparición es la referencia. |
| 26 | Documento repetido dentro del mismo archivo | Dos líneas con `1000000030` | Cargar la primera, rechazar las demás | `documento repetido en el archivo (primera aparición: línea N)` | Igual que el caso 25. |
| 27 | Correo repetido en el archivo, aunque cambie la mayúscula | `ana@x.co` y `ANA@X.co` | Cargar la primera, rechazar las demás | `correo repetido en el archivo (primera aparición: línea N)` | La comparación se hace **después** del `lower`, así que se detecta. |
| 28 | Correo usado por un usuario de otro perfil | El correo de un bibliotecario en el CSV de lectores | Rechazar | `correo ya registrado por otro usuario` | El correo es el login de **todos** los perfiles (`UNIQUE` en `usuario`), no solo de los lectores. |
| 29 | Año en el futuro | `2031` | Rechazar | `año en el futuro (posterior a AAAA)` | Un libro no puede haberse publicado después de hoy. Esta regla es más estricta que el `CHECK` del esquema (que llega hasta 2100). |
| 30 | Demasiados ejemplares | `1000` (¿quiso decir `10`?) | Rechazar | `ejemplares supera el máximo por carga (100)` | Protege de errores de digitación y evita crear miles de filas en `ejemplar`. Además, más de 32 767 rompería el `smallint` de `numero_copia`, y eso tumbaría la carga completa. |
| 31 | Texto más largo que la columna | Un título de 250 caracteres | Rechazar | `título supera 200 caracteres` (lo mismo para autor, categoría, nombres, apellidos y correo) | Sin esta regla, el `INSERT` fallaría con *value too long* y desharía la carga entera, incluidas las filas válidas. |
| 32 | Teléfono vacío | `…,correo@x.co,` | Rechazar | `teléfono vacío` | El teléfono es obligatorio para la notificación de mora; un motivo específico es más claro que "no numérico". |

### 2.3 Discrepancia encontrada en los datos del curso

El README de los datos semilla dice que la fila `9780000000034` prueba "`ejemplares_disponibles` no numérico (`"dos"`)", y el título de la fila dice lo mismo ("Relato sin ejemplares numéricos"). Pero en el archivo real el texto `dos` está en la **quinta** columna, la del año:

```
9780000000034,Relato sin ejemplares numéricos,Autor de Prueba,Novela,dos,3
```

Por eso la validación la rechaza como **`año no numérico`**, que es lo que de verdad trae la fila; el script de referencia del profesor produce el mismo resultado. La regla `ejemplares no numérico` sí existe y atraparía el error si el texto estuviera en la sexta columna; la probamos con el CSV propio.

### 2.4 Limitaciones conocidas (documentadas a propósito)

- **Comas dentro de un campo entre comillas:** no se soportan. La línea se parte por comas sin interpretar las comillas, así que se rechaza con un motivo claro (caso 24). Los CSV del curso no traen comas dentro de un campo.
- **Autores:** se buscan por nombre exacto. `gabriel garcía márquez` en minúsculas crearía otro autor, y dos personas distintas con el mismo nombre no se pueden distinguir. Cada fila del CSV trae un solo autor; la tabla `libro_autor` (N:M) permite agregar coautores después, por la API.
- **Teléfono con indicativo internacional** (`+57 300…`): se rechaza, porque el esquema solo admite dígitos. Quitar el `+` cambiaría la forma del número sin saber si la aplicación lo espera con indicativo o sin él.
- **Un usuario tiene un solo perfil:** un bibliotecario no puede registrarse también como lector con el mismo documento (caso `documento ya registrado (perfil bibliotecario)`).
- **El año actual se toma del reloj del servidor** (`current_date`) al momento de la carga.
