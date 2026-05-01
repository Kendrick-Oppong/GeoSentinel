import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/database/prisma.service';

@Injectable()
export class AssetsRepository {
  constructor(private readonly prisma: PrismaService) {}

  findMany() {
    return this.prisma.asset.findMany({ orderBy: { name: 'asc' } });
  }
}
