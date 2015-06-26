#!/bin/sh

export PERL5LIB=../src/modules

APP_PATH="bin/plwrd"
PERL="perl"

find ../src -regextype posix-extended -regex '.*.(pl|pm)$' | \
  xargs -n1 -I'{}' ${PERL} -c {} \
|| exit 1

sh static.sh && strip ${APP_PATH} && ./${APP_PATH} --verbose
