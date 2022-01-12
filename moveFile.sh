
export ARM_SUBSCRIPTION_ID="63c2f8f9-a3f8-4cbf-aaeb-341fc75caaa3"
export ARM_TENANT_ID="617e0530-4dad-4d11-befa-afcb00e44e79"
export ARM_CLIENT_ID="797bed90-8b53-415e-8b03-b684f54686bc"
export ARM_CLIENT_SECRET="ZIh6lMEl2VbiihD87diPM6AvzTU~UdZQ9Q"
export MANAGEMENT_RESOURCE_ENDPOINT="https://management.core.windows.net/" # This is Fixed value (DO NOT CHANGE)
export AZURE_DATABRICKS_APP_ID="2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" # This is Fixed value (DO NOT CHANGE)
export RESOURCE_GROUP="test-rg"
export LOCATION="eastus"
export DATABRICKS_WORKSPACE="Gubonbz25szmlzx"
export DATABRICKS_CLUSTER_NAME="test-cluster-01"
export DATABRICKS_SPARK_VERSION="7.3.x-scala2.12"
export DATABRICKS_NODE_TYPE="Standard_D3_v2"
export DATABRICKS_NUM_WORKERS=3 # Need to be number
export DATABRICKS_SPARK_CONF='{"spark.speculation":"true","spark.databricks.delta.preview.enabled":"true"}' # Needs to be valid JSON
export DATABRICKS_AUTO_TERMINATE_MINUTES=60 # Need to be a number


echo "Logging in using Azure service priciple"
az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
az account set -s  $ARM_SUBSCRIPTION_ID



if [[ $(az group exists --resource-group $RESOURCE_GROUP) = "false" ]]; then
echo "Resource Group does not exists, so creating.."
az group create --name $RESOURCE_GROUP --location $LOCATION
fi


az config set extension.use_dynamic_install=yes_without_prompt



$(az databricks workspace list | jq .[].name | grep -w $DATABRICKS_WORKSPACE) = $DATABRICKS_WORKSPACE


wsId=$(az resource show --resource-type Microsoft.Databricks/workspaces -g $RESOURCE_GROUP -n "$DATABRICKS_WORKSPACE" --query id -o tsv)
echo "Workspce ID: $wsId"


workspaceUrl=$(az resource show --resource-type Microsoft.Databricks/workspaces -g "$RESOURCE_GROUP" -n "$DATABRICKS_WORKSPACE" --query properties.workspaceUrl --output tsv)
echo "Workspce URL: $workspaceUrl"


token_response=$(az account get-access-token --resource $AZURE_DATABRICKS_APP_ID)
echo $token_response

token=$(jq .accessToken -r <<< "$token_response")
echo "Token: $token"



az_mgmt_resource_endpoint=$(curl -X GET -H 'Content-Type: application/x-www-form-urlencoded' \
-d 'grant_type=client_credentials&client_id='$ARM_CLIENT_ID'&resource='$MANAGEMENT_RESOURCE_ENDPOINT'&client_secret='$ARM_CLIENT_SECRET \
https://login.microsoftonline.com/$ARM_TENANT_ID/oauth2/token)

mgmt_access_token=$(jq .access_token -r <<< "$az_mgmt_resource_endpoint" )
echo "Management Access Token: $mgmt_access_token"



pat_token_response=$(curl -X POST \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token: $mgmt_access_token" \
    -H "X-Databricks-Azure-Workspace-Resource-Id: $wsId" \
    -d '{"lifetime_seconds": 300,"comment": "this is an example token"}' \
    https://$workspaceUrl/api/2.0/token/create
)



pat_token=$(jq .token_value -r <<< "$pat_token_response")
echo $pat_token


# Create Cluster config from variables 
JSON_STRING=$( jq -n -c \
                --arg cn "$DATABRICKS_CLUSTER_NAME" \
                --arg sv "$DATABRICKS_SPARK_VERSION" \
                --arg nt "$DATABRICKS_NODE_TYPE" \
                --arg nw "$DATABRICKS_NUM_WORKERS" \
                --arg sc "$DATABRICKS_SPARK_CONF" \
                --arg at "$DATABRICKS_AUTO_TERMINATE_MINUTES" \
                '{cluster_name: $cn,
                spark_version: $sv,
                node_type_id: $nt,
                num_workers: ($nw|tonumber),
                autotermination_minutes: ($at|tonumber),
                spark_conf: ($sc|fromjson)}' )



cluster_id_response=$(curl -X POST \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token: $mgmt_access_token" \
    -H "X-Databricks-Azure-Workspace-Resource-Id: $wsId" \
    -d $JSON_STRING \
    https://$workspaceUrl/api/2.0/clusters/create)


# Print cluster_id
cluster_id=$(jq .cluster_id -r <<< "$cluster_id_response")
echo "Cluster id: $cluster_id"
