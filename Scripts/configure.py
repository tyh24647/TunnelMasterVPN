#!/usr/bin/env python3
"""Create static metadata and the local StoreKit catalog. Run before project generation."""
from pathlib import Path
import plistlib
import json
R = Path(__file__).resolve().parents[1]

def plist(path, value):
    (R/path).write_bytes(plistlib.dumps(value, sort_keys=False))

common = {'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'$(EXECUTABLE_NAME)',
          'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0',
          'CFBundleName':'$(PRODUCT_NAME)','CFBundleShortVersionString':'1.0','CFBundleVersion':'1',
          'CredentialGroup':'$(AppIdentifierPrefix)$(TD_BUNDLE_PREFIX).credentials'}
plist('Configuration/App-Info.plist', common | {
    'CFBundleDisplayName':'TunnelMaster VPN - [⇅] - Free • Custom • Unlimited','CFBundlePackageType':'APPL',
    'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},
    'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
    'CFBundleURLTypes':[{'CFBundleURLSchemes':['tunneldojo'],'CFBundleURLName':'TunnelMaster VPN account callback'}],
    'ServiceBaseURL':'$(TD_SERVICE_URL)','SupportEmail':'$(TD_SUPPORT_EMAIL)',
    'ITSAppUsesNonExemptEncryption':True})
plist('Configuration/Packet-Info.plist', common | {
    'CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.networkextension.packet-tunnel',
    'NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).PacketTunnelProvider'}})
shared = {'com.apple.developer.networking.networkextension':['packet-tunnel-provider'],
          'keychain-access-groups':['$(AppIdentifierPrefix)$(TD_BUNDLE_PREFIX).credentials']}
plist('Configuration/App.entitlements', shared | {
    'com.apple.developer.networking.vpn.api':['allow-vpn'],
    'com.apple.developer.ubiquity-kvstore-identifier':'$(TeamIdentifierPrefix)$(TD_BUNDLE_PREFIX)'})
plist('Configuration/Packet.entitlements', shared)
plist('Shared/PrivacyInfo.xcprivacy', {
    'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[], 'NSPrivacyCollectedDataTypes':[],
    'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults',
                               'NSPrivacyAccessedAPITypeReasons':['CA92.1']}]})
products=[]
subscriptions=[]
for scope, prices in [('individual',['0.99','2.99','24.99','69.99']),('family',['2.99','9.99','49.99','199.99'])]:
    for term,price,period in zip(['weekly','monthly','yearly','lifetime'], prices, ['P1W','P1M','P1Y',None]):
        identifier=f'com.tyh24647.TunnelDojo.{scope}.{term}'
        value={'displayPrice':price,'familyShareable':scope=='family','internalID':scope+'-'+term,
               'localizations':[{'description':'Premium VPN service'+(' for your family' if scope=='family' else ''),
                                 'displayName':f'TunnelMaster VPN {scope.title()} {term.title()}','locale':'en_US'}],
               'productID':identifier,'referenceName':scope+' '+term}
        if term=='lifetime':
            value['type']='NonConsumable';products.append(value)
        else:
            value.update({'type':'RecurringSubscription','adHocOffers':[],'codeOffers':[],
                          'groupNumber':1 if scope=='family' else 2,
                          'subscriptionGroupID':'TUNNELDOJO-PREMIUM','recurringSubscriptionPeriod':period,
                          'introductoryOffer':{'internalID':'trial-'+scope+'-'+term,'paymentMode':'free',
                                               'subscriptionPeriod':'P1W','numberOfPeriods':1}})
            subscriptions.append(value)
catalog={'identifier':'B361F586-EBC1-4B9A-9257-323759F524DF', 'nonRenewingSubscriptions':[], 'products':products,
         'settings':{'_applicationInternalID':'','_developerTeamID':'','_failTransactionsEnabled':False,
                     '_locale':'en_US','_storefront':'USA','_storeKitErrors':[]},
         'subscriptionGroups':[{'id':'TUNNELDOJO-PREMIUM','name':'TunnelMaster VPN Premium','localizations':[], 'subscriptions':subscriptions}],
         'version':{'major':3,'minor':0}}
(R/'Configuration/TunnelMasterVPN.storekit').write_text(json.dumps(catalog,indent=2))
