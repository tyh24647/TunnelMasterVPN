"""Exercise the actual C packet/PCRE engine and service authorization policy."""
import ctypes as C
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'Service'))
from policy import device_allowed, entitlement, next_month, referral_code, PREFIX

class Core(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        binary = str(Path(cls.temp.name)/'core.so')
        sources = [str(ROOT/'Vendor/PCRE2/src'/x) for x in json.loads((ROOT/'Vendor/PCRE2/sources.json').read_text())]
        subprocess.run(['cc','-shared','-fPIC','-O1','-DHAVE_CONFIG_H','-DPCRE2_CODE_UNIT_WIDTH=8',
                        '-I'+str(ROOT/'Vendor/PCRE2/src'),str(ROOT/'Shared/RegexBridge.c'),
                        str(ROOT/'Shared/DNSPacket.c'),*sources,'-o',binary], check=True)
        cls.lib = C.CDLL(binary)
        cls.lib.td_regex_match.argtypes=[C.c_char_p,C.c_char_p,C.c_char_p,C.c_size_t]
        cls.lib.td_dns_extract.argtypes=[C.c_char_p,C.c_size_t,C.POINTER(C.c_size_t),C.POINTER(C.c_size_t)]
        cls.lib.td_dns_question.argtypes=[C.c_char_p,C.c_size_t,C.c_char_p,C.c_size_t]
        cls.lib.td_dns_answer.argtypes=[C.c_char_p,C.c_size_t,C.c_char_p,C.c_int,C.c_char_p,C.c_size_t]
        cls.lib.td_dns_wrap.argtypes=[C.c_char_p,C.c_size_t,C.c_char_p,C.c_size_t,C.c_char_p,C.c_size_t]

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def regex(self,pattern,subject):
        error=C.create_string_buffer(256)
        return self.lib.td_regex_match(pattern.encode(),subject.encode(),error,256)

    def test_lookahead_lookbehind_backreference_recursion(self):
        for pattern,subject in [(r'(?=ads\.)^ads\..+$','ads.example.com'),
                                (r'(?<=ads\.)example','ads.example'),
                                (r'^([a-z]+)\.\1\.example$','ads.ads.example'),
                                (r'^(?<p>a(?&p)?b)\.example$','aabb.example')]:
            self.assertEqual(self.regex(pattern,subject),1)
        self.assertEqual(self.regex('^ads\\.', 'cdn.example'),0)
        self.assertEqual(self.regex('(', 'example'),-1)

    def test_regex_budget(self):
        self.assertEqual(self.regex('(*NO_START_OPT)(*NO_AUTO_POSSESS)^(a+)+$', 'a'*200+'!'),-2)

    @staticmethod
    def query(kind=1):
        return struct.pack('!HHHHHH',123,0x0100,1,0,0,0)+b'\x03ads\x07example\x03com\x00'+struct.pack('!HH',kind,1)

    @staticmethod
    def packet(query,version=4):
        udp=struct.pack('!HHHH',54321,53,len(query)+8,0)+query
        if version==4:
            return bytes([0x45,0])+struct.pack('!H',20+len(udp))+bytes(4)+bytes([64,17])+bytes(2)+bytes([198,18,0,2,198,18,0,1])+udp
        return bytes([0x60,0,0,0])+struct.pack('!H',len(udp))+bytes([17,64])+bytes.fromhex('fd0074756e6e00000000000000000002fd0074756e6e00000000000000000001')+udp

    def answer(self,query,sink=b'0.0.0.0',failure=0):
        out=C.create_string_buffer(1500)
        size=self.lib.td_dns_answer(query,len(query),sink,failure,out,1500)
        return out.raw[:size]

    def test_a_aaaa_and_failure(self):
        q=self.query();a=self.answer(q)
        self.assertEqual(a[-4:],bytes(4))
        self.assertEqual(struct.unpack('!H',a[6:8])[0],1)
        self.assertEqual(self.answer(q,b'127.0.0.1')[-4:],bytes([127,0,0,1]))
        for kind in [28,65,64]:
            a=self.answer(self.query(kind))
            self.assertEqual(a[6:8],bytes(2))
        self.assertEqual(self.answer(q,failure=1)[3]&15,2)

    def test_ipv4_ipv6_reverse_and_checksum(self):
        for version,h in [(4,20),(6,40)]:
            query=self.query();packet=self.packet(query,version)
            offset=C.c_size_t();length=C.c_size_t()
            self.assertEqual(self.lib.td_dns_extract(packet,len(packet),C.byref(offset),C.byref(length)),version)
            self.assertEqual(packet[offset.value:offset.value+length.value],query)
            dns=self.answer(query);out=C.create_string_buffer(1500)
            size=self.lib.td_dns_wrap(packet,len(packet),dns,len(dns),out,1500)
            answer=out.raw[:size]
            self.assertEqual(answer[h:h+4],struct.pack('!HH',53,54321))
            addresses=answer[12:20] if version==4 else answer[8:40]
            pseudo=addresses+struct.pack('!HH',17,len(dns)+8)
            values=pseudo+answer[h:]
            if len(values)%2:values+=b'\0'
            total=sum(struct.unpack('!'+str(len(values)//2)+'H',values))
            while total>>16:total=(total&65535)+(total>>16)
            self.assertEqual(total,65535)

    def test_malformed_packets_and_fragment_rejected(self):
        for size in range(80):
            p=bytes(random.Random(size).randrange(256) for _ in range(size))
            offset=C.c_size_t();length=C.c_size_t()
            self.assertEqual(self.lib.td_dns_extract(p,len(p),C.byref(offset),C.byref(length)),0)
        p=bytearray(self.packet(self.query()));p[6]=0x20
        self.assertEqual(self.lib.td_dns_extract(bytes(p),len(p),C.byref(C.c_size_t()),C.byref(C.c_size_t())),0)
        host=C.create_string_buffer(256)
        q=self.query()
        for length in range(len(q)):
            self.assertEqual(self.lib.td_dns_question(q[:length],length,host,256),0)
        q=q[:12]+b'\xc0\x0c'+q[-4:]
        self.assertEqual(self.lib.td_dns_question(q,len(q),host,256),0)

class Policy(unittest.TestCase):
    def test_device_cap_and_family(self):
        self.assertTrue(device_allowed(False,{'a','b','c'},'a'))
        self.assertFalse(device_allowed(False,{'a','b','c'},'d'))
        self.assertTrue(device_allowed(True,{'a','b','c'},'d'))

    def test_calendar_referral_month(self):
        self.assertEqual(next_month(datetime(2028,1,31,tzinfo=timezone.utc)).day,29)
        self.assertEqual(next_month(datetime(2026,12,31,tzinfo=timezone.utc)).year,2027)
        self.assertTrue(referral_code('Tyler_42').startswith('TYLER42-'))

    def test_entitlement_not_client_assertion(self):
        value={'productId':PREFIX+'family.monthly','bundleId':'app','expiresDate':2000,'inAppOwnershipType':'PURCHASED'}
        self.assertTrue(entitlement(value,1000,'app')['family'])
        for patch in [{'expiresDate':500},{'revocationDate':10},{'isUpgraded':True},{'productId':'invented'},{'bundleId':'other'}]:
            with self.assertRaises(ValueError):entitlement(value|patch,1000,'app')
        self.assertFalse(entitlement(value|{'inAppOwnershipType':'FAMILY_SHARED'},1000,'app')['owner'])

if __name__=='__main__':
    unittest.main(verbosity=2)
