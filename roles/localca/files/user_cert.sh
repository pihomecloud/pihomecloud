#!/bin/bash

[ -z $2 ] && echo useage $0 cn mail && exit 1

cd $(dirname $0)

cn=$1
mail=$2
/srv/ca/cert.sh usr_cert "$cn" "$mail"
