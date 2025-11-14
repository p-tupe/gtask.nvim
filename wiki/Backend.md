# Backend (Optional)

OAuth proxy in Go. Public instance available at https://app.priteshtupe.com/gtask, or can self-hosted.

## Endpoints

- `POST /auth/start` - Generate auth URL with PKCE
- `GET /auth/callback` - Exchange OAuth code for tokens
- `GET /auth/poll/{state}` - Poll for auth completion
- `POST /auth/refresh` - Refresh expired tokens
- `GET /health` - Health check

## Self-Host

```bash
cd backend
cp google-auth-credentials.example.json google-auth-credentials.json
# Edit google-auth-credentials.json with your Google OAuth credentials
docker compose up -d
```

Update Neovim config:

```lua
require('gtask').setup({
  proxy_url = "http://localhost:3000"
})
```
