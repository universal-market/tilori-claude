"""A local stand-in for Tilori's MCP endpoint, for tests/needs-auth-probe.sh.

It answers every MCP POST with 401 and an OAuth challenge, serves OAuth
metadata and accepts client registration, like Tilori. That is what makes
Claude Code fall back to OAuth and write mcp-needs-auth-cache.json when its
headersHelper supplies no Authorization header. Listens on 127.0.0.1 only;
argv: port, request log path.
"""
import http.server, sys, json
P = sys.argv[1]; LOG = sys.argv[2]; B = 'http://127.0.0.1:%s' % P
class H(http.server.BaseHTTPRequestHandler):
    def _log(self):
        with open(LOG, 'a') as f:
            f.write(json.dumps({'m': self.command, 'p': self.path, 'auth': self.headers.get('Authorization', '')}) + '\n')
    def _json(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        self._log(); n = int(self.headers.get('Content-Length') or 0); self.rfile.read(n)
        if self.path == '/register':
            return self._json(201, {'client_id': 'fake-client', 'redirect_uris': ['http://localhost/callback'], 'token_endpoint_auth_method': 'none'})
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Bearer resource_metadata="%s/.well-known/oauth-protected-resource"' % B)
        self.send_header('Content-Length', '0'); self.end_headers()
    def do_GET(self):
        self._log()
        if self.path.startswith('/.well-known/oauth-protected-resource'):
            return self._json(200, {'resource': B + '/mcp/tilori/v1', 'authorization_servers': [B]})
        if self.path.startswith('/.well-known/oauth-authorization-server') or self.path.startswith('/.well-known/openid-configuration'):
            return self._json(200, {'issuer': B, 'authorization_endpoint': B + '/authorize', 'token_endpoint': B + '/token',
                                   'registration_endpoint': B + '/register', 'response_types_supported': ['code'],
                                   'code_challenge_methods_supported': ['S256'], 'grant_types_supported': ['authorization_code', 'refresh_token']})
        self.send_response(404); self.send_header('Content-Length', '0'); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(P)), H).serve_forever()
