"""TunnelMaster VPN control plane reference implementation.

Run behind HTTPS. Uses an operator-configured OIDC broker for social sign-in,
SMTP for confirmation/invitation mail, and Apple signature verification for IAP.
Gateway provisioning is delegated to an authenticated operator service. No VPN
servers are fabricated, and absent dependencies return 503 rather than success.
"""
import base64
import hashlib
import json
import os
import secrets
import sqlite3
import smtplib
import ssl
import time
import uuid
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import urlencode

import httpx
from fastapi import FastAPI, HTTPException, Request, Header
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field
from policy import PRODUCTS, referral_code, device_allowed, next_month, entitlement

app = FastAPI(title='TunnelMaster VPN control plane', version='0.1.0')
DB = os.getenv('DATABASE', 'tunneldojo.sqlite3')
BUNDLE = os.getenv('BUNDLE_ID', 'com.tyh24647.TunnelDojo')
CALLBACK = 'tunneldojo://auth/callback'
PROVIDERS = {'apple', 'microsoft', 'discord', 'github', 'facebook', 'google'}


def db():
    con = sqlite3.connect(DB, timeout=15)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA foreign_keys=ON')
    return con


def initialize():
    with db() as c:
        c.executescript('''
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, identity TEXT UNIQUE, email TEXT, username TEXT, referral TEXT UNIQUE, credit_until REAL DEFAULT 0, trial_used INTEGER DEFAULT 0, referred_by TEXT);
        CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, user_id TEXT REFERENCES users(id) ON DELETE CASCADE, expires REAL);
        CREATE TABLE IF NOT EXISTS codes(hash TEXT PRIMARY KEY, kind TEXT, payload TEXT, expires REAL);
        CREATE TABLE IF NOT EXISTS devices(user_id TEXT REFERENCES users(id) ON DELETE CASCADE, device_id TEXT, name TEXT, PRIMARY KEY(user_id,device_id));
        CREATE TABLE IF NOT EXISTS purchases(transaction_id TEXT PRIMARY KEY, original_id TEXT, user_id TEXT REFERENCES users(id) ON DELETE CASCADE, product TEXT, family INTEGER, owner INTEGER, expires REAL);
        CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY, recipient TEXT, subject TEXT, body TEXT, sent INTEGER DEFAULT 0, created REAL, attempts INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS limits(key TEXT PRIMARY KEY, window REAL, count INTEGER);
        ''')


initialize()


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def required(name):
    value = os.getenv(name)
    if not value:
        raise HTTPException(503, f'{name} is not configured')
    return value


def rate_limit(key, maximum=8, seconds=600):
    now = time.time()
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('SELECT * FROM limits WHERE key=?', (key,)).fetchone()
        if not row or row['window'] + seconds < now:
            c.execute('INSERT OR REPLACE INTO limits VALUES(?,?,1)', (key, now))
        elif row['count'] >= maximum:
            raise HTTPException(429, 'Try again later')
        else:
            c.execute('UPDATE limits SET count=count+1 WHERE key=?', (key,))


def put_code(kind, payload, ttl=600):
    code = secrets.token_urlsafe(32)
    with db() as c:
        c.execute('INSERT INTO codes VALUES(?,?,?,?)', (digest(code), kind, json.dumps(payload), time.time()+ttl))
    return code


def take_code(code, kind):
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('SELECT * FROM codes WHERE hash=? AND kind=?', (digest(code), kind)).fetchone()
        if not row or row['expires'] < time.time():
            raise HTTPException(400, 'Code invalid or expired')
        c.execute('DELETE FROM codes WHERE hash=?', (digest(code),))
        return json.loads(row['payload'])


def current_user(authorization):
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Sign in required')
    with db() as c:
        row = c.execute('SELECT users.* FROM users JOIN sessions ON users.id=sessions.user_id WHERE sessions.hash=? AND sessions.expires>?',
                        (digest(authorization[7:]), time.time())).fetchone()
    if not row:
        raise HTTPException(401, 'Session expired')
    return row


def access(user):
    with db() as c:
        rows = c.execute('SELECT * FROM purchases WHERE user_id=? AND expires>?', (user['id'], time.time())).fetchall()
    family = any(x['family'] for x in rows)
    return {'premium': bool(rows) or user['credit_until'] > time.time(),
            'family': family, 'owner': any(x['family'] and x['owner'] for x in rows)}


def account(user):
    rights = access(user)
    with db() as c:
        count = c.execute('SELECT count(*) FROM devices WHERE user_id=?', (user['id'],)).fetchone()[0]
    return {'id': user['id'], 'username': user['username'], 'referralCode': user['referral'],
            'family': rights['family'], 'premium': rights['premium'], 'deviceCount': count,
            'deviceLimit': None if rights['family'] else 3}


