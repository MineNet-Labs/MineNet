-- CreateEnum
CREATE TYPE "TransferKind" AS ENUM ('TRANSPORT', 'WAREHOUSE');

-- CreateEnum
CREATE TYPE "TransferStatus" AS ENUM ('AWAITING_HANDOVER', 'IN_TRANSIT', 'DELIVERED', 'STORED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "CoverType" AS ENUM ('STORAGE', 'TRANSIT', 'STORAGE_AND_TRANSIT');

-- CreateEnum
CREATE TYPE "PolicyStatus" AS ENUM ('REQUESTED', 'QUOTED', 'ACTIVE', 'EXPIRED', 'DECLINED');

-- CreateEnum
CREATE TYPE "ClaimStatus" AS ENUM ('FILED', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "LoanStatus" AS ENUM ('REQUESTED', 'ACTIVE', 'REPAID', 'DECLINED');

-- CreateTable
CREATE TABLE "CustodyTransfer" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "kind" "TransferKind" NOT NULL,
    "partyName" TEXT NOT NULL,
    "partyWallet" TEXT,
    "fromLocation" TEXT NOT NULL,
    "toLocation" TEXT NOT NULL,
    "sealId" TEXT NOT NULL,
    "vehicle" TEXT,
    "status" "TransferStatus" NOT NULL DEFAULT 'AWAITING_HANDOVER',
    "senderConfirmed" BOOLEAN NOT NULL DEFAULT true,
    "receiverConfirmed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CustodyTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InsurancePolicy" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "insurerCode" TEXT NOT NULL,
    "insurerName" TEXT NOT NULL,
    "coverType" "CoverType" NOT NULL,
    "sumInsured" DOUBLE PRECISION NOT NULL,
    "premium" DOUBLE PRECISION,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "status" "PolicyStatus" NOT NULL DEFAULT 'REQUESTED',
    "validFrom" TIMESTAMP(3) NOT NULL,
    "validTo" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InsurancePolicy_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InsuranceClaim" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "policyId" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "status" "ClaimStatus" NOT NULL DEFAULT 'FILED',
    "decisionNote" TEXT,
    "filedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InsuranceClaim_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Loan" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "lotId" TEXT NOT NULL,
    "financierCode" TEXT NOT NULL,
    "financierName" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'USD',
    "ratePct" DOUBLE PRECISION NOT NULL,
    "termDays" INTEGER NOT NULL,
    "purpose" TEXT NOT NULL,
    "status" "LoanStatus" NOT NULL DEFAULT 'REQUESTED',
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dueAt" TIMESTAMP(3),
    "repaidAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Loan_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CustodyTransfer_code_key" ON "CustodyTransfer"("code");

-- CreateIndex
CREATE INDEX "CustodyTransfer_lotId_idx" ON "CustodyTransfer"("lotId");

-- CreateIndex
CREATE INDEX "CustodyTransfer_status_idx" ON "CustodyTransfer"("status");

-- CreateIndex
CREATE UNIQUE INDEX "InsurancePolicy_code_key" ON "InsurancePolicy"("code");

-- CreateIndex
CREATE INDEX "InsurancePolicy_lotId_idx" ON "InsurancePolicy"("lotId");

-- CreateIndex
CREATE INDEX "InsurancePolicy_insurerCode_idx" ON "InsurancePolicy"("insurerCode");

-- CreateIndex
CREATE INDEX "InsurancePolicy_status_idx" ON "InsurancePolicy"("status");

-- CreateIndex
CREATE UNIQUE INDEX "InsuranceClaim_code_key" ON "InsuranceClaim"("code");

-- CreateIndex
CREATE INDEX "InsuranceClaim_policyId_idx" ON "InsuranceClaim"("policyId");

-- CreateIndex
CREATE INDEX "InsuranceClaim_lotId_idx" ON "InsuranceClaim"("lotId");

-- CreateIndex
CREATE INDEX "InsuranceClaim_status_idx" ON "InsuranceClaim"("status");

-- CreateIndex
CREATE UNIQUE INDEX "Loan_code_key" ON "Loan"("code");

-- CreateIndex
CREATE INDEX "Loan_lotId_idx" ON "Loan"("lotId");

-- CreateIndex
CREATE INDEX "Loan_status_idx" ON "Loan"("status");

-- AddForeignKey
ALTER TABLE "CustodyTransfer" ADD CONSTRAINT "CustodyTransfer_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsurancePolicy" ADD CONSTRAINT "InsurancePolicy_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsuranceClaim" ADD CONSTRAINT "InsuranceClaim_policyId_fkey" FOREIGN KEY ("policyId") REFERENCES "InsurancePolicy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsuranceClaim" ADD CONSTRAINT "InsuranceClaim_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Loan" ADD CONSTRAINT "Loan_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "MineralLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
