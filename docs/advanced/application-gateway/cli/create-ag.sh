set -e

while true; do
  read -p "Input your location (e.g. East Asia): " location
  if [ -z "$location" ]; then
    echo "Location can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input your resource group name: " rgName
  if [ -z "$rgName" ]; then
    echo "Resource group name can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input your application gateway name: " appgwName
  if [ -z "$appgwName" ]; then
    echo "Application gateway name can't be null"
  else
    break;
  fi
done

echo "Will create the application gateway" $appgwName "in your resrouce group" $rgName

read -p "Input your virtual network name [boshvnet-crp]: " vnetName
if [ -z "$vnetName" ]; then
  vnetName="boshvnet-crp"
fi

read -p "Input your subnet name for the application gateway [ApplicationGateway]: " subnetName
if [ -z "$subnetName" ]; then
  subnetName="ApplicationGateway"
fi

read -p "Input the subnet address prefix [10.0.1.0/24]: " subnetAddressPrefix
if [ -z "$subnetAddressPrefix" ]; then
  subnetAddressPrefix="10.0.1.0/24"
fi

read -p "Input your public IP name[publicIP01]: " publicipName
if [ -z "$publicipName" ]; then
  publicipName="publicIP01"
fi

routerNumber=2

while true; do
  read -p "Input your system domain[REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io]: " systemDomain
  if [ -z "$systemDomain" ]; then
    echo "System domain can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input the path of the certificate: " certPath
  if [ ! -f "$certPath" ]; then
    echo "Given path is not a valid file"
  else
    break;
  fi
done

while true; do
  read -p "Input the password of the certificate: " passwd
  if [ -z "$passwd" ]; then
    echo "password can't be null"
  else
    break;
  fi
done

# Uncomment it if the application gateway (AG) exists
# echo "Uncomment it if the application gateway exists"
# az network application-gateway delete --resource-group $rgName --name $appgwName --quiet

# Create public-ip
echo "Creating public IP address for front end configuration"
az network public-ip create --resource-group $rgName --name $publicipName --location $location --allocation-method Dynamic

# Create subnet for AG
echo "Creating subnet for application gateway"
az network vnet subnet create --resource-group $rgName --vnet-name $vnetName --name $subnetName --address-prefix $subnetAddressPrefix

# Create AG
az network application-gateway create --resource-group $rgName --name $appgwName --location $location --vnet-name $vnetName --subnet $subnetName --http-settings-protocol http --http-settings-port 80 --http-settings-cookie-based-affinity Disabled --frontend-port 80 --public-ip-address $publicipName --routing-rule-type Basic --sku Standard_Small --capacity $routerNumber

# Create probe
echo "Configuring a probe"
hostName="api."$systemDomain
az network application-gateway probe create --resource-group $rgName --gateway-name $appgwName --name 'CustomProbe' --protocol Http --host $hostName --path '/' --interval 60 --timeout 60 --threshold 3

# Use custom probe in http settings
az network application-gateway http-settings update --resource-group $rgName --gateway-name $appgwName --name 'appGatewayBackendHttpSettings' --probe 'CustomProbe'

# Create HTTPS frontend-port
az network application-gateway frontend-port create --resource-group $rgName --gateway-name $appgwName --name frontendporthttps --port 443
az network application-gateway frontend-port create --resource-group $rgName --gateway-name $appgwName --name frontendportlogs --port 4443

# Create AG ssl-cert
az network application-gateway ssl-cert create --resource-group $rgName --gateway-name $appgwName --name 'cert01' --cert-file $certPath --cert-password $passwd

# Create the listener and rule for frontend point 443
az network application-gateway http-listener create --resource-group $rgName --gateway-name $appgwName --name 'appGatewayHttpsListener' --frontend-port frontendporthttps --ssl-cert 'cert01'
az network application-gateway rule create --resource-group $rgName --gateway-name $appgwName --name 'HTTPSrule' --rule-type Basic --http-listener 'appGatewayHttpsListener' --address-pool 'appGatewayBackendPool'

# Create the listener and rule for frontend point 4443
az network application-gateway http-listener create --resource-group $rgName --gateway-name $appgwName --name 'appGatewayWebSocketListener' --frontend-port frontendportlogs --ssl-cert 'cert01'
az network application-gateway rule create --resource-group $rgName --gateway-name $appgwName --name 'WebSocketsrule' --rule-type Basic --http-listener 'appGatewayWebSocketListener' --address-pool 'appGatewayBackendPool'

