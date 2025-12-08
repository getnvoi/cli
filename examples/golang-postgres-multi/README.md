# Golang + PostgreSQL Multi-Server Example

Demonstrates 3-server deployment with Golang app and PostgreSQL database on separate nodes.

## Architecture

**3 Servers:**
- **Main (master)**: K3s control plane
- **Worker 1**: Application pods (Golang + Gin)
- **Worker 2**: Database (PostgreSQL StatefulSet)

This setup validates:
- Multi-server provisioning on Hetzner
- K3s cluster formation (master + workers)
- Node affinity (app and database on separate workers)
- Cross-node connectivity via K8s service DNS
- Persistent storage for PostgreSQL

## What It Does

- **Visit `/`**: Creates a random user → Returns all users with hostname
- **Visit `/health`**: Returns health status with database connectivity check
- **Database**: PostgreSQL persists data across deployments

## Prerequisites

1. Domain registered and managed by Cloudflare DNS
2. Hetzner Cloud account with API token
3. NVOI CLI built (`make build` from project root)

## Configuration

The `.env` file contains valid credentials (copied from `examples/golang`).

Update `deploy.yml`:
- `domain`: Your Cloudflare domain
- `subdomain`: Your desired subdomain

## Deploy

```bash
# From project root
make deploy-multi

# Or manually
cd examples/golang-postgres-multi
../../build/nvoi deploy
```

## Deployment Process

1. **Provision 3 Hetzner servers** (master + 2 workers)
2. **Install K3s** on master node
3. **Join workers** to K3s cluster
4. **Deploy PostgreSQL** as StatefulSet on worker
5. **Deploy Golang app** as Deployment on worker
6. **Configure Cloudflare tunnel** for HTTPS access

## Test After Deployment

```bash
# Health check
curl https://golang-pg-multi.yourdomain.com/health

# Create users and view all
curl https://golang-pg-multi.yourdomain.com/

# Multiple requests to see load balancing
for i in {1..5}; do
  curl https://golang-pg-multi.yourdomain.com/ | jq '.hostname'
done
```

## Verify Multi-Server Setup

SSH into master server:
```bash
ssh root@<master-ip>

# Check K3s cluster nodes
kubectl get nodes -o wide

# Verify pods are on different nodes
kubectl get pods -o wide

# Check StatefulSet (database)
kubectl get statefulsets

# Check services
kubectl get services
```

Expected output:
- 3 nodes: 1 master (control-plane) + 2 workers
- PostgreSQL pod on one worker node
- App pods on another worker node
- Database accessible via `db-example-golang-pg-multi:5432`

## Database Connection

App connects to PostgreSQL via K8s service DNS:
```
postgresql://appuser:password@db-example-golang-pg-multi:5432/app_production
```

Service name pattern: `db-{application.name}`

## Local Testing

Test the app locally (without deployment):
```bash
# Install PostgreSQL locally first
docker run -d \
  -p 5432:5432 \
  -e POSTGRES_DB=app_production \
  -e POSTGRES_USER=appuser \
  -e POSTGRES_PASSWORD=secure_postgres_password_12345 \
  postgres:16-alpine

# Update DATABASE_URL for local connection
export DATABASE_URL="postgresql://appuser:secure_postgres_password_12345@localhost:5432/app_production"

# Run the app
go run main.go

# Test endpoints
curl http://localhost:3000/health
curl http://localhost:3000/
```

## Response Example

```json
{
  "hostname": "web-7d4f8b9c5-abc12",
  "message": "User created on this visit!",
  "new_user": {
    "id": 1,
    "name": "Alice Smith",
    "email": "user-1699999999@example.com",
    "created_at": "2024-11-20T12:00:00Z",
    "updated_at": "2024-11-20T12:00:00Z"
  },
  "total_users": 5,
  "all_users": [...]
}
```

## Cleanup

```bash
# Delete all resources
../../build/nvoi delete
```

This removes:
- All 3 Hetzner servers
- Firewall rules
- Private network
- Cloudflare tunnel

## Troubleshooting

### Database connection fails
```bash
# SSH to master node
ssh root@<master-ip>

# Check database pod
kubectl get pods | grep db-
kubectl logs <db-pod-name>

# Check database service
kubectl get service db-example-golang-pg-multi

# Test connection from app pod
kubectl exec -it <app-pod> -- sh
nc -zv db-example-golang-pg-multi 5432
```

### App not starting
```bash
# Check app pods
kubectl get pods
kubectl describe pod <app-pod-name>
kubectl logs <app-pod-name>

# Verify environment variables
kubectl get secret example-golang-pg-multi-db -o yaml
```

### Workers not joining cluster
```bash
# On master
kubectl get nodes

# Check K3s logs on worker
ssh root@<worker-ip>
journalctl -u k3s-agent -f
```

## Technical Details

- **Language**: Go 1.21
- **Framework**: Gin (HTTP router)
- **ORM**: GORM with PostgreSQL driver
- **Database**: PostgreSQL 16 (alpine)
- **Orchestration**: Kubernetes (K3s)
- **Multi-stage build** for minimal image size
- **Health checks** for zero-downtime deployments
- **Connection pooling** (10 idle, 100 max connections)
