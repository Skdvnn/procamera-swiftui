#!/usr/bin/env python3
"""Patch ProCamera.xcodeproj to embed Widget + LockedCameraCapture extensions."""
from pathlib import Path

PBX = Path("/workspace/ProCamera.xcodeproj/project.pbxproj")
text = PBX.read_text()

# Idempotent: skip if already patched
if "ShutterWidgets" in text and "ShutterCaptureExtension" in text and "A1000030WWWWWWWW00000001" in text:
    print("pbxproj already has extension targets")
    raise SystemExit(0)

# --- Insert build file / file ref entries before End sections ---

build_files = """
		A1000027GGGGGGGG00000001 /* ShutterDeepLink.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000027GGGGGGGG00000002 /* ShutterDeepLink.swift */; };
		A1000028GGGGGGGG00000001 /* ShutterCaptureContext.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000028GGGGGGGG00000002 /* ShutterCaptureContext.swift */; };
		A1000029GGGGGGGG00000001 /* ShutterAppIntents.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000029GGGGGGGG00000002 /* ShutterAppIntents.swift */; };
		A1000030WWWWWWWW00000001 /* ShutterWidgetsBundle.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000030WWWWWWWW00000002 /* ShutterWidgetsBundle.swift */; };
		A1000031WWWWWWWW00000001 /* ShutterDeepLink.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000027GGGGGGGG00000002 /* ShutterDeepLink.swift */; };
		A1000032WWWWWWWW00000001 /* ShutterCaptureContext.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000028GGGGGGGG00000002 /* ShutterCaptureContext.swift */; };
		A1000033CCCCCCC000000001 /* ShutterCaptureExtension.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000033CCCCCCC000000002 /* ShutterCaptureExtension.swift */; };
		A1000034CCCCCCC000000001 /* ShutterDeepLink.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000027GGGGGGGG00000002 /* ShutterDeepLink.swift */; };
		A1000035CCCCCCC000000001 /* ShutterCaptureContext.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1000028GGGGGGGG00000002 /* ShutterCaptureContext.swift */; };
		A1000036EEEEEEEE00000001 /* ShutterWidgets.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = A1000036EEEEEEEE00000002 /* ShutterWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		A1000037EEEEEEEE00000001 /* ShutterCaptureExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = A1000037EEEEEEEE00000002 /* ShutterCaptureExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
"""

file_refs = """
		A1000027GGGGGGGG00000002 /* ShutterDeepLink.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShutterDeepLink.swift; sourceTree = "<group>"; };
		A1000028GGGGGGGG00000002 /* ShutterCaptureContext.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShutterCaptureContext.swift; sourceTree = "<group>"; };
		A1000029GGGGGGGG00000002 /* ShutterAppIntents.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShutterAppIntents.swift; sourceTree = "<group>"; };
		A1000030WWWWWWWW00000002 /* ShutterWidgetsBundle.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShutterWidgetsBundle.swift; sourceTree = "<group>"; };
		A1000030WWWWWWWW00000003 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		A1000030WWWWWWWW00000004 /* ShutterWidgets.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShutterWidgets.entitlements; sourceTree = "<group>"; };
		A1000033CCCCCCC000000002 /* ShutterCaptureExtension.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShutterCaptureExtension.swift; sourceTree = "<group>"; };
		A1000033CCCCCCC000000003 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		A1000033CCCCCCC000000004 /* ShutterCaptureExtension.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShutterCaptureExtension.entitlements; sourceTree = "<group>"; };
		A1000036EEEEEEEE00000002 /* ShutterWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShutterWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		A1000037EEEEEEEE00000002 /* ShutterCaptureExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShutterCaptureExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
"""

text = text.replace("/* End PBXBuildFile section */", build_files + "/* End PBXBuildFile section */")
text = text.replace("/* End PBXFileReference section */", file_refs + "/* End PBXFileReference section */")

# Groups
group_widgets = """
		A10000W0WWWWWWWW00000001 /* ShutterWidgets */ = {
			isa = PBXGroup;
			children = (
				A1000030WWWWWWWW00000002 /* ShutterWidgetsBundle.swift */,
				A1000030WWWWWWWW00000003 /* Info.plist */,
				A1000030WWWWWWWW00000004 /* ShutterWidgets.entitlements */,
			);
			path = ShutterWidgets;
			sourceTree = "<group>";
		};
		A10000C0CCCCCCC000000001 /* ShutterCaptureExtension */ = {
			isa = PBXGroup;
			children = (
				A1000033CCCCCCC000000002 /* ShutterCaptureExtension.swift */,
				A1000033CCCCCCC000000003 /* Info.plist */,
				A1000033CCCCCCC000000004 /* ShutterCaptureExtension.entitlements */,
			);
			path = ShutterCaptureExtension;
			sourceTree = "<group>";
		};
"""

text = text.replace("/* Begin PBXGroup section */", "/* Begin PBXGroup section */" + group_widgets)

