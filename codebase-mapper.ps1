<#
.SYNOPSIS
    AI SDK Codebase Functional Architecture Parser
.DESCRIPTION
    Automatically discovers and classifies source files within E:\Open Source\ai\packages\
    into the functional architecture domains defined in the Codebase Mapping report.
    
    Domains:
      1. Model Provider Adapters   (packages/<provider>/src)
      2. Core Protocol Handlers    (packages/ai/src, packages/provider-utils/src, packages/rsc/src)
    
    Sub-categories within each domain use filename-pattern and content-grep heuristics
    to isolate Request Serialization, Header/Identity, Stream Parsing, Tool Execution,
    and Client-Side Server Actions.

    Output: Structured JSON report + coloured console summary.
.NOTES
    Targets: E:\Open Source\ai
    Runtime: PowerShell 5.1+ / PowerShell 7+
#>

[CmdletBinding()]
param(
    [string]$RootPath = "E:\Open Source\ai",
    [string]$OutputJson = "E:\Open Source\ai\functional-architecture-report.json",
    [switch]$Quiet
)

# --- Helpers ------------------------------------------------------------------

function Write-Banner([string]$Text) {
    if (-not $Quiet) {
        $bar = "-" * 72
        Write-Host "`n$bar" -ForegroundColor DarkCyan
        Write-Host "  $Text" -ForegroundColor Cyan
        Write-Host "$bar" -ForegroundColor DarkCyan
    }
}

function Write-Category([string]$Label, [int]$Count) {
    if (-not $Quiet) {
        $colour = if ($Count -gt 0) { "Green" } else { "DarkGray" }
        Write-Host ("    [{0,3}]  {1}" -f $Count, $Label) -ForegroundColor $colour
    }
}

