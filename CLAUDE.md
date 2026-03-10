# CLAUDE.md

## Project Overview

This repo contains the **essesseff Onboarding Utility** — a bash script that automates creating a new essesseff app (9 GitHub repositories) and configuring Argo CD deployments for dev/qa/staging/prod environments.

It operates in two distinct modes:
- **Subscriber mode** (default): Uses the essesseff Public API to create repos, webhooks, teams, and retention policies via `POST /apps`.
- **Non-subscriber mode** (`--non-essesseff-subscriber-mode`): Clones template repos from GitHub, performs string replacement, and pushes them to the target GitHub org using the GitHub API directly — no essesseff API key required.

## Key Files

| File | Purpose |
|---|---|
| `essesseff-onboard.sh` | Main entry point — all logic lives here |
| `.essesseff` | Runtime config (never commit — gitignored) |
| `.essesseff.example` | Template for creating `.essesseff` |
| `bundled-global-templates.json` | Bundled template definitions used in non-subscriber mode |
| `setup-argocd-cluster.sh` | Helper for installing Argo CD on a K8s cluster |

## Configuration (`.essesseff` file)

The script reads config from `.essesseff` by default (overridable via `--config-file`). **This file must never be committed** — it contains API keys and tokens. The `.gitignore` already excludes it.

### Variables by context

**essesseff subscribers only:**
- `ESSESSEFF_API_KEY` — API key (format: `ess_xxx...`); must belong to `ESSESSEFF_ACCOUNT_SLUG`
- `ESSESSEFF_ACCOUNT_SLUG` — team account slug
- `ESSESSEFF_API_BASE_URL` — defaults to `https://www.essesseff.com/api/v1`
- `ARGOCD_INSTANCE_URL` — optional; when set, registers ArgoCD app URLs with essesseff

**All modes:**
- `GITHUB_ORG` — target GitHub organization login
- `APP_NAME` — app name (see naming rules below)
- `TEMPLATE_NAME` — template name (e.g., `essesseff-hello-world-go-template`)
- `TEMPLATE_IS_GLOBAL` — `true` or `false`

**Non-subscriber mode only (for `--create-app`):**
- `GITHUB_ORG_ADMIN_PAT` — GitHub PAT with `repo` + `workflow` scopes (classic) or Contents/Metadata/Workflows read-write (fine-grained); used to create repos and push content including `.github/workflows` (**not** the same as `GITHUB_TOKEN`)

**For `--setup-argocd`:**
- `ARGOCD_MACHINE_USER` — Argo CD machine user username
- `GITHUB_TOKEN` — machine user PAT with `repo` + `read:packages` scopes (**not** the same as `GITHUB_ORG_ADMIN_PAT`)
- `ARGOCD_MACHINE_EMAIL` — machine user email

**Optional:**
- `APP_DESCRIPTION`
- `REPOSITORY_VISIBILITY` — `private` (default) or `public`

## App Naming Rules

App names must be GitHub-repo-safe:
- Allowed: lowercase letters (`a-z`), numbers (`0-9`), hyphens (`-`)
- Cannot start or end with a hyphen
- ✅ `my-app`, `hello-world`, `app123`
- ❌ `My-App`, `my_app`, `-my-app`, `my-app-`

## The 9-Repo Structure

Every app creates exactly 9 repositories with predictable names:

| Repo | Name pattern |
|---|---|
| Source | `{app-name}` |
| Config (×4) | `{app-name}-config-dev`, `-config-qa`, `-config-staging`, `-config-prod` |
| Argo CD (×4) | `{app-name}-argocd-dev`, `-argocd-qa`, `-argocd-staging`, `-argocd-prod` |

## String Replacement (Non-Subscriber Mode)

Replacement is **literal and case-sensitive**. The script replaces:
1. `template_org_login` (e.g. `essesseff-hello-world-go-template`) → `GITHUB_ORG`
2. `replacement_string` (e.g. `hello-world`) → `APP_NAME`

