from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
project = root / 'LocalCopilot.xcodeproj'
project.mkdir(exist_ok=True)
def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
objects = []
def obj(key, text): objects.append(f'{uid(key)} = {{ {text} }};'); return uid(key)
files = []
builds = []
for file in sorted((root/'App').rglob('*.swift')):
    relative = file.relative_to(root).as_posix()
    ref = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = "<group>";')
    build = obj('build-'+relative, f'isa = PBXBuildFile; fileRef = {ref};')
    files.append(ref); builds.append(build)
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Questionio.app; sourceTree = BUILT_PRODUCTS_DIR;')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
dep = obj('dep', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = LocalCopilotCore;')
depBuild = obj('depbuild', f'isa = PBXBuildFile; productRef = {dep};')
sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({depBuild},); runOnlyForDeploymentPostprocessing = 0;')
renderer = obj('renderer', 'isa = PBXFileReference; lastKnownFileType = folder; path = "Resources/AnswerRenderer"; sourceTree = "<group>";')
files.append(renderer)
rendererBuild = obj('rendererbuild', f'isa = PBXBuildFile; fileRef = {renderer};')
icon = obj('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/Questionio.icns; sourceTree = \"<group>\";')
files.append(icon)
iconBuild = obj('iconbuild', f'isa = PBXBuildFile; fileRef = {icon};')
resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({rendererBuild},{iconBuild},); runOnlyForDeploymentPostprocessing = 0;')
products = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = obj('group', f'isa = PBXGroup; children = ({",".join(files)},{products},); sourceTree = "<group>";')
def configs(prefix, settings):
    ids=[]
    for name in ['Debug','Release']:
        s=dict(settings)
        s['SWIFT_OPTIMIZATION_LEVEL'] = '"-Onone"' if name=='Debug' else '"-O"'
        if name=='Release': s['SWIFT_COMPILATION_MODE']='wholemodule'
        ids.append(obj(prefix+name, 'isa = XCBuildConfiguration; buildSettings = {' + ''.join(f'{k} = {v};' for k,v in s.items()) + f'}}; name = {name};'))
    return obj(prefix+'list', f'isa = XCConfigurationList; buildConfigurations = ({",".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projconfig = configs('project', {'MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','ARCHS':'arm64','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES'})
targetconfig = configs('target', {'PRODUCT_NAME':'Questionio','PRODUCT_BUNDLE_IDENTIFIER':'local.localcopilot.desktop','INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_IDENTITY':'"-"','CODE_SIGN_STYLE':'Manual','ENABLE_APP_SANDBOX':'NO','ENABLE_HARDENED_RUNTIME':'NO','COMBINE_HIDPI_IMAGES':'YES','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/../Frameworks"'})
target=obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {targetconfig}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = LocalCopilot; packageProductDependencies = ({dep},); productName = LocalCopilot; productReference = {product}; productType = "com.apple.product-type.application";')
proj=obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {projconfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {proj}; }}\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'LocalCopilot.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Questionio.app" BlueprintName="LocalCopilot" ReferencedContainer="container:LocalCopilot.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Questionio.app" BlueprintName="LocalCopilot" ReferencedContainer="container:LocalCopilot.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)
