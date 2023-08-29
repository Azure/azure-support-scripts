# Multi-IP automatic configuration failing in Linux SUSE

## Description

* SUSE handles the automatic configuration of [Multi IP addresses using cloud-netconfig-azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/virtual-network-multiple-ip-addresses-portal#suse-linux-enterprise-and-opensuse) at Linux OS level.
* That plugin/script is currently failing in several regions, because of issues with one of the API URIs used by this plugin. 

## Mitigation steps

### Option 1

Do a redeployment to move the impacted virtual machine to a different host, and check if you are able to get the secondary IP assigned, given not all the Azure hosts are impacted. If this doesn't work, you could try a couple more of redeployments or follow the instructions in [Option 2](#option2)

### <a id="option2"></a>Option 2

The automatic configuration of the secondary IPs in SUSE VMs is currently failing in several Azure regions. While this issue is investigated and resolved, the secondary IP addresses can be configured manually.

1. You can validate the secondary IP address(es) have been assigned to this VM by IMDS using the following `curl` command. This is very important, as the communication will not be allowed out of the VMs if the IP addresses are not registered:

```bash
# curl -s -H Metadata:true --noproxy "*" http://169.254.169.254/metadata/instance/network/interface/?api-version=2021-02-01 | python3 -m json.tool
[
    {
        "ipv4": {
            "ipAddress": [
                {
                    "privateIpAddress": "10.0.0.10",
                    "publicIpAddress": "x.x.x.168"
                },
                {
                    "privateIpAddress": "10.0.0.15",
                    "publicIpAddress": ""
                }
            ],
            "subnet": [
                {
                    "address": "10.0.0.0",
                    "prefix": "24"
                }
            ]
        },
        "ipv6": {
            "ipAddress": []
        },
        "macAddress": "0022485BD42D"
    }
]
```

2. Modify the `/etc/sysconfig/network/ifcfg-eth0` file. 

```bash
sudo vi /etc/sysconfig/network/ifcfg-eth0
```

3. Set `CLOUD_NETCONFIG_MANAGE` to `no` and add the corresponding secondary IP address(es) at the end of the file as shown next:

```bash
CLOUD_NETCONFIG_MANAGE='no'
IPADDR2='10.0.0.15/24'
```

> [!NOTE]:
> Replace `10.0.0.15/24` with the corresponding secondary IP address and netmask bit. If you need to add more than a single secondary IP address to the same NIC, add extra lines increasing the corresponding index: `IPADDR3`, `IPADDR4`, and so on, and so forth.

4. Restart the network service to apply the changes:

```bash
sudo systemctl restart wicked
```

5. Validate the secondary IP(s) are configured at OS level:

```bash
ip address
```

6. You can also ping the corresponding IP address from another VM in the same VNET to test the communication is properly working.
