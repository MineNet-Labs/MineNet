import { PartialType } from '@nestjs/swagger';
import { CreateShaftDto } from './create-shaft.dto.js';

export class UpdateShaftDto extends PartialType(CreateShaftDto) {}
