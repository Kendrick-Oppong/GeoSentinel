import { Module } from '@nestjs/common';
import { AssetsController } from './assets.controller';
import { AssetsRepository } from './repositories/assets.repository';

@Module({
  controllers: [AssetsController],
  providers: [AssetsRepository],
  exports: [AssetsRepository],
})
export class AssetsModule {}
