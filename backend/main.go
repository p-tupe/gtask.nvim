package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// PKCE state storage
type PKCEState struct {
	CodeVerifier string
	Timestamp    int64
}

type CompletedAuth struct {
	Tokens    map[string]any
	Timestamp int64
}

type Server struct {
	states        map[string]PKCEState
	completedAuth map[string]CompletedAuth
	mutex         sync.RWMutex
	config        GoogleConfig
}

type GoogleConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
	Scope        string
}

type AuthStartResponse struct {
	AuthURL string `json:"authUrl"`
	State   string `json:"state"`
}

type TokenRequest struct {
	Code  string `json:"code"`
	State string `json:"state"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Details any    `json:"details,omitempty"`
}

func NewServer() *Server {
	config := GoogleConfig{
		ClientID:     getEnvOrDefault("GOOGLE_CLIENT_ID", "your-client-id-here"),
		ClientSecret: getEnvOrDefault("GOOGLE_CLIENT_SECRET", "your-client-secret-here"),
		RedirectURI:  getEnvOrDefault("REDIRECT_URI", "http://127.0.0.1:8080"),
		Scope:        "https://www.googleapis.com/auth/tasks",
	}

	return &Server{
		states:        make(map[string]PKCEState),
		completedAuth: make(map[string]CompletedAuth),
		config:        config,
	}
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// Generate cryptographically secure random string
func generateRandomString(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

// Generate PKCE code verifier and challenge
func generatePKCE() (string, string, error) {
	codeVerifier, err := generateRandomString(96)
	if err != nil {
		return "", "", err
	}

	hash := sha256.Sum256([]byte(codeVerifier))
	codeChallenge := base64.RawURLEncoding.EncodeToString(hash[:])

	return codeVerifier, codeChallenge, nil
}

// Generate a UUID-like state parameter
func generateState() (string, error) {
	return generateRandomString(32)
}

// Clean up expired states
func (s *Server) cleanupExpiredStates() {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	now := time.Now().Unix()
	for state, data := range s.states {
		if now-data.Timestamp > 600 { // 10 minutes
			delete(s.states, state)
		}
	}
}

// Enable CORS
func (s *Server) enableCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
}

// Handle OPTIONS requests for CORS
func (s *Server) handleOptions(w http.ResponseWriter, r *http.Request) {
	s.enableCORS(w)
	w.WriteHeader(http.StatusOK)
}

// POST /auth/start - Generate authorization URL
func (s *Server) handleAuthStart(w http.ResponseWriter, r *http.Request) {
	s.enableCORS(w)

	if r.Method == "OPTIONS" {
		s.handleOptions(w, r)
		return
	}

	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	codeVerifier, codeChallenge, err := generatePKCE()
	if err != nil {
		log.Printf("Error generating PKCE: %v", err)
		http.Error(w, "Failed to generate PKCE parameters", http.StatusInternalServerError)
		return
	}

	state, err := generateState()
	if err != nil {
		log.Printf("Error generating state: %v", err)
		http.Error(w, "Failed to generate state", http.StatusInternalServerError)
		return
	}

	// Store PKCE state
	s.mutex.Lock()
	s.states[state] = PKCEState{
		CodeVerifier: codeVerifier,
		Timestamp:    time.Now().Unix(),
	}
	s.mutex.Unlock()

	// Build authorization URL
	authURL := url.URL{
		Scheme: "https",
		Host:   "accounts.google.com",
		Path:   "/o/oauth2/v2/auth",
	}

	params := authURL.Query()
	params.Set("client_id", s.config.ClientID)
	params.Set("redirect_uri", s.config.RedirectURI)
	params.Set("response_type", "code")
	params.Set("scope", s.config.Scope)
	params.Set("access_type", "offline")
	params.Set("prompt", "consent")
	params.Set("code_challenge", codeChallenge)
	params.Set("code_challenge_method", "S256")
	params.Set("state", state)
	authURL.RawQuery = params.Encode()

	response := AuthStartResponse{
		AuthURL: authURL.String(),
		State:   state,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// POST /auth/token - Exchange authorization code for tokens
func (s *Server) handleToken(w http.ResponseWriter, r *http.Request) {
	s.enableCORS(w)

	if r.Method == "OPTIONS" {
		s.handleOptions(w, r)
		return
	}

	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if req.Code == "" || req.State == "" {
		http.Error(w, "Missing code or state parameter", http.StatusBadRequest)
		return
	}

	// Retrieve and validate PKCE state
	s.mutex.Lock()
	pkceData, exists := s.states[req.State]
	if exists {
		delete(s.states, req.State)
	}
	s.mutex.Unlock()

	if !exists {
		http.Error(w, "Invalid or expired state", http.StatusBadRequest)
		return
	}

	// Prepare token exchange request
	tokenURL := "https://oauth2.googleapis.com/token"
	data := url.Values{}
	data.Set("client_id", s.config.ClientID)
	data.Set("client_secret", s.config.ClientSecret)
	data.Set("code", req.Code)
	data.Set("redirect_uri", s.config.RedirectURI)
	data.Set("grant_type", "authorization_code")
	data.Set("code_verifier", pkceData.CodeVerifier)

	// Make request to Google
	resp, err := http.PostForm(tokenURL, data)
	if err != nil {
		log.Printf("Token exchange error: %v", err)
		http.Error(w, "Token exchange failed", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	// Forward the response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("Error decoding Google response: %v", err)
		http.Error(w, "Failed to parse token response", http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(result)
}

// POST /auth/refresh - Refresh access token
func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	s.enableCORS(w)

	if r.Method == "OPTIONS" {
		s.handleOptions(w, r)
		return
	}

	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if req.RefreshToken == "" {
		http.Error(w, "Missing refresh_token parameter", http.StatusBadRequest)
		return
	}

	// Prepare refresh request
	tokenURL := "https://oauth2.googleapis.com/token"
	data := url.Values{}
	data.Set("client_id", s.config.ClientID)
	data.Set("client_secret", s.config.ClientSecret)
	data.Set("refresh_token", req.RefreshToken)
	data.Set("grant_type", "refresh_token")

	// Make request to Google
	resp, err := http.PostForm(tokenURL, data)
	if err != nil {
		log.Printf("Token refresh error: %v", err)
		http.Error(w, "Token refresh failed", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	// Forward the response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("Error decoding Google response: %v", err)
		http.Error(w, "Failed to parse refresh response", http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(result)
}

// GET /auth/callback - OAuth callback handler
func (s *Server) handleCallback(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract authorization code and state from query parameters
	code := r.URL.Query().Get("code")
	state := r.URL.Query().Get("state")
	errorParam := r.URL.Query().Get("error")

	if errorParam != "" {
		// OAuth error occurred
		html := `<html><body><h1>Authentication Error</h1><p>` + errorParam + `</p><p>You can close this window.</p></body></html>`
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(html))
		return
	}

	if code == "" || state == "" {
		html := `<html><body><h1>Authentication Error</h1><p>Missing authorization code or state.</p><p>You can close this window.</p></body></html>`
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(html))
		return
	}

	// Exchange code for tokens immediately
	go func() {
		// Get PKCE state
		s.mutex.Lock()
		pkceData, exists := s.states[state]
		if exists {
			delete(s.states, state)
		}
		s.mutex.Unlock()

		if !exists {
			log.Printf("Invalid state in callback: %s", state)
			return
		}

		// Exchange code for tokens
		tokenURL := "https://oauth2.googleapis.com/token"
		data := url.Values{}
		data.Set("client_id", s.config.ClientID)
		data.Set("client_secret", s.config.ClientSecret)
		data.Set("code", code)
		data.Set("redirect_uri", s.config.RedirectURI)
		data.Set("grant_type", "authorization_code")
		data.Set("code_verifier", pkceData.CodeVerifier)

		resp, err := http.PostForm(tokenURL, data)
		if err != nil {
			log.Printf("Token exchange error in callback: %v", err)
			return
		}
		defer resp.Body.Close()

		var tokens map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&tokens); err != nil {
			log.Printf("Error decoding token response in callback: %v", err)
			return
		}

		// Store completed auth
		s.mutex.Lock()
		s.completedAuth[state] = CompletedAuth{
			Tokens:    tokens,
			Timestamp: time.Now().Unix(),
		}
		s.mutex.Unlock()

		log.Printf("Successfully completed OAuth for state: %s", state)
	}()

	// Return success page with instructions
	html := `<html><body>
		<h1>Authentication Successful!</h1>
		<p>Authorization completed! Please return to your terminal/editor.</p>
		<p>You can safely close this window.</p>
		<script>
			// Try to close the window (works if opened by script)
			setTimeout(function() { window.close(); }, 2000);
		</script>
	</body></html>`

	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(html))
}

// GET /auth/poll/{state} - Poll for completion of OAuth flow
func (s *Server) handlePoll(w http.ResponseWriter, r *http.Request) {
	s.enableCORS(w)

	if r.Method == "OPTIONS" {
		s.handleOptions(w, r)
		return
	}

	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract state from URL path
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 4 {
		http.Error(w, "Missing state parameter", http.StatusBadRequest)
		return
	}
	state := pathParts[3]

	// Check if auth is completed
	s.mutex.RLock()
	authData, exists := s.completedAuth[state]
	s.mutex.RUnlock()

	if !exists {
		// Not completed yet
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"completed": false,
		})
		return
	}

	// Completed - return tokens and clean up
	s.mutex.Lock()
	delete(s.completedAuth, state)
	s.mutex.Unlock()

	w.Header().Set("Content-Type", "application/json")
	response := map[string]interface{}{
		"completed": true,
		"tokens":    authData.Tokens,
	}
	json.NewEncoder(w).Encode(response)
}

// GET /health - Health check
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := map[string]interface{}{
		"status":    "ok",
		"timestamp": time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	server := NewServer()

	// Set up routes
	http.HandleFunc("/auth/start", server.handleAuthStart)
	http.HandleFunc("/auth/token", server.handleToken)
	http.HandleFunc("/auth/refresh", server.handleRefresh)
	http.HandleFunc("/auth/callback", server.handleCallback)
	http.HandleFunc("/auth/poll/", server.handlePoll)
	http.HandleFunc("/health", server.handleHealth)

	// Clean up expired states every 5 minutes
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			server.cleanupExpiredStates()
		}
	}()

	port := getEnvOrDefault("PORT", "3000")
	log.Printf("Gtask auth proxy listening on port %s", port)
	log.Printf("Health check: http://localhost:%s/health", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
