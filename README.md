# essesseff Onboarding Utility

### For essesseff subscribers

Automates the process of creating a new essesseff app in essesseff and GitHub, as well as configuring Argo CD deployments using the essesseff Public API and automation shell scripts provided in the template repos -- which process typically takes ***less than 5 minutes*** to complete.

### For non-subscribers to essesseff

Automates the process of cloning template repos, performing string replacement, creating new GitHub repos in desired org and with specified app name, as well as configuring Argo CD deployments using the GitHub API and automation shell scripts provided in the template repos -- which process typically takes ***less than 1 minute*** to complete.

## Features

- **List Templates**: View all available templates (global and account-specific, or bundled when using non-subscriber mode)
- **Create Apps**: Automatically create essesseff apps with all 9 repositories (via API for subscribers, or clone/replace/push for non-subscribers)
- **Non-essesseff-subscriber mode** (`--non-essesseff-subscriber-mode`): Create apps without an essesseff subscription — clone global templates, perform string replacement (org and app name), create and push repos to your GitHub org using a GitHub org admin PAT
- **Fault tolerance (non-subscriber mode)**: Automatic retries for transient failures: template clone (3 attempts, 10s delay), create-repo API on rate limit or server error (3 attempts, 15s delay), and push (3 attempts, 10s delay)
- **Setup Argo CD**: Configure Argo CD applications for dev, qa, staging, and/or prod environments
- **Rate Limiting**: Automatically respects essesseff API rate limits (subscriber mode)
- **Error Handling**: Comprehensive error handling with clear messages

## Prerequisites

Before using the essesseff onboarding utility, ensure the following prerequisites are met:

### Required Prerequisites

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

4. **essesseff API Key** (required for subscriber mode; not used with `--non-essesseff-subscriber-mode`):
   - Valid essesseff API key with appropriate permissions
   - API key must belong to the account specified in `ESSESSEFF_ACCOUNT_SLUG`

5. **GitHub Org Admin PAT** (required only for `--create-app` when using `--non-essesseff-subscriber-mode`):
   - **Classic PAT**: grant **`repo`** (create repos, push code) and **`workflow`** (create/update `.github/workflows` files; required because the templates include GitHub Actions workflows).
   - **Fine-grained PAT**: grant **Contents: Read and write**, **Metadata: Read**, and **Workflows: Read and write** for the organization (or all repositories); the token user must have permission in the org to create repositories.
   - The utility uses the PAT to call `POST /orgs/{org}/repos` and to push via HTTPS; do not confuse with `GITHUB_TOKEN` (Argo CD machine user).

