[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$SkipSsh,
    [switch]$SkipMeta,
    [switch]$SkipWebhook,
    [switch]$SkipEvolution,
    [switch]$VerboseReport
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'troubleshoot.config.json'
}

function Resolve-PathSafe {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $PSScriptRoot $PathValue
}

function Is-Placeholder {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }
    return $Value -match '^(CHANGE_ME|REPLACE_ME|YOUR_|<)'
}

function Mask-Value {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '[missing]'
    }
    if (Is-Placeholder $Value) {
        return '[placeholder]'
    }
    if ($Value.Length -le 8) {
        return ('*' * $Value.Length)
    }
    return '{0}***{1}' -f $Value.Substring(0, 4), $Value.Substring($Value.Length - 4)
}

function New-CheckResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Details,
        [string]$Evidence = ''
    )

    return [PSCustomObject]@{
        name = $Name
        status = $Status
        details = $Details
        evidence = $Evidence
    }
}

function Get-N8nAuthHeaders {
    param($N8nConfig)

    $headers = @{}
    $apiKey = [string]$N8nConfig.apiKey
    $user = [string]$N8nConfig.basicAuthUser
    $pass = [string]$N8nConfig.basicAuthPassword

    if (-not (Is-Placeholder $apiKey)) {
        $headers['X-N8N-API-KEY'] = $apiKey
        return $headers
    }

    if (-not (Is-Placeholder $user) -and -not (Is-Placeholder $pass)) {
        $pair = "{0}:{1}" -f $user, $pass
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        $headers['Authorization'] = "Basic {0}" -f $encoded
        return $headers
    }

    return $null
}

function Get-N8nExecutionItems {
    param([object]$Payload)

    if ($null -eq $Payload) {
        return @()
    }

    if ($Payload -is [System.Array]) {
        return $Payload
    }

    if ($Payload.PSObject.Properties.Name -contains 'data') {
        if ($Payload.data -is [System.Array]) {
            return $Payload.data
        }
        if ($null -ne $Payload.data) {
            return @($Payload.data)
        }
    }

    if ($Payload.PSObject.Properties.Name -contains 'results' -and $Payload.results -is [System.Array]) {
        return $Payload.results
    }

    if ($Payload.PSObject.Properties.Name -contains 'executions' -and $Payload.executions -is [System.Array]) {
        return $Payload.executions
    }

    return @()
}

function Test-TcpPortQuick {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 3000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $connected = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $connected) {
            return $false
        }

        $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Invoke-HttpCheck {
    param(
        [string]$Url,
        [string]$Method = 'GET',
        [hashtable]$Headers = $null,
        [int]$TimeoutSeconds = 12
    )

    $result = [ordered]@{
        ok = $false
        statusCode = 0
        body = ''
        error = ''
    }

    try {
        $params = @{
            Uri = $Url
            Method = $Method
            TimeoutSec = $TimeoutSeconds
            UseBasicParsing = $true
        }
        if ($Headers) {
            $params.Headers = $Headers
        }

        $response = Invoke-WebRequest @params
        $result.ok = $true
        $result.statusCode = [int]$response.StatusCode
        $result.body = [string]$response.Content
    }
    catch {
        $result.error = $_.Exception.Message
        $webResponse = $_.Exception.Response
        if ($webResponse) {
            try {
                $result.statusCode = [int]$webResponse.StatusCode
            }
            catch {
                $result.statusCode = 0
            }

            try {
                $stream = $webResponse.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $result.body = $reader.ReadToEnd()
                    $reader.Close()
                }
            }
            catch {
                $null = $null
            }
        }
    }

    return [PSCustomObject]$result
}