# Add to main group children
text = text.replace(
    "\t\t\t\tA1000026FFFFFFFF00000002 /* LookRecipes.swift */,\n",
    "\t\t\t\tA1000026FFFFFFFF00000002 /* LookRecipes.swift */,\n"
    "\t\t\t\tA1000027GGGGGGGG00000002 /* ShutterDeepLink.swift */,\n"
    "\t\t\t\tA1000028GGGGGGGG00000002 /* ShutterCaptureContext.swift */,\n"
    "\t\t\t\tA1000029GGGGGGGG00000002 /* ShutterAppIntents.swift */,\n"
    "\t\t\t\tA10000W0WWWWWWWW00000001 /* ShutterWidgets */,\n"
    "\t\t\t\tA10000C0CCCCCCC000000001 /* ShutterCaptureExtension */,\n",
)

# Products
text = text.replace(
    "\t\t\t\tA1000010AAAAAAAA00000010 /* ProCamera.app */,\n",
    "\t\t\t\tA1000010AAAAAAAA00000010 /* ProCamera.app */,\n"
    "\t\t\t\tA1000036EEEEEEEE00000002 /* ShutterWidgets.appex */,\n"
    "\t\t\t\tA1000037EEEEEEEE00000002 /* ShutterCaptureExtension.appex */,\n",
)

# Embed phase + frameworks for extensions
embed_phase = """
/* Begin PBXCopyFilesBuildPhase section */
		A10000E0EEEEEEEE00000001 /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				A1000036EEEEEEEE00000001 /* ShutterWidgets.appex in Embed Foundation Extensions */,
				A1000037EEEEEEEE00000001 /* ShutterCaptureExtension.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

"""

text = text.replace("/* Begin PBXFrameworksBuildPhase section */", embed_phase + "/* Begin PBXFrameworksBuildPhase section */")

frameworks_ext = """
		A10000W1WWWWWWWW00000001 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000C1CCCCCCC000000001 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
text = text.replace("/* End PBXFrameworksBuildPhase section */", frameworks_ext + "/* End PBXFrameworksBuildPhase section */")

# Update main target build phases + dependencies
text = text.replace(
    """\t\t\tbuildPhases = (
\t\t\t\tA1000041AAAAAAAA00000041 /* Sources */,
\t\t\t\tA1000020AAAAAAAA00000020 /* Frameworks */,
\t\t\t\tA1000042AAAAAAAA00000042 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = ProCamera;
""",
    """\t\t\tbuildPhases = (
\t\t\t\tA1000041AAAAAAAA00000041 /* Sources */,
\t\t\t\tA1000020AAAAAAAA00000020 /* Frameworks */,
\t\t\t\tA1000042AAAAAAAA00000042 /* Resources */,
\t\t\t\tA10000E0EEEEEEEE00000001 /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\tA10000D0WWWWWWWW00000001 /* PBXTargetDependency */,
\t\t\t\tA10000D1CCCCCCC000000001 /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = ProCamera;
""",
)

# Native targets for extensions
native_targets = """
		A10000W2WWWWWWWW00000001 /* ShutterWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000W5WWWWWWWW00000001 /* Build configuration list for PBXNativeTarget "ShutterWidgets" */;
			buildPhases = (
				A10000W3WWWWWWWW00000001 /* Sources */,
				A10000W1WWWWWWWW00000001 /* Frameworks */,
				A10000W4WWWWWWWW00000001 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ShutterWidgets;
			productName = ShutterWidgets;
			productReference = A1000036EEEEEEEE00000002 /* ShutterWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};
		A10000C2CCCCCCC000000001 /* ShutterCaptureExtension */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000C5CCCCCCC000000001 /* Build configuration list for PBXNativeTarget "ShutterCaptureExtension" */;
			buildPhases = (
				A10000C3CCCCCCC000000001 /* Sources */,
				A10000C1CCCCCCC000000001 /* Frameworks */,
				A10000C4CCCCCCC000000001 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ShutterCaptureExtension;
			productName = ShutterCaptureExtension;
			productReference = A1000037EEEEEEEE00000002 /* ShutterCaptureExtension.appex */;
			productType = "com.apple.product-type.app-extension";
		};
"""
text = text.replace("/* End PBXNativeTarget section */", native_targets + "/* End PBXNativeTarget section */")

# Project targets list + attributes
text = text.replace(
    """\t\t\t\tTargetAttributes = {
\t\t\t\t\tA1000040AAAAAAAA00000040 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t};
\t\t\t\t};
""",
    """\t\t\t\tTargetAttributes = {
\t\t\t\t\tA1000040AAAAAAAA00000040 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t};
\t\t\t\t\tA10000W2WWWWWWWW00000001 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t};
\t\t\t\t\tA10000C2CCCCCCC000000001 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;
\t\t\t\t\t};
\t\t\t\t};
""",
)

text = text.replace(
    """\t\t\ttargets = (
\t\t\t\tA1000040AAAAAAAA00000040 /* ProCamera */,
\t\t\t);
""",
    """\t\t\ttargets = (
\t\t\t\tA1000040AAAAAAAA00000040 /* ProCamera */,
\t\t\t\tA10000W2WWWWWWWW00000001 /* ShutterWidgets */,
\t\t\t\tA10000C2CCCCCCC000000001 /* ShutterCaptureExtension */,
\t\t\t);
""",
)

# Sources / resources for extensions + main app new files
sources = """
		A10000W3WWWWWWWW00000001 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A1000030WWWWWWWW00000001 /* ShutterWidgetsBundle.swift in Sources */,
				A1000031WWWWWWWW00000001 /* ShutterDeepLink.swift in Sources */,
				A1000032WWWWWWWW00000001 /* ShutterCaptureContext.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000C3CCCCCCC000000001 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A1000033CCCCCCC000000001 /* ShutterCaptureExtension.swift in Sources */,
				A1000034CCCCCCC000000001 /* ShutterDeepLink.swift in Sources */,
				A1000035CCCCCCC000000001 /* ShutterCaptureContext.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
text = text.replace("/* End PBXSourcesBuildPhase section */", sources + "/* End PBXSourcesBuildPhase section */")

