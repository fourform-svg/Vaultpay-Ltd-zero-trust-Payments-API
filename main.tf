module "kms" { source = "./modules/kms" project = var.project }
module "data" { source = "./modules/data" project = var.project kms_key_arn = module.kms.key_arn }
module "auth" { source = "./modules/auth" project = var.project }
module "compute" { source = "./modules/compute" project = var.project kms_key_arn = module.kms.key_arn table_name = module.data.table_name table_arn = module.data.table_arn }
module "api" { source = "./modules/api" project = var.project lambda_invoke_arn = module.compute.invoke_arn lambda_function_name = module.compute.function_name cognito_client_id = module.auth.client_id cognito_endpoint = module.auth.endpoint kms_key_arn = module.kms.key_arn }
