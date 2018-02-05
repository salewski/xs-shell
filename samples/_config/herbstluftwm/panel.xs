#! /usr/bin/env xs

# Display a panel for herbstluftwm.
#
# The left region contains tag indicators, alert and status indicators, a CPU
# load bar and the title of the focused window. The center region shows info
# for the track being played by mpd. The right region shows a clock.
#
# The alert indicators are:
#   B low battery
#   D high disk utilization
#   F fan failure (temperature rise w/stopped fan)
#   S swapfile in-use
#   T high temperature
#
# The status indicators are:
#   4 an IPv4 connection exists
#   6 an IPv6 connection exists
#   A AC power to mobile device
#   B Bluetooth device connection active
#   C CDMA cellular connection active
#   E Ethernet connection active
#   G GSM cellular connection active
#   M mouse keys active
#   N network connected
#   n network connected to a portal
#   V VPN connection active
#   W WiFi connection active
#   Z screensaver is enabled
#
# Alerts display on the OSD when the panel is concealed by a fullscreen
# window. The battery-critical alert is always displayed on the OSD
# regardless of whether the focused window is fullscreen.
#
# With the exception of the tag and alert indicators, bar content may be
# enabled selectively, whether for cosmetic or functional preference or
# to further reduce the panel's already low CPU load.

# ========================================================================
#                      C O N F I G U R A T I O N

panel_height_px = 22
# Setting the light-off string to a character
# might be desirable with a monospaced font.
_a = ''  # alert light
_s = ''  # status light
panel_font = 'NotoSans-12'         # XLFD or Xft
clockfmt = '%a %Y-%m-%d %H:%M %Z'  # date(1)
trackfmt = '%title%'               # mpc(1)

osd_font = '-*-liberation mono-bold-r-*-*-*-420-*-*-*-*-iso10646-1'  # XLFD
osd_offset_px = 50
osd_dwell_s = 3

battery_low_% = 10
battery_critical_% = 5
disk_full_% = 85
fan_margin_desktop_C = 50
fan_margin_mobile_C = 40
temperature_margin_desktop_C = 25
temperature_margin_mobile_C = 15
swap_usage_% = 5

# Presumed approximately-increasing order of CPU load:
enable_track = true
enable_herbstclient_and_alerts = true  # value ignored; always enabled
enable_clock = true
enable_network_status = true
enable_other_status = true
enable_cpubar = true

# If true, write startup information and main-loop errors to stderr
debug = false

# ========================================================================
#                       A R C H I T E C T U R E

# herbstclient& ----------------------------\  ; async
# clock& -----------------------------------\  ; poll/sleep
# mpc& -------------------------------------\  ; async
# cpu& -------------------------------------\  ; poll/sleep
# alert& -----------------------------------\  ; poll/sleep
#               /--> trigger| lights& ------\  ; poll/sleep
#              /                             ----> fifo| ----\
# netstat& ---/                                ; async        |
# other& ----/                                 ; poll/sleep   |
#   \---+-------> osdmsg| ---> osd& + osd_cat  ; select       v
#      /                                                event-loop | dzen2
# osd-cli-client

# ========================================================================
#             H  E  R  E     B  E     D  R  A  G  O  N  S
#             IOW: Change the following at your own risk.

# Override any extant aliases and check for existence of the binary
fn-dzen2 = <={access -1en dzen2 $path}
fn-dzen2-gcpubar = <={access -1en dzen2-gcpubar $path}
fn-hcitool = <={access -1en hcitool $path}
fn-herbstclient = <={access -1en herbstclient $path}
fn-iconv = <={access -1en iconv $path}
fn-mpc = <={access -1en mpc $path}
fn-nmcli = <={access -1en nmcli $path}
fn-osd_cat = <={access -1en osd_cat $path}
fn-sensors = <={access -1en sensors $path}
fn-xftwidth = <={access -1en xftwidth $path}
fn-xkbset = <={access -1en xkbset $path}
fn-xset = <={access -1en xset $path}

