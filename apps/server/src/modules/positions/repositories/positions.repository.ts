import { Injectable } from '@nestjs/common';
import sql from 'sql-template-tag';
import { PrismaService } from '@/database/prisma.service';
import { IngestPositionDto } from '../dto/ingest-position.dto';

@Injectable()
export class PositionsRepository {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: IngestPositionDto) {
    const results = await this.createMany([dto]);
    return results[0]!;
  }

  async createMany(dtos: IngestPositionDto[]) {
    const results = [];
    for (const dto of dtos) {
      const recordedAt = dto.recordedAt ? new Date(dto.recordedAt) : new Date();

      const rows = await this.prisma.$queryRaw<Array<{ id: bigint; recordedAt: Date }>>(sql`
        INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
        VALUES (
          ${dto.assetId},
          ST_SetSRID(ST_MakePoint(${dto.lng}, ${dto.lat}), 4326)::geography,
          ${dto.speed},
          ${dto.heading},
          ${dto.battery ?? null},
          ${recordedAt}
        )
        RETURNING id, recorded_at AS "recordedAt"
      `);

      const result = rows[0]!;
      results.push({
        ...result,
        id: result.id.toString(),
      });
    }

    return results;
  }
}
