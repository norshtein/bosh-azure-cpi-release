# Deploy Cloud Foundry with Traffic Manager

[Azure Traffic Manager](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-overview) allows you to control the distribution of user traffic for service endpoints in different datacenters. If you have multiple Cloud Foundry deployments in different locations, you can use traffic manager to route traffic to the location that is 'closest' to you.

1. Deploy your multiple Cloud Foundry deployments. In each deployment, you can use the `xip.io` domain as the system domain.

    1. If you use Azure Load Balancer, please refer to the [doc](../../get-started/via-arm-templates/deploy-bosh-via-arm-templates.md). You need to specify the DNS name label for the public IP of the Load Balancer.

    1. If you use Azure Application Gateway, please refer to the [doc](../application-gateway/).

1. [Create a traffic manager profile.](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-create-profile)

    1. Select `Performance` as the [traffic-routing method](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-routing-methods#a-name--performanceaperformance-traffic-routing-method).

    1. Select `Azure endpoints` as the [endpoint type](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-endpoint-types#azure-endpoints) and `PublicIPAddress` as the target resource type.

    1. Select `TCP` as the protocal and `80` as the port in the [endpoint monitor settings](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-monitoring#configure-endpoint-monitoring).

1. You need a real Internet domain (e.g. `contoso.com`).

1. Push a sample application in your each Cloud Foundry deployment.

    1. Login your Cloud Foundry.

    1. Download a demo application

        ```
        git clone https://github.com/bingosummer/2048
        ```

    1. Add a new route `game-2048.contoso.com` to the application manifest.

        ```
        ---
        applications:
        - name: game-2048
          buildpack: staticfile_buildpack
          routes:
          - route: game-2048.contoso.com
        ```

    1. Push the application.

1. [Point the your application route `game-2048.contoso.com` to the Azure traffic manager domain](https://docs.microsoft.com/en-us/azure/traffic-manager/traffic-manager-point-internet-domain).
