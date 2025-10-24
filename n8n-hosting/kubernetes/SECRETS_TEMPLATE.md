# Secrets Configuration Template

Before deploying n8n, you must generate secure random values for secrets.

## Step 1: Generate Random Values

Run these commands to generate secure random values:

```bash
# Generate encryption key
echo "N8N_ENCRYPTION_KEY: $(openssl rand -base64 32)"

# Generate runner auth token
echo "N8N_RUNNERS_AUTH_TOKEN: $(openssl rand -base64 24)"

# Generate PostgreSQL password
echo "POSTGRES_PASSWORD: $(openssl rand -base64 24)"
```

## Step 2: Update postgres-secret.yaml

Edit `postgres-secret.yaml` and replace these values:

```yaml
stringData:
  POSTGRES_USER: n8n_user
  POSTGRES_PASSWORD: <YOUR_GENERATED_PASSWORD>  # ← Replace this
  POSTGRES_DB: n8n
  POSTGRES_NON_ROOT_USER: n8n_user
  POSTGRES_NON_ROOT_PASSWORD: <YOUR_GENERATED_PASSWORD>  # ← Replace this
```

## Step 3: Update n8n-secret.yaml

Edit `n8n-secret.yaml` and replace these values:

```yaml
stringData:
  # Replace these CHANGE_ME values
  N8N_ENCRYPTION_KEY: "<YOUR_ENCRYPTION_KEY>"  # ← Replace this
  N8N_RUNNERS_AUTH_TOKEN: "<YOUR_AUTH_TOKEN>"  # ← Replace this
  
  # Optional: Set your webhook domain
  WEBHOOK_URL: "https://n8n.yourdomain.com"  # ← Optional: Uncomment and set
  
  # Optional: Adjust timezone
  GENERIC_TIMEZONE: "America/New_York"  # ← Adjust if needed
```

## Important Notes

⚠️ **CRITICAL**: The `N8N_ENCRYPTION_KEY` must be the same across ALL n8n instances (main, workers, webhook processors). If you lose this key, you will not be able to decrypt stored credentials.

⚠️ **Save these values securely**: Store the generated values in a password manager or secure vault. You may need them for:
- Scaling deployments
- Disaster recovery
- Migrating to new clusters

## Verification

Before deploying, verify that no placeholder values remain:

```bash
# Check for placeholder values
grep -r "CHANGE_ME" *.yaml
grep -r "changePassword" *.yaml

# If these commands return nothing, you're good to deploy!
```

## Example Generated Values

Here's what your generated values might look like:

```bash
# Example output (DO NOT USE THESE - generate your own!)
N8N_ENCRYPTION_KEY: dGVzdF9rZXlfZG9fbm90X3VzZV90aGlzX2dlbmVyYXRlX3lvdXJfb3du
N8N_RUNNERS_AUTH_TOKEN: dGVzdF90b2tlbl9nZW5lcmF0ZV95b3VyX293bg==
POSTGRES_PASSWORD: dGVzdF9wYXNzd29yZF9nZW5lcmF0ZV95b3VyX293bg==
```

## Quick Setup Script

Or use this one-liner to generate and display all values:

```bash
echo "Copy these values into your secret files:"
echo ""
echo "For postgres-secret.yaml:"
echo "  POSTGRES_PASSWORD: $(openssl rand -base64 24)"
echo ""
echo "For n8n-secret.yaml:"
echo "  N8N_ENCRYPTION_KEY: $(openssl rand -base64 32)"
echo "  N8N_RUNNERS_AUTH_TOKEN: $(openssl rand -base64 24)"
```

