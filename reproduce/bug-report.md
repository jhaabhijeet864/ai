# Vulnerability Report: Server-Side Request Forgery (SSRF) in TypeSafe AI Provider

## Summary
**Vulnerability Type:** Server-Side Request Forgery (SSRF) / Unsafe Redirect Following
**Affected Component:** `packages/typesafe-ai` and `packages/provider-utils`
**Severity:** High
**Status:** Confirmed / Verified via PoC

### Description
The TypeSafe AI provider implementation contains a critical security flaw where the `baseURL` configuration is blindly trusted, and the underlying HTTP client blindly follows 3xx redirects. 

This creates two primary attack vectors:
1. **Direct SSRF**: An attacker can set the `baseURL` to an internal IP (e.g., `http://169.254.169.254`) to target internal services.
2. **Redirect-Based SSRF**: Even if a trusted `baseURL` is used, the SDK will follow HTTP redirects to arbitrary internal addresses, bypassing initial routing guardrails.

---

## Technical Deep Dive

### 1. The Vulnerable Path

**Vector A: Unvalidated Initialization**
In `packages/typesafe-ai/src/typesafe-ai-provider.ts`, the `createTypeSafeAi` factory resolves the `baseURL` without validating the protocol or the destination IP:

```typescript
const baseURL =
  withoutTrailingSlash(
    loadOptionalSetting({
      settingValue: options.baseURL, // Attacker controlled input
      environmentVariableName: 'TYPESAFE_AI_BASE_URL',
    }),
  ) ?? 'https://api.typesafe.ai/v1';
```

**Vector B: Blind Redirect Following**
The `postJsonToApi` utility in `packages/provider-utils/src/post-to-api.ts` calls `fetch` without specifying a `redirect` strategy. According to the Fetch API specification, this defaults to `follow`.

```typescript
// packages/provider-utils/src/post-to-api.ts
const response = await fetch(url, {
  method: 'POST',
  // 'redirect' is omitted, defaults to 'follow'
  ...
});
```

This means that if the server at `baseURL` returns a `302 Found` pointing to an internal resource, the SDK will blindly issue a request to that internal resource.

### 2. Root Cause
The implementation lacks fundamental security guardrails:
1. **No Protocol Enforcement**: It does not verify that the URL starts with `https://`.
2. **No Hostname Validation**: It does not check if the hostname resolves to a private IP (RFC 1918).
3. **Unsafe HTTP Client Configuration**: It relies on the default `fetch` behavior which follows redirects automatically, whereas it should be using a manual redirect handler that validates each hop.

---

## Proof of Concept (PoC)

### PoC 1: Direct Routing (Localhost)
By setting `baseURL: 'http://localhost:8090'`, the SDK routes requests directly to an internal service. Verified via `reproduce/verify-routing.ts`.

### PoC 2: Unsafe Redirect Following
To demonstrate the redirect vulnerability:
1. **Redirect Server (`reproduce/redirect-server.mjs`)**: Listens on port `8091` and returns a `302 Found` redirecting to `http://localhost:8090/systemone`.
2. **Exploit Script (`reproduce/verify-redirect.ts`)**: Configures the provider with `baseURL: 'http://localhost:8091'`.

**Execution Results:**
The diagnostic listener on port `8090` captured the request despite the SDK initially targeting port `8091`.

```text
[REDIRECT] [Redirect Server] Received request for: /systemone
[REDIRECT] [Redirect Server] Redirecting to: http://localhost:8090/systemone

[LISTENER] ================== [Incoming Request] ==================
[LISTENER] Method:  GET
[LISTENER] URL:     /systemone
[LISTENER] Headers: { "host": "localhost:8090", ... }
========================================================================
```

---

## Impact Analysis

### High-Risk Scenarios
1. **Cloud Metadata Theft**: An attacker can target `http://169.254.169.254/latest/meta-data/` to steal AWS/GCP instance identity tokens.
2. **Internal Infrastructure Recon**: An attacker can use the SDK as a proxy to map the internal network of the application server.
3. **Bypassing WAFs/Guardrails**: If the initial request is made to a trusted domain that allows open redirects, the SDK can be used to attack internal services that are not exposed to the internet.

---

## Remediation Strategy

### Immediate Fixes
1. **Enforce HTTPS**: Reject any `baseURL` that does not use `https://`.
2. **Validate IPs**: Resolve the hostname and verify the IP address is not in a private range.
3. **Disable Automatic Redirects**: Change `postToApi` to use `redirect: 'manual'`.

### Recommended Implementation
The SDK already contains a hardened utility: `fetchWithValidatedRedirects` in `packages/provider-utils/src/fetch-with-validated-redirects.ts`. This utility should be used instead of raw `fetch` in `postToApi`.

**Correct Pattern:**
```typescript
// Use fetchWithValidatedRedirects to ensure every hop is checked
const response = await fetchWithValidatedRedirects({
  url,
  headers,
  // This ensures redirect targets are validated against private IP ranges
});
```
