output "api_url" { value = module.api.api_url }
output "cognito_pool_id" { value = module.auth.pool_id }
output "cognito_client_id" { value = module.auth.client_id }
output "dynamodb_table" { value = module.data.table_name }
output "waf_arn" { value = module.api.waf_arn }
