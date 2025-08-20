# Gtask Auth Proxy

A secure OAuth proxy service for gtask.nvim plugin that handles Google OAuth credentials. This service enables users to authenticate with Google Tasks without requiring manual Google Cloud setup.

## Production Deployment

This service is designed to be deployed by the plugin maintainer and used by all plugin users.

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

## Deployment

### Railway

```bash
# Install Railway CLI
curl -fsSL https://railway.app/install.sh | sh

# Deploy
railway login
railway new
railway add
railway deploy
```

### Vercel (with serverless functions)

- Create `api/` directory and convert handlers to serverless functions

### Google Cloud Run / AWS Lambda

- Build Docker image or deploy directly

## API Endpoints

- `POST /auth/start` - Generate secure authorization URL with PKCE
- `GET /auth/callback` - Handle OAuth redirect and exchange tokens
- `GET /auth/poll/{state}` - Poll for authentication completion
- `POST /auth/refresh` - Refresh expired access tokens  
- `GET /health` - Health check and status

## Security Features

- **PKCE Implementation** - Proof Key for Code Exchange with secure random generation
- **State Management** - Automatic cleanup of expired states (10 minute expiry)
- **No Data Persistence** - Only stores temporary authentication states
- **CORS Support** - Proper cross-origin headers for browser clients
- **Token Pass-through** - Tokens are not logged or stored permanently
- **Standard Library Only** - No external dependencies, minimal attack surface

## Architecture

- **Stateless Design** - Horizontally scalable, no persistent storage needed
- **In-Memory State** - PKCE states stored temporarily in memory with cleanup
- **Polling-Based** - Plugin polls for completion, eliminating need for webhooks
- **Production Ready** - Handles concurrent users, automatic scaling support

## Environment Requirements

- **Go 1.25+**
- **Standard library only** - No external dependencies
- **Internet access** - For Google OAuth API calls
- **HTTPS recommended** - For production deployment security
