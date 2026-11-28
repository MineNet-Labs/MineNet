import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBody,
  ApiConsumes,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import type { Response } from 'express';
import {
  DocumentsService,
  type UploadedFileLike,
} from './documents.service.js';
import {
  UploadDocumentDto,
  VerifyDocumentHashDto,
} from './dto/document.dto.js';

@ApiTags('documents')
@Controller('documents')
export class DocumentsController {
  constructor(private readonly documentsService: DocumentsService) {}

  @Post('upload')
  @UseInterceptors(FileInterceptor('file'))
  @ApiConsumes('multipart/form-data')
  @ApiOperation({
    summary:
      'Upload and AES-256-GCM encrypt a document; returns SHA-256 & keccak256 hashes',
  })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['file', 'docType', 'uploadedBy'],
      properties: {
        file: { type: 'string', format: 'binary' },
        docType: { type: 'string', example: 'Certificate' },
        uploadedBy: { type: 'string', example: 'Jean Uwimana' },
        organizationId: { type: 'string' },
        lotId: { type: 'string' },
      },
    },
  })
  upload(
    @UploadedFile() file: UploadedFileLike | undefined,
    @Body() dto: UploadDocumentDto,
  ) {
    return this.documentsService.upload(file, dto);
  }

  @Get()
  @ApiOperation({ summary: 'List stored documents' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'docType', required: false })
  findAll(
    @Query('organizationId') organizationId?: string,
    @Query('lotId') lotId?: string,
    @Query('docType') docType?: string,
  ) {
    return this.documentsService.findAll({ organizationId, lotId, docType });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get document metadata and cryptographic hashes' })
  findOne(@Param('id') id: string) {
    return this.documentsService.findOne(id);
  }

  @Get(':id/download')
  @ApiOperation({ summary: 'Decrypt and download the original document' })
  async download(@Param('id') id: string, @Res() res: Response) {
    const { fileName, mimeType, buffer } =
      await this.documentsService.download(id);
    res.setHeader('Content-Type', mimeType);
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${encodeURIComponent(fileName)}"`,
    );
    res.send(buffer);
  }

  @Post(':id/verify')
  @ApiOperation({
    summary: 'Verify a SHA-256 or keccak256 hash against the stored document',
  })
  verify(@Param('id') id: string, @Body() dto: VerifyDocumentHashDto) {
    return this.documentsService.verify(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete document metadata and encrypted blob' })
  remove(@Param('id') id: string) {
    return this.documentsService.remove(id);
  }
}
