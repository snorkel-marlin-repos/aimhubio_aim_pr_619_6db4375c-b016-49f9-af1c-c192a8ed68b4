from aim.storage.encoding import encode as E_encode
from aim.storage.encoding import decode as E_decode
from aim.storage.encoding import encode_path as E_encode_path
from aim.storage.encoding.encoding_native cimport decode_path

from aim.storage.types import AimObject, AimObjectPath
from aim.storage.utils import ArrayFlag, ObjectFlag

from typing import Any, Iterator, List, Tuple, Union


def unfold_tree(
    obj: AimObject,
    *,
    path: Tuple[Union[int, str], ...] = (),
    unfold_array: bool = True,
    depth: int = None
) -> Iterator[Tuple[Tuple[Union[int, str], ...], Any]]:
    if depth == 0:
        yield path, obj
        return
    if depth is not None:
        depth -= 1

    if obj is None:
        yield path, obj
    elif isinstance(obj, (bool, int, float, str, bytes)):
        yield path, obj
    elif isinstance(obj, (list, tuple)):
        if not unfold_array:
            yield path, obj
        else:
            yield path, ArrayFlag
            # Ellipsis (...) is set when array elements are expected
            for idx, val in enumerate(obj):
                yield from unfold_tree(val, path=path + (idx,), unfold_array=unfold_array, depth=depth)
    elif isinstance(obj, dict):
        # TODO: set ObjectFlag for all dicts?
        if obj == {}:
            yield path, ObjectFlag
        for key, val in obj.items():
            yield from unfold_tree(val, path=path + (key,), unfold_array=unfold_array, depth=depth)
    else:
        raise NotImplementedError


cpdef val_to_node(
    val: Any,
    strict: bool = True
):
    if not strict:
        node = dict()
        if val == ArrayFlag:
            node['__example_type__'] = str(list)
        elif val != ObjectFlag:
            node['__example_type__'] = str(type(val))
        return node
    if val == ObjectFlag:
        return dict()
    elif val == ArrayFlag:
        return []
    else:
        return val


def fold_tree(
    paths_vals: Iterator[Tuple[Tuple[Union[int, str], ...], Any]],
    strict: bool = True
) -> AimObject:
    (keys, val), = iter_fold_tree(paths_vals,
                                  level=0, strict=strict)
    # TODO raise KeyError here
    return val


def iter_fold_tree(
    paths_vals: Iterator[Tuple[Tuple[Union[int, str], ...], Any]],
    level: int = 0,
    strict: bool = True
):
    cdef int idx
    stack = []
    path = []

    # # TODO remove
    # paths_vals = list(paths_vals)
    # L = paths_vals
    # paths_vals = iter(paths_vals)
    try:
        keys, val = next(paths_vals)
        # assert not keys
        if keys:
            raise StopIteration
        node = val_to_node(val)
        stack.append(node)
    except StopIteration:
        if level > 0:
            return
        else:
            raise KeyError

    for keys, val in paths_vals:
        idx = 0
        while idx < len(path):
            if keys[idx] != path[idx]:
                break
            idx += 1

        while idx < len(path):
            last_state = stack.pop()
            if len(stack) == level:
                yield tuple(path), last_state
            path.pop()

        node = val_to_node(val, strict=strict)

        if len(keys) == len(path):
            # override with new
            stack.pop()
            path.pop()

        assert len(keys) == len(path) + 1
        key_to_add = keys[-1]
        path.append(key_to_add)
        assert stack

        if isinstance(stack[-1], list):
            assert isinstance(key_to_add, int)
            if key_to_add < 0:
                raise NotImplementedError
            elif key_to_add < len(stack[-1]):
                stack[-1][key_to_add] = node
            else:
                while len(stack[-1]) != key_to_add:
                    stack[-1].append(None)
                stack[-1].append(node)
        elif isinstance(stack[-1], dict):
            stack[-1][key_to_add] = node
        else:
            raise ValueError
        stack.append(node)

        # # stack.pop()
        # stack.append(new_state)

    # while path != keys[:len(path)]:
    #     last_state = stack.pop()
    #     if len(stack) == level:
    #         yield path, last_state
    #     path.pop()

    # if level == 0:
    #     yield (), stack[0]

    if level < len(stack):
        yield tuple(path[:level]), stack[level]



def encode_paths_vals(
    paths_vals: Iterator[Tuple[Tuple[Union[int, str], ...], Any]]
) -> Iterator[Tuple[bytes, bytes]]:
    for path, val in paths_vals:
        path = E_encode_path(path)
        val = E_encode(val)
        yield path, val


cdef class DecodePathsVals(object):
    cdef paths_vals
    cdef current_path
    cdef to_yield
    cdef int num_yielded

    def __cinit__(self, paths_vals):
        self.paths_vals = paths_vals
        self.current_path = None
        self.to_yield = []
        self.num_yielded = 0

    def __iter__(self):
        return self

    def __next__(self):
        return self._next()

    cdef _next(self):
        cdef int idx
        if self.to_yield:
            val = self.to_yield[self.num_yielded]
            self.num_yielded += 1
            if self.num_yielded == len(self.to_yield):
                self.num_yielded = 0
                self.to_yield = []
            return val

        while True:
            encoded_path, encoded_val = next(self.paths_vals)
            path = decode_path(encoded_path)
            val = E_decode(encoded_val)

            if self.current_path is None:
                if path:
                    to_yield = (), ObjectFlag
                    self.to_yield.append(to_yield)
                self.current_path = []
                break
            elif self.current_path != path:
                break

        idx = 0
        new_path = []
        while idx < len(self.current_path):
            key = path[idx]
            if key != self.current_path[idx]:
                break
            new_path.append(key)
            idx += 1
        self.current_path = new_path

        while idx < len(path):
            self.current_path.append(path[idx])
            if idx < len(path):
                to_yield = tuple(self.current_path), ObjectFlag
                self.to_yield.append(to_yield)
            idx += 1

        to_yield = tuple(path), val
        self.to_yield.append(to_yield)


        val = self.to_yield[self.num_yielded]
        self.num_yielded += 1
        if self.num_yielded == len(self.to_yield):
            self.num_yielded = 0
            self.to_yield = []
        return val


def encode_tree(
    obj: AimObject
) -> Iterator[Tuple[bytes, bytes]]:
    return encode_paths_vals(
        unfold_tree(obj)
    )


def decode_tree(
    paths_vals: Iterator[Tuple[bytes, bytes]],
    strict: bool = True
) -> AimObject:
    return fold_tree(
        DecodePathsVals(paths_vals),
        strict=strict
    )


def iter_decode_tree(
    paths_vals: Iterator[Tuple[bytes, bytes]],
    level: int = 1
):
    return iter_fold_tree(
        DecodePathsVals(paths_vals),
        level=level
    )
