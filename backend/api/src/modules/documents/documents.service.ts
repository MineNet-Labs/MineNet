import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { keccak256 } from 'viem';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  UploadDocumentDto,
  VerifyDocumentHashDto,
} from './dto/document.dto.js';

export type UploadedFileLike = {
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
};

@Injectable()
export class DocumentsService {
  private readonly uploadsDir = join(process.cwd(), 'uploads');
  private readonly encryptionKey: Buffer;

  constructor(private readonly prisma: PrismaService) {
    // Derive a 32-byte AES-256 key from env secret (replace with KMS in production)
    const secret =
      process.env.DOCUMENT_ENCRYPTION_KEY ??
      process.env.JWT_SECRET ??
      'minenet-dev-document-key';
    this.encryptionKey = createHash('sha256').update(secret).digest();
  }

  private encrypt(plain: Buffer): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.encryptionKey, iv);
    const encrypted = Buffer.concat([cipher.update(plain), cipher.final()]);
    const authTag = cipher.getAuthTag();
    // Format: [12-byte IV][16-byte GCM auth tag][ciphertext]
    return Buffer.concat([iv, authTag, encrypted]);
  }

  private decrypt(blob: Buffer): Buffer {
    const iv = blob.subarray(0, 12);
    const authTag = blob.subarray(12, 28);
    const ciphertext = blob.subarray(28);
    const decipher = createDecipheriv('aes-256-gcm', this.encryptionKey, iv);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  }

  async upload(file: UploadedFileLike | undefined, dto: UploadDocumentDto) {
    if (!file || !file.buffer) {
      throw new BadRequestException('A file must be uploaded in the "file" field');
    }

    if (dto.organizationId) {
      const org = await this.prisma.organization.findUnique({
        where: { id: dto.organizationId },
      });
      if (!org) {
        throw new NotFoundException(`Organization ${dto.organizationId} not found`);
      }
    }

    let lotOwnerWallet: string | null = null;
    if (dto.lotId) {
      const lot = await this.prisma.mineralLot.findUnique({
        where: { id: dto.lotId },
      });
      if (!lot) {
        throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
      }
      lotOwnerWallet = lot.ownerWallet;
    }

    const sha256Hash = `0x${createHash('sha256').update(file.buffer).digest('hex')}`;
    const keccak256Hash = keccak256(new Uint8Array(file.buffer));

    const storageKey = `${randomUUID()}.enc`;
    await mkdir(this.uploadsDir, { recursive: true });
    await writeFile(join(this.uploadsDir, storageKey), this.encrypt(file.buffer));

    const doc = await this.prisma.document.create({
      data: {
        docType: dto.docType,
        fileName: file.originalname,
        mimeType: file.mimetype || 'application/octet-stream',
        sizeBytes: file.size,
        storageKey,
        sha256Hash,
        keccak256Hash,
        encrypted: true,
        uploadedBy: dto.uploadedBy,
        organizationId: dto.organizationId,
        lotId: dto.lotId,
      },
    });

    if (dto.lotId) {
      await this.prisma.lotEvent.create({
        data: {
          lotId: dto.lotId,
          eventType: 'DOCUMENT_ADDED',
          actorWallet:
            lotOwnerWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: dto.uploadedBy,
          actorRole: 'Miner',
          dataHash: keccak256Hash,
          detail: `${dto.docType} uploaded: ${file.originalname}`,
        },
      });
    }

    return doc;
  }

  async findAll(filters?: {
    organizationId?: string;
    lotId?: string;
    docType?: string;
  }) {
    return this.prisma.document.findMany({
      where: {
        organizationId: filters?.organizationId,
        lotId: filters?.lotId,
        docType: filters?.docType
          ? { contains: filters.docType, mode: 'insensitive' }
          : undefined,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const doc = await this.prisma.document.findUnique({ where: { id } });
    if (!doc) {
      throw new NotFoundException(`Document ${id} not found`);
    }
    return doc;
  }

  async download(id: string) {
    const doc = await this.findOne(id);
    const encryptedBlob = await readFile(join(this.uploadsDir, doc.storageKey));
    const buffer = doc.encrypted ? this.decrypt(encryptedBlob) : encryptedBlob;
    return {
      fileName: doc.fileName,
      mimeType: doc.mimeType,
      buffer,
    };
  }

  async verify(id: string, dto: VerifyDocumentHashDto) {
    const doc = await this.findOne(id);
    const normalize = (h?: string) =>
      h ? (h.startsWith('0x') ? h.toLowerCase() : `0x${h.toLowerCase()}`) : undefined;

    const shaMatches =
      dto.sha256Hash !== undefined
        ? normalize(dto.sha256Hash) === doc.sha256Hash.toLowerCase()
        : null;
    const keccakMatches =
      dto.keccak256Hash !== undefined
        ? normalize(dto.keccak256Hash) === doc.keccak256Hash?.toLowerCase()
        : null;

    if (shaMatches === null && keccakMatches === null) {
      throw new BadRequestException(
        'Provide either sha256Hash or keccak256Hash to verify',
      );
    }

    return {
      documentId: doc.id,
      fileName: doc.fileName,
      valid: (shaMatches ?? true) && (keccakMatches ?? true),
      sha256Matches: shaMatches,
      keccak256Matches: keccakMatches,
      storedSha256: doc.sha256Hash,
      storedKeccak256: doc.keccak256Hash,
    };
  }

  async remove(id: string) {
    const doc = await this.findOne(id);
    await unlink(join(this.uploadsDir, doc.storageKey)).catch(() => undefined);
    return this.prisma.document.delete({ where: { id } });
  }
}
