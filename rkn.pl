#!/usr/bin/perl

# rkn.pl - manipulate list of denied domains from RosKomNadzor
#
# See details at
#   http://eais.rkn.gov.ru/tooperators/ 
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

use strict;
use warnings;

use vars qw($PROGRAM_NAME $VERSION);
$PROGRAM_NAME = "rkn.pl"; $VERSION  = '0.02';

use Getopt::Long qw(:config no_ignore_case bundling);
use XML::LibXML;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;
use POSIX qw(strftime);
use File::Spec::Functions qw(catdir catfile splitpath tmpdir);
use File::Path ();
use Encode ();

# /-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|

my $OPENSSL_CMD = 'openssl';
my $DATA_DIR = catdir(tmpdir(), 'rkn', 'data');
my $SIGNER_CERT_FILE = 'certs.pem';
my $KEY_FILE = 'key.pem';
my $WSDL_URI = 'http://vigruzki.rkn.gov.ru/services/OperatorRequestTest/?wsdl';

my $OPERATOR_NAME = 'test_operator';
my $INN_NUMBER = 123456;
my $OGRN_NUMBER = 5557788;
my $EMAIL_ADDRESS = '';

my $SLEEP_PERIOD = 60;

my %OPTIONS;
my $ENCODING = 'windows-1251';
my $WSDL;
my $FORCE;
my $USE_CODE;
my $VERSION_NUM = 2;

# /-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|

$| = 1;
&check_options();
&process();

# /-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|

sub process() {
    my $filepath = '';

    if ($0 ne '-e') {
        # default perl
        my ($volume, $path, $file) = splitpath $0;
        # TODO: windows support
        $filepath = $path ? $path : '.';
    } else {
        # staticperl uses '-e' as $0
        ...
    }

    my $wsdl_file = catfile($filepath, 'rkn.wsdl');
    my $request_file = catfile($filepath, 'request.xml');
    my $signature_file = catfile($filepath, 'request.bin');

    printf "Using WSDL file: %s\n", $wsdl_file;

    $WSDL = XML::Compile::WSDL11->new( $wsdl_file );
    $WSDL->compileCalls(transport =>
        XML::Compile::Transport::SOAPHTTP
            ->new( address => $WSDL->endPoint() )
    );

    &check_last_dump( \my $stamp );
    printf "Last dump date: %d\n", $stamp;

    if ($FORCE) {
        # retrieve data from server with code stored before
        if ($FORCE == 1) {
            warn "Force mode changes behavior: using code from local store\n";

            my $code = &load_code( $stamp );
            printf "Code number: %s\n", $code;

            &retrieve_result( $stamp, $code );
        } elsif ($FORCE == 2) {
            warn "Force mode changes behavior: sendRequest operation\n";

            if (my $code = &send_request( $request_file, $signature_file )) {
                printf "Received code number: %s\n", $code;
                &save_code( $stamp, $code );
            }
        } elsif ($FORCE == 3) {
            warn "Force mode changes behavior: getResult operation\n";

            my $code;

            if (defined $USE_CODE) {
                $code = $USE_CODE;
            } else {
                $code = &load_code( $stamp );
            }
            
            printf "Using code: %s\n", $code;
            &get_result( $stamp, $code );
        }
    } elsif (not -f catfile($DATA_DIR, $stamp, "result.zip")) {
        # archive file does not exists
        &make_request( $request_file, $signature_file, $stamp );
    } else {
        printf "Up to date: nothing to do\n";
    }

    exit 0;
}

sub check_last_dump {
    my ($date_ref) = @_;

    my $answer = $WSDL->call( 'getLastDumpDate' );
    $$date_ref = $answer->{parameters}{lastDumpDate};
    my $dir = catdir( $DATA_DIR, $$date_ref );

    unless (-e $dir) {
        printf "Creating directory: %s\n", $dir;

        if ($File::Path::VERSION >= 2) {
            &File::Path::make_path( $dir );
        } else {
            &File::Path::mkpath( $dir );
        }
    }

    printf "Result will be stored here: %s\n", $dir;
}

sub create_request_file($) {
    my ($out_file) = @_;

    my $dom = XML::LibXML::Document->new( '1.0', $ENCODING );
    my $request = $dom->createElement( 'request' );
    my $time = $dom->createElement( 'requestTime' );
    my $name = $dom->createElement( 'operatorName' );
    my $inn = $dom->createElement( 'inn' );
    my $ogrn = $dom->createElement( 'ogrn' );
    my $email = $dom->createElement( 'email' );

    $time->appendText( strftime("%Y-%m-%dT%H:%M:%S.000%z", localtime) );
    $name->appendText( $OPERATOR_NAME );
    $inn->appendText( $INN_NUMBER );
    $ogrn->appendText( $OGRN_NUMBER );
    $email->appendText( $EMAIL_ADDRESS );

    $request->addChild( $_ ) for ($time, $name, $inn, $ogrn);
    $request->addChild( $email ) if ($EMAIL_ADDRESS);

    $dom->setDocumentElement( $request );
    $dom->toFile( $out_file, 1 );
}

