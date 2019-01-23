dnl usage: m4 -DDB=<DB>
#!/bin/sh
PATH=$PATH:/usr/local/sbin:/usr/local/bin
sqlite3 DB \
	"delete from envelopes where created < datetime('now', '-30 days');"