6. **GitHub Machine User** (required for `--setup-argocd`):
   - GitHub machine user account created
   - Personal Access Token (PAT) with `repo` and `read:packages` scopes
   - Machine user added to the GitHub organization
   - See: [GitHub Argo CD Machine User Setup Guide](https://www.essesseff.com/docs/deployment/github-argocd-machine-user-setup#step-0:-tldr---quick-setup-for-essesseff-onboarding-utility)

## Installation

1. Clone or download the essesseff onboarding utility repository
2. Make the script executable:
   ```bash
   chmod +x essesseff-onboard.sh
   ```
3. Copy the example configuration file:
   ```bash
   cp .essesseff.example .essesseff
   ```
4. Edit `.essesseff` and fill in your configuration values

## Configuration

The utility reads configuration from a `.essesseff` file (by default). Create this file by copying `.essesseff.example` and filling in your values.

### Required Configuration Variables

**For all operations**:
- `ESSESSEFF_API_KEY` - Your essesseff API key
- `ESSESSEFF_ACCOUNT_SLUG` - Your essesseff team account slug
- `GITHUB_ORG` - GitHub organization login
- `APP_NAME` - essesseff app name (must conform to GitHub repository naming standards)

**For `--create-app`** (subscriber mode):
- `TEMPLATE_NAME` - Name of the template to use (e.g., "essesseff-hello-world-go-template")
- `TEMPLATE_IS_GLOBAL` - Set to `true` for global templates, `false` for account-specific templates

**For `--create-app` with `--non-essesseff-subscriber-mode`**:
- `TEMPLATE_NAME` - Template name = GitHub org of the template (e.g., "essesseff-hello-world-go-template"). Use `--list-templates --non-essesseff-subscriber-mode` to see available names.
- `GITHUB_ORG_ADMIN_PAT` - GitHub Personal Access Token with org repo create/push and **workflow** permissions (used to create the 9 repos and push content, including `.github/workflows`; classic PAT needs `repo` + `workflow` scopes)

**For `--setup-argocd`**:
- `ARGOCD_MACHINE_USER` - Argo CD machine user username
- `GITHUB_TOKEN` - GitHub Personal Access Token for the machine user
- `ARGOCD_MACHINE_EMAIL` - Email address for the machine user

### Optional Configuration Variables

- `ESSESSEFF_API_BASE_URL` - essesseff API base URL (defaults to `https://essesseff.com/api/v1`)
- `APP_DESCRIPTION` - App description (optional for `--create-app`)
- `REPOSITORY_VISIBILITY` - Repository visibility: `private` or `public` (default: `private`)
- `ARGOCD_INSTANCE_URL` - (optional, for `--setup-argocd` only) Base URL of your Argo CD instance (e.g. `https://argocd.example.com`). When set, the utility registers each environment's Argo CD application URL with essesseff (e.g. `https://argocd.example.com/applications/argocd/my-app-dev`), so the app's deployment cards and settings can link directly to the Argo CD application.

### App Name Requirements

App names must conform to GitHub repository naming standards:
- Allowed characters: lowercase letters (a-z), numbers (0-9), and dashes (-)
- Cannot start or end with a dash
- Examples: `my-app`, `hello-world`, `app123` ✅
- Invalid: `My-App`, `my_app`, `-my-app`, `my-app-` ❌

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

### Non-essesseff-subscriber mode (no essesseff subscription)

List bundled templates (no API key required):

```bash
./essesseff-onboard.sh --list-templates --non-essesseff-subscriber-mode --config-file .essesseff
```

Create app by cloning templates, replacing strings, and pushing to your GitHub org (requires `GITHUB_ORG_ADMIN_PAT` in `.essesseff`). Repos are cloned into the **current working directory** and left there after push so you can inspect content and debug string replacement:

```bash
./essesseff-onboard.sh \
  --create-app \
  --non-essesseff-subscriber-mode \
  --config-file .essesseff
```

Then optionally set up Argo CD (same as subscriber mode; requires Argo CD machine user credentials):

```bash
./essesseff-onboard.sh \
  --non-essesseff-subscriber-mode \
  --setup-argocd dev,qa,staging,prod \
  --config-file .essesseff
```

In non-subscriber mode the utility does not call the essesseff API. Argo CD setup does not provide notifications-secret.yaml; the argocd-env setup-argocd.sh scripts detect its absence and skip Argo CD Notifications setup (they only enable notifications when a real essesseff notifications-secret is present).

### Verbose Output

Enable verbose output for debugging:

```bash
./essesseff-onboard.sh --create-app --verbose --config-file .essesseff
```

## Command-Line Options

- `--list-templates` - List all available templates (global and account-specific, or bundled if used with `--non-essesseff-subscriber-mode`)
- `--language LANGUAGE` - Filter templates by language (go, python, node, java)
- `--create-app` - Create a new essesseff app (via API for subscribers, or clone/replace/push for non-subscribers)
- `--setup-argocd ENVS` - Comma-separated list of environments (dev,qa,staging,prod)
- `--non-essesseff-subscriber-mode` - Run without essesseff API: clone templates, replace strings, create and push repos to your GitHub org
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

### Strings not replaced in repo content (non-subscriber mode)

Repos are cloned into the current working directory (e.g. `hello-world`, `hello-world-config-dev`, …) and not deleted after push. You can inspect any directory to verify replacements. Replacement is **literal and case-sensitive**. The script replaces:
1. `template_org_login` (e.g. `essesseff-hello-world-go-template`) → `GITHUB_ORG`
2. `replacement_string` from the bundled template (e.g. `hello-world`) → `APP_NAME`

If some occurrences in the template repo use a different spelling or case (e.g. `hello_world`, `HelloWorld`), they will not be changed. The template repos are expected to use the exact strings defined in `bundled-global-templates.json`. If you see missing replacements, check the template source; org/app names containing `#`, `&`, or `\` are now escaped correctly.

### Template Clone Fails (non-subscriber mode)

**Error**: `Failed to clone https://github.com/<template-org>/<repo>.git`

**Solution**:
- Template repos are public; the script does not use auth to clone them. If the clone fails, check the **git error** printed above this message (the script now shows it): "Repository not found" → repo name or org may have changed; "Could not resolve host" or "Connection timed out" → retry (can be a transient GitHub or network issue).
- Wait a few minutes and run the command again if you suspect GitHub slowness.

### Repository Clone Fails (target app repos, e.g. setup-argocd)

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
