# Hito 3. Documento de normalización del esquema `biblioteca`

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

Archivos: esquema nuevo en [`postgres/init/01_esquema.sql`](../../postgres/init/01_esquema.sql) · migración de una base con datos en [`postgres/scripts/hito3/normalizacion.sql`](../../postgres/scripts/hito3/normalizacion.sql) · evidencia de consultas en [`postgres/scripts/hito3/parte-b-evidencia.sql`](../../postgres/scripts/hito3/parte-b-evidencia.sql) · salidas de `psql` en [`hito3-evidencias.md`](hito3-evidencias.md).

## 1. Esquema antes (Hito 2)

| Tabla | Columnas (PK en **negrita**) | FK |
|---|---|---|
| `usuario` | **id_usuario**, documento (UNIQUE), nombres, apellidos, correo (UNIQUE), contrasena_hash, perfil, debe_cambiar_contrasena, activo, fecha_registro | — |
| `lector` | **id_usuario**, telefono | id_usuario → usuario |
| `bibliotecario` | **id_usuario** | id_usuario → usuario |
| `categoria` | **id_categoria**, nombre (UNIQUE) | — |
| `autor` | **id_autor**, nombre (UNIQUE) | — |
| `libro` | **isbn**, titulo, anio_publicacion, id_categoria, activo | id_categoria → categoria |
| `libro_autor` | **isbn, id_autor** | isbn → libro; id_autor → autor |
| `ejemplar` | **isbn, numero_copia**, estado | isbn → libro |
| `prestamo` | **id_prestamo**, id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento, fecha_devolucion; índice único parcial de préstamos abiertos | id_lector → lector; (isbn, numero_copia) → ejemplar; id_bibliotecario → bibliotecario |

## 2. Dependencias funcionales y claves candidatas

Cada dependencia sale de una regla del negocio, no de los datos (S17).

| Tabla | Claves candidatas | Dependencias no triviales (regla) |
|---|---|---|
| `usuario` | {id_usuario}, {documento}, {correo} | id_usuario → todo; documento → id_usuario (un documento es una persona); correo → id_usuario (el correo es el login, único) |
| `lector` | {id_usuario} | id_usuario → telefono (cada lector registra un teléfono) |
| `bibliotecario` | {id_usuario} | ninguna (solo la clave) |
| `categoria` | {id_categoria}, {nombre} | id_categoria → nombre; nombre → id_categoria (cada categoría tiene un nombre único) |
| `autor` | {id_autor}, {nombre} | id_autor → nombre; nombre → id_autor (decisión documentada: un nombre por autor) |
| `libro` | {isbn} | isbn → titulo, anio_publicacion, id_categoria, activo (un ISBN identifica una edición). **No** titulo → isbn: un título puede tener varias ediciones |
| `libro_autor` | {isbn, id_autor} | ninguna (relación N:M) |
| `ejemplar` | {isbn, numero_copia} | isbn, numero_copia → estado (el estado es de cada copia física). **No** isbn → estado |
| `prestamo` | {id_prestamo} | id_prestamo → id_lector, isbn, numero_copia, id_bibliotecario, fecha_prestamo, fecha_vencimiento, fecha_devolucion. No hay clave natural: el mismo ejemplar se puede prestar, devolver y volver a prestar el mismo día |

## 3. Forma normal y problemas encontrados

**Las 9 tablas estaban en FNBC:** en cada dependencia no trivial, el determinante es una clave candidata. Revisamos las señales de alarma del S19, con la consulta de evidencia de cada una (resultado en el Docker del grupo):

| Señal revisada | Consulta de evidencia | Resultado | Conclusión |
|---|---|---|---|
| Listas en una celda o columnas numeradas | teléfonos con más de un valor | 0 | No hay |
| Texto de otra entidad repetido | libros por categoría | categoría por FK (Novela 18, Ciencia 3…) | No hay |
| Clave sustituta sin `UNIQUE` natural | documentos y correos repetidos | 0 y 0 | Protegidas (`UNIQUE`) |
| Datos derivados guardados | `ejemplares_disponibles` y el estado del préstamo | no existen como columnas; se calculan (5 préstamos en mora) | No hay |
| Dato que parece derivado | `fecha_vencimiento = fecha_prestamo + 14` | 30 de 30 | **Histórico**, no redundante (S20, A5) |

**Problemas encontrados** (de integridad, no de forma normal; evidencia: 0 filas hoy, pero ninguna restricción lo garantizaba):
- **P1. El perfil en dos lugares:** `usuario.perfil` y la fila en `lector` o `bibliotecario` podían contradecirse (por ejemplo, un "administrador" que sigue en `lector`).
- **P2. Nombres que solo cambian en mayúsculas:** el `UNIQUE (nombre)` de `categoria` y `autor` aceptaba "Novela" y "novela".

