from copy import deepcopy
from typing import Iterator, Tuple

from aim.storage.hashing import hash_auto
from aim.storage.types import AimObject, AimObjectKey


class Context:
    __slots__ = ['_context', '_hash']

    def __init__(
        self,
        context: AimObject
    ):
        self._context = deepcopy(context)
        self._hash = None

    @property
    def idx(self) -> int:
        return hash(self)

    def __repr__(self) -> str:
        return f'<Context#{hash(self)} {self._context}>'

    def to_dict(self) -> AimObject:
        return self._context

    def __iter__(self) -> Iterator[AimObjectKey]:
        return iter(self._context)

    def __len__(self) -> int:
        return len(self._context)

    def __getitem__(self, idx) -> AimObject:
        return self._context[idx]

    def _calc_hash(self) -> int:
        return hash_auto(self._context)

    def __hash__(self) -> int:
        if self._hash is None:
            self._hash = self._calc_hash()
        return self._hash

    def __eq__(self, other: 'Context') -> bool:
        if hash(self) != hash(other):
            return False
        return self._context == other._context


class Metric:
    __slots__ = ['_name', '_context', '_hash', '_metric_hash']

    def __init__(
        self,
        name: str,
        context: Context
    ):
        self._name = name
        self._context = context
        self._hash = None
        self._metric_hash = None

    @property
    def selector(self) -> Tuple[int, str]:
        return self._context.idx, self._name

    @property
    def context_idx(self) -> int:
        return self._context.idx

    @property
    def metric_idx(self) -> int:
        if self._metric_hash is None:
            self._metric_hash = hash_auto(self.name)
        return self._metric_hash

    def _calc_hash(self) -> int:
        return hash_auto((self.name, self.context))

    def __hash__(self) -> int:
        if self._hash is None:
            self._hash = self._calc_hash()
        return self._hash

    def __eq__(self, other: 'Metric') -> bool:
        if hash(self) != hash(other):
            return False
        return (self._name == other.name and self._context == other._context)
