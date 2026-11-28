-- CreateEnum
CREATE TYPE "InspectionStatus" AS ENUM ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'REJECTED');

-- CreateTable
CREATE TABLE "Inspection" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "siteId" TEXT,
    "shaft" TEXT,
    "type" TEXT NOT NULL,
    "inspectorName" TEXT,
    "inspectorWallet" TEXT,
    "status" "InspectionStatus" NOT NULL DEFAULT 'PENDING',
    "measuredGradePct" DOUBLE PRECISION,
    "sampleId" TEXT,
    "method" TEXT,
    "findings" TEXT,
    "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Inspection_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Inspection_code_key" ON "Inspection"("code");

-- CreateIndex
CREATE INDEX "Inspection_lotId_idx" ON "Inspection"("lotId");

-- CreateIndex
CREATE INDEX "Inspection_status_idx" ON "Inspection"("status");

-- AddForeignKey
ALTER TABLE "Inspection" ADD CONSTRAINT "Inspection_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