sub create_signature_file($$) {
    my ($request_file, $signature_file) = @_;

    my $command = join ' ', $OPENSSL_CMD, 'smime', '-sign',
        '-in',      $request_file,
        '-out',     $signature_file,
        '-signer',  $SIGNER_CERT_FILE,
        '-inkey',   $KEY_FILE,
        '-outform', 'DER',
        '-nodetach',
    ;

    printf "Executing command:\n%s\n", $command;

    my $result = qx($command 2>&1);
    my $status = $?;
    my $exit = $status >> 8;
    my $signal = $status & 127;
    my $coredump = $status & 128 ? "with core dump" : "";

    if ($status < 0) {
        # When command not found qx{...} returns '-1'
        printf STDERR "%s: No such file or directory\n", $OPENSSL_CMD;
        $FORCE || exit 1;
    }

    if ($exit or $signal or $coredump) {
        printf STDERR "%s failed%s: exit=%s signal=%s result=%s output:\n\n%s",
            $OPENSSL_CMD,
            $coredump,
            $exit,
            $signal,
            $status,
            $result,
        ;
        $FORCE || exit 1;
    } else {
        printf "Signature file created: %s\n", $signature_file;
        return 1;
    }
}

sub send_request($$) {
    my ($xmlreq_file, $xmlreqsign_file) = @_;

    my $xmlreq = '';
    my $xmlreqsign = '';

    {
        local $/;

        if (open my $req_fh, "<", $xmlreq_file) {
            $xmlreq = <$req_fh>;
            close $req_fh;
        } else {
            printf STDERR "open %s: %s\n", $xmlreq_file, $!;
            $FORCE || exit 1;
        }

        if (open my $sig_fh, "<", $xmlreqsign_file) {
            $xmlreqsign = <$sig_fh>;
            close $sig_fh;
        } else {
            printf STDERR "open %s: %s\n", $xmlreqsign_file, $!;
            $FORCE || exit 1;
        }
    }

    my $answer = $WSDL->call( sendRequest => {
        parameters => {
            requestFile         => $xmlreq,
            signatureFile       => $xmlreqsign,
            dumpFormatVersion   => $VERSION_NUM,
        },
    });

    my $params = $answer->{parameters};

    if ($params->{result}) {
        return $params->{code};
    } else {
        my $error = $params->{resultComment};

        if (&Encode::is_utf8($error)) {
            $error = &Encode::encode_utf8($error);
        }

        printf STDERR "sendRequest: %s\n", $error;
        exit 1;
    }
}

sub load_code($) {
    my ($stamp) = @_;

    my $file = catfile($DATA_DIR, $stamp, 'code.dat');

    if (open my $fh, "<", $file) {
        local $/;

        my $code = <$fh>;
        chomp $code;
        close $fh;
    
        return $code;
    } else {
        printf STDERR "open %s: %s\n", $file, $!;
        exit 1;
    }
}

sub save_code($$) {
    my ($stamp, $code) = @_;

    my $file = catfile($DATA_DIR, $stamp, 'code.dat');

    if (open my $fh, ">", $file) {
        print $fh $code, "\n";
        close $fh;
    } else {
        printf STDERR "open %s: %s\n", $file, $!;
        exit 1;
    }
}

sub get_result($$) {
    my ($stamp, $code) = @_;

    my $answer = $WSDL->call( getResult => {
        parameters => {
            code => $code,
        },
    });

    my $params = $answer->{parameters};

    if ($params->{result}) {
        my $archive_file = catfile($DATA_DIR, $stamp, "result.zip");

        if (open my $fh, ">:raw", $archive_file) {
            syswrite $fh, $params->{registerZipArchive}
                or die sprintf "write %s: %s", $archive_file, $!;
            close $fh;
        }

        return $archive_file;
    } else {
        my $error = $params->{resultComment};

        if (&Encode::is_utf8($error)) {
            $error = &Encode::encode_utf8($error);
        }

        printf STDERR "getResult: %s\n", $error;
        return;
    }
}

