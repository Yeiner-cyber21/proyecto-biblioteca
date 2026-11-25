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
| **Hito 3** | **Entregado el 24/11/2026** con el commit «Entrega hito 3» en `main` y el link del repositorio en el campus. Contenido: `docs/hito3/hito3-documento-normalizacion.md`, `postgres/init/` actualizado, `postgres/scripts/hito3/normalizacion.sql` y los reportes del S16 sobre el esquema nuevo (`docs/hito3/hito3-evidencias.md`). |
| **Hito 4** | Entrega el **30/11/2026**. Listo en el repositorio: `postgres/scripts/hito4/programacion.sql` (también `postgres/init/03_programacion.sql`), `pruebas-programacion.sql` y la sección 15 del README ("Lógica en la base de datos"). **Falta:** correr todo en el Docker del grupo, tomar las 4 capturas de `demo-hito4.sql` (o un video de 2 a 3 minutos) y subirlas a `docs/hito4/capturas/`. Fuera de alcance, documentado: "todo libro con al menos un autor" (lo garantiza la carga). |
| **Hito 5** | Roles de PostgreSQL con privilegios mínimos, API REST en Node.js y login con contraseñas bcrypt. La API puede leer los reportes de las 4 vistas que ya crea `reportes.sql` (por ejemplo, `biblioteca.reporte_prestamos_mora` para la lista con el botón "Enviar notificación"). |
