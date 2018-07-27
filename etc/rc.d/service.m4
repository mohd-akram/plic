dnl usage: m4 -DNAME=<NAME> -DCOMMAND=<COMMAND> -DARGS=<ARGS>
#!/bin/sh

# PROVIDE: NAME
# REQUIRE: LOGIN
# KEYWORD: shutdown

. /etc/rc.subr

name=NAME

load_rc_config $name
: ${NAME`'_user:=NAME}
: ${NAME`'_prepend:="/usr/sbin/daemon -f"}

command="COMMAND"
command_args="ARGS"

run_rc_command "$1"
