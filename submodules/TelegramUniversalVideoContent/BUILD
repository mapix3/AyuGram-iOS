load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
sgsrc = [
    "//Swiftgram/SGExternalVideoPlayer:SGExternalVideoPlayer",
]


swift_library(
    name = "TelegramUniversalVideoContent",
    module_name = "TelegramUniversalVideoContent",
    srcs = sgsrc + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PhotoResources:PhotoResources",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/RadialStatusNode:RadialStatusNode",
        "//submodules/AppBundle:AppBundle",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/HLSPlayback:HLSPlayback",
    ],
    visibility = [
        "//visibility:public",
    ],
)
