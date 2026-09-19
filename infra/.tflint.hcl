config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.44.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# The recommended preset wants required_version in every module. That is deliberately
# not done here: the root module in envs/ owns the Terraform version constraint, and a
# child module that pins its own becomes harder to reuse from a root on a different
# version. The constraint is declared once, in envs/dev/versions.tf.
rule "terraform_required_version" {
  enabled = false
}