Template repos are cloned into the current working directory and are not deleted after push. App/org names containing `#`, `&`, or `\` are escaped correctly.

If replacements are missing, check that the template uses the exact strings from `bundled-global-templates.json`. Different casing or spellings (e.g. `HelloWorld`) will not be replaced.

## Rate Limiting

The essesseff API is rate-limited to **3 requests per 10 seconds**. The script automatically waits 4 seconds before each API call to stay compliant. HTTP 429 responses trigger an automatic retry after 10 seconds.

## System Dependencies

Required tools (script validates these before running):
- `bash` 4.0+
- `curl`
- `git`
- `jq`
- `kubectl` (only required for `--setup-argocd`)

## Coding Conventions

- Pure bash — no external scripting languages
- Comprehensive error handling with clear user-facing messages
- `--setup-argocd` continues with remaining environments if one fails
- Use `--verbose` flag for debug output
- `kubectl` must be pre-configured for each target environment before running — the script does not configure it

## Testing Approach

- Use `--non-essesseff-subscriber-mode` to test without live API calls
- Use `--list-templates` as a lightweight API connectivity check (subscriber mode)
- Use `--verbose` to trace execution
- Inspect cloned directories to verify string replacements before push (non-subscriber mode)

---

## essesseff API Reference

**Base URL:** `https://www.essesseff.com/api/v1`
> Use `www` to avoid 307 redirects.

**Auth header:** `X-API-Key: ess_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

**Rate limit:** 3 requests per 10 seconds (headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`)

**403 gotcha:** The API key must belong to the `account_slug` in the path. A mismatched key returns `403 Forbidden`, not `401`.

**API overview:** https://www.essesseff.com/docs/api

### Path structure

- Global resources: `/api/v1/global/...` — no account slug needed
- Account resources: `/api/v1/accounts/{account_slug}/...` — key must match slug

### Endpoints used by this script

#### GET /global/templates
https://www.essesseff.com/docs/api/templates#global

Lists global templates. Supports `?language=go|python|node|java|rust|php` filter.

Response fields per template:
```json
{
  "name": "essesseff-hello-world-go-template",
  "language": "go",
  "template_org_login": "essesseff-hello-world-go-template",
  "source_template_repo": "hello-world",
  "is_global_template": true,
  "replacement_string": "hello-world"
}
```

#### GET /global/templates/{template_name}
https://www.essesseff.com/docs/api/templates#global-detail

Returns all fields for a specific global template — same shape as above. Used to get the full template object before `POST /apps`.

> ⚠️ **Java Spring Boot exception:** The `replacement_string` for `essesseff-helloworld-springboot-templat` is `"helloworld"` (no hyphen), not `"hello-world"`. All other global templates use `"hello-world"`. Getting this wrong silently produces broken repos.

#### GET /accounts/{account_slug}/templates and GET /accounts/{account_slug}/templates/{template_name}
https://www.essesseff.com/docs/api/templates#global

Same shape as global templates but account-specific. API key must match `account_slug`.

#### POST /accounts/{account_slug}/organizations/{organization_login}/apps
https://www.essesseff.com/docs/api/apps#create

Creates the 9-repo app. 

> ⚠️ **`app_name` is a query parameter, not a body field:**
> `POST /api/v1/accounts/{slug}/organizations/{org}/apps?app_name={app_name}`

Request body:
```json
{
  "description": "optional",
  "programming_language": "go",
  "repository_visibility": "private",
  "template": {
    "template_org_login": "essesseff-hello-world-go-template",
    "source_template_repo": "hello-world",
    "is_global_template": true,
    "replacement_string": "hello-world"
  }
}
```

All four `template` fields are required. The response `resultant_repos` object contains all 9 repo names.

#### GET /accounts/{account_slug}/organizations/{organization_login}/apps/{app_name}
https://www.essesseff.com/docs/api/apps#detail

Gets app details including all `repository_urls` and `repository_ids`. Returns **404** if the app doesn't exist — this is how the script checks for pre-existing apps before attempting creation.

#### GET /accounts/{account_slug}/organizations/{organization_login}/apps/{app_name}/notifications-secret

Returns `notifications-secret.yaml` content (YAML, not JSON) for Argo CD setup. Secrets are auto-generated on first fetch. The file contains Argo CD webhook URL, AWS API Gateway key, and per-environment app secrets.

> ⚠️ **Delete this file after applying to the cluster — never commit it.**

#### POST /accounts/{account_slug}/organizations/{organization_login}/apps/{app_name}/environments/{env}/set-argocd-application-url

Sets the Argo CD application URL for a given environment in the essesseff UI. `env` must be `DEV`, `QA`, `STAGING`, or `PROD`. Returns `204 No Content` on success. Send `null` to clear. Only called when `ARGOCD_INSTANCE_URL` is set in config.
