fn .usage {|*|
	# Display args help for named function.
	if {{~ $#* 1} && {!~ $* -*}} {help $* | grep '^a:'}
}

fn .pu {|*|
	# User ps: [FLAGS] [USER]
	let (flags) {
		while {~ $*(1) -*} {
			~ $*(1) -[fFcyM] && flags = $flags $*(1)
			* = $(2 ...)
		}
		ps -Hlj $flags -U^`{if {~ $#* 0} {echo $USER} else {echo $*}}
	}
}

fn .fbset {|*|
	# Set framebuffer size: x-pixels y-pixels
	if {~ $TERM linux} {fbset -a -g $* $* 32} else {echo 'not a vt'}
}

fn .d {|*|
	# Help tag: docstring
}
fn .a {|*|
	# Help tag: argstring
}
fn .c {|*|
	# Help tag: category
}
fn .r {|*|
	# Help tag: related
}

fn .xsin-rp {
	# Create a random prompt; for use at shell startup only.
	%prompt; rp; _n@$pid = 0
}

fn .web-query {|site path query|
	# Web lookup primitive.
	if {~ $#query 0} {
		web-browser $site
	} else {
		let (q) {
			q = `{echo $^query|sed 's/\+/%2B/g'|tr ' ' +}
			web-browser $site^$path^$q
		}
	}
}

fn .herald {
	# Greetings and salutations.
	let (fn-nl = {printf \n}; fn-isconsole = {~ `tty *tty*}) {
		.as; cookie; .an; nl
		isconsole && {on; nl; net; nl; thermal; battery; load; nl}
		.ab; where; .an
	}
}