# Get monitor info
monitor = $1
~ $monitor () && monitor = 0
geometry = `{herbstclient monitor_rect $monitor >[2]/dev/null}
~ $geometry () && {throw error panel.sh 'Invalid monitor '^$monitor}
(x y panel_width _) = $geometry

# Define the common part of the temporary file names
tmpfile_base = `{mktemp -u /tmp/panel-XXXXXXXX}

# Define colors and bg/fg pairs
fgcolor = '#efefef'
bgcolor = `{herbstclient get frame_border_normal_color}
selbg = `{herbstclient get window_border_active_color}
selfg = '#101010'
occbg = $bgcolor
occfg = '#ffffff'
unfbg = '#9ca668'
unffg = '#141414'
urgbg = '#ff0675'
urgfg = '#141414'
dflbg = $bgcolor
dflfg = '#ababab'
stsbg = '#002f00'
stsfg = '#00cf00'
alrbg = '#3f0000'
alrfg = '#ff0000'
sepbg = $bgcolor
sepfg = $selbg
cpubar_meter = SkyBlue1
cpubar_background = SkyBlue4

fn attr {|bg fg| printf '^bg(%s)^fg(%s)' $bg $fg}
normal_attr = `{attr $bgcolor $fgcolor}
selected_attr = `{attr $selbg $selfg}
occupied_attr = `{attr $occbg $occfg}
unfocused_attr = `{attr $unfbg $unffg}
urgent_attr = `{attr $urgbg $urgfg}
default_attr = `{attr $dflbg $dflfg}
status_marker_attr = `{attr $stsbg $sepfg}
status_indicator_attr = `{attr $stsbg $stsfg}
alert_marker_attr = `{attr $alrbg $sepfg}
alert_indicator_attr = `{attr $alrbg $alrfg}
separator_attr = `{attr $sepbg $sepfg}

dzen2_opts = -w $panel_width -x $x -y $y -h $panel_height_px \
	-ta l -bg $bgcolor -fg $fgcolor -fn $panel_font

dzen2_gcpubar_opts = -h `($panel_height_px/2) \
	-fg $cpubar_meter -bg $cpubar_background \
	-i 0.7

osd_cat_opts = -f $osd_font \
	-i `($x+$osd_offset_px) -o `($y+$osd_offset_px+$panel_height_px) \
	-s 5 -c $alrfg -d $osd_dwell_s

# Uncomment these two utility functions if they're not in your library
#fn %argify {|*|
#        # Always return a one-element list.
#        if {~ $* ()} {result ''} else {result `` '' {echo -n $*}}
#}
#
#fn %with-read-lines {|file body|
#        # Run body with each line from file.
#        # Body must be a lambda; its argument is bound to the line content.
#        <$file let (__l = <=read) {
#                while {!~ $__l ()} {
#                        $body $__l
#                        __l = <=read
#                }
#        }
#}

# Define a logger, enabled by the debug variable
fn logger {|fmt args| if $debug {printf 'PANEL: '^$fmt^\n $args >[1=2]}}

# Carve out space for the panel
herbstclient pad $monitor $panel_height_px

# Create the status-lights trigger fifo
trigger = $tmpfile_base^-trigger-^$monitor
mkfifo $trigger

# Create the display event fifo
fifo = $tmpfile_base^-fifo-^$monitor
mkfifo $fifo

# Create the OSD fifo
osdmsg = $tmpfile_base^-osd-^$monitor
mkfifo $osdmsg

# Initialize task management
taskpids =
fn rt {|*| taskpids = $taskpids $* $apid}

# Send window manager events
herbstclient --idle >$fifo &
rt herbstclient

