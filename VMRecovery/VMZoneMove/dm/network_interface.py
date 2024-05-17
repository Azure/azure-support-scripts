from dataclasses import dataclass
from dataclasses_json import dataclass_json
from typing import List
from dm.network_interface_ip_configuration import NetworkInterfaceIPConfiguration


@dataclass_json
@dataclass
class NetworkInterface:
    id: str
    ip_configurations: List[NetworkInterfaceIPConfiguration]

    def __init__(self, id: str, ip_configurations: List[NetworkInterfaceIPConfiguration] = None):
        self.id = id
        if ip_configurations is None:
            self.ip_configurations: List[NetworkInterfaceIPConfiguration] = []
        else:
            self.ip_configurations = ip_configurations
