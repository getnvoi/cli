# Rails Single Server Example

Rails 8 app with PostgreSQL and Solid Trifecta on a single server.

## Setup

```bash
cp .env.production.example .env.production
# Fill in credentials
nvoi deploy
```

## What it does

- Creates a new user on every page visit
- Lists all users
- Runs Solid Queue worker as separate process
