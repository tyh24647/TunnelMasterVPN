#!/usr/bin/env python3
"""Generate an Xcode project without requiring XcodeGen."""
from pathlib import Path
import hashlib
import json
import re
import sys
WIREGUARD = '--wireguard' in sys.argv

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def oid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def add(key, isa, **fields):
    key = oid(key)
    objects[key] = {'isa': isa, **fields}
    return key

def ref(path, filetype=None):
    key = 'file:' + path
    if oid(key) in objects:
        return oid(key)
    types = {'.swift':'sourcecode.swift','.c':'sourcecode.c.c','.h':'sourcecode.c.h','.xcconfig':'text.xcconfig','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.json':'text.json','.js':'sourcecode.javascript','.html':'text.html','.css':'text.css','.xcassets':'folder.assetcatalog','.xcprivacy':'text.xml','.txt':'text','.storekit':'text.json'}
    return add(key,'PBXFileReference',lastKnownFileType=filetype or types.get(Path(path).suffix,'text'),path=path,sourceTree='<group>')

def buildfile(target, path, **kwargs):
    return add('build:'+target+':'+path,'PBXBuildFile',fileRef=ref(path),**kwargs)

def configlist(key, settings, project=False):
    ids=[]
    for name in ['Debug','Release']:
        s=settings.copy()
        if project:
            s |= {'GCC_OPTIMIZATION_LEVEL': '0' if name=='Debug' else 's','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym', 'ENABLE_TESTABILITY':'YES' if name=='Debug' else 'NO', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) DEBUG ' if name=='Debug' else '$(inherited)', 'SWIFT_COMPILATION_MODE':'singlefile' if name=='Debug' else 'wholemodule'}
        ids.append(add(key+':'+name,'XCBuildConfiguration',baseConfigurationReference=ref('Configuration/Project.xcconfig'),buildSettings=s,name=name))
    return add(key+':list','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

products=[]
targets=[]
shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Shared').glob('*.swift'))
common_c = ['Shared/RegexBridge.c','Shared/DNSPacket.c'] + ['Vendor/PCRE2/src/'+p for p in json.loads((ROOT/'Vendor/PCRE2/sources.json').read_text())]
app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'App').glob('*.swift')) + shared + common_c
packet_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'PacketTunnel').glob('*.swift')) + shared + common_c
if WIREGUARD:
    packet_sources += sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Vendor/WireGuard/Sources/WireGuardKit').glob('*.swift'))
    packet_sources += sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Vendor/WireGuard/Sources/WireGuardKitC').glob('*.c'))
    packet_sources += ['Vendor/WireGuard/Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift']
configs = [
    ('TunnelMasterVPN','app','Configuration/App-Info.plist',app_sources,['Shared/PrivacyInfo.xcprivacy']),
    ('TunnelMasterVPNPacket','extension','Configuration/Packet-Info.plist',packet_sources,['Shared/PrivacyInfo.xcprivacy'])
]

