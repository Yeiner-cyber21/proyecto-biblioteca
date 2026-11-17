# `postgres/scripts/`

Scripts SQL sueltos que **no se ejecutan automáticamente** — quedan
disponibles dentro del contenedor en `/scripts` para correrlos a mano,
cuantas veces se quiera, sin perder los datos existentes. Útil para
consultas de una práctica, un `ALTER TABLE`, o probar algo sin tocar el
esquema inicial.

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/mi_consulta.sql
```

O entrar a una sesión interactiva de `psql` y ejecutar el `\i` desde ahí:

```bash
docker compose exec postgres psql -U curso -d curso
curso=# \i /scripts/mi_consulta.sql
```

## Organización de esta carpeta (grupo 9)

| Carpeta | Qué tiene | Ruta dentro de Docker |
|---|---|---|
| `datos/` | Los 4 CSV semilla del curso y el CSV propio del grupo | `/scripts/datos/` |
| `hito2/` | Hito 2 (S14 a S16): cargas, préstamos de prueba, reportes y verificación | `/scripts/hito2/` |
| `hito2/taller-S16/` | Taller de consultas S16 (esquema `tienda`) | `/scripts/hito2/taller-S16/` |
| `hito3/` | Hito 3 (S17 a S20): examen del esquema `biblioteca` | `/scripts/hito3/` |
| `hito3/taller-S18/` | Taller de formas normales S18 (esquema `automotriz`) | `/scripts/hito3/taller-S18/` |
| `hito3/taller-S19/` | Taller de esquemas mal diseñados S19 (4 esquemas) | `/scripts/hito3/taller-S19/` |

Ejemplo:

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/reportes.sql
```

Los comandos de cada hito, en orden, están en el README principal (sección 2).
