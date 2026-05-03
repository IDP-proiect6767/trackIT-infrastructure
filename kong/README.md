# Kong API Gateway

DB-less mode with declarative config. All routing, rate limiting, CORS, and logging is in `kong.yml`.

## Validate locally

```bash
docker run --rm \
  -e KONG_DATABASE=off \
  -v "$(pwd)/kong.yml:/kong/kong.yml" \
  kong:3 kong config -c /kong/kong.yml parse /kong/kong.yml
```

## Routes summary

| Route group     | Paths                                                                                                                                                             | Backend                     |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| auth-routes     | `/api/v1/auth`, `/api/v1/users`, `/api/v1/admin/users`                                                                                                            | auth-service:8081           |
| business-routes | `/api/v1/workouts`, `/api/v1/exercises`, `/api/v1/workout-logs`, `/api/v1/foods`, `/api/v1/meals`, `/api/v1/stats`, `/api/v1/dashboard`, `/api/v1/users/me/goals` | business-logic-service:8082 |

## Plugins

| Plugin          | Scope       | Config                                     |
| --------------- | ----------- | ------------------------------------------ |
| `rate-limiting` | Global      | 100 req/min per IP                         |
| `rate-limiting` | auth-routes | 20 req/min per IP (brute-force protection) |
| `cors`          | Global      | `*` origins, standard methods              |
| `file-log`      | Global      | stdout                                     |
| `prometheus`    | Global      | metrics at `:8001/metrics`                 |

## Notes

- `/api/v1/admin/users` is exposed but role enforcement is done by Auth Service (`@PreAuthorize("hasRole('ADMIN')")`). Kong is just a router.
- `/api/v1/auth/validate` is public-by-design. Services call it directly via `http://auth-service:8081` over `frontend-net`, NOT through Kong.
- Kong admin API is only published locally in dev (`8001:8001`). In the Swarm stack, admin is not published — use `docker exec` to inspect.

## Reload (DB-less)

Since config is loaded at startup from the mounted file, a config change requires a rolling service update:

```bash
# Dev compose
docker compose -f compose/docker-compose.dev.yml restart kong

# Swarm
docker service update --force trackit_kong
```
