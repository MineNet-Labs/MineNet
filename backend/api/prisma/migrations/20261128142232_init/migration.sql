-- CreateEnum
CREATE TYPE "OrgStatus" AS ENUM ('PENDING', 'VALIDATED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "ParticipantRole" AS ENUM ('ADMIN', 'REGULATOR', 'MINER', 'INSPECTOR', 'TRANSPORTER', 'WAREHOUSE', 'PROCESSOR', 'REFINERY', 'CUSTOMS', 'BUYER', 'INSURER', 'FINANCIER', 'AUDITOR', 'ORACLE', 'ACCREDITOR');

-- CreateEnum
CREATE TYPE "LotStatus" AS ENUM ('REGISTERED', 'INSPECTED', 'REJECTED', 'CONSUMED');

-- CreateTable
CREATE TABLE "Organization" (
    "id" TEXT NOT NULL,
    "orgIdBytes32" TEXT,
    "name" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "rdbNumber" TEXT,
    "tin" TEXT,
    "regulatorName" TEXT,
    "licenceNumber" TEXT,
    "licenceIssuedAt" TIMESTAMP(3),
    "licenceExpiryAt" TIMESTAMP(3),
    "status" "OrgStatus" NOT NULL DEFAULT 'PENDING',
    "payoutWallet" TEXT,
    "contactEmail" TEXT,
    "contactPhone" TEXT,
    "address" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Organization_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "walletAddress" TEXT NOT NULL,
    "fullName" TEXT,
    "email" TEXT,
    "roles" "ParticipantRole"[],
    "isSuspended" BOOLEAN NOT NULL DEFAULT false,
    "nonce" TEXT,
    "organizationId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MineralLot" (
    "id" TEXT NOT NULL,
    "lotCode" TEXT NOT NULL,
    "lotIdBytes32" TEXT,
    "tokenId" BIGINT,
    "mineralType" TEXT NOT NULL,
    "quantityGrams" BIGINT NOT NULL,
    "status" "LotStatus" NOT NULL DEFAULT 'REGISTERED',
    "regulatorHold" BOOLEAN NOT NULL DEFAULT false,
    "openFlags" INTEGER NOT NULL DEFAULT 0,
    "ownerWallet" TEXT NOT NULL,
    "custodianWallet" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MineralLot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LotEvent" (
    "id" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "eventType" TEXT NOT NULL,
    "actorWallet" TEXT NOT NULL,
    "counterparty" TEXT,
    "dataHash" TEXT NOT NULL,
    "txHash" TEXT,
    "blockNumber" BIGINT,
    "detail" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LotEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Document" (
    "id" TEXT NOT NULL,
    "docType" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "storageKey" TEXT NOT NULL,
    "sha256Hash" TEXT NOT NULL,
    "keccak256Hash" TEXT,
    "encrypted" BOOLEAN NOT NULL DEFAULT true,
    "uploadedBy" TEXT NOT NULL,
    "organizationId" TEXT,
    "lotId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Document_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IndexerCursor" (
    "contractName" TEXT NOT NULL,
    "contractAddress" TEXT NOT NULL,
    "chainId" INTEGER NOT NULL,
    "lastBlock" BIGINT NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IndexerCursor_pkey" PRIMARY KEY ("contractName")
);

-- CreateIndex
CREATE UNIQUE INDEX "Organization_orgIdBytes32_key" ON "Organization"("orgIdBytes32");

-- CreateIndex
CREATE UNIQUE INDEX "Organization_rdbNumber_key" ON "Organization"("rdbNumber");

-- CreateIndex
CREATE UNIQUE INDEX "User_walletAddress_key" ON "User"("walletAddress");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "MineralLot_lotCode_key" ON "MineralLot"("lotCode");

-- CreateIndex
CREATE UNIQUE INDEX "MineralLot_lotIdBytes32_key" ON "MineralLot"("lotIdBytes32");

-- CreateIndex
CREATE UNIQUE INDEX "MineralLot_tokenId_key" ON "MineralLot"("tokenId");

-- CreateIndex
CREATE INDEX "LotEvent_lotId_occurredAt_idx" ON "LotEvent"("lotId", "occurredAt");

-- CreateIndex
CREATE INDEX "LotEvent_txHash_idx" ON "LotEvent"("txHash");

-- CreateIndex
CREATE UNIQUE INDEX "Document_storageKey_key" ON "Document"("storageKey");

-- CreateIndex
CREATE INDEX "Document_sha256Hash_idx" ON "Document"("sha256Hash");

-- CreateIndex
CREATE INDEX "Document_lotId_idx" ON "Document"("lotId");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MineralLot" ADD CONSTRAINT "MineralLot_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LotEvent" ADD CONSTRAINT "LotEvent_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Document" ADD CONSTRAINT "Document_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Document" ADD CONSTRAINT "Document_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;