def get_or_create(identity, email):
    # Email and OAuth identities are intentionally not auto-linked by matching email.
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        user = c.execute('SELECT * FROM users WHERE identity=?', (identity,)).fetchone()
        if not user:
            uid = str(uuid.uuid4())
            username = 'member-' + secrets.token_hex(4)
            c.execute('INSERT INTO users(id,identity,email,username,referral) VALUES(?,?,?,?,?)',
                      (uid, identity, email, username, referral_code(username)))
            user = c.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
    return user


def session(user):
    token = secrets.token_urlsafe(48)
    with db() as c:
        c.execute('INSERT INTO sessions VALUES(?,?,?)', (digest(token), user['id'], time.time()+86400*30))
    return {'token': token, 'account': account(user)}


def enqueue(recipient, subject, body, unique=None):
    required('SMTP_HOST')
    if '\n' in recipient or '\r' in recipient or '@' not in recipient or len(recipient) > 254:
        raise HTTPException(400, 'Invalid email')
    with db() as c:
        c.execute('INSERT OR IGNORE INTO outbox(id,recipient,subject,body,created) VALUES(?,?,?,?,?)',
                  (unique or secrets.token_hex(16), recipient, subject, body, time.time()))


class EmailInput(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class CodeInput(BaseModel):
    code: str = Field(min_length=1, max_length=512)


@app.post('/v1/auth/email')
def email_start(body: EmailInput, request: Request):
    rate_limit('email-ip:'+request.client.host)
    rate_limit('email-address:'+digest(body.email.lower()), 3)
    code = put_code('email', {'email': body.email.strip().lower()})
    enqueue(body.email, 'Confirm your TunnelMaster VPN account', 'Paste this one-time code into TunnelMaster VPN within 10 minutes:\n\n'+code+'\n\nIf you did not request this, ignore this message.')
    return {'message': 'If the address can receive mail, a confirmation code has been queued.'}


@app.post('/v1/auth/email/confirm')
def email_confirm(body: CodeInput, request: Request):
    rate_limit('confirm:'+request.client.host, 20)
    payload = take_code(body.code, 'email')
    return session(get_or_create('email:'+payload['email'], payload['email']))


@app.get('/v1/auth/authorize')
def authorize(provider: str, state: str, code_challenge: str, redirect_uri: str, code_challenge_method: str = 'S256'):
    if provider not in PROVIDERS or redirect_uri != CALLBACK or code_challenge_method != 'S256' or len(state) > 128 or len(code_challenge) != 43:
        raise HTTPException(400, 'Invalid authorization request')
    connections = json.loads(required('OIDC_CONNECTIONS_JSON'))
    if provider not in connections:
        raise HTTPException(503, 'Provider is not configured')
    broker_state = put_code('oauth', {'state': state, 'challenge': code_challenge})
    query = {'response_type': 'code', 'client_id': required('OIDC_CLIENT_ID'),
             'redirect_uri': required('PUBLIC_BASE_URL')+'/v1/auth/callback',
             'scope': 'openid email profile', 'state': broker_state, 'connection': connections[provider]}
    return RedirectResponse(required('OIDC_AUTHORIZE_URL')+'?'+urlencode(query), status_code=302)


@app.get('/v1/auth/callback')
async def auth_callback(state: str, code: str):
    intent = take_code(state, 'oauth')
    async with httpx.AsyncClient(timeout=15) as client:
        token = await client.post(required('OIDC_TOKEN_URL'), data={
            'grant_type': 'authorization_code', 'code': code,
            'client_id': required('OIDC_CLIENT_ID'), 'client_secret': required('OIDC_CLIENT_SECRET'),
            'redirect_uri': required('PUBLIC_BASE_URL')+'/v1/auth/callback'})
        if token.status_code != 200 or 'access_token' not in token.json():
            raise HTTPException(401, 'Provider rejected authorization')
        response = await client.get(required('OIDC_USERINFO_URL'), headers={'Authorization':'Bearer '+token.json()['access_token']})
    if response.status_code != 200:
        raise HTTPException(401, 'Unable to verify identity')
    info = response.json()
    if not info.get('sub'):
        raise HTTPException(401, 'Missing provider identity')
    user = get_or_create(required('OIDC_ISSUER')+'|'+info['sub'], info.get('email') if info.get('email_verified') else None)
    exchange = put_code('exchange', {'uid': user['id'], 'challenge': intent['challenge']}, 120)
    return RedirectResponse(CALLBACK+'?'+urlencode({'code':exchange, 'state':intent['state']}), status_code=302)


class Exchange(BaseModel):
    code: str = Field(max_length=512)
    code_verifier: str = Field(min_length=43, max_length=128)
    redirect_uri: str


@app.post('/v1/auth/exchange')
def exchange(body: Exchange):
    if body.redirect_uri != CALLBACK:
        raise HTTPException(400, 'Invalid callback')
    payload = take_code(body.code, 'exchange')
    challenge = base64.urlsafe_b64encode(hashlib.sha256(body.code_verifier.encode()).digest()).decode().rstrip('=')
    if not secrets.compare_digest(challenge, payload['challenge']):
        raise HTTPException(401, 'PKCE mismatch')
    with db() as c:
        user = c.execute('SELECT * FROM users WHERE id=?', (payload['uid'],)).fetchone()
    return session(user)


@app.get('/v1/me')
def me(authorization: str | None = Header(default=None)):
    return account(current_user(authorization))


@app.delete('/v1/me')
def delete_me(authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    # Gateway credentials must be revoked by the provisioning service before account deletion.
    raise HTTPException(503, 'Gateway credential revocation and retention workflow must be implemented before enabling account deletion')


class DeviceInput(BaseModel):
    deviceID: str = Field(min_length=16, max_length=100)
    name: str = Field(max_length=100)


@app.post('/v1/devices')
def register_device(body: DeviceInput, authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    family = access(user)['family']
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        existing = {r[0] for r in c.execute('SELECT device_id FROM devices WHERE user_id=?', (user['id'],))}
        if not device_allowed(family, existing, body.deviceID):
            raise HTTPException(409, 'Three devices already registered')
        c.execute('INSERT OR REPLACE INTO devices VALUES(?,?,?)', (user['id'], body.deviceID, body.name))
    return {'message': 'Device registered'}


@app.post('/v1/referrals/redeem')
def redeem(body: CodeInput, authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    rate_limit('referral:'+user['id'], 5)
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        user = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        owner = c.execute('SELECT id FROM users WHERE referral=?', (body.code.upper().strip(),)).fetchone()
        has_purchase = c.execute('SELECT 1 FROM purchases WHERE user_id=?', (user['id'],)).fetchone()
        if not owner or owner['id'] == user['id'] or user['referred_by'] or user['trial_used'] or has_purchase:
            raise HTTPException(409, 'Referral not eligible')
        until = next_month(datetime.now(timezone.utc)).timestamp()
        c.execute('UPDATE users SET referred_by=?,credit_until=?,trial_used=1 WHERE id=?', (owner['id'], until, user['id']))
    return {'message': 'One month of service credit applied. Existing Apple billing is unchanged.'}


@app.post('/v1/trials/lifetime')
def lifetime_trial(authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        user = c.execute('SELECT * FROM users WHERE id=?', (user['id'],)).fetchone()
        purchased = c.execute('SELECT 1 FROM purchases WHERE user_id=?', (user['id'],)).fetchone()
        if user['trial_used'] or purchased:
            raise HTTPException(409, 'Trial already used or purchase exists')
        c.execute('UPDATE users SET trial_used=1,credit_until=? WHERE id=?', (time.time()+7*86400, user['id']))
    return {'message': 'Seven-day service trial started. No automatic lifetime charge.'}


class PurchaseInput(BaseModel):
    signedTransaction: str = Field(min_length=10, max_length=32768)


def verify_apple(signed):
    from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier
    from appstoreserverlibrary.models.Environment import Environment
    roots = [p.read_bytes() for p in Path(required('APPLE_ROOTS_DIRECTORY')).glob('*.cer')]
    if not roots:
        raise HTTPException(503, 'Apple trust roots missing')
    environment = Environment.PRODUCTION if os.getenv('APPLE_ENVIRONMENT', 'Production') == 'Production' else Environment.SANDBOX
    verifier = SignedDataVerifier(roots, True, environment, BUNDLE, int(required('APPLE_APP_ID')))
    try:
        decoded = verifier.verify_and_decode_signed_transaction(signed)
        # attrs-based SDK model: select fields explicitly, never decode the unverified JWS body.
        fields = ['productId','bundleId','revocationDate','isUpgraded','expiresDate','inAppOwnershipType','transactionId','originalTransactionId','appAccountToken']
        value = {name:getattr(decoded, name, None) for name in fields}
        ownership = value['inAppOwnershipType']
        value['inAppOwnershipType'] = getattr(ownership, 'value', ownership)
        return value
    except Exception as exc:
        raise HTTPException(400, 'Invalid Apple signed transaction') from exc


@app.post('/v1/purchases/verify')
def purchase(body: PurchaseInput, authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    decoded = verify_apple(body.signedTransaction)
    try:
        plan = entitlement(decoded, time.time()*1000, BUNDLE)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    if plan['owner'] and str(decoded.get('appAccountToken', '')).lower() != user['id'].lower():
        raise HTTPException(403, 'Purchase account binding mismatch')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        original_owner = c.execute('SELECT user_id FROM purchases WHERE original_id=? AND owner=1', (decoded['originalTransactionId'],)).fetchone()
        if plan['owner'] and original_owner and original_owner['user_id'] != user['id']:
            raise HTTPException(409, 'Purchase belongs to another account')
        prior = c.execute('SELECT user_id FROM purchases WHERE transaction_id=?', (decoded['transactionId'],)).fetchone()
        if prior and prior['user_id'] != user['id']:
            raise HTTPException(409, 'Transaction already linked to another account')
        c.execute('INSERT OR REPLACE INTO purchases VALUES(?,?,?,?,?,?,?)',
                  (decoded['transactionId'], decoded['originalTransactionId'], user['id'], plan['product'], plan['family'], plan['owner'], (plan['expires']/1000 if plan['expires'] else 253402300799)))
    return {'message': 'Purchase verified. Premium service entitlement updated.'}


class InvitationInput(BaseModel):
    emails: str = Field(max_length=1500)


@app.post('/v1/family/invitations')
def invite(body: InvitationInput, authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    if not access(user)['owner']:
        raise HTTPException(403, 'A verified family purchaser is required')
    emails = {x.strip().lower() for x in body.emails.split(',') if x.strip()}
    if not 1 <= len(emails) <= 5:
        raise HTTPException(400, 'Enter one to five family recipients')
    rate_limit('invite:'+user['id'], 5, 86400)
    for email in emails:
        enqueue(email, 'TunnelMaster VPN family access is available',
                'Your family organizer has enabled TunnelMaster VPN family access. Set up Apple Family Sharing, download TunnelMaster VPN, and restore purchases using your own Apple Account. This email alone does not grant access.',
                unique=digest(user['id']+'|'+email+'|family-v1'))
    return {'message': 'Family invitations queued after verified payment'}


def catalog():
    path = os.getenv('GATEWAY_CATALOG')
    return json.loads(Path(path).read_text()) if path else {'servers': []}


@app.get('/v1/servers')
def servers():
    result = catalog()
    result['purchasesEnabled'] = os.getenv('COMMERCIAL_READY', 'false') == 'true'
    return result


class TunnelInput(BaseModel):
    serverID: str = Field(max_length=100)
    exitID: str = Field(default='', max_length=100)
    deviceID: str = Field(default='', max_length=100)


@app.post('/v1/tunnels')
async def tunnel(body: TunnelInput, authorization: str | None = Header(default=None)):
    user = current_user(authorization)
    entries = catalog()['servers']
    selected = next((s for s in entries if s['id'] == body.serverID and s['online']), None)
    if not selected:
        raise HTTPException(404, 'Gateway unavailable')
    rights = access(user)
    if selected['premium'] and not rights['premium']:
        raise HTTPException(403, 'Premium entitlement required')
    if body.exitID and (not rights['premium'] or body.exitID not in selected['multihopExits']):
        raise HTTPException(400, 'Unsupported multi-hop route')
    with db() as c:
        if not c.execute('SELECT 1 FROM devices WHERE user_id=? AND device_id=?', (user['id'],body.deviceID)).fetchone():
            raise HTTPException(403, 'Register this device before provisioning')
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(required('PROVISIONER_URL')+'/tunnels',
            headers={'Authorization':'Bearer '+required('PROVISIONER_TOKEN')},
            json={'accountID':user['id'],'deviceID':body.deviceID,'entry':body.serverID,'exit':body.exitID or None,'premium':rights['premium']})
    if response.status_code != 200:
        raise HTTPException(503, 'Provisioning failed')
    return response.json()


def deliver_outbox():
    """Run as a single worker. Only queued, explicitly requested operational mail is sent."""
    with db() as c:
        rows = c.execute('SELECT * FROM outbox WHERE sent=0 AND attempts<10 ORDER BY created LIMIT 20').fetchall()
    for row in rows:
        message = EmailMessage()
        message['From'] = required('MAIL_FROM')
        message['To'] = row['recipient']
        message['Subject'] = row['subject']
        message.set_content(row['body'])
        with db() as c:
            c.execute('UPDATE outbox SET attempts=attempts+1 WHERE id=?', (row['id'],))
        with smtplib.SMTP_SSL(required('SMTP_HOST'), int(os.getenv('SMTP_PORT','465')), context=ssl.create_default_context()) as smtp:
            smtp.login(required('SMTP_USER'), required('SMTP_PASSWORD'))
            smtp.send_message(message)
        with db() as c:
            c.execute('UPDATE outbox SET sent=1,body="" WHERE id=?', (row['id'],))
