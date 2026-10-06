"""Pure service policy, shared with unit tests. No client flag grants premium access."""
from datetime import datetime, timedelta, timezone
import calendar
import re
import secrets

PREFIX = 'com.tyh24647.TunnelDojo.'
PRODUCTS = {
    PREFIX + scope + '.' + term: {'family': scope == 'family', 'lifetime': term == 'lifetime'}
    for scope in ('individual', 'family')
    for term in ('weekly', 'monthly', 'yearly', 'lifetime')
}

def referral_code(username):
    slug = re.sub(r'[^A-Z0-9]', '', username.upper())[:16] or 'MEMBER'
    return slug + '-' + secrets.token_hex(4).upper()

def device_allowed(family, registered, device_id):
    return family or device_id in registered or len(registered) < 3

def next_month(now):
    year = now.year + (now.month == 12)
    month = now.month % 12 + 1
    return now.replace(year=year, month=month, day=min(now.day, calendar.monthrange(year, month)[1]))

def entitlement(decoded, now_ms, bundle):
    product = decoded.get('productId')
    if product not in PRODUCTS or decoded.get('bundleId') != bundle:
        raise ValueError('Unknown product or bundle')
    if decoded.get('revocationDate') or decoded.get('isUpgraded'):
        raise ValueError('Revoked or superseded transaction')
    plan = PRODUCTS[product]
    expires = decoded.get('expiresDate')
    if not plan['lifetime'] and (not expires or expires <= now_ms):
        raise ValueError('Subscription expired')
    return {'product': product, 'family': plan['family'], 'expires': expires,
            'owner': decoded.get('inAppOwnershipType') == 'PURCHASED'}
