from abc import abstractmethod
from dm.failover_state import FailoverState
from enum import Enum


class FailoverPossibilityCode(Enum):
    NODOUBT = 0,
    IDOUBT = 1,
    NOGO=2


class FailoverPossibility:
    code: FailoverPossibilityCode
    reasons: list[str]

    def __init__(self, code: FailoverPossibilityCode, reasons: list[str]):
        self.code = code
        self.reasons = reasons


class ICloud:
    def __init__(self, subscription_id: str): pass

    @abstractmethod
    def get_vm(self, resource_group_name: str, vm_name: str): pass

    @abstractmethod
    def commit_failover_state(self, resource_group_name: str, vm_name: str, failover_state: FailoverState): pass

    @abstractmethod
    def evaluate_failover_possibility(self, resource_group_name: str, vm_name: str) -> FailoverPossibility: pass

    @abstractmethod
    def failover_vm(self, old_vm_name: str, new_vm_name: str, admin_password: str, new_vm_zone: int,
                    failover_state: FailoverState): pass
