#!/bin/sh

APPNAME="plwrd"
STRIP="none"
LINKTYPE="static" # "allow-dynamic"

. ~/.staticperlrc

~/staticperl mkapp bin/$APPNAME --boot ../src/main.pl \
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
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
--add "../src/modules/Local/DB/UnQLite.pm Local/DB/UnQLite.pm" \
--add "../src/modules/Local/Feersum/Tiny.pm Local/Feersum/Tiny.pm" \
--add "../src/modules/Local/Run.pm Local/Run.pm" \
$@
