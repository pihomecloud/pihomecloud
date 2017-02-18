#!/bin/bash
#{{ ansible_managed }}
#From https://github.com/igustin/packt

# Packt daily free e-book claim & download

source "$(dirname $0)/packt.cfg"

function log {
    echo "$(date '+%d.%m.%Y. %H:%M:%S') $1" >> "$log"
}

# initial clean up
log "*** Packt started ***"
rm -f $cookie packt*.html

[ ! -d $dldir ]  && dldir=$(dirname $0)/ebooks

# login
log "Packt web login"

# web login
curl -s --retry $rtry -m $tout -A "$agent" -b "$cookie" -c "$cookie" -d "email=$userid" -d "password=$pwd" -d "op=Login" -d "form_build_id=form-73ba86bbfb2a50719049129632c84810 " -d "form_token=2f1d586bf7df196b77d0761709d03199" -d "form_id=packt_user_login_form" https://www.packtpub.com
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }
log "[OK] logged in"

# daily free e-book
curl -s --retry $rtry -m $tout -A "$agent" -b "$cookie" -c "$cookie" https://www.packtpub.com/packt/offers/free-learning > packt_daily.html
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }

title=$(grep "dotd-title" -A 2 packt_daily.html | tail -1 | sed 's/^[^0-9A-Za-z]*//;s/[\t ]*<\/h2>$//')
log "[OK] Today's free e-book: $title"

# claim
claim=$(grep -oE "freelearning-claim/[0-9]+/[0-9]+" packt_daily.html)
curl -s --retry $rtry -m $tout -A "$agent" -b "$cookie" -c "$cookie" -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' -H 'Accept-Encoding: gzip, deflate' -H 'Accept-Language: en-US,en;q=0.5' -H 'Connection: keep-alive' -H 'Host: www.packtpub.com' -H 'Referer: https://www.packtpub.com/packt/offers/free-learning' "https://www.packtpub.com/$claim"
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }
log "[OK] e-Book claimed"

# download link
book=$(echo $claim | sed 's/.*\/\([0-9]*\)\/.*/\1/')

# PDF download
curl -s -L --retry $rtry -A "$agent" -b "$cookie" -c "$cookie" "https://www.packtpub.com/ebook_download/$book/pdf" > "$dldir/$title.pdf"
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }
log "[OK] PDF downloaded $dldir/$title.pdf"

# Mobi download
curl -s -L --retry $rtry -A "$agent" -b "$cookie" -c "$cookie" "https://www.packtpub.com/ebook_download/$book/mobi" > "$dldir/$title.mobi"
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }
log "[OK] Mobi downloaded $dldir/$title.mobi"

# Packt logout
curl -s --retry $rtry -m $tout -A "$agent" -b "$cookie" -c "$cookie" https://www.packtpub.com/logout > packt_logout.html
cex=$?; test "$cex" -ne "0" && { log "[KO] curl exit error code: $cex"; exit; }
log "[OK] Packt logout"

rm -f $cookie packt*.html

log "[OK] books fethed under $dldir/"
# end
