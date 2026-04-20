# Relay and Provisioning Backend

## What It Runs

The Go service in `services/relay` provides:

- WebSocket relay at `GET /v1/relay`.
- Pricing endpoint at `GET /v1/pricing`.
- Trial/cloud start endpoint at `POST /v1/cloud/sessions/start`.
- Cloud node registration endpoint at `POST /v1/cloud/nodes/register`.
- Polar webhook endpoint at `POST /webhooks/polar`.
- Razorpay webhook endpoint at `POST /webhooks/razorpay`.

The relay routes JSON frames by `sid`. It does not decrypt payloads and does not store prompts, terminal output, diffs, file content, or private keys.

## Local Run

```sh
docker compose up --build
```

For production, set these environment variables:

```sh
PUBLIC_BASE_URL=https://relay.codexnomad.pro
CODEXNOMAD_RELAY_URL=wss://relay.codexnomad.pro/v1/relay
RELAY_SHARED_TOKEN=long-random-token
APP_SHARED_TOKEN=long-random-token
ADMIN_SHARED_TOKEN=long-random-token
SUPABASE_URL=https://PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
DIGITALOCEAN_TOKEN=...
TAILSCALE_TAILNET=example.com
TAILSCALE_API_KEY=tskey-api-...
POLAR_WEBHOOK_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...
```

Apply the Supabase schema:

```sh
supabase db push
```

or paste `services/relay/migrations/001_initial.sql` into the Supabase SQL editor.

## Daemon Integration

The daemon connects to:

```sh
CODEXNOMAD_RELAY_URL=wss://relay.codexnomad.pro/v1/relay
CODEXNOMAD_RELAY_TOKEN=$RELAY_SHARED_TOKEN
codexnomad codex
```

The daemon sends `daemon_hello`, then encrypted `ciphertext` frames. The Flutter app sends `mobile_hello`, receives `daemon_ready`, then sends encrypted commands. The relay forwards frames between participants in the same `sid`.

Handshake frames expose only public session keys and routing IDs. All terminal output, file content, prompts, diffs, and commands are inside encrypted envelopes.

## Flutter Integration

Flutter uses:

- `GET /v1/pricing?country=IN` to show Razorpay ₹699/mo or Polar $12/mo.
- `POST /v1/cloud/sessions/start` with `{ "user_id", "email", "country", "agent", "repo_url" }` to start trial/pro cloud provisioning.
- `GET /v1/relay` WebSocket for local and cloud session streaming.

The start-cloud response returns:

```json
{
  "server_id": "srv_...",
  "status": "creating",
  "region": "blr1",
  "estimated_seconds": 45,
  "message": "Building your cloud server."
}
```

The app shows the 45-second spinner with stages:

1. Selecting nearest region.
2. Creating cloud runner.
3. Securing Tailscale tunnel.
4. Installing Codex Nomad daemon.
5. Preparing workspace.
6. Connecting session.

## Polar Webhook Setup

In Polar:

1. Open the product dashboard.
2. Create the $12/month Pro product.
3. Create a webhook endpoint:
   - URL: `https://relay.codexnomad.pro/webhooks/polar`
   - Events: `subscription.created`, `subscription.active`, `subscription.updated`, `subscription.canceled`, `subscription.revoked`, `subscription.past_due`, `order.paid`
4. Copy the webhook signing secret into `POLAR_WEBHOOK_SECRET`.
5. Ensure checkout metadata includes:

```json
{
  "user_id": "supabase-user-id",
  "email": "user@example.com",
  "country": "US"
}
```

## Razorpay Webhook Setup

In Razorpay:

1. Create the ₹699/month subscription plan.
2. Go to Account & Settings -> Webhooks.
3. Create a webhook endpoint:
   - URL: `https://relay.codexnomad.pro/webhooks/razorpay`
   - Secret: a long random value also set as `RAZORPAY_WEBHOOK_SECRET`
   - Events: `subscription.activated`, `subscription.charged`, `subscription.authenticated`, `subscription.paused`, `subscription.halted`, `subscription.cancelled`, `subscription.completed`
4. Ensure subscription `notes` include:

```json
{
  "user_id": "supabase-user-id",
  "email": "user@example.com",
  "country": "IN"
}
```

Razorpay signs raw webhook bodies with HMAC-SHA256 in `X-Razorpay-Signature`; the service verifies the raw body before parsing.

## Cloud Session Reality

Provisioning is automatic: the backend creates a one-time Tailscale auth key, creates a DigitalOcean droplet with cloud-init, installs Tailscale, installs the Codex Nomad daemon, installs the configured CLI commands, and registers the node as ready.

The next required daemon patch is `codexnomad cloud-worker`: a headless cloud runner that can start a Codex/Claude subprocess on backend command and publish its pairing payload to Supabase. Without that, cloud infrastructure can become ready, but the app cannot yet start a no-QR cloud agent session.
