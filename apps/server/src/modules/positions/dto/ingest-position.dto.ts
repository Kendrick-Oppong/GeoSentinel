import { IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Max, Min, IsISO8601 } from 'class-validator';

export class IngestPositionDto {
  @IsOptional()
  @IsString()
  assetId?: string;

  @IsLatitude()
  lat!: number;

  @IsLongitude()
  lng!: number;

  @IsNumber()
  @Min(0)
  speed!: number;

  @IsNumber()
  @Min(0)
  @Max(359)
  heading!: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  battery?: number;

  @IsOptional()
  @IsISO8601()
  recordedAt?: string;
}