# Send clock events
if $enable_clock {
	while true {
		n = <={%argify `{date +^$clockfmt}}
		!~ $l $n && {printf 'clock'\t'%s'\n $n}
		l = $n
		sleep 1
	} >$fifo &
	rt clock
}

# Send player events
if $enable_track {
	mpc idleloop >$fifo &
	rt mpc
}

# Send CPU bar events
if $enable_cpubar {
	%with-read-lines <{dzen2-gcpubar $dzen2_gcpubar_opts} {|*|
		echo cpubar\t$* >$fifo
	} &
	rt cpu
}

# Start the OSD
<$osdmsg while true {
	osd_cat $osd_cat_opts
	sleep 1
} &
rt osd
fn osd {|msg| echo $msg >$osdmsg}

# If the panel is covered, use the OSD for alerts
fn alert_if_fullscreen {|fmt args|
	~ `{herbstclient attr clients.focus.fullscreen} true && {
		osd `{printf $fmt $args}
	}
}

# Send alert events
fn battery () {
	BAT = /sys/class/power_supply/BAT
	AC = /sys/class/power_supply/AC
	LOW = $battery_low_%
	CRITICAL = $battery_critical_%
	let (w = false; cap = 0; chg = 0; v) {
		if {{access -d $AC} && {~ `{cat $AC/online} 1}} {
			# We're on line power at the moment
		} else if {access -d $BAT^0} {
			for d $BAT? {
				if {~ `{cat $d/present} 1} {
					v = `{cat $d/energy_full}
					cap = `($cap+$v)
					v = `{cat $d/energy_now}
					chg = `($chg+$v)
				}
			}
			if {!~ $cap 0} {
				v = `(100.0*$chg/$cap)
				if {$v :le $LOW} {w = true}
			}
		}
		if {$v :le $CRITICAL} {osd 'Battery charge is critically low'}
		$w && {alert_if_fullscreen 'Battery charge < %d%%' $LOW}
		result $w
	}
}

fn disk () {
	THRPCT = $disk_full_%
	VOLUMES = / /boot /home /run /tmp /var
	utilizations = `{df | less -n +2 | grep -w '-e'^$VOLUMES | tr -d % \
		| awk '{ print $5 "\t" $6 }'}
	let (w = false) {
		while {!~ $utilizations ()} {
			(occ name) = $utilizations(1 2)
			utilizations = $utilizations(3 ...)
			{$occ :ge $THRPCT} && {w = true}
		}
		$w && {alert_if_fullscreen 'Disk > %d%% full' $THRPCT}
		result $w
	}
}

HIGH = `{sensors|grep Package\\\|Physical|cut -d= -f2|cut -d\. -f1}
CHASSIS = `{cat /sys/devices/virtual/dmi/id/chassis_type}
fn get_setpoint {|margin_desktop_C margin_mobile_C|
	if {~ $CHASSIS ()} {
		result `($HIGH - $margin_desktop_C)
	} else if {{$CHASSIS :lt 8} || {$CHASSIS :gt 16}} {
		result `($HIGH - $margin_desktop_C)
	} else {
		result `($HIGH - $margin_mobile_C)
	}
}
TEMPERATURE_THRESHOLD = <={get_setpoint \
	$temperature_margin_desktop_C $temperature_margin_mobile_C}
FAN_THRESHOLD = <={get_setpoint $fan_margin_desktop_C $fan_margin_mobile_C}

fn get_curtemp {
	result `{sensors|grep Package\\\|Physical \
			|cut -d: -f2|cut -d\. -f1|tr -d ' +'}
}

fn fan () {
	temp = <=get_curtemp
	speeds = `{sensors|grep fan|cut -d: -f2|awk '{print $1}'}
	speed = 0; for s $speeds {speed = `($speed+$s)}
	if {{$temp :gt $FAN_THRESHOLD} && {~ $speed 0}} {
		cycles = `($cycles+1)
		{$cycles :gt 1} && {
			alert_if_fullscreen 'Fan is stopped at %dC' \
				$FAN_THRESHOLD
			result true
		}
	} else {
		cycles = 0
		result false
	}
}

