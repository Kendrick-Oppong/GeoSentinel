import { Activity, Bell, MapPinned, RadioTower } from 'lucide-react';
import { ConnectionStatus } from '@/components/ui/ConnectionStatus';

const fleetStats = [
  { label: 'Active', value: 12, icon: Activity },
  { label: 'Alerts', value: 3, icon: Bell },
  { label: 'Geofences', value: 8, icon: MapPinned },
];

export default function App() {
  return (
    <main className="flex min-h-screen flex-col bg-background">
      <header className="flex h-14 items-center justify-between border-b px-5">
        <div className="flex items-center gap-3">
          <RadioTower className="size-5 text-primary" aria-hidden="true" />
          <span className="font-semibold">GeoSentinel</span>
        </div>
        <ConnectionStatus status="disconnected" />
      </header>

      <section className="grid min-h-0 flex-1 grid-cols-[1fr_360px]">
        <div className="relative bg-muted">
          <div className="absolute inset-0 grid place-items-center text-sm text-muted-foreground">
            MapLibre dashboard surface
          </div>
        </div>

        <aside className="flex flex-col gap-4 border-l bg-card p-4">
          <div className="grid grid-cols-3 gap-2">
            {fleetStats.map((stat) => (
              <div key={stat.label} className="rounded-md border p-3">
                <stat.icon className="mb-2 size-4 text-primary" aria-hidden="true" />
                <div className="text-2xl font-semibold">{stat.value}</div>
                <div className="text-xs text-muted-foreground">{stat.label}</div>
              </div>
            ))}
          </div>
          <div className="rounded-md border p-4">
            <h1 className="text-sm font-medium">Operational dashboard scaffold</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Feature folders are ready for map layers, asset panels, geofences, alerts, replay,
              sockets, and API services.
            </p>
          </div>
        </aside>
      </section>
    </main>
  );
}
