from cloud.cloud import ICloud, FailoverPossibilityCode
from cloud.cloud_factory import CloudFactory
from dm.failover_state import FailoverState
from dm.vm import VM
from utils import get_confirmation


class FailoverService:
    old_vm_name: str
    new_vm_name: str
    resource_group_name: str
    subscription_id: str
    new_zone: int
    admin_password: str
    cloud: ICloud
    should_commit_failover_state: bool

    def __init__(self,
                 subscription_id: str,
                 resource_group_name: str,
                 old_vm_name: str,
                 new_vm_name: str,
                 new_zone: str,
                 admin_password: str,
                 cloud_factory: CloudFactory):
        self.subscription_id = subscription_id
        self.resource_group_name = resource_group_name
        self.old_vm_name = old_vm_name
        self.new_vm_name = new_vm_name
        self.new_zone = new_zone
        self.admin_password = admin_password
        self.cloud = cloud_factory.get_cloud()
        self.should_commit_failover_state = False

    def execute_failover(self):
        failover_possibility = self.cloud.evaluate_failover_possibility(self.resource_group_name, self.old_vm_name, self.admin_password)
        reasons = ""
        for i, reason in enumerate(failover_possibility.reasons, start=1):
            reasons += "{}. {}\n".format(i, reason)

        if failover_possibility.code == FailoverPossibilityCode.NOGO:
            print("Failover cannot be done for the following reasons:\n {}".format(reasons))
            return

        if failover_possibility.code == FailoverPossibilityCode.IDOUBT:
            conf = get_confirmation("There is a chance that the failover operation does not succeed due to the following reasons." +
                             "\n{}".format(reasons) +
                             "\nDo you still wish to go ahead (y/n)? ")

            if not conf:
                return

        old_vm: VM = self.cloud.get_vm(self.resource_group_name, self.old_vm_name)

        if FailoverState.is_state_exists(old_vm.failover_tracker):
            failover_state = FailoverState.scan_failover_state(old_vm.failover_tracker)
        else:
            self.should_commit_failover_state = True
            failover_state = FailoverState.init_from_vm(old_vm)

        if self.should_commit_failover_state:
            print("Committing failover state")
            self.cloud.commit_failover_state(self.resource_group_name, self.old_vm_name, failover_state)
        print("Failing over VM: {}".format(old_vm.id))
        self.cloud.failover_vm(self.resource_group_name, self.old_vm_name, self.new_vm_name, self.admin_password,
                               self.new_zone, failover_state)
