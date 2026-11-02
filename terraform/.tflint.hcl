# The terraform ruleset is bundled with tflint, so no `tflint --init` / network access is needed.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
