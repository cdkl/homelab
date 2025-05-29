variable "rails_master_key" {
  description = "Rails master key for kegserve - this is set in config/master.key in the kegserve project, and is also specified in kegserve's actions secrets."
  type        = string
  sensitive   = true
}