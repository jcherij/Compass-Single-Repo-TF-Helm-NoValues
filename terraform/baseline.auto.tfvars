# baseline.auto.tfvars — Compass
# Maintained by Platform Engineering. Lives in compass-infra.
# Auto-loaded by Terraform. Contains values stable across all environments:
# shared infrastructure sizing defaults and notification endpoints.
# Account-specific, region-specific, and environment-named values are NOT
# here — they live in compass-config.tfvars / compass-env.tfvars per environment.

aurora_min_capacity = 0.5
aurora_max_capacity = 4

redis_node_type = "cache.t4g.medium"

# Precedence test fixture — layer 3 of 5
test_precedence_tag = "baseline"
