#!/bin/bash

set -e

projname='counter_test'
ucf='mimas.ucf'
part='xc6slx9-tqg144-2'
spipart='M25P16'
spisize='2048'

XILINX_ISE="${XILINX_ISE:-/opt/Xilinx/14.7/ISE_DS/ISE/bin/lin64}"
[[ ! -x "${XILINX_ISE}/xst" ]] && echo 'Please point $XILINX_ISE to your ISE installation' && exit 1
basedir="$(cd "${0%/*}" && echo ${PWD})"
workdir="${basedir}/work"
mkdir -p "${workdir}"
cd "${workdir}"

build() {
    # Synthesis
    yosys - -L "${projname}_synth.log" << EOF
$(find "${basedir}/src" -iname *.v -printf 'read_verilog "%p"\n')

synth_xilinx -top ${projname} -retime

# Map I/O and clock buffers
select -set clocks */t:FDRE %x:+FDRE[C] */t:FDRE %d
iopadmap -inpad BUFGP O:I @clocks
iopadmap -outpad OBUF I:O -inpad IBUF O:I @clocks %n

write_edif ${projname}.edif
EOF

    # Place and route
    "${XILINX_ISE}/ngdbuild" -uc "${basedir}/${ucf}" -p "${part}" "${projname}.edif" "${projname}.ngd"
    "${XILINX_ISE}/map" -p "${part}" -w -mt 2 -o "${projname}_map.ncd" "${projname}.ngd"
    "${XILINX_ISE}/par" -w -mt 4 "${projname}_map.ncd" "${projname}.ncd"

    # Timing report and bitstream generation
    "${XILINX_ISE}/trce" -v -n -fastpaths "${projname}.ncd" -o "${projname}.twr" "${projname}_map.pcf"
    "${XILINX_ISE}/bitgen" -w -g Binary:Yes -g Compress -g UnusedPin:PullNone "${projname}.ncd"
}

_impact() {
    touch -a "${projname}.mcs"
    cat > "${projname}_impact.cmd" << EOF
setMode -bs
setCable -p usb21 -b 12000000
addDevice -p 1 -file ${projname}.bit
attachFlash -p 1 -spi ${spipart}
assignFileToAttachedFlash -p 1 -file ${projname}.mcs
program -p 1 $@
exit
EOF
    "${XILINX_ISE}/impact" -batch "${projname}_impact.cmd"
}

load() {
    _impact
}

flash() {
    "${XILINX_ISE}/promgen" -u 0000 "${projname}.bit" -s ${spisize} -spi -w -o "${projname}"
    _impact -spionly -e -v -loadfpga
}

[[ -z "$@" ]] && echo 'Please specify one or more of build/load/flash' && exit 1
for action in $@; do
    $action
done
