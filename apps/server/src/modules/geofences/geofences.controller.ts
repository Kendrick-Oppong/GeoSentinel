import { Controller, Get } from '@nestjs/common';

@Controller('geofences')
export class GeofencesController {
  @Get()
  list() {
    return [];
  }
}
