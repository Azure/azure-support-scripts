from azure.identity import InteractiveBrowserCredential
from azure.mgmt.compute import ComputeManagementClient
# how to make this dynamic?
from azure.mgmt.compute.v2023_09_01.models import VirtualMachine


class ComputeResourceProvider:
    subscription_id: str
    compute_client: ComputeManagementClient

    def __init__(self, subscription_id: str, credentials: InteractiveBrowserCredential, api_version: str):
        self.subscription_id = subscription_id
        self.compute_client = ComputeManagementClient(credentials, subscription_id, api_version=api_version)

    def get_vm(self, resource_group_name: str, vm_name: str) -> VirtualMachine:
        print("GETting VM: /subscriptions/{}/resourceGroups/{}/providers/Microsoft.Compute/VirtualMachines/{}"
              .format(self.subscription_id, resource_group_name, vm_name))
        return self.compute_client.virtual_machines.get(resource_group_name, vm_name)

    def put_vm(self, resource_group_name: str, vm: VirtualMachine):
        print("PUTting VM: {}".format(vm))
        poller = self.compute_client.virtual_machines.begin_create_or_update(resource_group_name, vm.name, vm)
        poller.wait(300000)
        print("VM PUT Done")
