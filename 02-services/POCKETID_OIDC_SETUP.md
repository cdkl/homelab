# PocketID OIDC Client Setup for TinyAuth Integration

## Prerequisites

Before TinyAuth can integrate with PocketID for OAuth authentication, you must complete the following manual setup steps in PocketID:

### 1. Create a User Account in PocketID

1. Visit `https://pocketid.cdklein.com/setup]`
2. Create your initial administrator account
3. Complete the PocketID initial setup process

### 2. Create an OIDC Client in PocketID

You need to create an OIDC client in PocketID with the following configuration:

#### Required OIDC Client Settings

- **Client Name**: TinyAuth (or any descriptive name)
- **Redirect URIs**: 
  - `https://auth.cdklein.com/api/oauth/callback/generic`
- **Grant Types**: 
  - `authorization_code`
  - `refresh_token`
- **Scopes**: 
  - `openid`
  - `email` 
  - `profile`
  - `groups`
- **Response Types**: `code`

#### After Creating the Client

1. Note the generated **Client ID** - you'll need this for your Terraform variables
2. Note the generated **Client Secret** - you'll need this for your Terraform variables

### 3. Configure Terraform Variables

In your `terraform.tfvars` file, define the following variables:

```hcl
# PocketID OIDC Integration
tinyauth_oauth_client_id     = "your-client-id-from-pocketid"
tinyauth_oauth_client_secret = "your-client-secret-from-pocketid"
```

### 4. TinyAuth Environment Variables

The TinyAuth deployment is already configured to use these environment variables:

```yaml
env:
  - name: GENERIC_CLIENT_ID
    value: var.tinyauth_oauth_client_id
  - name: GENERIC_CLIENT_SECRET
    value: var.tinyauth_oauth_client_secret
  - name: GENERIC_AUTH_URL
    value: https://pocketid.cdklein.com/authorize
  - name: GENERIC_TOKEN_URL
    value: https://pocketid.cdklein.com/api/oidc/token
  - name: GENERIC_USER_URL
    value: https://pocketid.cdklein.com/api/oidc/userinfo
  - name: GENERIC_SCOPES
    value: openid email profile groups
  - name: GENERIC_NAME
    value: Pocket ID
```

## Deployment

After configuring the variables in `terraform.tfvars`:

1. Apply the Terraform configuration:
   ```bash
   terraform plan
   terraform apply
   ```

2. The TinyAuth deployment will restart with the new OAuth configuration.

## Authentication Flow

When properly configured, the authentication flow works as follows:

1. User visits a protected service (e.g., `https://foundryvtt.cdklein.com`)
2. Traefik middleware checks authentication via TinyAuth
3. If not authenticated, user is redirected to `https://auth.cdklein.com`
4. TinyAuth login page offers "Login with Pocket ID" option
5. User clicks the button and is redirected to PocketID
6. After PocketID authentication, user is redirected back to TinyAuth
7. TinyAuth creates a session and redirects user back to original service

## Testing the Integration

You can test if the integration is working by:

1. **Visit TinyAuth**: Go to `https://auth.cdklein.com`
2. **OAuth Button**: Look for a "Pocket ID" login button
3. **OAuth Flow**: Click the button to test the redirect to PocketID
4. **Check Logs**: Monitor TinyAuth logs with:
   ```bash
   kubectl logs deployment/tinyauth -f
   ```

## Troubleshooting

If the integration isn't working:

1. **Verify PocketID Setup**: Ensure you've created a user account and completed initial setup
2. **Check OIDC Client**: Confirm the OIDC client exists in PocketID with the correct redirect URI
3. **Verify Variables**: Ensure `tinyauth_oauth_client_id` and `tinyauth_oauth_client_secret` are set correctly in your tfvars file
4. **Check Redirect URI**: Must be exactly `https://auth.cdklein.com/api/oauth/callback/generic`
5. **Monitor Logs**: Check both TinyAuth and PocketID logs for OAuth-related errors

## Important Notes

- **Manual Setup Required**: The OIDC client cannot be created automatically via Terraform - it must be set up manually in PocketID's web interface
- **Credentials Security**: Client ID and secret should be defined in your `terraform.tfvars` file and never committed to source control
- **First-Time Setup**: You must create at least one user account in PocketID before OAuth integration will work
- **HTTPS Required**: All OAuth flows require HTTPS endpoints

## URLs

- **PocketID**: https://pocketid.cdklein.com
- **TinyAuth**: https://auth.cdklein.com
- **PocketID OIDC Discovery**: https://pocketid.cdklein.com/.well-known/openid-configuration

## Security Notes

- Client credentials are stored as Terraform variables (marked as sensitive)
- HTTPS is enforced for all OAuth flows
- Session cookies are HTTP-only and secure
- Users authenticate with their PocketID credentials, not local TinyAuth accounts

The integration will only work after completing the manual PocketID setup steps above!
