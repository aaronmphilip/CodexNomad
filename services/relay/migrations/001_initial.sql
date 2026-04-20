create table if not exists public.subscriptions (
  user_id text primary key,
  email text,
  provider text,
  status text not null default 'free',
  plan text,
  country text,
  subscription_id text,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.cloud_servers (
  id text primary key,
  user_id text not null,
  agent text not null default 'codex',
  region text not null,
  country text,
  status text not null default 'creating',
  droplet_id bigint,
  public_ipv4 text,
  tailscale_hostname text,
  tailscale_auth_key_id text,
  repo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists cloud_servers_user_status_idx
  on public.cloud_servers (user_id, status, created_at desc);

create table if not exists public.session_mappings (
  id text primary key,
  user_id text not null,
  server_id text references public.cloud_servers(id) on delete set null,
  daemon_session_id text,
  agent text not null default 'codex',
  mode text not null default 'local',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.webhook_events (
  id text primary key,
  provider text not null,
  event_type text not null,
  user_id text,
  processed boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;
alter table public.cloud_servers enable row level security;
alter table public.session_mappings enable row level security;
alter table public.webhook_events enable row level security;

create policy "users read own subscription" on public.subscriptions
  for select using (auth.uid()::text = user_id);

create policy "users read own cloud servers" on public.cloud_servers
  for select using (auth.uid()::text = user_id);

create policy "users read own session mappings" on public.session_mappings
  for select using (auth.uid()::text = user_id);
