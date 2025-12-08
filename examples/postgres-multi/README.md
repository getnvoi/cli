# PostgreSQL Multi-Instance Example

Production setup with app on master server and PostgreSQL on dedicated worker server.

## Architecture

```
┌─────────────────────────────────────┐
│  Master Server (cx32)               │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  K3s Server Mode                    │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ App Pod                      │  │
│  │ - Port 3000                  │  │
│  │ - Connects to:               │  │
│  │   postgres-service:5432      │  │
│  └──────────────────────────────┘  │
│                                     │
│  Private IP: 10.0.0.1               │
└─────────────────────────────────────┘
            │
            │ K3s Cluster Network (WireGuard)
            │
┌─────────────────────────────────────┐
│  Worker Server (cx42)               │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  K3s Agent Mode                     │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ PostgreSQL StatefulSet       │  │
│  │ - Service: postgres-service  │  │
│  │ - Port: 5432                 │  │
│  │ - Volume: /var/lib/postgres  │  │
│  └──────────────────────────────┘  │
│                                     │
│  Private IP: 10.0.0.2               │
│  Volume: /opt/postgres_data         │
└─────────────────────────────────────┘
```

## Cost

- **Master**: 1x cx32 (~€10/month)
- **Worker**: 1x cx42 (~€15/month)
- **Total**: ~€25/month

## Benefits

1. **Resource Isolation**: Database gets dedicated server resources
2. **Better Performance**: App and DB don't compete for CPU/memory
3. **Scalability**: Can add more workers for distributed workloads
4. **High Availability**: Foundation for future HA setups

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
   nvoi-cli deploy --config examples/postgres-multi/deploy.yml
   ```

## Verification

```bash
# SSH to master
ssh root@<master-ip>

# Check PostgreSQL pod (should be on worker node)
kubectl get pods -o wide | grep postgres

# SSH to worker node
ssh root@<worker-ip>

# Check volume on worker
ls -la /opt/postgres_data/

# From master: Test service DNS
kubectl run -it --rm debug --image=postgres:16-alpine --restart=Never -- \
  psql postgresql://appuser:$DB_PASSWORD@postgres-service:5432/app_production -c '\dt'
```

## How It Works

1. **Master Server**: Runs K3s in server mode, hosts the app
2. **Worker Server**: Joins K3s cluster as agent, runs PostgreSQL
3. **K3s Networking**: Private network (10.0.0.0/16) between nodes
4. **Service DNS**: App connects via `postgres-service:5432`
5. **Volume**: PostgreSQL data persists on worker node filesystem

## Features

- ✅ PostgreSQL 16 Alpine on dedicated server
- ✅ Persistent data storage on worker
- ✅ K3s service discovery
- ✅ Private cluster networking
- ✅ Resource isolation
- ✅ Production-ready setup
