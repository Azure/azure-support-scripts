from dataclasses import dataclass
from dataclasses_json import dataclass_json


@dataclass_json
@dataclass
class DataDisk:
    id: str

    def __init__(self, id: str):
        self.id = id

    def get_name(self) -> str: pass
