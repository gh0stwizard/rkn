Keep your WSDL file up-to-date
==============================

```
$ cd rkn/

# working
$ wget -O rkn.wsdl wget -O rkn.wsdl http://vigruzki.rkn.gov.ru/services/OperatorRequest/?wsdl

# test
$ wget -O rkn.wsdl wget -O rkn.wsdl http://vigruzki.rkn.gov.ru/services/OperatorRequestTest/?wsdl
```


Using your certificates
=======================


Place your certificate and keys where is rkn.pl is placed
---------------------------------------------------------


```
$ cd rkn/

$ cp /some/where/rkn-cert.pem ./certs.pem
$ cp /some/where/rkn-key.pem ./key.pem
```


Use command-line options
------------------------

```
$ perl rkn.pl [your options] -s /my/path/to/cert.pem -k /my/key.pem
```


Basic program usage
===========


```
$ perl rkn.pl -n "Operator 1" --inn-number "12345" --ogrn-number "423123"
```

Help
====

```
$ perl rkn.pl --help

Allowed options:
  -h [--help]                      show this usage information
  -v [--version]                   show version information
  -s [--signer-certificate] arg    path to signer certificate file
  -k [--key-file] arg              path to key file
  -n [--operator-name] arg         operator name
  -i [--inn-number] arg            INN number
  -o [--ogrn-number] arg           OGRN number
  -e [--email] arg                 email address
                                   - optional
  -V [--version-num] arg           versionNum parameter
                                   - default is 2
  -O [--openssl-bin] arg           path to openssl command
  -D [--data-directory] arg        path to directory where result will be stored
                                   - default is TMP_DIR/rkn/data
  -P [--sleep-period] arg          sleep period in seconds between getResult attempts
                                   - default is 60 seconds
  --force                          force mode (skip some critical errors)
  --force-send-request             force sendRequest operation
  --force-get-result               force getResult operation
  --with-code arg                  use specified code for getResult operation
```

