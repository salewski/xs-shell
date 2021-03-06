fn %advise {|name thunk|
	# Insert a thunk at the beginning of a function
	let (f = `` \n {var fn-$name}; c) {
		if {{echo $f|grep -wqv $thunk} && {echo $f|grep -q '{.*}'}} {
			c = `` \n {echo -- $f|sed 's/= ''\(%closure([^)]*)' \
				^'{\)\(.*}''\)$/= ''\1%seq '^$thunk^' {\2}/'}
			if {$c :eq $f} {
				c = `` \n {echo -- $f|sed 's/= ''\({\(|[^|]\+|\)\?' \
					^'%seq \)\(.*}\)/= ''\1'^$thunk^' \3/'}
			}
			if {$c :eq $f} {
				c = `` \n {echo -- $f|sed 's/= ''\({\(|[^|]' \
					^'\+|\)\?\)\(.*}\)/= ''\1 %seq ' \
					^$thunk^' {\3}/'}
			}
			if {$c :eq $f} {
				c = `` \n {echo -- $f|sed 's/= ''\(.*\)''$' \
					^'/= ''{%seq '^$thunk^' {\1}}''/'}
			}
			fn-$name = `` \n {echo -- $c|sed 's/fn-[^ ]\+ = ' \
				^'''\(.\+\)''/\1/'|sed 's/''''/''/g'}
		}
	}
}

fn %unadvise {|name thunk|
	# Remove a thunk from a function.
	let (f = $(fn-$name)) {
		if {{echo $f|grep -wq $thunk} && {echo $f|grep -q '{.*}'}} {
			fn $name `` \n {echo $f|sed 's/'^$thunk^'//'}
		}
	}
}

fn %prewrap {|name|
	# Capture the original function as %_NAME.
	# Use this to wrap a function.
	~ $(fn-%_^$name) () && fn-%_^$name = $(fn-$name)
}

fn %cfn {|test name thunk|
	# When test is true, define function.
	if $test {fn $name $thunk}
}

fn %arglist {|fn-name|
	# Print a function's argument list.
	let ((_ args _) = <={~~ $(fn-$fn-name) *\|*\|*}) {
		~ $args *\^* || echo $args
	}
}

fn %pprint {|fn-name|
	# Prettyprint named function.
	~ $(fn-$fn-name) () && {throw error %pprint 'not a function'}
	printf fn\ %s $fn-name
	let (depth = 1; q = 0; i = 0; lc) {
		let ( \
			fn-wrap = {
				!~ $lc ' ' && printf ' '
				printf %c\n '\'
				for i `{seq `($depth*4)} {printf ' '}
			} \
			) {
			%with-read-chars $(fn-$fn-name) {|c|
				~ $c '''' && {q = `(($q+1)%2)}
				~ $q 0 && switch $c (
				'%'	{~ $i 0 && {wrap; depth = `($depth+1)}}
				'{'	{wrap; depth = `($depth+1)}
				'}'	{depth = `($depth-1)}
				'^'	{wrap}
				)
				i = 1
				printf %c $c
				lc = $c
			}
		}
	}
	printf \n
}

fn %id {|*|
	# Without an arg, return a five-element list:
	#   name version date hash repository-url
	# With an arg, return the index'th item(s).
	let (info = xs <={~~ <=$&version 'xs '*' (git: '*'; '*' @ '*')'}) {
		if {~ $#* 0} {
			result $info
		} else {
			result $info($*)
		}
	}
}

fn %header-doc {|fn-name|
	# Print a function's header documentation.
	# If present, print .d (description),
	# .a (argument) and .i (informational) lines.
	.ensure-libloc
	escape {|fn-quit| let (pass = 0; file = <={%objget $libloc $fn-name}) {
		~ $file () && throw error %header-doc 'not in library'
		(file _) = <={~~ $file *:*}
		%with-read-lines $file {|l|
			if {~ $pass 1} {
				if {~ $l \t\#*} {
					printf %s `` '' {echo $l|cut -c4-}
				} else if {~ $l \t.d* \t.a* \t.i*} {
					printf %s `` '' {echo $l}
				} else if {~ $l \t.c* \t.r* \t.f*} {
					true
				} else {
					echo
					quit
				}
			}
			{~ $l *'fn '$fn-name^* *'%cfn {'*'} '$fn-name^*} \
				&& {pass = 1}
		}
	}}
}
