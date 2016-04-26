#!/bin/bash

[ -z $1 ] && echo useage $0 extensions cn [mail]&& exit 1

cd $(dirname $0)

i=0
extensions="$1"
cn="$2"
mail=""
[ ! -z "$3" ] && mail="$3"
csr=intermediate/csr/$cn.csr
key=intermediate/private/$cn.key
cert=intermediate/certs/$cn.cert.pem
sslConf=intermediate/openssl.cnf
days=375
caFile=intermediate/certs/ca-chain.cert.pem


[ -e $cert ] && echo "Please revoke cert before creating a new one : 
openssl ca -config intermediate/openssl.cnf -revoke $cert
rm $cert" && exit

echo "Appuyer sur Entree pour la generation du certificat pour $cn ($extensions) $mail"
read toto

sed -i "s/commonName_default              =.*/commonName_default              = $cn/" $sslConf
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))
sed -i "s/emailAddress_default            =.*/emailAddress_default            = $mail/" $sslConf
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

openssl genrsa -aes256 -out "$key" 2048
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))
chmod 400 "$key"
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))
openssl req -config $sslConf \
      -key "$key" \
      -new -sha256 -out "$csr"
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

openssl ca -config $sslConf \
      -extensions $extensions -days $days -notext -md sha256 \
      -in "$csr" \
      -out "$cert"
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

chmod 440  "$cert"
chgrp sslread "$cert"
chgrp sslread "$key"
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

openssl x509 -noout -text -in "$cert"
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

if [ "$extensions" = "server_cert" ]
then
  openssl rsa -in "$key" -out "$key.nopass"
  [ $? -ne 0 ] && echo "Problème $i : exit" && exit
  i=$(($i+1))
  
  chmod 400 "$key.nopass"
  [ $? -ne 0 ] && echo "Problème $i : exit" && exit
  i=$(($i+1))
  key="$key.nopass"
elif [ "$extensions" = "usr_cert" ]
then
  openssl pkcs12 -export -out "$pks" -inkey "$key" -in "$cert"
  [ $? -ne 0 ] && echo "Problème $i : exit" && exit
  i=$(($i+1))
  chmod 440  "$pks"
  chgrp sslread "$pks"
fi

openssl verify -CAfile $caFile "$cert" 
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

[ $((openssl x509 -noout -modulus -in "$cert" | openssl md5 ;   openssl rsa -noout -modulus -in "$key" | openssl md5) | uniq | wc -l) -eq 1 ] && echo "la clé $key et le certificat $cert correspondent" || echo 'KO pas de corespondance entre cle et certificat !!!!'
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

sed -i "s/commonName_default              = .*/commonName_default              = /" $sslConf
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

sed -i "s/emailAddress_default            =.*/emailAddress_default            = /" $sslConf
[ $? -ne 0 ] && echo "Problème $i : exit" && exit
i=$(($i+1))

