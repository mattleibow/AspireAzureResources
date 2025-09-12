<#

Usage Examples:

    .\scripts\infra\test-deploy-sp.ps1 `
      -AppId "12345678-1234-1234-1234-123456789abc" `
      -SubscriptionId "87654321-4321-4321-4321-210987654321" `
      -ResourceGroupName "rg-aspire-dev"

#>

param(
    [Parameter(Mandatory=$true)] [string]$AppId,
    [Parameter(Mandatory=$true)] [string]$SubscriptionId,
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [string]$TenantId = ""
)

$ErrorActionPreference = "Stop"

# Get current Azure CLI context and auto-detect tenant if needed
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
    Write-Host "   az login" -ForegroundColor White
    Write-Host ""
    exit 1
}

if (-not $TenantId) {
    $TenantId = $currentAccount.tenantId
}

Write-Host ""
Write-Host "🧪 Service Principal Validation Tests" -ForegroundColor Cyan
Write-Host "════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "📋 Test Configuration:" -ForegroundColor Yellow
Write-Host "  • App ID: $AppId"
Write-Host "  • Subscription: $($currentAccount.name)"
Write-Host "  • Resource Group: $ResourceGroupName"
Write-Host "  • Tenant: $TenantId"
Write-Host ""

$ErrorCount = 0
$TestCount = 0

# Test 1: Verify resource group exists
Write-Host "🏗️  TEST 1: Resource Group Verification" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    $rg = az group show --name $ResourceGroupName -o json | ConvertFrom-Json
    if ($rg) {
        Write-Host "   ✅ Resource group '$ResourceGroupName' found in '$($rg.location)'" -ForegroundColor Green
        Write-Host "      📍 Location: $($rg.location)" -ForegroundColor DarkGray
        Write-Host "      📋 State: $($rg.properties.provisioningState)" -ForegroundColor DarkGray
        Write-Host "      🆔 Id: $($rg.id)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "   ❌ Resource group '$ResourceGroupName' not found" -ForegroundColor Red
    $ErrorCount++
}
Write-Host ""

# Test 2: Verify the application exists
Write-Host "🔐 TEST 2: Entra ID Application Verification" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    $app = az ad app show --id $AppId -o json | ConvertFrom-Json
    if ($app) {
        Write-Host "   ✅ Application '$($app.displayName)' found" -ForegroundColor Green
        Write-Host "      🆔 Object ID: $($app.id)" -ForegroundColor DarkGray
        Write-Host "      📅 Created: $($app.createdDateTime)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "   ❌ Application not found or inaccessible" -ForegroundColor Red
    $ErrorCount++
}
Write-Host ""

# Test 3: Verify service principal exists
Write-Host "👤 TEST 3: Service Principal Verification" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    $sp = az ad sp show --id $AppId -o json | ConvertFrom-Json
    if ($sp) {
        Write-Host "   ✅ Service Principal found" -ForegroundColor Green
        Write-Host "      🆔 Object ID: $($sp.id)" -ForegroundColor DarkGray
        Write-Host "      📋 Type: $($sp.servicePrincipalType)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "   ❌ Service Principal not found" -ForegroundColor Red
    $ErrorCount++
}
Write-Host ""

# Test 4: Check federated credentials (if not skipped)
Write-Host "🔗 TEST 4: GitHub OIDC Configuration" -ForegroundColor Magenta
Write-Host "───────────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    $feds = az ad app federated-credential list --id $AppId -o json | ConvertFrom-Json
    if ($feds -and $feds.Count -gt 0) {
        Write-Host "   ✅ Found $($feds.Count) federated credential(s)" -ForegroundColor Green
        $githubOidcFound = $false
        foreach ($fed in $feds) {
            Write-Host "      📋 Subject: $($fed.subject)" -ForegroundColor DarkGray
            Write-Host "      🌐 Issuer: $($fed.issuer)" -ForegroundColor DarkGray
            Write-Host "      👥 Audiences: $($fed.audiences -join ', ')" -ForegroundColor DarkGray
            Write-Host "" -ForegroundColor DarkGray
            if ($fed.issuer -eq "https://token.actions.githubusercontent.com") {
                Write-Host "      ✅ GitHub Actions OIDC issuer configured" -ForegroundColor Green
                $githubOidcFound = $true
            }
        }
        if (-not $githubOidcFound) {
            Write-Host "      ⚠️  GitHub Actions OIDC issuer not found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ❌ No federated credentials found" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "   ❌ Failed to list federated credentials" -ForegroundColor Red
    $ErrorCount++
}
Write-Host ""

# Test 5: Check role assignments at subscription scope (azd standard)
Write-Host "🔑 TEST 5: Permission Verification (AZD Standard)" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────" -ForegroundColor Magenta
$TestCount++
$subscriptionScope = "/subscriptions/$SubscriptionId"

try {
    $roles = az role assignment list --assignee $AppId --scope $subscriptionScope -o json | ConvertFrom-Json
    if ($roles -and $roles.Count -gt 0) {
        Write-Host "   ✅ Found $($roles.Count) subscription-level role assignment(s)" -ForegroundColor Green
        
        $contributorFound = $false
        $uaaFound = $false
        
        foreach ($role in $roles) {
            Write-Host "      🛡️  Role: $($role.roleDefinitionName)" -ForegroundColor Green
            Write-Host "         📍 Scope: $($role.scope)" -ForegroundColor DarkGray
            
            if ($role.roleDefinitionName -eq "Contributor") {
                $contributorFound = $true
                Write-Host "         ✅ Contributor role found (for resource management)" -ForegroundColor Green
            }
            if ($role.roleDefinitionName -eq "User Access Administrator") {
                $uaaFound = $true
                Write-Host "         ✅ User Access Administrator role found (for role management)" -ForegroundColor Green
            }
        }
        
        if (-not $contributorFound) {
            Write-Host "      ❌ Contributor role missing (required for azd deployment)" -ForegroundColor Red
            $ErrorCount++
        }
        if (-not $uaaFound) {
            Write-Host "      ❌ User Access Administrator role missing (required for azd)" -ForegroundColor Red
            $ErrorCount++
        }
        
        if ($contributorFound -and $uaaFound) {
            Write-Host "      ✅ All required azd roles are present!" -ForegroundColor Green
        }
        
    } else {
        Write-Host "   ❌ No subscription-level role assignments found (required for azd)" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "   ❌ Failed to check subscription-level role assignments" -ForegroundColor Red
    $ErrorCount++
}
Write-Host ""

# Test 6: Test a simple read operation (list resources in RG)
Write-Host "📋 TEST 6: Resource Access Test" -ForegroundColor Magenta
Write-Host "───────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    # This tests if the SP has at least Reader permissions
    Write-Host "   🔍 Checking resource access permissions..." -ForegroundColor DarkGray
    
    # Try to list resources (this tests read permissions)
    $resourcesJson = az resource list --resource-group $ResourceGroupName -o json 2>$null
    if ($resourcesJson) {
        $resourceList = $resourcesJson | ConvertFrom-Json
        $resourceCount = $resourceList.Count
        Write-Host "   ✅ Successfully listed resources ($resourceCount found)" -ForegroundColor Green
        
        if ($resourceCount -gt 0) {
            foreach ($res in $resourceList) {
                Write-Host "      📦 $($res.name) ($($res.type))" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "   ❌ Failed to list resources (permission issue?)" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "   ❌ Failed to list resources (permission issue?)" -ForegroundColor Red
    Write-Host "      🔍 Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    $ErrorCount++
}
Write-Host ""

# Test 7: Test deployment capability (validation only)
Write-Host "🚀 TEST 7: Deployment Capability Test" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────" -ForegroundColor Magenta
$TestCount++
try {
    # Create a minimal test template to validate deployment permissions
    $testTemplate = @{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters = @{}
        variables = @{}
        resources = @()
        outputs = @{
            testOutput = @{
                type = "string"
                value = "validation-success"
            }
        }
    } | ConvertTo-Json -Depth 10

    $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
    $testTemplate | Out-File -FilePath $tempFile -Encoding UTF8

    # Validate deployment (doesn't actually deploy anything)
    Write-Host "   🔍 Running ARM template validation..." -ForegroundColor DarkGray
    $validation = az deployment group validate --resource-group $ResourceGroupName --template-file $tempFile -o json | ConvertFrom-Json
    
    Remove-Item $tempFile -Force

    if ($validation.error) {
        Write-Host "   ❌ Deployment validation failed: $($validation.error.message)" -ForegroundColor Red
        $ErrorCount++
    } else {
        Write-Host "   ✅ Deployment validation successful" -ForegroundColor Green
        Write-Host "      📋 Template validation passed" -ForegroundColor DarkGray
        Write-Host "      🛡️  Deployment permissions confirmed" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "   ❌ Deployment validation failed" -ForegroundColor Red
    Write-Host "      🔍 Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    $ErrorCount++
}
Write-Host ""

# Summary
Write-Host "🎉 VALIDATION COMPLETE!" -ForegroundColor Green
Write-Host "══════════════════════" -ForegroundColor Green
Write-Host ""

if ($ErrorCount -eq 0) {
    Write-Host "✅ All $TestCount tests passed! Service Principal is ready for deployment." -ForegroundColor Green
    Write-Host ""
    Write-Host "🔐 GitHub Repository Variables" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════" -ForegroundColor Yellow
    Write-Host "Add these values to your GitHub repository variables:" -ForegroundColor White
    Write-Host "(Settings → Secrets and variables → Actions → Variables tab)" -ForegroundColor White
    Write-Host ""
    Write-Host "Variable Name: AZURE_CLIENT_ID" -ForegroundColor Cyan
    Write-Host "Value: $AppId" -ForegroundColor White
    Write-Host ""
    Write-Host "Variable Name: AZURE_TENANT_ID" -ForegroundColor Cyan  
    Write-Host "Value: $TenantId" -ForegroundColor White
    Write-Host ""
    Write-Host "Variable Name: AZURE_SUBSCRIPTION_ID" -ForegroundColor Cyan
    Write-Host "Value: $SubscriptionId" -ForegroundColor White
    Write-Host ""
    Write-Host "Variable Name: AZURE_ENV_NAME" -ForegroundColor Cyan
    Write-Host "Value: [Choose your environment name, e.g., 'dev', 'staging', 'prod']" -ForegroundColor White
    Write-Host ""
    Write-Host "Variable Name: AZURE_LOCATION" -ForegroundColor Cyan
    Write-Host "Value: [Your Azure region, e.g., 'eastus', 'westus2']" -ForegroundColor White
    Write-Host ""
    Write-Host "📝 Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Add the above variables to your GitHub repository"
    Write-Host "     (Settings → Secrets and variables → Actions → Variables tab)"
    Write-Host "  2. Set AZURE_ENV_NAME to your preferred environment name (e.g., 'dev')"
    Write-Host "  3. Your GitHub Actions workflow will use these variables for azd deployment"
    Write-Host "  4. Deploy your infrastructure with confidence! 🚀"
    Write-Host ""
} else {
    Write-Host "❌ $ErrorCount out of $TestCount tests failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "🔧 Troubleshooting Steps:" -ForegroundColor Yellow
    Write-Host "  1. Re-run the create-deploy-sp.ps1 script"
    Write-Host "  2. Check Azure Portal → Entra ID → App registrations"
    Write-Host "  3. Verify role assignments in Azure Portal → IAM"
    Write-Host ""
    exit 1
}
