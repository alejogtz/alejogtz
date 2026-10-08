# Nexu — Deploy local (Omarchy)

Documentación del stack local de Nexu (backend Rails + front Angular team/website) en la laptop Omarchy.

## Respuesta corta: ¿dónde vive el deploy?

**Antes:** los servicios corrían desde `~/environment/prestemos_backend` y `~/environment/nexu-front` (el workspace de desarrollo).

**Ahora:** el runtime es **independiente**:

| Rol | Ruta |
|-----|------|
| Workspace (código diario) | `~/environment/{prestemos_backend,nexu-front}` |
| Deploy / runtime | `~/nexu-deploy/{backend,frontend}` |
| Website estático (nginx) | `/srv/nexu/website` |
| Scripts / configs | `~/environment/local-deploy/` |

`deploy-backend.sh` y `deploy-frontend.sh` trabajan sobre **`~/nexu-deploy`** (clone git propio). No mutan el working tree de `environment` salvo que pases `--from-workspace` (rsync workspace → deploy).

## URLs locales

| URL | Qué sirve |
|-----|-----------|
| http://nexu-backend.local | API Rails (Puma `:3000` vía nginx) |
| http://nexu.team.local | CRM Angular (Express `:3001` + API same-origin) |
| http://nexu.website.local | Website Angular (nginx → `/srv/nexu/website`) |

En la LAN, en el cliente:

```
192.168.0.118 nexu-backend.local nexu.team.local nexu.website.local
```

Firewall del servidor:

```bash
sudo ufw allow 80/tcp comment 'nexu local-deploy'
sudo ufw reload
```

## Arquitectura

```
Browser / LAN
    │ :80 Host header
    ▼
nginx
  ├─ nexu-backend.local  → 127.0.0.1:3000  (Puma, ~/nexu-deploy/backend)
  ├─ nexu.team.local
  │     /api/config      → /srv/nexu/team-api-config.json  (api.url = "")
  │     /auth|/oauth|…   → 127.0.0.1:3000  (Host = nexu.team.local)
  │     /                → 127.0.0.1:3001  (Express, ~/nexu-deploy/frontend)
  └─ nexu.website.local
        /api/config      → /srv/nexu/website-api-config.json
        estáticos        → /srv/nexu/website
        /auth|/oauth|…   → 127.0.0.1:3000
```

Postgres/Redis(Valkey) locales; `RAILS_ENV=development`.

## Por qué API same-origin en team

Si el SPA en `nexu.team.local` llamaba a `nexu-backend.local`, Devise fallaba:

```
HTTP Origin header (http://nexu.team.local) didn't match request.base_url (http://nexu-backend.local)
→ 401
```

Eso rompía el login y Doorkeeper devolvía `invalid_request` / `missing_param`.  
Solución: nginx hace de API en el mismo host; `/api/config` fuerza `api.url: ""`.

## Website ≠ WordPress

En producción, `server.js` con `BUILD_ENV=website` proxea `/` a `landing.nexu.mx` (WordPress).  
En local **no** usamos ese Express para website: nginx sirve el build Angular desde `/srv/nexu/website`.

## Comandos

### Setup (una vez)

```bash
cd ~/environment/local-deploy
./scripts/setup.sh          # nginx, valkey, hosts, clones en ~/nexu-deploy, systemd
./scripts/deploy-backend.sh
./scripts/deploy-frontend.sh
```

### Redeploy por rama (default: clone en ~/nexu-deploy)

```bash
./scripts/deploy-backend.sh feature/mi-rama
./scripts/deploy-frontend.sh feature/mi-rama team
./scripts/deploy-all.sh feature/mi-rama
```

### Publicar cambios locales del workspace sin commit

```bash
./scripts/deploy-backend.sh --from-workspace
./scripts/deploy-frontend.sh --from-workspace team
```

### Flags útiles

- `--force-dirty` — permite deploy con working tree sucio en el clone
- `--migrate` — corre `db:migrate` (usa `expect` por el `db_safeguard`)
- `--from-workspace` — rsync desde `~/environment/...` hacia `~/nexu-deploy/...`

## Servicios systemd --user

```bash
systemctl --user status nexu-backend nexu-sidekiq nexu-team
journalctl --user -u nexu-backend -f
```

Units viven en `~/.config/systemd/user/` y apuntan a `%h/nexu-deploy/...`.

Env overrides: `~/.config/nexu-local/{backend,team,website}.env`

## Archivos clave

- `~/environment/local-deploy/scripts/` — setup + deploy
- `~/environment/local-deploy/nginx/nexu-local.conf` — vhosts
- `~/environment/local-deploy/systemd/` — plantillas de units
- `/etc/nginx/conf.d/nexu-local.conf` — instalado
- `/etc/hosts` — bloque `# nexu-local-deploy`

## Notas Omarchy

- Paquetes: `nginx` + `valkey` (provee Redis), no `apt`.
- `$HOME` es `700` → nginx no puede leer `~/environment/...`; por eso website va a `/srv/nexu`.
- Express force-SSL se evita en team con `X-Forwarded-Proto: https` en nginx (sin parches al repo `nexu-front`).

## Checklist si algo falla

1. `curl -I -H 'Host: nexu.team.local' http://127.0.0.1/`
2. `curl -s -H 'Host: nexu.team.local' http://127.0.0.1/api/config` → debe tener `"url": ""`
3. Login: Origin mismatch en `log/development.log` → revisar nginx same-origin
4. LAN timeout puerto 80 → `sudo ufw allow 80/tcp`
5. Servicios apuntando al workspace viejo → reinstalar units desde `local-deploy/systemd` y `daemon-reload`
