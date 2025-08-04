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