for name,kind,plist,sources,resources in configs:
    product=add('product:'+name,'PBXFileReference',explicitFileType='wrapper.application' if kind=='app' else 'wrapper.app-extension',includeInIndex=0,path=name+('.app' if kind=='app' else '.appex'),sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    phases=[]
    phases.append(add('sources:'+name,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in sources],runOnlyForDeploymentPostprocessing=0))
    phases.append(add('resources:'+name,'PBXResourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in resources],runOnlyForDeploymentPostprocessing=0))
    phases.append(add('frameworks:'+name,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0))
    settings={'PRODUCT_NAME':'$(TARGET_NAME)',
        'PRODUCT_BUNDLE_IDENTIFIER':'$(TD_BUNDLE_PREFIX)' + ('.PacketTunnel' if kind!='app' else ''),
        'INFOPLIST_FILE':plist,'GENERATE_INFOPLIST_FILE':'NO',
        'CODE_SIGN_ENTITLEMENTS':'Configuration/App.entitlements' if kind=='app' else 'Configuration/Packet.entitlements',
        'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
        'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'] + (['@executable_path/../../Frameworks'] if kind!='app' else []),
        'SKIP_INSTALL':'NO' if kind=='app' else 'YES','APPLICATION_EXTENSION_API_ONLY':'NO' if kind=='app' else 'YES',
        'SWIFT_OBJC_BRIDGING_HEADER':'Shared/Bridge.h' if kind=='app' else 'Configuration/PacketBridge.h',
        'HEADER_SEARCH_PATHS':['$(inherited)','$(SRCROOT)/Shared','$(SRCROOT)/Vendor/PCRE2/src'],
        'GCC_PREPROCESSOR_DEFINITIONS':['$(inherited)','HAVE_CONFIG_H=1','PCRE2_CODE_UNIT_WIDTH=8'],
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited)' + (' TUNNELDOJO_WIREGUARD' if WIREGUARD else '')}
    if WIREGUARD:
        settings['GCC_PREPROCESSOR_DEFINITIONS'].append('TUNNELDOJO_WIREGUARD=1')
        if kind!='app':
            settings['LIBRARY_SEARCH_PATHS']=['$(inherited)','$(BUILT_PRODUCTS_DIR)']
            settings['OTHER_LDFLAGS']=['$(inherited)','-lwg-go']
            settings['HEADER_SEARCH_PATHS'] += ['$(SRCROOT)/Vendor/WireGuard/Sources/WireGuardKitC','$(SRCROOT)/Vendor/WireGuard/Sources/WireGuardKitGo']
            phases.insert(0,add('go-build','PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=[],outputPaths=['$(BUILT_PRODUCTS_DIR)/libwg-go.a'],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/bash',shellScript='"$SRCROOT/Scripts/build-wireguard.sh"',name='Build WireGuard Go bridge'))
    cfg=configlist('config:'+name,settings)
    target=add('target:'+name,'PBXNativeTarget',buildConfigurationList=cfg,buildPhases=phases,buildRules=[],dependencies=[],name=name,productName=name,productReference=product,productType='com.apple.product-type.application' if kind=='app' else 'com.apple.product-type.app-extension')
    targets.append(target)

projectid=oid('project')
embeds=[]
deps=[]
for target,product in zip(targets[1:],products[1:]):
    name=objects[target]['name']
    proxy=add('proxy:'+name,'PBXContainerItemProxy',containerPortal=projectid,proxyType=1,remoteGlobalIDString=target,remoteInfo=name)
    deps.append(add('dependency:'+name,'PBXTargetDependency',target=target,targetProxy=proxy))
    embeds.append(add('embed:'+name,'PBXBuildFile',fileRef=product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']}))
embedphase=add('embed:phase','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=embeds,name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
objects[targets[0]]['buildPhases'].append(embedphase)
objects[targets[0]]['dependencies']=deps
for p in (ROOT/'Configuration').iterdir():
    if p.is_file():
        ref(str(p.relative_to(ROOT)))
for p in ['README.md','Docs/Testing.md','Docs/Release.md']:
    ref(p)
productgroup=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
fileids=[key for key,value in objects.items() if value['isa']=='PBXFileReference' and value.get('sourceTree')=='<group>']
rootgroup=add('rootgroup','PBXGroup',children=fileids+[productgroup],sourceTree='<group>')
projectconfig=configlist('projectconfig',{'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','CLANG_WARN_UNGUARDED_AVAILABILITY':'YES_AGGRESSIVE','GCC_WARN_UNUSED_VARIABLE':'YES','GCC_WARN_UNUSED_FUNCTION':'YES','ENABLE_STRICT_OBJC_MSGSEND':'YES'},True)
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'1600','LastUpgradeCheck':'1600','TargetAttributes':{t:{'CreatedOnToolsVersion':'16.0','ProvisioningStyle':'Automatic','SystemCapabilities':{'com.apple.NetworkExtensions':{'enabled':1}}} for t in targets}},buildConfigurationList=projectconfig,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=rootgroup,packageReferences=[],productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=targets)

def atom(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else json.dumps(value, ensure_ascii=False)

def encode(value, indent=0):
    pad='\t'*indent
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(indent+1)+atom(str(k))+ ' = '+encode(v,indent+1)+';\n' for k,v in value.items())+pad+'}'
    if isinstance(value,list):
        return '(\n'+''.join('\t'*(indent+1)+encode(v,indent+1)+',\n' for v in value)+pad+')'
    if isinstance(value,int):
        return str(value)
    return atom(value)

project=ROOT/'TunnelMasterVPN.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':projectid})+'\n')
scheme_dir=project/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
for scheme_name,storekit in [('TunnelMasterVPN',False),('TunnelMasterVPN-StoreKit',True)]:
    refxml=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="TunnelMasterVPN.app" BlueprintName="TunnelMasterVPN" ReferencedContainer="container:TunnelMasterVPN.xcodeproj"/>'
    testing='<StoreKitConfigurationFileReference identifier="../../../Configuration/TunnelMasterVPN.storekit"/>' if storekit else ''
    xml=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{refxml}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{refxml}</BuildableProductRunnable>
    {testing}
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{refxml}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (scheme_dir/(scheme_name+'.xcscheme')).write_text(xml)
print('Generated TunnelMasterVPN.xcodeproj with',len(targets),'targets.')
