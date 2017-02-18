#!/usr/bin/env perl
#{{ ansible_managed }}

#===============================================================================
# Auteur : pihomecloud
# Date   : 08/11/2015
# But    : Vérification d'une liste de certificats et leur clé correspondante
#===============================================================================
use strict;
use warnings;
use Getopt::Long;
use Date::Parse;
use File::Basename;

my $VERSION = '1.0';

my $certs;
my $index;
my $errorOnly;
my %index;
my $warningDays = 60;
my $criticalDays = 15;
my $summary = "";

my ($ok, $warning, $critical, $unknown, $dependant) = (0,1,2,3,4);
my @statusName = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN', 'DEPENDANT');

my $status = $ok;
my $exitMessage = "";
my $messageSeparator = ",\n";

sub usage {
  my $message = shift;
  print $message."\n" if $message;
  print "Usage : \n";
  print "  cert : certificat à valider (peut être un repertoire *.pem)\n";
  print "  index : index des certificat pour vérifier s'ils ne sont pas révoqués\n";
  print "  warning : seuil de warning\n";
  print "  critical : seuil de warning\n";
  print "  error : n'afficher que les erreurs\n";
  exit $unknown;
}

sub status {
  my $tStatus = shift;
  # ok < warning < critical < unknown < dependant
  $status = $tStatus if $status < $tStatus;
}

sub finalExit {
  my $tStatus = shift;
  my $message = shift;
  $summary = "No certificate with problem" unless $summary;
  status $tStatus if $tStatus;
  $exitMessage = "[".$statusName[$status]."] Check is ".$statusName[$status]." " unless $exitMessage;
  $exitMessage = "[".$statusName[$status]."] $summary$messageSeparator$exitMessage";
  $exitMessage.=$message if $message;
  print $exitMessage."\n";
  exit $status;
}

sub addMessage {
  my $tStatus = shift;
  my $message = join(' ', @_);
  status $tStatus;
  if ($tStatus > $ok or !$errorOnly){
    $summary .= $statusName[$tStatus].":".$message." ";
  }
  $exitMessage .= $messageSeparator if $exitMessage;
  $exitMessage .= "[".$statusName[$tStatus]."] ".$message;
}

GetOptions( 'cert|f=s' => \$certs, 'index|i=s' => \$index, 
            'warning|w=i' => \$warningDays, 'critical|c=i' => \$criticalDays,
            'error|e' => \$errorOnly) or usage;

usage "certificate option is mandatory" unless $certs; 
usage "warning ($warningDays) must be greater or equal critical ($criticalDays)" if $warningDays < $criticalDays; 

if ($index){
  open(my $fh, '<', $index)
  or finalExit $unknown,"Could not open file '$index' $!";
  while (my $row = <$fh>) {
    chomp $row;
    $index{$1} = $2 if $row =~ m/^V\s+\w+\s+(\w+)\s+\w+\s+(.*)/;
  }
}

sub checkCert {
  my $cert = shift;
  my $certName = basename $cert;
  $certName =~ s/\.pem$//;
  $certName =~ s/\.cert$//;
  
  my ($endDate, $serial) = `openssl x509 -enddate -serial -noout -in "$cert"` or finalExit($unknown,"\nunable to get $cert information");
  $endDate =~ s/.*=//;
  chomp $endDate;
  $serial =~ s/.*=//;
  chomp $serial;
  my $timeRemaining = str2time($endDate) - time();
  
  if ($timeRemaining > $warningDays*86400){
    addMessage $ok,"Certificate $certName expires on $endDate > $warningDays days";
  }elsif($timeRemaining < $criticalDays*86400){
    addMessage $critical,"Certificate $certName expires on $endDate < $criticalDays days";
  }else{
    addMessage $warning,"Certificate $certName expires on $endDate < $warningDays days";
  }
  if ($index){
    if($index{$serial}){
      addMessage $ok,"Certificate $certName is Valid : ".$index{$serial};
    }else{
      addMessage $warning,"Certificate $certName is not valid";
    }
  }
}

if (-d $certs){
  opendir(my $dh, $certs) || die "can't opendir $certs: $!";
  while(readdir $dh) {
    checkCert $certs.'/'.$_ if /.cert.pem$/;
  }
}else{
  checkCert $certs;
}

finalExit;
