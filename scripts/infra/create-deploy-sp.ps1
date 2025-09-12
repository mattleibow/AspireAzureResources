<#

Usage Examples:

    # Create new resource group and service principal:
    .\scripts\infra\create-deploy-sp.ps1 `
      -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" `
      -DisplayName "aspire-deploy-sp" `
      -ResourceGroupName "rg-aspire-dev" `
      -ResourceGroupLocation "East US" `
      -GithubRepo "mattleibow/AspireAzureResources"

    # Use existing resource group (no location needed):
    .\scripts\infra\create-deploy-sp.ps1 `
      -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" `
      -DisplayName "aspire-deploy-sp" `
      -ResourceGroupName "rg-aspire-existing" `
      -GithubRepo "mattleibow/AspireAzureResources"

#>

param(
    [Parameter(Mandatory=$true)] [string]$SubscriptionId,
    [Parameter(Mandatory=$true)] [string]$DisplayName,
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [Parameter(Mandatory=$false)] [string]$ResourceGroupLocation,
    [Parameter(Mandatory=$true)] [string]$GithubRepo,
    [ValidateSet("branch","environment","tags")] [string]$SubjectMode = "branch",
    [string]$SubjectValue = "main",
    [string]$Role = "Contributor"
)

$ErrorActionPreference = "Stop"

$Subject = switch ($SubjectMode) {
    "branch"       { "repo:$($GithubRepo):ref:refs/heads/$SubjectValue" }
    "environment"  { "repo:$($GithubRepo):environment:$SubjectValue" }
    "tags"         { "repo:$($GithubRepo):ref:refs/tags/$SubjectValue" }
}
$Issuer = "https://token.actions.githubusercontent.com"
$Audience = "api://AzureADTokenExchange"
$Scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

# Get current Azure CLI context
try {
    $currentAccount = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $currentAccount) {
        throw "Not logged in"
    }
} catch {
    Write-Host ""
    Write-Host "❌ ERROR: Not logged into Azure CLI" -ForegroundColor Red
    Write-Host "═══════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Fix: Login to Azure first" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Step 1: Login to Azure" -ForegroundColor Yellow
    Write-Host "      az login" -ForegroundColor White
    Write-Host ""
    Write-Host "   Step 2: If you have multiple tenants, specify the target tenant" -ForegroundColor Yellow
    Write-Host "      az login --tenant 'your-tenant-id-or-domain'" -ForegroundColor White
    Write-Host ""
    Write-Host "   Step 3: Set the target subscription (if you have multiple)" -ForegroundColor Yellow
    Write-Host "      az account set --subscription 'your-subscription-id'" -ForegroundColor White
    Write-Host ""
    Write-Host "   Step 4: Verify your context" -ForegroundColor Yellow
    Write-Host "      az account show" -ForegroundColor White
    Write-Host ""
    Write-Host "🔍 Then re-run this script!" -ForegroundColor Cyan
    exit 1
}

$TenantId = $currentAccount.tenantId
$currentSubId = $currentAccount.id
$currentSubName = $currentAccount.name

Write-Host ""
Write-Host "🚀 Azure Deployment Service Principal Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "📋 Configuration Summary:" -ForegroundColor Yellow
Write-Host "  • Service Principal: $DisplayName"
Write-Host "  • Resource Group: $ResourceGroupName"
Write-Host "  • Resource Group Location: $ResourceGroupLocation"
Write-Host "  • GitHub Repository: $GithubRepo"
Write-Host "  • Subject: $Subject"
Write-Host "  • Role: $Role"
Write-Host ""


# Azure Context Verification
Write-Host "🔍 STEP 1: Verifying Azure Context" -ForegroundColor Magenta
Write-Host "──────────────────────────────────" -ForegroundColor Magenta
Write-Host "   • Tenant: $($currentAccount.tenantId)"
Write-Host "   • Subscription: $currentSubName"
Write-Host "   • User: $($currentAccount.user.name)"
Write-Host ""

