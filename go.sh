#!/bin/bash

CONNECTOR_JAR=~/prj/gaiax/gaia-x-4-roms/tp3/roms-edc/launchers/connector/build/libs/connector.jar
EDC_PROVIDER_URL=http://localhost:18183
EDC_CONSUMER_URL=http://localhost:28183

echo
echo "------------------------------------------------------------------------------"
echo "start EDC-Connectors"

cd provider
gnome-terminal --tab --title="Provider" --geometry=150x24+50+50 -- bash \
  -c "java \
  -Dedc.keystore=resources/connector/certs/cert.pfx \
  -Dedc.keystore.password=123456 \
  -Dedc.vault=resources/connector/configuration/connector-vault.properties \
  -Dedc.fs.config=resources/connector/configuration/connector-configuration.properties \
  -jar ${CONNECTOR_JAR}"

cd ../consumer
gnome-terminal --tab --title="Consumer" --geometry=150x24+50+800 -- bash \
  -c "java \
  -Dedc.keystore=resources/connector/certs/cert.pfx \
  -Dedc.keystore.password=123456 \
  -Dedc.vault=resources/connector/configuration/connector-vault.properties \
  -Dedc.fs.config=resources/connector/configuration/connector-configuration.properties \
  -jar ${CONNECTOR_JAR}"

cd ..

echo
echo "------------------------------------------------------------------------------"
read -p "press Enter to initialize provider"

cd messages

curl -H 'Content-Type: application/json' \
     -d @0-dataplane.json \
     -X POST "${EDC_PROVIDER_URL}/management/v2/dataplanes" \
     -s | jq .
echo

curl -H 'Content-Type: application/json' \
     -d @1-asset.json \
     -X POST "${EDC_PROVIDER_URL}/management/v3/assets" \
     -s | jq .

curl -H 'Content-Type: application/json' \
     -d @2-policy-definition.json \
     -X POST "${EDC_PROVIDER_URL}/management/v2/policydefinitions" \
     -s | jq .

curl -H 'Content-Type: application/json' \
     -d @3-contract-definition.json \
     -X POST "${EDC_PROVIDER_URL}/management/v2/contractdefinitions" \
     -s | jq .
echo

echo
echo "------------------------------------------------------------------------------"
read -p "press Enter to initialize consumer"

POLICY_ID=$(curl -H 'Content-Type: application/json' \
     -d @4-get-dataset.json \
     -X POST "${EDC_CONSUMER_URL}/management/v2/catalog/dataset/request" \
     -s | jq -r '.["odrl:hasPolicy"]["@id"]')
echo "POLICY_ID: ${POLICY_ID}"

echo "replacing policy id in 5-negotiate-contract.json with the one from the previous response"
cat 5-negotiate-contract.json | jq --arg policyId "${POLICY_ID}" '.policy."@id" = $policyId' > negotiate-contract.json

echo "press Enter to continue"
read -n 1 -s   

CONTRACT_NEG_ID=$(curl -H 'Content-Type: application/json' \
     -d @negotiate-contract.json \
     -X POST "${EDC_CONSUMER_URL}/management/v2/contractnegotiations" \
     -s | jq -r '.["@id"]')
echo "Contract Negotiation ID: ${CONTRACT_NEG_ID}"
echo

echo "give the connectors time to finalize the negotiation"
echo "press Enter to continue"
read -n 1 -s   

echo "verify contract negotiation"
CON_AGGREEMENT_ID=$(curl "${EDC_CONSUMER_URL}/management/v2/contractnegotiations/${CONTRACT_NEG_ID}" -s | \
    jq -r '.["@id"]')
echo "Contract Agreement ID: ${CON_AGGREEMENT_ID}"
echo

echo "start the transfer"
jq --arg new_value ${CON_AGGREEMENT_ID} \
   '.contractId = $new_value' \
   6-transfer.json > transfer.json

TRANS_PROC_ID=$(curl -H 'Content-Type: application/json' \
     -d @transfer.json \
     -X POST "${EDC_CONSUMER_URL}/management/v2/transferprocesses" -s | \
     jq -r '.["@id"]')
echo "Transfer Process ID: ${TRANS_PROC_ID}"

curl "${EDC_CONSUMER_URL}/management/v2/transferprocesses/${TRANS_PROC_ID}" -s | jq
