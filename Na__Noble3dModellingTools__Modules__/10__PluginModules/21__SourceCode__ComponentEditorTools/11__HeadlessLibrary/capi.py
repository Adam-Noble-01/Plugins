"""Small typed ctypes binding to the installed SketchUp 2026 standalone C API.

Only load this DLL in the separate worker process, never inside SketchUp's Ruby
process. Signatures: https://extensions.sketchup.com/developers/sketchup_c_api/
All C API calls run on this process's main thread.
"""
import ctypes as C
import os
from pathlib import Path


class Ref(C.Structure):
    _fields_ = [('ptr', C.c_void_p)]


class Point(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double), ('z', C.c_double)]


class Box(C.Structure):
    _fields_ = [('minimum', Point), ('maximum', Point)]


class Transform(C.Structure):
    _fields_ = [('values', C.c_double * 16)]


class Color(C.Structure):
    _fields_ = [('red', C.c_ubyte), ('green', C.c_ubyte), ('blue', C.c_ubyte), ('alpha', C.c_ubyte)]


class ApiError(RuntimeError):
    pass


class API:
    NO_DATA = 9

    def __init__(self, directory):
        self.directory = Path(directory).resolve()
        self.dll_directory = os.add_dll_directory(str(self.directory))
        self.dll = C.CDLL(str(self.directory / 'SketchUpAPI.dll'))
        self.invoke('SUInitialize', restype=None)

    def close(self):
        self.invoke('SUTerminate', restype=None)
        self.dll_directory.close()

    def invoke(self, name, *args, restype=C.c_int):
        function = getattr(self.dll, name)
        # All numeric arguments must be explicitly typed; references are C
        # structs passed by value, not pointers masquerading as Python integers.
        types = []
        for arg in args:
            if isinstance(arg, bytes):
                types.append(C.c_char_p)
            elif hasattr(arg, '_obj'):  # ctypes.byref
                types.append(C.POINTER(type(arg._obj)))
            else:
                types.append(type(arg))
        function.argtypes = types
        function.restype = restype
        return function(*args)

    def call(self, name, *args, optional=False):
        result = self.invoke(name, *args)
        if optional and result == self.NO_DATA:
            return False
        if result != 0:
            raise ApiError(f'{name} failed (C API result {result}).')
        return True

    def ref(self, name, *args, optional=False):
        value = Ref()
        self.call(name, *args, C.byref(value), optional=optional)
        return value

    def convert(self, name, value):
        return self.invoke(name, value, restype=Ref)

    def scalar(self, name, owner, value_type=C.c_size_t, optional=False):
        value = value_type()
        self.call(name, owner, C.byref(value), optional=optional)
        return value.value

    def refs(self, prefix, suffix, owner, *extra):
        count = C.c_size_t()
        self.call(prefix + 'GetNum' + suffix, owner, *extra, C.byref(count))
        if not count.value:
            return []
        values = (Ref * count.value)()
        self.call(prefix + 'Get' + suffix, owner, *extra, count, values, C.byref(count))
        return list(values[:count.value])

    def text(self, name, owner, optional=False):
        string = self.ref('SUStringCreate')
        try:
            self.call(name, owner, C.byref(string), optional=optional)
            size = self.scalar('SUStringGetUTF8Length', string)
            buffer = C.create_string_buffer(size + 1)
            copied = C.c_size_t()
            self.call('SUStringGetUTF8', string, C.c_size_t(size + 1), buffer, C.byref(copied))
            return buffer.value.decode('utf-8')
        finally:
            self.call('SUStringRelease', C.byref(string))

    def pid(self, entity):
        return self.scalar('SUEntityGetPersistentID', entity, C.c_int64)

    def metadata(self, entity, dictionary_name, values):
        dictionary = self.ref('SUEntityGetAttributeDictionary', entity, dictionary_name.encode())
        for key, text in values.items():
            value = self.ref('SUTypedValueCreate')
            try:
                self.call('SUTypedValueSetString', value, str(text).encode('utf-8'))
                self.call('SUAttributeDictionarySetValue', dictionary, key.encode(), value)
            finally:
                self.call('SUTypedValueRelease', C.byref(value))


class Model:
    def __init__(self, api, path=None):
        self.api = api
        self.ref = Ref()
        if path is None:
            api.call('SUModelCreate', C.byref(self.ref))
        else:
            status = C.c_int()
            api.call('SUModelCreateFromFileWithStatus', C.byref(self.ref), str(path).encode('utf-8'), C.byref(status))
            if status.value != 0:
                self.close()
                raise ApiError('This file was created by a newer SketchUp version; it cannot be edited safely by this helper.')

    def close(self):
        if self.ref.ptr:
            self.api.call('SUModelRelease', C.byref(self.ref))

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def save(self, path):
        self.api.call('SUModelSaveToFile', self.ref, str(path).encode('utf-8'))

    def entities(self):
        return self.api.ref('SUModelGetEntities', self.ref)

    def definitions(self):
        return [(kind, definition) for kind in ['Component', 'Group', 'Image']
                for definition in self.api.refs('SUModel', kind + 'Definitions', self.ref)]

    def resources(self, kind):
        prefix, suffix = ('SULayer', 'Layers') if kind == 'tags' else ('SUMaterial', 'Materials')
        return [{'ref': value, 'id': ('tag:' if kind == 'tags' else 'material:') + str(self.api.pid(self.api.convert(prefix + 'ToEntity', value))),
                 'name': self.api.text(prefix + 'GetName', value)}
                for value in self.api.refs('SUModel', suffix, self.ref)]

    def walk(self):
        contexts = [('root', self.entities())]
        definitions = self.definitions()
        contexts += [(str(self.api.pid(self.api.convert('SUComponentDefinitionToEntity', definition))),
                      self.api.ref('SUComponentDefinitionGetEntities', definition)) for _, definition in definitions]
        kinds = [('Face', 'Faces'), ('Edge', 'Edges'), ('Group', 'Groups'),
                 ('ComponentInstance', 'Instances'), ('Image', 'Images'),
                 ('GuidePoint', 'GuidePoints'), ('GuideLine', 'GuideLines'),
                 ('SectionPlane', 'SectionPlanes'), ('Text', 'Texts'),
                 ('Dimension', 'Dimensions'), ('Polyline3d', 'Polyline3ds')]
        for context_id, entities in contexts:
            for kind, plural in kinds:
                extra = (C.c_bool(False),) if kind == 'Edge' else ()
                for value in self.api.refs('SUEntities', plural, entities, *extra):
                    drawing = self.api.convert('SU' + kind + 'ToDrawingElement', value)
                    entity = self.api.convert('SUDrawingElementToEntity', drawing)
                    yield {'kind': kind, 'ref': value, 'drawing': drawing, 'pid': self.api.pid(entity), 'context': context_id}
