variable "azs" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "endpoint_service_name" {
  description = "VPC Endpoint Service Name from provider"
  type        = string
}