function Resolve-Relative([string]$Full) {
    $Full.Replace($RootPath, "").TrimStart("\").Replace("\", "/")
}

function Find-SourceFiles([string]$Dir, [string[]]$Patterns, [string[]]$Exclude = @()) {
    <#
        Returns .ts/.tsx source files (excluding tests, fixtures, snapshots, node_modules, dist)
        whose basename matches ANY of the glob patterns supplied.
    #>
    if (-not (Test-Path $Dir)) { return @() }

    $allFiles = Get-ChildItem -Path $Dir -Recurse -File -Include "*.ts","*.tsx" -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Replace("\", "/")
            $rel -notmatch "node_modules|dist|__fixtures__|__snapshots__" -and
            $_.Name -notmatch "\.test(\-d)?\.tsx?$" -and
            $_.Name -notmatch "\.config\." -and
            $_.Name -ne "vitest.config.ts"
        }

    $matched = @()
    foreach ($f in $allFiles) {
        $base = $f.Name
        foreach ($pat in $Patterns) {
            if ($base -like $pat) {
                $skip = $false
                foreach ($ex in $Exclude) {
                    if ($base -like $ex) { $skip = $true; break }
                }
                if (-not $skip) { $matched += $f; break }
            }
        }
    }
    return $matched
}

function Find-ByContent([string]$Dir, [string[]]$ContentPatterns, [string[]]$FileGlobs = @("*.ts","*.tsx")) {
    <#
        Searches file content for any of the supplied regex patterns.
        Returns files containing at least one match.
    #>
    if (-not (Test-Path $Dir)) { return @() }

    $allFiles = Get-ChildItem -Path $Dir -Recurse -File -Include $FileGlobs -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Replace("\", "/")
            $rel -notmatch "node_modules|dist|__fixtures__|__snapshots__" -and
            $_.Name -notmatch "\.test(\-d)?\.tsx?$"
        }

    $matched = @()
    foreach ($f in $allFiles) {
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        foreach ($pat in $ContentPatterns) {
            if ($content -match $pat) {
                $matched += $f
                break
            }
        }
    }
    return $matched
}

# --- Provider Package Discovery -----------------------------------------------

$packagesRoot = Join-Path $RootPath "packages"

# Identify all provider packages (excludes framework integrations, tooling, and core)
$nonProviderPackages = @(
    "ai", "provider", "provider-utils", "react", "vue", "svelte", "angular",
    "rsc", "codemod", "code-mode", "devtools", "gateway", "harness", "harness-*",
    "langchain", "llamaindex", "mcp", "otel", "policy-opa", "sandbox-*",
    "test-server", "tui", "typesafe-ai", "valibot", "workflow", "workflow-harness",
    "zai"
)

$providerDirs = Get-ChildItem -Path $packagesRoot -Directory | Where-Object {
    $name = $_.Name
    $isExcluded = $false
    foreach ($ex in $nonProviderPackages) {
        if ($name -like $ex) { $isExcluded = $true; break }
    }
    -not $isExcluded -and (Test-Path (Join-Path $_.FullName "src"))
}

# ==============================================================================
#  DOMAIN 1: MODEL PROVIDER ADAPTERS
# ==============================================================================

Write-Banner "DOMAIN 1: Model Provider Adapters"

# --- 1A. Request Serialization Pipelines --------------------------------------
# Factory functions building outgoing API payloads, prompt converters,
# config mappers, tools preparation, schema normalization, request body builders.

$serializationPatterns = @(
    "convert-to-*-prompt*",   # Prompt -> API payload converters
    "convert-to-*-messages*", # Message format converters
    "*-prepare-tools*",       # Tool schema preparation
    "*-api.ts",               # Core API payload builders
    "*-prompt.ts",            # Prompt construction
    "*-tools.ts",             # Tool definition serialization
    "normalize-*-json-schema*", # JSON schema normalization
    "sanitize-*-json-schema*",  # Schema sanitization
    "*-language-model.ts",    # Language model implementation (doGenerate/doStream)
    "*-embedding-model.ts",   # Embedding model payload construction
    "*-image-model.ts",       # Image model payload construction
    "*-speech-model.ts",      # Speech model payload construction
    "*-video-model.ts",       # Video model payload construction
    "*-batch.ts",             # Batch request construction
    "*-language-model-options*", # Model option schemas
    "*-language-model-capabilities*", # Capability flags
    "*-model-capabilities*",
    "*-forward-compatible*",
    "convert-*-usage*",       # Usage/token count mapping
    "map-*-stop-reason*",     # Stop reason translation
    "map-*-finish-reason*",   # Finish reason translation
    "get-cache-control*",     # Cache control directives
    "*-message-metadata*",    # Message metadata shaping
    "*-message-lifecycle*"    # Message lifecycle hooks
)

$serializationExcludes = @(
    "*-provider.ts",          # Handled separately as identity/factory
    "*-error.ts",             # Error types
    "*-config.ts"             # Config - belongs to identity domain
)

$serializationFiles = @()
foreach ($dir in $providerDirs) {
    $srcDir = Join-Path $dir.FullName "src"
    $serializationFiles += Find-SourceFiles -Dir $srcDir -Patterns $serializationPatterns -Exclude $serializationExcludes
}

Write-Category "Request Serialization Pipelines" $serializationFiles.Count

# --- 1B. Header & Identity Lifecycle Managers ---------------------------------
# Provider factories, config objects, API key loading, base URL resolution,
# header construction, error wrappers, and version identifiers.

$identityPatterns = @(
    "*-provider.ts",          # Provider factory (createOpenAI, createAnthropic, etc.)
    "*-config.ts",            # Provider config objects
    "*-error.ts",             # Provider-specific error types
    "version.ts",             # SDK version stamp injected into headers
    "index.ts",               # Re-export barrel (defines public surface)
    "*-stream-error*"         # Stream error handlers
)

$identityFiles = @()
foreach ($dir in $providerDirs) {
    $srcDir = Join-Path $dir.FullName "src"
    $identityFiles += Find-SourceFiles -Dir $srcDir -Patterns $identityPatterns
}

Write-Category "Header & Identity Lifecycle Managers" $identityFiles.Count


# ==============================================================================
#  DOMAIN 2: CORE PROTOCOL HANDLERS
# ==============================================================================

Write-Banner "DOMAIN 2: Core Protocol Handlers"

$coreSrc        = Join-Path $packagesRoot "ai\src"
$provUtilsSrc   = Join-Path $packagesRoot "provider-utils\src"
$rscSrc         = Join-Path $packagesRoot "rsc\src"
$provSpecSrc    = Join-Path $packagesRoot "provider\src"

# --- 2A. Stream Parsing & Ingestion Engines -----------------------------------
# Line-by-line protocol parsers, SSE decoders, chunk transformers,
# stream construction, text stream piping, UI message stream readers.

$streamPatterns = @(
    "stream-*",               # stream-text, stream-language-model-call, etc.
    "*-stream*.ts",           # create-ui-message-stream, to-text-stream, etc.
    "smooth-stream*",         # Token smoothing/buffering
    "parse-json-event-stream*", # SSE JSON event parsing
    "to-text-stream*",        # Raw text stream conversion
    "create-text-stream*",    # Text stream response builders
    "pipe-text-stream*",      # Pipe to HTTP response
    "create-sse-*",           # SSE keep-alive wrappers
    "read-ui-message-stream*",# UI message stream reader/decoder
    "to-ui-message-stream*",  # Core -> UI stream transformer
    "to-ui-message-chunk*",   # Chunk-level UI message mapping
    "ui-message-chunk*",      # Chunk type definitions
    "json-to-sse-*",          # JSON -> SSE framing
    "*-stream-writer*",       # Stream writer abstractions
    "create-ui-message-stream-response*",
    "pipe-ui-message-stream*",
    "handle-ui-message-stream*",
    "get-response-ui-message-id*",
    "ui-message-stream-*",    # Stream outcome, headers, callbacks
    "response-handler*",      # HTTP response body stream handler
    "streaming-tool-call-*",  # Streaming tool call argument accumulator
    "transcription-stream-*", # Transcription stream envelope
    "convert-async-iterator*",# AsyncIterator -> ReadableStream bridge
    "cancel-response-body*",  # Response cancellation
    "extract-lines*",         # Line-by-line extraction
    "post-to-api*",           # Core POST with stream response
    "post-multipart-stream*"  # Multipart stream POST
)

$streamExcludes = @(
    "stream-retry-*"          # Retry logic - belongs to resilience, not parsing
)

$streamFiles = @()
foreach ($searchDir in @($coreSrc, $provUtilsSrc)) {
    $streamFiles += Find-SourceFiles -Dir $searchDir -Patterns $streamPatterns -Exclude $streamExcludes
}

Write-Category "Stream Parsing & Ingestion Engines" $streamFiles.Count

# --- 2B. Tool Execution Core Loops --------------------------------------------
# Step-by-step orchestrators, tool call parsing, tool execution,
# tool approval flows, tool fingerprinting, and tool context validation.

$toolPatterns = @(
    "execute-tool-call*",
    "execute-tools-from-stream*",
    "parse-tool-call*",
    "tool-call*",
    "tool-result*",
    "tool-error*",
    "tool-output*",
    "tool-order*",
    "tool-approval-*",
    "tool-caller-*",
    "tool-execution-*",
    "tool-fingerprint*",
    "tool-input-*",
    "tool-output-*",
    "tools-context-*",
    "validate-tool-*",
    "invoke-tool-*",
    "collect-tool-*",
    "resolve-tool-*",
    "active-tools*",
    "filter-active-tools*",
    "is-tool-execution-*",
    "stop-condition*",
    "prepare-step*",
    "prepare-step-call-settings*",
    "step-result*",
    "generate-text.ts",        # Main orchestrator with multi-step loop
    "generate-text-result*",
    "generate-text-events*",
    "language-model-events*",
    "content-part*",
    "output.ts",               # Output type declarations for tool results
    "output-utils*",
    "reasoning*",
    "reasoning-output*",
    "default-generate-text-result*",
    "convert-language-model-content*",
    "prune-messages*",
    "response-message*",
    "to-response-messages*",
    "sum-token-counts*",
    "calculate-tokens-per-second*"
)

$toolFiles = @()
$toolFiles += Find-SourceFiles -Dir (Join-Path $coreSrc "generate-text") -Patterns $toolPatterns
# Also pull provider-utils tool utilities
$toolFiles += Find-SourceFiles -Dir $provUtilsSrc -Patterns @(
    "create-tool-name-mapping*",
    "provider-defined-tool-factory*",
    "provider-executed-tool-factory*"
)

Write-Category "Tool Execution Core Loops" $toolFiles.Count

# --- 2C. Client-Side Server Actions -------------------------------------------
# RSC (React Server Components) actions, streamable UI, AI state management,
# provider context, and shared client utilities.

$serverActionPatterns = @(
    "stream-ui*",             # streamUI server action
    "streamable-ui*",         # createStreamableUI
    "streamable-value*",      # createStreamableValue
    "ai-state*",              # AI state management
    "provider*",              # RSC provider context
    "rsc-server*",            # Server-side RSC entry
    "rsc-client*",            # Client-side RSC entry
    "rsc-shared*",            # Shared RSC utilities
    "types*"                  # RSC type definitions
)

$serverActionFiles = @()
$serverActionFiles += Find-SourceFiles -Dir $rscSrc -Patterns $serverActionPatterns
# Include shared-client subdirectory
$sharedClientDir = Join-Path $rscSrc "shared-client"
if (Test-Path $sharedClientDir) {
    $serverActionFiles += Get-ChildItem -Path $sharedClientDir -Recurse -File -Include "*.ts","*.tsx" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "\.test(\-d)?\.tsx?$" }
}
# Include RSC subdirectories (stream-ui, streamable-ui, streamable-value, util)
foreach ($subDir in @("stream-ui", "streamable-ui", "streamable-value", "util", "types")) {
    $fullSub = Join-Path $rscSrc $subDir
    if (Test-Path $fullSub) {
        $serverActionFiles += Get-ChildItem -Path $fullSub -Recurse -File -Include "*.ts","*.tsx" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "\.test(\-d)?\.tsx?$" }
    }
}
# Deduplicate
$serverActionFiles = $serverActionFiles | Sort-Object FullName -Unique

