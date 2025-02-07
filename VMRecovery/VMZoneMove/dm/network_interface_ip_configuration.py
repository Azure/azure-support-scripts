from dataclasses import dataclass
from dataclasses_json import dataclass_json


@dataclass_json
@dataclass
class NetworkInterfaceIPConfiguration:
    name: str
    public_ip_address_id: str

    def __init__(self, name: str, public_ip_address_id: str = None):
        self.name = name
        self.public_ip_address_id = public_ip_address_id
