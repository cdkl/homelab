data "terraform_remote_state" "cluster" {
  backend = "pg"
  config = {
    conn_str = "postgres://lorez.local:15432/terraform_cluster?sslmode=disable"
  }
}