# Verify subscription matches parameter
if ($currentSubId -ne $SubscriptionId) {
    Write-Host "   ❌ ERROR: Subscription Mismatch" -ForegroundColor Red
    Write-Host "      Current: $currentSubId" -ForegroundColor Red
    Write-Host "      Expected: $SubscriptionId" -ForegroundColor Red
    Write-Host ""
    Write-Host "   💡 Fix Options:" -ForegroundColor Yellow
    Write-Host "      Option 1: Switch to the target subscription" -ForegroundColor Yellow
    Write-Host "         az account set --subscription $SubscriptionId" -ForegroundColor White
    Write-Host ""
    Write-Host "      Option 2: Use your current subscription instead" -ForegroundColor Yellow
    Write-Host "         Re-run this script with: -SubscriptionId $currentSubId" -ForegroundColor White
    Write-Host ""
    Write-Host "   🔍 To see all your subscriptions:" -ForegroundColor Yellow
    Write-Host "         az account list --output table" -ForegroundColor White
    exit 1
}

Write-Host "   ✅ Azure context verified!" -ForegroundColor Green
Write-Host ""


# Validate or Create Resource Group
Write-Host "🏗️  STEP 2: Setting up Resource Group" -ForegroundColor Magenta
Write-Host "────────────────────────────────────────" -ForegroundColor Magenta
$rg = az group show --name $ResourceGroupName -o json 2>$null | ConvertFrom-Json
if (-not $rg) {
    # Resource group doesn't exist, need to create it
    if (-not $ResourceGroupLocation) {
        Write-Host "   ❌ ERROR: Resource group '$ResourceGroupName' does not exist" -ForegroundColor Red
        Write-Host "      and no ResourceGroupLocation parameter was provided." -ForegroundColor Red
        Write-Host ""
        Write-Host "   💡 Fix: Either:" -ForegroundColor Yellow
        Write-Host "      • Provide -ResourceGroupLocation parameter (e.g., 'East US')" -ForegroundColor Yellow
        Write-Host "      • Create the resource group first: az group create --name $ResourceGroupName --location <location>" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "   📍 Creating resource group '$ResourceGroupName' in '$ResourceGroupLocation'..."
    az group create --name $ResourceGroupName --location $ResourceGroupLocation | Out-Null
    Write-Host "   ✅ Resource group created successfully" -ForegroundColor Green
    $actualLocation = $ResourceGroupLocation
} else {
    Write-Host "   ✅ Resource group '$ResourceGroupName' already exists (in $($rg.location))" -ForegroundColor Green
    $actualLocation = $rg.location
}
Write-Host ""


# Creating Application
Write-Host "🔐 STEP 3: Creating Entra ID Application" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor Magenta
$app = az ad app list --display-name $DisplayName --query "[0]" -o json | ConvertFrom-Json
if (-not $app) {
    Write-Host "   📝 Creating Entra ID application..."
    $app = az ad app create --display-name $DisplayName -o json | ConvertFrom-Json
    Write-Host "   ✅ Application created successfully" -ForegroundColor Green
} else {
    Write-Host "   ✅ Application '$DisplayName' already exists" -ForegroundColor Green
}
$appId = $app.appId
$appObjectId = $app.id
Write-Host "   📋 App ID: $appId"
Write-Host ""


# Creating Service Principal
Write-Host "👤 STEP 4: Creating Service Principal" -ForegroundColor Magenta
Write-Host "──────────────────────────────────────" -ForegroundColor Magenta
$sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" -o json | ConvertFrom-Json
if (-not $sp) {
    Write-Host "   🔧 Creating service principal..."
    $sp = az ad sp create --id $appId -o json | ConvertFrom-Json
    Write-Host "   ✅ Service principal created successfully" -ForegroundColor Green
} else {
    Write-Host "   ✅ Service principal already exists" -ForegroundColor Green
}
$spObjectId = $sp.id
Write-Host "   📋 Service Principal ID: $spObjectId"
Write-Host ""


# Setup Federated Credential
Write-Host "🔗 STEP 5: Configuring GitHub OIDC (Secretless Auth)" -ForegroundColor Magenta
Write-Host "───────────────────────────────────────────────────" -ForegroundColor Magenta
$feds = az ad app federated-credential list --id $appId -o json | ConvertFrom-Json
$existingFed = $feds | Where-Object { $_.issuer -eq $Issuer -and $_.subject -eq $Subject -and $_.audiences -contains $Audience }
if (-not $existingFed) {
    Write-Host "   🎫 Adding federated credential for GitHub Actions..."
    
    # Create parameters as a hashtable and save to temp file (most reliable approach)
    $credentialName = "gh-" + (Get-Date -Format "yyyyMMddHHmmss")
    $paramsObj = @{
        issuer = $Issuer
        subject = $Subject
        description = "GitHub OIDC $Subject"
        audiences = @($Audience)
        name = $credentialName
    }
    
    # Use temp file approach to avoid PowerShell JSON escaping issues
    $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
    
    try {
        $paramsObj | ConvertTo-Json -Depth 4 | Out-File -FilePath $tempFile -Encoding UTF8
        az ad app federated-credential create --id $appId --parameters "@$tempFile" | Out-Null
        Write-Host "   ✅ Federated credential configured successfully" -ForegroundColor Green
    } finally {
        # Clean up temp file
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
} else {
    Write-Host "   ✅ Federated credential already configured" -ForegroundColor Green
}
Write-Host "   📋 Subject: $Subject"
Write-Host "   📋 Issuer: $Issuer"
Write-Host ""


# Role Assignment
Write-Host "🔑 STEP 6: Assigning Deployment Permissions" -ForegroundColor Magenta
Write-Host "───────────────────────────────────────────" -ForegroundColor Magenta
$exists = az role assignment list --assignee $appId --scope $Scope --role $Role --query "[0]" -o json | ConvertFrom-Json
if (-not $exists) {
    Write-Host "   🛡️  Assigning '$Role' role to service principal..."
    az role assignment create --assignee $appId --role $Role --scope $Scope | Out-Null
    Write-Host "   ✅ Role assignment completed successfully" -ForegroundColor Green
} else {
    Write-Host "   ✅ Role '$Role' already assigned" -ForegroundColor Green
}
Write-Host "   📋 Scope: Resource Group '$ResourceGroupName'"
Write-Host "   📋 Role: $Role"
Write-Host ""


# Summary and GitHub Secrets
Write-Host "🎉 SETUP COMPLETE!" -ForegroundColor Green
Write-Host "═════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "📊 Summary of Created Resources:" -ForegroundColor Cyan
Write-Host "  ✅ Resource Group: $ResourceGroupName (in $actualLocation)"
Write-Host "  ✅ Entra ID App: $DisplayName"
Write-Host "  ✅ Service Principal: $spObjectId"
Write-Host "  ✅ Federated Credential: GitHub OIDC configured"
Write-Host "  ✅ Role Assignment: $Role on Resource Group"
Write-Host ""

Write-Host "🔐 GitHub Repository Secrets" -ForegroundColor Yellow
Write-Host "═══════════════════════════════" -ForegroundColor Yellow
Write-Host "Copy these values to your GitHub repository secrets:" -ForegroundColor White
Write-Host ""
Write-Host "Secret Name: AZURE_DEPLOY_APP_ID" -ForegroundColor Cyan
Write-Host "Value: $appId" -ForegroundColor White
Write-Host ""
Write-Host "Secret Name: AZURE_TENANT_ID" -ForegroundColor Cyan  
Write-Host "Value: $TenantId" -ForegroundColor White
Write-Host ""
Write-Host "Secret Name: AZURE_SUBSCRIPTION_ID" -ForegroundColor Cyan
Write-Host "Value: $SubscriptionId" -ForegroundColor White
Write-Host ""

Write-Host "📝 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Add the above secrets to your GitHub repository"
Write-Host "     (Settings → Secrets and variables → Actions)"
Write-Host "  2. Copy 'example-github-workflow.yml' to '.github/workflows/deploy.yml'"
Write-Host "  3. Customize the workflow for your needs"
Write-Host "  4. Push to your main branch to trigger deployment!"
Write-Host ""

Write-Host "🧪 Validation:" -ForegroundColor Yellow
Write-Host "  Run: .\test-deploy-sp.ps1 -AppId $appId -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName"
Write-Host ""

# Technical output for automation/logging
$result = [pscustomobject]@{
    displayName      = $DisplayName
    appId            = $appId
    servicePrincipal = $spObjectId
    tenantId         = $TenantId
    subscriptionId   = $SubscriptionId
    resourceGroup    = $ResourceGroupName
    location         = $actualLocation
    scope            = $Scope
    githubSubject    = $Subject
    issuer           = $Issuer
    audience         = $Audience
}

Write-Host "📋 Technical Details (JSON):" -ForegroundColor DarkGray
$result | ConvertTo-Json -Depth 3
 