# Gtask Auth Proxy

A secure OAuth proxy service for gtask.nvim plugin that handles Google OAuth credentials. This service enables users to authenticate with Google Tasks without requiring manual Google Cloud setup.

## API Endpoints

- `POST /auth/start` - Generate secure authorization URL with PKCE
- `GET /auth/callback` - Handle OAuth redirect and exchange tokens
- `GET /auth/poll/{state}` - Poll for authentication completion
- `POST /auth/refresh` - Refresh expired access tokens
- `GET /health` - Health check and status

## Local Development

1. **Set environment variables:**

```bash
# Required
export GOOGLE_CLIENT_ID="your-dev-client-id"
export GOOGLE_CLIENT_SECRET="your-dev-client-secret"

# Optional
export REDIRECT_URI="http://localhost:3000/auth/callback"
export PORT="3000"
```

2. **Run:**

```bash
go run main.go
```

## Deployment

### Using Docker

### Using Systemd
