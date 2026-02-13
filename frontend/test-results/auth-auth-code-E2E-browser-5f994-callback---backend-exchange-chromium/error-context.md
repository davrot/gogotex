# Page snapshot

```yaml
- generic [ref=e3]:
  - heading "gogotex — frontend (dev)" [level=1] [ref=e4]
  - paragraph [ref=e5]:
    - text: This is a minimal scaffold for Phase‑03 focusing on authentication (login + callback). Use the
    - code [ref=e6]: /auth/callback
    - text: route for the OAuth callback.
  - paragraph [ref=e7]:
    - link "Sign in with Keycloak" [ref=e8] [cursor=pointer]:
      - /url: http://keycloak-keycloak:8080/realms/undefined/protocol/openid-connect/auth?client_id=undefined&response_type=code&redirect_uri=http%3A%2F%2Ffrontend%2Fauth%2Fcallback
  - paragraph [ref=e9]:
    - link "Open callback page (dev)" [ref=e10] [cursor=pointer]:
      - /url: /auth/callback
```