fn swap () {
	THRPCT = $swap_usage_%
	swapping = `{
tail -n +2 /proc/swaps | awk '
BEGIN { tot = 0; use = 0 }
{ tot += $3; use += $4; }
END { print ((use * 100 / tot) > '^$THRPCT^') }
'
	}
	if {~ $swapping 1} {
		alert_if_fullscreen 'Swapfile > %d%% full' $THRPCT
		result true
	} else {result false}
}

fn temperature () {
	temp = <=get_curtemp
	if {$temp :gt $TEMPERATURE_THRESHOLD} {
		alert_if_fullscreen 'Temperature > %dC' $TEMPERATURE_THRESHOLD
		result true
	} else {result false}
}

while true {
	if <=battery {b = B} else {b = $_a}
	if <=disk {d = D} else {d = $_a}
	if <=fan {f = F} else {f = $_a}
	if <=swap {s = S} else {s = $_a}
	if <=temperature {t = T} else {t = $_a}
	echo alert\t$b$d$f$s$t
	sleep 10
} >$fifo &
rt alert

# Send status events
let (i4 = $_s; i6 = $_s; a = $_s; b = $_s; c = $_s; e = $_s; \
	g = $_s; m = $_s; n = $_s; v = $_s; w = $_s; z = $_s) {

	fn post_status_event {
		echo status\t$i4$i6$a$b$c$e$g$m$n$v$w$z >$fifo
	}

	fn update_network_status_lights {
		c = $_s; e = $_s; g = $_s; v = $_s; w = $_s
		i4 = $_s; i6 = $_s; n = $_s
		let (net_type; dev) {
			%with-read-lines <{nmcli -t connection show --active \
						|cut -d: -f3,4} {|net_info|
				(net_type dev) = <={~~ $net_info *:*}
				switch $net_type (
				'cdma' {c = C}
				'802-3-ethernet' {e = E}
				'gsm' {g = G}
				'vpn' {v = V}
				'802-11-wireless' {w = W}
				{}
				)
				if {nmcli -t device show $dev \
					| grep -q '^IP4\.GATEWAY:.\+$' } \
					{i4 = 4}
				if {nmcli -t device show $dev \
					| grep -q '^IP6\.GATEWAY:.\+$' } \
					{i6 = 6}
			}
		}
		switch `{nmcli --colors no networking connectivity} (
		'portal' {n = n}
		'full' {n = N}
		{}
		)
		post_status_event
	}

	fn update_other_status_lights {
		AC_online = /sys/class/power_supply/AC/online
		access -f $AC_online && {
			if {~ `{cat $AC_online} 1} \
				{a = A} else {a = $_s}
		}
		if {hcitool con|grep -qv Connections:} \
			{b = B} else {b = $_s}
		if {xkbset q|grep -q '^Mouse-Keys = On'} \
			{m = M} else {m = $_s}
		if {!~ `{xset q|grep timeout|awk '{print $2}'} 0} \
			{z = Z} else {z = $_s}
		post_status_event
	}

	<$trigger while true {
		switch <=read (
		network {update_network_status_lights}
		other {update_other_status_lights}
		{}
		)
		sleep 1
	} &
}
rt lights

if $enable_network_status {
	{
		sleep 1
		echo network >$trigger
		sleep 1
		nmcli monitor|while true {read; echo network >$trigger}
	} &
	rt netstat
}

if $enable_other_status {
	while true {
		echo other >$trigger
		sleep 3
	} &
	rt other
}

# Draw the three panel regions
fn drawtags {
	for t `{herbstclient tag_status $monitor} {
		let ((f n) = `{cut --output-delimiter=' ' -c1,2- <<<$t}) {
			switch $f (
			'#' {printf $selected_attr}
			'+' {printf $unfocused_attr}
			':' {printf $occupied_attr}
			'!' {printf $urgent_attr}
			{printf $default_attr}
			)
			printf \ %s\n $n
		}
	}
	printf $normal_attr
}

