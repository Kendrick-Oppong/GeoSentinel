import { Controller, Get } from '@nestjs/common';
import { AssetsRepository } from './repositories/assets.repository';

@Controller('assets')
export class AssetsController {
  constructor(private readonly assetsRepository: AssetsRepository) {}

  @Get()
  list() {
    return this.assetsRepository.findMany();
  }
}
