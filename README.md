# Aspire Azure Resources

A .NET Aspire application with Azure deployment infrastructure.

## 🚀 Quick Start

### For Developers (Running Locally)

**Option 1: Using Aspire CLI**
1. Restore .NET tools (one time)
   ```bash
   dotnet tool restore
   ```
2. Run the application
   ```bash
   dotnet aspire run
   ```

**Option 2: Using .NET CLI**
1. Run the application
   ```bash
   dotnet run --project src/AspireAzureResources.AppHost
   ```

### For DevOps (Setting Up Deployment)

> [!NOTE]
> See [Infrastructure Setup Guide](scripts/infra/README.md) for complete deployment setup instructions.

**Quick Setup:**
1. Login to Azure with correct tenant/subscription
2. Run `scripts/infra/create-deploy-sp.ps1` to create deployment identity
3. Add output secrets to GitHub repository settings
4. Push to main branch → automatic deployment via GitHub Actions

## 📁 Project Structure

```
├── src/                                        # Application source code
│   ├── AspireAzureResources.AppHost/           # Aspire orchestration
│   └── AspireAzureResources.ServiceDefaults/
├── scripts/infra/                              # Infrastructure & deployment scripts
│   ├── create-deploy-sp.ps1                    # Creates Azure deployment identity
│   ├── test-deploy-sp.ps1                      # Validates deployment setup
│   └── README.md                               # Complete setup documentation
└── azure.yaml                                  # Azure Developer CLI configuration
```

## 🏗️ Infrastructure

This project uses **secretless deployment** with Azure workload identity federation:

- **🔧 CI/CD**: Federated Service Principal (OIDC, no stored secrets)
- **📥 Data Ingestion**: User Assigned Managed Identity (write permissions)
- **🤖 AI Agents**: User Assigned Managed Identity (read-only permissions)

**Security Features:**
- ✅ No client secrets stored anywhere
- ✅ Least privilege role assignments
- ✅ Resource group scoped permissions
- ✅ Audit trail for all operations

## 🔗 Links

- **[Infrastructure Setup](scripts/infra/README.md)** - Complete deployment setup guide
- **[.NET Aspire Documentation](https://learn.microsoft.com/en-us/dotnet/aspire/)** - Official Aspire documentation
- **[Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)** - Azure Developer CLI documentation
- **[Azure Portal](https://portal.azure.com)** - Manage Azure resources
- **[GitHub Actions](../../actions)** - View deployment runs
