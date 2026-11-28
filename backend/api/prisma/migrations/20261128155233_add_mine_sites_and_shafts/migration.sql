-- CreateEnum
CREATE TYPE "SiteStatus" AS ENUM ('ACTIVE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "ShaftStatus" AS ENUM ('OPERATIONAL', 'MAINTENANCE', 'CLOSED');

-- AlterTable
ALTER TABLE "MineralLot" ADD COLUMN     "siteId" TEXT;

-- AlterTable
ALTER TABLE "Organization" ADD COLUMN     "contactName" TEXT;

-- CreateTable
CREATE TABLE "MineSite" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "district" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "status" "SiteStatus" NOT NULL DEFAULT 'ACTIVE',
    "areaHa" DOUBLE PRECISION NOT NULL,
    "minerals" TEXT[],
    "licence" TEXT NOT NULL,
    "licenceExpiry" TIMESTAMP(3) NOT NULL,
    "manager" TEXT NOT NULL,
    "lastActivity" TIMESTAMP(3),
    "organizationId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MineSite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MineShaft" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "depthM" DOUBLE PRECISION NOT NULL,
    "mineral" TEXT NOT NULL,
    "status" "ShaftStatus" NOT NULL DEFAULT 'OPERATIONAL',
    "lastInspection" TIMESTAMP(3),
    "siteId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MineShaft_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "MineSite_code_key" ON "MineSite"("code");

-- CreateIndex
CREATE INDEX "MineSite_organizationId_idx" ON "MineSite"("organizationId");

-- CreateIndex
CREATE UNIQUE INDEX "MineShaft_code_key" ON "MineShaft"("code");

-- CreateIndex
CREATE INDEX "MineShaft_siteId_idx" ON "MineShaft"("siteId");

-- AddForeignKey
ALTER TABLE "MineSite" ADD CONSTRAINT "MineSite_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MineShaft" ADD CONSTRAINT "MineShaft_siteId_fkey" FOREIGN KEY ("siteId") REFERENCES "MineSite"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MineralLot" ADD CONSTRAINT "MineralLot_siteId_fkey" FOREIGN KEY ("siteId") REFERENCES "MineSite"("id") ON DELETE SET NULL ON UPDATE CASCADE;
