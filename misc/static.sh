#!/bin/sh

APPNAME="plwrd"
STRIP="none" #ppi"
LINKTYPE="static" #allow-dynamic"
BIN_DIR="bin"
RC_FILE=${HOME}/.staticperlrc
SP_FILE=${HOME}/staticperl
BOOT_FILE="../src/main.pl"


if [ -f ${RC_FILE} ]; then
	. ${RC_FILE}
else
	echo "${RC_FILE}: not found"
	exit 1
fi

${SP_FILE} mkapp ${BIN_DIR}/$APPNAME --boot ${BOOT_FILE} \
-Msort.pm \
-Mfeature.pm \
-Mvars \
-Mutf8 \
-Mutf8_heavy.pl \
-MErrno \
-MFcntl \
-MPOSIX \
-MSocket \
-MCarp \
-MEncode \
-Mcommon::sense \
-MEV \
-MGuard \
-MAnyEvent \
-MAnyEvent::Handle \
-MAnyEvent::Socket \
-MAnyEvent::Impl::EV \
-MAnyEvent::Impl::Perl \
-MAnyEvent::Util \
-MAnyEvent::Log \
-MPod::Usage \
-MGetopt::Long \
-MFile::Spec::Functions \
-MJSON::XS \
-MSys::Syslog \
-MFeersum \
-MIO::File \
-MHTTP::Body \
-MMIME::Type::FileName \
-MUnQLite \
-MMath::BigInt \
-MIO::FDPass \
-MProc::FastSpawn \
-MAnyEvent::Fork \
-MAnyEvent::Fork::RPC \
-MAnyEvent::Fork::Pool \
-MData::Dumper \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
--add "../src/modules/Local/DB/UnQLite.pm Local/DB/UnQLite.pm" \
--add "../src/modules/Local/Feersum/Tiny.pm Local/Feersum/Tiny.pm" \
--add "../src/modules/Local/Run.pm Local/Run.pm" \
$@
