from dm.data_disk import DataDisk
from dm.network_profile import NetworkProfile


class VM:
    id: str
    data_disks: list[DataDisk]
    network_profile: NetworkProfile
    failover_tracker: str

    def __init__(self, id: str, failover_tracker: str):
        self.id = id
        self.failover_tracker = failover_tracker
        self.data_disks = []
        self.network_profile = NetworkProfile()

    def get_name(self) -> str: pass
