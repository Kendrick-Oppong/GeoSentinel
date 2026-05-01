import { Module } from '@nestjs/common';
import { RealtimeModule } from '../realtime/realtime.module';
import { PositionsController } from './positions.controller';
import { PositionsRepository } from './repositories/positions.repository';

@Module({
  imports: [RealtimeModule],
  controllers: [PositionsController],
  providers: [PositionsRepository],
  exports: [PositionsRepository],
})
export class PositionsModule {}
