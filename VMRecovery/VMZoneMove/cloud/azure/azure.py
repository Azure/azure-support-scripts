from azure.identity import InteractiveBrowserCredential
from azure.mgmt.compute.v2023_09_01.models import (
    VirtualMachine,
    StorageProfile,
    OSDisk,
    ManagedDiskParameters,
    NetworkProfile,
    DataDisk as AzureDataDisk,
    NetworkInterfaceReference as AzureNetworkInterfaceReference
)
from azure.mgmt.network.models import (
    NetworkInterface as AzureNetworkInterface,
    NetworkInterfaceIPConfiguration as AzureNetworkInterfaceIPConfiguration,
    PublicIPAddress as AzurePublicIPAddress
)
from cloud.azure.compute_resource_provider import ComputeResourceProvider
from cloud.azure.network_resource_provider import NetworkResourceProvider
from cloud.cloud import ICloud, FailoverPossibility, FailoverPossibilityCode
from dm.data_disk import DataDisk
from dm.failover_state import FailoverState
from dm.network_interface import NetworkInterface
from dm.network_interface_ip_configuration import NetworkInterfaceIPConfiguration
from dm.vm import VM


class Azure(ICloud):
    subscription_id: str
    crp = ComputeResourceProvider
    nrp = NetworkResourceProvider
    credentials: InteractiveBrowserCredential
    api_versions: dict[str, str]

    def __init__(self, subscription_id):
        self.api_versions = {
            'crp': '2023-09-01',
            'nrp': '2023-09-01'
        }

        self.subscription_id = subscription_id
        self.credentials = InteractiveBrowserCredential()
        self.crp = ComputeResourceProvider(subscription_id, self.credentials, self.api_versions['crp'])
        self.nrp = NetworkResourceProvider(subscription_id, self.credentials, self.api_versions['nrp'])

    def get_vm(self, resource_group_name: str, vm_name: str) -> VM:
        azure_vm: VirtualMachine = self.crp.get_vm(resource_group_name, vm_name)
        failover_tracker = azure_vm.vm_id
        #if azure_vm.tags is not None and 'failover_tracker' in azure_vm.tags and len(azure_vm.tags['failover_tracker']) > 0:
            #failover_tracker = azure_vm.tags['failover_tracker']
        vm = VM(azure_vm.id, failover_tracker)

        # data disks
        for azure_data_disk in azure_vm.storage_profile.data_disks:
            if azure_data_disk.managed_disk is not None:
                vm.data_disks.append(DataDisk(azure_data_disk.managed_disk.id))

        i = 0
        # network interfaces
        for azure_network_interface_reference in azure_vm.network_profile.network_interfaces:
            i += 1
            network_interface = NetworkInterface(azure_network_interface_reference.id)
            old_nic_resource_group_name = NetworkResourceProvider.get_network_interface_resource_group_name(
                azure_network_interface_reference.id)
            old_nic_name = NetworkResourceProvider.get_network_interface_name(azure_network_interface_reference.id)
            azure_network_interface = self.nrp.get_nic(old_nic_resource_group_name, old_nic_name)
            for azure_ip_config in azure_network_interface.ip_configurations:
                network_interface.ip_configurations.append(NetworkInterfaceIPConfiguration(
                    azure_ip_config.name,
                    None if azure_ip_config.public_ip_address is None else azure_ip_config.public_ip_address.id
                ))
            vm.network_profile.network_interfaces.append(network_interface)

        return vm

    def commit_failover_state(self, resource_group_name: str, vm_name: str, failover_state: FailoverState):
        failover_state.commit()

    def evaluate_failover_possibility(self, resource_group_name: str, vm_name: str, admin_password: str):
        code = FailoverPossibilityCode.NODOUBT
        reasons = []
        azure_vm: VirtualMachine = self.crp.get_vm(resource_group_name, vm_name)
        account_types_guarantee_success = ["PREMIUM_ZRS", "STANDARDSSD_ZRS"]
        account_types_guarantee_success_str = ",".join(account_types_guarantee_success)

        if azure_vm.zones is None:
            code = FailoverPossibilityCode.NOGO
            reasons.append("VM {} does not have any zone. Failover cannot be applied.".format(azure_vm.name))
            return FailoverPossibility(code, reasons)

        if azure_vm.storage_profile.os_disk.os_type.upper() == "WINDOWS" and (admin_password is None or admin_password == ""):
            code = FailoverPossibilityCode.NOGO
            reasons.append("VM {} is a windows VM. Admin password needs to be provided for failover to be applied")
            return FailoverPossibility(code, reasons)

        for disk in azure_vm.storage_profile.data_disks:
            if disk.managed_disk.storage_account_type.upper() not in account_types_guarantee_success:
                reasons.append("Detach of disk {} with account type {} may or may not work."
                               "Account types that guarantee disk detach success during zone down scenario: {}"
                               .format(disk.name, disk.managed_disk.storage_account_type, account_types_guarantee_success_str))
                code = FailoverPossibilityCode.IDOUBT

        for azure_nic_reference in azure_vm.network_profile.network_interfaces:
            nic_resource_group_name = NetworkResourceProvider.get_network_interface_resource_group_name(azure_nic_reference.id)
            nic_name = NetworkResourceProvider.get_network_interface_name(azure_nic_reference.id)
            azure_nic = self.nrp.get_nic(nic_resource_group_name, nic_name)

            for azure_ip_config in azure_nic.ip_configurations:
                if azure_ip_config.public_ip_address is not None:
                    code = FailoverPossibilityCode.IDOUBT
                    reasons.append("The public IP {} cannot be transferred to a different zone. Failover operation will ignore it".format(azure_ip_config.public_ip_address.id))

        return FailoverPossibility(code, reasons)

    def failover_vm(self, resource_group_name: str, old_vm_name: str, new_vm_name: str, admin_password: str,
                    new_vm_zone: int, failover_state: FailoverState):
        azure_old_vm: VirtualMachine = self.crp.get_vm(resource_group_name, old_vm_name)
        location = azure_old_vm.location
        azure_new_vm: VirtualMachine = VirtualMachine(
            location=azure_old_vm.location,
            zones=[new_vm_zone],
            hardware_profile=azure_old_vm.hardware_profile
        )
        azure_new_vm.name = new_vm_name

        old_vm_update_is_required = False

        # storage profile
        Azure._copy_storage_profile(azure_old_vm, azure_new_vm, admin_password, failover_state)
        # mark currently attached disks for force detach
        for azure_data_disk in azure_old_vm.storage_profile.data_disks:
            azure_data_disk.to_be_detached = True
            azure_data_disk.detach_option = 'ForceDetach'
            old_vm_update_is_required = True

        # network profile
        azure_new_vm.network_profile = NetworkProfile()
        azure_new_vm.network_profile.network_interfaces = []
        # get old nic information
        old_nic_references = Azure._get_old_nic_references(azure_old_vm)

        azure_old_nics = self.nrp.get_nics(old_nic_references)
        for old_nic in failover_state.network_profile.network_interfaces:
            azure_old_nic = azure_old_nics[old_nic.id]
            azure_new_nic = Azure._copy_network_interface(azure_old_nic, location, failover_state)
            old_nic_resource_group_name = NetworkResourceProvider.get_network_interface_resource_group_name(old_nic.id)
            old_nic_update_is_required = Azure._detach_public_ip_if_present(azure_old_nic)
            if old_nic_update_is_required:
               self.nrp.put_nic(old_nic_resource_group_name, azure_old_nic.name, azure_old_nic)
            azure_new_nic = self.nrp.put_nic(old_nic_resource_group_name, azure_new_nic.name, azure_new_nic)
            azure_new_vm.network_profile.network_interfaces.append(AzureNetworkInterfaceReference(id=azure_new_nic.id))

        if old_vm_update_is_required:
            print(azure_old_vm.serialize())
            self.crp.put_vm(resource_group_name, azure_old_vm)

        self.crp.put_vm(resource_group_name, azure_new_vm)

    @classmethod
    def _copy_storage_profile(cls, azure_old_vm: VirtualMachine, azure_new_vm: VirtualMachine,
                              admin_password: str, failover_state: FailoverState):
        assert azure_old_vm is not None
        assert azure_new_vm is not None
        assert admin_password is not None

        azure_new_vm.storage_profile = StorageProfile()
        azure_new_vm.storage_profile.disk_controller_type = azure_old_vm.storage_profile.disk_controller_type
        # copy image reference
        if azure_old_vm.storage_profile.image_reference is not None:
            azure_new_vm.storage_profile.image_reference = azure_old_vm.storage_profile.image_reference
            azure_new_vm.storage_profile.os_disk = OSDisk(create_option='FromImage')
            azure_new_vm.os_profile = azure_old_vm.os_profile
            azure_new_vm.os_profile.admin_password = admin_password
        # TODO: throw error if image reference is not present

        azure_new_vm.storage_profile.data_disks = []
        lun = 0
        for failover_disk in failover_state.data_disks:
            data_disk = AzureDataDisk(create_option='Attach', lun=lun)
            data_disk.managed_disk = ManagedDiskParameters()
            data_disk.managed_disk.id = failover_disk.id
            data_disk.create_option = 'Attach'
            azure_new_vm.storage_profile.data_disks.append(data_disk)
            lun += 1

    @classmethod
    def _get_old_nic_references(cls, azure_old_vm: VirtualMachine):
        old_nic_references = []
        for azure_network_interface_reference in azure_old_vm.network_profile.network_interfaces:
            old_nic_id = azure_network_interface_reference.id
            old_nic_resource_group_name = NetworkResourceProvider.get_network_interface_resource_group_name(old_nic_id)
            old_nic_name = NetworkResourceProvider.get_network_interface_name(old_nic_id)
            old_nic_references.append((old_nic_resource_group_name, old_nic_name))

        return old_nic_references

    @classmethod
    def _get_subnet_map(cls, network_interface: AzureNetworkInterface):
        subnet_map = {}
        for azure_ip_config in network_interface.ip_configurations:
            subnet_map[azure_ip_config.name] = azure_ip_config.subnet

        return subnet_map

    @classmethod
    def _detach_public_ip_if_present(cls, network_interface: AzureNetworkInterface):
        nic_update_is_required = False

        for azure_ip_config in network_interface.ip_configurations:
            # detach public ip address from old nic
            if azure_ip_config.public_ip_address is not None:
                azure_ip_config.public_ip_address = None
                nic_update_is_required = True

        return nic_update_is_required

    @classmethod
    def _copy_nic_ip_configurations(cls, azure_old_nic: AzureNetworkInterface, subnet_map: dict[str, str],
                                    failover_state: FailoverState):
        assert azure_old_nic is not None
        assert len(azure_old_nic.ip_configurations) == len(subnet_map)

        nic_failover_state_representation = None
        for network_interface in failover_state.network_profile.network_interfaces:
            if azure_old_nic.id == network_interface.id:
                nic_failover_state_representation = network_interface
                break
        assert nic_failover_state_representation is not None

        public_ip_map = {}
        # for ip_config in nic_failover_state_representation.ip_configurations:
        #     if ip_config.public_ip_address_id is not None:
        #         public_ip_map[ip_config.name] = ip_config.public_ip_address_id

        new_nic_ip_configurations = []
        for ip_config in azure_old_nic.ip_configurations:
            assert ip_config.name is not None
            assert ip_config.name in subnet_map

            new_nic_ip_configuration = AzureNetworkInterfaceIPConfiguration(
                name=ip_config.name + "-copy",
                subnet=subnet_map[ip_config.name]
            )
            if ip_config.name in public_ip_map:
                new_nic_ip_configuration.public_ip_address = AzurePublicIPAddress(id=public_ip_map[ip_config.name])
            new_nic_ip_configurations.append(new_nic_ip_configuration)

        return new_nic_ip_configurations

    @classmethod
    def _copy_network_interface(cls, azure_old_nic: AzureNetworkInterface,
                                location: str, failover_state: FailoverState):
        subnet_map = Azure._get_subnet_map(azure_old_nic)
        new_nic_ip_configurations = Azure._copy_nic_ip_configurations(azure_old_nic, subnet_map, failover_state)
        azure_new_nic = AzureNetworkInterface(
            location=location,
            ip_configurations=new_nic_ip_configurations
        )
        azure_new_nic.name = azure_old_nic.name + "-copy"
        azure_new_nic.primary = azure_old_nic.primary

        return azure_new_nic