sub retrieve_result($$) {
    my ($stamp, $code) = @_;

    printf "Retrieving";

    my $count = 0;
    my $done = 0;
    my $file = '';

    until ($done) {
        if ($count >= 3) {
            print "\b\b\b   \b\b\b";
            $count = 0;
        }

        $count++;

        if ($file = &get_result( $stamp, $code )) {
            $done = 1;
        } else {
            print ".";
            sleep $SLEEP_PERIOD;
        }
    }

    print "\n";
    printf "Completed! Results placed into file: %s\n", $file;
}

sub make_request($$$) {
    my ($request_file, $signature_file, $stamp) = @_;

    &create_request_file( $request_file );
    printf "Request file created: %s\n", $request_file;
    
    &create_signature_file( $request_file, $signature_file );

    if (my $code = &send_request( $request_file, $signature_file )) {
        printf "Received code number: %s\n", $code;
        &save_code( $stamp, $code );
        &retrieve_result( $stamp, $code );
    }
}

sub check_options() {
    my $retval = GetOptions(\%OPTIONS,
        'help|h',
        'version|v',
        'openssl-bin|O=s',
        'data-directory|D=s',
        'signer-certificate|s=s',
        'key-file|k=s',
        'operator-name|n=s',
        'inn-number|i=i',
        'ogrn-numner|o=s',
        'email|e=s',
        'force',
        'force-send-request',
        'force-get-result',
        'with-code=s',
        'sleep-period|P=i',
        'version-num|V=i',
    );

    if (defined $retval and !$retval) {
        # unknown option workaround
        print "use --help for help\n";
        exit 1;
    } elsif (exists $OPTIONS{'help'}) {
        &print_help();
        exit 0;
    } elsif (exists $OPTIONS{'version'}) {
        printf "%s version %s\n", $PROGRAM_NAME, $VERSION;
        exit 0;
    } else {
        $OPERATOR_NAME = $OPTIONS{'operator-name'}
            if defined $OPTIONS{'operator-name'};
        $INN_NUMBER = $OPTIONS{'inn-number'}
            if defined $OPTIONS{'inn-number'};
        $OGRN_NUMBER = $OPTIONS{'ogrn-number'}
            if defined $OPTIONS{'ogrn-number'};
        $EMAIL_ADDRESS = $OPTIONS{'email'}
            if defined $OPTIONS{'email'};
        $KEY_FILE = $OPTIONS{'key-file'}
            if defined $OPTIONS{'key-file'};
        $SIGNER_CERT_FILE = $OPTIONS{'signer-certificate'}
            if defined $OPTIONS{'signer-certificate'};
        $DATA_DIR = $OPTIONS{'data-directory'}
            if defined $OPTIONS{'data-directory'};
        $OPENSSL_CMD = $OPTIONS{'openssl-bin'}
            if defined $OPTIONS{'openssl-bin'};
        $SLEEP_PERIOD = $OPTIONS{'sleep-period'}
            if defined $OPTIONS{'sleep-period'};
        $VERSION_NUM = $OPTIONS{'version-num'}
            if defined $OPTIONS{'version-num'};

        $FORCE = $OPTIONS{'force'};
        $FORCE = 2 if defined $OPTIONS{'force-send-request'};
        $FORCE = 3 if defined $OPTIONS{'force-get-result'};

        $USE_CODE = $OPTIONS{'with-code'}
            if defined $OPTIONS{'with-code'};
    }
}

sub print_help() {
    printf "Allowed options:\n";

    my $h = "  %-32s %-45s\n";

    printf $h,  "-h [--help]", "show this usage information";
    printf $h,  "-v [--version]", "show version information";

    printf $h,  "-s [--signer-certificate] arg",
                "path to signer certificate file";
    printf $h,  "-k [--key-file] arg",
                "path to key file";

    printf $h,  "-n [--operator-name] arg", "operator name";
    printf $h,  "-i [--inn-number] arg", "INN number";
    printf $h,  "-o [--ogrn-number] arg", "OGRN number";
    printf $h,  "-e [--email] arg", "email address";
    printf $h,  "", "- optional";
    
    printf $h,  "-V [--version-num] arg", "versionNum parameter";
    printf $h,  "", "- default is 2";

    printf $h,  "-O [--openssl-bin] arg", 
                "path to openssl command";
    printf $h,  "-D [--data-directory] arg",
                "path to directory where result will be stored";
    printf $h,  "", "- default is TMP_DIR/rkn/data";
    printf $h,  "-P [--sleep-period] arg",
                "sleep period in seconds between getResult attempts";
    printf $h,  "", "- default is 60 seconds";

    printf $h,  "--force", "force mode (skip some critical errors)";
    printf $h,  "--force-send-request", "force sendRequest operation";
    printf $h,  "--force-get-result", "force getResult operation";
    printf $h,  "--with-code arg", "use specified code for getResult operation";
}

