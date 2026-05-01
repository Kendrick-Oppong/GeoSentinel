import { ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';

import { Environment } from './config/env.validation';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
    forceCloseConnections: true,
  });
  const config = app.get(ConfigService<Environment>);

  app.useLogger(app.get(Logger));
  app.use(helmet());
  app.enableShutdownHooks();
  app.enableCors({
    origin: config.getOrThrow<string>("WEB_ORIGIN" ),
    credentials: true,
  });
  app.setGlobalPrefix('api');
  app.enableVersioning({ type: VersioningType.URI });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
      validationError: {
        target: false,
        value: false,
      },
    }),
  );

  await app.listen(config.getOrThrow("SERVER_PORT"));
}

void bootstrap();