function Invoke-SshCommand {
    param(
        [string]$User,
        [string]$HostName,
        [string]$KeyPath,
        [string]$Command
    )

    $sshPath = (Get-Command ssh -ErrorAction SilentlyContinue)
    if (-not $sshPath) {
        return [PSCustomObject]@{ ok = $false; output = 'ssh command not found in PATH'; exitCode = 9001 }
    }

    $args = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=8')
    if (-not [string]::IsNullOrWhiteSpace($KeyPath)) {
        $args += @('-i', $KeyPath)
    }

    $args += ("{0}@{1}" -f $User, $HostName)

    $escaped = $Command.Replace('"', '\"')
        $args += ("bash -lc `"{0}`"" -f $escaped)

    $output = & ssh @args 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        ok = ($exitCode -eq 0)
        output = $output.Trim()
        exitCode = $exitCode
    }
}

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$configRaw = Get-Content -Path $ConfigPath -Raw
$config = $configRaw | ConvertFrom-Json

$checks = New-Object System.Collections.Generic.List[object]
$probableFailures = New-Object System.Collections.Generic.List[string]

$hetzner = $config.accounts.hetzner
$n8n = $config.accounts.n8n
$meta = $config.accounts.meta
$google = $config.accounts.google
$evolution = $config.accounts.evolutionApi
$browserless = $config.accounts.browserless

$requestTimeout = [int]$config.checks.requestTimeoutSeconds
if ($requestTimeout -lt 3) {
    $requestTimeout = 12
}

$tailLines = [int]$config.checks.tailLogLines
if ($tailLines -lt 10) {
    $tailLines = 80
}

$executionSampleSize = [int]$config.checks.recentExecutionSampleSize
if ($executionSampleSize -lt 5) {
    $executionSampleSize = 25
}

$resolvedOutputFolder = Resolve-PathSafe $config.checks.outputFolder
if (-not $resolvedOutputFolder) {
    $resolvedOutputFolder = Join-Path $PSScriptRoot 'reports'
}
if (-not (Test-Path $resolvedOutputFolder)) {
    New-Item -Path $resolvedOutputFolder -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$requiredInputs = @(
    @{ Name = 'Hetzner serverIp'; Value = [string]$hetzner.serverIp },
    @{ Name = 'Hetzner sshUser'; Value = [string]$hetzner.sshUser },
    @{ Name = 'n8n baseUrl'; Value = [string]$n8n.baseUrl },
    @{ Name = 'n8n webhookPath'; Value = [string]$n8n.webhookPath },
    @{ Name = 'Meta graphApiVersion'; Value = [string]$meta.graphApiVersion },
    @{ Name = 'Meta phoneNumberId'; Value = [string]$meta.phoneNumberId },
    @{ Name = 'Meta verifyToken'; Value = [string]$meta.verifyToken },
    @{ Name = 'Meta systemUserToken'; Value = [string]$meta.systemUserToken },
    @{ Name = 'Google projectId'; Value = [string]$google.projectId },
    @{ Name = 'Google geminiApiKey'; Value = [string]$google.geminiApiKey }
)

$missingPlaceholders = @()
foreach ($item in $requiredInputs) {
    if (Is-Placeholder $item.Value) {
        $missingPlaceholders += $item.Name
    }
}

if ($missingPlaceholders.Count -gt 0) {
    $checks.Add((New-CheckResult -Name 'Config completeness' -Status 'WARN' -Details ('Placeholders detected: ' + ($missingPlaceholders -join ', ')) -Evidence 'Fill placeholders to enable all checks.'))
}
else {
    $checks.Add((New-CheckResult -Name 'Config completeness' -Status 'PASS' -Details 'No placeholders detected in required fields.'))
}

$baseUri = [Uri]$n8n.baseUrl
$n8nHost = $baseUri.Host

try {
    $dnsN8n = Resolve-DnsName -Name $n8nHost -Type A -ErrorAction Stop
    $ips = ($dnsN8n | Select-Object -ExpandProperty IPAddress)
    $checks.Add((New-CheckResult -Name 'DNS n8n host resolution' -Status 'PASS' -Details ($n8nHost + ' resolves') -Evidence ($ips -join ', ')))
}
catch {
    $checks.Add((New-CheckResult -Name 'DNS n8n host resolution' -Status 'FAIL' -Details ($n8nHost + ' does not resolve') -Evidence $_.Exception.Message))
    $probableFailures.Add('Domain or DNS issue: n8n host does not resolve.')
}

$ipToCheck = [string]$hetzner.serverIp
if ([string]::IsNullOrWhiteSpace($ipToCheck)) {
    $ipToCheck = $n8nHost
}

foreach ($port in @(22, 80, 443)) {
    $ok = Test-TcpPortQuick -HostName $ipToCheck -Port $port -TimeoutMs 3500
    if ($ok) {
        $checks.Add((New-CheckResult -Name ("TCP {0}:{1}" -f $ipToCheck, $port) -Status 'PASS' -Details 'Port reachable.'))
    }
    else {
        $checks.Add((New-CheckResult -Name ("TCP {0}:{1}" -f $ipToCheck, $port) -Status 'FAIL' -Details 'Port not reachable.'))
    }
}

$rootCheck = Invoke-HttpCheck -Url $n8n.baseUrl -TimeoutSeconds $requestTimeout
if ($rootCheck.ok -and $rootCheck.statusCode -ge 200 -and $rootCheck.statusCode -lt 500) {
    $checks.Add((New-CheckResult -Name 'n8n HTTPS endpoint' -Status 'PASS' -Details ('HTTP ' + $rootCheck.statusCode) -Evidence ($n8n.baseUrl)))
}

$n8nCredentialSignalPattern = '(credential|credentials|reconnect|re-auth|reauth|refresh\s*token|token[^\n\r]{0,30}expired|invalid_grant|unauthorized|authorization failed|access token session has expired|please reconnect)'

$n8nHeaders = Get-N8nAuthHeaders -N8nConfig $n8n
if ($null -eq $n8nHeaders) {
    $checks.Add((New-CheckResult -Name 'n8n executions inspection' -Status 'SKIP' -Details 'No n8n API key or non-placeholder basic auth configured; cannot inspect recent executions automatically.'))
}
else {
    $executionEndpoints = @(
        ("{0}/api/v1/executions?limit={1}" -f $n8n.baseUrl.TrimEnd('/'), $executionSampleSize),
        ("{0}/rest/executions?limit={1}" -f $n8n.baseUrl.TrimEnd('/'), $executionSampleSize)
    )

    $execPayload = $null
    $execSourceUrl = ''
    $execFailureEvidence = ''
    foreach ($endpoint in $executionEndpoints) {
        $execCheck = Invoke-HttpCheck -Url $endpoint -Headers $n8nHeaders -TimeoutSeconds $requestTimeout
        if ($execCheck.ok -and $execCheck.statusCode -eq 200) {
            try {
                $execPayload = ($execCheck.body | ConvertFrom-Json -ErrorAction Stop)
                $execSourceUrl = $endpoint
                break
            }
            catch {
                $execFailureEvidence = "Endpoint returned non-JSON body: {0}" -f $endpoint
            }
        }
        else {
            if ($execCheck.statusCode -eq 401 -or $execCheck.statusCode -eq 403) {
                $execFailureEvidence = "Unauthorized/forbidden when calling: {0}" -f $endpoint
            }
        }
    }

    if ($null -eq $execPayload) {
        $details = 'Could not inspect n8n executions via API endpoints.'
        if (-not [string]::IsNullOrWhiteSpace($execFailureEvidence)) {
            $checks.Add((New-CheckResult -Name 'n8n executions inspection' -Status 'WARN' -Details $details -Evidence $execFailureEvidence))
        }
        else {
            $checks.Add((New-CheckResult -Name 'n8n executions inspection' -Status 'WARN' -Details $details))
        }
        $probableFailures.Add('Cannot query n8n executions automatically; verify n8n API auth or inspect Executions UI manually.')
    }
    else {
        $executionItems = Get-N8nExecutionItems -Payload $execPayload
        if ($executionItems.Count -eq 0) {
            $checks.Add((New-CheckResult -Name 'n8n executions inspection' -Status 'WARN' -Details 'Executions API responded but no items were found in payload.' -Evidence $execSourceUrl))
        }
        else {
            $failedExecutions = @($executionItems | Where-Object {
                ($_.status -eq 'error') -or ($_.finished -eq $false -and $_.stoppedAt)
            })

            $credentialSignals = New-Object System.Collections.Generic.List[string]
            foreach ($exec in $failedExecutions) {
                $snapshot = ($exec | ConvertTo-Json -Depth 12)
                if ($snapshot -match $n8nCredentialSignalPattern) {
                    $id = [string]$exec.id
                    $startedAt = [string]$exec.startedAt
                    $credentialSignals.Add("executionId={0}, startedAt={1}" -f $id, $startedAt)
                }
            }

            if ($credentialSignals.Count -gt 0) {
                $checks.Add((New-CheckResult -Name 'n8n credential-refresh error detection' -Status 'FAIL' -Details ("Detected credential/auth signals in failed executions ({0} of {1} sampled)." -f $credentialSignals.Count, $executionItems.Count) -Evidence (($credentialSignals | Select-Object -First 5) -join '; ')))
                $probableFailures.Add('n8n execution history indicates credential refresh/reconnect is required.')
            }
            else {
                $checks.Add((New-CheckResult -Name 'n8n credential-refresh error detection' -Status 'PASS' -Details ("No credential-refresh signals found in {0} sampled executions." -f $executionItems.Count) -Evidence $execSourceUrl))
            }
        }
    }
}
else {
    $checks.Add((New-CheckResult -Name 'n8n HTTPS endpoint' -Status 'FAIL' -Details ('Unreachable or bad response: HTTP ' + $rootCheck.statusCode) -Evidence $rootCheck.error))
    $probableFailures.Add('n8n endpoint unavailable from public internet. Check VPS state, Nginx, SSL, and firewall.')
}

if (-not $SkipWebhook) {
    if (Is-Placeholder ([string]$meta.verifyToken)) {
        $checks.Add((New-CheckResult -Name 'Meta webhook verification path' -Status 'SKIP' -Details 'verifyToken placeholder not replaced.'))
    }
    else {
        $challenge = 'diagchallenge123'
        $verifyUrl = ('{0}/webhook/{1}?hub_mode=subscribe&hub_verify_token={2}&hub_challenge={3}' -f $n8n.baseUrl.TrimEnd('/'), $n8n.webhookPath, [System.Uri]::EscapeDataString($meta.verifyToken), $challenge)
        $verifyCheck = Invoke-HttpCheck -Url $verifyUrl -TimeoutSeconds $requestTimeout

        if ($verifyCheck.statusCode -eq 200 -and $verifyCheck.body -match $challenge) {
            $checks.Add((New-CheckResult -Name 'Meta webhook verification path' -Status 'PASS' -Details 'Webhook verify token accepted.'))
        }
        elseif ($verifyCheck.statusCode -eq 403) {
            $checks.Add((New-CheckResult -Name 'Meta webhook verification path' -Status 'FAIL' -Details 'Webhook returned 403. Verify token mismatch likely.'))
            $probableFailures.Add('Meta webhook verify token mismatch between n8n workflow and Meta app settings.')
        }
        else {
            $checks.Add((New-CheckResult -Name 'Meta webhook verification path' -Status 'FAIL' -Details ('Unexpected verify response HTTP ' + $verifyCheck.statusCode) -Evidence $verifyCheck.body))
            $probableFailures.Add('Webhook path misconfiguration or workflow inactive.')
        }
    }
}
else {
    $checks.Add((New-CheckResult -Name 'Meta webhook verification path' -Status 'SKIP' -Details 'Skipped by parameter.'))
}

if (-not $SkipMeta) {
    if (Is-Placeholder ([string]$meta.systemUserToken)) {
        $checks.Add((New-CheckResult -Name 'Meta Graph token validity' -Status 'SKIP' -Details 'systemUserToken placeholder not replaced.'))
    }
    else {
        $authHeader = @{ Authorization = ('Bearer ' + [string]$meta.systemUserToken) }
        $meUrl = ('{0}/{1}/me' -f $meta.graphBaseUrl.TrimEnd('/'), $meta.graphApiVersion)
        $meCheck = Invoke-HttpCheck -Url $meUrl -Headers $authHeader -TimeoutSeconds $requestTimeout

        if ($meCheck.ok -and $meCheck.statusCode -eq 200) {
            $checks.Add((New-CheckResult -Name 'Meta Graph token validity' -Status 'PASS' -Details 'Meta token accepted by Graph API.'))
        }
        else {
            $checks.Add((New-CheckResult -Name 'Meta Graph token validity' -Status 'FAIL' -Details ('Meta token rejected. HTTP ' + $meCheck.statusCode) -Evidence $meCheck.body))
            $probableFailures.Add('Meta System User token expired/revoked or missing required scopes.')
        }

        $phoneUrl = ('{0}/{1}/{2}?fields=id,display_phone_number,verified_name' -f $meta.graphBaseUrl.TrimEnd('/'), $meta.graphApiVersion, $meta.phoneNumberId)
        $phoneCheck = Invoke-HttpCheck -Url $phoneUrl -Headers $authHeader -TimeoutSeconds $requestTimeout
        if ($phoneCheck.ok -and $phoneCheck.statusCode -eq 200) {
            $checks.Add((New-CheckResult -Name 'Meta phone number object access' -Status 'PASS' -Details 'Phone number object query succeeded.'))
        }
        else {
            $checks.Add((New-CheckResult -Name 'Meta phone number object access' -Status 'FAIL' -Details ('Cannot read phone number object. HTTP ' + $phoneCheck.statusCode) -Evidence $phoneCheck.body))
            $probableFailures.Add('Meta phone_number_id not accessible with current token/account.')
        }
    }
}
else {
    $checks.Add((New-CheckResult -Name 'Meta Graph token validity' -Status 'SKIP' -Details 'Skipped by parameter.'))
}

if ($evolution.enabled -and -not $SkipEvolution) {
    try {
        $evoUri = [Uri]$evolution.baseUrl
        $dnsEvo = Resolve-DnsName -Name $evoUri.Host -Type A -ErrorAction Stop
        $checks.Add((New-CheckResult -Name 'DNS Evolution host resolution' -Status 'PASS' -Details ($evoUri.Host + ' resolves') -Evidence (($dnsEvo | Select-Object -ExpandProperty IPAddress) -join ', ')))
    }
    catch {
        $checks.Add((New-CheckResult -Name 'DNS Evolution host resolution' -Status 'FAIL' -Details 'Evolution host does not resolve' -Evidence $_.Exception.Message))
        $probableFailures.Add('Evolution API domain/DNS issue.')
    }

    $managerUrl = $evolution.baseUrl.TrimEnd('/') + $evolution.managerPath
    $evoCheck = Invoke-HttpCheck -Url $managerUrl -TimeoutSeconds $requestTimeout
    if ($evoCheck.ok) {
        $checks.Add((New-CheckResult -Name 'Evolution Manager endpoint' -Status 'PASS' -Details ('HTTP ' + $evoCheck.statusCode) -Evidence $managerUrl))
    }
    else {
        $checks.Add((New-CheckResult -Name 'Evolution Manager endpoint' -Status 'FAIL' -Details ('HTTP ' + $evoCheck.statusCode) -Evidence $evoCheck.error))
        $probableFailures.Add('Evolution API manager endpoint unavailable.')
    }
}
else {
    $checks.Add((New-CheckResult -Name 'Evolution API checks' -Status 'SKIP' -Details 'Disabled in config or skipped by parameter.'))
}

$sshChecksEnabled = [bool]$config.checks.enableRemoteSshChecks
if ($SkipSsh) {
    $sshChecksEnabled = $false
}

if ($sshChecksEnabled) {
    $sshKey = [string]$hetzner.sshPrivateKeyPath
    if (-not [string]::IsNullOrWhiteSpace($sshKey) -and -not (Test-Path $sshKey)) {
        $checks.Add((New-CheckResult -Name 'SSH key path' -Status 'WARN' -Details 'Configured SSH key path does not exist.' -Evidence $sshKey))
    }

    $remoteEcho = Invoke-SshCommand -User ([string]$hetzner.sshUser) -HostName ([string]$hetzner.serverIp) -KeyPath $sshKey -Command 'echo connected; hostname; date -Iseconds'
    if ($remoteEcho.ok) {
        $checks.Add((New-CheckResult -Name 'SSH connectivity to VPS' -Status 'PASS' -Details 'SSH command executed on VPS.' -Evidence $remoteEcho.output))

        $composeFile = [string]$hetzner.composeFile
        if ([string]::IsNullOrWhiteSpace($composeFile)) {
            $composeFile = '~/.n8n/docker-compose.yml'
        }

        $psResult = Invoke-SshCommand -User ([string]$hetzner.sshUser) -HostName ([string]$hetzner.serverIp) -KeyPath $sshKey -Command ("docker compose -f {0} ps" -f $composeFile)
        if ($psResult.ok) {
            $checks.Add((New-CheckResult -Name 'Docker compose service status' -Status 'PASS' -Details 'docker compose ps executed.' -Evidence $psResult.output))

            if ($psResult.output -notmatch 'n8n') {
                $probableFailures.Add('n8n container not found in docker compose output.')
            }
            if ($psResult.output -match 'n8n' -and $psResult.output -notmatch 'n8n\s+.*Up') {
                $probableFailures.Add('n8n container is not Up.')
            }
            if ($psResult.output -match 'evolution-api' -and $psResult.output -notmatch 'evolution-api\s+.*Up') {
                $probableFailures.Add('evolution-api container is not Up (if your live flow depends on it).')
            }
        }
        else {
            $checks.Add((New-CheckResult -Name 'Docker compose service status' -Status 'FAIL' -Details 'Could not execute docker compose ps on VPS.' -Evidence $psResult.output))
            $probableFailures.Add('Docker services may be stopped or compose path/user permissions are wrong.')
        }

        $nginxResult = Invoke-SshCommand -User ([string]$hetzner.sshUser) -HostName ([string]$hetzner.serverIp) -KeyPath $sshKey -Command 'systemctl is-active nginx'
        if ($nginxResult.ok -and $nginxResult.output -match 'active') {
            $checks.Add((New-CheckResult -Name 'Nginx service state' -Status 'PASS' -Details 'Nginx is active.'))
        }
        else {
            $checks.Add((New-CheckResult -Name 'Nginx service state' -Status 'FAIL' -Details 'Nginx is not active.' -Evidence $nginxResult.output))
            $probableFailures.Add('Nginx is not active, so webhooks may never reach n8n.')
        }

        $ufwResult = Invoke-SshCommand -User ([string]$hetzner.sshUser) -HostName ([string]$hetzner.serverIp) -KeyPath $sshKey -Command 'sudo -n ufw status'
        if ($ufwResult.ok) {
            $checks.Add((New-CheckResult -Name 'UFW firewall state' -Status 'PASS' -Details 'Firewall status command succeeded.' -Evidence $ufwResult.output))
        }
        else {
            $checks.Add((New-CheckResult -Name 'UFW firewall state' -Status 'WARN' -Details 'Could not read UFW status with current SSH user (may require passwordless sudo).' -Evidence $ufwResult.output))
        }

        $logCmd = "docker compose -f {0} logs --tail={1} n8n" -f $composeFile, $tailLines
        $n8nLogs = Invoke-SshCommand -User ([string]$hetzner.sshUser) -HostName ([string]$hetzner.serverIp) -KeyPath $sshKey -Command $logCmd
        if ($n8nLogs.ok) {
            $checks.Add((New-CheckResult -Name 'n8n logs tail' -Status 'PASS' -Details 'Collected recent n8n logs.' -Evidence $n8nLogs.output))
            if ($n8nLogs.output -match $n8nCredentialSignalPattern) {
                $checks.Add((New-CheckResult -Name 'n8n log credential/auth signal detection' -Status 'WARN' -Details 'Recent n8n logs include credential/auth-expiry patterns.' ))
                $probableFailures.Add('n8n logs indicate credential refresh/reconnect may be required.')
            }
            elseif ($n8nLogs.output -match 'ECONNREFUSED|401|403|Webhook') {
                $probableFailures.Add('n8n logs include auth/webhook-related errors. Check report evidence for exact lines.')
            }
        }
        else {
            $checks.Add((New-CheckResult -Name 'n8n logs tail' -Status 'WARN' -Details 'Failed to read n8n logs.' -Evidence $n8nLogs.output))
        }
    }
    else {
        $checks.Add((New-CheckResult -Name 'SSH connectivity to VPS' -Status 'FAIL' -Details 'Cannot run SSH command on VPS.' -Evidence $remoteEcho.output))
        $probableFailures.Add('VPS unreachable by SSH. If billing froze the server, this is the primary failure point.')
    }
}
else {
    $checks.Add((New-CheckResult -Name 'Remote SSH checks' -Status 'SKIP' -Details 'Skipped by config or parameter.'))
}

$port22Fail = ($checks | Where-Object { $_.name -like 'TCP *:22' -and $_.status -eq 'FAIL' }).Count -gt 0
$port443Fail = ($checks | Where-Object { $_.name -like 'TCP *:443' -and $_.status -eq 'FAIL' }).Count -gt 0
$n8nEndpointFail = ($checks | Where-Object { $_.name -eq 'n8n HTTPS endpoint' -and $_.status -eq 'FAIL' }).Count -gt 0
$sshFail = ($checks | Where-Object { $_.name -eq 'SSH connectivity to VPS' -and $_.status -eq 'FAIL' }).Count -gt 0
$metaTokenFail = ($checks | Where-Object { $_.name -eq 'Meta Graph token validity' -and $_.status -eq 'FAIL' }).Count -gt 0

if ($sshFail -or ($port22Fail -and $port443Fail -and $n8nEndpointFail)) {
    $probableFailures.Add('Infrastructure outage likely: server suspended/offline, network inaccessible, or account freeze impact.')
}
if ($metaTokenFail) {
    $probableFailures.Add('Meta token problem likely: regenerate System User token and update n8n credential.')
}
if ($probableFailures.Count -eq 0) {
    $probableFailures.Add('No single hard failure detected. Next focus: n8n workflow active state and execution history around the message timestamp.')
}

$accountSnapshot = [ordered]@{
    hetzner = [ordered]@{
        provider = [string]$hetzner.provider
        projectName = [string]$hetzner.projectName
        serverName = [string]$hetzner.serverName
        serverIp = [string]$hetzner.serverIp
        sshUser = [string]$hetzner.sshUser
        sshPrivateKeyPath = [string]$hetzner.sshPrivateKeyPath
        composeFile = [string]$hetzner.composeFile
    }
    n8n = [ordered]@{
        baseUrl = [string]$n8n.baseUrl
        webhookPath = [string]$n8n.webhookPath
        basicAuthUser = Mask-Value ([string]$n8n.basicAuthUser)
        basicAuthPassword = Mask-Value ([string]$n8n.basicAuthPassword)
    }
    meta = [ordered]@{
        graphBaseUrl = [string]$meta.graphBaseUrl
        graphApiVersion = [string]$meta.graphApiVersion
        businessAccountId = [string]$meta.businessAccountId
        phoneNumberId = [string]$meta.phoneNumberId
        ownerWhatsAppE164 = [string]$meta.ownerWhatsAppE164
        verifyToken = Mask-Value ([string]$meta.verifyToken)
        systemUserToken = Mask-Value ([string]$meta.systemUserToken)
    }
    google = [ordered]@{
        projectId = [string]$google.projectId
        clientId = [string]$google.clientId
        oauthRedirectUri = [string]$google.oauthRedirectUri
        geminiApiKey = Mask-Value ([string]$google.geminiApiKey)
    }
    evolutionApi = [ordered]@{
        enabled = [bool]$evolution.enabled
        baseUrl = [string]$evolution.baseUrl
        managerPath = [string]$evolution.managerPath
        apiKey = Mask-Value ([string]$evolution.apiKey)
    }
    browserless = [ordered]@{
        cdpUrl = Mask-Value ([string]$browserless.cdpUrl)
    }
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    machine = $env:COMPUTERNAME
    project = $config.project
    accountSnapshot = $accountSnapshot
    checks = $checks
    probableFailurePoints = @($probableFailures | Select-Object -Unique)
}

$jsonPath = Join-Path $resolvedOutputFolder ("diagnostic_report_{0}.json" -f $timestamp)
$txtPath = Join-Path $resolvedOutputFolder ("diagnostic_report_{0}.txt" -f $timestamp)

$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add(("Generated: {0}" -f $report.generatedAt))
$summaryLines.Add(("Machine: {0}" -f $report.machine))
$summaryLines.Add('')
$summaryLines.Add('Checks:')
foreach ($item in $checks) {
    $summaryLines.Add(("[{0}] {1} - {2}" -f $item.status, $item.name, $item.details))
    if ($VerboseReport -and -not [string]::IsNullOrWhiteSpace($item.evidence)) {
        $summaryLines.Add(("    Evidence: {0}" -f $item.evidence.Replace("`r", ' ').Replace("`n", ' ')))
    }
}
$summaryLines.Add('')
$summaryLines.Add('Probable failure points:')
foreach ($reason in ($probableFailures | Select-Object -Unique)) {
    $summaryLines.Add(("- {0}" -f $reason))
}

$summaryLines | Set-Content -Path $txtPath -Encoding UTF8

Write-Host ''
Write-Host '=== WhatsApp Agent Diagnostic Summary ===' -ForegroundColor Cyan
$checks | Select-Object status, name, details | Format-Table -AutoSize
Write-Host ''
Write-Host 'Probable failure points:' -ForegroundColor Yellow
($probableFailures | Select-Object -Unique) | ForEach-Object { Write-Host (" - {0}" -f $_) }
Write-Host ''
Write-Host ("Report files:" ) -ForegroundColor Green
Write-Host (" - {0}" -f $jsonPath)
Write-Host (" - {0}" -f $txtPath)
