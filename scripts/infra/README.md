# Infrastructure Setup Scripts

This folder contains scripts and documentation for setting up Azure deployment infrastructure for the Aspire application.

## 🚀 Quick Start

**One-time setup per environment:**

1. **Login to Azure** (correct tenant/subscription)
2. **Run setup script** to create deployment Service Principal
3. **Add secrets to GitHub** (copy-paste from script output)
4. **Deploy via GitHub Actions** (automatic from now on)

## 🏗️ Architecture Overview

**Three Identity Pattern (Recommended):**

1. **🔧 CI/CD Identity** (Federated Service Principal)
   - Purpose: Deploy infrastructure only
   - Permissions: Contributor on Resource Group
   - Authentication: OIDC (secretless)

2. **📥 Ingestion Identity** (User Assigned Managed Identity) 
   - Purpose: Write data to databases/storage
   - Permissions: Data write roles only (scoped)
   - Authentication: Managed Identity

3. **🤖 AI Agent Identity** (User Assigned Managed Identity)
   - Purpose: Read-only access to data
   - Permissions: Data read roles only (scoped)
   - Authentication: Managed Identity

## 📁 Files in This Folder

| File | Purpose | When to Use |
|------|---------|-------------|
| `README.md` | This documentation | Read first! |
| `create-deploy-sp.ps1` | Creates federated Service Principal for CI/CD | Run once per environment setup |
| `test-deploy-sp.ps1` | Validates SP configuration | Run after setup to verify |

## 🛠️ Step-by-Step Setup

### Step 1: Azure Login & Context

```powershell
# Login to Azure (will open browser)
az login

# If multiple tenants, specify the target tenant
az login --tenant "contoso.onmicrosoft.com"

# List available subscriptions
az account list --output table

# Set target subscription
az account set --subscription "Production Subscription"

# Verify current context
az account show --query "{tenant: tenantDisplayName, subscription: name}" -o table
```

### Step 2: Run Setup Script (Creates Everything!)

```powershell
# Run the setup script (adjust parameters for your environment)
./scripts/infra/create-deploy-sp.ps1 `
  -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
  -DisplayName "aspire-deploy-sp-dev" `
  -ResourceGroupName "rg-aspire-dev" `
  -ResourceGroupLocation "East US" `
  -GithubRepo "mattleibow/AspireAzureResources" `
  -SubjectMode branch `
  -SubjectValue main

# Copy the GitHub secrets from the output!
```

