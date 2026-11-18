# Pendientes del proyecto Biblioteca

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

Lista de trabajo que **todavía no se ha hecho**. Lo ya entregado (S14, los 4 reportes y el taller de S16) está documentado en el [README](../README.md).

## Para cerrar la entrega del Hito 2 (S16)

El código, la documentación y las evidencias del taller S16 están completos (README, secciones 8.4 y 9). Falta solo la entrega:

- [x] Correr en Docker, seguidos y el mismo día: `datos-prueba.sql`, `reportes.sql` y `verificacion-parte-b.sql`. La verificación dio `sí` en las 9 filas.
- [x] Correr la Parte A en Docker: 11 de 11.
- [x] Capturas de S16 en `docs/hito2/capturas/paso8-*.png`.
- [x] Hacer `git push` a la rama `main`.
- [ ] Invitar al profesor como colaborador del repositorio privado (*Settings → Collaborators*). Sin eso, no puede ver el repositorio.
- [ ] Subir al campus un `.txt` con el enlace del repositorio.

## Opcional (no suma a la rúbrica)

| Qué | Detalle |
|---|---|
| Retos R1 a R3 del taller S16 | R1: el ejercicio 11 con `GROUP BY` + `HAVING count(…) = …` (y por qué `count(*)` no da lo mismo que `count(DISTINCT …)`); R2: las dos versiones del 11 con una categoría sin productos; R3: comparar lo que gastó cada cliente referido con lo que gastó quien lo refirió. |

## Siguientes hitos

| Cuándo | Qué falta |
|---|---|
| **S20 / Hito 3** | El análisis del esquema `biblioteca` ya está en la Parte B del S19 (`docs/hito3/S19-taller-esquemas.md`): las 9 tablas en FNBC. Falta en S20: aplicar los dos cambios propuestos (FK compuesta `perfil` ↔ `lector`/`bibliotecario` y `UNIQUE` sin mayúsculas en `categoria` y `autor`), decidir si se desnormaliza alguna columna a propósito y entregar el documento del Hito 3. |
| **Hito 4** | Procedimiento almacenado y trigger, a partir de las reglas que el esquema no garantiza (README, sección 4): máximo 3 préstamos activos, no prestar a un lector en mora, coherencia de perfiles, etc. |
| **Hito 5** | Roles de PostgreSQL con privilegios mínimos, API REST en Node.js y login con contraseñas bcrypt. La API puede leer los reportes de las 4 vistas que ya crea `reportes.sql` (por ejemplo, `biblioteca.reporte_prestamos_mora` para la lista con el botón "Enviar notificación"). |
