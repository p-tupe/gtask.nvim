# Gtask Auth Proxy

A secure OAuth proxy service for gtask.nvim plugin that handles Google OAuth credentials. This service enables users to authenticate with Google Tasks without requiring manual Google Cloud setup.

## API Endpoints

- `POST /auth/start` - Generate secure authorization URL with PKCE
- `GET /auth/callback` - Handle OAuth redirect and exchange tokens
- `GET /auth/poll/{state}` - Poll for authentication completion
- `POST /auth/refresh` - Refresh expired access tokens
- `GET /health` - Health check and status

## Development

```bash
# Add your credentials
cp google-auth-credentials.example.json google-auth-credentials.json

# Run server
go run main.go
```

## Deployment

### Using Docker

### Using Systemd
