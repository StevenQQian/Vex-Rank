#!/usr/bin/env python3
"""Generate MakapakaScout.xcodeproj.

The simulator build uses swiftc directly, which is enough to run but cannot
be code signed or installed on a phone. Signing needs a real project so that
xcodebuild can talk to the developer account and provision the bundle id, so
the project is generated from the sources on disk rather than kept by hand and
left to drift.
"""
import os, re, uuid, pathlib

ROOT = pathlib.Path(__file__).parent
PROJECT = ROOT / "MakapakaScout.xcodeproj"
BUNDLE_ID = "com.vexrank.app"
TEAM = "JJRCKVACCR"

def oid(seed):
    return uuid.uuid5(uuid.NAMESPACE_URL, seed).hex[:24].upper()

# Only the app's own sources. VEXRankKit comes in as the local Swift package
# it already is, so the module the app imports actually exists and the package
# stays the single definition of the kit rather than being copied in here.
sources = sorted([p for p in (ROOT / "App").glob("*.swift")])
# Tournament mode's Live Activity: Shared/ is built into both the app and the
# widget extension, Widget/ into the extension alone.
shared = sorted((ROOT / "Shared").glob("*.swift"))
widget = sorted((ROOT / "Widget").glob("*.swift"))
# The app's icons, which the Live Activity draws too. Built into the
# extension from the kit's own files rather than linking the kit.
widget_kit = [ROOT / "VEXRankKit/Sources/VEXRankKit" / name for name in ("StrokeIcons.swift", "StrokePath.swift")]
assets = ROOT / "App/Assets.xcassets"

file_refs, build_files, group_children = [], [], []
app_sources, widget_sources = [], []
for path in sources + shared + widget + widget_kit:
    rel = path.relative_to(ROOT).as_posix()
    fid = oid("file:" + rel)
    file_refs.append(f'\t\t{fid} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{path.name}"; path = "{rel}"; sourceTree = "<group>"; }};')
    group_children.append(f'\t\t\t\t{fid} /* {path.name} */,')
    # One build file per target a source is compiled into.
    for target, into in (("app", app_sources), ("widget", widget_sources)):
        # The app gets the kit files through the package, not as sources.
        if (target == "app" and path in widget + widget_kit) or (target == "widget" and path in sources):
            continue
        bid = oid("build:" + rel) if target == "app" else oid(f"build:{target}:" + rel)
        build_files.append(f'\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {path.name} */; }};')
        into.append(bid)

resource_phase_files, resource_refs = [], []
if assets.exists():
    rel = assets.relative_to(ROOT).as_posix()
    fid, bid = oid("file:assets"), oid("build:assets")
    file_refs.append(f'\t\t{fid} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = Assets.xcassets; path = "{rel}"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{bid} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* Assets.xcassets */; }};')
    group_children.append(f'\t\t\t\t{fid} /* Assets.xcassets */,')
    resource_refs.append(f'\t\t\t\t{bid} /* Assets.xcassets in Resources */,')

# The privacy manifest: required-reason APIs the app uses (UserDefaults).
privacy = ROOT / "App/PrivacyInfo.xcprivacy"
if privacy.exists():
    rel = privacy.relative_to(ROOT).as_posix()
    fid, bid = oid("file:privacy"), oid("build:privacy")
    file_refs.append(f'\t\t{fid} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; name = PrivacyInfo.xcprivacy; path = "{rel}"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{bid} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* PrivacyInfo.xcprivacy */; }};')
    group_children.append(f'\t\t\t\t{fid} /* PrivacyInfo.xcprivacy */,')
    resource_refs.append(f'\t\t\t\t{bid} /* PrivacyInfo.xcprivacy in Resources */,')

ids = {k: oid(k) for k in ["project","target","group","productsGroup","product","sources","resources","frameworks",
                            "cfgListProject","cfgListTarget","debugProject","releaseProject","debugTarget","releaseTarget",
                            "packageRef","productDep","packageBuildFile",
                            "wTarget","wProduct","wSources","wFrameworks","wCfgList","wDebug","wRelease",
                            "embedPhase","embedBuildFile","wDependency","wProxy"]}
build_files.append(f'\t\t{ids["embedBuildFile"]} /* TournamentWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ids["wProduct"]} /* TournamentWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')

build_files.append(f'\t\t{ids["packageBuildFile"]} /* VEXRankKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids["productDep"]} /* VEXRankKit */; }};')
# Xcode also lists the package folder itself in the navigator; without it the
# local package is declared but never located.
file_refs.append(f'\t\t{oid("file:package")} /* VEXRankKit */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; name = VEXRankKit; path = VEXRankKit; sourceTree = "<group>"; }};')
group_children.append(f'\t\t\t\t{oid("file:package")} /* VEXRankKit */,')
# Build settings that live in a file, so a local-only one (the events.vex
# token, in the git-ignored Secrets.xcconfig) can be included without editing
# the project. See App/Config/Base.xcconfig.
base_config = oid("file:App/Config/Base.xcconfig")
file_refs.append(f'\t\t{base_config} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = Base.xcconfig; path = "App/Config/Base.xcconfig"; sourceTree = "<group>"; }};')
group_children.append(f'\t\t\t\t{base_config} /* Base.xcconfig */,')

