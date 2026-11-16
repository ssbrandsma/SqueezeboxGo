# shellcheck shell=bash
# lib-safety.sh — shared plan/confirm/refusal helpers for the stock bundle.
#
# Sourced by install.sh / run-jive.sh / restore.sh. Bash + POSIX sh
# compatible. Never performs actions itself; it only prints plans,
# asks for confirmation, and refuses dangerous paths/units.
#
# SPDX-License-Identifier: GPL-2.0-or-later

# plan <line...> — echo what the script is about to do (always called
# before any mutating step).
plan() {
	while [ $# -gt 0 ]; do
		printf '[plan] %s\n' "$1"
		shift
	done
}

# note <line...> — informational output, same channel as plan.
note() {
	while [ $# -gt 0 ]; do
		printf '[note] %s\n' "$1"
		shift
	done
}

# fatal <msg> — refuse and exit nonzero.
fatal() {
	printf '[refuse] %s\n' "$*" >&2
	exit 1
}

# confirm <prompt> — require typed YES unless STOCK_YES=1.
confirm() {
	if [ "${STOCK_YES:-0}" = '1' ]; then
		note "STOCK_YES=1, skipping confirmation: $1"
		return 0
	fi
	printf '[confirm] %s\n' "$1"
	printf '[confirm] Type YES (all caps) to continue, anything else aborts: '
	answer=''
	IFS= read -r answer || true
	[ "$answer" = 'YES' ] || fatal 'aborted by user (confirmation not given)'
}

# refuse_destructive_path <path> — exit 1 unless <path> is an allowed
# bundle location: /opt/squeezebox-stock*, $HOME/*, or one of the
# colon-separated $STOCK_ALLOW_PREFIX extras (host tests use this).
# Refuses: empty, relative, dot-dot, /, and every system prefix.
refuse_destructive_path() {
	p="$1"
	[ -n "$p" ] || fatal 'empty path refused'
	case "$p" in
		/*) ;;
		*) fatal "relative path refused: $p (use an absolute path)" ;;
	esac
	case "$p" in
		# '*' matches empty, so these two cover middle, trailing ('x/../',
		# 'x/..') and root ('/..') dot-dot forms; longer lists are dead.
		*'/../'*|*/..) fatal "dot-dot path refused: $p" ;;
	esac
	# Strip trailing slashes (but keep root detectable).
	while [ "${p%/}" != "$p" ] && [ "$p" != '/' ]; do p="${p%/}"; done
	[ "$p" != '/' ] || fatal 'refusing to operate on /'

	# System prefixes are never bundle locations.
	for sys in /bin /boot /dev /etc /lib /lib32 /lib64 /libx32 \
		/media /mnt /proc /root /run /sbin /snap /srv /sys /usr /var; do
		if [ "$p" = "$sys" ] || case "$p" in "$sys"/*) true ;; *) false ;; esac; then
			fatal "system path refused (bundle lives outside system dirs): $p"
		fi
	done

	# Allowlist.
	if [ "$p" = '/opt/squeezebox-stock' ] \
		|| case "$p" in '/opt/squeezebox-stock-'*) true ;; *) false ;; esac; then
		return 0
	fi
	home="${HOME:-/root}"
	if [ "$p" = "$home" ] || case "$p" in "$home"/*) true ;; *) false ;; esac; then
		# $HOME itself is refused (too broad); anything under it is fine.
		[ "$p" != "$home" ] || fatal "refusing to operate on \$HOME itself: $p"
		return 0
	fi
	extra="${STOCK_ALLOW_PREFIX:-}"
	if [ -n "$extra" ]; then
		old_ifs="$IFS"; IFS=':'
		# shellcheck disable=SC2162
		for prefix in $extra; do
			IFS="$old_ifs"
			[ -n "$prefix" ] || { IFS=':'; continue; }
			if [ "$p" = "$prefix" ] || case "$p" in "$prefix"/*) true ;; *) false ;; esac; then
				IFS="$old_ifs"
				return 0
			fi
			IFS=':'
		done
		IFS="$old_ifs"
	fi
	fatal "path refused (want /opt/squeezebox-stock*, \$HOME/*, or \$STOCK_ALLOW_PREFIX): $p"
}

# refuse_critical_unit <unit> — exit 1 if <unit> is infrastructure that
# must never be stopped (ssh session, init, login, networking, console).
refuse_critical_unit() {
	u="$1"
	[ -n "$u" ] || fatal 'empty unit name refused'
	case "$u" in
		*/*|*' '*|*';'*|*'&'*|*'|'*|*'$'*|*'`'*|*'('*|*')'*)
			fatal "unit name has illegal characters (refusing injection): $u" ;;
	esac
	case "$u" in
		systemd-*|systemd.*|*.slice|*.scope|*.socket|*.path|*.timer|*.mount|*.swap)
			fatal "refusing to manage systemd infrastructure unit: $u" ;;
	esac
	for crit in dbus.service dbus.socket ssh.service sshd.service \
		NetworkManager.service systemd-networkd.service systemd-resolved.service \
		systemd-logind.service systemd-udevd.service \
		getty.target getty@.service serial-getty@.service \
		multi-user.target graphical.target default.target; do
		if [ "$u" = "$crit" ]; then
			fatal "refusing to stop critical unit (console/ssh/net/login): $u"
		fi
	done
	case "$u" in
		getty@*|serial-getty@*) fatal "refusing to stop console unit: $u" ;;
	esac
	case "$u" in
		*.service|*.target) ;;
		*) fatal "refusing non-service/target unit: $u (want something.service)" ;;
	esac
}
