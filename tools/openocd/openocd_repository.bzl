def _get_platform_specific_config(os_name):
    _WINDOWS = {
        "sha256": "5cba78c08ad03aa38549e94186cbb4ec34c384565a40a6652715577e4f1a458f",
        "prefix": "xpack-openocd-0.12.0-1",
        "url": "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-1/xpack-openocd-0.12.0-1-win32-x64.zip",
    }
    _PLATFORM_SPECIFIC_CONFIGS = {
        "mac os x": {
            "sha256": "ca569b6bfd9b3cd87a5bc88b3a33a5c4fe854be3cf95a3dcda1c194e8da9d7bb",
            "prefix": "xpack-openocd-0.12.0-1",
            "url": "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-1/xpack-openocd-0.12.0-1-darwin-x64.tar.gz",
        },
        "linux": {
            "sha256": "940f22eccddb0946b69149d227948f77d5917a2c5f1ab68e5d84d614c2ceed20",
            "prefix": "xpack-openocd-0.12.0-1",
            "url": "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v0.12.0-1/xpack-openocd-0.12.0-1-linux-x64.tar.gz",
        },
        "windows": _WINDOWS,
        "windows server 2019": _WINDOWS,
        "windows 10": _WINDOWS,
    }
    if os_name not in _PLATFORM_SPECIFIC_CONFIGS.keys():
        fail("OS configuration not available for:", os_name)
    return _PLATFORM_SPECIFIC_CONFIGS[os_name]

def _openocd_repository_impl(repository_ctx):
    tar_name = "openocd.tgz"

    config = _get_platform_specific_config(repository_ctx.os.name)
    prefix = config["prefix"]
    repository_ctx.download_and_extract(
        url = config["url"],
        sha256 = config["sha256"],
        stripPrefix = prefix,
    )

    # Bazel does not support unicode character targets in download and extract, so extraction happens as a seperate step and files containing unicode characters are removed
    setup_script_template = """
    set -eux pipefail
    tar -zxvf {tar_name}
    # Remove files with unicode characters as bazel doesn't like them
    /bin/mv {prefix}/* ./
    /bin/rm -r  {tar_name}
    """
    executable_extension = ""
    if "windows" in repository_ctx.os.name:
        executable_extension = ".exe"
    repository_ctx.symlink("bin/openocd"+ executable_extension, "openocd" )

    repository_ctx.file(
        "BUILD",
        content = """
package(default_visibility = ["//visibility:public"])
exports_files(["openocd"])
""",
    )

openocd_repository = repository_rule(
    _openocd_repository_impl,
)

def openocd_deps():
    """ openocd_deps fetchs openocd from the xpack repositories
    """
    openocd_repository(name = "com_openocd")
