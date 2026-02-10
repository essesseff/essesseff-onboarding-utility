# essesseff Onboarding Utility

Using the essesseff Public API and (if running with `--setup-argocd`) shell scripts that execute kubectl, the essesseff Onboarding Utility automates the process of creating a new essesseff app in essesseff and GitHub, as well as of configuring Argo CD deployments on each of your env-specific K8s cluster(s).

*Please Note:*

*essesseff™ is an independent DevOps ALM PaaS-as-SaaS and is in no way affiliated with, endorsed by, sponsored by, or otherwise connected to GitHub® or The Linux Foundation®.* 

*essesseff™ and the essesseff™ logo design are trademarks of essesseff LLC.*

*GITHUB®, the GITHUB® logo design and the INVERTOCAT logo design are trademarks of GitHub, Inc., registered in the United States and other countries.*

*Argo®, Helm®, Kubernetes® and K8s® are registered trademarks of The Linux Foundation.*

This diagram provides a representation of what the essesseff onboarding utility is able to setup on a per app basis typically in under 5 minutes per app:

![Golden Path App Template Diagram](https://www.essesseff.com/images/architecture/essesseff-app-template-minus-subscription-light-mode.svg)

*Note: GitHub and K8s Licensed and Hosted Separately. This diagram shows an example of three K8s-deployed apps following the build-once-deploy-many "essesseff app" model, each app with its own Source and Helm-config-env GitHub repos (and Argo CD GitHub repos (not shown)), and with deployments distributed across as few or as many K8s clusters as desired, both on an env-specific basis as well as on a one-or-many deployments per environment basis. The essesseff app templates easily support and provide standardized configuration and automation OOTB for all of the above.*

## Features of essesseff Onboarding Utility

- **List Templates**: View all available templates (global and account-specific)
- **Create Apps**: Automatically create essesseff apps with all 9 repositories
- **Setup Argo CD**: Configure Argo CD applications for dev, qa, staging, and/or prod environments
- **Rate Limiting**: Automatically respects essesseff API rate limits
- **Error Handling**: Comprehensive error handling with clear messages

## Required Prerequisites for Running essesseff Onboarding Utility

1. **GitHub Organization Setup**:
   - GitHub organization must already exist
   - essesseff GitHub App must already be installed in the GitHub organization
   - Organization must be linked to the essesseff account (via essesseff UI)

2. **System Dependencies**:
   - `bash` (version 4.0 or higher)
   - `curl` (for API calls)
   - `git` (for repository cloning)
   - `jq` (for JSON parsing)
   - `kubectl` (required if using `--setup-argocd`)

3. **kubectl Configuration** (required for `--setup-argocd`):
   - `kubectl` must be installed and configured for each target environment
   - Kubernetes cluster access must be available for each target environment
   - Proper permissions to create secrets, configmaps, and Argo CD applications
   - **Important**: `kubectl` configuration is a prerequisite that must be completed before running the utility
  
4. (required for `--setup-argocd`) **(if not done already) Deploy/Configure Argo CD on each of the Environment-specific Kubernetes Cluster(s) by running the Argo CD cluster setup script**:

   From shell terminal(s) with kubectl configured for each env-specific K8s cluster:
```bash
   chmod 744 setup-argocd-cluster.sh
   ./setup-argocd-cluster.sh
   ```

5. **essesseff API Key**:
   - Valid essesseff API key with appropriate permissions
   - API key must belong to the account specified in `ESSESSEFF_ACCOUNT_SLUG`

6. **GitHub Machine User** (required for `--setup-argocd`):
   - GitHub machine user account created
   - Personal Access Token (PAT) with `repo` and `read:packages` scopes
   - Machine user added to the GitHub organization
   - See: [GitHub Argo CD Machine User Setup Guide](https://www.essesseff.com/docs/deployment/github-argocd-machine-user-setup#step-0:-tldr---quick-setup-for-essesseff-onboarding-utility)

## Installation of essesseff Onboarding Utility

1. Clone or download the essesseff onboarding utility repository, and if using --setup-argocd option, also be sure to execute with kubectl configured for the env-specific K8s cluster(s). 
2. Make the script executable:
   ```bash
   chmod +x essesseff-onboard.sh
   ```
3. Copy the example configuration file:
   ```bash
   cp .essesseff.example .essesseff
   ```
4. Edit `.essesseff` and fill in your configuration values

## Configuration of essesseff Onboarding Utility

The utility reads configuration from a `.essesseff` file (by default). Create this file by copying `.essesseff.example` and filling in your values.

### Required Configuration Variables

**For all operations**:
- `ESSESSEFF_API_KEY` - Your essesseff API key
- `ESSESSEFF_ACCOUNT_SLUG` - Your essesseff team account slug
- `GITHUB_ORG` - GitHub organization login
- `APP_NAME` - essesseff app name (must conform to GitHub repository naming standards)

**For `--create-app`**:
- `TEMPLATE_NAME` - Name of the template to use (e.g., "essesseff-hello-world-go-template")
- `TEMPLATE_IS_GLOBAL` - Set to `true` for global templates, `false` for account-specific templates

**For `--setup-argocd`**:
- `ARGOCD_MACHINE_USER` - Argo CD machine user username
- `GITHUB_TOKEN` - GitHub Personal Access Token for the machine user
- `ARGOCD_MACHINE_EMAIL` - Email address for the machine user

### Optional Configuration Variables

- `ESSESSEFF_API_BASE_URL` - essesseff API base URL (defaults to `https://essesseff.com/api/v1`)
- `APP_DESCRIPTION` - App description (optional for `--create-app`)
- `REPOSITORY_VISIBILITY` - Repository visibility: `private` or `public` (default: `private`)

### App Name Requirements

App names must conform to GitHub repository naming standards:
- Allowed characters: lowercase letters (a-z), numbers (0-9), and dashes (-)
- Cannot start or end with a dash
- Examples: `my-app`, `hello-world`, `app123` ✅
- Invalid: `My-App`, `my_app`, `-my-app`, `my-app-` ❌

*Please also note that java application names should not include hyphens.*

## Usage

### List Available Templates

List all available templates (global and account-specific):

```bash
./essesseff-onboard.sh --list-templates --config-file .essesseff
```

Filter templates by programming language:

```bash
./essesseff-onboard.sh --list-templates --language go --config-file .essesseff
```

### Create essesseff App

Create a new essesseff app (without Argo CD setup):

```bash
./essesseff-onboard.sh --create-app --config-file .essesseff
```

### Create App and Setup Argo CD

Create a new essesseff app and set up Argo CD for all environments:

```bash
./essesseff-onboard.sh \
  --create-app \
  --setup-argocd dev,qa,staging,prod \
  --config-file .essesseff
```

### Setup Argo CD Only

Set up Argo CD for specific environments (app already exists):

```bash
./essesseff-onboard.sh \
  --setup-argocd dev,qa \
  --config-file .essesseff
```

### Verbose Output

Enable verbose output for debugging:

```bash
./essesseff-onboard.sh --create-app --verbose --config-file .essesseff
```

## Command-Line Options

- `--list-templates` - List all available templates (global and account-specific)
- `--language LANGUAGE` - Filter templates by language (go, python, node, java)
- `--create-app` - Create a new essesseff app
- `--setup-argocd ENVS` - Comma-separated list of environments (dev,qa,staging,prod)
- `--config-file FILE` - Path to configuration file (default: `.essesseff`)
- `--verbose` - Enable verbose output
- `-h, --help` - Show help message

## How It Works

### App Creation Process

1. Validates app name conforms to GitHub repository naming standards
2. Checks if app already exists in the specified organization
3. Fetches template details (global or account-specific based on configuration)
4. Creates the essesseff app via API (creates all 9 repositories)

### Argo CD Setup Process

1. Downloads `notifications-secret.yaml` once (contains secrets for all environments)
2. For each specified environment:
   - Clones the Argo CD environment repository (`{app-name}-argocd-{env}`)
   - Creates `.env` file with only necessary variables
   - Copies `notifications-secret.yaml` to the repository
   - Executes `setup-argocd.sh` script

**Note**: The utility assumes `kubectl` is properly configured for each target environment. This is a prerequisite that must be completed before running the utility.

## Environment Variables in .env Files

When setting up Argo CD, the utility creates `.env` files in each Argo CD repository with only the variables required by `setup-argocd.sh`:

- `ARGOCD_MACHINE_USER`
- `GITHUB_TOKEN`
- `ARGOCD_MACHINE_EMAIL`
- `GITHUB_ORG`
- `APP_NAME`
- `ENVIRONMENT` (set per-environment: dev, qa, staging, or prod)

API-related variables (`ESSESSEFF_API_KEY`, `ESSESSEFF_API_BASE_URL`, `ESSESSEFF_ACCOUNT_SLUG`) and app creation variables (`APP_DESCRIPTION`, `REPOSITORY_VISIBILITY`, `TEMPLATE_NAME`, `TEMPLATE_IS_GLOBAL`) are NOT copied to the `.env` files as they are not needed by `setup-argocd.sh`.

## Rate Limiting

The utility automatically respects the essesseff API rate limit of 3 requests per 10 seconds by waiting 4 seconds before each API call. This ensures compliance with the rate limit.

## Error Handling

- Validates all configuration before making API calls
- Checks prerequisites (kubectl, git, etc.)
- Provides clear error messages with guidance
- Continues with other environments if one fails (for `--setup-argocd`)
- Handles HTTP 429 (rate limit) errors with automatic retry

## Validation

After running the onboarding utility, validate the setup:

1. **essesseff.com UI**: Verify all 9 repositories exist, check repository visibility, confirm webhook configuration
2. **Argo CD UI**: Verify Argo CD applications are created, check application sync status, validate repository connections, confirm notification webhooks are configured

## Troubleshooting

### kubectl Not Configured

**Error**: `kubectl is not properly configured or cannot connect to cluster`

**Solution**: Configure `kubectl` for the target environment before running the utility. This is a prerequisite.

### App Already Exists

**Error**: `App 'my-app' already exists in organization 'my-org'`

**Solution**: Choose a different app name or delete the existing app first.

### Repository Clone Fails

**Error**: `Failed to clone repository: my-app-argocd-dev`

**Solution**: 
- Ensure the app was created successfully
- Verify you have access to the repository
- Check that the repository exists in the GitHub organization

### API Rate Limit

**Warning**: `Rate limit exceeded, waiting 10 seconds before retry...`

**Solution**: The utility automatically handles rate limits. If you see this message, the utility will retry automatically.

## Security

- **Never commit `.essesseff` files** to version control (they contain sensitive API keys and tokens)
- The `.gitignore` file is configured to exclude `.essesseff` files
- Use `.essesseff.example` as a template and keep actual credentials secure

## Support

For issues, questions, or contributions, please open an issue in the [essesseff onboarding utility repository](https://github.com/essesseff/essesseff-onboarding-utility).

## License

MIT License

Copyright (c) 2026 essesseff LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