fn drawcenter {|text|
	let (t = <={%argify $text}) {
		let (w = `{xftwidth $panel_font $t}) {
			printf '^p(_CENTER)^p(-%d)%s%s'\n \
				`($w/2) $default_attr $t
		}
	}
}

fn drawright {|text|
	let (w = `{xftwidth $panel_font <={%argify \
				`{sed 's/\^..([^)]*)//g' <<<$text}}}; \
		t = <={%argify $text}; pad = 10) {
			printf '^p(_RIGHT)^p(-%d)%s'\n `($w+$pad) $t
	}
}

# Kill prior incarnation's processes and fifos that avoided assassination
taskfile = /tmp/panel-^$monitor^-tasks
for (task pid) `{access -f $taskfile && cat $taskfile} {
	if {kill -0 $pid >[2]/dev/null} {
		logger 'cleanup pgroup %d (%s)' $pid $task
		pkill -g $pid
	}
}
echo $taskpids >$taskfile
fifofile = /tmp/panel-^$monitor^-fifos
for fifo `{access -f $fifofile && cat $fifofile} {
	if {access $fifo} {
		logger 'cleanup fifo %s' $fifo
		rm -f $fifo
	}
}
echo $fifo $trigger $osdmsg >$fifofile

# Process events
fn terminate {
	rm -f $fifo
	rm -f $trigger
	rm -f $osdmsg
	for (task pid) $taskpids {
		logger 'killing pgroup %d (%s)' $pid $task
		pkill -g $pid
	}
	exit
}

fn lights {|alert status|
	if {$enable_network_status || $enable_other_status} {
		printf '%s«%s%s%s»%s«%s%s%s»%s'\n \
			$alert_marker_attr \
			$alert_indicator_attr $alert $alert_marker_attr \
			$status_marker_attr \
			$status_indicator_attr $status $status_marker_attr \
			$normal_attr
	} else {
		printf '%s«%s%s%s»%s'\n \
			$alert_marker_attr \
			$alert_indicator_attr $alert $alert_marker_attr \
			$normal_attr
	}
}

fn title {herbstclient attr clients.focus.title >[2]/dev/null}

fn track {
	let (info = `` '' {/usr/bin/mpc -f $trackfmt}) {
		if {grep -qwF '[paused]' <<<$info} {
			echo
		} else {
			head -1 <<<$info|iconv -tlatin1//translit
		}
	}
}

logger 'starting: %s; %s; %s' \
	<={%argify `{var enable_network_status}} \
	<={%argify `{var enable_other_status}} \
	<={%argify `{var enable_cpubar}}

let (tags; sep; title; track; lights; at = ''; st = ''; cpubar; clock) {
	tags = `` \n {drawtags}
	sep = $separator_attr^'|'
	title = `title
	track = `{drawcenter `{track}}
	lights = `{lights $at $st}
	<$fifo while true {
		let ((ev p1 p2) = <={%split \t <=read}) {
			switch $ev (
				tag_changed {tags = `` \n {drawtags}}
				tag_flags {tags = `` \n {drawtags}; \
						title = `title}
				focus_changed {title = $p2}
				window_title_changed {title = $p2}
				player {track = `{track}}
				alert {at = <={%argify $p1}; \
					lights = `{lights $at $st}}
				status {st = <={%argify $p1}; \
					lights = `{lights $at $st}}
				cpubar {cpubar = $p1}
				clock {clock = $p1}
				quit_panel {terminate}
				reload {terminate}
				{}
			)
			echo $tags ' '$lights $cpubar $sep $title \
				`{if $enable_track {drawcenter $track}} \
				`{if $enable_clock {drawright $clock}}
		}
	} | dzen2 $dzen2_opts
} |[2] {if $debug {cat >>/dev/stderr}}