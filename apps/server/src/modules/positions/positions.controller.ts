import { Body, Controller, Post, UseGuards, Req } from '@nestjs/common';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { IngestPositionDto } from './dto/ingest-position.dto';
import { PositionsRepository } from './repositories/positions.repository';
import { ApiKeyGuard } from '../../common/guards/api-key.guard';
import type { Request } from 'express';

interface AuthenticatedRequest extends Request {
  assetId: string;
}

@Controller('positions')
export class PositionsController {
  constructor(
    private readonly positionsRepository: PositionsRepository,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  @Post('ingest')
  @UseGuards(ApiKeyGuard)
  async ingest(
    @Body() dto: IngestPositionDto | IngestPositionDto[],
    @Req() req: AuthenticatedRequest,
  ) {
    const dtos = Array.isArray(dto) ? dto : [dto];
    const assetId = req.assetId;

    const results = await this.positionsRepository.createMany(
      dtos.map((d) => ({ ...d, assetId })),
    );

    // Broadcast each position to the realtime gateway
    for (let i = 0; i < results.length; i++) {
      const position = results[i]!;
      const originalDto = dtos[i]!;

      this.realtimeGateway.emitPositionUpdate({
        assetId,
        lat: originalDto.lat,
        lng: originalDto.lng,
        speed: originalDto.speed,
        heading: originalDto.heading,
        battery: originalDto.battery ?? null,
        recordedAt: position.recordedAt.toISOString(),
      });
    }

    return results;
  }
}
