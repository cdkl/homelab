terraform {
    backend "pg" {
        conn_str = "postgresql://lorez.local:15432/terraform_services?sslmode=disable"
    }
}
