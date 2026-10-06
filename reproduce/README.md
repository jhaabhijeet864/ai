# Security Analysis: TypeSafe AI Provider SSRF & Unsafe Redirects

## Target Overview
**PR:** #22004 · feat: support `TYPESAFE_AI_BASE_URL` for TypeSafe AI provider endpoint configuration
**Component:** `packages/typesafe-ai` & `packages/provider-utils`
**Objective:** Identify if the `baseURL` configuration and the underlying HTTP client allow for Server-Side Request Forgery (SSRF) by bypassing routing guardrails.

---

## 1. Technical Analysis

### Initialization Logic
The TypeSafe AI provider is initialized via the `createTypeSafeAi` factory function. The `baseURL` is resolved using a priority chain:
1. `options.baseURL` (Dynamic configuration object)
2. `process.env.TYPESAFE_AI_BASE_URL` (Environment variable)
3. `'https://api.typesafe.ai/v1'` (Hardcoded default)

### Request Construction & Redirects
The resolved `baseURL` is used in `doDecide` to construct the API endpoint. The requests are sent via `postJsonToApi` in `@ai-sdk/provider-utils`.

**Critical Flaw 1: Blind Trust of baseURL**
The `baseURL` is treated as a trusted string and interpolated directly into the request URL without any validation of the protocol (HTTP vs HTTPS) or the destination IP (Private vs Public).

**Critical Flaw 2: Unsafe Redirect Following**
The underlying `postToApi` utility uses `globalThis.fetch` without specifying a `redirect` strategy. Per the Fetch spec, this defaults to `follow`. This means that if the initial target redirects the request, the SDK will blindly follow it to any destination, including internal network addresses.

---

## 2. Exploit Hypotheses

### Scenario A: Direct SSRF (Cloud Metadata)
**Payload:** `baseURL: 'http://169.254.169.254'`
**Result:** The SDK attempts to contact the Cloud Metadata Service directly.

### Scenario B: Indirect SSRF (Redirect-Based)
**Payload:** `baseURL: 'http://attacker-controlled-domain.com'`
**Server Response:** `302 Found` -> `Location: http://localhost:8080/admin`
**Result:** The SDK follows the redirect to the internal admin interface, bypassing initial `baseURL` checks.

---

## 3. Final Verdict

**Severity:** High
**Verdict:** **VULNERABLE**

The implementation fails to apply standard SSRF protections. By blindly trusting the `baseURL` and relying on default redirect behavior, it introduces multiple SSRF vectors.

---

## 4. Proof of Concept (PoC)

The `@reproduce` folder contains two distinct PoCs to verify these flaws.

### PoC 1: Direct Routing (Internal Target)
Verifies that `baseURL` can be pointed directly at an internal service.
1. **Start Listener**: `node reproduce/diagnostic-listener.mjs`
2. **Run Exploit**: `npx tsx reproduce/verify-routing.ts`
3. **Result**: Listener captures a POST request to `/systemone`.

### PoC 2: Unsafe Redirect Following
Verifies that the SDK follows redirects to internal targets.
1. **Run Automated PoC**: `node reproduce/run-redirect-poc.mjs`
   - This script spawns a `diagnostic-listener` (port 8090) and a `redirect-server` (port 8091).
   - It executes `verify-redirect.ts` which targets the redirect server.
2. **Result**: The diagnostic listener captures a request redirected from the redirect server, proving the SSRF via redirect.

### Evidence
See `Terminal_1.png` and `Terminal_2.png` for execution logs.

---

## 5. Directory Guide for Triagers

The following files are provided for verification:

| File | Purpose |
| :--- | :--- |
| `bug-report.md` | **Primary Document**. Detailed vulnerability report for submission. |
| `README.md` | High-level analysis and PoC instructions. |
| `diagnostic-listener.mjs` | Simulates an internal target/service to capture SSRF requests. |
| `redirect-server.mjs` | Simulates a malicious/compromised server that issues redirects. |
| `verify-routing.ts` | PoC script for Direct SSRF. |
| `verify-redirect.ts` | PoC script for Redirect-based SSRF. |
| `run-redirect-poc.mjs` | Orchestrator script to run the Redirect PoC end-to-end. |
| `Terminal_*.png` | Screenshots of successful exploit execution. |
