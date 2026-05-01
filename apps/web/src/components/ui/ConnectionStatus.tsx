import { Badge } from './badge';

type ConnectionStatusProps = {
  status: 'live' | 'reconnecting' | 'disconnected';
};

export function ConnectionStatus({ status }: ConnectionStatusProps) {
  const label = status === 'live' ? 'Live' : status === 'reconnecting' ? 'Reconnecting' : 'Offline';

  return <Badge variant={status === 'live' ? 'default' : 'secondary'}>{label}</Badge>;
}
