# MineNet Backend

Hybrid backend workspace for MineNet:

- **`api/`** — NestJS (TypeScript) REST API, wallet/JWT auth, RBAC, encrypted off-chain storage, and Prisma/PostgreSQL data layer.
- **`indexer/`** *(planned)* — Go (`go-ethereum`) event indexer for Base L2 smart contracts and IoT/oracle workers.

## Quick Start

1. Start local PostgreSQL and Redis:
   ```powershell
   cd backend
   docker compose up -d
   ```

2. Configure environment variables:
   ```powershell
   cd api
   Copy-Item .env.example .env
   ```

3. Generate Prisma client and run migrations:
   ```powershell
   npx prisma generate
   npx prisma migrate dev
   ```

4. Start the NestJS API:
   ```powershell
   npm run start:dev
   ```

- API base URL: `http://localhost:4000/api/v1`
- Swagger docs: `http://localhost:4000/docs`
- Health check: `http://localhost:4000/api/v1/health`
