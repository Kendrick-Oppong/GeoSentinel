import { WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import type { Server } from 'socket.io';
import type { ServerToClientEvents } from '@geosentinel/shared';

@WebSocketGateway({ cors: { origin: '*' } })
export class RealtimeGateway {
  @WebSocketServer()
  private readonly server!: Server;

  emitPositionUpdate(payload: ServerToClientEvents['position:update']) {
    this.server.emit('position:update', payload);
  }

  emitAlert(payload: ServerToClientEvents['alert:new']) {
    this.server.emit('alert:new', payload);
  }
}
