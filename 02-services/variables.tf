variable "rails_master_key" {
  description = "Rails master key for kegserve - this is set in config/master.key in the kegserve project, and is also specified in kegserve's actions secrets."
  type        = string
  sensitive   = true
}

variable "tinyauth_users_list" {
  description = "List of maps containing user: bcrypt_hash pairs"
  type        = list(map(string))
}

variable "tinyauth_oauth_client_id" {
  description = "OAuth2 client ID for TinyAuth"
  type        = string
}

variable "tinyauth_oauth_client_secret" {
  description = "OAuth2 client secret for TinyAuth"
  type        = string
  sensitive   = true
}

variable "foundryvtt_username" {
  description = "FoundryVTT license username"
  type        = string
  sensitive   = true
}

variable "foundryvtt_password" {
  description = "FoundryVTT license password"
  type        = string
  sensitive   = true
}

variable "foundryvtt_release_url" {
  description = "FoundryVTT release download URL (from your licensed account)"
  type        = string
  sensitive   = true
}

variable "foundryvtt_admin_key" {
  description = "FoundryVTT admin access key for server configuration"
  type        = string
  sensitive   = true
}

variable "pocketid_client_id" {
  description = "PocketID OIDC client ID for oauth2-proxy"
  type        = string
}

variable "pocketid_client_secret" {
  description = "PocketID OIDC client secret for oauth2-proxy"
  type        = string
  sensitive   = true
}

variable "pocketid_api_key" {
  description = "PocketID API key for accessing PocketID services"
  type        = string
  sensitive   = true
}
