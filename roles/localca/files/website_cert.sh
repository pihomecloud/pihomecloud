#!/bin/bash

[ -z $1 ] && echo useage $0 url_site && exit 1

cd $(dirname $0)

url=$1
/srv/ca/cert.sh server_cert $url
