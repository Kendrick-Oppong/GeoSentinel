import { Body, Controller, Post } from '@nestjs/common';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { IngestPositionDto } from './dto/ingest-position.dto';
import { PositionsRepository } from './repositories/positions.repository';

@Controller('positions')
export class PositionsController {
  constructor(
    private readonly positionsRepository: PositionsRepository,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  @Post()
  async ingest(@Body() dto: IngestPositionDto) {
    const position = await this.positionsRepository.create(dto);
    this.realtimeGateway.emitPositionUpdate({
      assetId: dto.assetId,
      lat: dto.lat,
      lng: dto.lng,
      speed: dto.speed,
      heading: dto.heading,
      battery: dto.battery ?? null,
      recordedAt: position.recordedAt.toISOString(),
    });

    return position;
  }
}
