import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { LoggerModule } from 'nestjs-pino';
import { validateEnv } from './config/env.validation';
import { DatabaseModule } from './database/database.module';
import { AlertsModule } from './modules/alerts/alerts.module';
import { AssetsModule } from './modules/assets/assets.module';
import { GeofencesModule } from './modules/geofences/geofences.module';
import { HealthModule } from './modules/health/health.module';
import { PositionsModule } from './modules/positions/positions.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      envFilePath: ['.env', '../../.env'],
      isGlobal: true,
      validate: validateEnv,
    }),
    PrismaModule,
    LoggerModule.forRoot(),
    ScheduleModule.forRoot(),
    DatabaseModule,
    HealthModule,
    RealtimeModule,
    AssetsModule,
    PositionsModule,
    GeofencesModule,
    AlertsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
