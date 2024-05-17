import os
import uuid
from dataclasses import dataclass
from typing import List

from dataclasses_json import dataclass_json
from dm.data_disk import DataDisk
from dm.network_profile import NetworkProfile
from dm.vm import VM


@dataclass_json
@dataclass
class FailoverState:
    data_disks: List[DataDisk]
    network_profile: NetworkProfile
    id: str

    def __init__(self, data_disks: List[DataDisk], network_profile: NetworkProfile, id: str):
        self.data_disks = data_disks
        self.network_profile = network_profile
        self.id = id

    @classmethod
    def init_from_vm(cls, vm: VM):
        return FailoverState(vm.data_disks, vm.network_profile, uuid.uuid4())

    @classmethod
    def is_state_exists(cls, id: str):
        return os.path.exists(FailoverState._get_path(id))

    @classmethod
    def scan_failover_state(cls, id: str):
        f = open(FailoverState._get_path(id), "r")
        string = f.read()

        return FailoverState.from_json(string)

    def commit(self):
        string = self.to_json()

        f = open(FailoverState._get_path(self.id), "x")
        f.write(string)
        f.close()

    @classmethod
    def _get_path(cls, id: str):
        return "failover state store/{}".format(id)