# Also scan provider-utils for serialization schema checks used at boundaries
$boundarySchemaFiles = Find-ByContent -Dir $provUtilsSrc -ContentPatterns @(
    "parseProviderOptions",
    "validate.*schema",
    "parseJSON|safeParseJSON"
) | Where-Object { $_.Name -notmatch "\.test" }

$serverActionFiles += $boundarySchemaFiles
$serverActionFiles = $serverActionFiles | Sort-Object FullName -Unique

Write-Category "Client-Side Server Actions" $serverActionFiles.Count

# --- Also capture Provider Specification interfaces ---------------------------
# These define the contracts (LanguageModelV4, etc.) that all domains implement.

$specPatterns = @("*.ts")
$specFiles = @()
if (Test-Path $provSpecSrc) {
    $specFiles = Get-ChildItem -Path $provSpecSrc -Recurse -File -Include "*.ts" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notmatch "\.test(\-d)?\.tsx?$" -and
            $_.FullName -notmatch "node_modules|dist"
        }
}

Write-Category "Provider Specification Interfaces (@ai-sdk/provider)" $specFiles.Count

# ==============================================================================
#  BUILD REPORT
# ==============================================================================

function To-Entry($f) {
    @{
        path     = Resolve-Relative $f.FullName
        filename = $f.Name
        sizeKB   = [math]::Round($f.Length / 1024, 1)
    }
}

