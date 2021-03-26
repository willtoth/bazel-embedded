def _openocd_batch_wrapper_windows(script):
    # A bit of a hacky way to do this... The issue is Windows does not support
    # symlinks which does not work well for runfiles in particular. To enable them
    # the user must use Developer Mode, also not ideal. Instead:
    # 1) Use the generated 'symlink' (bazel just copies the exe) as a generic path to the root of openocd
    # 2) Open the MANIFEST file (non-standard format, beware for future versions)
    # 3) Find com_openocd and use the full path to the symlink
    # 4) In batch script, cd to base of tool and call bin/openocd.exe directly
    # TODO: 1) Make sure it can only find 1 com_openocd
    # TODO: 2) Notify the user if it is not found
    windows_script_prepend = """
@echo off

rem Call the SEARCH function on each line of MANIFEST file
for /f "tokens=*" %%a in (MANIFEST) do call :SEARCH %%a %%a

rem Look for the line that starts with com_openocd
:SEARCH
set str1=%1
if /i "%str1:~0,11%"=="com_openocd" goto FOUND

goto FAIL

rem Get the drive (di) and path(pi) to file passed by SEARCH and merge together
:FOUND
for %%i in (%2) do call :MAKEPATH %%~di%%~pi

goto EOF

rem cd to that path to run openocd in the correct directory
:MAKEPATH
cd %1


"""
    windows_script_append = """
goto EOF

:FAIL

:EOF

"""
    return windows_script_prepend + script + windows_script_append


def _openocd_flash_impl(ctx):
    # Write firmware to memory location 0x8000000 i.e. start of executable flash
    interface_config_string = ""
    for config in ctx.attr.interface_configs:
        interface_config_string = interface_config_string + " -f " + config
    chip_config_string = ""
    for config in ctx.attr.device_configs:
        chip_config_string = chip_config_string + " -f " + config
    transport_string = ""
    if ctx.attr.transport:
        transport_string = "-c \"transport select %s\"" % (ctx.attr.transport)
    script_template = """
{openocd} {interface_config_string} {transport_string} {chip_config_string} -c "adapter_khz {programmer_frequency}; program {firmware} verify reset exit {flash_offset}"
"""
    script = ctx.actions.declare_file("%s.sh" % ctx.label.name)

    script_content = script_template.format(
        openocd = ctx.file._openocd.short_path,
        interface_config_string = interface_config_string,
        chip_config_string = chip_config_string,
        firmware = ctx.file.image.short_path,
        flash_offset = ctx.attr.flash_offset,
        programmer_frequency = ctx.attr.programmer_frequency,
        transport_string = transport_string,
    )
    ctx.actions.write(script, script_content, is_executable = True)
    runfiles = ctx.runfiles(files = [ctx.file._openocd, ctx.file.image])
    return [DefaultInfo(executable = script, runfiles = runfiles)]

openocd_flash = rule(
    implementation = _openocd_flash_impl,
    doc = """
Used to flash a binary image to a microcontroller using openocd

Example:
    openocd_flash(
        name = "main_flash",
        device_configs = [
            "target/stm32h7x_dual_bank.cfg",
        ],
        image = ":main",
        interface_configs = [
            "interface/stlink.cfg",
        ],
        transport = "hla_swd",
    )
""",
    attrs = {
        "image": attr.label(
            doc = "Binary image to flash",
            mandatory = True,
            allow_single_file = True,
        ),
        "interface_configs": attr.string_list(
            doc = "openocd config path for interface, note that user defined configs are not supported at this time",
        ),
        "device_configs": attr.string_list(
            doc = "openocd config path for chip/board, note that user defined configs are not suppported at this time",
        ),
        "flash_offset": attr.string(
            doc = "The starting point of the flash memory",
            mandatory = False,
            default = "0x8000000",
        ),
        "_openocd": attr.label(
            doc = "Executable for flashing",
            default = "@com_openocd//:openocd",
            allow_single_file = True,
        ),
        "programmer_frequency": attr.string(
            doc = "The programming frequency of the adapter",
            default = "24000",
            mandatory = False,
        ),
        "transport": attr.string(
            doc = "Debugger transport interface",
            default = "hla_swd",
            mandatory = False,
        ),
    },
    executable = True,
)

def _openocd_debug_server_impl(ctx):
    is_windows = ctx.host_configuration.host_path_separator == ";"
    interface_config_string = ""
    for config in ctx.attr.interface_configs:
        interface_config_string = interface_config_string + " -f " + config
    chip_config_string = ""
    for config in ctx.attr.device_configs:
        chip_config_string = chip_config_string + " -f " + config
    transport_string = ""
    if ctx.attr.transport:
        transport_string = "-c \"transport select %s\"" % (ctx.attr.transport)
    script_template = """
{openocd} {interface_config_string} {transport_string} -c "adapter speed {programmer_frequency}" {chip_config_string}

"""

    script_content = ""
    if is_windows:
        script = ctx.actions.declare_file("%s.bat" % ctx.label.name)
        script_content = script_template.format(
            openocd = "\"bin/openocd.exe\"",
            interface_config_string = interface_config_string,
            chip_config_string = chip_config_string,
            programmer_frequency = ctx.attr.programmer_frequency,
            transport_string = transport_string,
        )
        script_content = _openocd_batch_wrapper_windows(script_content)
    else:
        script = ctx.actions.declare_file("%s.sh" % ctx.label.name)
        script_content = script_template.format(
            openocd = ctx.file._openocd.short_path,
            interface_config_string = interface_config_string,
            chip_config_string = chip_config_string,
            programmer_frequency = ctx.attr.programmer_frequency,
            transport_string = transport_string,
        )
    ctx.actions.write(script, script_content, is_executable = True)
    runfiles = ctx.runfiles(files = [ctx.file._openocd] )
    return [DefaultInfo(executable = script, runfiles = runfiles)]

