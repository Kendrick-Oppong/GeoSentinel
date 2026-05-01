import { Injectable } from '@nestjs/common';
import sql from 'sql-template-tag';
import { PrismaService } from '@/database/prisma.service';
import { IngestPositionDto } from '../dto/ingest-position.dto';

@Injectable()
export class PositionsRepository {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: IngestPositionDto) {
    const rows = await this.prisma.$queryRaw<Array<{ id: string; recordedAt: Date }>>(sql`
      INSERT INTO positions (asset_id, location, speed, heading, battery)
      VALUES (
        ${dto.assetId},
        ST_SetSRID(ST_MakePoint(${dto.lng}, ${dto.lat}), 4326)::geography,
        ${dto.speed},
        ${dto.heading},
        ${dto.battery ?? null}
      )
      RETURNING id, recorded_at AS "recordedAt"
    `);

    return rows[0]!;
  }
}