$report = [ordered]@{
    generated     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    rootPath      = $RootPath
    providerCount = $providerDirs.Count
    providerNames = @($providerDirs | ForEach-Object { $_.Name } | Sort-Object)

    domain1_ModelProviderAdapters = [ordered]@{
        "1A_RequestSerializationPipelines" = [ordered]@{
            description = "Factory functions and converters building outgoing API payloads"
            fileCount   = $serializationFiles.Count
            files       = @($serializationFiles | ForEach-Object { To-Entry $_ })
        }
        "1B_HeaderIdentityLifecycleManagers" = [ordered]@{
            description = "Provider factories, config objects, API key loading, header construction"
            fileCount   = $identityFiles.Count
            files       = @($identityFiles | ForEach-Object { To-Entry $_ })
        }
    }

    domain2_CoreProtocolHandlers = [ordered]@{
        "2A_StreamParsingIngestionEngines" = [ordered]@{
            description = "Line-by-line protocol parsers, SSE decoders, chunk transformers, stream writers"
            fileCount   = $streamFiles.Count
            files       = @($streamFiles | ForEach-Object { To-Entry $_ })
        }
        "2B_ToolExecutionCoreLoops" = [ordered]@{
            description = "Step-by-step orchestrators, tool call parsing, execution, approval, and validation"
            fileCount   = $toolFiles.Count
            files       = @($toolFiles | ForEach-Object { To-Entry $_ })
        }
        "2C_ClientSideServerActions" = [ordered]@{
            description = "RSC actions, streamable UI, AI state management, boundary schema validation"
            fileCount   = $serverActionFiles.Count
            files       = @($serverActionFiles | ForEach-Object { To-Entry $_ })
        }
    }

    supplementary_ProviderSpecifications = [ordered]@{
        description = "Contract interfaces (LanguageModelV4, EmbeddingModelV1, etc.) from @ai-sdk/provider"
        fileCount   = $specFiles.Count
        files       = @($specFiles | ForEach-Object { To-Entry $_ })
    }
}

# --- Totals -------------------------------------------------------------------

$totalFiles = $serializationFiles.Count +
              $identityFiles.Count +
              $streamFiles.Count +
              $toolFiles.Count +
              $serverActionFiles.Count +
              $specFiles.Count

$report["totalClassifiedFiles"] = $totalFiles

if (-not $Quiet) {
    Write-Banner "SUMMARY"
    Write-Host "  Providers discovered:      $($providerDirs.Count)" -ForegroundColor Yellow
    Write-Host "  Total classified files:    $totalFiles" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Domain 1 - Provider Adapters" -ForegroundColor Magenta
    Write-Category "  1A  Request Serialization"      $serializationFiles.Count
    Write-Category "  1B  Header & Identity"          $identityFiles.Count
    Write-Host ""
    Write-Host "  Domain 2 - Core Protocol" -ForegroundColor Magenta
    Write-Category "  2A  Stream Parsing"             $streamFiles.Count
    Write-Category "  2B  Tool Execution Loops"       $toolFiles.Count
    Write-Category "  2C  Client-Side Actions"        $serverActionFiles.Count
    Write-Host ""
    Write-Host "  Supplementary" -ForegroundColor Magenta
    Write-Category "  Provider Specs"                 $specFiles.Count
    Write-Host ""
}

# --- Write JSON ---------------------------------------------------------------

$report | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputJson -Encoding utf8
if (-not $Quiet) {
    Write-Host "  Report written to: $OutputJson" -ForegroundColor Green
    Write-Host ""
}

return $report
