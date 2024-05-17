from azure.identity import InteractiveBrowserCredential
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.network.models import NetworkInterface


class NetworkResourceProvider:
    def __init__(self, subscription_id: str, credentials: InteractiveBrowserCredential, api_version: str):
        self.subscription_id = subscription_id
        self.network_client = NetworkManagementClient(credentials, subscription_id, api_version=api_version)

    def get_nic(self, resource_group_name: str, nic_name: str) -> NetworkInterface:
        return self.network_client.network_interfaces.get(resource_group_name, nic_name)

    def get_nics(self, identifiers: list[(str, str)]):
        result = {}
        for identifier in identifiers:
            id = NetworkResourceProvider.get_network_interface_id(self.subscription_id, identifier[0], identifier[1])
            if id in result:
                continue
            nic = self.get_nic(identifier[0], identifier[1])
            if nic.id != id:
                raise Exception("Invalid id! {} is not same as {}".format(nic.id, id))
            result[nic.id] = nic

        return result

    def put_nic(self, resource_group_name: str, nic_name: str, nic: NetworkInterface) -> NetworkInterface:
        print("PUTting NIC: {}".format(nic))
        poller = self.network_client.network_interfaces.begin_create_or_update(resource_group_name, nic_name, nic)
        poller.wait(10000)
        print("NIC PUT Done")

        return poller.result()

    @classmethod
    def get_network_interface_id(cls, subscription_id: str, resource_group_name: str, nic_name: str):
        return '/subscriptions/{}/resourceGroups/{}/providers/Microsoft.Network/networkInterfaces/{}'.format(
            subscription_id,
            resource_group_name,
            nic_name
        )

    @classmethod
    def get_network_interface_resource_group_name(cls, network_interface_id: str):
        parts = network_interface_id.split('/')
        resource_group_name = parts[4]

        return resource_group_name

    @classmethod
    def get_network_interface_name(cls, network_interface_id: str):
        parts = network_interface_id.split('/')

        return parts[-1]
