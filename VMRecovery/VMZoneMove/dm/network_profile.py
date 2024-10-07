from dataclasses import dataclass
from dataclasses_json import dataclass_json
from typing import List
from dm.network_interface import NetworkInterface


@dataclass_json
@dataclass
class NetworkProfile:
    network_interfaces: List[NetworkInterface]

    def __init__(self, network_interfaces: List[NetworkInterface] = None):
        if network_interfaces is None:
            self.network_interfaces: List[NetworkInterface] = []
        else:
            self.network_interfaces = network_interfaces