vaultpay-zero-trust-api/diagrams/architecture.png
vaultpay-zero-trust-api/diagrams/architecture.png
# VaultPay Ltd - Zero-Trust Payments API

> **Client:** VaultPay Ltd - London Fintech (FCA Authorised Payments Institution)  
> **Product:** Instant GBP payments API for marketplaces  
> **Region:** eu-west-2 (London) | **IaC:** Terraform | **Pattern:** Zero Trust + Idempotency

### 📖 Company Story
VaultPay processes £2M daily for UK marketplaces. Their old API used static API keys stored in GitHub (leaked in 2024). No audit trail, no rate limiting - a competitor scraped all transactions.

**Requirements from CISO:**
- Zero Trust: every request authenticated with short-lived JWT (1h), not static keys
- Idempotency: payments must not double-charge if client retries
- Least privilege: Lambda can only read/write its own user's transactions
- UK data residency, KMS CMK with rotation, all logs encrypted
- Rate limiting + WAF to stop scraping
- PCI-DSS style audit logs

### 🏗️ Architecture

```
Marketplace -> WAF (Rate 1000/IP + CommonRuleSet) -> API GW HTTP API
  | JWT Authorizer (Cognito issuer)
  |-> Lambda in Private Subnets (X-Ray, KMS, VPC, no internet)
       |-> DynamoDB Transactions (KMS CMK, PITR, TTL) - PK=user_id (from JWT sub)
       |-> DynamoDB Idempotency (KMS, TTL 24h) - PK=Idempotency-Key header
       |-> CloudWatch Logs (KMS) + X-Ray traces

Cognito User Pool: 12-char password, SRP auth, 1h token validity, prevent user enumeration
```

**Key Design Decisions:**
- **user_id = JWT sub claim** - Lambda cannot query other users' data, enforced in code + IAM condition
- **Idempotency table** - Client sends `Idempotency-Key` header, we store 24h, return original response on duplicate
- **Lambda in VPC** - Even if code compromised, cannot exfiltrate to internet (no NAT, only VPC endpoints for DynamoDB/KMS)
- **KMS everywhere** - DynamoDB CMK, Lambda env vars, CloudWatch Logs - allows key revocation = instant kill switch

### 🔒 Zero Trust Controls

| Control | Implementation |
| :--- | :--- |
| **Authentication** | Cognito JWT, 1h validity, audience check, issuer `https://cognito-idp.eu-west-2.amazonaws.com/<pool>` |
| **Authorization** | API GW authorizer_type=JWT, no API key fallback. Lambda uses `sub` as partition key |
| **Network** | Private subnets only, SG no ingress, egress 0.0.0.0/0 but no NAT - add VPC endpoints in prod |
| **Least Privilege** | IAM: only GetItem/PutItem/Query on transactions table + Get/Put on idempotency, no Scan, no DeleteTable |
| **Encryption** | KMS CMK with auto-rotation, policy allows only Log Archive account + CloudWatch Logs service |
| **Rate Limit** | WAF rate-based 1000/5min per IP blocks before Lambda = cost protection |

### 💷 Cost (Serverless = Cheap)

- API GW HTTP: $1 per 1M requests
- Lambda 128MB: $0.20 per 1M
- DynamoDB On-Demand: $1.25 per 1M writes, $0.25 per 1M reads
- WAF: $5/mo + $1 per 1M
- Cognito: Free <50k MAUs
- **For 5M payments/mo:** ~£35/mo vs £400+ for EC2 ALB

### 🚀 Deployment

```bash
# Package lambda
cd modules/compute
zip lambda.zip ../../src/handler.py
cd ../..

# Backend
aws s3 mb s3://vaultpay-terraform-state-eu-west-2 --region eu-west-2
aws dynamodb create-table --table-name terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region eu-west-2

terraform init
terraform apply

API=$(terraform output -raw api_url)
POOL=$(terraform output -raw cognito_pool_id)
CLIENT=$(terraform output -raw cognito_client_id)

# Create user
aws cognito-idp sign-up --client-id $CLIENT --username payments@test.com --password 'Str0ng!Pass1234' --region eu-west-2
aws cognito-idp admin-confirm-sign-up --user-pool-id $POOL --username payments@test.com --region eu-west-2

# Get JWT
TOKEN=$(aws cognito-idp initiate-auth --client-id $CLIENT --auth-flow USER_PASSWORD_AUTH --auth-parameters USERNAME=payments@test.com,PASSWORD='Str0ng!Pass1234' --region eu-west-2 --query 'AuthenticationResult.IdToken' --output text)

# Create payment with idempotency
curl -X POST $API/payments -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: order-123" -H "Content-Type: application/json" -d '{"amount": 25.50, "currency":"GBP"}'

# Duplicate - should return original
curl -X POST $API/payments -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: order-123" -d '{"amount": 25.50}'
```

### 🧪 Security Tests

- No token -> 401
- Expired token -> 401
- Try query other user_id -> returns 0 items (enforced by partition key)
- Flood 1001 req in 5 min from same IP -> WAF 403
- No Idempotency-Key on retry -> new txn (client bug - we document requirement)

### 🔮 Roadmap
- [ ] VPC Endpoints for DynamoDB + KMS (remove NAT)
- [ ] Cognito custom domain + PKCE for SPA
- [ ] Step Functions for payment settlement
- [ ] EventBridge to Ledger

---
**Architect:** Toyin Odesanya | Specialty: Fintech Zero Trust  
**Repo:** github.com/fourform-svg/vaultpay-zero-trust-api