resources = """
		A10000W4WWWWWWWW00000001 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000C4CCCCCCC000000001 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""
text = text.replace("/* End PBXResourcesBuildPhase section */", resources + "/* End PBXResourcesBuildPhase section */")

# Add shared sources to main app
text = text.replace(
    "\t\t\t\tA1000026FFFFFFFF00000001 /* LookRecipes.swift in Sources */,\n",
    "\t\t\t\tA1000026FFFFFFFF00000001 /* LookRecipes.swift in Sources */,\n"
    "\t\t\t\tA1000027GGGGGGGG00000001 /* ShutterDeepLink.swift in Sources */,\n"
    "\t\t\t\tA1000028GGGGGGGG00000001 /* ShutterCaptureContext.swift in Sources */,\n"
    "\t\t\t\tA1000029GGGGGGGG00000001 /* ShutterAppIntents.swift in Sources */,\n",
)

# Container item proxies + dependencies
proxies = """
/* Begin PBXContainerItemProxy section */
		A10000P0WWWWWWWW00000001 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A1000060AAAAAAAA00000060 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A10000W2WWWWWWWW00000001;
			remoteInfo = ShutterWidgets;
		};
		A10000P1CCCCCCC000000001 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A1000060AAAAAAAA00000060 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A10000C2CCCCCCC000000001;
			remoteInfo = ShutterCaptureExtension;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		A10000D0WWWWWWWW00000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A10000W2WWWWWWWW00000001 /* ShutterWidgets */;
			targetProxy = A10000P0WWWWWWWW00000001 /* PBXContainerItemProxy */;
		};
		A10000D1CCCCCCC000000001 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A10000C2CCCCCCC000000001 /* ShutterCaptureExtension */;
			targetProxy = A10000P1CCCCCCC000000001 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

"""
text = text.replace("/* Begin XCBuildConfiguration section */", proxies + "/* Begin XCBuildConfiguration section */")

# Build configurations for extensions (Debug/Release)
ext_configs = """
		A10000W6WWWWWWWW00000001 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShutterWidgets/ShutterWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 25;
				DEVELOPMENT_TEAM = 9DKG694QL7;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShutterWidgets/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.skylardann.filmcam.dev.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		A10000W7WWWWWWWW00000001 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShutterWidgets/ShutterWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 25;
				DEVELOPMENT_TEAM = 9DKG694QL7;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShutterWidgets/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.skylardann.filmcam.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		A10000C6CCCCCCC000000001 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShutterCaptureExtension/ShutterCaptureExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 25;
				DEVELOPMENT_TEAM = 9DKG694QL7;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShutterCaptureExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.skylardann.filmcam.dev.capture;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		A10000C7CCCCCCC000000001 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShutterCaptureExtension/ShutterCaptureExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 25;
				DEVELOPMENT_TEAM = 9DKG694QL7;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShutterCaptureExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.skylardann.filmcam.capture;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
"""

text = text.replace("/* End XCBuildConfiguration section */", ext_configs + "/* End XCBuildConfiguration section */")

config_lists = """
		A10000W5WWWWWWWW00000001 /* Build configuration list for PBXNativeTarget "ShutterWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10000W6WWWWWWWW00000001 /* Debug */,
				A10000W7WWWWWWWW00000001 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10000C5CCCCCCC000000001 /* Build configuration list for PBXNativeTarget "ShutterCaptureExtension" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10000C6CCCCCCC000000001 /* Debug */,
				A10000C7CCCCCCC000000001 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
"""
text = text.replace("/* End XCConfigurationList section */", config_lists + "/* End XCConfigurationList section */")

PBX.write_text(text)
print("Patched pbxproj with ShutterWidgets + ShutterCaptureExtension")