## 4. Cambios aplicados y migración

| Cambio | Resuelve |
|---|---|
| `usuario`: `UNIQUE (id_usuario, perfil)`, destino de las FK compuestas | P1 |
| `lector`: columna `perfil` (`DEFAULT 'lector'`, `CHECK (perfil = 'lector')`) y **FK compuesta** `(id_usuario, perfil) → usuario`, que reemplaza a la FK simple | P1 |
| `bibliotecario`: lo mismo, con `'bibliotecario'` | P1 |
| Índices únicos `lower(categoria.nombre)` y `lower(trim(autor.nombre))` | P2 |
| `carga-libros.sql`: busca categorías y autores sin distinguir mayúsculas (`ON CONFLICT` sobre el índice nuevo y joins con `lower()`) | Que la carga no falle con P2 |

**Migración** (`normalizacion.sql`, receta del S19: evidencia → `BEGIN` → crear → verificar → quitar las FK simples → `COMMIT`), en la base del grupo:
- **Conteos antes = después:** usuario 21, lector 20, bibliotecario 1, categoria 10 y autor 33. `EXCEPT` de `lector` y `bibliotecario` en 0 filas; `perfil` lleno en las 20 + 1 filas.
- **Las reglas nuevas rechazan** cambiar el perfil de un lector, registrar como lector a la bibliotecaria, crear "novela" y crear " gabriel garcía márquez ". La carga reconoce al autor en minúscula sin duplicarlo (`INSERT 0 0`).
- **`init/` probado** en una base aparte (`prueba_init`): `01_esquema.sql` y `02_carga.sql` terminan en `COMMIT` sin errores. La base migrada y una nueva quedan con la misma estructura (`pg_dump -s`).
- **Reportes del S16 sobre el esquema nuevo:** `30 | 20 | 10 | 5`, los 4 reportes con **21, 2, 4 y 5 filas** y la verificación **9 de 9**.

## 5. Desnormalizaciones deliberadas

**Una, para integridad (no para rendimiento): `lector.perfil` y `bibliotecario.perfil`.** Es una copia de `usuario.perfil` con valor constante: en sentido estricto cumple `∅ → perfil`, y es redundancia. **Por qué:** es la forma declarativa de garantizar P1, el mismo patrón que recomendamos en la Parte C del S18. **Cómo se mantiene:** el `CHECK` fija el valor y la FK compuesta obliga a que coincida con `usuario`, así que **no puede desincronizarse**. **Verificación:** la consulta de contradicciones del paso 1 de `normalizacion.sql`, que da 0.

**Lo que decidimos NO desnormalizar:**
- **`ejemplares_disponibles`, que se calcula.** Nuestro volumen es pequeño (37 libros, 104 ejemplares, 30 préstamos). En el S20 medimos, con 303 750 préstamos, que **el índice da casi toda la mejora** (de ~30 a ~4 ms) sin redundancia, y nuestro esquema **ya tiene** ese índice parcial (`ux_prestamo_ejemplar_abierto`). Guardarla exigiría un trigger (Hito 4) y una consulta de descuadre; si una medición futura lo justifica, se agrega con la vista `descuadre` del S20 (A3).
- **El estado del préstamo (mora), que se calcula** con las fechas: guardado, envejecería cada día.
- **El top 20, que queda como vista normal:** con nuestro volumen es inmediato; si crece, pasaría a vista materializada con `REFRESH` diario (S20, A4).

`fecha_vencimiento` **no** es una desnormalización: es un dato histórico del préstamo (S20, A5).

## 6. Esquema después

| Tabla | Cambio | Forma normal |
|---|---|---|
| `usuario` | + `UNIQUE (id_usuario, perfil)` (superclave, no clave candidata nueva) | FNBC |
| `lector` | + `perfil` con `CHECK` y FK compuesta | FNBC, salvo la columna constante `perfil`: redundancia deliberada (sección 5) |
| `bibliotecario` | + `perfil` con `CHECK` y FK compuesta | Igual que `lector` |
| `categoria`, `autor` | + índice único sin distinguir mayúsculas | FNBC |
| `libro`, `libro_autor`, `ejemplar`, `prestamo` | sin cambios | FNBC |

Ninguna tabla queda en 3FN sin estar en FNBC (no hay claves candidatas compuestas que se solapen). La única redundancia es la columna `perfil`, deliberada y protegida. **Pendiente para el Hito 4 (triggers):** máximo 3 préstamos activos, no prestar a un lector en mora, solo prestar ejemplares activos y todo libro con al menos un autor.
