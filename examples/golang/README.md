# Go + GORM + SQLite Example

Minimal example demonstrating NVOI deployment.

## What It Does

- Visit `/` → Creates random user → Returns all users
- Visit `/health` → Health check
- Database persists across deployments

## Prerequisites

1. Own a domain and add it to Cloudflare DNS
2. Hetzner Cloud account
3. Run `make build` from project root

## Deploy

```bash
# Setup
cp .env.example .env
vim .env  # Add your tokens

# Update domain in deploy.yml
vim deploy.yml  # Set domain/subdomain

# Deploy
make example-deploy
```

## Test

```bash
# After deployment
curl https://yoursubdomain.yourdomain.com/
curl https://yoursubdomain.yourdomain.com/health
```

## Local Test

```bash
make example-run
curl http://localhost:3000/
```

## Response Example

```json
{
  "message": "User created on this visit!",
  "new_user": {
    "id": 1,
    "name": "Alice Smith",
    "email": "user1699999999@example.com"
  },
  "total_users": 1,
  "all_users": [...]
}
```