SETTINGS_TARGET = f'''
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 5;
\t\t\t\tDEVELOPMENT_TEAM = {TEAM};
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = App/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Makapaka Scout";
\t\t\t\tINFOPLIST_KEY_CFBundleName = "Makapaka Scout";\n\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;\n\t\t\t\tINFOPLIST_KEY_UILaunchScreen_BackgroundColor = LaunchBackground;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 1.1;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = MakapakaScout;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
'''

# The extension's versions must match the app's or the phone refuses to
# install the pair.
SETTINGS_WIDGET = f'''
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 5;
\t\t\t\tDEVELOPMENT_TEAM = {TEAM};
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Widget/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Tournament mode";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
\t\t\t\tMARKETING_VERSION = 1.1;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.TournamentWidget;
\t\t\t\tPRODUCT_NAME = TournamentWidget;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
'''

pbx = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 60;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
\t\t{ids["product"]} /* MakapakaScout.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MakapakaScout.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{ids["wProduct"]} /* TournamentWidget.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TournamentWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXContainerItemProxy section */
\t\t{ids["wProxy"]} = {{isa = PBXContainerItemProxy; containerPortal = {ids["project"]}; proxyType = 1; remoteGlobalIDString = {ids["wTarget"]}; remoteInfo = TournamentWidget; }};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{ids["embedPhase"]} /* Embed Foundation Extensions */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ( {ids["embedBuildFile"]}, ); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ids["frameworks"]} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{ids["wFrameworks"]} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ids["group"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(group_children)}
\t\t\t\t{ids["productsGroup"]} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ids["productsGroup"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ( {ids["product"]} /* MakapakaScout.app */, {ids["wProduct"]} /* TournamentWidget.appex */, );
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ids["target"]} /* MakapakaScout */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids["cfgListTarget"]};
\t\t\tbuildPhases = ( {ids["sources"]}, {ids["frameworks"]}, {ids["resources"]}, {ids["embedPhase"]}, );
\t\t\tbuildRules = ();
\t\t\tdependencies = ( {ids["wDependency"]}, );
\t\t\tname = MakapakaScout;
\t\t\tproductName = MakapakaScout;
\t\t\tproductReference = {ids["product"]} /* MakapakaScout.app */;
\t\t\tpackageProductDependencies = ( {ids["productDep"]} /* VEXRankKit */, );\n\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{ids["wTarget"]} /* TournamentWidget */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids["wCfgList"]};
\t\t\tbuildPhases = ( {ids["wSources"]}, {ids["wFrameworks"]}, );
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = TournamentWidget;
\t\t\tproductName = TournamentWidget;
\t\t\tproductReference = {ids["wProduct"]} /* TournamentWidget.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXTargetDependency section */
\t\t{ids["wDependency"]} = {{isa = PBXTargetDependency; target = {ids["wTarget"]} /* TournamentWidget */; targetProxy = {ids["wProxy"]}; }};
/* End PBXTargetDependency section */

/* Begin PBXProject section */
\t\t{ids["project"]} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1610;
\t\t\t\tLastUpgradeCheck = 1610;
\t\t\t\tTargetAttributes = {{ {ids["target"]} = {{ CreatedOnToolsVersion = 16.1; }}; {ids["wTarget"]} = {{ CreatedOnToolsVersion = 16.1; }}; }};
\t\t\t}};
\t\t\tbuildConfigurationList = {ids["cfgListProject"]};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = ( en, Base, );
\t\t\tmainGroup = {ids["group"]};
\t\t\tproductRefGroup = {ids["productsGroup"]};
\t\t\tpackageReferences = ( {ids["packageRef"]} /* XCLocalSwiftPackageReference "VEXRankKit" */, );\n\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = ( {ids["target"]} /* MakapakaScout */, {ids["wTarget"]} /* TournamentWidget */, );
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ids["resources"]} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(resource_refs)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ids["sources"]} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f'\t\t\t\t{b},' for b in app_sources)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{ids["wSources"]} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f'\t\t\t\t{b},' for b in widget_sources)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{ids["debugProject"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["releaseProject"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ids["debugTarget"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {base_config} /* Base.xcconfig */;
\t\t\tbuildSettings = {{{SETTINGS_TARGET}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["releaseTarget"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {base_config} /* Base.xcconfig */;
\t\t\tbuildSettings = {{{SETTINGS_TARGET}\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ids["wDebug"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{SETTINGS_WIDGET}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids["wRelease"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{SETTINGS_WIDGET}\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ids["cfgListProject"]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( {ids["debugProject"]} /* Debug */, {ids["releaseProject"]} /* Release */, );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ids["cfgListTarget"]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( {ids["debugTarget"]} /* Debug */, {ids["releaseTarget"]} /* Release */, );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ids["wCfgList"]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ( {ids["wDebug"]} /* Debug */, {ids["wRelease"]} /* Release */, );
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{ids["packageRef"]} /* XCLocalSwiftPackageReference "VEXRankKit" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = VEXRankKit;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{ids["productDep"]} /* VEXRankKit */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = VEXRankKit;
		}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {ids["project"]};
}}
'''

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text(pbx)
print(f"wrote {PROJECT}/project.pbxproj with {len(sources) + len(shared)} app and {len(widget) + len(shared) + len(widget_kit)} widget sources")
