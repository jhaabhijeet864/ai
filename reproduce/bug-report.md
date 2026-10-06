# Vulnerability Report: Blind Trusted-Origin Redirect Bypass (SSRF) in TypeSafe AI Provider

## Summary
**Vulnerability Type:** Server-Side Request Forgery (SSRF) via Unsafe Redirect Following
**Affected Component:** `packages/provider-utils` (Core Transport) and `packages/typesafe-ai`
**Severity:** High
**Status:** Confirmed / Verified via PoC

### Description
The AI SDK contains a critical systemic risk where the core HTTP transport utility (`postJsonToApi`) blindly follows HTTP 3xx redirects to arbitrary destinations, including internal network addresses. 

While the SDK allows for `baseURL` configuration, the primary security failure is that even when a developer configures a completely authentic, trusted base URL (e.g., `https://api.typesafe.ai`), a compromise or open redirect on that trusted gateway allows an attacker to manipulate the SDK into making downstream connections to sensitive internal resources, such as cloud metadata endpoints (`169.254.169.254`). This effectively turns a third-party API vulnerability into an internal network breach of the application server.

---

## Technical Deep Dive

### 1. The Vulnerable Path: Blind Redirect Following
The core of the issue resides in `packages/provider-utils/src/post-to-api.ts`. The `postToApi` function (used by `postJsonToApi`) issues requests using `globalThis.fetch` without specifying a `redirect` strategy.

```typescript
// packages/provider-utils/src/post-to-api.ts
const response = await fetch(url, {
  method: 'POST',
  // 'redirect' is omitted, defaults to 'follow' per Fetch spec
  ...
});
```

Per the Fetch API specification, the default behavior is `follow`. This means that if the target server returns a `302 Found` or `303 See Other`, the SDK will automatically issue a new request to the `Location` header provided by the server, without any validation of the destination hostname or IP address.

### 2. Root Cause: Implementation Oversight
The most significant finding is that the SDK maintainers have already recognized this risk and implemented a hardened solution elsewhere in the codebase. The utility `fetchWithValidatedRedirects` (in `packages/provider-utils/src/fetch-with-validated-redirects.ts`) was specifically designed to:
1. Set `redirect: 'manual'`.
2. Validate every hop using `validateDownloadUrl` to block private/internal IP ranges.
3. Sanitize headers on cross-origin redirects to prevent credential leakage.

The vulnerability exists because this security wrapper was **not applied** to the core `postJsonToApi` transport used by the TypeSafe AI provider, creating a clear implementation gap between the intended security architecture and the actual code.

---

## Proof of Concept (PoC)

### Setup
The vulnerability was verified using a "Trusted-Origin" simulation:
1. **Trusted Gateway (`reproduce/redirect-server.mjs`)**: A server (simulating a trusted API endpoint) that returns a `302 Found` redirecting to `http://localhost:8090/systemone`.
2. **Internal Target (`reproduce/diagnostic-listener.mjs`)**: A listener on port `8090` simulating a sensitive internal service.
3. **Client (`reproduce/verify-redirect.ts`)**: An SDK instance configured to target the "trusted" gateway.

### Execution Results
Despite the client targeting the trusted gateway, the request was successfully routed to the internal target.

```text
[REDIRECT] [Redirect Server] Received request for: /systemone
[REDIRECT] [Redirect Server] Redirecting to: http://localhost:8090/systemone

[LISTENER] ================== [Incoming Request] ==================
[LISTENER] Method:  GET
[LISTENER] URL:     /systemone
[LISTENER] Headers: { "host": "localhost:8090", ... }
========================================================================
```

**Note on Request Mutation**: As observed in the logs, the initial `POST` request mutates into a `GET` request upon following the `302` redirect, as mandated by the HTTP specification. While the request body is dropped, the connection handshake still occurs, allowing for internal port scanning and metadata exfiltration.

---

## Impact Analysis

### High-Risk Scenarios
1. **Cloud Metadata Exfiltration**: A redirect to `http://169.254.169.254/latest/meta-data/` allows an attacker to steal IAM credentials and instance identity tokens.
2. **Internal Infrastructure Recon**: The SDK can be used as a proxy to map the internal network (ports, services) of the application server.
3. **Multi-Tenant Risk**: In platforms where users can provide custom provider configurations, this flaw allows a user to target the platform's own internal infrastructure.

---

## Remediation Strategy

### Recommended Implementation
The fix is straightforward: replace the raw `fetch` call in `packages/provider-utils/src/post-to-api.ts` with the existing `fetchWithValidatedRedirects` utility.

**Corrected Pattern:**
```typescript
import { fetchWithValidatedRedirects } from './fetch-with-validated-redirects';

// Replace raw fetch with the validated wrapper
const response = await fetchWithValidatedRedirects({
  url,
  headers,
  abortSignal,
  // This ensures every redirect hop is validated against private IP ranges
});
```
By leveraging the existing security infrastructure, the SDK can maintain legitimate redirect functionality while blocking internal network exposure.