**Script Parameters:**
- `SubscriptionId`: Target Azure subscription (required)
- `DisplayName`: Name for the service principal (required - make it descriptive)
- `ResourceGroupName`: Resource group where this SP can deploy (required)
- `ResourceGroupLocation`: Azure region for the resource group (optional - only needed if RG doesn't exist)
- `GithubRepo`: Your GitHub repository in owner/repo format (required)
- `SubjectMode`: Authentication scope - `branch`, `environment`, or `tags` (optional, defaults to `branch`)
- `SubjectValue`: Branch name (e.g., `main`), environment name (e.g., `prod`), or `*` for tags (optional, defaults to `main`)
- `Role`: Azure role to assign (optional, defaults to `Contributor`)

**✨ What the script does automatically:**

1. **🔍 Verifies Azure Context** - Ensures you're logged in with correct tenant/subscription
2. **🏗️ Sets up Resource Group** - Creates if it doesn't exist (requires -ResourceGroupLocation)
3. **🔐 Creates Entra ID Application** - Registers the app for authentication
4. **👤 Creates Service Principal** - Creates the identity for deployments
5. **🔗 Configures GitHub OIDC** - Sets up secretless authentication (federated credentials)
6. **🔑 Assigns Deployment Permissions** - Grants Contributor role at Resource Group scope

**🛡️ Enhanced Error Handling:** Script stops immediately on any error (`$ErrorActionPreference = "Stop"`)

### Step 3: Validate Setup

```powershell
# Test the created Service Principal
./scripts/infra/test-deploy-sp.ps1 `
  -AppId "<APP_ID_FROM_SETUP_OUTPUT>" `
  -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
  -ResourceGroupName "rg-aspire-dev"

# All tests should pass ✅
```

### Step 4: Configure GitHub Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

```
AZURE_DEPLOY_APP_ID=<appId from script output>
AZURE_TENANT_ID=<tenantId from script output>
AZURE_SUBSCRIPTION_ID=<your subscription ID>
```

## 🔒 Security Best Practices

### Least Privilege Principle

- **Start broad, then narrow**: Begin with `Contributor` role, then create custom roles after understanding deployment needs
- **Scope appropriately**: Assign roles at Resource Group level, not Subscription
- **Regular review**: Audit permissions quarterly

### Multiple Environments

```powershell
# Development Environment
.\create-deploy-sp.ps1 -DisplayName "aspire-deploy-sp-dev" -ResourceGroupName "rg-aspire-dev" -ResourceGroupLocation "East US" -SubjectValue "develop"

# Staging Environment  
.\create-deploy-sp.ps1 -DisplayName "aspire-deploy-sp-staging" -ResourceGroupName "rg-aspire-staging" -ResourceGroupLocation "East US" -SubjectValue "staging"

# Production Environment
.\create-deploy-sp.ps1 -DisplayName "aspire-deploy-sp-prod" -ResourceGroupName "rg-aspire-prod" -ResourceGroupLocation "East US" -SubjectMode "environment" -SubjectValue "production"
```

### Subject Patterns

| Pattern | Use Case | Example |
|---------|----------|---------|
| `branch` | Branch-based deployment | `main`, `develop` |
| `environment` | Environment protection | `prod`, `staging` |
| `tags` | Release-based deployment | `*` (all tags) |

## 🚨 Troubleshooting

### Common Issues

**"Application already exists"**
- ✅ Normal - script is idempotent
- ✅ Will reuse existing app and add missing pieces

**"Permission denied creating application"**
- ❌ Need Application Administrator role
- 🔧 Ask Azure admin to grant role or run script for you

**"Role assignment failed"**
- ❌ Need Owner or User Access Administrator at target scope
- 🔧 Ask Azure admin to grant role at Resource Group level

**"GitHub Actions OIDC login fails"**
- ❌ Check repository secrets are correct
- ❌ Verify subject pattern matches your branch/environment
- 🔧 Run test script to validate configuration

### Validation Commands

```powershell
# Check current Azure context
az account show

# List applications you created
az ad app list --display-name "aspire-deploy-sp*" --query "[].{displayName:displayName, appId:appId}" -o table

# Check role assignments
az role assignment list --assignee "<APP_ID>" --scope "/subscriptions/<SUB_ID>/resourceGroups/<RG_NAME>" -o table

# List federated credentials
az ad app federated-credential list --id "<APP_ID>" --query "[].{name:name, subject:subject, issuer:issuer}" -o table
```

## 🔄 Maintenance

### Rotating Credentials

**Federated credentials don't need rotation** - they use OIDC token exchange (no stored secrets).

If you need to update the subject (e.g., change branch):
1. Run the setup script again with new `SubjectValue`
2. Old federated credentials remain (no harm)
3. Or manually delete old ones: `az ad app federated-credential delete --id <APP_ID> --federated-credential-id <CRED_ID>`

### Updating Permissions

```powershell
# Add new role to existing SP
az role assignment create --assignee "<APP_ID>" --role "Storage Account Contributor" --scope "/subscriptions/<SUB_ID>/resourceGroups/<RG_NAME>"

# Remove role from SP
az role assignment delete --assignee "<APP_ID>" --role "Contributor" --scope "/subscriptions/<SUB_ID>/resourceGroups/<RG_NAME>"
```

### Cleanup

```powershell
# Remove role assignments
az role assignment delete --assignee "<APP_ID>" --scope "/subscriptions/<SUB_ID>/resourceGroups/<RG_NAME>"

# Delete service principal
az ad sp delete --id "<APP_ID>"

# Delete application (also removes federated credentials)
az ad app delete --id "<APP_ID>"
```

## 📚 References

- [Azure Workload Identity Federation](https://docs.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure RBAC Best Practices](https://docs.microsoft.com/en-us/azure/role-based-access-control/best-practices)
- [.NET Aspire Overview](https://learn.microsoft.com/en-us/dotnet/aspire/get-started/aspire-overview)

## 🆘 Getting Help

1. **Run validation script** with `-Verbose` flag
2. **Check Azure Portal** → Entra ID → App registrations → Your app
3. **Test GitHub Actions** with a simple deployment
4. **Review logs** in GitHub Actions run details
5. **Ask team** - someone may have solved this before!

---

💡 **Pro Tip**: Save the output from your setup script - it contains all the information you need for troubleshooting and additional environment setups.
