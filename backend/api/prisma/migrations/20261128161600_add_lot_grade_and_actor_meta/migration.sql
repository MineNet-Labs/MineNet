-- AlterTable
ALTER TABLE "LotEvent" ADD COLUMN     "actorName" TEXT,
ADD COLUMN     "actorRole" TEXT;

-- AlterTable
ALTER TABLE "MineralLot" ADD COLUMN     "gradePct" DOUBLE PRECISION,
ADD COLUMN     "shaftId" TEXT;

-- CreateIndex
CREATE INDEX "MineralLot_organizationId_idx" ON "MineralLot"("organizationId");

-- CreateIndex
CREATE INDEX "MineralLot_siteId_idx" ON "MineralLot"("siteId");
