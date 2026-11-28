-- CreateEnum
CREATE TYPE "ReportStatus" AS ENUM ('DRAFT', 'SUBMITTED', 'REVIEWED');

-- CreateEnum
CREATE TYPE "TicketStatus" AS ENUM ('OPEN', 'IN_PROGRESS', 'RESOLVED');

-- AlterTable
ALTER TABLE "Organization" ADD COLUMN     "renewalNote" TEXT,
ADD COLUMN     "renewalRequestedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "SiteReport" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "siteId" TEXT NOT NULL,
    "period" TEXT NOT NULL,
    "author" TEXT NOT NULL,
    "summary" TEXT NOT NULL,
    "productionKg" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "safetyScore" INTEGER NOT NULL DEFAULT 100,
    "complianceNotes" TEXT,
    "status" "ReportStatus" NOT NULL DEFAULT 'SUBMITTED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SiteReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupportTicket" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "portal" TEXT NOT NULL DEFAULT 'miner',
    "category" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "submittedBy" TEXT NOT NULL,
    "organizationId" TEXT,
    "status" "TicketStatus" NOT NULL DEFAULT 'OPEN',
    "resolutionNote" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SupportTicket_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SiteReport_code_key" ON "SiteReport"("code");

-- CreateIndex
CREATE INDEX "SiteReport_siteId_idx" ON "SiteReport"("siteId");

-- CreateIndex
CREATE INDEX "SiteReport_period_idx" ON "SiteReport"("period");

-- CreateIndex
CREATE UNIQUE INDEX "SupportTicket_code_key" ON "SupportTicket"("code");

-- CreateIndex
CREATE INDEX "SupportTicket_portal_status_idx" ON "SupportTicket"("portal", "status");

-- AddForeignKey
ALTER TABLE "SiteReport" ADD CONSTRAINT "SiteReport_siteId_fkey" FOREIGN KEY ("siteId") REFERENCES "MineSite"("id") ON DELETE CASCADE ON UPDATE CASCADE;
