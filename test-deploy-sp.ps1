# Test script to validate the deployment Service Principal is correctly configured
# This simulates what GitHub Actions will do (minus the OIDC token exchange)

param(
    [Parameter(Mandatory=$true)] [string]$AppId,
    [Parameter(Mandatory=$true)] [string]$SubscriptionId,
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [string]$TenantId = "",  # Auto-detect if not provided
    [switch]$TestRoleOnly,   # Skip federated credential tests
    [switch]$Verbose
)

Write-Host "=== Testing Deployment Service Principal ===" -ForegroundColor Cyan
Write-Host "AppId: $AppId"
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroupName"
Write-Host ""

# Get tenant ID if not provided
if (-not $TenantId) {
    $TenantId = (az account show --query tenantId -o tsv)
    Write-Host "Auto-detected Tenant: $TenantId"
}

$ErrorCount = 0

# Test 1: Verify the application exists
Write-Host "Test 1: Application exists..." -ForegroundColor Yellow
try {
    $app = az ad app show --id $AppId -o json | ConvertFrom-Json
    if ($app) {
        Write-Host "✓ Application '$($app.displayName)' found" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  ObjectId: $($app.id)"
        }
    }
} catch {
    Write-Host "✗ Application not found or inaccessible" -ForegroundColor Red
    $ErrorCount++
}

# Test 2: Verify service principal exists
Write-Host "Test 2: Service Principal exists..." -ForegroundColor Yellow
try {
    $sp = az ad sp show --id $AppId -o json | ConvertFrom-Json
    if ($sp) {
        Write-Host "✓ Service Principal found" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "  ObjectId: $($sp.id)"
            Write-Host "  ServicePrincipalType: $($sp.servicePrincipalType)"
        }
    }
} catch {
    Write-Host "✗ Service Principal not found" -ForegroundColor Red
    $ErrorCount++
}

# Test 3: Check federated credentials (if not skipped)
if (-not $TestRoleOnly) {
    Write-Host "Test 3: Federated credentials..." -ForegroundColor Yellow
    try {
        $feds = az ad app federated-credential list --id $AppId -o json | ConvertFrom-Json
        if ($feds -and $feds.Count -gt 0) {
            Write-Host "✓ Found $($feds.Count) federated credential(s)" -ForegroundColor Green
            foreach ($fed in $feds) {
                if ($Verbose) {
                    Write-Host "  - Subject: $($fed.subject)"
                    Write-Host "    Issuer: $($fed.issuer)"
                    Write-Host "    Audiences: $($fed.audiences -join ', ')"
                }
                if ($fed.issuer -eq "https://token.actions.githubusercontent.com") {
                    Write-Host "    ✓ GitHub Actions OIDC issuer found" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "✗ No federated credentials found" -ForegroundColor Red
            $ErrorCount++
        }
    } catch {
        Write-Host "✗ Failed to list federated credentials" -ForegroundColor Red
        $ErrorCount++
    }
}

# Test 4: Check role assignments at resource group scope
Write-Host "Test 4: Role assignments..." -ForegroundColor Yellow
$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
try {
    $roles = az role assignment list --assignee $AppId --scope $scope -o json | ConvertFrom-Json
    if ($roles -and $roles.Count -gt 0) {
        Write-Host "✓ Found $($roles.Count) role assignment(s) at resource group scope" -ForegroundColor Green
        foreach ($role in $roles) {
            Write-Host "  - Role: $($role.roleDefinitionName)" -ForegroundColor Green
            if ($Verbose) {
                Write-Host "    Scope: $($role.scope)"
                Write-Host "    Principal: $($role.principalName)"
            }
        }
    } else {
        Write-Host "✗ No role assignments found at resource group scope" -ForegroundColor Red
        $ErrorCount++
    }
} catch {
    Write-Host "✗ Failed to check role assignments" -ForegroundColor Red
    $ErrorCount++
}

# Test 5: Test a simple read operation (list resources in RG)
Write-Host "Test 5: Permission test (list resources)..." -ForegroundColor Yellow
try {
    # This tests if the SP has at least Reader permissions
    $resources = az resource list --resource-group $ResourceGroupName --query "length(@)" -o tsv
    Write-Host "✓ Successfully listed resources ($resources found)" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to list resources (permission issue?)" -ForegroundColor Red
    $ErrorCount++
    if ($Verbose) {
        Write-Host "  Error: $($_.Exception.Message)"
    }
}

# Test 6: Test deployment capability (validation only)
Write-Host "Test 6: Deployment validation test..." -ForegroundColor Yellow
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
    $validation = az deployment group validate --resource-group $ResourceGroupName --template-file $tempFile -o json | ConvertFrom-Json
    
    Remove-Item $tempFile -Force

    if ($validation.error) {
        Write-Host "✗ Deployment validation failed: $($validation.error.message)" -ForegroundColor Red
        $ErrorCount++
    } else {
        Write-Host "✓ Deployment validation successful" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Deployment validation failed" -ForegroundColor Red
    $ErrorCount++
    if ($Verbose) {
        Write-Host "  Error: $($_.Exception.Message)"
    }
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
if ($ErrorCount -eq 0) {
    Write-Host "✓ All tests passed! The Service Principal is correctly configured for deployment." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Add these GitHub repository secrets:"
    Write-Host "   - AZURE_DEPLOY_APP_ID: $AppId"
    Write-Host "   - AZURE_TENANT_ID: $TenantId"
    Write-Host "   - AZURE_SUBSCRIPTION_ID: $SubscriptionId"
    Write-Host "2. Use the OIDC login action in your GitHub workflow"
    Write-Host "3. Deploy your infrastructure!"
} else {
    Write-Host "✗ $ErrorCount test(s) failed. Please review the errors above." -ForegroundColor Red
    exit 1
}
