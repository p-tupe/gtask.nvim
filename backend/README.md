# Gtask Auth Proxy

A secure OAuth proxy service for gtask.nvim plugin that handles Google OAuth credentials. This service enables users to authenticate with Google Tasks without requiring manual Google Cloud setup.

### Environment Variables

Required for deployment:

```bash
GOOGLE_CLIENT_ID="your-google-oauth-client-id"
GOOGLE_CLIENT_SECRET="your-google-oauth-client-secret"
REDIRECT_URI="https://your-domain.com/auth/callback"
PORT="3000"
```

### Local Development

1. **Set environment variables:**

```bash
export GOOGLE_CLIENT_ID="your-dev-client-id"
export GOOGLE_CLIENT_SECRET="your-dev-client-secret"
export REDIRECT_URI="http://localhost:3000/auth/callback"
export PORT="3000"
```

2. **Run:**

```bash
go run main.go
```

3. **Build:**

```bash
go build -o gtask-proxy main.go
./gtask-proxy
```

## API Endpoints

- `POST /auth/start` - Generate secure authorization URL with PKCE
- `GET /auth/callback` - Handle OAuth redirect and exchange tokens
- `GET /auth/poll/{state}` - Poll for authentication completion
- `POST /auth/refresh` - Refresh expired access tokens
- `GET /health` - Health check and status