openocd_debug_server = rule(
    implementation = _openocd_debug_server_impl,
    doc = """
Starts gdb debug server on TCP port :3333

Example:
    openocd_debug_server(
        name = "main_debug_server",
        device_configs = [
            "target/stm32h7x_dual_bank.cfg",
        ],
        interface_configs = [
            "interface/stlink.cfg",
        ],
        transport = "hla_swd",
    )
""",
    attrs = {
        "device_configs": attr.string_list(
            doc = "openocd config path for chip/board/interface",
        ),
        "interface_configs": attr.string_list(
            doc = "openocd config path for interface",
        ),
        "_openocd": attr.label(
            doc = "Executable for flashing using stlink",
            default = "@com_openocd//:openocd",
            allow_single_file = True,
        ),
        "programmer_frequency": attr.string(
            doc = "The programming frequency of the adapter",
            default = "3300",
            mandatory = False,
        ),
        "transport": attr.string(
            doc = "Debugger transport interface",
            mandatory = False,
        ),
    },
    executable = True,
)

def _openocd_execution_wrapper_impl(ctx):
    # Write firmware to memory location 0x8000000 i.e. start of executable flash
    interface_config_string = ""
    for config in ctx.attr.interface_configs:
        interface_config_string = interface_config_string + " -f " + config
    chip_config_string = ""
    for config in ctx.attr.device_configs:
        chip_config_string = chip_config_string + " -f " + config
    transport_string = ""
    if ctx.attr.transport:
        transport_string = "-c \"transport select %s\"" % (ctx.attr.transport)

    script_template = """
set -eo pipefail
ln -s $1 $1.elf
$RUNFILES_DIR/openocd {interface_config_string} {transport_string} {chip_config_string} -c "adapter_khz {programmer_frequency}; program $1 verify reset exit"
$RUNFILES_DIR/serial_wrapper -p {port} -f {fail_string} -s {success_string} -b {baud_rate}
"""
    script = ctx.actions.declare_file("%s.sh" % ctx.label.name)

    script_content = script_template.format(
        interface_config_string = interface_config_string,
        chip_config_string = chip_config_string,
        flash_offset = ctx.attr.flash_offset,
        programmer_frequency = ctx.attr.programmer_frequency,
        transport_string = transport_string,
        port = ctx.attr.port,
        fail_string = ctx.attr.fail_string,
        success_string = ctx.attr.success_string,
        baud_rate = ctx.attr.baud_rate,
    )
    ctx.actions.write(script, script_content, is_executable = True)
    runfiles = ctx.runfiles(
        files = [ctx.files._openocd[0], ctx.files._serial_wrapper[0]],
        root_symlinks = {"openocd": ctx.files._openocd[0], "serial_wrapper": ctx.files._serial_wrapper[0]},
    )
    return [DefaultInfo(executable = script, runfiles = runfiles)]

openocd_execution_wrapper = rule(
    implementation = _openocd_execution_wrapper_impl,
    doc = """
Starts gdb debug server on TCP port :3333

Example:
    openocd_execution_wrapper(
        name = "stm32h7",
        device_configs = [
            "target/stm32h7x_dual_bank.cfg",
        ],
        interface_configs = [
            "interface/stlink.cfg",
        ],
        transport = "hla_swd",
    )
""",
    attrs = {
        "device_configs": attr.string_list(
            doc = "openocd config path for chip/board/interface",
        ),
        "interface_configs": attr.string_list(
            doc = "openocd config path for interface",
        ),
        "_openocd": attr.label(
            doc = "Executable for flashing using stlink",
            default = "@com_openocd//:openocd",
            allow_single_file = True,
            cfg = "host",
        ),
        "_serial_wrapper": attr.label(
            doc = "Executable to wrap serial output to stdout with a given return code",
            default = "@bazel_embedded//tools/serial:serial_wrapper",
            allow_single_file = True,
            cfg = "host",
        ),
        "programmer_frequency": attr.string(
            doc = "The programming frequency of the adapter",
            default = "3300",
            mandatory = False,
        ),
        "transport": attr.string(
            doc = "Debugger transport interface",
            mandatory = False,
        ),
        "flash_offset": attr.string(
            doc = "The starting point of the flash memory",
            mandatory = False,
            default = "0x8000000",
        ),
        "fail_string": attr.string(
            doc = "When a line from the serial output contains this string exit the wrapper with a failure code",
            default = "",
        ),
        "success_string": attr.string(
            doc = "When a line from the serial output contains this string exit the wrapper with a success code",
            default = "",
        ),
        "port": attr.string(
            doc = "The serial port to monitor after uploading to the microcontroller",
            default = "/dev/ttyACM0",
        ),
        "baud_rate": attr.string(
            doc = "The baud rate that the serial port is operating at",
            default = "115200",
        ),
    },
    executable = True,
)
