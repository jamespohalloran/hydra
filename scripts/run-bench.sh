#!/bin/bash

set -Eeuxo pipefail

cd "$( dirname "${BASH_SOURCE[0]}" )/.."

numReqs=10000
numParallel=100
clientId=benchclient
clientSecret=benchsecret
basicAuth=YmVuY2hjbGllbnQ6YmVuY2hzZWNyZXQ=

cat > BENCHMARKS.md << EOF
---
id: performance-hydra
title: ORY Hydra
---

In this document you will find benchmark results for different endpoints of ORY Hydra. All benchmarks are executed
using [rakyll/hey](https://github.com/rakyll/hey). Please note that these benchmarks run against the in-memory storage
adapter of ORY Hydra. These benchmarks represent what performance you would get with a zero-overhead database implementation.

We do not include benchmarks against databases (e.g. MySQL or PostgreSQL) as the performance greatly differs between
deployments (e.g. request latency, database configuration) and tweaking individual things may greatly improve performance.
We believe, for that reason, that benchmark results for these database adapters are difficult to generalize and potentially
deceiving. They are thus not included.

This file is updated on every push to master. It thus represents the benchmark data for the latest version.

All benchmarks run 10.000 requests in total, with 100 concurrent requests. All benchmarks run on Circle-CI with a
["2 CPU cores and 4GB RAM"](https://support.circleci.com/hc/en-us/articles/360000489307-Why-do-my-tests-take-longer-to-run-on-CircleCI-than-locally-)
configuration.

## BCrypt

ORY Hydra uses BCrypt to obfuscate secrets of OAuth 2.0 Clients. When using flows such as the OAuth 2.0 Client Credentials
Grant, ORY Hydra validates the client credentials using BCrypt which causes (by design) CPU load. CPU load and performance
depend on the BCrypt cost which can be set using the environment variable \`BCRYPT_COST\`. For these benchmarks,
we have set \`BCRYPT_COST=8\`.

EOF

BCRYPT_COST=8 PUBLIC_PORT=9000 ADMIN_PORT=9001 ISSUER_URL=http://localhost:9000 DATABASE_URL=memory hydra serve all --dangerous-force-http --disable-telemetry > /dev/null 2>&1 &

while ! echo exit | nc 127.0.0.1 9000; do sleep 1; done
while ! echo exit | nc 127.0.0.1 9001; do sleep 1; done

sleep 1

echo "Creating benchmark client"
hydra clients create \
    -g client_credentials \
    --id $clientId \
    --secret $clientSecret \
    -a foo \
    --endpoint http://localhost:9001

echo "Generating initial access tokens for token introspection benchmark"
authToken=$(hydra token client --endpoint http://localhost:9000 --client-id $clientId --client-secret $clientSecret)
introToken=$(hydra token client --endpoint http://localhost:9000 --client-id $clientId --client-secret $clientSecret)

cat >> BENCHMARKS.md << EOF
## OAuth 2.0

This section contains various benchmarks against OAuth 2.0 endpoints

### Token Introspection

\`\`\`
EOF

hey -n $numReqs -c $numParallel -m POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "token=$introToken" \
    http://localhost:9001/oauth2/introspect 2>&1 \
    | tee -a BENCHMARKS.md


cat >> BENCHMARKS.md << EOF
\`\`\`

### Client Credentials Grant

This endpoint uses [BCrypt](#bcrypt).

\`\`\`
EOF

hey -n $numReqs -c $numParallel -m POST \
	-H "Authorization: Basic $basicAuth" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    http://localhost:9000/oauth2/token 2>&1 \
    | tee -a BENCHMARKS.md


cat >> BENCHMARKS.md << EOF
\`\`\`

## OAuth 2.0 Client Management

### Creating OAuth 2.0 Clients

This endpoint uses [BCrypt](#bcrypt) and generates IDs and secrets by reading from `/dev/urandom` which negatively impacts
performance. Performance will be better if IDs and secrets are set in the request as opposed to generated by ORY Hydra.

\`\`\`
This test is currently disabled due to issues with /dev/urandom being inaccessible in the CI.
EOF

##hey -n $numReqs -c $numParallel -m POST \
#    -H "Content-Type: application/json" \
#    -d '{}' \
#    http://localhost:9001/clients 2>&1 \
#    | tee -a BENCHMARKS.md

cat >> BENCHMARKS.md << EOF
\`\`\`

### Listing OAuth 2.0 Clients

\`\`\`
EOF

hey -n $numReqs -c $numParallel -m GET \
    http://localhost:9001/clients 2>&1 \
    | tee -a BENCHMARKS.md

cat >> BENCHMARKS.md << EOF
\`\`\`

### Fetching a specific OAuth 2.0 Client

\`\`\`
EOF

hey -n $numReqs -c $numParallel -m GET \
    http://localhost:9001/clients/$clientId 2>&1 \
    | tee -a BENCHMARKS.md

cat >> BENCHMARKS.md << EOF
\`\`\`
EOF