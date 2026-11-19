load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
]

sgsrcs = [
    "//Swiftgram/SGStatus:SGStatus"
]

swift_library(
    name = "TelegramUIPreferences",
    module_name = "TelegramUIPreferences",
    srcs = sgsrcs + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
