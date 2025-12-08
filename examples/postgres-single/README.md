# PostgreSQL Single Instance Example

Simple deployment with app and PostgreSQL database on one server.

## Architecture

```
┌─────────────────────────────────────┐
│  Server (cx32)                      │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ App Container                │  │
│  │ - Port 3000                  │  │
│  │ - Connects to localhost:5432 │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ PostgreSQL Container         │  │
│  │ - Port 5432                  │  │
│  │ - Volume: postgres_data      │  │
│  └──────────────────────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

## Cost

- **Server**: 1x cx32 (~€10/month)
- **Total**: ~€10/month

## Setup

1. **Copy environment file**:
   ```bash
   cp .env.production.example .env.production
   ```

2. **Edit `.env.production`** with your credentials:
   ```bash
   CLOUDFLARE_API_TOKEN=your_token
   CLOUDFLARE_ACCOUNT_ID=your_account_id
   HETZNER_API_TOKEN=your_token
   DB_PASSWORD=your_secure_password
   SECRET_KEY_BASE=$(openssl rand -hex 64)
   JWT_SECRET=$(openssl rand -hex 32)
   ```

3. **Deploy**:
   ```bash
   nvoi-cli deploy --config examples/postgres-single/deploy.yml
   ```

## Verification

```bash
# SSH to server
ssh root@<server-ip>

# Check PostgreSQL pod
kubectl get pods | grep postgres

# Check volume
ls -la /opt/postgres_data/

# Test connection
kubectl exec -it postgres-0 -- psql -U appuser -d app_production -c '\dt'
```

## Features

- ✅ PostgreSQL 16 Alpine
- ✅ Persistent data storage
- ✅ Health checks
- ✅ Automatic backups (via volume)
- ✅ Simple single-server setup
