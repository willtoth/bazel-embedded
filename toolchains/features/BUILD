load(":defs.bzl", "print_all_features")

print_all_features(
    name = "print_all_features",
    is_windows = select({
        "@bazel_tools//src/conditions:host_windows": True,
        "//conditions:default": False,
    }),
)
