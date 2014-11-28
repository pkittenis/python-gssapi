GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from libc.string cimport memcmp, memcpy
from libc.stdlib cimport free, malloc

from gssapi.raw.cython_types cimport gss_OID

cdef inline bint c_compare_oids(gss_OID a, gss_OID b):
    return (a.length == b.length and
            not memcmp(a.elements, b.elements, a.length))


cdef class OID:
    """GSSAPI OID

    A new OID may be created by passing the `elements` argument
    to the constructor.  The `elements` argument should be a
    `bytes` consisting of the BER-encoded values in the OID.

    To retrive the underlying bytes, use the :func:`bytes`
    function in Python 3 or the :meth:`__bytes__` method directly
    in Python 2.

    This object is hashable, and may be compared using equality
    operators.
    """
    # defined in pxd
    # cdef gss_OID_desc raw_oid = NULL
    # cdef bint _free_on_dealloc = NULL

    def __cinit__(OID self, OID cpy=None, elements=None):
        if cpy is not None and elements is not None:
            raise TypeError("Cannot instantiate a OID from both a copy and "
                            " a new set of elements")
        if cpy is not None:
            self.raw_oid = cpy.raw_oid

        if elements is None:
            self._free_on_dealloc = False
        else:
            self._from_bytes(elements)

    cdef int _copy_from(OID self, gss_OID_desc base) except -1:
        self.raw_oid.length = base.length
        self.raw_oid.elements = malloc(self.raw_oid.length)
        if self.raw_oid.elements is NULL:
            raise MemoryError("Could not allocate memory for OID elements!")
        memcpy(self.raw_oid.elements, base.elements, self.raw_oid.length)
        self._free_on_dealloc = True
        return 0

    cdef int _from_bytes(OID self, object base) except -1:
        base_bytes = bytes(base)
        cdef char* byte_str = base_bytes

        self.raw_oid.length = len(base_bytes)
        self.raw_oid.elements = malloc(self.raw_oid.length)
        if self.raw_oid.elements is NULL:
            raise MemoryError("Could not allocate memory for OID elements!")
        self._free_on_dealloc = True
        memcpy(self.raw_oid.elements, byte_str, self.raw_oid.length)
        return 0

    def __dealloc__(self):
        # NB(directxman12): MIT Kerberos has gss_release_oid
        #                   for this purpose, but it's not in the RFC
        if self._free_on_dealloc:
            free(self.raw_oid.elements)

    def __bytes__(self):
        return (<char*>self.raw_oid.elements)[:self.raw_oid.length]

    def _decode_asn1ber(self):
        ber_encoding = self.__bytes__()
        # NB(directxman12): indexing a byte string yields an int in Python 3,
        #                   but yields a substring in Python 2
        if six.PY2:
            ber_encoding = [ord(c) for c in ber_encoding]

        decoded = [ber_encoding[0] // 40, ber_encoding[0] % 40]
        pos = 1
        value = 0
        while pos < len(ber_encoding):
            byte = ber_encoding[pos]
            if byte & 0x80:
                # This is one of the leading bytes
                value <<= 7
                value += ((byte & 0x7f) * 128)
            else:
                # This is the last byte of this value
                value += (byte & 0x7f)
                decoded.append(value)
                value = 0
            pos += 1
        return decoded

    def __repr__(self):
        dotted_oid = '.'.join(str(x) for x in self._decode_asn1ber())
        return "<OID {0}>".format(dotted_oid)

    def __hash__(self):
        return hash(self.__bytes__())

    def __richcmp__(OID self, OID other, op):
        if op == 2 or op == 3:  # ==
            return c_compare_oids(&self.raw_oid, &other.raw_oid)
        elif op == 3:  # !=
            return not c_compare_oids(&self.raw_oid, &other.raw_oid)
        else:
            return NotImplemented
