variable "rails_master_key" {
  description = "Rails master key for kegserve - this is set in config/master.key in the kegserve project, and is also specified in kegserve's actions secrets."
  type        = string
  sensitive   = true
}

variable "tinyauth_users_list" {
  description = "List of maps containing user: bcrypt_hash pairs"
  type        = list(map(string))
}
