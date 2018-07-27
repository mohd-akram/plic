.POSIX:

SITE = plic.ml
PORT = 8080
ACMEDIR = /usr/local/www/acme

name = plic
version = `git describe --tags | cut -c 2- | cut -f -2 -d - | sed 's/-/./'`
license = MIT
homepage = https://$(SITE)
dependencies = nginx sqlite3
service_command = $(sbindir)/$(name)
service_args = --port $(PORT) --db $(pkgdbdir)/data.db

prefix = /usr/local
sbindir = $(prefix)/sbin
sysconfdir = $(prefix)/etc
localstatedir = $(prefix)/var
pkgdbdir = $(localstatedir)/db/$(name)
nginx_confsubdir = $(sysconfdir)/nginx/conf.d

nginx_conf = etc/nginx/site.conf
rcd = etc/rc.d/service

all: bin/plic $(nginx_conf) $(rcd)

bin/plic: src/plic.cr
	shards build --release --no-debug

$(nginx_conf): $(nginx_conf).m4
	m4 -DSITE=$(SITE) -DPORT=$(PORT) -DACMEDIR=$(ACMEDIR) \
		$(nginx_conf).m4 > $@

$(rcd): $(rcd).m4
	m4 -DNAME=$(name) -DCOMMAND=$(service_command) \
		-DARGS="$(service_args)" $(rcd).m4 > $@

install: all
	install -d $(DESTDIR)$(sbindir)
	install -s bin/plic $(DESTDIR)$(sbindir)
	install -d $(DESTDIR)$(nginx_confsubdir)
	install $(nginx_conf) $(DESTDIR)$(nginx_confsubdir)/$(SITE).conf
	install -d $(DESTDIR)$(pkgdbdir)

install-freebsd:
	$(MAKE) localstatedir=/var install
	install -d $(DESTDIR)$(sysconfdir)/rc.d
	install $(rcd) $(DESTDIR)$(sysconfdir)/rc.d/$(name)
