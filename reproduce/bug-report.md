# Vulnerability Report: Blind Redirect Following Leading to Server-Side Request Forgery (SSRF)

## Summary
A Server-Side Request Forgery (SSRF) vulnerability exists within the core network transport layers of the SDK (`packages/provider-utils`). The underlying HTTP client utility (`postJsonToApi`) invokes the runtime `fetch` implementation without explicitly defining a `redirect` strategy. 

According to the Fetch API specification, this defaults to `follow`. Consequently, if a configured API endpoint or downstream host responds with an HTTP 3xx redirect status code pointing to an internal loopback network sequence or private IP infrastructure (e.g., RFC 1918 or Cloud Metadata space `169.254.169.254`), the server execution runtime will blindly follow the redirect and dispatch an unvalidated request to that internal target.

---

## Technical Deep Dive & Root Cause

### 1. The Vulnerable Mechanism
The core issue lies in `packages/provider-utils/src/post-to-api.ts`. The transport configuration object leaves the `redirect` handling behavior entirely to default engine assumptions:

```typescript
// packages/provider-utils/src/post-to-api.ts
const response = await fetch(url, {
  method: 'POST',
  headers,
  body: JSON.stringify(payload)
  // The 'redirect' option is missing, defaulting to 'follow'
});
```

### 2. The Attacker Vector (Trusted Domain Pivoting)
Even when an enterprise application configures a completely trusted, valid external API endpoint (e.g., `https://api.typesafe.ai/v1`), this default behavior exposes the internal network. If the external API gateway is compromised, misconfigured, or contains an open redirect vulnerability, an attacker can return a `302 Found` or `307 Temporary Redirect` response. 

Because the SDK does not evaluate subsequent connection hops, the client runtime follows the `Location` header back into the internal server architecture. Note that while the initial request uses `POST`, standard `302` handling rules mutate the subsequent redirect request to a `GET` operation, dropping the request body payload while completing the network handshake.

---

## Proof of Concept (PoC)

### 1. Environment Topology
To isolate the redirect logic, configure two local services within a staging workbench:
*   **Redirect Orchestrator:** Listens on port `8091` and acts as a mock API endpoint.
*   **Internal Resource Listener:** Listens on port `8090` to represent a restricted internal administration microservice.

### 2. Reproduction Script (`verify-redirect.ts`)
```typescript
import { createTypeSafeAi } from './packages/typesafe-ai/src/typesafe-ai-provider';

async function runVerificationSuite() {
  // Configured to point to the mock API server acting as the redirect agent
  const provider = createTypeSafeAi({
    baseURL: 'http://localhost:8091',
    apiKey: 'diagnostic-token',
  });

  const model = provider.decisionModel('jev-latest');

  try {
    await model.doDecide({
      questions: { q1: { type: 'boolean', criteria: {} } },
      state: {},
    });
  } catch (error) {
    // Structural parsing errors are expected due to the empty mock response payload frame
    console.log('[Info] Transport phase execution terminated.');
  }
}

runVerificationSuite();
```

### 3. Captured Logs
When the script is executed, the redirect orchestrator responds with a `302` status code pointing to `http://localhost:8090/systemone`. The restricted listener captures the forwarded handshake:

```text
[MOCK API GATEWAY] Received request. Responding with 302 to http://localhost:8090/systemone
[RESTRICTED INTERNAL LISTENER] Intercepted incoming network request!
[RESTRICTED INTERNAL LISTENER] Method: GET
[RESTRICTED INTERNAL LISTENER] Host: localhost:8090
[RESTRICTED INTERNAL LISTENER] Path: /systemone
```

---

## Impact Analysis
*   **Internal Infrastructure Exploration:** Attackers can leverage open redirects on whitelisted target domains to map out internal microservices or firewalled local hosts behind the application framework.
*   **Cloud Environment Declassification:** The application runtime can be forced to target host cloud instance portals (`http://169.254.169.254/latest/meta-data/`) to read sensitive metadata structures.
*   **Bypassing Network Access Controls:** Since the connection originates locally from the application server, it bypasses external perimeter firewall protections.

---

## Remediation Strategy
The SDK already provides a secure network utility tailored for this behavior: `fetchWithValidatedRedirects` within `packages/provider-utils/src/fetch-with-validated-redirects.ts`. This utility explicitly restricts private network exposure during redirect transitions.

Update `postJsonToApi` to use this existing secure wrapper rather than the unconfigured native `fetch` instance:

```typescript
// Enforce strict loopback validation metrics across all connection redirects
const response = await fetchWithValidatedRedirects({
  url,
  headers,
  method: 'POST',
  body: JSON.stringify(payload)
});
```
