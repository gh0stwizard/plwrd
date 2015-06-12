#!/bin/sh

export PERL5LIB=../src/modules
find ../src -regextype posix-extended -regex '.*.(pl|pm)$' | \
xargs -n1 -I'{}' perl -c {} || exit 1
unset PERL5LIB

sh static.sh && strip bin/plwrd && ./bin/plwrd --verbose
