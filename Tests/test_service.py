"""Local HTTP security tests; mocks mail enqueue, never sends email or calls providers."""
import base64
import hashlib
import importlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Service'))

class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        os.environ['DATABASE']=str(Path(cls.temp.name)/'test.sqlite3')
        os.environ['COMMERCIAL_READY']='false'
        cls.app=importlib.import_module('app')
        from fastapi.testclient import TestClient
        cls.client=TestClient(cls.app.app)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def credentials(self,name):
        user=self.app.get_or_create('test:'+name,name+'@example.invalid')
        result=self.app.session(user)
        return user,{'Authorization':'Bearer '+result['token']}

    def test_email_confirmation_is_one_time(self):
        with patch.object(self.app,'enqueue') as mail:
            response=self.client.post('/v1/auth/email',json={'email':'test@example.invalid'})
            self.assertEqual(response.status_code,200)
            code=mail.call_args.args[2].split('\n\n')[1]
        response=self.client.post('/v1/auth/email/confirm',json={'code':code})
        self.assertEqual(response.status_code,200)
        self.assertIn('token',response.json())
        self.assertEqual(self.client.post('/v1/auth/email/confirm',json={'code':code}).status_code,400)

    def test_pkce_and_replay(self):
        user,_=self.credentials('pkce')
        verifier='a'*43
        challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
        code=self.app.put_code('exchange',{'uid':user['id'],'challenge':challenge})
        bad={'code':code,'code_verifier':'b'*43,'redirect_uri':self.app.CALLBACK}
        self.assertEqual(self.client.post('/v1/auth/exchange',json=bad).status_code,401)
        good=bad|{'code_verifier':verifier}
        self.assertEqual(self.client.post('/v1/auth/exchange',json=good).status_code,400)
        good['code']=self.app.put_code('exchange',{'uid':user['id'],'challenge':challenge})
        self.assertEqual(self.client.post('/v1/auth/exchange',json=good).status_code,200)

    def test_unpaid_family_invitation_rejected(self):
        _,headers=self.credentials('family')
        with patch.object(self.app,'enqueue') as mail:
            response=self.client.post('/v1/family/invitations',headers=headers,json={'emails':'other@example.invalid'})
            self.assertEqual(response.status_code,403)
            mail.assert_not_called()

    def test_referral_repeat_and_self_rejected(self):
        owner,owner_headers=self.credentials('referrer')
        _,headers=self.credentials('referred')
        body={'code':owner['referral']}
        self.assertEqual(self.client.post('/v1/referrals/redeem',headers=owner_headers,json=body).status_code,409)
        self.assertEqual(self.client.post('/v1/referrals/redeem',headers=headers,json=body).status_code,200)
        self.assertEqual(self.client.post('/v1/referrals/redeem',headers=headers,json=body).status_code,409)

    def test_server_is_not_commercially_enabled(self):
        response=self.client.get('/v1/servers')
        self.assertEqual(response.status_code,200)
        self.assertFalse(response.json()['purchasesEnabled'])
        self.assertEqual(response.json()['servers'],[])

if __name__=='__main__':
    unittest.main(verbosity=2)
