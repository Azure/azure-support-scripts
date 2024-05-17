import argparse

from cloud.cloud_factory import CloudFactory
from service.failover_service import FailoverService
from utils import get_confirmation


def main():
    parser = argparse.ArgumentParser(description="Example program to handle VM information.")
    parser.add_argument("oldVMName", help="Name of the old virtual machine", type=str)
    parser.add_argument("newVMName", help="Name of the new virtual machine", type=str)
    parser.add_argument("subscriptionId", help="azure subscription ID", type=str)
    parser.add_argument("resourceGroupName", help="Name of the resource group", type=str)
    parser.add_argument("newZone", help="New availability zone", type=int)
    parser.add_argument("adminPassword", help="New VM admin password", type=str)

    args = parser.parse_args()
    old_vm_name = args.oldVMName
    new_vm_name = args.newVMName
    subscription_id = args.subscriptionId
    resource_group_name = args.resourceGroupName
    new_zone = args.newZone
    admin_password = args.adminPassword

    print(f"Old VM Name: {old_vm_name}")
    print(f"New VM Name: {new_vm_name}")
    print(f"Subscription ID: {subscription_id}")
    print(f"Resource Group Name: {resource_group_name}")
    print(f"New Zone: {new_zone}")

    if not get_confirmation():
        print("Exiting")
        return

    cloud_factory: CloudFactory = CloudFactory(subscription_id)
    failover_service: FailoverService = FailoverService(
        subscription_id=subscription_id,
        resource_group_name=resource_group_name,
        old_vm_name=old_vm_name,
        new_vm_name=new_vm_name,
        new_zone=new_zone,
        admin_password=admin_password,
        cloud_factory=cloud_factory
    )

    failover_service.execute_failover()


main()
