from cloud.azure.azure import Azure
from cloud.cloud import ICloud


class CloudFactory:
    subscription_id: str

    def __init__(self, subscription_id: str):
        self.subscription_id = subscription_id

    def get_cloud(self) -> ICloud:
        cloud = Azure(self.subscription_id)

        return cloud
